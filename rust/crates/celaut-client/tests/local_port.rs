//! The local port: one `ServiceTunnel` stream per TCP connection, so HTTP keep-alive
//! pays one tunnel open for many requests. The tunnels here go to a small HTTP/1.1
//! server in the test instead of a node.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use celaut_client::LocalPort;
use celaut_wire::{Tunnel, TunnelOpener, WireError};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;

/// An HTTP/1.1 server that keeps connections alive and answers each request with
/// `<connection number> <path>`. Gives its port.
async fn http_server() -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let count = Arc::new(AtomicUsize::new(0));
    tokio::spawn(async move {
        loop {
            let (socket, _) = listener.accept().await.unwrap();
            let n = count.fetch_add(1, Ordering::SeqCst) + 1;
            tokio::spawn(async move {
                let (reader, mut writer) = socket.into_split();
                let mut lines = BufReader::new(reader).lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    let path = line.split(' ').nth(1).unwrap_or("?").to_string();
                    // Skip the headers.
                    while let Ok(Some(header)) = lines.next_line().await {
                        if header.is_empty() {
                            break;
                        }
                    }
                    let body = format!("{n} {path}");
                    let reply = format!(
                        "HTTP/1.1 200 OK\r\ncontent-length: {}\r\n\r\n{body}",
                        body.len()
                    );
                    if writer.write_all(reply.as_bytes()).await.is_err() {
                        return;
                    }
                }
                // The client half-closed: close too.
                let _ = writer.shutdown().await;
            });
        }
    });
    port
}

