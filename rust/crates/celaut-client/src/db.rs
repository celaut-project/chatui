//! The Celaut database of the app (`docs/celaut/ui.md`, section 1).
//!
//! All the Celaut data of the app is in one database: the client id of each node, the
//! last accepted advertisement of each node, the instances and their tokens, the
//! deposits, the last quotes and the event log of local reputation. There is one
//! database for the whole app, not one per wallet, and no record has a wallet key. A
//! deposit does not record which wallet paid: the transaction id is enough, and the
//! history of the wallet shows the rest.
//!
//! The client ids and the instance tokens are bearer secrets, so the file is encrypted
//! with AES-256-GCM. The key comes from the caller (on Android, the Keystore store of
//! the app). A write goes to a temporary file first and then replaces the file, so a
//! stop in the middle leaves the old file.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, PoisonError};

use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_256_GCM, NONCE_LEN};
use ring::rand::{SecureRandom, SystemRandom};
use serde::{Deserialize, Serialize};

use crate::store::{keep_newer, PeerStore, Seen, StoreError};

/// The version of the content.
pub const DB_VERSION: u32 = 1;

/// The length of the key, in bytes.
pub const KEY_LEN: usize = 32;

/// How many quotes the database keeps. The oldest go first.
pub const MAX_QUOTES: usize = 64;

/// How many events the database keeps. The oldest go first.
pub const MAX_EVENTS: usize = 1024;

const MAGIC: &[u8; 8] = b"CELAUTDB";
const FORMAT: u8 = 1;
const HEADER_LEN: usize = MAGIC.len() + 1;

/// What the app knows about one node. The key is the peer_id, so a node with more than
/// one address is one node.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NodeRecord {
    /// The client id of the app on this node. A bearer secret: the balance of the
    /// client on the node goes with it.
    pub client_id: String,
    /// The addresses (`host:port`) where the app reached this node, the last first.
    #[serde(default)]
    pub addresses: Vec<String>,
    /// The limit of the deposits to this node, in nanoERG, if the user changed it.
    #[serde(default)]
    pub deposit_limit_nano_erg: Option<u64>,
}

/// An instance that the app started. Any full wallet of the app can stop it.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct InstanceRecord {
    /// The node.
    pub peer_id: String,
    /// The address (`host:port`) of the node at the start.
    pub address: String,
    /// The instance token. A bearer secret.
    pub token: String,
    /// The service id, in lowercase hex.
    pub service_id: String,
    /// The internal ports of the instance.
    #[serde(default)]
    pub slots: Vec<u16>,
    /// The time of the start, in Unix seconds.
    pub started_at: i64,
    /// What the start took from the balance of the client, in MU of the node, if the
    /// app could read the balance before and after the start.
    #[serde(default)]
    pub start_charge_mu: Option<String>,
}

/// Where a deposit is.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "stage", rename_all = "snake_case")]
pub enum DepositStage {
    /// The preparation waits for the confirmation of the user.
    Prepared,
    /// The transaction was sent; the box is not yet seen on the explorer.
    Sent { tx_id: String },
    /// `Payable` was called. It is never called again for this deposit.
    PayableCalled { tx_id: String, accepted: bool },
}

/// A deposit to a node. It does not record which wallet paid (`docs/celaut/ui.md`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DepositRecord {
    pub peer_id: String,
    /// The address (`host:port`) of the node when the deposit was made.
    pub address: String,
    /// The deposit token in R4.
    pub deposit_token: String,
    pub nano_erg: u64,
    /// The MU that the amount buys on the node.
    pub mu: String,
    /// The address that receives the deposit.
    pub pay_to_address: String,
    /// The id of the deposit transaction, known before the signature.
    #[serde(default)]
    pub tx_id: String,
    /// The time of the preparation, in Unix seconds.
    pub made_at: i64,
    pub stage: DepositStage,
}

/// The last quote of a node for a service.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuoteRecord {
    pub peer_id: String,
    pub service_id: String,
    /// The cost of the start, in MU of the node.
    pub cost_mu: String,
    /// The time of the quote, in Unix seconds.
    pub at: i64,
}

/// What happened with a node, for the local reputation (`docs/celaut/balancer.md`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventKind {
    /// The node accepted a payment (+10 in nodo).
    PaymentCommunicated,
    /// The node did not accept a payment (−100 in nodo).
    PaymentNotAcknowledged,
}

