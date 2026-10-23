//! Give a service to a node that does not have it (`docs/celaut/package.md`).
//!
//! A node refuses a service that it does not have, unless the request carries it. The
//! app gets the service from a node that has it (`GetService`), or from a `.celaut.bee`
//! file that `nodo export` wrote, keeps it in a file of the app, and gives it to the
//! node with a quote: the node stores it, and then the launch works as usual. The file
//! is read while it is sent, so a large service never sits in memory.
//!
//! One transfer at a time. [`celaut_transfer_progress`] gives its bytes so far, and
//! [`celaut_cancel_transfer`] stops it: the node gets markers that make it refuse the cut
//! service, so a node never keeps half a service. A node that already has the service
//! answers after its hash, and the app then stops sending it (`celaut_wire::relay`).

use std::path::PathBuf;
use std::sync::Mutex;

use celaut_client::db::PackageRecord;
use celaut_client::package::{
    import, inspect, read, remove_file, save, Cancel, Layout, PackageError, PackageInfo,
};

use super::celaut::{error_of, invalid, CelautError, CelautErrorKind};
use super::celaut_db::{db, now_seconds};
use super::celaut_service::{
    configuration, forget_if_broken, n, quote_view, service_id, session, NodeAddress, QuoteView,
};
use celaut_client::db::QuoteRecord;

/// What a package file holds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageView {
    /// Where the file is.
    pub path: String,
    /// The size of the file, in bytes.
    pub bytes: u64,
    /// The id of the service (64 hexadecimal characters), if the package says it.
    pub service_id: Option<String>,
    /// True if the package has the Service part, not only its description.
    pub has_service: bool,
    /// True for a file of `nodo export` (its parts get the indices of a node).
    pub nodo_export: bool,
}

/// A service file that the user loaded into the app (the library of `celaut_packages`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LibraryPackageView {
    /// The id of the service: 64 lowercase hexadecimal characters.
    pub service_id: String,
    /// The name to show.
    pub name: String,
    /// The file of the app that holds the package.
    pub path: String,
    /// The size of the file, in bytes.
    pub bytes: u64,
    /// The time of the load, in Unix seconds.
    pub imported_at: i64,
    /// True for a file of `nodo export`.
    pub nodo_export: bool,
    /// False if the file is gone (the user or the system deleted it): the record stays so
    /// that the screen can say it, and the user can load the file again.
    pub present: bool,
}

/// The longest name that the library keeps, in characters.
const MAX_NAME: usize = 80;

/// The name to show for a file: the name of the file without `.celaut.bee` or `.bee`, with
/// no control characters, and no more than [`MAX_NAME`] characters. An empty name is the
/// first 8 characters of the service id.
fn clean_name(name: &str, service_id: &str) -> String {
    let base = name.rsplit(['/', '\\']).next().unwrap_or(name).trim();
    let lower = base.to_ascii_lowercase();
    let base = if lower.ends_with(".celaut.bee") {
        &base[..base.len() - ".celaut.bee".len()]
    } else if lower.ends_with(".bee") {
        &base[..base.len() - ".bee".len()]
    } else {
        base
    };
    let cleaned: String = base
        .chars()
        .filter(|c| !c.is_control())
        .take(MAX_NAME)
        .collect();
    let cleaned = cleaned.trim().to_string();
    if cleaned.is_empty() {
        service_id.chars().take(8).collect()
    } else {
        cleaned
    }
}

fn library_view(service_id: &str, r: &PackageRecord) -> LibraryPackageView {
    LibraryPackageView {
        service_id: service_id.to_string(),
        name: r.name.clone(),
        path: r.path.clone(),
        bytes: r.bytes,
        imported_at: r.imported_at,
        nodo_export: r.nodo_export,
        present: std::path::Path::new(&r.path).is_file(),
    }
}

