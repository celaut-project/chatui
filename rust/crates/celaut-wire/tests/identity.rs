//! The identity check against the fixed certificates in `tests/data`
//! (made by `tests/data/make_certs.py` with the nodo code).

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use celaut_wire::channel::{new_verifier, tls_connect};
use celaut_wire::identity::peer_id_from_certificate;
use celaut_wire::{ConnectOptions, IdentityError, WireError};
use rustls::client::danger::ServerCertVerifier;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use tokio::io::AsyncReadExt;
use tokio::net::TcpListener;
use tokio_rustls::TlsAcceptor;

fn data(name: &str) -> Vec<u8> {
    let path = format!("{}/tests/data/{name}", env!("CARGO_MANIFEST_DIR"));
    std::fs::read(&path).unwrap_or_else(|e| panic!("{path}: {e}"))
}

fn peer_id_of(name: &str) -> String {
    String::from_utf8(data(name)).unwrap().trim().to_string()
}

#[test]
fn valid_identity_gives_the_peer_id() {
    let id = peer_id_from_certificate(&data("node.der")).unwrap();
    assert_eq!(id, peer_id_of("node.peer_id"));
    assert_eq!(id.len(), 64);
    let other = peer_id_from_certificate(&data("other.der")).unwrap();
    assert_eq!(other, peer_id_of("other.peer_id"));
    assert_ne!(id, other);
}

#[test]
fn wrong_public_key_is_refused() {
    // The extension names the identity of node.der. The signature is from another key.
    assert!(matches!(
        peer_id_from_certificate(&data("bad-signature.der")),
        Err(IdentityError::BadSignature(_))
    ));
}

#[test]
fn missing_extension_is_refused() {
    assert_eq!(
        peer_id_from_certificate(&data("no-extension.der")),
        Err(IdentityError::NoExtension)
    );
}

#[test]
fn bad_extensions_are_refused() {
    assert_eq!(
        peer_id_from_certificate(&data("uppercase.der")),
        Err(IdentityError::NonCanonicalKey)
    );
    assert!(matches!(
        peer_id_from_certificate(&data("no-colon.der")),
        Err(IdentityError::BadExtension(_))
    ));
    assert!(matches!(
        peer_id_from_certificate(&data("not-ascii.der")),
        Err(IdentityError::BadExtension(_))
    ));
}

#[test]
fn garbage_never_panics() {
    assert!(peer_id_from_certificate(&[]).is_err());
    assert!(peer_id_from_certificate(&[0x30]).is_err());
    assert!(peer_id_from_certificate(&[0x30, 0x84, 0xff, 0xff, 0xff, 0xff]).is_err());
    assert!(peer_id_from_certificate(b"-----BEGIN CERTIFICATE-----").is_err());
    let good = data("node.der");
    let id = peer_id_of("node.peer_id");
    // Each prefix, and each byte changed.
    for end in 0..good.len() {
        assert!(
            peer_id_from_certificate(&good[..end]).is_err(),
            "prefix {end}"
        );
    }
    for at in 0..good.len() {
        let mut bad = good.clone();
        bad[at] ^= 0x5a;
        // A change in a field that the identity does not cover can still pass.
        if let Ok(found) = peer_id_from_certificate(&bad) {
            assert_eq!(found, id);
        }
    }
}

fn verify(verifier: &dyn ServerCertVerifier, name: &str) -> Result<(), rustls::Error> {
    let der = CertificateDer::from(data(name));
    verifier
        .verify_server_cert(
            &der,
            &[],
            &ServerName::try_from("celaut-node").unwrap(),
            &[],
            UnixTime::now(),
        )
        .map(|_| ())
}

#[test]
fn verifier_pins_the_first_identity() {
    let verifier = new_verifier(None);
    verify(&*verifier, "node.der").unwrap();
    assert_eq!(verifier.peer_id().unwrap(), peer_id_of("node.peer_id"));
    // Same node again: fine. Another identity: refused.
    verify(&*verifier, "node.der").unwrap();
    assert!(verify(&*verifier, "other.der").is_err());
    assert!(matches!(
        verifier.take_refusal(),
        Some(IdentityError::PeerMismatch { .. })
    ));
}

