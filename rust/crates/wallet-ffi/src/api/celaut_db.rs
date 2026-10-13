//! The Celaut database of the app (`docs/celaut/ui.md`, section 1).
//!
//! One database for the whole app holds the client ids, the advertisements, the
//! instances and their tokens, the deposits, the last quotes and the event log. It is
//! never one per wallet, and it has no wallet key: any full wallet of the app can manage
//! any instance and pay any node.
//!
//! Until the app opens the file with [`celaut_open_database`], the database is in
//! memory. The app opens it at the start, with a key from the Keystore store of the app.

use std::sync::{Arc, RwLock};

use celaut_client::db::{set_aside, DepositStage, KEY_LEN};
use celaut_client::{CelautData, CelautDb, DbError};
use once_cell::sync::Lazy;
use rand::{rngs::SysRng, TryRng};

use super::celaut::{CelautError, CelautErrorKind};

static DB: Lazy<RwLock<Arc<CelautDb>>> = Lazy::new(|| RwLock::new(Arc::new(CelautDb::in_memory())));

/// The database of the app.
pub(crate) fn db() -> Arc<CelautDb> {
    DB.read()
        .map(|d| d.clone())
        .unwrap_or_else(|p| p.into_inner().clone())
}

pub(crate) fn storage_error(e: DbError) -> CelautError {
    CelautError {
        kind: CelautErrorKind::Storage,
        message: e.to_string(),
    }
}

/// The time now, in Unix seconds.
pub(crate) fn now_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| i64::try_from(d.as_secs()).unwrap_or(i64::MAX))
        .unwrap_or(0)
}

/// What [`celaut_open_database`] found.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CelautDatabaseView {
    pub path: String,
    pub nodes: u32,
    pub instances: u32,
    pub deposits: u32,
    /// The new name of an old file that the key could not open, if there was one. The
    /// app starts a new database and keeps the old file.
    pub set_aside_path: Option<String>,
}

fn count(n: usize) -> u32 {
    u32::try_from(n).unwrap_or(u32::MAX)
}

/// A new random key for the database, as 64 hexadecimal characters. The app keeps it in
/// its Keystore store.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_new_database_key() -> Result<String, CelautError> {
    let mut key = [0u8; KEY_LEN];
    SysRng.try_fill_bytes(&mut key).map_err(|_| CelautError {
        kind: CelautErrorKind::Storage,
        message: "the system gave no random numbers".into(),
    })?;
    Ok(hex::encode(key))
}

/// Open the database file `path` with `key_hex` (64 hexadecimal characters) and use it
/// for all the Celaut calls. What the app already has in memory is added to it.
///
/// A deposit that was only prepared in an earlier run is removed: its preparation
/// ended with that run, so it was never sent. A node of an earlier version gets its paid
/// credit from its accepted deposits. A file that the key cannot open is moved
/// to a new name, and a new database starts.
#[flutter_rust_bridge::frb]
pub fn celaut_open_database(
    path: String,
    key_hex: String,
) -> Result<CelautDatabaseView, CelautError> {
    let (opened, view) = open_file(&path, &key_hex, db().snapshot())?;
    let mut global = DB.write().unwrap_or_else(|p| p.into_inner());
    *global = Arc::new(opened);
    Ok(view)
}

/// [`celaut_open_database`] without the change of the database of the app.
fn open_file(
    path: &str,
    key_hex: &str,
    memory: CelautData,
) -> Result<(CelautDb, CelautDatabaseView), CelautError> {
    let key = hex::decode(key_hex.trim()).map_err(|_| storage_error(DbError::Key))?;
    let mut set_aside_path = None;
    let opened = match CelautDb::open(path, &key) {
        Ok(db) => db,
        Err(DbError::Unreadable(_)) => {
            let moved = set_aside(std::path::Path::new(path), &now_seconds().to_string())
                .map_err(storage_error)?;
            set_aside_path = Some(moved.display().to_string());
            CelautDb::open(path, &key).map_err(storage_error)?
        }
        Err(e) => return Err(storage_error(e)),
    };
    opened
        .update(|d| {
            d.deposits
                .retain(|_, deposit| deposit.stage != DepositStage::Prepared);
            d.merge_missing(memory);
            d.count_paid_credit();
        })
        .map_err(storage_error)?;
    let view = opened.read(|d| CelautDatabaseView {
        path: path.to_string(),
        nodes: count(d.nodes.len()),
        instances: count(d.instances.len()),
        deposits: count(d.deposits.len()),
        set_aside_path,
    });
    Ok((opened, view))
}

