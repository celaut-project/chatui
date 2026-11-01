//! HTTP requests to a web slot of an instance through the `ServiceTunnel`, with no local
//! port.
//!
//! An [`HttpTunnel`] speaks HTTP/1.1 (the `hyper` client) over one tunnel stream. The
//! requests of one `HttpTunnel` go one after the other on that stream (keep-alive), so
//! the node charges `TUNNEL_OPEN_MU` once for all of them, not once for each resource of
//! a page. The stream opens with the first request, not with the `HttpTunnel`.
//!
//! When the stream is closed (the service closed the connection, the node dropped it, or
//! a request failed half way) the next request opens another one. A request is sent
//! again only when it surely did not reach the service (see the rules in
//! [`HttpTunnel::request_streaming`]), the same rule as the local port
//! (`local_port.rs`, PR #77).
//!
//! Content-Length, chunked bodies and `Connection: close` are handled by `hyper`.
//! [`Limits`] bounds the size of the head and of the body of an answer and the time to
//! wait for the peer, so that a request ends with an error and never hangs.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use bytes::Bytes;
use celaut_wire::tunnel::MAX_PAYLOAD;
use celaut_wire::{ReceiptSink, Tunnel, TunnelOpener, WireError};
use http::{header, HeaderName, HeaderValue, Method, Request, Uri};
use http_body_util::{BodyExt, Full};
use hyper::body::{Body, Incoming};
use hyper::client::conn::http1;
use hyper_util::rt::TokioIo;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{Mutex as AsyncMutex, OwnedMutexGuard};

use crate::local_port::{is_transient, AbortOnDrop, Target};

/// The most bytes of the head of an answer (status line and headers).
pub const MAX_HEAD_BYTES: usize = 64 * 1024;
/// The most headers in an answer.
pub const MAX_HEADERS: usize = 100;
/// The most bytes of the body of one answer.
pub const MAX_BODY_BYTES: usize = 64 * 1024 * 1024;
/// How long to wait for the head of the answer after the request goes out. It is long
/// because a service may work before it answers (a model that loads, a slow query).
pub const HEADER_TIMEOUT: Duration = Duration::from_secs(120);
/// How long to wait between two pieces of the body of an answer.
pub const IDLE_TIMEOUT: Duration = Duration::from_secs(60);
/// How many times a request that surely did not reach the service is sent again.
const OPEN_RETRIES: u32 = 3;

/// The limits of an [`HttpTunnel`]. The default is the constants of this module.
#[derive(Debug, Clone, Copy)]
pub struct Limits {
    /// Bytes of the head of an answer. At least 8192. More is an error.
    pub max_head_bytes: usize,
    /// Headers in an answer. More is an error.
    pub max_headers: usize,
    /// Bytes of the body of an answer, with or without `Content-Length`. More is an
    /// error ([`HttpTunnelError::BodyTooLarge`]), also for a streamed body.
    pub max_body_bytes: usize,
    /// Time from the request to the head of the answer.
    pub header_timeout: Duration,
    /// Time with no byte of the body.
    pub idle_timeout: Duration,
}

impl Default for Limits {
    fn default() -> Self {
        Limits {
            max_head_bytes: MAX_HEAD_BYTES,
            max_headers: MAX_HEADERS,
            max_body_bytes: MAX_BODY_BYTES,
            header_timeout: HEADER_TIMEOUT,
            idle_timeout: IDLE_TIMEOUT,
        }
    }
}

