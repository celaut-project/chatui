//! A TCP port on 127.0.0.1 for one port of an instance.
//!
//! Each TCP connection to the local port opens one `ServiceTunnel` stream and relays
//! the bytes both ways. The node charges `TUNNEL_OPEN_MU` for each stream, so the
//! caller keeps its connections alive (HTTP keep-alive) and does not open one per
//! request.
//!
//! The end of the data from the local connection half-closes the stream, and the end
//! of the stream closes the local connection. An error of the stream (for example a
//! refusal of the node) closes the local connection and is kept in
//! [`LocalPort::last_error`].

use std::net::{Ipv4Addr, SocketAddr};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use celaut_wire::tunnel::MAX_PAYLOAD;
use celaut_wire::{Tunnel, TunnelOpener};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::{JoinHandle, JoinSet};

#[derive(Debug, Default)]
struct Shared {
    streams: AtomicU64,
    last_error: Mutex<Option<String>>,
}

/// A local port for one slot of one instance. Dropping it closes the port and every
/// connection on it.
#[derive(Debug)]
pub struct LocalPort {
    port: u16,
    shared: Arc<Shared>,
    task: JoinHandle<()>,
}

impl LocalPort {
    /// Listen on `127.0.0.1` and a free port. Must be called inside a Tokio runtime.
    pub async fn bind(
        opener: Arc<dyn TunnelOpener>,
        token: String,
        slot: u16,
    ) -> std::io::Result<LocalPort> {
        let listener = TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, 0))).await?;
        let port = listener.local_addr()?.port();
        let shared = Arc::new(Shared::default());
        let task = tokio::spawn(accept(listener, opener, token, slot, shared.clone()));
        Ok(LocalPort { port, shared, task })
    }

    /// The local port.
    pub fn port(&self) -> u16 {
        self.port
    }

    /// How many `ServiceTunnel` streams this port opened: one per TCP connection.
    pub fn streams_opened(&self) -> u64 {
        self.shared.streams.load(Ordering::Relaxed)
    }

    /// The last error of a stream, if any.
    pub fn last_error(&self) -> Option<String> {
        self.shared.last_error.lock().ok().and_then(|e| e.clone())
    }
}

impl Drop for LocalPort {
    fn drop(&mut self) {
        // The connections are in the JoinSet of the task: they end with it.
        self.task.abort();
    }
}

async fn accept(
    listener: TcpListener,
    opener: Arc<dyn TunnelOpener>,
    token: String,
    slot: u16,
    shared: Arc<Shared>,
) {
    let mut connections = JoinSet::new();
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                let Ok((socket, _)) = accepted else {
                    // For example no file descriptors left: wait a little, do not spin.
                    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                    continue;
                };
                let _ = socket.set_nodelay(true);
                shared.streams.fetch_add(1, Ordering::Relaxed);
                let tunnel = opener.open_tunnel(&token, slot, None);
                connections.spawn(relay(socket, tunnel, shared.clone()));
            }
            // Collect the ended connections, so that the set does not grow.
            Some(_) = connections.join_next(), if !connections.is_empty() => {}
        }
    }
}

/// Aborts a task when dropped.
struct AbortOnDrop(JoinHandle<()>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

async fn relay(socket: TcpStream, tunnel: Tunnel, shared: Arc<Shared>) {
    let (mut reader, mut writer) = socket.into_split();
    let Tunnel {
        to_service,
        mut from_service,
    } = tunnel;
    // Aborted when the relay ends or is aborted (the port is dropped).
    let _up = AbortOnDrop(tokio::spawn(async move {
        let mut buffer = vec![0u8; MAX_PAYLOAD];
        loop {
            match reader.read(&mut buffer).await {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    if to_service.send(buffer[..n].to_vec()).await.is_err() {
                        break;
                    }
                }
            }
        }
        // `to_service` is dropped here: the stream is half-closed.
    }));
    while let Some(item) = from_service.recv().await {
        match item {
            Ok(data) => {
                if writer.write_all(&data).await.is_err() {
                    break;
                }
            }
            Err(e) => {
                if let Ok(mut last) = shared.last_error.lock() {
                    *last = Some(e.to_string());
                }
                break;
            }
        }
    }
    // The stream ended. The end of the relay stops the reading too, which closes the
    // local connection.
    let _ = writer.shutdown().await;
}