/// One event of the log.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventRecord {
    pub peer_id: String,
    pub kind: EventKind,
    /// The time, in Unix seconds.
    pub at: i64,
}

/// The content of the database.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CelautData {
    #[serde(default)]
    pub version: u32,
    /// The nodes, by peer_id.
    #[serde(default)]
    pub nodes: BTreeMap<String, NodeRecord>,
    /// The last accepted advertisement of each node, by peer_id.
    #[serde(default)]
    pub seen: BTreeMap<String, Seen>,
    /// The instances that run, by local instance id.
    #[serde(default)]
    pub instances: BTreeMap<String, InstanceRecord>,
    /// The deposits, by local deposit id.
    #[serde(default)]
    pub deposits: BTreeMap<String, DepositRecord>,
    /// The last quotes, the oldest first.
    #[serde(default)]
    pub quotes: Vec<QuoteRecord>,
    /// The event log, the oldest first.
    #[serde(default)]
    pub events: Vec<EventRecord>,
}

impl CelautData {
    /// The nanoERG of the deposits to `peer_id` that count against its limit: every
    /// deposit that was prepared and not cancelled.
    pub fn deposited_nano_erg(&self, peer_id: &str) -> u64 {
        self.deposits
            .values()
            .filter(|d| d.peer_id == peer_id)
            .fold(0u64, |sum, d| sum.saturating_add(d.nano_erg))
    }

    /// Remember the address of a node, the last first.
    pub fn note_address(&mut self, peer_id: &str, address: &str) {
        if let Some(node) = self.nodes.get_mut(peer_id) {
            node.addresses.retain(|a| a != address);
            node.addresses.insert(0, address.to_string());
        }
    }

    /// Add a quote, and drop the oldest ones over [`MAX_QUOTES`].
    pub fn add_quote(&mut self, quote: QuoteRecord) {
        self.quotes
            .retain(|q| !(q.peer_id == quote.peer_id && q.service_id == quote.service_id));
        self.quotes.push(quote);
        let over = self.quotes.len().saturating_sub(MAX_QUOTES);
        self.quotes.drain(..over);
    }

    /// Add an event, and drop the oldest ones over [`MAX_EVENTS`].
    pub fn add_event(&mut self, event: EventRecord) {
        self.events.push(event);
        let over = self.events.len().saturating_sub(MAX_EVENTS);
        self.events.drain(..over);
    }

    /// Add what `other` has and this one does not. An entry of this one wins.
    pub fn merge_missing(&mut self, other: CelautData) {
        for (k, v) in other.nodes {
            self.nodes.entry(k).or_insert(v);
        }
        for (k, v) in other.seen {
            keep_newer(&mut self.seen, &k, v);
        }
        for (k, v) in other.instances {
            self.instances.entry(k).or_insert(v);
        }
        for (k, v) in other.deposits {
            self.deposits.entry(k).or_insert(v);
        }
        for q in other.quotes {
            self.add_quote(q);
        }
        for e in other.events {
            self.add_event(e);
        }
    }
}

/// The database failed.
#[derive(Debug, thiserror::Error)]
pub enum DbError {
    /// The file cannot be read or written.
    #[error("the Celaut database file {path}: {message}")]
    Io { path: String, message: String },
    /// The file exists but this key cannot open it, or it is damaged.
    #[error("the Celaut database file {0} cannot be opened with this key, or it is damaged")]
    Unreadable(String),
    /// The key is not 32 bytes.
    #[error("the key of the Celaut database must be {KEY_LEN} bytes")]
    Key,
    /// No random numbers from the system.
    #[error("the system gave no random numbers")]
    Random,
}

impl From<DbError> for StoreError {
    fn from(e: DbError) -> Self {
        StoreError(e.to_string())
    }
}

struct DbFile {
    path: PathBuf,
    key: LessSafeKey,
}

impl DbFile {
    fn new(path: PathBuf, key: &[u8]) -> Result<Self, DbError> {
        let unbound = UnboundKey::new(&AES_256_GCM, key).map_err(|_| DbError::Key)?;
        Ok(DbFile {
            path,
            key: LessSafeKey::new(unbound),
        })
    }

