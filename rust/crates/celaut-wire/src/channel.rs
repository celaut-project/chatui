//! A TCP and TLS 1.3 connection to a node, checked with [`IdentityVerifier`], and the
//! tonic channel on it.

use std::sync::Arc;
use std::time::Duration;

use bee_rpc::frame::{ParseOptions, Part};
use celaut_net::BoxStream;
use hyper_util::rt::TokioIo;
use rustls::pki_types::ServerName;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;
use tonic::codegen::http::Uri;
use tonic::transport::{Channel, Endpoint};

use crate::identity::{IdentityVerifier, TLS_SERVER_NAME};
use crate::{Transport, WireError};

/// Options of [`Connection::connect`].
#[derive(Clone, Debug)]
pub struct ConnectOptions {
    /// The `peer_id` that the node must prove. `None` for a first contact: then the
    /// certificate gives the `peer_id`, and the caller learns it.
    pub expected_peer_id: Option<String>,
    /// A limit for the TCP connection, the TLS handshake and the HTTP/2 setup.
    pub connect_timeout: Duration,
    /// A limit for each call.
    pub call_timeout: Duration,
}

impl Default for ConnectOptions {
    fn default() -> Self {
        ConnectOptions {
            expected_peer_id: None,
            connect_timeout: Duration::from_secs(10),
            call_timeout: Duration::from_secs(30),
        }
    }
}

/// The TLS client settings of a node: TLS 1.3, ALPN `h2`, no client certificate, the
/// certificate checked by `verifier`.
pub fn tls_config(verifier: Arc<IdentityVerifier>) -> Result<rustls::ClientConfig, WireError> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let mut config = rustls::ClientConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(|e| WireError::Connect(format!("TLS setup: {e}")))?
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth();
    config.alpn_protocols = vec![b"h2".to_vec()];
    Ok(config)
}

/// A verifier for `expected`, with the algorithms of the ring provider.
pub fn new_verifier(expected: Option<String>) -> Arc<IdentityVerifier> {
    let provider = rustls::crypto::ring::default_provider();
    IdentityVerifier::new(expected, provider.signature_verification_algorithms)
}

/// The TCP connection goes by the route of the app (`celaut_net`): direct, through a
/// SOCKS5 proxy (Tor), or not at all. The TLS handshake and the identity check are the
/// same on each route, so the node proves its identity through a proxy too.
async fn tls_handshake(
    connector: &TlsConnector,
    host: &str,
    port: u16,
) -> Result<TlsStream<BoxStream>, std::io::Error> {
    let tcp = celaut_net::connect(host, port).await?;
    // The name is the same for every node and is not checked (see the verifier).
    let name = ServerName::try_from(TLS_SERVER_NAME)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;
    connector.connect(name, tcp).await
}

/// Open the TLS connection to `host:port` and check the node. Gives the stream and the
/// `peer_id`. This is [`Connection::connect`] without HTTP/2.
pub async fn tls_connect(
    host: &str,
    port: u16,
    options: &ConnectOptions,
) -> Result<(TlsStream<BoxStream>, String), WireError> {
    let verifier = new_verifier(options.expected_peer_id.clone());
    let connector = TlsConnector::from(Arc::new(tls_config(verifier.clone())?));
    let result = tokio::time::timeout(
        options.connect_timeout,
        tls_handshake(&connector, host, port),
    )
    .await;
    match result {
        Err(_) => Err(WireError::Timeout),
        Ok(Err(e)) => Err(refusal_or(&verifier, describe(&e))),
        Ok(Ok(stream)) => match verifier.peer_id() {
            Some(peer_id) => Ok((stream, peer_id)),
            None => Err(WireError::Connect(
                "the TLS handshake gave no identity".to_string(),
            )),
        },
    }
}

/// The Buffers of a raw response as a stream, one at a time.
fn futures_unfold(response: bee_rpc::grpc::RawResponse) -> crate::transport::Buffers {
    let stream = tokio_stream::wrappers::ReceiverStream::new({
        let (tx, rx) = tokio::sync::mpsc::channel(1);
        tokio::spawn(async move {
            let mut response = response;
            loop {
                let item = match response.next().await {
                    Ok(Some(buffer)) => Ok(buffer),
                    Ok(None) => return,
                    Err(e) => Err(wire_error(e)),
                };
                let stop = item.is_err();
                if tx.send(item).await.is_err() || stop {
                    return;
                }
            }
        });
        rx
    });
    Box::pin(stream)
}

