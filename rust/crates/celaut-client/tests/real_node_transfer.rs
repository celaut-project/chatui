//! The bytes of a service that the app sends to a real node with a quote, before and
//! after the node has the service (`docs/celaut/package.md`, "A node that already has the
//! service"). Quotes are free: no deposit, no instance. A node that does not have the
//! service stores it (that is what the transfer is for).
//!
//! `#[ignore]`d: it needs a real nodo Gateway and a `.celaut.bee` file.
//!
//! ```text
//! CELAUT_NODE_PORT=53460 CELAUT_PACKAGE=/tmp/653cdd.celaut.bee CELAUT_MODES=before,after \
//!   cargo test -p celaut-client --test real_node_transfer -- --ignored --nocapture
//! ```
//!
//! Modes, in the order given:
//!
//! - `before`: the call of the app before this change (`Transport::call_buffers`, the
//!   bee-rpc relay call): all the service goes, also to a node that has it.
//! - `after`: `NodeSession::quote_with_service` (`relay::call_with_service`, with the
//!   wait for an early answer).
//! - `after-nowait`: `relay::call_with_service` with no wait: the service starts at once,
//!   and stops when the answer comes.
//! - `inspect` alone: only say which service the package holds (no connection).
//!
//! Optional: `CELAUT_NODE_HOST` (default `127.0.0.1`).

use std::time::{Duration, Instant};

use celaut_client::package::{inspect, read, Cancel};
use celaut_client::{MemoryPeerStore, NodeSession};
use celaut_proto::celaut::{Configuration, EstimatedCost};
use celaut_wire::gateway::SERVICE_TRANSFER_TIMEOUT;
use celaut_wire::{ConnectOptions, Connection, SendCounter, Skips, Transport, WireError};
use prost::Message;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

fn cost(answer: Result<Vec<bee_rpc::frame::Part>, WireError>) -> Result<EstimatedCost, String> {
    let parts = answer.map_err(|e| e.to_string())?;
    let part = parts
        .iter()
        .find(|p| p.index == 1)
        .ok_or("no EstimatedCost")?;
    EstimatedCost::decode(part.data.as_slice()).map_err(|e| e.to_string())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a real node and a package: see the comment at the top of the file"]
async fn bytes_of_the_service_that_the_node_gets() {
    let host = env("CELAUT_NODE_HOST").unwrap_or_else(|| "127.0.0.1".into());
    let port: u16 = env("CELAUT_NODE_PORT")
        .expect("set CELAUT_NODE_PORT")
        .parse()
        .expect("port");
    let package = std::path::PathBuf::from(env("CELAUT_PACKAGE").expect("set CELAUT_PACKAGE"));
    let modes = env("CELAUT_MODES").unwrap_or_else(|| "before,after".into());
    let info = inspect(&package).await.expect("a package");
    let id = info.service_id.expect("the package says its service");
    println!(
        "package {} ({} bytes), service {}",
        package.display(),
        info.bytes,
        hex::encode(id)
    );
    if modes == "inspect" {
        return;
    }

    let connection = Connection::connect(&host, port, ConnectOptions::default())
        .await
        .expect("connect");
    let peer_id = connection.peer_id().to_string();
    let session = NodeSession::open(connection, &peer_id, &MemoryPeerStore::new())
        .await
        .expect("a session");
    println!("node {peer_id}");

    for mode in modes.split(',') {
        let sent = SendCounter::new();
        let service = sent.wrap(read(package.clone(), info.layout, Cancel::new()));
        let request = session.request(id, Configuration::default());
        let started = Instant::now();
        let result = match mode {
            "before" => {
                use tokio_stream::StreamExt;
                let head: Vec<Result<bee_rpc::buffer::Buffer, WireError>> = request
                    .parts()
                    .iter()
                    .flat_map(|p| bee_rpc::frame::serialize_part(p).collect::<Vec<_>>())
                    .map(Ok)
                    .collect();
                let input = Box::pin(tokio_stream::iter(head).chain(service));
                cost(
                    session
                        .transport()
                        .call_buffers(
                            "GetServiceEstimatedCost",
                            input,
                            &[1],
                            SERVICE_TRANSFER_TIMEOUT,
                        )
                        .await,
                )
            }
            "after" => session
                .quote_with_service(id, Configuration::default(), service, &Skips::new())
                .await
                .map_err(|e| e.to_string()),
            "after-nowait" => cost(
                celaut_wire::relay::call_with_service(
                    session.transport().channel(),
                    "/celaut.Gateway/GetServiceEstimatedCost",
                    request.parts(),
                    service,
                    &[1],
                    SERVICE_TRANSFER_TIMEOUT,
                    Duration::ZERO,
                    &Skips::new(),
                )
                .await,
            ),
            other => panic!("unknown mode {other}"),
        };
        let quote = match &result {
            Ok(c) => format!("cost {:?}", c.cost.as_ref().map(|a| a.n.as_str())),
            Err(e) => format!("error: {e}"),
        };
        println!(
            "RESULT mode={mode} service_bytes_sent={} buffers={} whole_service={} seconds={:.2} {quote}",
            sent.bytes(),
            sent.buffers(),
            sent.ended(),
            started.elapsed().as_secs_f64(),
        );
    }
}
