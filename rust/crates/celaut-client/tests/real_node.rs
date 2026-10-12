//! Integration test of milestone M2 against a real node: quote, start, a call through
//! the local port, stop, and the refund in `GetMetrics`.
//!
//! It is `#[ignore]`d because it needs a running nodo (x86_64 with KVM) that already
//! has the service in its registry, and it spends the free credit of a new client on
//! that node. Reach the Gateway through a local port, for example an SSH port-forward
//! (no new firewall rule on the host):
//!
//! ```text
//! ssh -N -L 18460:127.0.0.1:53460 node-host &
//! CELAUT_NODE_PORT=18460 CELAUT_SERVICE_ID=<64 hex> \
//!   cargo test -p celaut-client --test real_node -- --ignored --nocapture
//! ```
//!
//! Optional: `CELAUT_NODE_HOST` (default `127.0.0.1`), `CELAUT_HTTP_PATH` (default
//! `/`) and `CELAUT_INITIAL_MU`, the balance of the instance at the start (default
//! 1000000 MU; the default of the node is one hour of the resources, more than the free
//! credit). The service must answer HTTP/1.1 on its first slot.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use celaut_balancer::QuoteCache;
use celaut_client::session::parse_service_id;
use celaut_client::{quotes, LocalPort, MemoryPeerStore, NodeSession};
use celaut_proto::celaut::{Amount, Configuration};
use celaut_wire::{ConnectOptions, Connection, TunnelOpener};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// One HTTP/1.1 GET on a kept-alive connection. Gives the status code and the body.
async fn get(socket: &mut BufReader<TcpStream>, path: &str) -> std::io::Result<(u16, String)> {
    let request = format!("GET {path} HTTP/1.1\r\nHost: service\r\nConnection: keep-alive\r\n\r\n");
    socket.get_mut().write_all(request.as_bytes()).await?;
    let mut status = String::new();
    if socket.read_line(&mut status).await? == 0 {
        return Err(std::io::ErrorKind::UnexpectedEof.into());
    }
    let code = status
        .split_whitespace()
        .nth(1)
        .and_then(|c| c.parse().ok())
        .ok_or(std::io::ErrorKind::InvalidData)?;
    let mut length = 0usize;
    loop {
        let mut line = String::new();
        if socket.read_line(&mut line).await? == 0 {
            return Err(std::io::ErrorKind::UnexpectedEof.into());
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("content-length") {
                length = value
                    .trim()
                    .parse()
                    .map_err(|_| std::io::ErrorKind::InvalidData)?;
            }
        }
    }
    let mut body = vec![0u8; length];
    socket.read_exact(&mut body).await?;
    Ok((code, String::from_utf8_lossy(&body).into_owned()))
}

#[tokio::test]
#[ignore = "needs a real node: see the comment at the top of the file"]
async fn quote_start_call_stop_and_refund() {
    let host = env("CELAUT_NODE_HOST").unwrap_or_else(|| "127.0.0.1".into());
    let port: u16 = env("CELAUT_NODE_PORT")
        .expect("set CELAUT_NODE_PORT")
        .parse()
        .expect("port");
    let service_id =
        parse_service_id(&env("CELAUT_SERVICE_ID").expect("set CELAUT_SERVICE_ID")).expect("id");
    let path = env("CELAUT_HTTP_PATH").unwrap_or_else(|| "/".into());
    let configuration = Configuration {
        initial_mu: Some(Amount {
            n: env("CELAUT_INITIAL_MU").unwrap_or_else(|| "1000000".into()),
        }),
        ..Default::default()
    };

    let connection = Connection::connect(&host, port, ConnectOptions::default())
        .await
        .expect("connect");
    let peer_id = connection.peer_id().to_string();
    let store = MemoryPeerStore::new();
    let session = NodeSession::open(connection, &peer_id, &store)
        .await
        .expect("open a session");
    let credit = session.balance().await.expect("balance");
    println!("node {peer_id}\nfree credit of the new client: {credit} MU");

    // The quote, through the balancer.
    let cache = Mutex::new(QuoteCache::new());
    let ranked = quotes(&[&session], service_id, &configuration, &cache).await;
    assert!(ranked.failures.is_empty(), "{:?}", ranked.failures);
    let best = &ranked.ranked[0];
    println!(
        "quote: {:?}\ncost for the comparison: {:?} nanoERG",
        best.candidate.quote, best.cost_nano_erg
    );
    let cost = celaut_balancer::amount(best.candidate.quote.cost.as_ref()).expect("cost");
    assert!(
        cost <= credit,
        "the quote {cost} is more than the credit {credit}"
    );

    // Start.
    let started = session
        .start(service_id, configuration.clone())
        .await
        .expect("start");
    let slots = started.slots();
    let after_start = session.balance().await.expect("balance");
    let instance_balance = session
        .instance_balance(&started.token)
        .await
        .expect("metrics");
    println!(
        "started: slots {slots:?}\nclient balance after the start: {after_start} MU\ninstance balance: {instance_balance} MU"
    );
    assert!(!slots.is_empty(), "the instance has no slot");
    assert!(after_start < credit, "the start cost nothing");

    // Calls through the local port, all on one TCP connection (one stream). The
    // service can need a moment to listen: a connection that closes before an answer
    // is tried again.
    let opener: Arc<dyn TunnelOpener> = Arc::new(session.transport().clone());
    let local = LocalPort::bind(opener, started.token.clone(), slots[0])
        .await
        .expect("local port");
    let deadline = Instant::now() + Duration::from_secs(120);
    let (mut socket, first) = loop {
        let mut socket = BufReader::new(
            TcpStream::connect(("127.0.0.1", local.port()))
                .await
                .expect("connect to the local port"),
        );
        match tokio::time::timeout(Duration::from_secs(20), get(&mut socket, &path)).await {
            Ok(Ok(answer)) => break (socket, answer),
            other => {
                assert!(
                    Instant::now() < deadline,
                    "no answer through the tunnel: {other:?}, last error {:?}",
                    local.last_error()
                );
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    };
    let streams_before = local.streams_opened();
    let mut answers = vec![first];
    for _ in 0..2 {
        answers.push(get(&mut socket, &path).await.expect("kept-alive call"));
    }
    println!("answers through the tunnel: {answers:?}");
    assert!(answers.iter().all(|(code, _)| *code == 200), "{answers:?}");
    assert_eq!(
        local.streams_opened(),
        streams_before,
        "the kept-alive calls opened new streams"
    );
    drop(socket);
    let instance_after_calls = session
        .instance_balance(&started.token)
        .await
        .expect("metrics");
    println!(
        "streams opened: {}\ninstance balance after the calls: {instance_after_calls} MU",
        local.streams_opened()
    );
    drop(local);

    // Stop, and the refund in the balance of the client.
    let before_stop = session.balance().await.expect("balance");
    let refund = session.stop(&started.token).await.expect("stop");
    let after_stop = session.balance().await.expect("balance");
    println!(
        "refund: {refund} MU\nclient balance: {before_stop} MU before the stop, {after_stop} MU after"
    );
    assert!(refund > 0, "no refund");
    assert_eq!(
        after_stop,
        before_stop + refund,
        "the refund is not in GetMetrics"
    );
    // The node forgets the token of a stopped instance.
    let gone = session.instance_balance(&started.token).await;
    assert!(
        gone.is_err(),
        "the stopped instance is still known: {gone:?}"
    );
}