#[cfg(test)]
mod tests {
    use super::*;
    use celaut_client::db::{DepositRecord, InstanceRecord, NodeRecord};

    fn temp_path() -> String {
        let dir = std::env::temp_dir().join(format!(
            "celaut-ffi-db-{}",
            &celaut_new_database_key().unwrap()[..16]
        ));
        dir.join("celaut.db").display().to_string()
    }

    fn deposit(stage: DepositStage) -> DepositRecord {
        DepositRecord {
            peer_id: "aa".repeat(32),
            address: "node:1".into(),
            deposit_token: "tok".into(),
            nano_erg: 1_000_000,
            mu: "1000000".into(),
            pay_to_address: "9f".into(),
            tx_id: "ab".repeat(32),
            made_at: 1,
            stage,
        }
    }

    #[test]
    fn the_client_ids_instances_and_sent_deposits_survive_a_restart() {
        let path = temp_path();
        let key = celaut_new_database_key().unwrap();
        // The app had a node, an instance and two deposits in memory before the open.
        let mut memory = CelautData::default();
        memory.nodes.insert(
            "aa".repeat(32),
            NodeRecord {
                client_id: "client-1".into(),
                addresses: vec!["node:1".into()],
                deposit_limit_nano_erg: Some(5),
                ..Default::default()
            },
        );
        memory.instances.insert(
            "i1".into(),
            InstanceRecord {
                peer_id: "aa".repeat(32),
                token: "token-1".into(),
                ..Default::default()
            },
        );
        memory.deposits.insert(
            "sent".into(),
            deposit(DepositStage::Sent {
                tx_id: "ab".repeat(32),
            }),
        );
        let (first, view) = open_file(&path, &key, memory).unwrap();
        assert_eq!((view.nodes, view.instances, view.deposits), (1, 1, 1));
        // A deposit prepared in this run goes into the file too.
        first
            .update(|d| {
                d.deposits
                    .insert("prepared".into(), deposit(DepositStage::Prepared));
            })
            .unwrap();
        drop(first);

        // The restart: a new open of the same file with the same key, and an empty
        // memory.
        let (again, view) = open_file(&path, &key, CelautData::default()).unwrap();
        assert_eq!(view.set_aside_path, None);
        let data = again.snapshot();
        assert_eq!(data.nodes[&"aa".repeat(32)].client_id, "client-1");
        assert_eq!(data.nodes[&"aa".repeat(32)].deposit_limit_nano_erg, Some(5));
        assert_eq!(data.instances["i1"].token, "token-1");
        assert!(data.deposits.contains_key("sent"));
        // The prepared deposit of the earlier run was never sent: it is gone.
        assert!(!data.deposits.contains_key("prepared"));
    }

    #[test]
    fn a_file_that_the_key_cannot_open_is_set_aside() {
        let path = temp_path();
        let mut memory = CelautData::default();
        memory.nodes.insert("aa".repeat(32), NodeRecord::default());
        let (first, _) = open_file(&path, &celaut_new_database_key().unwrap(), memory).unwrap();
        drop(first);
        let (fresh, view) = open_file(
            &path,
            &celaut_new_database_key().unwrap(),
            CelautData::default(),
        )
        .unwrap();
        let moved = view.set_aside_path.expect("set aside");
        assert!(std::path::Path::new(&moved).exists());
        assert!(fresh.snapshot().nodes.is_empty());
        assert!(open_file(&path, "not hex", CelautData::default()).is_err());
    }

    #[test]
    fn a_new_key_is_32_random_bytes() {
        let a = celaut_new_database_key().unwrap();
        let b = celaut_new_database_key().unwrap();
        assert_eq!(a.len(), 64);
        assert_ne!(a, b);
    }
}
