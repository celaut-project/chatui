//! The transfer of a service to the real nodo Gateway: a quote that carries the service,
//! `GetService`, and an input that is cut. `#[ignore]`d, with the same setup as
//! `nodo.rs`:
//!
//! ```text
//! NODO_DIR=/path/to/nodo NODO_PYTHON=/path/to/python \
//!   cargo test -p celaut-client --test nodo_service -- --ignored --test-threads=1
//! ```
//!
//! nodo master `5649c2c` (2026-10-15) with bee_rpc v0.0.2 was used.

use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};

use bee_rpc::buffer::Buffer;
use bee_rpc::frame::{serialize_part, ParseOptions, Parser, Part};
use bee_rpc::hash::HashAlgorithm;
use celaut_client::package::{inspect, read, save, Cancel, Layout, PackageError};
use celaut_client::refusal::{classify, Refusal};
use celaut_client::{ClientError, MemoryPeerStore, NodeSession};
use celaut_proto::celaut::metadata::hash_tag::Hash;
use celaut_proto::celaut::metadata::HashTag;
use celaut_proto::celaut::service::Container;
use celaut_proto::celaut::{Configuration, Metadata, Service};
use celaut_wire::gateway::SHA3_256_TYPE;
use celaut_wire::{Buffers, ConnectOptions, Connection, WireError};
use prost::Message;

struct Node {
    child: Child,
    port: u16,
    peer_id: String,
}

