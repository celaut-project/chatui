//! The last Peer advertisement that the client accepted from each node.
//!
//! The Peer carries a `ts`. A node that tells us an older `ts` is replaying an old
//! message, and we refuse it. The state is small: the `ts` and the content digest per
//! `peer_id`.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Mutex, PoisonError};

use serde::{Deserialize, Serialize};

/// What the client remembers about the last accepted Peer of one node.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Seen {
    /// `Peer.ts` of the message.
    pub ts: i64,
    /// Its content digest (lowercase hex). With an equal `ts`, the same digest is the
    /// same message again (see [`crate::peer::check_ts`]).
    pub digest: String,
}

/// The storage failed.
#[derive(Debug, thiserror::Error)]
#[error("the peer store failed: {0}")]
pub struct StoreError(pub String);

/// Where the last accepted advertisement of each node is kept.
pub trait PeerStore: Send + Sync {
    /// The last accepted advertisement of `peer_id`.
    fn get(&self, peer_id: &str) -> Result<Option<Seen>, StoreError>;
    /// Remember `seen` for `peer_id`. An older `ts` than the stored one is ignored.
    fn put(&self, peer_id: &str, seen: Seen) -> Result<(), StoreError>;
}

/// A store in memory. It is empty after a restart.
#[derive(Debug, Default)]
pub struct MemoryPeerStore {
    peers: Mutex<BTreeMap<String, Seen>>,
}

impl MemoryPeerStore {
    /// An empty store.
    pub fn new() -> Self {
        Self::default()
    }
}

impl PeerStore for MemoryPeerStore {
    fn get(&self, peer_id: &str) -> Result<Option<Seen>, StoreError> {
        let peers = self.peers.lock().unwrap_or_else(PoisonError::into_inner);
        Ok(peers.get(peer_id).cloned())
    }

    fn put(&self, peer_id: &str, seen: Seen) -> Result<(), StoreError> {
        let mut peers = self.peers.lock().unwrap_or_else(PoisonError::into_inner);
        keep_newer(&mut peers, peer_id, seen);
        Ok(())
    }
}

pub(crate) fn keep_newer(peers: &mut BTreeMap<String, Seen>, peer_id: &str, seen: Seen) {
    match peers.get(peer_id) {
        Some(old) if old.ts > seen.ts => {}
        _ => {
            peers.insert(peer_id.to_string(), seen);
        }
    }
}

/// A store in one JSON file. A write goes to a temporary file first and then replaces
/// the file, so a stop in the middle leaves the old file.
///
/// The file is not secret. A file that exists but is not valid is an error: the
/// client does not forget the old `ts` values silently. The user can delete the file.
#[derive(Debug)]
pub struct FilePeerStore {
    path: PathBuf,
    lock: Mutex<()>,
}

impl FilePeerStore {
    /// A store in `path`. The file is made on the first `put`.
    pub fn new(path: impl Into<PathBuf>) -> Self {
        FilePeerStore {
            path: path.into(),
            lock: Mutex::new(()),
        }
    }

    fn read(&self) -> Result<BTreeMap<String, Seen>, StoreError> {
        match std::fs::read(&self.path) {
            Ok(bytes) => serde_json::from_slice(&bytes)
                .map_err(|e| StoreError(format!("{} is not valid: {e}", self.path.display()))),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(BTreeMap::new()),
            Err(e) => Err(StoreError(format!("{}: {e}", self.path.display()))),
        }
    }
}

impl PeerStore for FilePeerStore {
    fn get(&self, peer_id: &str) -> Result<Option<Seen>, StoreError> {
        let _guard = self.lock.lock().unwrap_or_else(PoisonError::into_inner);
        Ok(self.read()?.get(peer_id).cloned())
    }

    fn put(&self, peer_id: &str, seen: Seen) -> Result<(), StoreError> {
        let _guard = self.lock.lock().unwrap_or_else(PoisonError::into_inner);
        let mut peers = self.read()?;
        keep_newer(&mut peers, peer_id, seen);
        let bytes = serde_json::to_vec_pretty(&peers).map_err(|e| StoreError(e.to_string()))?;
        let mut temporary = self.path.clone().into_os_string();
        temporary.push(".tmp");
        let temporary = PathBuf::from(temporary);
        let io = |e: std::io::Error| StoreError(format!("{}: {e}", self.path.display()));
        std::fs::write(&temporary, bytes).map_err(io)?;
        std::fs::rename(&temporary, &self.path).map_err(io)
    }
}
