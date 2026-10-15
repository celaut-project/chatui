//! A service as a package: save the Buffers of `GetService`, inspect a `.bee` file, and
//! read it for a node with the indices of `StartService`.

use std::path::PathBuf;

use bee_rpc::buffer::buffer::Head;
use bee_rpc::buffer::Buffer;
use bee_rpc::frame::{serialize_part, ParseOptions, Parser, Part};
use bee_rpc::hash::HashAlgorithm;
use bee_rpc::pointer::block_pointer;
use celaut_client::package::{inspect, read, save, Cancel, Layout, PackageError};
use celaut_proto::celaut::metadata::hash_tag::Hash;
use celaut_proto::celaut::metadata::HashTag;
use celaut_proto::celaut::Metadata;
use celaut_wire::gateway::SHA3_256_TYPE;
use celaut_wire::{Buffers, WireError};
use prost::Message;
use tokio_stream::StreamExt;

fn dir() -> PathBuf {
    let d = std::env::temp_dir().join(format!(
        "celaut-package-{}-{}",
        std::process::id(),
        rand_suffix()
    ));
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn rand_suffix() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos() as u64
}

const SERVICE_ID: [u8; 32] = [7u8; 32];

fn metadata() -> Vec<u8> {
    Metadata {
        hashtag: Some(HashTag {
            hash: vec![Hash {
                r#type: SHA3_256_TYPE.to_vec(),
                value: SERVICE_ID.to_vec(),
            }],
            ..Default::default()
        }),
        ..Default::default()
    }
    .encode_to_vec()
}

/// The Buffers of a service part with one block, as a node sends a Service: a head,
/// some bytes, a block with its content, more bytes, a separator.
fn service_buffers(index: i32, content: &[u8]) -> Vec<Buffer> {
    let id = HashAlgorithm::Sha3_256.digest(content);
    let marker = || Buffer {
        block: Some(block_pointer(&id, HashAlgorithm::Sha3_256, false)),
        ..Default::default()
    };
    vec![
        Buffer {
            head: Some(Head {
                index,
                partitions: vec![],
            }),
            chunk: Some(b"before".to_vec()),
            ..Default::default()
        },
        marker(),
        Buffer {
            chunk: Some(content.to_vec()),
            ..Default::default()
        },
        marker(),
        Buffer {
            chunk: Some(b"after".to_vec()),
            separator: Some(true),
            ..Default::default()
        },
    ]
}

/// What `GetService` answers: the hash (4), the Metadata (5), the Service (6), and a
/// flow control signal at the end.
fn get_service_answer(content: &[u8]) -> Vec<Buffer> {
    let hash = Hash {
        r#type: SHA3_256_TYPE.to_vec(),
        value: SERVICE_ID.to_vec(),
    };
    let mut out: Vec<Buffer> = serialize_part(&Part::new(4, hash.encode_to_vec())).collect();
    out.extend(serialize_part(&Part::new(5, metadata())));
    out.extend(service_buffers(6, content));
    out.push(Buffer {
        signal: Some(true),
        ..Default::default()
    });
    out
}

fn stream(buffers: Vec<Buffer>) -> Buffers {
    Box::pin(tokio_stream::iter(buffers.into_iter().map(Ok)))
}

async fn collect(mut s: Buffers) -> Result<Vec<Buffer>, WireError> {
    let mut out = Vec::new();
    while let Some(item) = s.next().await {
        out.push(item?);
    }
    Ok(out)
}

/// The parts that a node parses from `buffers`, with the indices of StartService.
fn parse(buffers: Vec<Buffer>) -> Vec<Part> {
    let mut parser = Parser::new(ParseOptions::accepting([1, 2, 3, 4, 5, 6]));
    let mut parts = Vec::new();
    for b in buffers {
        parts.extend(parser.push(b).unwrap());
    }
    parts.extend(parser.finish().unwrap());
    parts
}

#[tokio::test]
async fn the_answer_of_get_service_is_saved_and_read_back_for_a_node() {
    let d = dir();
    let path = d.join("service.bee");
    let content = vec![42u8; 3 * 1024 * 1024];
    let cancel = Cancel::new();
    let bytes = save(stream(get_service_answer(&content)), &path, &cancel).await.unwrap();
    assert_eq!(bytes, std::fs::metadata(&path).unwrap().len());
    assert_eq!(cancel.bytes(), bytes);
    assert!(!d.join("service.bee.partial").exists());

    let info = inspect(&path).await.unwrap();
    assert_eq!(info.layout, Layout::Gateway);
    assert_eq!(info.service_id, Some(SERVICE_ID));
    assert!(info.has_service);
    assert_eq!(info.bytes, bytes);

    let back = collect(read(path, info.layout, Cancel::new())).await.unwrap();
    // The signal of the call is not part of the package.
    assert!(back.iter().all(|b| b.signal.is_none()));
    let parts = parse(back);
    assert_eq!(parts.iter().map(|p| p.index).collect::<Vec<_>>(), [4, 5, 6]);
    let mut expected = b"before".to_vec();
    expected.extend(&content);
    expected.extend(b"after");
    assert!(parts[2].data == expected, "the Service with its block");
    std::fs::remove_dir_all(d).unwrap();
}

