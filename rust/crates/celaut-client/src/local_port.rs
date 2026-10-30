//! A TCP port on 127.0.0.1 for one port of an instance.
//!
//! Each TCP connection to the local port opens one `ServiceTunnel` stream and relays
//! the bytes both ways. The node charges `TUNNEL_OPEN_MU` for each stream, so the
//! caller keeps its connections alive (HTTP keep-alive) and does not open one per
//! request. The stream opens with the first bytes of the connection, not with the
//! connection: a browser opens spare connections that never send, and those cost
//! nothing.
//!
//! The end of the data from the local connection half-closes the stream, and the end
//! of the stream closes the local connection. An error of the stream (for example a
//! refusal of the node) closes the local connection and is kept in
//! [`LocalPort::last_error`].
//!
//! The receipts of each stream go to the [`ReceiptSink`] of the port, if it has one.

use std::net::{Ipv4Addr, SocketAddr};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use celaut_wire::tunnel::MAX_PAYLOAD;
use celaut_wire::{ReceiptSink, Tunnel, TunnelOpener};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::{JoinHandle, JoinSet};

#[derive(Debug, Default)]
struct Shared {
    streams: AtomicU64,
    last_error: Mutex<Option<String>>,
}

/// What a connection needs to open its stream. The opener can be replaced while the port
/// stays (see [`LocalPort::set_opener`]).
struct Target {
    opener: Mutex<Arc<dyn TunnelOpener>>,
    token: String,
    slot: u16,
    receipts: Option<ReceiptSink>,
}

impl std::fmt::Debug for Target {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Target").field("slot", &self.slot).finish_non_exhaustive()
    }
}

impl Target {
    fn open(&self) -> Tunnel {
        let opener = self
            .opener
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        opener.open_tunnel(&self.token, self.slot, self.receipts.clone())
    }
}

/// A local port for one slot of one instance. Dropping it closes the port and every
/// connection on it.
#[derive(Debug)]
pub struct LocalPort {
    port: u16,
    shared: Arc<Shared>,
    target: Arc<Target>,
    task: JoinHandle<()>,
}

impl LocalPort {
    /// Listen on `127.0.0.1` and a free port. The receipts of the streams go to
    /// `receipts`. Must be called inside a Tokio runtime.
    pub async fn bind(
        opener: Arc<dyn TunnelOpener>,
        token: String,
        slot: u16,
        receipts: Option<ReceiptSink>,
    ) -> std::io::Result<LocalPort> {
        Self::bind_preferred(opener, token, slot, receipts, None).await
    }

    /// Like [`LocalPort::bind`], but tries `preferred` first, and takes a free port if
    /// that one is taken. The same port each time keeps the origin of a web page (its
    /// cookies and its local storage) from one start to the next.
    pub async fn bind_preferred(
        opener: Arc<dyn TunnelOpener>,
        token: String,
        slot: u16,
        receipts: Option<ReceiptSink>,
        preferred: Option<u16>,
    ) -> std::io::Result<LocalPort> {
        let listener = match preferred {
            Some(p) => match TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, p))).await {
                Ok(listener) => listener,
                Err(_) => TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, 0))).await?,
            },
            None => TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, 0))).await?,
        };
        let port = listener.local_addr()?.port();
        let shared = Arc::new(Shared::default());
        let target = Arc::new(Target {
            opener: Mutex::new(opener),
            token,
            slot,
            receipts,
        });
        let task = tokio::spawn(accept(listener, target.clone(), shared.clone()));
        Ok(LocalPort {
            port,
            shared,
            target,
            task,
        })
    }

    /// Open the next streams with `opener` (a new connection to the node, after the old
    /// one broke). The connections that are open keep their streams. The last error is
    /// cleared: it was of the old opener.
    pub fn set_opener(&self, opener: Arc<dyn TunnelOpener>) {
        *self.target.opener.lock().unwrap_or_else(|e| e.into_inner()) = opener;
        if let Ok(mut last) = self.shared.last_error.lock() {
            *last = None;
        }
    }

    /// False if the task of the port ended, so that the port accepts nothing.
    pub fn is_alive(&self) -> bool {
        !self.task.is_finished()
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

async fn accept(listener: TcpListener, target: Arc<Target>, shared: Arc<Shared>) {
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
                connections.spawn(relay(socket, target.clone(), shared.clone()));
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

async fn relay(socket: TcpStream, target: Arc<Target>, shared: Arc<Shared>) {
    let (mut reader, mut writer) = socket.into_split();
    let mut buffer = vec![0u8; MAX_PAYLOAD];
    // The stream opens (and the node charges it) when the first bytes come. A connection
    // that closes before that never opens one.
    let first = match reader.read(&mut buffer).await {
        Ok(0) | Err(_) => return,
        Ok(n) => n,
    };
    shared.streams.fetch_add(1, Ordering::Relaxed);
    let Tunnel {
        to_service,
        mut from_service,
    } = target.open();
    if to_service.send(buffer[..first].to_vec()).await.is_err() {
        return;
    }
    // Aborted when the relay ends or is aborted (the port is dropped).
    let _up = AbortOnDrop(tokio::spawn(async move {
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