/// Load the service file at `path` (a copy of the file that the user chose, in the cache of
/// the app) into the library of the app, which keeps it in a private directory `dir` under
/// the id of its service. The file is moved, not copied. `name` is the name of the file
/// that the user chose. A file that is not a package of a service, or that does not say
/// which service it is, is refused (kind `invalidInput`) and stays where it is. A second
/// load of the same service replaces the first.
#[flutter_rust_bridge::frb]
pub async fn celaut_import_package(
    path: String,
    name: String,
    dir: String,
) -> Result<LibraryPackageView, CelautError> {
    if dir.trim().is_empty() {
        return Err(invalid("the app has no directory for the package"));
    }
    let imported = import(&PathBuf::from(&path), &PathBuf::from(dir))
        .await
        .map_err(package_error)?;
    let id = hex::encode(imported.service_id);
    let record = PackageRecord {
        name: clean_name(&name, &id),
        path: imported.path.display().to_string(),
        bytes: imported.info.bytes,
        imported_at: now_seconds(),
        nodo_export: imported.info.layout == Layout::NodoExport,
    };
    let view = library_view(&id, &record);
    db().update(|d| {
        d.packages.insert(id.clone(), record);
    })
    .map_err(super::celaut_db::storage_error)?;
    Ok(view)
}

/// The service files that the user loaded into the app, by name. It makes no connection.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_packages() -> Vec<LibraryPackageView> {
    let mut list: Vec<LibraryPackageView> = db().read(|d| {
        d.packages
            .iter()
            .map(|(id, r)| library_view(id, r))
            .collect()
    });
    list.sort_by(|a, b| {
        a.name
            .to_lowercase()
            .cmp(&b.name.to_lowercase())
            .then_with(|| a.service_id.cmp(&b.service_id))
    });
    list
}

/// Remove a service file from the library: the file is deleted and the record is dropped.
/// The nodes that have the service keep it. Nothing happens for a service that is not in
/// the library.
#[flutter_rust_bridge::frb]
pub async fn celaut_remove_package(service_id_hex: String) -> Result<(), CelautError> {
    let id = hex::encode(service_id(&service_id_hex)?);
    let record = db().read(|d| d.packages.get(&id).cloned());
    let Some(record) = record else {
        return Ok(());
    };
    remove_file(&PathBuf::from(&record.path))
        .await
        .map_err(package_error)?;
    db().update(|d| {
        d.packages.remove(&id);
    })
    .map_err(super::celaut_db::storage_error)?;
    Ok(())
}

/// What a transfer does now.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferStage {
    /// No transfer.
    Idle,
    /// The app gets the service from a node.
    Fetching,
    /// The app gives the service to a node.
    Sending,
}

/// The transfer that runs, if any.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransferView {
    pub stage: TransferStage,
    /// The bytes moved so far.
    pub bytes: u64,
    /// The size of the whole package, when the app knows it (a send of a file).
    pub total: Option<u64>,
}

struct Running {
    stage: TransferStage,
    cancel: Cancel,
    total: Option<u64>,
}

static TRANSFER: Mutex<Option<Running>> = Mutex::new(None);

fn transfer() -> std::sync::MutexGuard<'static, Option<Running>> {
    TRANSFER.lock().unwrap_or_else(|e| e.into_inner())
}

/// Mark a transfer as running. Refused if another one runs.
fn begin(stage: TransferStage, total: Option<u64>) -> Result<Cancel, CelautError> {
    let mut t = transfer();
    if t.is_some() {
        return Err(invalid("another transfer of a service runs"));
    }
    let cancel = Cancel::new();
    *t = Some(Running {
        stage,
        cancel: cancel.clone(),
        total,
    });
    Ok(cancel)
}

fn end() {
    *transfer() = None;
}

pub(crate) fn package_error(e: PackageError) -> CelautError {
    match e {
        PackageError::Io(e) => CelautError {
            kind: CelautErrorKind::Storage,
            message: e.to_string(),
        },
        PackageError::Invalid(text) => CelautError {
            kind: CelautErrorKind::InvalidInput,
            message: text,
        },
        PackageError::Cancelled => CelautError {
            kind: CelautErrorKind::TransferFailed,
            message: "the transfer was cancelled".into(),
        },
        PackageError::Wire(e) => error_of(e.into()),
    }
}

fn view_of(path: String, info: &PackageInfo) -> PackageView {
    PackageView {
        path,
        bytes: info.bytes,
        service_id: info.service_id.map(hex::encode),
        has_service: info.has_service,
        nodo_export: info.layout == Layout::NodoExport,
    }
}