/// Why a request failed.
#[derive(Debug, thiserror::Error)]
pub enum HttpTunnelError {
    /// The method, the path or a header is not valid.
    #[error("invalid request: {0}")]
    InvalidRequest(String),
    /// The tunnel failed: no connection to the node, a refusal, a closed stream. The text
    /// is the error of the node when there is one.
    #[error("tunnel: {0}")]
    Tunnel(String),
    /// The answer is not valid HTTP, or is bigger than the limit of its head.
    #[error("http: {0}")]
    Http(String),
    /// The peer was silent for too long. The text says where.
    #[error("timed out waiting for the {0}")]
    Timeout(&'static str),
    /// The body of the answer is bigger than `max_body_bytes`.
    #[error("the answer is larger than {limit} bytes")]
    BodyTooLarge { limit: usize },
}

/// A whole answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpResponse {
    pub status: u16,
    /// In the order received. A value that is not UTF-8 is converted with replacement
    /// characters.
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

/// An answer whose body is still on its way.
#[derive(Debug)]
pub struct StreamedResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: ResponseBody,
}

/// The body of a [`StreamedResponse`]. It holds the stream: the next request of the
/// `HttpTunnel` waits until the body is read to its end or dropped. A body dropped before
/// its end closes the stream (the rest of the answer would be in the way of the next
/// request), and the next request opens another one.
pub struct ResponseBody {
    incoming: Incoming,
    guard: OwnedMutexGuard<Option<Conn>>,
    limits: Limits,
    received: usize,
    done: bool,
}

impl std::fmt::Debug for ResponseBody {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ResponseBody")
            .field("received", &self.received)
            .field("done", &self.done)
            .finish_non_exhaustive()
    }
}

impl ResponseBody {
    /// The next piece of the body, or `None` at its end. An error ends the body and
    /// closes the stream.
    pub async fn next_chunk(&mut self) -> Result<Option<Vec<u8>>, HttpTunnelError> {
        loop {
            if self.done {
                return Ok(None);
            }
            let frame = tokio::time::timeout(self.limits.idle_timeout, self.incoming.frame())
                .await
                .map_err(|_| HttpTunnelError::Timeout("body of the answer"))?;
            match frame {
                None => {
                    self.done = true;
                    return Ok(None);
                }
                Some(Err(e)) => return Err(self.failure(e)),
                Some(Ok(frame)) => {
                    // Trailers are skipped.
                    let Ok(data) = frame.into_data() else {
                        continue;
                    };
                    if data.is_empty() {
                        continue;
                    }
                    self.received += data.len();
                    if self.received > self.limits.max_body_bytes {
                        return Err(HttpTunnelError::BodyTooLarge {
                            limit: self.limits.max_body_bytes,
                        });
                    }
                    return Ok(Some(data.to_vec()));
                }
            }
        }
    }

    fn failure(&self, e: hyper::Error) -> HttpTunnelError {
        match self.guard.as_ref().and_then(|c| c.state.error()) {
            Some(text) => HttpTunnelError::Tunnel(text),
            None => HttpTunnelError::Http(e.to_string()),
        }
    }
}

impl Drop for ResponseBody {
    fn drop(&mut self) {
        if !self.done {
            // Not read to its end: this stream cannot carry another request.
            *self.guard = None;
        }
    }
}

/// What the tasks of a connection learned, for the decisions of the request.
#[derive(Default)]
struct ConnState {
    /// The error of the stream: whether nothing could have reached the service, and the
    /// text.
    error: Mutex<Option<(bool, String)>>,
    /// A byte came back from the service.
    answered: AtomicBool,
}

impl ConnState {
    fn error(&self) -> Option<String> {
        self.error.lock().ok()?.as_ref().map(|(_, t)| t.clone())
    }

    /// The stream failed before it was open, and no byte came back.
    fn never_opened(&self) -> bool {
        !self.answered.load(Ordering::SeqCst)
            && self
                .error
                .lock()
                .ok()
                .is_some_and(|e| e.as_ref().is_some_and(|(transient, _)| *transient))
    }
}

/// One tunnel stream with an HTTP/1.1 client on it. Dropping it ends the stream.
struct Conn {
    sender: http1::SendRequest<Full<Bytes>>,
    state: Arc<ConnState>,
    _tasks: [AbortOnDrop; 3],
}

