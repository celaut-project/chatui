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
//! A port can have a secret ([`LocalPort::bind_secured`]). Then each connection must
//! start with the bytes of the secret, which the relay takes off and checks before it
//! opens a stream: a connection that starts with anything else, that sends less, or that
//! waits more than [`AUTH_TIMEOUT`] is closed and opens nothing (the node charges
//! nothing). On a phone, loopback is shared by all the apps, so this keeps another app
//! from using the stream of the instance. A port without a secret relays every
//! connection, as before.
//!
//! The receipts of each stream go to the [`ReceiptSink`] of the port, if it has one.

use std::collections::VecDeque;
use std::net::{Ipv4Addr, SocketAddr};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use celaut_wire::tunnel::MAX_PAYLOAD;
use celaut_wire::{ReceiptSink, Tunnel, TunnelOpener};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio::task::{JoinHandle, JoinSet};

/// A random secret for [`LocalPort::bind_secured`]: 64 hex characters (256 bits).
pub fn new_secret() -> String {
    let mut bytes = [0u8; 32];
    ring::rand::SecureRandom::fill(&ring::rand::SystemRandom::new(), &mut bytes)
        .expect("the system has no random source");
    hex::encode(bytes)
}

/// How long a connection of a secured port has to send its secret.
pub const AUTH_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(5);

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
    /// The bytes that each connection must start with, if the port has a secret.
    secret: Option<Vec<u8>>,
}

impl std::fmt::Debug for Target {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Target")
            .field("slot", &self.slot)
            .finish_non_exhaustive()
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
        Self::bind_secured(opener, token, slot, receipts, preferred, None).await
    }

    /// Like [`LocalPort::bind_preferred`], but with a `secret` (see [`new_secret`]): each
    /// connection must start with its bytes, or it is closed without opening a stream.
    /// An empty secret is the same as none.
    pub async fn bind_secured(
        opener: Arc<dyn TunnelOpener>,
        token: String,
        slot: u16,
        receipts: Option<ReceiptSink>,
        preferred: Option<u16>,
        secret: Option<String>,
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
            secret: secret.filter(|s| !s.is_empty()).map(String::into_bytes),
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

/// How many times a stream that failed to open is opened again.
const OPEN_RETRIES: u32 = 3;
/// The most bytes kept to send again to a new stream. A request longer than this (an
/// upload) is not sent again: its start is gone.
const REPLAY_LIMIT: usize = 1 << 20;

/// An error of the open of a stream that says nothing reached the service: no connection
/// to the node (a broken link, a circuit of Tor that died), or a node that is
/// unavailable. A refusal (wrong token, no balance) is not one: it would fail again.
fn is_transient(error: &celaut_wire::WireError) -> bool {
    use celaut_wire::WireError;
    match error {
        WireError::Connect(_) | WireError::Timeout => true,
        WireError::Call(text) => {
            text.starts_with("Unavailable") || text.starts_with("Unknown: transport")
        }
        _ => false,
    }
}

/// Equal slices of the same length, in a time that does not depend on where they differ.
fn same(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |d, (x, y)| d | (x ^ y)) == 0
}

/// Read the secret from the start of the connection. True if it came whole and equal;
/// what came after it is left in `rest`. False on the first byte that differs, or if
/// the connection ends first.
async fn read_secret(
    reader: &mut tokio::net::tcp::OwnedReadHalf,
    secret: &[u8],
    buffer: &mut [u8],
    rest: &mut Vec<u8>,
) -> bool {
    let mut got: Vec<u8> = Vec::with_capacity(secret.len());
    while got.len() < secret.len() {
        let n = match reader.read(buffer).await {
            Ok(0) | Err(_) => return false,
            Ok(n) => n,
        };
        got.extend_from_slice(&buffer[..n]);
        let have = got.len().min(secret.len());
        if !same(&got[..have], &secret[..have]) {
            return false;
        }
    }
    rest.extend_from_slice(&got[secret.len()..]);
    true
}