/// Get the service from `source`, a node that has it, into a file in `dir` (a
/// directory of the app), and say what the file holds. A node that does not have the
/// service gives the error [`CelautErrorKind::ServiceMissing`].
#[flutter_rust_bridge::frb]
pub async fn celaut_fetch_service(
    source: NodeAddress,
    service_id_hex: String,
    dir: String,
) -> Result<PackageView, CelautError> {
    let id = service_id(&service_id_hex)?;
    if dir.trim().is_empty() {
        return Err(invalid("the app has no directory for the package"));
    }
    let folder = PathBuf::from(dir).join("packages");
    std::fs::create_dir_all(&folder).map_err(|e| package_error(e.into()))?;
    let path = folder.join(format!("{}.bee", hex::encode(id)));
    let s = session(&source).await?;
    let cancel = begin(TransferStage::Fetching, None)?;
    let result = async {
        let raw = s.get_service(id).await.map_err(|e| {
            forget_if_broken(&source, &e);
            error_of(e)
        })?;
        save(raw, &path, &cancel).await.map_err(|e| match e {
            PackageError::Invalid(text) if text.contains("does not have the service") => {
                CelautError {
                    kind: CelautErrorKind::ServiceMissing,
                    message: text,
                }
            }
            other => package_error(other),
        })?;
        let info = inspect(&path).await.map_err(package_error)?;
        if info.service_id.is_some_and(|got| got != id) || !info.has_service {
            let _ = std::fs::remove_file(&path);
            return Err(invalid("the node gave another service, or no Service part"));
        }
        Ok(view_of(path.display().to_string(), &info))
    }
    .await;
    end();
    result
}

/// What the package file at `path` holds: for a `.celaut.bee` that the user chose.
#[flutter_rust_bridge::frb]
pub async fn celaut_inspect_package(path: String) -> Result<PackageView, CelautError> {
    let info = inspect(&PathBuf::from(&path)).await.map_err(package_error)?;
    Ok(view_of(path, &info))
}

/// Give the service in the package at `path` to `node` with a quote, and give the quote.
/// After it, the node has the service. The package must hold the service
/// `service_id_hex` (when it says its id) and its Service part. If the transfer fails or
/// is cancelled, the node refuses the cut service, and the error has the kind
/// [`CelautErrorKind::TransferFailed`]. A node can store the service and still refuse
/// the quote (for example, for an architecture that it does not run): that refusal is
/// the error.
#[flutter_rust_bridge::frb]
pub async fn celaut_send_service(
    node: NodeAddress,
    service_id_hex: String,
    initial_mu: Option<String>,
    path: String,
) -> Result<QuoteView, CelautError> {
    let id = service_id(&service_id_hex)?;
    let configuration = configuration(initial_mu)?;
    let path = PathBuf::from(path);
    let info = inspect(&path).await.map_err(package_error)?;
    if !info.has_service {
        return Err(invalid("the package has no Service part"));
    }
    if info.service_id.is_some_and(|got| got != id) {
        return Err(invalid("the package holds another service"));
    }
    let s = session(&node).await?;
    let cancel = begin(TransferStage::Sending, Some(info.bytes))?;
    // What the node got of the service: it can answer before the end when it already
    // has the service, and then the rest is not sent.
    let sent = celaut_wire::SendCounter::new();
    let result = s
        .quote_with_service(
            id,
            configuration,
            sent.wrap(read(path, info.layout, cancel)),
        )
        .await;
    end();
    tracing::info!(
        "service {}: sent {} bytes in {} Buffers to {}, of a package of {} bytes; {}",
        hex::encode(id),
        sent.bytes(),
        sent.buffers(),
        s.peer_id(),
        info.bytes,
        if sent.ended() {
            "the whole service went"
        } else if result.is_ok() {
            "the node answered first: it has the service"
        } else {
            "the transfer stopped"
        }
    );
    let quote = result.map_err(|e| {
        forget_if_broken(&node, &e);
        error_of(e)
    })?;
    let stored = db().update(|d| {
        d.add_quote(QuoteRecord {
            peer_id: s.peer_id().to_string(),
            service_id: hex::encode(id),
            cost_mu: n(&quote.cost),
            at: now_seconds(),
        });
    });
    if let Err(e) = stored {
        tracing::warn!("the quote is not stored: {e}");
    }
    let mut view = quote_view(node, s.peer_id().to_string(), &quote);
    view.client_balance_mu = s.balance().await.map(|b| b.to_string()).unwrap_or_default();
    Ok(view)
}