#[tokio::test]
async fn a_nodo_export_gets_the_indices_of_start_service() {
    let d = dir();
    let path = d.join("echo.celaut.bee");
    // `nodo export`: Metadata at 1, Service at 2, no hash part.
    let mut file: Vec<Buffer> = serialize_part(&Part::new(1, metadata())).collect();
    file.extend(service_buffers(2, b"the filesystem"));
    let mut raw = Vec::new();
    bee_rpc::bee_file::write_bee(&mut raw, file).unwrap();
    std::fs::write(&path, raw).unwrap();

    let info = inspect(&path).await.unwrap();
    assert_eq!(info.layout, Layout::NodoExport);
    assert_eq!(info.service_id, Some(SERVICE_ID), "from the Metadata");
    assert!(info.has_service);

    let parts = parse(collect(read(path, info.layout, Cancel::new())).await.unwrap());
    assert_eq!(parts.iter().map(|p| p.index).collect::<Vec<_>>(), [5, 6]);
    std::fs::remove_dir_all(d).unwrap();
}

#[tokio::test]
async fn a_node_that_does_not_have_the_service_gives_nothing_and_no_file_stays() {
    let d = dir();
    let path = d.join("none.bee");
    let only_signal = vec![Buffer {
        signal: Some(true),
        ..Default::default()
    }];
    let error = save(stream(only_signal), &path, &Cancel::new()).await.unwrap_err();
    assert!(matches!(error, PackageError::Invalid(_)), "{error}");
    assert!(!path.exists() && !d.join("none.bee.partial").exists());
    std::fs::remove_dir_all(d).unwrap();
}

#[tokio::test]
async fn an_error_of_the_node_or_a_cancel_leaves_no_file() {
    let d = dir();
    let path = d.join("cut.bee");
    let mut items: Vec<Result<Buffer, WireError>> =
        get_service_answer(b"x").into_iter().take(4).map(Ok).collect();
    items.push(Err(WireError::Call("the node stopped".into())));
    let error = save(Box::pin(tokio_stream::iter(items)), &path, &Cancel::new())
        .await
        .unwrap_err();
    assert!(matches!(error, PackageError::Wire(_)), "{error}");
    assert!(!path.exists() && !d.join("cut.bee.partial").exists());

    let cancel = Cancel::new();
    cancel.cancel();
    let error = save(stream(get_service_answer(b"x")), &path, &cancel).await.unwrap_err();
    assert!(matches!(error, PackageError::Cancelled), "{error}");
    assert!(!path.exists());
    std::fs::remove_dir_all(d).unwrap();
}

#[tokio::test]
async fn a_cut_file_or_a_cancel_is_an_error_of_the_stream_for_the_node() {
    let d = dir();
    let path = d.join("service.bee");
    save(stream(get_service_answer(&[1u8; 1000])), &path, &Cancel::new()).await.unwrap();
    let full = std::fs::read(&path).unwrap();
    // Cut inside a record, and inside the length of a record.
    for cut in [10, full.len() - 2] {
        std::fs::write(&path, &full[..cut]).unwrap();
        let error = collect(read(path.clone(), Layout::Gateway, Cancel::new()))
            .await
            .unwrap_err();
        assert!(matches!(error, WireError::Relay(ref t) if t.contains("cut")), "{cut}: {error}");
    }

    std::fs::write(&path, &full).unwrap();
    let cancel = Cancel::new();
    cancel.cancel();
    let error = collect(read(path, Layout::Gateway, cancel)).await.unwrap_err();
    assert!(matches!(error, WireError::Relay(ref t) if t.contains("cancel")), "{error}");
    std::fs::remove_dir_all(d).unwrap();
}

#[tokio::test]
async fn files_that_are_not_packages_are_refused() {
    let d = dir();
    let empty = d.join("empty.bee");
    std::fs::write(&empty, b"").unwrap();
    assert!(matches!(inspect(&empty).await, Err(PackageError::Invalid(_))));

    let huge = d.join("huge.bee");
    std::fs::write(&huge, u32::MAX.to_be_bytes()).unwrap();
    assert!(matches!(inspect(&huge).await, Err(PackageError::Invalid(_))));

    let garbage = d.join("garbage.bee");
    let mut raw = 5u32.to_be_bytes().to_vec();
    raw.extend([0xff; 5]);
    std::fs::write(&garbage, raw).unwrap();
    assert!(matches!(inspect(&garbage).await, Err(PackageError::Invalid(_))));

    assert!(matches!(inspect(&d.join("missing.bee")).await, Err(PackageError::Io(_))));
    std::fs::remove_dir_all(d).unwrap();
}

#[tokio::test]
async fn a_package_without_the_service_id_says_so() {
    let d = dir();
    let path = d.join("no-id.bee");
    let mut file: Vec<Buffer> = serialize_part(&Part::new(1, Metadata::default().encode_to_vec()))
        .collect();
    file.extend(service_buffers(2, b"fs"));
    let mut raw = Vec::new();
    bee_rpc::bee_file::write_bee(&mut raw, file).unwrap();
    std::fs::write(&path, raw).unwrap();
    let info = inspect(&path).await.unwrap();
    assert_eq!(info.service_id, None);
    assert!(info.has_service);
    std::fs::remove_dir_all(d).unwrap();
}
