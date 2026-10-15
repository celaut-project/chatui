//! The connection to a node on each route of the app (`celaut_net`). One test function,
//! because the route is one value for the whole process.

use std::io;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use celaut_net::socks::{listen_loopback, serve, Dialer};
use celaut_net::{set_route, BoxStream, Route, Socks5};
use celaut_wire::channel::tls_connect;
use celaut_wire::{ConnectOptions, WireError};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use tokio::io::AsyncReadExt;
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::TlsAcceptor;

fn data(name: &str) -> Vec<u8> {
    let path = format!("{}/tests/data/{name}", env!("CARGO_MANIFEST_DIR"));
    std::fs::read(&path).unwrap_or_else(|e| panic!("{path}: {e}"))
}

async fn tls_server() -> SocketAddr {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let key = PrivateKeyDer::try_from(data("node.key.der")).unwrap();
    let mut config = rustls::ServerConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(vec![CertificateDer::from(data("node.der"))], key)
        .unwrap();
    config.alpn_protocols = vec![b"h2".to_vec()];
    let acceptor = TlsAcceptor::from(Arc::new(config));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        loop {
            let Ok((tcp, _)) = listener.accept().await else {
                return;
            };
            let acceptor = acceptor.clone();
            tokio::spawn(async move {
                if let Ok(mut tls) = acceptor.accept(tcp).await {
                    let mut buf = [0u8; 64];
                    while matches!(tls.read(&mut buf).await, Ok(n) if n > 0) {}
                }
            });
        }
    });
    addr
}

/// A proxy dialer that records what the client asked for.
struct Recording(Mutex<Vec<(String, u16)>>);

impl Dialer for Recording {
    async fn dial(&self, host: String, port: u16) -> io::Result<BoxStream> {
        self.0.lock().unwrap().push((host.clone(), port));
        Ok(Box::new(TcpStream::connect((host.as_str(), port)).await?))
    }
}

fn options() -> ConnectOptions {
    ConnectOptions {
        expected_peer_id: None,
        connect_timeout: Duration::from_secs(5),
        call_timeout: Duration::from_secs(5),
    }
}

#[tokio::test]
async fn the_identity_of_a_node_is_checked_on_every_route() {
    let node = tls_server().await;
    let peer_id = String::from_utf8(data("node.peer_id")).unwrap().trim().to_string();

    // Direct.
    set_route(Route::Direct);
    let (_stream, id) = tls_connect("127.0.0.1", node.port(), &options()).await.unwrap();
    assert_eq!(id, peer_id);

    // Through a SOCKS5 proxy: the node proves the same identity, and the proxy got the
    // host and the port of the node.
    let dialer = Arc::new(Recording(Mutex::default()));
    let (listener, proxy_addr) = listen_loopback().await.unwrap();
    tokio::spawn(serve(listener, ("u".into(), "p".into()), dialer.clone()));
    set_route(Route::Socks(Socks5 {
        addr: proxy_addr,
        auth: Some(("u".into(), "p".into())),
    }));
    let (_stream, id) = tls_connect("127.0.0.1", node.port(), &options()).await.unwrap();
    assert_eq!(id, peer_id);
    assert_eq!(
        dialer.0.lock().unwrap().as_slice(),
        [("127.0.0.1".to_string(), node.port())]
    );

    // Through the proxy, a node with another identity than the expected one is refused.
    let mut wrong = options();
    wrong.expected_peer_id = Some("00".repeat(32));
    let error = tls_connect("127.0.0.1", node.port(), &wrong).await.unwrap_err();
    assert!(matches!(error, WireError::Identity(_)), "{error}");

    // Blocked: no connection, and the proxy gets no new request.
    set_route(Route::Blocked("Tor is starting".into()));
    let before = dialer.0.lock().unwrap().len();
    let error = tls_connect("127.0.0.1", node.port(), &options()).await.unwrap_err();
    assert!(matches!(error, WireError::Connect(ref t) if t.contains("Tor is starting")), "{error}");
    assert_eq!(dialer.0.lock().unwrap().len(), before);
    set_route(Route::Direct);
}