/// Opens each tunnel as a TCP connection to a local server, and records the opens.
struct FakeNode {
    server_port: u16,
    opened: Mutex<Vec<(String, u16)>>,
    /// When set, every tunnel fails with this text, as a refusal of the node.
    refuse: Option<String>,
    /// How many of the first opens fail with "cannot connect", as a node that cannot be
    /// reached for a moment.
    unreachable: AtomicUsize,
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
        let refuse = self.refuse.clone();
        let unreachable = self
            .unreachable
            .try_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
            .is_ok();
        tokio::spawn(async move {
            if unreachable {
                let _ = from_tx
                    .send(Err(WireError::Connect("no route".to_string())))
                    .await;
                return;
            }
            if let Some(text) = refuse {
                let _ = from_tx.send(Err(WireError::Call(text))).await;
                return;
            }
            let socket = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
            let (mut reader, mut writer) = socket.into_split();
            tokio::spawn(async move {
                while let Some(data) = to_rx.recv().await {
                    writer.write_all(&data).await.unwrap();
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

async fn node(refuse: Option<&str>) -> Arc<FakeNode> {
    Arc::new(FakeNode {
        server_port: http_server().await,
        opened: Mutex::new(Vec::new()),
        refuse: refuse.map(str::to_string),
        unreachable: AtomicUsize::new(0),
    })
}

/// Send one GET on `socket` and read one response (headers and body).
async fn get(socket: &mut BufReader<TcpStream>, path: &str) -> String {
    let request = format!("GET {path} HTTP/1.1\r\nhost: localhost\r\n\r\n");
    socket
        .get_mut()
        .write_all(request.as_bytes())
        .await
        .unwrap();
    let mut length = 0;
    loop {
        let mut line = String::new();
        socket.read_line(&mut line).await.unwrap();
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some(value) = line.strip_prefix("content-length: ") {
            length = value.parse().unwrap();
        }
    }
    let mut body = vec![0u8; length];
    socket.read_exact(&mut body).await.unwrap();
    String::from_utf8(body).unwrap()
}

async fn connect(port: u16) -> BufReader<TcpStream> {
    BufReader::new(TcpStream::connect(("127.0.0.1", port)).await.unwrap())
}

#[tokio::test]
async fn keep_alive_uses_one_stream_for_many_requests() {
    let fake = node(None).await;
    let local = LocalPort::bind(fake.clone(), "tok".into(), 3030, None)
        .await
        .unwrap();

    let mut socket = connect(local.port()).await;
    assert_eq!(get(&mut socket, "/").await, "1 /");
    assert_eq!(get(&mut socket, "/whoami").await, "1 /whoami");
    assert_eq!(get(&mut socket, "/again").await, "1 /again");
    // Three requests, one TCP connection, one tunnel open.
    assert_eq!(local.streams_opened(), 1);
    assert_eq!(
        *fake.opened.lock().unwrap(),
        vec![("tok".to_string(), 3030)]
    );

    // A second connection is a second stream (and a second open fee on a node).
    let mut other = connect(local.port()).await;
    assert_eq!(get(&mut other, "/").await, "2 /");
    assert_eq!(local.streams_opened(), 2);
    assert_eq!(local.last_error(), None);
}

#[tokio::test]
async fn a_half_close_reaches_the_service() {
    let fake = node(None).await;
    let local = LocalPort::bind(fake, "tok".into(), 3030, None)
        .await
        .unwrap();
    let mut socket = TcpStream::connect(("127.0.0.1", local.port()))
        .await
        .unwrap();
    socket
        .write_all(b"GET /last HTTP/1.1\r\n\r\n")
        .await
        .unwrap();
    socket.shutdown().await.unwrap();
    // The service answers, sees the end and closes: the whole answer, then EOF.
    let mut all = String::new();
    tokio::time::timeout(Duration::from_secs(5), socket.read_to_string(&mut all))
        .await
        .expect("the local connection was not closed")
        .unwrap();
    assert!(all.ends_with("1 /last"), "{all:?}");
}

#[tokio::test]
async fn a_refusal_closes_the_connection_and_is_kept() {
    let fake = node(Some("InvalidArgument: no local instance")).await;
    let local = LocalPort::bind(fake, "bad".into(), 3030, None)
        .await
        .unwrap();
    let mut socket = TcpStream::connect(("127.0.0.1", local.port()))
        .await
        .unwrap();
    socket.write_all(b"GET / HTTP/1.1\r\n\r\n").await.unwrap();
    let mut all = Vec::new();
    let read = tokio::time::timeout(Duration::from_secs(5), socket.read_to_end(&mut all))
        .await
        .expect("the local connection was not closed");
    // Closed with no answer: an end of stream, or a reset when the request was not
    // read yet.
    match read {
        Ok(_) => assert!(all.is_empty()),
        Err(e) => assert_eq!(e.kind(), std::io::ErrorKind::ConnectionReset),
    }
    assert!(local.last_error().unwrap().contains("no local instance"));
}

#[tokio::test]
async fn dropping_the_port_closes_it() {
    let fake = node(None).await;
    let local = LocalPort::bind(fake, "tok".into(), 3030, None)
        .await
        .unwrap();
    let port = local.port();
    let mut socket = connect(port).await;
    assert_eq!(get(&mut socket, "/").await, "1 /");
    drop(local);
    tokio::time::sleep(Duration::from_millis(100)).await;
    // The open connection is closed, and the port accepts no new one.
    let mut rest = Vec::new();
    let n = tokio::time::timeout(Duration::from_secs(5), socket.read_to_end(&mut rest))
        .await
        .expect("the connection stayed open");
    assert!(n.map(|n| n == 0).unwrap_or(true));
    assert!(TcpStream::connect(("127.0.0.1", port)).await.is_err());
}

#[tokio::test]
async fn a_connection_that_sends_nothing_opens_no_stream() {
    let fake = node(None).await;
    let local = LocalPort::bind(fake.clone(), "tok".into(), 3030, None)
        .await
        .unwrap();
    // A spare connection, as a browser opens: it never sends and then closes.
    let spare = TcpStream::connect(("127.0.0.1", local.port()))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;
    drop(spare);
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(local.streams_opened(), 0);
    assert!(fake.opened.lock().unwrap().is_empty());
    // A connection that sends opens one.
    let mut socket = connect(local.port()).await;
    assert_eq!(get(&mut socket, "/").await, "1 /");
    assert_eq!(local.streams_opened(), 1);
}

#[tokio::test]
async fn the_preferred_port_is_used_when_free_and_not_when_taken() {
    let fake = node(None).await;
    let first = LocalPort::bind(fake.clone(), "tok".into(), 3030, None)
        .await
        .unwrap();
    let taken = first.port();
    // The port is taken: another one is used.
    let second = LocalPort::bind_preferred(fake.clone(), "tok".into(), 3030, None, Some(taken))
        .await
        .unwrap();
    assert_ne!(second.port(), taken);
    // Free again: the same port comes back.
    drop(first);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let third = LocalPort::bind_preferred(fake, "tok".into(), 3030, None, Some(taken))
        .await
        .unwrap();
    assert_eq!(third.port(), taken);
}

#[tokio::test]
async fn a_new_opener_serves_the_next_connections_and_clears_the_error() {
    let refusing = node(Some("Unavailable: the node went away")).await;
    let local = LocalPort::bind(refusing, "tok".into(), 3030, None)
        .await
        .unwrap();
    let mut socket = TcpStream::connect(("127.0.0.1", local.port()))
        .await
        .unwrap();
    socket.write_all(b"GET / HTTP/1.1\r\n\r\n").await.unwrap();
    let mut all = Vec::new();
    let _ = tokio::time::timeout(Duration::from_secs(5), socket.read_to_end(&mut all)).await;
    assert!(local.last_error().is_some());
    assert!(local.is_alive());

    let port = local.port();
    local.set_opener(node(None).await);
    assert_eq!(local.last_error(), None);
    let mut again = connect(port).await;
    assert_eq!(get(&mut again, "/").await, "1 /");
}

#[tokio::test]
async fn a_stream_that_cannot_reach_the_node_is_opened_again_with_the_same_bytes() {
    let fake = node(None).await;
    // The first two opens fail before any byte comes back.
    fake.unreachable.store(2, Ordering::SeqCst);
    let local = LocalPort::bind(fake.clone(), "tok".into(), 3030, None)
        .await
        .unwrap();
    let mut socket = connect(local.port()).await;
    // The browser sees no error: the request is sent again to the third stream.
    let answer = tokio::time::timeout(Duration::from_secs(10), get(&mut socket, "/retry"))
        .await
        .expect("no answer after the retries");
    assert_eq!(answer, "1 /retry");
    assert_eq!(fake.opened.lock().unwrap().len(), 3);
    assert_eq!(local.last_error(), None);
    // The connection is still good for the next request.
    assert_eq!(get(&mut socket, "/next").await, "1 /next");
}

#[tokio::test]
async fn a_node_that_stays_unreachable_ends_the_connection_after_the_retries() {
    let fake = node(None).await;
    fake.unreachable.store(100, Ordering::SeqCst);
    let local = LocalPort::bind(fake.clone(), "tok".into(), 3030, None)
        .await
        .unwrap();
    let mut socket = TcpStream::connect(("127.0.0.1", local.port()))
        .await
        .unwrap();
    socket.write_all(b"GET / HTTP/1.1\r\n\r\n").await.unwrap();
    let mut all = Vec::new();
    let _ = tokio::time::timeout(Duration::from_secs(10), socket.read_to_end(&mut all))
        .await
        .expect("the local connection was not closed");
    assert!(all.is_empty());
    // The first open and three retries.
    assert_eq!(fake.opened.lock().unwrap().len(), 4);
    assert!(local.last_error().unwrap().contains("no route"));
}

/// A secured port, and the secret of it.
async fn secured(fake: Arc<FakeNode>) -> (LocalPort, String) {
    let secret = celaut_client::new_secret();
    let local = LocalPort::bind_secured(fake, "tok".into(), 3030, None, None, Some(secret.clone()))
        .await
        .unwrap();
    (local, secret)
}

/// True if the connection is closed by the relay (EOF or reset) within a few seconds.
async fn is_closed(socket: &mut TcpStream) -> bool {
    let mut byte = [0u8; 1];
    match tokio::time::timeout(Duration::from_secs(5), socket.read(&mut byte)).await {
        Ok(Ok(0)) | Ok(Err(_)) => true,
        _ => false,
    }
}

#[tokio::test]
async fn a_secured_port_relays_a_connection_that_starts_with_the_secret() {
    let fake = node(None).await;
    let (local, secret) = secured(fake.clone()).await;
    assert_eq!(secret.len(), 64);

    let mut socket = connect(local.port()).await;
    socket.get_mut().write_all(secret.as_bytes()).await.unwrap();
    assert_eq!(get(&mut socket, "/hello").await, "1 /hello");
    assert_eq!(get(&mut socket, "/again").await, "1 /again");
    assert_eq!(local.streams_opened(), 1);

    // The secret and the first request can also come in one write.
    let mut other = connect(local.port()).await;
    let request = format!("{secret}GET /one HTTP/1.1\r\nhost: localhost\r\n\r\n");
    other.get_mut().write_all(request.as_bytes()).await.unwrap();
    let mut line = String::new();
    other.read_line(&mut line).await.unwrap();
    assert!(line.starts_with("HTTP/1.1 200"), "{line}");
    assert_eq!(local.streams_opened(), 2);
}

#[tokio::test]
async fn a_secured_port_closes_a_connection_without_the_secret_and_opens_no_stream() {
    let fake = node(None).await;
    let (local, _secret) = secured(fake.clone()).await;

    // A plain request, as another app would send.
    let mut socket = TcpStream::connect(("127.0.0.1", local.port())).await.unwrap();
    socket
        .write_all(b"GET / HTTP/1.1\r\nhost: localhost\r\n\r\n")
        .await
        .unwrap();
    assert!(is_closed(&mut socket).await);

    // The HTTP/2 preface of a gRPC client.
    let mut grpc = TcpStream::connect(("127.0.0.1", local.port())).await.unwrap();
    grpc.write_all(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n").await.unwrap();
    assert!(is_closed(&mut grpc).await);

    assert_eq!(local.streams_opened(), 0);
    assert!(fake.opened.lock().unwrap().is_empty());
}

#[tokio::test]
async fn a_secured_port_rejects_a_wrong_or_short_secret_and_opens_no_stream() {
    let fake = node(None).await;
    let (local, secret) = secured(fake.clone()).await;

    // Same length, one byte different.
    let mut wrong = secret.clone().into_bytes();
    wrong[63] = if wrong[63] == b'0' { b'1' } else { b'0' };
    let mut a = TcpStream::connect(("127.0.0.1", local.port())).await.unwrap();
    a.write_all(&wrong).await.unwrap();
    a.write_all(b"GET / HTTP/1.1\r\n\r\n").await.unwrap();
    assert!(is_closed(&mut a).await);

    // The right start, then the end of the connection before the secret is whole.
    let mut b = TcpStream::connect(("127.0.0.1", local.port())).await.unwrap();
    b.write_all(&secret.as_bytes()[..40]).await.unwrap();
    b.shutdown().await.unwrap();
    assert!(is_closed(&mut b).await);

    assert_eq!(local.streams_opened(), 0);
    assert!(fake.opened.lock().unwrap().is_empty());

    // The port still serves a connection with the right secret.
    let mut ok = connect(local.port()).await;
    ok.get_mut().write_all(secret.as_bytes()).await.unwrap();
    assert_eq!(get(&mut ok, "/").await, "1 /");
}

#[tokio::test]
async fn a_secured_port_closes_a_connection_that_stalls_before_the_secret() {
    let fake = node(None).await;
    let (local, secret) = secured(fake.clone()).await;
    let mut socket = TcpStream::connect(("127.0.0.1", local.port())).await.unwrap();
    socket.write_all(&secret.as_bytes()[..10]).await.unwrap();
    // No more bytes: the relay gives up after AUTH_TIMEOUT (5 s).
    let mut byte = [0u8; 1];
    let end = tokio::time::timeout(Duration::from_secs(10), socket.read(&mut byte)).await;
    assert!(matches!(end, Ok(Ok(0)) | Ok(Err(_))), "{end:?}");
    assert_eq!(local.streams_opened(), 0);
}

#[tokio::test]
async fn two_secrets_are_different() {
    assert_ne!(celaut_client::new_secret(), celaut_client::new_secret());
}
