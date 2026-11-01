//! HTTP over the tunnel with no local port. The tunnels go to a small HTTP/1.1 server in
//! the test instead of a node (the same fake opener as `local_port.rs`).

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use celaut_client::{HttpTunnel, HttpTunnelError, Limits};
use celaut_wire::{Tunnel, TunnelOpener, WireError};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;

/// Read one request (head and body by Content-Length) from `socket`. `None` at the end.
async fn read_request(socket: &mut TcpStream, pending: &mut Vec<u8>) -> Option<(String, Vec<u8>)> {
    loop {
        if let Some(end) = pending.windows(4).position(|w| w == b"\r\n\r\n") {
            let head = String::from_utf8_lossy(&pending[..end]).to_string();
            let length = head
                .lines()
                .find_map(|l| {
                    l.to_ascii_lowercase()
                        .strip_prefix("content-length:")
                        .map(|v| v.trim().parse::<usize>().unwrap())
                })
                .unwrap_or(0);
            while pending.len() < end + 4 + length {
                let mut buf = [0u8; 4096];
                let n = socket.read(&mut buf).await.ok()?;
                if n == 0 {
                    return None;
                }
                pending.extend_from_slice(&buf[..n]);
            }
            let body = pending[end + 4..end + 4 + length].to_vec();
            pending.drain(..end + 4 + length);
            return Some((head, body));
        }
        let mut buf = [0u8; 4096];
        let n = socket.read(&mut buf).await.ok()?;
        if n == 0 {
            return None;
        }
        pending.extend_from_slice(&buf[..n]);
    }
}

/// An HTTP/1.1 server with a few paths. Gives its port.
async fn http_server() -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let count = Arc::new(AtomicUsize::new(0));
    tokio::spawn(async move {
        loop {
            let (mut socket, _) = listener.accept().await.unwrap();
            let n = count.fetch_add(1, Ordering::SeqCst) + 1;
            tokio::spawn(async move {
                let mut pending = Vec::new();
                while let Some((head, body)) = read_request(&mut socket, &mut pending).await {
                    let first = head.lines().next().unwrap().to_string();
                    let path = first.split(' ').nth(1).unwrap().to_string();
                    let route = path.split('?').next().unwrap().to_string();
                    let reply: Vec<u8> = match route.as_str() {
                        "/hello" => b"HTTP/1.1 201 Created\r\nx-test: yes\r\nset-cookie: a=1\r\nset-cookie: b=2\r\ncontent-length: 5\r\n\r\nhello".to_vec(),
                        "/echo" => {
                            let mut r = format!("HTTP/1.1 200 OK\r\ncontent-length: {}\r\n\r\n", body.len()).into_bytes();
                            r.extend_from_slice(&body);
                            r
                        }
                        "/chunked" => b"HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n2\r\nab\r\n3\r\ncde\r\n0\r\n\r\n".to_vec(),
                        "/big" => {
                            let mut r = b"HTTP/1.1 200 OK\r\ncontent-length: 1000\r\n\r\n".to_vec();
                            r.extend(std::iter::repeat_n(b'x', 1000));
                            r
                        }
                        "/bigchunked" => {
                            let mut r = b"HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n".to_vec();
                            for _ in 0..10 {
                                r.extend_from_slice(b"64\r\n");
                                r.extend(std::iter::repeat_n(b'y', 100));
                                r.extend_from_slice(b"\r\n");
                            }
                            r.extend_from_slice(b"0\r\n\r\n");
                            r
                        }
                        "/stall" => {
                            tokio::time::sleep(Duration::from_secs(60)).await;
                            return;
                        }
                        // The service answers and closes the connection, without saying so.
                        "/close" => {
                            let text = format!("{n} close");
                            let r = format!("HTTP/1.1 200 OK\r\ncontent-length: {}\r\n\r\n{text}", text.len());
                            let _ = socket.write_all(r.as_bytes()).await;
                            let _ = socket.shutdown().await;
                            return;
                        }
                        _ => {
                            let text = format!("{n} {path}");
                            format!("HTTP/1.1 200 OK\r\ncontent-length: {}\r\n\r\n{text}", text.len()).into_bytes()
                        }
                    };
                    if socket.write_all(&reply).await.is_err() {
                        return;
                    }
                }
            });
        }
    });
    port
}