/// [`futures_unfold`] for a call with `block_skip`: the task that owns the response also
/// forwards the skip requests of the reader, before it reads each Buffer. Gives the stream
/// and the function that queues a request.
fn futures_unfold_skippable(
    response: bee_rpc::grpc::RawResponse,
) -> (crate::transport::Buffers, crate::transport::Skipper) {
    use std::sync::{Arc, Mutex, PoisonError};
    let queue: Arc<Mutex<Vec<Vec<u8>>>> = Arc::new(Mutex::new(Vec::new()));
    let (tx, rx) = tokio::sync::mpsc::channel(1);
    let requests = queue.clone();
    tokio::spawn(async move {
        let mut response = response;
        loop {
            let asked: Vec<Vec<u8>> =
                std::mem::take(&mut *requests.lock().unwrap_or_else(PoisonError::into_inner));
            for id in asked {
                response.request_skip(&id);
            }
            let item = match response.next().await {
                Ok(Some(buffer)) => Ok(buffer),
                Ok(None) => return,
                Err(e) => Err(wire_error(e)),
            };
            let stop = item.is_err();
            if tx.send(item).await.is_err() || stop {
                return;
            }
        }
    });
    let skipper: crate::transport::Skipper = Arc::new(move |id: &[u8]| {
        if id.is_empty() {
            return false;
        }
        queue
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .push(id.to_vec());
        true
    });
    (
        Box::pin(tokio_stream::wrappers::ReceiverStream::new(rx)),
        skipper,
    )
}

/// The text of an error and its sources.
fn describe(error: &dyn std::error::Error) -> String {
    let mut text = error.to_string();
    let mut source = error.source();
    while let Some(inner) = source {
        let part = inner.to_string();
        if !text.contains(&part) {
            text.push_str(": ");
            text.push_str(&part);
        }
        source = inner.source();
    }
    text
}

/// The identity error that the verifier saw, if any. Else a connection error.
fn refusal_or(verifier: &IdentityVerifier, text: String) -> WireError {
    match verifier.take_refusal() {
        Some(e) => WireError::Identity(e),
        None => WireError::Connect(text),
    }
}

/// A checked gRPC channel to one node.
#[derive(Clone, Debug)]
pub struct Connection {
    channel: Channel,
    peer_id: String,
    call_timeout: Duration,
}

impl Connection {
    /// Connect to `host:port` (a name or an IP literal, with no brackets).
    pub async fn connect(
        host: &str,
        port: u16,
        options: ConnectOptions,
    ) -> Result<Connection, WireError> {
        let verifier = new_verifier(options.expected_peer_id.clone());
        let connector = TlsConnector::from(Arc::new(tls_config(verifier.clone())?));
        let host_owned = host.to_string();
        let service = tower::service_fn(move |_uri: Uri| {
            let connector = connector.clone();
            let host = host_owned.clone();
            async move {
                tls_handshake(&connector, &host, port)
                    .await
                    .map(TokioIo::new)
            }
        });
        // The URI is not used to connect. The service above does it.
        let endpoint = Endpoint::from_static("http://celaut-node");
        let result = tokio::time::timeout(
            options.connect_timeout,
            endpoint.connect_with_connector(service),
        )
        .await;
        let channel = match result {
            Err(_) => return Err(WireError::Timeout),
            Ok(Err(e)) => return Err(refusal_or(&verifier, describe(&e))),
            Ok(Ok(channel)) => channel,
        };
        let peer_id = verifier
            .peer_id()
            .ok_or_else(|| WireError::Connect("the TLS handshake gave no identity".to_string()))?;
        Ok(Connection {
            channel,
            peer_id,
            call_timeout: options.call_timeout,
        })
    }

    /// The `peer_id` that the certificate of the node proved.
    pub fn peer_id(&self) -> &str {
        &self.peer_id
    }
}

