//! The HTTP clients of the app on each network route (`celaut_net`). One test function,
//! because the route is one value for the whole process.

use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use celaut_net::socks::{listen_loopback, serve, Dialer};
use celaut_net::{set_route, BoxStream, Route, Socks5};
use tokio::net::TcpStream;

/// A small HTTP server that answers `ok` and counts the requests.
fn http_server() -> (u16, Arc<AtomicUsize>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let count = Arc::new(AtomicUsize::new(0));
    let seen = count.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { return };
            let mut buf = [0u8; 2048];
            let _ = stream.read(&mut buf);
            seen.fetch_add(1, Ordering::SeqCst);
            let _ = stream.write_all(
                b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
            );
        }
    });
    (port, count)
}

struct Recording(Mutex<Vec<(String, u16)>>);

impl Dialer for Recording {
    async fn dial(&self, host: String, port: u16) -> std::io::Result<BoxStream> {
        self.0.lock().unwrap().push((host.clone(), port));
        Ok(Box::new(TcpStream::connect((host.as_str(), port)).await?))
    }
}

#[tokio::test]
async fn a_client_follows_the_route() {
    let (port, requests) = http_server();
    let url = format!("http://127.0.0.1:{port}/");

    // Direct.
    set_route(Route::Direct);
    let body = wallet_net::http::client().get(&url).send().await.unwrap().text().await.unwrap();
    assert_eq!(body, "ok");
    assert_eq!(requests.load(Ordering::SeqCst), 1);

    // Through a SOCKS5 proxy with a password: the proxy gets the request to the host.
    let dialer = Arc::new(Recording(Mutex::default()));
    let (listener, addr) = listen_loopback().await.unwrap();
    tokio::spawn(serve(listener, ("user".into(), "s3cret".into()), dialer.clone()));
    set_route(Route::Socks(Socks5 {
        addr,
        auth: Some(("user".into(), "s3cret".into())),
    }));
    let body = wallet_net::http::client().get(&url).send().await.unwrap().text().await.unwrap();
    assert_eq!(body, "ok");
    assert_eq!(requests.load(Ordering::SeqCst), 2);
    assert_eq!(dialer.0.lock().unwrap().as_slice(), [("127.0.0.1".to_string(), port)]);

    // A wrong password: the request fails and the server sees nothing.
    set_route(Route::Socks(Socks5 {
        addr,
        auth: Some(("user".into(), "wrong".into())),
    }));
    assert!(wallet_net::http::client().get(&url).send().await.is_err());
    assert_eq!(requests.load(Ordering::SeqCst), 2);

    // Blocked: the request fails, and it does not go direct.
    set_route(Route::Blocked("Tor is starting".into()));
    assert!(wallet_net::http::client().get(&url).send().await.is_err());
    assert_eq!(requests.load(Ordering::SeqCst), 2);
    assert_eq!(dialer.0.lock().unwrap().len(), 1);

    // An environment proxy is not used.
    set_route(Route::Direct);
    std::env::set_var("HTTP_PROXY", "http://127.0.0.1:9");
    std::env::set_var("ALL_PROXY", "http://127.0.0.1:9");
    let body = wallet_net::http::client().get(&url).send().await.unwrap().text().await.unwrap();
    assert_eq!(body, "ok");
}