impl Conn {
    /// Open a stream and put the HTTP client on it. The bytes of the client go to the
    /// stream and back through an in-memory pipe, and three tasks move them.
    async fn open(target: &Target, limits: &Limits) -> Result<Conn, HttpTunnelError> {
        let Tunnel {
            to_service,
            mut from_service,
        } = target.open();
        let (client_io, pump_io) = tokio::io::duplex(MAX_PAYLOAD);
        let (mut from_client, mut to_client) = tokio::io::split(pump_io);
        let state = Arc::new(ConnState::default());

        let up = tokio::spawn(async move {
            let mut buffer = vec![0u8; MAX_PAYLOAD];
            loop {
                match from_client.read(&mut buffer).await {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if to_service.send(buffer[..n].to_vec()).await.is_err() {
                            break;
                        }
                    }
                }
            }
            // `to_service` is dropped here: the client has no more to send.
        });
        let down_state = state.clone();
        let down = tokio::spawn(async move {
            while let Some(item) = from_service.recv().await {
                match item {
                    Ok(data) => {
                        down_state.answered.store(true, Ordering::SeqCst);
                        if to_client.write_all(&data).await.is_err() {
                            return;
                        }
                    }
                    Err(e) => {
                        if let Ok(mut slot) = down_state.error.lock() {
                            *slot = Some((is_transient(&e), e.to_string()));
                        }
                        break;
                    }
                }
            }
            // The end of the stream (or its error): the client reads the end of its data.
            let _ = to_client.shutdown().await;
        });

        let (sender, connection) = http1::Builder::new()
            .max_buf_size(limits.max_head_bytes.max(8192))
            .max_headers(limits.max_headers)
            .handshake(TokioIo::new(client_io))
            .await
            .map_err(|e| HttpTunnelError::Http(e.to_string()))?;
        let driver = tokio::spawn(async move {
            let _ = connection.await;
        });
        Ok(Conn {
            sender,
            state,
            _tasks: [AbortOnDrop(up), AbortOnDrop(down), AbortOnDrop(driver)],
        })
    }
}

/// An HTTP client for one slot of one instance, through the tunnel. See the module
/// documentation.
pub struct HttpTunnel {
    target: Arc<Target>,
    limits: Limits,
    streams: AtomicU64,
    /// The stream, if any. The lock is held from the request to the end of its body,
    /// which serializes the requests.
    conn: Arc<AsyncMutex<Option<Conn>>>,
}

impl std::fmt::Debug for HttpTunnel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HttpTunnel")
            .field("target", &self.target)
            .field("limits", &self.limits)
            .finish_non_exhaustive()
    }
}

/// How an attempt to send a request ended.
enum Attempt {
    /// The head of the answer.
    Answered(hyper::Response<Incoming>),
    /// Nothing of the request was written to the stream.
    NotSent(hyper::Error),
    /// The request may have been written.
    Failed(hyper::Error),
}

impl HttpTunnel {
    /// A client for port `slot` of the instance with `token`, with the default
    /// [`Limits`]. The receipts of the stream go to `receipts`. No stream opens yet. Must
    /// be used inside a Tokio runtime.
    pub fn new(
        opener: Arc<dyn TunnelOpener>,
        token: String,
        slot: u16,
        receipts: Option<ReceiptSink>,
    ) -> HttpTunnel {
        Self::with_limits(opener, token, slot, receipts, Limits::default())
    }

    /// Like [`HttpTunnel::new`], with other limits.
    pub fn with_limits(
        opener: Arc<dyn TunnelOpener>,
        token: String,
        slot: u16,
        receipts: Option<ReceiptSink>,
        limits: Limits,
    ) -> HttpTunnel {
        HttpTunnel {
            target: Arc::new(Target::new(opener, token, slot, receipts)),
            limits,
            streams: AtomicU64::new(0),
            conn: Arc::new(AsyncMutex::new(None)),
        }
    }