/// The transfer that runs now.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_transfer_progress() -> TransferView {
    match transfer().as_ref() {
        Some(r) => TransferView {
            stage: r.stage,
            bytes: r.cancel.bytes(),
            total: r.total,
        },
        None => TransferView {
            stage: TransferStage::Idle,
            bytes: 0,
            total: None,
        },
    }
}

/// Stop the transfer that runs, if any. The node refuses the cut service.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_cancel_transfer() {
    if let Some(r) = transfer().as_ref() {
        r.cancel.cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_name_of_a_file_is_cleaned() {
        let id = "ab".repeat(32);
        for (raw, want) in [
            ("echo.celaut.bee", "echo"),
            ("ECHO.CELAUT.BEE", "ECHO"),
            ("my service.bee", "my service"),
            ("plain", "plain"),
            ("/storage/emulated/0/Download/echo.celaut.bee", "echo"),
            ("C:\\Users\\x\\echo.celaut.bee", "echo"),
            ("  spaced  .celaut.bee", "spaced"),
            ("tab\there\u{7}.bee", "tabhere"),
            ("", "abababab"),
            (".celaut.bee", "abababab"),
            ("   ", "abababab"),
        ] {
            assert_eq!(clean_name(raw, &id), want, "{raw:?}");
        }
        let long = format!("{}.celaut.bee", "x".repeat(300));
        assert_eq!(clean_name(&long, &id).chars().count(), MAX_NAME);
        // A name in another alphabet is not cut in the middle of a character.
        let wide = format!("{}.bee", "é".repeat(200));
        assert_eq!(clean_name(&wide, &id).chars().count(), MAX_NAME);
    }

    #[test]
    fn a_record_is_a_view_and_a_missing_file_is_not_present() {
        let id = "cd".repeat(32);
        let record = PackageRecord {
            name: "echo".into(),
            path: "/no/such/file.bee".into(),
            bytes: 9,
            imported_at: 3,
            nodo_export: true,
        };
        let view = library_view(&id, &record);
        assert_eq!((view.name.as_str(), view.bytes, view.nodo_export), ("echo", 9, true));
        assert!(!view.present);
        let here = std::env::temp_dir().join(format!("celaut-view-{}", std::process::id()));
        std::fs::write(&here, b"x").unwrap();
        let present = library_view(&id, &PackageRecord { path: here.display().to_string(), ..record });
        assert!(present.present);
        std::fs::remove_file(here).unwrap();
    }

    #[test]
    fn one_transfer_at_a_time_and_its_progress() {
        let cancel = begin(TransferStage::Sending, Some(100)).unwrap();
        assert!(begin(TransferStage::Fetching, None).is_err());
        let p = celaut_transfer_progress();
        assert_eq!((p.stage, p.bytes, p.total), (TransferStage::Sending, 0, Some(100)));
        celaut_cancel_transfer();
        assert!(cancel.is_cancelled());
        end();
        assert_eq!(celaut_transfer_progress().stage, TransferStage::Idle);
        // No transfer: cancel does nothing.
        celaut_cancel_transfer();
    }

    #[test]
    fn package_errors_have_their_kinds() {
        assert_eq!(
            package_error(PackageError::Cancelled).kind,
            CelautErrorKind::TransferFailed
        );
        assert_eq!(
            package_error(PackageError::Invalid("x".into())).kind,
            CelautErrorKind::InvalidInput
        );
        assert_eq!(
            package_error(PackageError::Io(std::io::Error::other("disk"))).kind,
            CelautErrorKind::Storage
        );
        assert_eq!(
            package_error(PackageError::Wire(celaut_wire::WireError::Relay("cut".into()))).kind,
            CelautErrorKind::TransferFailed
        );
    }
}
