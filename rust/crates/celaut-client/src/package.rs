//! A service as a package: the Buffers that give it to a node that does not have it
//! (`docs/celaut/package.md`).
//!
//! A node takes a service in `StartService` or `GetServiceEstimatedCost`: the hashes
//! (index 4), the Metadata (index 5) and the Service (index 6), with the blocks of the
//! Service. The app gets these Buffers from `GetService` of another node, or from a
//! `.celaut.bee` file that `nodo export` wrote. Both can be large, so this module moves
//! them as a stream, one Buffer at a time, and keeps them in a `.bee` file on the
//! phone, never in memory:
//!
//! - [`save`] writes the Buffers of `GetService` to a `.bee` file.
//! - [`inspect`] reads the head of a `.bee` file: its layout, and the service id from
//!   the Metadata or from a hash part. It stops before the Service.
//! - [`read`] gives the Buffers of a `.bee` file for a node: the head indices of a
//!   `nodo export` file (1 Metadata, 2 Service) become 5 and 6.
//!
//! A [`Cancel`] stops a transfer: the stream gives an error, and the node gets markers
//! that make it refuse the cut input (`bee_rpc::grpc::call_buffers`).

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use bee_rpc::buffer::Buffer;
use celaut_proto::celaut::metadata::hash_tag::Hash;
use celaut_proto::celaut::Metadata;
use celaut_wire::gateway::SHA3_256_TYPE;
use celaut_wire::{Buffers, WireError};
use prost::Message;
use tokio::io::{AsyncReadExt, AsyncWriteExt, BufReader, BufWriter};

/// The longest record that a `.bee` file can have here. A Buffer carries at most one
/// chunk of 1 MiB; this leaves room, and refuses a false length before it allocates.
pub const MAX_RECORD: u32 = 16 * 1024 * 1024;

/// Why a package cannot be used.
#[derive(Debug, thiserror::Error)]
pub enum PackageError {
    /// A file error.
    #[error("the package file: {0}")]
    Io(#[from] std::io::Error),
    /// The file is not a `.bee` file of a service.
    #[error("the package is not valid: {0}")]
    Invalid(String),
    /// The transfer was cancelled.
    #[error("the transfer was cancelled")]
    Cancelled,
    /// The node gave an error.
    #[error(transparent)]
    Wire(#[from] WireError),
}

/// The indices of the parts of a package.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Layout {
    /// The indices of `StartService` and of the answer of `GetService`: 4 hashes, 5
    /// Metadata, 6 Service.
    Gateway,
    /// The indices of `nodo export`: 1 Metadata, 2 Service.
    NodoExport,
}

impl Layout {
    /// The index of the Metadata and of the Service.
    fn indices(self) -> (i32, i32) {
        match self {
            Layout::Gateway => (5, 6),
            Layout::NodoExport => (1, 2),
        }
    }

    /// The index for a node of a head index of this layout.
    fn for_node(self, index: i32) -> i32 {
        match (self, index) {
            (Layout::NodoExport, 1) => 5,
            (Layout::NodoExport, 2) => 6,
            (_, other) => other,
        }
    }
}

/// What the head of a package says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageInfo {
    pub layout: Layout,
    /// The size of the file, in bytes.
    pub bytes: u64,
    /// The id of the service (SHA3-256), from the Metadata or a hash part. `None` if the
    /// package does not say it.
    pub service_id: Option<[u8; 32]>,
    /// True if a Service part starts in the package.
    pub has_service: bool,
}

/// Stops a transfer, and counts its bytes. Clone it to share it.
#[derive(Debug, Clone, Default)]
pub struct Cancel {
    cancelled: Arc<AtomicBool>,
    bytes: Arc<AtomicU64>,
}

impl Cancel {
    pub fn new() -> Self {
        Cancel::default()
    }

    /// Stop the transfer: the next Buffer is an error.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    /// The bytes that the transfer moved so far (the records of the `.bee` file).
    pub fn bytes(&self) -> u64 {
        self.bytes.load(Ordering::Acquire)
    }

    fn add(&self, n: u64) {
        self.bytes.fetch_add(n, Ordering::AcqRel);
    }
}

/// A Buffer with no data for a package: a flow control signal or a skip request of the
/// sender. They are for the call that carried them, not for the next node.
fn is_control_only(b: &Buffer) -> bool {
    b.chunk.is_none() && b.head.is_none() && b.block.is_none() && b.separator != Some(true)
}