    /// Open the next streams with `opener` (a new connection to the node, after the old
    /// one broke). The stream that is open stays until it closes.
    pub fn set_opener(&self, opener: Arc<dyn TunnelOpener>) {
        self.target.set_opener(opener);
    }

    /// How many `ServiceTunnel` streams this client opened. Each one is charged
    /// `TUNNEL_OPEN_MU` by the node.
    pub fn streams_opened(&self) -> u64 {
        self.streams.load(Ordering::Relaxed)
    }

    /// Send a request and read the whole answer. `path_and_query` starts with `/`.
    /// `headers` are added to the request; `Host` is `localhost` if not given, and
    /// `Content-Length`, `Transfer-Encoding` and `Connection` are the client's, so they
    /// are dropped from `headers`. The body of the answer is limited by
    /// [`Limits::max_body_bytes`].
    pub async fn request(
        &self,
        method: &str,
        path_and_query: &str,
        headers: &[(String, String)],
        body: Vec<u8>,
    ) -> Result<HttpResponse, HttpTunnelError> {
        let StreamedResponse {
            status,
            headers,
            mut body,
        } = self
            .request_streaming(method, path_and_query, headers, body)
            .await?;
        let mut all = Vec::new();
        while let Some(chunk) = body.next_chunk().await? {
            all.extend_from_slice(&chunk);
        }
        Ok(HttpResponse {
            status,
            headers,
            body: all,
        })
    }

    /// Send a request and give the answer when its head arrives; the body is read with
    /// [`ResponseBody::next_chunk`]. Other requests wait until the body is read or
    /// dropped.
    ///
    /// The request goes to the open stream. If that stream is closed (the service closed
    /// the connection after its last answer), a new one opens first. The request is sent
    /// again, to a new stream, only when it surely never reached the service: nothing of
    /// it was written, or the stream failed to open (no connection to the node, a time
    /// limit) before any byte came back, up to 3 times with a wait of 0.25, 0.5 and 0.75
    /// s. A request that went out on a stream that then failed (`Unavailable`, an early
    /// end, a timeout) is never sent again, because the service may have run it. A
    /// refusal of the node is not retried either.
    pub async fn request_streaming(
        &self,
        method: &str,
        path_and_query: &str,
        headers: &[(String, String)],
        body: Vec<u8>,
    ) -> Result<StreamedResponse, HttpTunnelError> {
        let template = Template::new(method, path_and_query, headers, body)?;
        let mut guard = self.conn.clone().lock_owned().await;
        let mut retries = 0u32;
        loop {
            let reused = guard.as_ref().is_some_and(|c| !c.sender.is_closed());
            if !reused {
                *guard = Some(Conn::open(&self.target, &self.limits).await?);
                self.streams.fetch_add(1, Ordering::Relaxed);
            }
            let conn = guard.as_mut().ok_or_else(|| {
                HttpTunnelError::Tunnel("the stream closed before the request".into())
            })?;
            let request = template.build()?;
            let attempt = tokio::time::timeout(self.limits.header_timeout, async {
                if let Err(e) = conn.sender.ready().await {
                    return Attempt::NotSent(e);
                }
                match conn.sender.try_send_request(request).await {
                    Ok(response) => Attempt::Answered(response),
                    Err(e) if e.message().is_some() => Attempt::NotSent(e.into_error()),
                    Err(e) => Attempt::Failed(e.into_error()),
                }
            })
            .await;
            let (error, safe_to_send_again) = match attempt {
                Err(_) => {
                    // The request may be at the service: not sent again, and the stream
                    // is not trusted.
                    *guard = None;
                    return Err(HttpTunnelError::Timeout("head of the answer"));
                }
                Ok(Attempt::Answered(response)) => {
                    return self.streamed(response, guard);
                }
                Ok(Attempt::NotSent(e)) => (e, true),
                Ok(Attempt::Failed(e)) => (e, conn.state.never_opened()),
            };
            let text = conn.state.error();
            *guard = None;
            // A stale stream (it was open and closed) is replaced for free; the other
            // failures use the retries.
            if safe_to_send_again && (reused || retries < OPEN_RETRIES) {
                if !reused {
                    retries += 1;
                    tokio::time::sleep(Duration::from_millis(250 * u64::from(retries))).await;
                }
                continue;
            }
            return Err(match text {
                Some(text) => HttpTunnelError::Tunnel(text),
                None => HttpTunnelError::Http(error.to_string()),
            });
        }
    }