impl Connection {
    async fn bee_call(
        &self,
        method: &str,
        parts: Vec<Part>,
        accepted: &[i32],
        timeout: Duration,
    ) -> Result<Vec<Part>, WireError> {
        let options = bee_rpc::grpc::CallOptions {
            parse: ParseOptions::accepting(accepted.iter().copied()),
            block_skip: false,
            timeout: Some(timeout),
        };
        let path = format!("/celaut.Gateway/{method}");
        bee_rpc::grpc::call(self.channel.clone(), &path, parts, options)
            .await
            .map_err(wire_error)
    }

    /// The tonic channel, for the calls that are not one request and one answer
    /// (`ServiceTunnel`).
    pub(crate) fn channel(&self) -> Channel {
        self.channel.clone()
    }
}

/// The error of a bee-rpc call, as a wire error.
fn wire_error(e: bee_rpc::Error) -> WireError {
    match e {
        bee_rpc::Error::Transport(t) if t == "deadline exceeded" => WireError::Timeout,
        other => WireError::Call(other.to_string()),
    }
}

/// An error of the input of a relay, carried through bee-rpc and back.
const INPUT_ERROR: &str = "the input of the relay failed: ";

impl Transport for Connection {
    async fn call_buffers(
        &self,
        method: &str,
        input: crate::transport::Buffers,
        accepted: &[i32],
        timeout: Duration,
    ) -> Result<Vec<Part>, WireError> {
        use tokio_stream::StreamExt;
        let options = bee_rpc::grpc::CallOptions {
            parse: ParseOptions::accepting(accepted.iter().copied()),
            block_skip: false,
            timeout: Some(timeout),
        };
        let path = format!("/celaut.Gateway/{method}");
        // A wire error of the input goes through bee-rpc as an I/O error, and comes back.
        let input = input.map(|item| {
            item.map_err(|e| {
                let text = match e {
                    WireError::Relay(text) => text,
                    other => other.to_string(),
                };
                bee_rpc::Error::Io(std::io::Error::other(format!("{INPUT_ERROR}{text}")))
            })
        });
        bee_rpc::grpc::call_buffers(self.channel.clone(), &path, Box::pin(input), options)
            .await
            .map_err(|e| match e {
                bee_rpc::Error::Io(io) if io.to_string().starts_with(INPUT_ERROR) => {
                    WireError::Relay(io.to_string()[INPUT_ERROR.len()..].to_string())
                }
                other => wire_error(other),
            })
    }

    async fn call_raw(
        &self,
        method: &str,
        parts: Vec<Part>,
        timeout: Duration,
    ) -> Result<crate::transport::Buffers, WireError> {
        let options = bee_rpc::grpc::CallOptions {
            timeout: Some(timeout),
            ..Default::default()
        };
        let path = format!("/celaut.Gateway/{method}");
        let response = bee_rpc::grpc::call_raw(self.channel.clone(), &path, parts, options)
            .await
            .map_err(wire_error)?;
        let stream = futures_unfold(response);
        Ok(stream)
    }

    async fn call_raw_skippable(
        &self,
        method: &str,
        parts: Vec<Part>,
        timeout: Duration,
    ) -> Result<crate::transport::RawAnswer, WireError> {
        let options = bee_rpc::grpc::CallOptions {
            timeout: Some(timeout),
            block_skip: true,
            ..Default::default()
        };
        let path = format!("/celaut.Gateway/{method}");
        let response = bee_rpc::grpc::call_raw(self.channel.clone(), &path, parts, options)
            .await
            .map_err(wire_error)?;
        let (buffers, skipper) = futures_unfold_skippable(response);
        Ok(crate::transport::RawAnswer {
            buffers,
            skipper: Some(skipper),
        })
    }

    async fn call(
        &self,
        method: &str,
        parts: Vec<Part>,
        accepted: &[i32],
    ) -> Result<Vec<Part>, WireError> {
        self.bee_call(method, parts, accepted, self.call_timeout)
            .await
    }

    async fn call_with_timeout(
        &self,
        method: &str,
        parts: Vec<Part>,
        accepted: &[i32],
        timeout: Duration,
    ) -> Result<Vec<Part>, WireError> {
        self.bee_call(method, parts, accepted, timeout).await
    }
}
