//! Integration test against the real nodo Gateway.
//!
//! These tests are `#[ignore]`d because they need a nodo checkout and a Python with its
//! requirements. They run the real `Gateway()` of nodo (without firewall, manager or
//! services: M1 starts no service, so no root and no KVM are needed) on a local TLS port
//! with `nodo_gateway.py`. Run them like this:
//!
//! ```text
//! NODO_DIR=/path/to/nodo NODO_PYTHON=/path/to/python \
//!   cargo test -p celaut-client --test nodo -- --ignored --test-threads=1
//! ```
//!
//! The Python needs the packages of `nodo/bash/requirements.txt` (cryptography, grpcio,
//! protobuf, mnemonic, bip32, ecdsa, PyYAML, psutil, netifaces2, tabulate, requests) and
//! `bee_rpc` v0.0.2. nodo dev `e3d12301` was used.

use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};

use celaut_client::{connect_and_fetch, ClientError, MemoryPeerStore};
use celaut_wire::{ConnectOptions, IdentityError, WireError};

struct Node {
    child: Child,
    port: u16,
    peer_id: String,
    /// What the node printed after READY.
    log: Arc<Mutex<Vec<String>>>,
}

impl Node {
    fn log_contains(&self, text: &str) -> bool {
        self.log
            .lock()
            .expect("log")
            .iter()
            .any(|l| l.contains(text))
    }
}

impl Drop for Node {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn start(extra: &[&str]) -> Node {
    let dir = std::env::var("NODO_DIR").expect("set NODO_DIR to a nodo checkout");
    let python = std::env::var("NODO_PYTHON")
        .expect("set NODO_PYTHON to a Python with the nodo requirements");
    let script = format!("{}/tests/nodo_gateway.py", env!("CARGO_MANIFEST_DIR"));
    let mut child = Command::new(python)
        .arg(script)
        .args(extra)
        .env("PYTHONPATH", dir)
        .current_dir(std::env::temp_dir())
        .stdout(Stdio::piped())
        .spawn()
        .expect("start nodo_gateway.py");
    let stdout = child.stdout.take().expect("stdout");
    let mut lines = BufReader::new(stdout).lines();
    while let Some(line) = lines.next() {
        let line = line.expect("line");
        if let Some(rest) = line.strip_prefix("READY ") {
            let (port, peer_id) = rest.split_once(' ').expect("READY port peer_id");
            let port = port.parse().expect("port");
            // Keep reading, so that the node never blocks on a full pipe.
            let log = Arc::new(Mutex::new(Vec::new()));
            let sink = log.clone();
            std::thread::spawn(move || {
                for line in lines.map_while(Result::ok) {
                    sink.lock().expect("log").push(line);
                }
            });
            return Node {
                child,
                port,
                peer_id: peer_id.to_string(),
                log,
            };
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    panic!("nodo_gateway.py ended before READY");
}

#[tokio::test]
#[ignore = "needs a nodo checkout: see the comment at the top of the file"]
async fn first_contact_gives_the_verified_advertisement() {
    let node = start(&[]);
    let store = MemoryPeerStore::new();
    let info = connect_and_fetch("127.0.0.1", node.port, ConnectOptions::default(), &store)
        .await
        .expect("connect and fetch");
    assert_eq!(info.peer_id, node.peer_id);
    assert_eq!(info.peer.public_key, node.peer_id);
    assert!(info.peer.ts > 1_700_000_000);
    assert!(!info.peer.uri.is_empty(), "the node advertises no address");
    println!("{:#?}", info.peer);

    // The node serves the same signed message for up to 60 s: the same ts is accepted.
    let again = connect_and_fetch("127.0.0.1", node.port, ConnectOptions::default(), &store)
        .await
        .expect("second fetch");
    assert_eq!(again.peer.ts, info.peer.ts);
}

#[tokio::test]
#[ignore = "needs a nodo checkout: see the comment at the top of the file"]
async fn expected_peer_id_is_checked() {
    let node = start(&[]);
    let store = MemoryPeerStore::new();
    let wrong = ConnectOptions {
        expected_peer_id: Some("00".repeat(32)),
        ..Default::default()
    };
    let err = connect_and_fetch("127.0.0.1", node.port, wrong, &store)
        .await
        .unwrap_err();
    assert!(
        matches!(
            err,
            ClientError::Wire(WireError::Identity(IdentityError::PeerMismatch { .. }))
        ),
        "{err:?}"
    );
    let right = ConnectOptions {
        expected_peer_id: Some(node.peer_id.clone()),
        ..Default::default()
    };
    connect_and_fetch("127.0.0.1", node.port, right, &store)
        .await
        .expect("right id");
}

#[tokio::test]
#[ignore = "needs a nodo checkout: see the comment at the top of the file"]
async fn proof_of_work_against_the_node() {
    // After the first client, each next client needs a proof of work of difficulty 1.
    let node = start(&["--free-clients", "1"]);
    for _ in 0..3 {
        let store = MemoryPeerStore::new();
        connect_and_fetch("127.0.0.1", node.port, ConnectOptions::default(), &store)
            .await
            .expect("fetch with proof of work");
    }
    // The node asked for work (the first client was free).
    std::thread::sleep(std::time::Duration::from_millis(300));
    assert!(
        node.log_contains("POW_REQUIRED difficulty=1") && node.log_contains("CLIENT_CREATED"),
        "the node never asked for a proof of work: {:?}",
        node.log.lock().expect("log")
    );
}

#[tokio::test]
#[ignore = "needs a nodo checkout: see the comment at the top of the file"]
async fn a_node_that_is_not_a_node_is_refused() {
    // A port with no TLS server.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind");
    let port = listener.local_addr().expect("addr").port();
    drop(listener);
    let store = MemoryPeerStore::new();
    let err = connect_and_fetch("127.0.0.1", port, ConnectOptions::default(), &store)
        .await
        .unwrap_err();
    assert!(
        matches!(err, ClientError::Wire(WireError::Connect(_))),
        "{err:?}"
    );
}