#[test]
fn verifier_checks_the_expected_identity() {
    let verifier = new_verifier(Some(peer_id_of("other.peer_id")));
    assert!(verify(&*verifier, "node.der").is_err());
    assert_eq!(
        verifier.take_refusal(),
        Some(IdentityError::PeerMismatch {
            expected: peer_id_of("other.peer_id"),
            actual: peer_id_of("node.peer_id"),
        })
    );
    assert!(verifier.peer_id().is_none());
    verify(&*verifier, "other.der").unwrap();
}

/// A TLS 1.3 server with the test key and the certificate `cert`. Gives its address.
async fn tls_server(cert: &str) -> SocketAddr {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let key = PrivateKeyDer::try_from(data("node.key.der")).unwrap();
    let mut config = rustls::ServerConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(vec![CertificateDer::from(data(cert))], key)
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
                    // Keep the connection open until the client closes it.
                    let mut buf = [0u8; 64];
                    while matches!(tls.read(&mut buf).await, Ok(n) if n > 0) {}
                }
            });
        }
    });
    addr
}

fn options(expected: Option<String>) -> ConnectOptions {
    ConnectOptions {
        expected_peer_id: expected,
        connect_timeout: Duration::from_secs(5),
        call_timeout: Duration::from_secs(5),
    }
}

#[tokio::test]
async fn handshake_gives_the_peer_id() {
    let addr = tls_server("node.der").await;
    let (_stream, id) = tls_connect("127.0.0.1", addr.port(), &options(None))
        .await
        .unwrap();
    assert_eq!(id, peer_id_of("node.peer_id"));
    let (_stream, id) = tls_connect(
        "127.0.0.1",
        addr.port(),
        &options(Some(peer_id_of("node.peer_id"))),
    )
    .await
    .unwrap();
    assert_eq!(id, peer_id_of("node.peer_id"));
}

#[tokio::test]
async fn handshake_refuses_another_identity() {
    let addr = tls_server("node.der").await;
    let err = tls_connect(
        "127.0.0.1",
        addr.port(),
        &options(Some(peer_id_of("other.peer_id"))),
    )
    .await
    .unwrap_err();
    assert!(
        matches!(
            &err,
            WireError::Identity(IdentityError::PeerMismatch { .. })
        ),
        "{err:?}"
    );
}

#[tokio::test]
async fn handshake_refuses_a_certificate_without_identity() {
    for (name, want) in [
        ("no-extension.der", IdentityError::NoExtension),
        ("uppercase.der", IdentityError::NonCanonicalKey),
    ] {
        let addr = tls_server(name).await;
        let err = tls_connect("127.0.0.1", addr.port(), &options(None))
            .await
            .unwrap_err();
        assert!(
            matches!(&err, WireError::Identity(e) if *e == want),
            "{name}: {err:?}"
        );
    }
    let addr = tls_server("bad-signature.der").await;
    let err = tls_connect("127.0.0.1", addr.port(), &options(None))
        .await
        .unwrap_err();
    assert!(
        matches!(&err, WireError::Identity(IdentityError::BadSignature(_))),
        "{err:?}"
    );
}

#[tokio::test]
async fn plain_tcp_server_is_a_connect_error() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        loop {
            let Ok((mut tcp, _)) = listener.accept().await else {
                return;
            };
            tokio::spawn(async move {
                use tokio::io::AsyncWriteExt;
                let _ = tcp.write_all(b"HTTP/1.1 400 Bad Request\r\n\r\n").await;
                let _ = tcp.shutdown().await;
            });
        }
    });
    let err = tls_connect("127.0.0.1", port, &options(None))
        .await
        .unwrap_err();
    assert!(matches!(err, WireError::Connect(_)), "{err:?}");
}

#[tokio::test]
async fn silent_server_is_a_timeout() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let _keep = tokio::spawn(async move {
        let mut held = Vec::new();
        while let Ok((tcp, _)) = listener.accept().await {
            held.push(tcp);
        }
    });
    let mut opts = options(None);
    opts.connect_timeout = Duration::from_millis(300);
    let err = tls_connect("127.0.0.1", port, &opts).await.unwrap_err();
    assert!(matches!(err, WireError::Timeout), "{err:?}");
}

#[tokio::test]
async fn refused_port_is_a_connect_error() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    drop(listener);
    let err = tls_connect("127.0.0.1", port, &options(None))
        .await
        .unwrap_err();
    assert!(matches!(err, WireError::Connect(_)), "{err:?}");
}
