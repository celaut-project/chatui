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
}

impl TunnelOpener for FakeNode {
    fn open_tunnel(&self, token: &str, slot: u16) -> Tunnel {
        self.opened.lock().unwrap().push((token.to_string(), slot));
        let (to_service, mut to_rx) = mpsc::channel::<Vec<u8>>(16);
        let (from_tx, from_service) = mpsc::channel(16);
        let port = self.server_port;
        let refuse = self.refuse.clone();
        tokio::spawn(async move {
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
    let local = LocalPort::bind(fake.clone(), "tok".into(), 3030)
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
    let local = LocalPort::bind(fake, "tok".into(), 3030).await.unwrap();
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
    let local = LocalPort::bind(fake, "bad".into(), 3030).await.unwrap();
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
    let local = LocalPort::bind(fake, "tok".into(), 3030).await.unwrap();
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