/// Write the Buffers of `input` to a `.bee` file at `path`. The file is written next to
/// `path` and renamed when it is complete, so `path` never holds a cut package. Gives
/// the number of bytes.
pub async fn save(mut input: Buffers, path: &Path, cancel: &Cancel) -> Result<u64, PackageError> {
    use tokio_stream::StreamExt;
    let partial = partial_path(path);
    let result = async {
        let file = tokio::fs::File::create(&partial).await?;
        let mut writer = BufWriter::new(file);
        let mut total = 0u64;
        while let Some(item) = input.next().await {
            if cancel.is_cancelled() {
                return Err(PackageError::Cancelled);
            }
            let mut buffer = item?;
            if is_control_only(&buffer) {
                continue;
            }
            // A signal is for the call that carried it.
            buffer.signal = None;
            buffer.skip = None;
            let record = buffer.encode_to_vec();
            let len = u32::try_from(record.len())
                .ok()
                .filter(|l| *l <= MAX_RECORD)
                .ok_or_else(|| PackageError::Invalid("a Buffer is too large".into()))?;
            writer.write_u32(len).await?;
            writer.write_all(&record).await?;
            let n = 4 + u64::from(len);
            total += n;
            cancel.add(n);
        }
        writer.flush().await?;
        Ok(total)
    }
    .await;
    match result {
        Ok(total) if total > 0 => {
            tokio::fs::rename(&partial, path).await?;
            Ok(total)
        }
        Ok(_) => {
            let _ = tokio::fs::remove_file(&partial).await;
            Err(PackageError::Invalid("the node gave nothing: it does not have the service".into()))
        }
        Err(e) => {
            let _ = tokio::fs::remove_file(&partial).await;
            Err(e)
        }
    }
}

fn partial_path(path: &Path) -> PathBuf {
    let mut name = path.file_name().map(|n| n.to_os_string()).unwrap_or_default();
    name.push(".partial");
    path.with_file_name(name)
}

/// One record of a `.bee` file, or `None` at a clean end.
async fn next_record<R: tokio::io::AsyncRead + Unpin>(
    reader: &mut R,
) -> Result<Option<Buffer>, PackageError> {
    // A clean end has no byte of a new record. One to three bytes are a cut length.
    let mut prefix = [0u8; 4];
    let mut got = 0;
    while got < prefix.len() {
        let n = reader.read(&mut prefix[got..]).await?;
        if n == 0 {
            break;
        }
        got += n;
    }
    match got {
        0 => return Ok(None),
        4 => {}
        _ => return Err(PackageError::Invalid("the file is cut".into())),
    }
    let len = u32::from_be_bytes(prefix);
    if len > MAX_RECORD {
        return Err(PackageError::Invalid(format!("a record of {len} bytes")));
    }
    let mut record = vec![0u8; len as usize];
    reader.read_exact(&mut record).await.map_err(|e| {
        if e.kind() == std::io::ErrorKind::UnexpectedEof {
            PackageError::Invalid("the file is cut".into())
        } else {
            e.into()
        }
    })?;
    Buffer::decode(record.as_slice())
        .map(Some)
        .map_err(|e| PackageError::Invalid(format!("a record is not a Buffer: {e}")))
}

/// The id of the service in a Metadata: its SHA3-256 hash.
fn id_in_metadata(metadata: &Metadata) -> Option<[u8; 32]> {
    metadata
        .hashtag
        .as_ref()?
        .hash
        .iter()
        .find_map(id_in_hash)
}

