//! HTTP clients for Argus's own requests.
//!
//! reqwest 0.13 verifies certificates with the platform verifier unless it is
//! handed a TLS config, and on Android that verifier needs JNI setup the app
//! does not do. Every client here gets the config reqwest 0.12's `rustls-tls`
//! feature built: rustls with the ring provider, the bundled Mozilla roots from
//! webpki-roots, and HTTP/1.1 only.

use std::sync::{Arc, LazyLock};

static TLS_CONFIG: LazyLock<rustls::ClientConfig> = LazyLock::new(|| {
    let roots = rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let mut config = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("ring supports the default TLS versions")
        .with_root_certificates(roots)
        .with_no_client_auth();
    config.alpn_protocols = vec![b"http/1.1".to_vec()];
    config
});

/// A proxy that no connection can use: the port 0. A client that has it fails every
/// request, so a blocked route never becomes a direct connection.
const BLOCKED_PROXY: &str = "socks5h://127.0.0.1:0";

/// Use instead of `reqwest::Client::builder()`.
///
/// The client follows the network route of the app (`celaut_net::route`) at the moment
/// that it is built: direct, through a SOCKS5 proxy (Tor), or with no way out. The
/// environment proxies are never used. A client that lives a long time keeps the route
/// that it had, so its owner must build it again when the route changes.
pub fn client_builder() -> reqwest::ClientBuilder {
    let builder = reqwest::Client::builder()
        .tls_backend_preconfigured(TLS_CONFIG.clone())
        .no_proxy();
    let blocked = || reqwest::Proxy::all(BLOCKED_PROXY).expect("a valid proxy URL");
    match celaut_net::route() {
        celaut_net::Route::Direct => builder,
        celaut_net::Route::Socks(proxy) => match reqwest::Proxy::all(proxy.url()) {
            Ok(proxy) => builder.proxy(proxy),
            Err(_) => builder.proxy(blocked()),
        },
        celaut_net::Route::Blocked(_) => builder.proxy(blocked()),
    }
}

/// Use instead of `reqwest::Client::new()`; like it, panics if the client
/// cannot be built.
pub fn client() -> reqwest::Client {
    client_builder().build().expect("HTTP client")
}