    fn io(&self, e: impl std::fmt::Display) -> DbError {
        DbError::Io {
            path: self.path.display().to_string(),
            message: e.to_string(),
        }
    }

    fn unreadable(&self) -> DbError {
        DbError::Unreadable(self.path.display().to_string())
    }

    /// The content of the file, or `None` if there is no file.
    fn read(&self) -> Result<Option<CelautData>, DbError> {
        let bytes = match std::fs::read(&self.path) {
            Ok(b) => b,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(self.io(e)),
        };
        if bytes.len() < HEADER_LEN + NONCE_LEN || &bytes[..MAGIC.len()] != MAGIC {
            return Err(self.unreadable());
        }
        if bytes[MAGIC.len()] != FORMAT {
            return Err(self.unreadable());
        }
        let (header, rest) = bytes.split_at(HEADER_LEN);
        let (nonce, sealed) = rest.split_at(NONCE_LEN);
        let nonce = Nonce::try_assume_unique_for_key(nonce).map_err(|_| self.unreadable())?;
        let mut sealed = sealed.to_vec();
        let plain = self
            .key
            .open_in_place(nonce, Aad::from(header), &mut sealed)
            .map_err(|_| self.unreadable())?;
        let data = serde_json::from_slice(plain).map_err(|_| self.unreadable())?;
        Ok(Some(data))
    }

    fn write(&self, data: &CelautData) -> Result<(), DbError> {
        let mut plain = serde_json::to_vec(data).map_err(|e| self.io(e))?;
        let mut nonce = [0u8; NONCE_LEN];
        SystemRandom::new()
            .fill(&mut nonce)
            .map_err(|_| DbError::Random)?;
        let mut header = Vec::with_capacity(HEADER_LEN);
        header.extend_from_slice(MAGIC);
        header.push(FORMAT);
        self.key
            .seal_in_place_append_tag(
                Nonce::assume_unique_for_key(nonce),
                Aad::from(&header[..]),
                &mut plain,
            )
            .map_err(|_| self.io("the encryption failed"))?;
        let mut bytes = header;
        bytes.extend_from_slice(&nonce);
        bytes.extend_from_slice(&plain);

        if let Some(dir) = self.path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| self.io(e))?;
        }
        let mut temporary = self.path.clone().into_os_string();
        temporary.push(".tmp");
        let temporary = PathBuf::from(temporary);
        {
            use std::io::Write;
            let mut file = std::fs::File::create(&temporary).map_err(|e| self.io(e))?;
            file.write_all(&bytes).map_err(|e| self.io(e))?;
            file.sync_all().map_err(|e| self.io(e))?;
        }
        std::fs::rename(&temporary, &self.path).map_err(|e| self.io(e))
    }
}

struct Inner {
    data: CelautData,
    file: Option<DbFile>,
}

/// The Celaut database of the app: in memory, or in one encrypted file.
pub struct CelautDb {
    inner: Mutex<Inner>,
}

impl std::fmt::Debug for CelautDb {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let inner = self.inner.lock().unwrap_or_else(PoisonError::into_inner);
        f.debug_struct("CelautDb")
            .field("path", &inner.file.as_ref().map(|f| f.path.clone()))
            .finish_non_exhaustive()
    }
}

impl Default for CelautDb {
    fn default() -> Self {
        Self::in_memory()
    }
}

impl CelautDb {
    /// A database in memory. It is empty after a restart.
    pub fn in_memory() -> Self {
        CelautDb {
            inner: Mutex::new(Inner {
                data: CelautData {
                    version: DB_VERSION,
                    ..Default::default()
                },
                file: None,
            }),
        }
    }

    /// The database in the file `path`, encrypted with `key`. The file is made on the
    /// first change. A file that this key cannot open is an error: the database never
    /// writes over it.
    pub fn open(path: impl Into<PathBuf>, key: &[u8]) -> Result<Self, DbError> {
        if key.len() != KEY_LEN {
            return Err(DbError::Key);
        }
        let file = DbFile::new(path.into(), key)?;
        let mut data = file.read()?.unwrap_or_default();
        data.version = DB_VERSION;
        Ok(CelautDb {
            inner: Mutex::new(Inner {
                data,
                file: Some(file),
            }),
        })
    }

