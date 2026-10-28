//! The M2 calls on fixed bee-rpc streams: the order of the request, the guard, the
//! quote, the start, the stop, the balance and the quotes of several nodes.

mod common;

use std::sync::Mutex;

use bee_rpc::buffer::Buffer;
use bee_rpc::frame::Part;
use celaut_balancer::{Misfit, QuoteCache, ServiceAsk};
use celaut_client::session::parse_service_id;
use celaut_client::{quotes, quotes_for, ClientError, MemoryPeerStore, NodeSession};
use celaut_proto::celaut::contract::Ledger;
use celaut_proto::celaut::instance::UriSlot;
use celaut_proto::celaut::metadata::hash_tag::Hash;
use celaut_proto::celaut::service::container::Architecture;
use celaut_proto::celaut::{
    Amount, ArchitectureResources, BytesKeyValue, Client, Configuration, Contract, ContractRate,
    EstimatedCost, Instance, Metrics, ModifyDepositInput, ModifyDepositOutput, Peer,
    ExecutionReceipt, RecursionGuard, Refund, ServiceInstance,
    Sysresources, TokenMessage,
};
use celaut_wire::gateway::SHA3_256_TYPE;
use celaut_wire::WireError;
use common::{stream_of, FixedStreams};
use prost::Message;
use ring::signature::{Ed25519KeyPair, KeyPair};

const SERVICE: [u8; 32] = [0xab; 32];

fn mu(n: &str) -> Option<Amount> {
    Some(Amount { n: n.into() })
}

fn signal() -> Buffer {
    Buffer {
        signal: Some(true),
        ..Default::default()
    }
}

/// The Peer of the vectors, signed by the key of `seed`, with only an ERG contract at
/// `mu_per_nano_erg` if given, else with no contract. Gives the Peer and its peer_id.
fn peer_of(seed: u8, mu_per_nano_erg: Option<&str>) -> (Peer, String) {
    peer_with(seed, mu_per_nano_erg, None)
}

/// [`peer_of`], with `resources` as `Peer.resources` if given.
fn peer_with(
    seed: u8,
    mu_per_nano_erg: Option<&str>,
    resources: Option<Vec<ArchitectureResources>>,
) -> (Peer, String) {
    let mut peer = common::vectors().peers[0].peer();
    if let Some(resources) = resources {
        peer.resources = resources;
    }
    peer.payment_contracts.clear();
    if let Some(rate) = mu_per_nano_erg {
        peer.payment_contracts = vec![ContractRate {
            contract: Some(Contract {
                ledger: Some(Ledger {
                    tags: vec!["ergo".into()],
                    ..Default::default()
                }),
                xattrs: vec![BytesKeyValue {
                    key: "token_id".into(),
                    value: Some(b"ERG".to_vec()),
                }],
            }),
            mu_per_unit: mu(rate),
        }];
    }
    let pair = Ed25519KeyPair::from_seed_unchecked(&[seed; 32]).unwrap();
    peer.public_key = hex::encode(pair.public_key().as_ref());
    let digest = celaut_client::peer::content_digest(&peer);
    let payload = celaut_client::peer::signed_payload(&peer.public_key, peer.ts, &digest);
    peer.signature = hex::encode(pair.sign(payload.as_bytes()).as_ref());
    let id = peer.public_key.clone();
    (peer, id)
}

/// A session with the node of `seed`; `more` are the answers after the opening.
async fn session_of(
    seed: u8,
    rate: Option<&str>,
    more: Vec<Vec<Buffer>>,
) -> NodeSession<FixedStreams> {
    session_with(seed, rate, None, more).await
}

/// [`session_of`], with `resources` as `Peer.resources` if given.
async fn session_with(
    seed: u8,
    rate: Option<&str>,
    resources: Option<Vec<ArchitectureResources>>,
    more: Vec<Vec<Buffer>>,
) -> NodeSession<FixedStreams> {
    let (peer, peer_id) = peer_with(seed, rate, resources);
    let mut answers = vec![
        stream_of(
            1,
            &Client {
                client_id: "c11e47000000400080000000000000aa".into(),
                ..Default::default()
            },
        ),
        stream_of(1, &peer),
    ];
    answers.extend(more);
    NodeSession::open(
        FixedStreams::new(answers),
        &peer_id,
        &MemoryPeerStore::new(),
    )
    .await
    .expect("open")
}

async fn session(more: Vec<Vec<Buffer>>) -> NodeSession<FixedStreams> {
    session_of(1, None, more).await
}