fn id_in_hash(hash: &Hash) -> Option<[u8; 32]> {
    (hash.r#type == SHA3_256_TYPE).then(|| hash.value.as_slice().try_into().ok())?
}

/// Read the head of the package at `path`: its layout and the id of its service. It
/// reads until the Service part starts, so it does not read the Service.
pub async fn inspect(path: &Path) -> Result<PackageInfo, PackageError> {
    let file = tokio::fs::File::open(path).await?;
    let bytes = file.metadata().await?.len();
    let mut reader = BufReader::new(file);
    let mut layout = None;
    let mut service_id = None;
    let mut has_service = false;
    // The message that is open: its index and its bytes (only small parts are kept).
    let mut open: Option<(i32, Vec<u8>)> = None;
    while let Some(buffer) = next_record(&mut reader).await? {
        if let Some(head) = &buffer.head {
            if open.is_none() {
                let index = head.index;
                let detected = *layout.get_or_insert(match index {
                    1 | 2 => Layout::NodoExport,
                    _ => Layout::Gateway,
                });
                let (_, service_index) = detected.indices();
                if index == service_index {
                    has_service = true;
                    break;
                }
                open = Some((index, Vec::new()));
            }
        }
        if let Some((_, data)) = open.as_mut() {
            if buffer.block.is_some() {
                return Err(PackageError::Invalid("a block before the Service".into()));
            }
            if let Some(chunk) = &buffer.chunk {
                data.extend_from_slice(chunk);
                if data.len() > MAX_RECORD as usize {
                    return Err(PackageError::Invalid("a part before the Service is too large".into()));
                }
            }
        }
        if buffer.separator == Some(true) {
            if let (Some((index, data)), Some(l)) = (open.take(), layout) {
                let (metadata_index, _) = l.indices();
                if index == metadata_index {
                    let metadata = Metadata::decode(data.as_slice())
                        .map_err(|e| PackageError::Invalid(format!("the Metadata: {e}")))?;
                    service_id = service_id.or(id_in_metadata(&metadata));
                } else if index == 4 {
                    if let Ok(hash) = Hash::decode(data.as_slice()) {
                        service_id = service_id.or(id_in_hash(&hash));
                    }
                }
            }
        }
    }
    let layout = layout.ok_or_else(|| PackageError::Invalid("the file is empty".into()))?;
    Ok(PackageInfo {
        layout,
        bytes,
        service_id,
        has_service,
    })
}

/// The Buffers of the package at `path` for a node, with the indices of `StartService`.
/// The file is read while the Buffers are sent. An error of the file, or a cancel, is
/// an error of the stream (the node then refuses the input).
pub fn read(path: PathBuf, layout: Layout, cancel: Cancel) -> Buffers {
    let (tx, rx) = tokio::sync::mpsc::channel::<Result<Buffer, WireError>>(4);
    tokio::spawn(async move {
        let failed = |e: PackageError| Err(WireError::Relay(e.to_string()));
        let file = match tokio::fs::File::open(&path).await {
            Ok(file) => file,
            Err(e) => {
                let _ = tx.send(failed(e.into())).await;
                return;
            }
        };
        let mut reader = BufReader::new(file);
        loop {
            if cancel.is_cancelled() {
                let _ = tx.send(failed(PackageError::Cancelled)).await;
                return;
            }
            let item = match next_record(&mut reader).await {
                Ok(Some(mut buffer)) => {
                    if let Some(head) = buffer.head.as_mut() {
                        head.index = layout.for_node(head.index);
                    }
                    cancel.add(4 + buffer.encoded_len() as u64);
                    Ok(buffer)
                }
                Ok(None) => return,
                Err(e) => failed(e),
            };
            let stop = item.is_err();
            if tx.send(item).await.is_err() || stop {
                return;
            }
        }
    });
    Box::pin(tokio_stream::wrappers::ReceiverStream::new(rx))
}

/// The folder of the library inside `dir`, a private directory of the app.
pub fn library_dir(dir: &Path) -> PathBuf {
    dir.join("packages").join("library")
}

/// The file of the service `service_id` in the library.
pub fn library_path(dir: &Path, service_id: &[u8; 32]) -> PathBuf {
    library_dir(dir).join(format!("{}.bee", hex::encode(service_id)))
}

/// A package that was loaded into the library.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Imported {
    /// The id of the service.
    pub service_id: [u8; 32],
    /// Where the file is now.
    pub path: PathBuf,
    pub info: PackageInfo,
}

/// Load the package at `source` into the library under `dir`: check it, then move it to
/// `<dir>/packages/library/<service id>.bee`. A file that is not a package of a service,
/// or that does not say which service it is, is refused and left where it is. The id comes
/// from the Metadata or from a hash part: the app does not hash a whole service on the
/// phone. A package of a service that the library already has replaces it.
///
/// The file is moved when `source` is on the same disk (the copy of the file picker is in
/// the cache of the app), and copied otherwise, so a large service is never in memory and
/// is not on the phone twice for long.
pub async fn import(source: &Path, dir: &Path) -> Result<Imported, PackageError> {
    let info = inspect(source).await?;
    if !info.has_service {
        return Err(PackageError::Invalid("the file has no Service part".into()));
    }
    let service_id = info.service_id.ok_or_else(|| {
        PackageError::Invalid("the file does not say which service it is".into())
    })?;
    let folder = library_dir(dir);
    tokio::fs::create_dir_all(&folder).await?;
    let target = library_path(dir, &service_id);
    // The new file is written next to the target and renamed, so the library never holds
    // a cut file, also if the phone stops in the middle.
    let partial = partial_path(&target);
    let _ = tokio::fs::remove_file(&partial).await;
    match tokio::fs::rename(source, &partial).await {
        Ok(()) => {}
        Err(_) => {
            tokio::fs::copy(source, &partial).await.inspect_err(|_| {
                let _ = std::fs::remove_file(&partial);
            })?;
            let _ = tokio::fs::remove_file(source).await;
        }
    }
    tokio::fs::rename(&partial, &target).await?;
    Ok(Imported {
        service_id,
        path: target,
        info,
    })
}

/// Delete the file of a package in the library. A file that is not there is not an error.
pub async fn remove_file(path: &Path) -> Result<(), PackageError> {
    match tokio::fs::remove_file(path).await {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}