    fn streamed(
        &self,
        response: hyper::Response<Incoming>,
        mut guard: OwnedMutexGuard<Option<Conn>>,
    ) -> Result<StreamedResponse, HttpTunnelError> {
        let status = response.status().as_u16();
        let headers = response
            .headers()
            .iter()
            .map(|(k, v)| {
                (
                    k.as_str().to_string(),
                    String::from_utf8_lossy(v.as_bytes()).into_owned(),
                )
            })
            .collect();
        let incoming = response.into_body();
        // A `Content-Length` over the limit fails now, before the body is read.
        if incoming.size_hint().lower() > self.limits.max_body_bytes as u64 {
            *guard = None;
            return Err(HttpTunnelError::BodyTooLarge {
                limit: self.limits.max_body_bytes,
            });
        }
        let done = incoming.is_end_stream();
        Ok(StreamedResponse {
            status,
            headers,
            body: ResponseBody {
                incoming,
                guard,
                limits: self.limits,
                received: 0,
                done,
            },
        })
    }
}

/// A request that can be built again for each attempt.
struct Template {
    method: Method,
    uri: Uri,
    headers: Vec<(HeaderName, HeaderValue)>,
    body: Bytes,
}

impl Template {
    fn new(
        method: &str,
        path_and_query: &str,
        headers: &[(String, String)],
        body: Vec<u8>,
    ) -> Result<Template, HttpTunnelError> {
        let invalid = |what: &str, e: &dyn std::fmt::Display| {
            HttpTunnelError::InvalidRequest(format!("{what}: {e}"))
        };
        let method = Method::from_bytes(method.as_bytes()).map_err(|e| invalid("method", &e))?;
        let uri: Uri = path_and_query.parse().map_err(|e| invalid("path", &e))?;
        if !path_and_query.starts_with('/') || uri.scheme().is_some() || uri.authority().is_some() {
            return Err(HttpTunnelError::InvalidRequest(
                "the path must start with '/'".into(),
            ));
        }
        let mut out = Vec::new();
        for (name, value) in headers {
            let name =
                HeaderName::from_bytes(name.as_bytes()).map_err(|e| invalid("header", &e))?;
            if name == header::CONTENT_LENGTH
                || name == header::TRANSFER_ENCODING
                || name == header::CONNECTION
            {
                continue;
            }
            let value = HeaderValue::from_str(value).map_err(|e| invalid("header", &e))?;
            out.push((name, value));
        }
        if !out.iter().any(|(n, _)| *n == header::HOST) {
            out.push((header::HOST, HeaderValue::from_static("localhost")));
        }
        Ok(Template {
            method,
            uri,
            headers: out,
            body: Bytes::from(body),
        })
    }

    fn build(&self) -> Result<Request<Full<Bytes>>, HttpTunnelError> {
        let mut request = Request::builder()
            .method(self.method.clone())
            .uri(self.uri.clone())
            .body(Full::new(self.body.clone()))
            .map_err(|e| HttpTunnelError::InvalidRequest(e.to_string()))?;
        for (name, value) in &self.headers {
            request.headers_mut().append(name.clone(), value.clone());
        }
        Ok(request)
    }
}

impl From<WireError> for HttpTunnelError {
    fn from(e: WireError) -> Self {
        HttpTunnelError::Tunnel(e.to_string())
    }
}
