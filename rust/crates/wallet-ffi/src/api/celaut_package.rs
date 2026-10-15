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
//! service, so a node never keeps half a service.

use std::path::PathBuf;
use std::sync::Mutex;

use celaut_client::package::{inspect, read, save, Cancel, Layout, PackageError, PackageInfo};

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

fn package_error(e: PackageError) -> CelautError {
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
    let result = s
        .quote_with_service(id, configuration, read(path, info.layout, cancel))
        .await;
    end();
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