    /// The file of the database, if it has one.
    pub fn path(&self) -> Option<PathBuf> {
        self.lock().file.as_ref().map(|f| f.path.clone())
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Read the content.
    pub fn read<R>(&self, f: impl FnOnce(&CelautData) -> R) -> R {
        f(&self.lock().data)
    }

    /// A copy of the content.
    pub fn snapshot(&self) -> CelautData {
        self.lock().data.clone()
    }

    /// Change the content and write the file. If the write fails, the change stays in
    /// memory and the error comes back; the next successful write saves it.
    pub fn update<R>(&self, f: impl FnOnce(&mut CelautData) -> R) -> Result<R, DbError> {
        let mut inner = self.lock();
        let answer = f(&mut inner.data);
        if let Some(file) = &inner.file {
            file.write(&inner.data)?;
        }
        Ok(answer)
    }
}

/// The advertisements are part of the database.
impl PeerStore for CelautDb {
    fn get(&self, peer_id: &str) -> Result<Option<Seen>, StoreError> {
        Ok(self.read(|d| d.seen.get(peer_id).cloned()))
    }

    fn put(&self, peer_id: &str, seen: Seen) -> Result<(), StoreError> {
        Ok(self.update(|d| keep_newer(&mut d.seen, peer_id, seen))?)
    }
}

/// Move a file that cannot be opened to a new name next to it, so that a new database
/// can start and the old file stays for the user. Gives the new name.
pub fn set_aside(path: &Path, suffix: &str) -> Result<PathBuf, DbError> {
    let mut name = path.as_os_str().to_owned();
    name.push(format!(".unreadable-{suffix}"));
    let target = PathBuf::from(name);
    std::fs::rename(path, &target).map_err(|e| DbError::Io {
        path: path.display().to_string(),
        message: e.to_string(),
    })?;
    Ok(target)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir() -> PathBuf {
        let mut bytes = [0u8; 8];
        SystemRandom::new().fill(&mut bytes).unwrap();
        let dir = std::env::temp_dir().join(format!("celaut-db-{}", hex::encode(bytes)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn sample(data: &mut CelautData) {
        data.nodes.insert(
            "aa".repeat(32),
            NodeRecord {
                client_id: "c1".into(),
                addresses: vec!["node.example:53460".into()],
                deposit_limit_nano_erg: Some(7),
            },
        );
        data.instances.insert(
            "i1".into(),
            InstanceRecord {
                peer_id: "aa".repeat(32),
                address: "node.example:53460".into(),
                token: "secret-token".into(),
                service_id: "bb".repeat(32),
                slots: vec![3030],
                started_at: 1,
                start_charge_mu: Some("100".into()),
            },
        );
        data.deposits.insert(
            "d1".into(),
            DepositRecord {
                peer_id: "aa".repeat(32),
                address: "node.example:53460".into(),
                deposit_token: "tok".into(),
                nano_erg: 10_000_000,
                mu: "10000000".into(),
                pay_to_address: "9f...".into(),
                tx_id: "cc".repeat(32),
                made_at: 2,
                stage: DepositStage::Sent {
                    tx_id: "cc".repeat(32),
                },
            },
        );
        data.add_event(EventRecord {
            peer_id: "aa".repeat(32),
            kind: EventKind::PaymentCommunicated,
            at: 3,
        });
    }

    #[test]
    fn the_data_survives_a_restart() {
        let path = dir().join("celaut.db");
        let key = [7u8; KEY_LEN];
        {
            let db = CelautDb::open(&path, &key).unwrap();
            db.update(sample).unwrap();
            db.put(
                &"aa".repeat(32),
                Seen {
                    ts: 5,
                    digest: "d".into(),
                },
            )
            .unwrap();
        }
        let again = CelautDb::open(&path, &key).unwrap();
        let data = again.snapshot();
        let mut expected = CelautData {
            version: DB_VERSION,
            ..Default::default()
        };
        sample(&mut expected);
        expected.seen.insert(
            "aa".repeat(32),
            Seen {
                ts: 5,
                digest: "d".into(),
            },
        );
        assert_eq!(data, expected);
    }

    #[test]
    fn the_file_is_encrypted_and_needs_the_key() {
        let path = dir().join("celaut.db");
        let db = CelautDb::open(&path, &[1u8; KEY_LEN]).unwrap();
        db.update(sample).unwrap();
        let bytes = std::fs::read(&path).unwrap();
        let text = String::from_utf8_lossy(&bytes);
        assert!(!text.contains("secret-token"));
        assert!(!text.contains("c1"));
        let err = CelautDb::open(&path, &[2u8; KEY_LEN]).unwrap_err();
        assert!(matches!(err, DbError::Unreadable(_)), "{err}");
        // The file is not changed by the failed open.
        assert_eq!(std::fs::read(&path).unwrap(), bytes);
    }

    #[test]
    fn a_damaged_file_is_unreadable_and_can_be_set_aside() {
        let path = dir().join("celaut.db");
        let db = CelautDb::open(&path, &[1u8; KEY_LEN]).unwrap();
        db.update(sample).unwrap();
        let mut bytes = std::fs::read(&path).unwrap();
        let last = bytes.len() - 1;
        bytes[last] ^= 1;
        std::fs::write(&path, &bytes).unwrap();
        assert!(matches!(
            CelautDb::open(&path, &[1u8; KEY_LEN]),
            Err(DbError::Unreadable(_))
        ));
        let moved = set_aside(&path, "1").unwrap();
        assert!(moved.exists());
        let fresh = CelautDb::open(&path, &[1u8; KEY_LEN]).unwrap();
        assert!(fresh.snapshot().nodes.is_empty());
    }

    #[test]
    fn a_key_of_the_wrong_length_is_refused() {
        let path = dir().join("celaut.db");
        assert!(matches!(
            CelautDb::open(&path, &[1u8; 16]),
            Err(DbError::Key)
        ));
    }

    #[test]
    fn no_file_until_the_first_change() {
        let path = dir().join("sub").join("celaut.db");
        let db = CelautDb::open(&path, &[1u8; KEY_LEN]).unwrap();
        assert!(!path.exists());
        db.update(|d| d.nodes.clear()).unwrap();
        assert!(path.exists());
    }

    #[test]
    fn deposits_count_per_node_and_lists_are_bounded() {
        let mut data = CelautData::default();
        sample(&mut data);
        assert_eq!(data.deposited_nano_erg(&"aa".repeat(32)), 10_000_000);
        assert_eq!(data.deposited_nano_erg(&"bb".repeat(32)), 0);
        for i in 0..(MAX_QUOTES + 5) {
            data.add_quote(QuoteRecord {
                peer_id: format!("p{i}"),
                service_id: "s".into(),
                cost_mu: "1".into(),
                at: i as i64,
            });
        }
        assert_eq!(data.quotes.len(), MAX_QUOTES);
        assert_eq!(data.quotes[0].peer_id, "p5");
        // A new quote of the same node and service replaces the old one.
        data.add_quote(QuoteRecord {
            peer_id: "p6".into(),
            service_id: "s".into(),
            cost_mu: "2".into(),
            at: 99,
        });
        assert_eq!(data.quotes.len(), MAX_QUOTES);
        assert_eq!(data.quotes.iter().filter(|q| q.peer_id == "p6").count(), 1);
        assert_eq!(data.quotes.last().unwrap().cost_mu, "2");
    }

    #[test]
    fn the_addresses_of_a_node_keep_the_last_first() {
        let mut data = CelautData::default();
        sample(&mut data);
        let peer = "aa".repeat(32);
        data.note_address(&peer, "10.0.0.1:1");
        data.note_address(&peer, "node.example:53460");
        assert_eq!(
            data.nodes[&peer].addresses,
            vec!["node.example:53460".to_string(), "10.0.0.1:1".to_string()]
        );
    }

    #[test]
    fn a_merge_keeps_the_entries_that_exist() {
        let mut a = CelautData::default();
        sample(&mut a);
        let mut b = CelautData::default();
        b.nodes.insert(
            "aa".repeat(32),
            NodeRecord {
                client_id: "other".into(),
                ..Default::default()
            },
        );
        b.nodes.insert(
            "dd".repeat(32),
            NodeRecord {
                client_id: "c2".into(),
                ..Default::default()
            },
        );
        a.merge_missing(b);
        assert_eq!(a.nodes[&"aa".repeat(32)].client_id, "c1");
        assert_eq!(a.nodes[&"dd".repeat(32)].client_id, "c2");
    }
}
