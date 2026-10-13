//! The M2 calls on fixed bee-rpc streams: the order of the request, the guard, the
//! quote, the start, the stop, the balance and the quotes of several nodes.

mod common;

use std::sync::Mutex;

use bee_rpc::buffer::Buffer;
use bee_rpc::frame::Part;
use celaut_balancer::QuoteCache;
use celaut_client::session::parse_service_id;
use celaut_client::{quotes, ClientError, MemoryPeerStore, NodeSession};
use celaut_proto::celaut::contract::Ledger;
use celaut_proto::celaut::instance::UriSlot;
use celaut_proto::celaut::metadata::hash_tag::Hash;
use celaut_proto::celaut::{
    Amount, BytesKeyValue, Client, Configuration, Contract, ContractRate, EstimatedCost, Instance,
    Metrics, Peer, RecursionGuard, Refund, ServiceInstance, TokenMessage,
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
    let mut peer = common::vectors().peers[0].peer();
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
    let (peer, peer_id) = peer_of(seed, rate);
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
    };
    let s = session(vec![after_signal(&instance)]).await;
    let started = s.start(SERVICE, Configuration::default()).await.unwrap();
    assert_eq!(started.token, "instance-token");
    assert_eq!(started.slots(), vec![3030]);
    let (method, parts) = s.transport().request(2);
    assert_eq!(method, "StartService");
    assert_eq!(indices(&parts), vec![1, 2, 4]);
}

#[tokio::test]
async fn an_instance_with_no_token_is_refused() {
    let instance = ServiceInstance {
        token: String::new(),
        instance: Some(Instance::default()),
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
    assert_eq!(a.transport().calls(), 3);

    // Within 10 s the same question makes no call.
    let again = quotes(&[&a, &c], SERVICE, &config, &cache).await;
    assert_eq!(again.ranked.len(), 2);
    assert_eq!(a.transport().calls(), 3);
    assert_eq!(c.transport().calls(), 3);
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