/// Opens each tunnel as a TCP connection to the local server, and records the opens.
struct FakeNode {
    server_port: u16,
    opened: Mutex<Vec<(String, u16)>>,
    /// How many of the first opens fail with "cannot connect".
    unreachable: AtomicUsize,
    /// How many of the first opens take the request and then fail with `Unavailable`.
    fail_after_request: AtomicUsize,
    /// The chunks that reached the service, over all streams.
    delivered: Arc<Mutex<Vec<Vec<u8>>>>,
}

impl TunnelOpener for FakeNode {
    fn open_tunnel(
        &self,
        token: &str,
        slot: u16,
        _receipts: Option<celaut_wire::ReceiptSink>,
    ) -> Tunnel {
        self.opened.lock().unwrap().push((token.to_string(), slot));
        let (to_service, mut to_rx) = mpsc::channel::<Vec<u8>>(16);
        let (from_tx, from_service) = mpsc::channel(16);
        let port = self.server_port;
        let take = |c: &AtomicUsize| {
            c.try_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
                .is_ok()
        };
        let unreachable = take(&self.unreachable);
        let fail_after = take(&self.fail_after_request);
        let delivered = self.delivered.clone();
        tokio::spawn(async move {
            if fail_after {
                if let Some(data) = to_rx.recv().await {
                    delivered.lock().unwrap().push(data);
                }
                let _ = from_tx
                    .send(Err(WireError::Call("Unavailable: transport error".into())))
                    .await;
                return;
            }
            if unreachable {
                let _ = from_tx
                    .send(Err(WireError::Connect("no route".to_string())))
                    .await;
                return;
            }
            let socket = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
            let (mut reader, mut writer) = socket.into_split();
            tokio::spawn(async move {
                while let Some(data) = to_rx.recv().await {
                    delivered.lock().unwrap().push(data.clone());
                    if writer.write_all(&data).await.is_err() {
                        return;
                    }
                }
                let _ = writer.shutdown().await;
            });
            let mut buffer = vec![0u8; 1024];
            loop {
                match reader.read(&mut buffer).await {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if from_tx.send(Ok(buffer[..n].to_vec())).await.is_err() {
                            break;
                        }
                    }
                }
            }
        });
        Tunnel {
            to_service,
            from_service,
        }
    }
}

async fn node() -> Arc<FakeNode> {
    Arc::new(FakeNode {
        server_port: http_server().await,
        opened: Mutex::new(Vec::new()),
        unreachable: AtomicUsize::new(0),
        fail_after_request: AtomicUsize::new(0),
        delivered: Arc::new(Mutex::new(Vec::new())),
    })
}

fn tunnel(fake: &Arc<FakeNode>) -> HttpTunnel {
    HttpTunnel::new(fake.clone(), "tok".into(), 3030, None)
}

fn short_limits() -> Limits {
    Limits {
        max_body_bytes: 500,
        header_timeout: Duration::from_millis(300),
        idle_timeout: Duration::from_millis(300),
        ..Limits::default()
    }
}

async fn text(t: &HttpTunnel, path: &str) -> String {
    let r = tokio::time::timeout(Duration::from_secs(10), t.request("GET", path, &[], vec![]))
        .await
        .expect("no answer")
        .unwrap();
    assert_eq!(r.status, 200);
    String::from_utf8(r.body).unwrap()
}