async fn relay(socket: TcpStream, target: Arc<Target>, shared: Arc<Shared>) {
    let (mut reader, mut writer) = socket.into_split();
    let mut buffer = vec![0u8; MAX_PAYLOAD];
    // The stream opens (and the node charges it) when the first bytes come. A connection
    // that closes before that never opens one.
    let mut first_chunk = Vec::new();
    // On a secured port the connection starts with the secret: take it off and check it
    // before anything else.
    if let Some(secret) = &target.secret {
        let checked = tokio::time::timeout(
            AUTH_TIMEOUT,
            read_secret(&mut reader, secret, &mut buffer, &mut first_chunk),
        )
        .await;
        if !matches!(checked, Ok(true)) {
            return;
        }
    }
    // The bytes after the secret may already be in `first_chunk`.
    if first_chunk.is_empty() {
        match reader.read(&mut buffer).await {
            Ok(0) | Err(_) => return,
            Ok(n) => first_chunk.extend_from_slice(&buffer[..n]),
        }
    }
    shared.streams.fetch_add(1, Ordering::Relaxed);
    let Tunnel {
        to_service,
        mut from_service,
    } = target.open();
    let mut to_service = Some(to_service);

    // The local reader feeds this channel, so that the loop below can open the stream
    // again (a node that cannot be reached right now) and send what was read.
    let (up_tx, mut up_rx) = mpsc::channel::<Vec<u8>>(4);
    // Aborted when the relay ends or is aborted (the port is dropped).
    let _up = AbortOnDrop(tokio::spawn(async move {
        loop {
            match reader.read(&mut buffer).await {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    if up_tx.send(buffer[..n].to_vec()).await.is_err() {
                        break;
                    }
                }
            }
        }
        // `up_tx` is dropped here: the end of the local data.
    }));

    // What waits to go to the stream.
    let mut queue: VecDeque<Vec<u8>> = VecDeque::new();
    queue.push_back(first_chunk);
    // What went since the stream opened, while no byte came back: to send again.
    let mut replay: Vec<Vec<u8>> = Vec::new();
    let mut replay_bytes = 0usize;
    let mut replayable = true;
    let mut local_ended = false;
    let mut answered = false;
    let mut retries = 0u32;

    loop {
        // The end of the local data half-closes the stream, once all has been sent.
        if local_ended && queue.is_empty() {
            to_service = None;
        }
        // A clone for the wait for room: the select must not borrow `to_service`.
        let room = to_service.clone().filter(|_| !queue.is_empty());
        let has_room = room.is_some();
        tokio::select! {
            chunk = up_rx.recv(), if !local_ended && queue.len() < 4 => match chunk {
                Some(chunk) => queue.push_back(chunk),
                None => local_ended = true,
            },
            permit = async {
                match room {
                    Some(room) => room.reserve_owned().await,
                    None => std::future::pending().await,
                }
            }, if has_room => {
                let Ok(permit) = permit else {
                    // The stream is closed: its error, if any, comes from the other side.
                    queue.clear();
                    to_service = None;
                    continue;
                };
                let chunk = queue.pop_front().unwrap_or_default();
                if !answered {
                    replay_bytes += chunk.len();
                    if replay_bytes > REPLAY_LIMIT {
                        replayable = false;
                        replay.clear();
                    } else {
                        replay.push(chunk.clone());
                    }
                }
                let _ = permit.send(chunk);
            }
            item = from_service.recv() => match item {
                Some(Ok(data)) => {
                    answered = true;
                    replay.clear();
                    if writer.write_all(&data).await.is_err() {
                        break;
                    }
                }
                Some(Err(e)) => {
                    if !answered && replayable && retries < OPEN_RETRIES && is_transient(&e) {
                        retries += 1;
                        // A short wait, longer each time: the link may be coming back.
                        tokio::time::sleep(std::time::Duration::from_millis(250 * u64::from(retries))).await;
                        let tunnel = target.open();
                        from_service = tunnel.from_service;
                        to_service = Some(tunnel.to_service);
                        // What was sent goes first, then what waited.
                        let mut again: VecDeque<Vec<u8>> = std::mem::take(&mut replay).into();
                        again.append(&mut queue);
                        queue = again;
                        replay_bytes = 0;
                        continue;
                    }
                    if let Ok(mut last) = shared.last_error.lock() {
                        *last = Some(e.to_string());
                    }
                    break;
                }
                None => break,
            },
        }
    }
    // The stream ended. The end of the relay stops the reading too, which closes the
    // local connection.
    let _ = writer.shutdown().await;
}