impl Drop for Node {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn start() -> Node {
    let dir = std::env::var("NODO_DIR").expect("set NODO_DIR to a nodo checkout");
    let python = std::env::var("NODO_PYTHON").expect("set NODO_PYTHON");
    let script = format!("{}/tests/nodo_gateway.py", env!("CARGO_MANIFEST_DIR"));
    let mut child = Command::new(python)
        .arg(script)
        .env("PYTHONPATH", dir)
        .current_dir(std::env::temp_dir())
        .stdout(Stdio::piped())
        .spawn()
        .expect("start nodo_gateway.py");
    let mut lines = BufReader::new(child.stdout.take().expect("stdout")).lines();
    while let Some(Ok(line)) = lines.next() {
        if let Some(rest) = line.strip_prefix("READY ") {
            let (port, peer_id) = rest.split_once(' ').expect("READY port peer_id");
            std::thread::spawn(move || for line in lines.map_while(Result::ok) { println!("nodo: {line}") });
            return Node {
                child,
                port: port.parse().expect("port"),
                peer_id: peer_id.to_string(),
            };
        }
    }
    panic!("nodo_gateway.py ended before READY");
}

async fn session(node: &Node) -> NodeSession<Connection> {
    let connection = Connection::connect("127.0.0.1", node.port, ConnectOptions::default())
        .await
        .expect("connect");
    NodeSession::open(connection, &node.peer_id, &MemoryPeerStore::new())
        .await
        .expect("a session")
}

/// A service with a filesystem of `size` bytes, and its package with the indices of
/// `StartService`: the hash (4), the Metadata (5) and the Service (6), with no block,
/// as a phone could send it the first time.
fn package(seed: u8, size: usize) -> ([u8; 32], Vec<u8>, Vec<Buffer>) {
    let filesystem: Vec<u8> = (0..size)
        .map(|i| (i as u8).wrapping_mul(31).wrapping_add(seed))
        .collect();
    let service = Service {
        prose: format!("a test service {seed}"),
        container: Some(Container {
            filesystem,
            ..Default::default()
        }),
        ..Default::default()
    }
    .encode_to_vec();
    let id: [u8; 32] = HashAlgorithm::Sha3_256.digest(&service).try_into().unwrap();
    let hash = Hash {
        r#type: SHA3_256_TYPE.to_vec(),
        value: id.to_vec(),
    };
    let metadata = Metadata {
        hashtag: Some(HashTag {
            hash: vec![hash.clone()],
            ..Default::default()
        }),
        ..Default::default()
    };
    let mut buffers: Vec<Buffer> = serialize_part(&Part::new(4, hash.encode_to_vec())).collect();
    buffers.extend(serialize_part(&Part::new(5, metadata.encode_to_vec())));
    buffers.extend(serialize_part(&Part::new(6, service.clone())));
    (id, service, buffers)
}

fn stream(items: Vec<Result<Buffer, WireError>>) -> Buffers {
    Box::pin(tokio_stream::iter(items))
}

fn refusal_of(e: &ClientError) -> Option<Refusal> {
    match e {
        ClientError::Wire(WireError::Call(text)) => classify(text),
        _ => None,
    }
}

/// The Buffers of a package file.
async fn buffers_of(path: &std::path::Path) -> Vec<Buffer> {
    use tokio_stream::StreamExt;
    let mut out = Vec::new();
    let mut s = read(path.to_path_buf(), Layout::Gateway, Cancel::new());
    while let Some(b) = s.next().await {
        out.push(b.unwrap());
    }
    out
}

/// Save what `GetService` of `s` gives for `id` to `path`.
async fn get(s: &NodeSession<Connection>, id: [u8; 32], path: &std::path::Path) -> Result<u64, PackageError> {
    match s.get_service(id).await {
        Ok(raw) => save(raw, path, &Cancel::new()).await,
        Err(e) => Err(PackageError::Invalid(format!("GetService: {e}"))),
    }
}

#[tokio::test]
#[ignore = "needs a nodo checkout: see the comment at the top of the file"]
async fn a_service_goes_from_the_phone_to_node_a_then_from_node_a_to_node_b() {
    let (a, b) = (start(), start());
    let (sa, sb) = (session(&a).await, session(&b).await);
    let (id, service, buffers) = package(1, 3 * 1024 * 1024 + 17);
    let dir = std::env::temp_dir().join(format!("nodo-relay-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();

    // The phone gives the service to node A with a quote.
    let before = sa.quote(id, Configuration::default()).await.unwrap_err();
    assert_eq!(refusal_of(&before), Some(Refusal::ServiceMissing), "{before}");
    let quote = sa
        .quote_with_service(id, Configuration::default(), stream(buffers.into_iter().map(Ok).collect()))
        .await;
    println!("node A, the quote with the service: {quote:?}");
    if let Err(e) = &quote {
        // Without a manager and KVM the node may not price it, but it has it now.
        assert_ne!(refusal_of(e), Some(Refusal::ServiceMissing), "{e}");
    }

    // GetService of node A: the Buffers that nodo makes, kept in a file.
    let from_a = dir.join("from-a.bee");
    let bytes = get(&sa, id, &from_a).await.expect("node A gives the service");
    let info = inspect(&from_a).await.unwrap();
    let framed = buffers_of(&from_a).await;
    let blocks = framed.iter().filter(|b| b.block.is_some()).count();
    println!("node A gave {bytes} bytes, {} Buffers, {blocks} block markers", framed.len());
    assert_eq!((info.layout, info.service_id, info.has_service), (Layout::Gateway, Some(id), true));

    // A transfer to node B that is cut in the middle of the Service: B refuses it.
    let six = framed
        .iter()
        .position(|b| b.head.as_ref().is_some_and(|h| h.index == 6))
        .expect("a Service part");
    let cut_at = six + (framed.len() - six) / 2;
    let mut cut: Vec<Result<Buffer, WireError>> = framed.iter().take(cut_at).cloned().map(Ok).collect();
    cut.push(Err(WireError::Relay("the file is cut".into())));
    let error = sb
        .quote_with_service(id, Configuration::default(), stream(cut))
        .await
        .unwrap_err();
    assert!(
        matches!(error, ClientError::Wire(WireError::Relay(ref t)) if t == "the file is cut"),
        "{error}"
    );
    let after_cut = sb.quote(id, Configuration::default()).await.unwrap_err();
    assert_eq!(
        refusal_of(&after_cut),
        Some(Refusal::ServiceMissing),
        "node B must not keep a cut service: {after_cut}"
    );

    // The whole transfer from the file: node B has it, the same bytes.
    let quote = sb
        .quote_with_service(id, Configuration::default(), read(from_a.clone(), info.layout, Cancel::new()))
        .await;
    println!("node B, the quote with the service: {quote:?}");
    if let Err(e) = &quote {
        assert_ne!(refusal_of(e), Some(Refusal::ServiceMissing), "{e}");
    }
    let from_b = dir.join("from-b.bee");
    get(&sb, id, &from_b).await.expect("node B gives the service");
    let mut parser = Parser::new(ParseOptions::accepting([4, 5, 6]));
    let mut parts = Vec::new();
    for b in buffers_of(&from_b).await {
        parts.extend(parser.push(b).unwrap());
    }
    parts.extend(parser.finish().unwrap());
    let got = parts.iter().find(|p| p.index == 6).expect("a Service part");
    assert!(got.data == service, "node B has the service that the phone gave to node A");
    std::fs::remove_dir_all(dir).unwrap();
}

#[tokio::test]
#[ignore = "needs a nodo checkout: see the comment at the top of the file"]
async fn a_first_transfer_cut_in_the_service_is_not_stored() {
    let node = start();
    let s = session(&node).await;
    let (id, _service, buffers) = package(2, 3 * 1024 * 1024);
    let six = buffers
        .iter()
        .position(|b| b.head.as_ref().is_some_and(|h| h.index == 6))
        .unwrap();
    let mut items: Vec<Result<Buffer, WireError>> = buffers.into_iter().take(six + 2).map(Ok).collect();
    items.push(Err(WireError::Relay("the file is cut".into())));
    let error = s
        .quote_with_service(id, Configuration::default(), stream(items))
        .await
        .unwrap_err();
    assert!(
        matches!(error, ClientError::Wire(WireError::Relay(ref t)) if t == "the file is cut"),
        "{error}"
    );
    let again = s.quote(id, Configuration::default()).await.unwrap_err();
    assert_eq!(refusal_of(&again), Some(Refusal::ServiceMissing), "{again}");
}