fn quote(cost: &str) -> EstimatedCost {
    EstimatedCost {
        cost: mu(cost),
        init_maintenance_cost: mu("0"),
        max_maintenance_cost: mu("0"),
        maintenance_seconds_loop: 0,
        variance: 0.0,
    }
}

/// The answer of GetServiceEstimatedCost and StartService: the signal, then the reply.
fn after_signal(message: &impl Message) -> Vec<Buffer> {
    let mut out = vec![signal()];
    out.extend(stream_of(1, message));
    out
}

fn indices(parts: &[Part]) -> Vec<i32> {
    parts.iter().map(|p| p.index).collect()
}

#[tokio::test]
async fn client_guard_and_configuration_come_before_the_hash() {
    let s = session(vec![after_signal(&quote("5")), after_signal(&quote("5"))]).await;
    let configuration = Configuration {
        initial_mu: mu("1000"),
        ..Default::default()
    };
    s.quote(SERVICE, configuration.clone()).await.unwrap();
    let (method, parts) = s.transport().request(2);
    assert_eq!(method, "GetServiceEstimatedCost");
    assert_eq!(indices(&parts), vec![1, 2, 3, 4]);
    assert_eq!(
        Client::decode(parts[0].data.as_slice()).unwrap().client_id,
        s.client_id()
    );
    assert_eq!(
        Configuration::decode(parts[2].data.as_slice()).unwrap(),
        configuration
    );
    let hash = Hash::decode(parts[3].data.as_slice()).unwrap();
    assert_eq!(hash.r#type, SHA3_256_TYPE.to_vec());
    assert_eq!(hash.value, SERVICE.to_vec());

    // An all-default configuration has no bytes and is not sent; the order stays.
    s.quote(SERVICE, Configuration::default()).await.unwrap();
    let (_, parts) = s.transport().request(3);
    assert_eq!(indices(&parts), vec![1, 2, 4]);
}

#[tokio::test]
async fn the_guard_asks_for_no_delegation() {
    let s = session(vec![after_signal(&quote("5"))]).await;
    s.quote(SERVICE, Configuration::default()).await.unwrap();
    let (_, parts) = s.transport().request(2);
    let guard = RecursionGuard::decode(parts[1].data.as_slice()).unwrap();
    assert_eq!(
        guard,
        RecursionGuard {
            token: String::new(),
            remaining_hops: Some(1),
        }
    );
    // `remaining_hops` is optional: 1 must be on the wire, not left out.
    assert!(!parts[1].data.is_empty());
}

#[tokio::test]
async fn start_gives_the_token_and_the_slots() {
    let instance = ServiceInstance {
        token: "instance-token".into(),
        instance: Some(Instance {
            api: None,
            uri_slot: vec![UriSlot {
                internal_port: 3030,
                uri: vec![],
            }],
        }),
        receipt: Some(ExecutionReceipt {
            kind: "start".into(),
            ..Default::default()
        }),
    };
    let s = session(vec![after_signal(&instance)]).await;
    let started = s.start(SERVICE, Configuration::default()).await.unwrap();
    assert_eq!(started.token, "instance-token");
    assert_eq!(started.slots(), vec![3030]);
    // The start receipt comes with it, for the app to check.
    assert_eq!(started.receipt.map(|r| r.kind).as_deref(), Some("start"));
    let (method, parts) = s.transport().request(2);
    assert_eq!(method, "StartService");
    assert_eq!(indices(&parts), vec![1, 2, 4]);
}

#[tokio::test]
async fn an_instance_with_no_token_is_refused() {
    let instance = ServiceInstance {
        token: String::new(),
        instance: Some(Instance::default()),
        receipt: None,
    };
    let s = session(vec![after_signal(&instance)]).await;
    let err = s
        .start(SERVICE, Configuration::default())
        .await
        .unwrap_err();
    assert!(
        matches!(err, ClientError::Wire(WireError::Protocol(_))),
        "{err:?}"
    );
}

#[tokio::test]
async fn stop_gives_the_refund_and_metrics_the_balance() {
    let s = session(vec![
        stream_of(1, &Refund { amount: mu("123") }),
        stream_of(
            1,
            &Metrics {
                balance: mu("4500000"),
            },
        ),
        // A Refund with no amount has no bytes: nothing arrives, and that is 0.
        vec![],
    ])
    .await;
    assert_eq!(s.stop("instance-token").await.unwrap(), 123);
    let (method, parts) = s.transport().request(2);
    assert_eq!(method, "StopService");
    let token = TokenMessage::decode(parts[0].data.as_slice()).unwrap();
    assert_eq!(token.token, "instance-token");
    assert_eq!(token.slot, None);

    assert_eq!(s.balance().await.unwrap(), 4_500_000);
    let (method, parts) = s.transport().request(3);
    assert_eq!(method, "GetMetrics");
    assert_eq!(
        TokenMessage::decode(parts[0].data.as_slice())
            .unwrap()
            .token,
        s.client_id()
    );
    assert_eq!(s.stop("other").await.unwrap(), 0);
}

#[tokio::test]
async fn a_top_up_moves_credit_to_the_instance_with_modify_deposit() {
    let s = session(vec![
        stream_of(
            1,
            &ModifyDepositOutput {
                success: true,
                message: "Deposit modified correctly".into(),
            },
        ),
        stream_of(
            1,
            &ModifyDepositOutput {
                success: false,
                message: "Error charging the father".into(),
            },
        ),
    ])
    .await;
    s.top_up("instance-token", 250_000).await.unwrap();
    let (method, parts) = s.transport().request(2);
    assert_eq!(method, "ModifyDeposit");
    assert_eq!(parts.len(), 1);
    assert_eq!(parts[0].index, 1);
    let input = ModifyDepositInput::decode(parts[0].data.as_slice()).unwrap();
    assert_eq!(input.service_token, "instance-token");
    assert_eq!(input.difference.unwrap().n, "250000");
    // The node refuses: the client has less credit than that.
    let err = s.top_up("instance-token", 9).await.unwrap_err();
    assert!(err.to_string().contains("Error charging the father"), "{err}");
}

#[tokio::test]
async fn a_bad_amount_is_an_error() {
    let s = session(vec![stream_of(1, &Refund { amount: mu("-1") })]).await;
    let err = s.stop("t").await.unwrap_err();
    assert!(matches!(err, ClientError::Amount(_)), "{err:?}");
}

#[tokio::test]
async fn quotes_rank_the_nodes_and_use_the_cache() {
    // a: 900 MU at 10 MU per nanoERG = 90 nanoERG. c: 100 MU at 1 = 100 nanoERG.
    let a = session_of(1, Some("10"), vec![after_signal(&quote("900"))]).await;
    // b: an answer that cannot be parsed. The node failed and is not a candidate.
    let b = session_of(
        2,
        Some("1"),
        vec![vec![Buffer {
            chunk: Some(vec![1, 2, 3]),
            head: Some(bee_rpc::buffer::buffer::Head {
                index: 9,
                partitions: vec![],
            }),
            separator: Some(true),
            ..Default::default()
        }]],
    )
    .await;
    let c = session_of(3, Some("1"), vec![after_signal(&quote("100"))]).await;
    // d: no ERG rate, so its price cannot be compared: last, even if it is cheap.
    let d = session_of(4, None, vec![after_signal(&quote("1"))]).await;
    let cache = Mutex::new(QuoteCache::new());
    let config = Configuration::default();

    let first = quotes(&[&d, &c, &b, &a], SERVICE, &config, &cache).await;
    let order: Vec<&str> = first
        .ranked
        .iter()
        .map(|r| r.candidate.peer_id.as_str())
        .collect();
    assert_eq!(order, vec![a.peer_id(), c.peer_id(), d.peer_id()]);
    assert_eq!(first.ranked[0].cost_nano_erg, Some(90.0));
    assert_eq!(first.failures.len(), 1);
    assert_eq!(first.failures[0].peer_id, b.peer_id());
    assert!(first.skipped.is_empty());
    assert_eq!(a.transport().calls(), 3);

    // Within 10 s the same question makes no call.
    let again = quotes(&[&a, &c], SERVICE, &config, &cache).await;
    assert_eq!(again.ranked.len(), 2);
    assert_eq!(a.transport().calls(), 3);
    assert_eq!(c.transport().calls(), 3);
}

const GIB: u64 = 1 << 30;

/// One announced entry for `tag` with a memory ceiling.
fn announced(tag: &str, mem_limit: u64) -> ArchitectureResources {
    ArchitectureResources {
        architecture: Some(Architecture {
            tags: vec![tag.into()],
            ..Default::default()
        }),
        resources: Some(Sysresources {
            mem_limit: Some(mem_limit),
            ..Default::default()
        }),
    }
}

#[tokio::test]
async fn quotes_for_skips_the_nodes_that_can_never_run_the_service_and_does_not_call_them() {
    let answer = || vec![after_signal(&quote("100"))];
    // Big enough, too small, another architecture only, and a node that announced nothing.
    let big = session_with(1, Some("1"), Some(vec![announced("amd64", 4 * GIB)]), answer()).await;
    let small =
        session_with(2, Some("1"), Some(vec![announced("x86_64", GIB)]), answer()).await;
    let arm = session_with(3, Some("1"), Some(vec![announced("arm64", 8 * GIB)]), answer()).await;
    let silent = session_with(4, Some("1"), Some(vec![]), answer()).await;
    let ask = ServiceAsk {
        architecture: Some("linux/amd64"),
        resources: Sysresources {
            mem_limit: Some(2 * GIB),
            ..Default::default()
        },
    };
    let cache = Mutex::new(QuoteCache::new());
    let config = Configuration::default();

    let answer = quotes_for(
        &[&big, &small, &arm, &silent],
        SERVICE,
        &config,
        &cache,
        Some(&ask),
    )
    .await;

    let mut asked: Vec<&str> = answer
        .ranked
        .iter()
        .map(|r| r.candidate.peer_id.as_str())
        .collect();
    asked.sort();
    let mut expected = vec![big.peer_id(), silent.peer_id()];
    expected.sort();
    assert_eq!(asked, expected);
    assert!(answer.failures.is_empty());
    let skipped: Vec<&str> = answer.skipped.iter().map(|s| s.peer_id.as_str()).collect();
    assert_eq!(skipped, vec![small.peer_id(), arm.peer_id()]);
    assert!(matches!(
        answer.skipped[0].misfits.as_slice(),
        [Misfit::MemLimit { .. }]
    ));
    assert!(matches!(
        answer.skipped[1].misfits.as_slice(),
        [Misfit::NotRun { .. }]
    ));
    // The opening is 2 calls. A node that was asked has one more; a skipped one has none.
    assert_eq!(big.transport().calls(), 3);
    assert_eq!(silent.transport().calls(), 3);
    assert_eq!(small.transport().calls(), 2);
    assert_eq!(arm.transport().calls(), 2);
}

#[tokio::test]
async fn quotes_for_with_no_ask_or_no_known_architecture_skips_no_node() {
    let answer = || vec![after_signal(&quote("100"))];
    let small =
        session_with(2, Some("1"), Some(vec![announced("amd64", 1)]), answer()).await;
    let config = Configuration::default();
    let no_ask = quotes_for(
        &[&small],
        SERVICE,
        &config,
        &Mutex::new(QuoteCache::new()),
        None,
    )
    .await;
    assert_eq!(no_ask.ranked.len(), 1);
    assert!(no_ask.skipped.is_empty());

    let small =
        session_with(2, Some("1"), Some(vec![announced("amd64", 1)]), answer()).await;
    let unknown = ServiceAsk {
        architecture: None,
        resources: Sysresources {
            mem_limit: Some(u64::MAX),
            ..Default::default()
        },
    };
    let no_arch = quotes_for(
        &[&small],
        SERVICE,
        &config,
        &Mutex::new(QuoteCache::new()),
        Some(&unknown),
    )
    .await;
    assert_eq!(no_arch.ranked.len(), 1);
    assert!(no_arch.skipped.is_empty());
}

#[test]
fn service_ids_are_64_hex_characters() {
    let text = "ab".repeat(32);
    assert_eq!(parse_service_id(&text), Some(SERVICE));
    assert_eq!(parse_service_id(&text.to_uppercase()), Some(SERVICE));
    assert_eq!(parse_service_id(&format!(" {text} ")), Some(SERVICE));
    assert_eq!(parse_service_id(&text[2..]), None);
    assert_eq!(parse_service_id(&"zz".repeat(32)), None);
}

#[tokio::test]
async fn a_resumed_session_keeps_the_client_id_and_makes_no_new_client() {
    let (peer, peer_id) = peer_of(1, None);
    let store = celaut_client::CelautDb::in_memory();
    let session = NodeSession::resume(
        FixedStreams::new(vec![stream_of(1, &peer)]),
        &peer_id,
        "c11e47000000400080000000000000bb".into(),
        &store,
    )
    .await
    .expect("resume");
    assert_eq!(session.client_id(), "c11e47000000400080000000000000bb");
    // One call only: GetPeerInfo, not GenerateClient.
    assert_eq!(session.transport().calls(), 1);
    assert_eq!(session.transport().request(0).0, "GetPeerInfo");
    // The advertisement went into the database of the app.
    assert!(store.read(|d| d.seen.contains_key(&peer_id)));
}