#[tokio::test]
async fn get_returns_status_headers_and_body() {
    let fake = node().await;
    let t = tunnel(&fake);
    let r = t.request("GET", "/hello?x=1", &[], vec![]).await.unwrap();
    assert_eq!(r.status, 201);
    assert_eq!(r.body, b"hello");
    let value = |name: &str| -> Vec<&str> {
        r.headers
            .iter()
            .filter(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
            .collect()
    };
    assert_eq!(value("x-test"), ["yes"]);
    // A repeated header keeps both values.
    assert_eq!(value("set-cookie"), ["a=1", "b=2"]);
    assert_eq!(
        *fake.opened.lock().unwrap(),
        vec![("tok".to_string(), 3030)]
    );
    // The request carried the path with its query and a default Host.
    let sent = String::from_utf8(fake.delivered.lock().unwrap()[0].clone()).unwrap();
    assert!(sent.starts_with("GET /hello?x=1 HTTP/1.1\r\n"), "{sent}");
    assert!(
        sent.to_ascii_lowercase().contains("host: localhost"),
        "{sent}"
    );
}

#[tokio::test]
async fn a_post_body_arrives_intact() {
    let fake = node().await;
    let t = tunnel(&fake);
    // Bigger than one payload of the tunnel and not text.
    let body: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
    let headers = vec![(
        "content-type".to_string(),
        "application/octet-stream".to_string(),
    )];
    let r = t
        .request("POST", "/echo", &headers, body.clone())
        .await
        .unwrap();
    assert_eq!(r.status, 200);
    assert_eq!(r.body, body);
    // What the service received is the head and then exactly the body.
    let all: Vec<u8> = fake.delivered.lock().unwrap().concat();
    assert!(all.ends_with(&body));
    let head = String::from_utf8_lossy(&all[..all.len() - body.len()]).to_ascii_lowercase();
    assert!(head.starts_with("post /echo http/1.1"), "{head}");
    assert!(head.contains("content-length: 200000"), "{head}");
    assert!(
        head.contains("content-type: application/octet-stream"),
        "{head}"
    );
}

#[tokio::test]
async fn sequential_requests_share_one_stream() {
    let fake = node().await;
    let t = tunnel(&fake);
    assert_eq!(t.streams_opened(), 0);
    for i in 0..5 {
        assert_eq!(text(&t, &format!("/r{i}")).await, format!("1 /r{i}"));
    }
    assert_eq!(t.streams_opened(), 1);
    assert_eq!(fake.opened.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn a_chunked_answer_is_joined_and_keeps_the_stream() {
    let fake = node().await;
    let t = tunnel(&fake);
    assert_eq!(text(&t, "/chunked").await, "abcde");
    assert_eq!(text(&t, "/after").await, "1 /after");
    assert_eq!(t.streams_opened(), 1);
}

#[tokio::test]
async fn a_streamed_body_comes_in_pieces_and_a_dropped_one_closes_the_stream() {
    let fake = node().await;
    let t = tunnel(&fake);
    let mut r = t
        .request_streaming("GET", "/chunked", &[], vec![])
        .await
        .unwrap();
    let mut got = Vec::new();
    while let Some(c) = r.body.next_chunk().await.unwrap() {
        got.extend(c);
    }
    assert_eq!(got, b"abcde");
    drop(r);
    assert_eq!(text(&t, "/next").await, "1 /next");
    assert_eq!(t.streams_opened(), 1);
    // Dropped before its end: the stream is closed, the next request opens another.
    let r = t
        .request_streaming("GET", "/bigchunked", &[], vec![])
        .await
        .unwrap();
    drop(r);
    assert_eq!(text(&t, "/third").await, "2 /third");
    assert_eq!(t.streams_opened(), 2);
}

#[tokio::test]
async fn when_the_peer_closes_between_requests_the_next_one_opens_a_stream_once() {
    let fake = node().await;
    let t = tunnel(&fake);
    assert_eq!(text(&t, "/close").await, "1 close");
    // The service closed the connection; give the close time to reach the client.
    tokio::time::sleep(Duration::from_millis(200)).await;
    let before = fake.delivered.lock().unwrap().len();
    assert_eq!(text(&t, "/again").await, "2 /again");
    assert_eq!(t.streams_opened(), 2);
    assert_eq!(fake.opened.lock().unwrap().len(), 2);
    // The second request reached the service once, and only on the new stream.
    assert_eq!(fake.delivered.lock().unwrap().len(), before + 1);
}

#[tokio::test]
async fn a_request_that_failed_after_delivery_is_not_sent_again() {
    let fake = node().await;
    fake.fail_after_request.store(1, Ordering::SeqCst);
    let t = tunnel(&fake);
    let err = tokio::time::timeout(
        Duration::from_secs(10),
        t.request("POST", "/once", &[], b"payload".to_vec()),
    )
    .await
    .expect("no answer")
    .unwrap_err();
    assert!(
        matches!(&err, HttpTunnelError::Tunnel(m) if m.contains("Unavailable")),
        "{err:?}"
    );
    // Wait longer than the first retry wait: nothing else may come.
    tokio::time::sleep(Duration::from_millis(600)).await;
    assert_eq!(fake.opened.lock().unwrap().len(), 1);
    assert_eq!(fake.delivered.lock().unwrap().len(), 1);
    // The next request is a new one, on a new stream.
    assert_eq!(text(&t, "/fine").await, "1 /fine");
    assert_eq!(fake.opened.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn a_stream_that_failed_to_open_is_opened_again_and_the_request_is_delivered_once() {
    let fake = node().await;
    fake.unreachable.store(2, Ordering::SeqCst);
    let t = tunnel(&fake);
    assert_eq!(text(&t, "/retry").await, "1 /retry");
    assert_eq!(fake.opened.lock().unwrap().len(), 3);
    assert_eq!(t.streams_opened(), 3);
    assert_eq!(fake.delivered.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn a_node_that_stays_unreachable_fails_after_the_retries() {
    let fake = node().await;
    fake.unreachable.store(100, Ordering::SeqCst);
    let t = tunnel(&fake);
    let err = tokio::time::timeout(Duration::from_secs(10), t.request("GET", "/", &[], vec![]))
        .await
        .expect("hung")
        .unwrap_err();
    assert!(
        matches!(&err, HttpTunnelError::Tunnel(m) if m.contains("no route")),
        "{err:?}"
    );
    // The first open and three retries.
    assert_eq!(fake.opened.lock().unwrap().len(), 4);
    assert!(fake.delivered.lock().unwrap().is_empty());
}

#[tokio::test]
async fn an_answer_over_the_limit_is_an_error() {
    let fake = node().await;
    let t = HttpTunnel::with_limits(fake.clone(), "tok".into(), 3030, None, short_limits());
    // Content-Length 1000, limit 500: refused from the head.
    let err = t.request("GET", "/big", &[], vec![]).await.unwrap_err();
    assert!(
        matches!(err, HttpTunnelError::BodyTooLarge { limit: 500 }),
        "{err:?}"
    );
    // Chunked, 1000 bytes in pieces of 100: refused when the limit is passed.
    let err = t
        .request("GET", "/bigchunked", &[], vec![])
        .await
        .unwrap_err();
    assert!(
        matches!(err, HttpTunnelError::BodyTooLarge { limit: 500 }),
        "{err:?}"
    );
    // The client still works after the errors.
    assert_eq!(text(&t, "/small").await, "3 /small");
}

#[tokio::test]
async fn a_stalled_peer_times_out() {
    let fake = node().await;
    let t = HttpTunnel::with_limits(fake.clone(), "tok".into(), 3030, None, short_limits());
    let started = std::time::Instant::now();
    let err = tokio::time::timeout(
        Duration::from_secs(10),
        t.request("GET", "/stall", &[], vec![]),
    )
    .await
    .expect("the request hung")
    .unwrap_err();
    assert!(matches!(err, HttpTunnelError::Timeout(_)), "{err:?}");
    assert!(started.elapsed() < Duration::from_secs(5));
    // The request was delivered and is not sent again; the next one uses a new stream.
    assert_eq!(fake.delivered.lock().unwrap().len(), 1);
    assert_eq!(text(&t, "/ok").await, "2 /ok");
}

#[tokio::test]
async fn invalid_requests_are_refused_before_any_stream_opens() {
    let fake = node().await;
    let t = tunnel(&fake);
    for (m, p) in [
        ("GET", "hello"),
        ("GET", "http://other/x"),
        ("BAD METHOD", "/"),
    ] {
        let err = t.request(m, p, &[], vec![]).await.unwrap_err();
        assert!(
            matches!(err, HttpTunnelError::InvalidRequest(_)),
            "{m} {p}: {err:?}"
        );
    }
    assert_eq!(t.streams_opened(), 0);
}
