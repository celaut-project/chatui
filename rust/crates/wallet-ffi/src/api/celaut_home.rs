//! The data of the compute overview of the home screen (`docs/celaut/ui.md`, section 2):
//! the compute that the nodes of the app offer, the credit of the app on them, and the
//! instances that run with their cost so far.
//!
//! The nodes are the ones in the node list of the user (section 4 of ui.md): the
//! database has one record per peer_id, and a removed node keeps its record but is not
//! in the sums. A node that does not answer is counted as unreachable, and its values
//! are unknown, never 0. A sum with unknown parts is "at least" its known part.

use std::time::Duration;

use celaut_client::overview::{
    credit_nano_erg, nano_erg_of, offer_of, offered, split_credit, Offer, Shown, Total,
};

use super::celaut::{invalid, CelautError, CelautErrorKind};
use super::celaut_db::{db, now_seconds, storage_error};
use super::celaut_service::{address_of_key, cost_so_far, key, session, NodeAddress, Session};

/// How long the overview waits for each step of one node (the connection, then the
/// balance). Short, because the home screen waits for the slowest node: a node that does
/// not answer in this time counts as unreachable, and the checks in the background
/// (`celaut_health`) try it again later.
const NODE_TIMEOUT: Duration = Duration::from_secs(5);

/// [`NODE_TIMEOUT`] through Tor or another proxy, where a circuit is slow.
const NODE_TIMEOUT_PROXY: Duration = Duration::from_secs(20);

fn node_timeout() -> Duration {
    if matches!(celaut_net::route(), celaut_net::Route::Direct) {
        NODE_TIMEOUT
    } else {
        NODE_TIMEOUT_PROXY
    }
}

/// A sum where some parts can be unknown (`docs/celaut/ui.md`, section 2):
/// - `total` is the sum when every part is known;
/// - else, if `at_least` is true, the screen shows "at least `known` (`unknown_nodes`
///   nodes unknown)";
/// - else nothing is known, and the screen shows "unknown", never 0.
#[derive(Debug, Clone, PartialEq)]
pub struct CoresTotalView {
    pub total: Option<f64>,
    pub known: f64,
    pub unknown_nodes: u32,
    pub at_least: bool,
}

/// [`CoresTotalView`] for a number of bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BytesTotalView {
    pub total: Option<i64>,
    pub known: i64,
    pub unknown_nodes: u32,
    pub at_least: bool,
}

/// [`CoresTotalView`] for nanoERG, as text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NanoErgTotalView {
    pub total: Option<String>,
    pub known: String,
    pub unknown_nodes: u32,
    pub at_least: bool,
}

/// One node of the app.
#[derive(Debug, Clone, PartialEq)]
pub struct NodeComputeView {
    pub peer_id: String,
    /// The address (`host:port`) that answered, or the last one known.
    pub address: String,
    pub reachable: bool,
    /// Why the node is unreachable.
    pub error: Option<String>,
    /// What the node advertises (offered, not free). `None` is unknown.
    pub cpu_cores: Option<f64>,
    pub mem_bytes: Option<i64>,
    pub disk_bytes: Option<i64>,
    /// The balance of the client of the app on the node, in MU of the node.
    pub credit_mu: Option<String>,
    /// The MU of the node for one nanoERG.
    pub mu_per_nano_erg: Option<String>,
    /// The credit in nanoERG, at the rate of the node.
    pub credit_nano_erg: Option<String>,
    /// The part of the balance that the user paid, in MU and in nanoERG. The free credit
    /// counts as spent first.
    pub paid_mu: Option<String>,
    pub paid_nano_erg: Option<String>,
    /// The part of the balance that is free credit of the node, in MU and in nanoERG.
    pub free_mu: Option<String>,
    pub free_nano_erg: Option<String>,
    /// True if the node does not know the client id of the app (it forgot it). The
    /// screen asks the user: a new client, or a retry later.
    pub client_unknown: bool,
}

/// An instance that the app started and did not stop.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunningInstanceView {
    pub instance_id: String,
    pub peer_id: String,
    pub service_id: String,
    /// The time of the start, in Unix seconds.
    pub started_at: i64,
    /// The balance of the instance on the node, in MU. `None` is unknown.
    pub balance_mu: Option<String>,
    /// What the instance cost so far, in MU of its node. `None` is unknown.
    pub cost_so_far_mu: Option<String>,
    /// The same in nanoERG, at the rate of the node. `None` is unknown.
    pub cost_so_far_nano_erg: Option<String>,
}

/// The compute overview.
#[derive(Debug, Clone, PartialEq)]
pub struct ComputeOverviewView {
    /// The reachable nodes (each peer_id once): the ones in the sums.
    pub nodes_counted: u32,
    /// The nodes of the app that did not answer.
    pub nodes_unreachable: u32,
    pub cpu_cores: CoresTotalView,
    pub mem_bytes: BytesTotalView,
    pub disk_bytes: BytesTotalView,
    /// The credit of the app on all its nodes, in nanoERG.
    pub credit_nano_erg: NanoErgTotalView,
    /// The part of that credit that the user paid, in nanoERG.
    pub paid_nano_erg: NanoErgTotalView,
    /// The part of that credit that is free credit of the nodes, in nanoERG.
    pub free_nano_erg: NanoErgTotalView,
    pub nodes: Vec<NodeComputeView>,
    pub instances: Vec<RunningInstanceView>,
}

fn to_i64(v: Option<u64>) -> Option<i64> {
    v.map(|v| i64::try_from(v).unwrap_or(i64::MAX))
}

fn at_least<T: Copy>(t: &Total<T>, parts: u32) -> bool {
    matches!(t.shown(parts), Shown::AtLeast { .. })
}

fn bytes_total(t: Total<u64>, parts: u32) -> BytesTotalView {
    BytesTotalView {
        total: to_i64(t.value(parts)),
        known: i64::try_from(t.known).unwrap_or(i64::MAX),
        unknown_nodes: t.unknown,
        at_least: at_least(&t, parts),
    }
}

fn nano_erg_total(t: Total<u128>, parts: u32) -> NanoErgTotalView {
    NanoErgTotalView {
        total: t.value(parts).map(|n| n.to_string()),
        known: t.known.to_string(),
        unknown_nodes: t.unknown,
        at_least: at_least(&t, parts),
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct Reached {
    pub(crate) session: Option<Session>,
    /// The address that answered, or the last one known.
    pub(crate) address: String,
    pub(crate) error: Option<CelautError>,
    pub(crate) credit_mu: Option<u128>,
    /// How long the working address took to answer, in milliseconds. 0 if none worked.
    pub(crate) latency_ms: u32,
}

/// A session on the node at one of its addresses, the last one first.
async fn reach(addresses: &[String]) -> Reached {
    reach_within(addresses, node_timeout()).await
}

/// [`reach`] with a limit of `limit` for each step of each address.
#[flutter_rust_bridge::frb(ignore)]
pub(crate) async fn reach_within(addresses: &[String], limit: Duration) -> Reached {
    let mut last_error = None;
    for text in addresses {
        let Some(address) = address_of_key(text) else {
            continue;
        };
        let started = std::time::Instant::now();
        match tokio::time::timeout(limit, session(&address)).await {
            Ok(Ok(s)) => {
                let credit_mu = match tokio::time::timeout(limit, s.balance()).await {
                    Ok(Ok(b)) => Some(b),
                    _ => None,
                };
                return Reached {
                    session: Some(s),
                    address: text.clone(),
                    error: None,
                    credit_mu,
                    latency_ms: u32::try_from(started.elapsed().as_millis()).unwrap_or(u32::MAX),
                };
            }
            Ok(Err(e)) => last_error = Some(e),
            Err(_) => {
                last_error = Some(CelautError {
                    kind: CelautErrorKind::Timeout,
                    message: "the node did not answer in time".into(),
                })
            }
        }
    }
    Reached {
        session: None,
        address: addresses.first().cloned().unwrap_or_default(),
        error: Some(last_error.unwrap_or_else(|| invalid("the app has no address of this node"))),
        credit_mu: None,
        latency_ms: 0,
    }
}

/// Ask every node of the node list for its advertisement and the balance of the client,
/// and every instance for its balance. The nodes are asked at the same time. A removed
/// node is asked only if an instance of the app runs on it, and it is not in the sums.
#[flutter_rust_bridge::frb]
pub async fn celaut_compute_overview() -> Result<ComputeOverviewView, CelautError> {
    let data = db().snapshot();
    let asks = data
        .nodes
        .iter()
        .filter(|(peer_id, node)| {
            node.listed
                || data
                    .instances
                    .values()
                    .any(|i| i.stopped_at.is_none() && &i.peer_id == *peer_id)
        })
        .map(|(peer_id, node)| async move {
            let mut addresses = node.addresses.clone();
            addresses.dedup();
            (peer_id.clone(), reach(&addresses).await)
        });
    let reached = futures::future::join_all(asks).await;
    // What this reach says about each node is also its last check (`celaut_health`).
    let now = now_seconds();
    super::celaut_health::record(reached.iter().map(|(p, r)| (p.as_str(), r)), now);

    let mut nodes = Vec::new();
    let mut offers: Vec<(String, Offer)> = Vec::new();
    let mut credits: Vec<(String, Option<u128>)> = Vec::new();
    let mut paid: Vec<(String, Option<u128>)> = Vec::new();
    let mut free: Vec<(String, Option<u128>)> = Vec::new();
    let mut unreachable = 0u32;
    for (peer_id, r) in &reached {
        if !data.nodes.get(peer_id).is_some_and(|n| n.listed) {
            continue;
        }
        let (offer, rate) = match &r.session {
            // The session checked that the advertisement is from this peer_id.
            Some(s) if s.peer_id() == peer_id => {
                (Some(offer_of(&s.info().peer)), s.mu_per_nano_erg())
            }
            _ => (None, None),
        };
        let credit_nano = r.credit_mu.and_then(|mu| nano_erg_of(mu, rate));
        let parts = r
            .credit_mu
            .and_then(|mu| split_credit(mu, data.nodes.get(peer_id).and_then(|n| n.paid())));
        let paid_nano = parts.and_then(|p| nano_erg_of(p.paid_mu, rate));
        let free_nano = parts.and_then(|p| nano_erg_of(p.free_mu, rate));
        match offer {
            Some(o) => offers.push((peer_id.clone(), o)),
            None => unreachable += 1,
        }
        credits.push((peer_id.clone(), credit_nano));
        paid.push((peer_id.clone(), paid_nano));
        free.push((peer_id.clone(), free_nano));
        let o = offer.unwrap_or_default();
        nodes.push(NodeComputeView {
            peer_id: peer_id.clone(),
            address: r.address.clone(),
            reachable: offer.is_some(),
            error: if offer.is_some() {
                None
            } else {
                Some(
                    r.error
                        .as_ref()
                        .map(|e| e.message.clone())
                        .unwrap_or_else(|| "the node is now another node".into()),
                )
            },
            client_unknown: r
                .error
                .as_ref()
                .is_some_and(|e| e.kind == CelautErrorKind::ClientUnknown),
            paid_mu: parts.map(|p| p.paid_mu.to_string()),
            paid_nano_erg: paid_nano.map(|n| n.to_string()),
            free_mu: parts.map(|p| p.free_mu.to_string()),
            free_nano_erg: free_nano.map(|n| n.to_string()),
            cpu_cores: o.cpu_cores,
            mem_bytes: to_i64(o.mem_bytes),
            disk_bytes: to_i64(o.disk_bytes),
            credit_mu: r.credit_mu.map(|m| m.to_string()),
            mu_per_nano_erg: rate.map(|m| m.to_string()),
            credit_nano_erg: credit_nano.map(|n| n.to_string()),
        });
    }
    let sums = offered(offers.iter().map(|(p, o)| (p.as_str(), *o)));
    let credit = credit_nano_erg(credits.iter().map(|(p, c)| (p.as_str(), *c)));
    let paid_total = credit_nano_erg(paid.iter().map(|(p, c)| (p.as_str(), *c)));
    let free_total = credit_nano_erg(free.iter().map(|(p, c)| (p.as_str(), *c)));
    let credit_parts = u32::try_from(credits.len()).unwrap_or(u32::MAX);

    let mut instances = Vec::new();
    // A stopped instance stays in the database until the user deletes it; it costs
    // nothing and is not shown here.
    for (instance_id, record) in data.instances.iter().filter(|(_, r)| r.stopped_at.is_none()) {
        let found = reached
            .iter()
            .find(|(p, _)| *p == record.peer_id)
            .and_then(|(_, r)| r.session.clone());
        let balance = match &found {
            Some(s) => {
                match tokio::time::timeout(node_timeout(), s.instance_balance(&record.token)).await {
                    Ok(Ok(b)) => Some(b),
                    _ => None,
                }
            }
            None => None,
        };
        let cost = balance.and_then(|b| {
            cost_so_far(
                record.start_charge_mu.as_deref(),
                record.topped_up_mu.as_deref(),
                b,
            )
        });
        let rate = found.as_ref().and_then(|s| s.mu_per_nano_erg());
        instances.push(RunningInstanceView {
            instance_id: instance_id.clone(),
            peer_id: record.peer_id.clone(),
            service_id: record.service_id.clone(),
            started_at: record.started_at,
            balance_mu: balance.map(|b| b.to_string()),
            cost_so_far_mu: cost.map(|c| c.to_string()),
            cost_so_far_nano_erg: cost
                .and_then(|c| nano_erg_of(c, rate))
                .map(|n| n.to_string()),
        });
    }

    Ok(ComputeOverviewView {
        nodes_counted: sums.nodes,
        nodes_unreachable: unreachable,
        cpu_cores: CoresTotalView {
            total: sums.cpu_cores.value(sums.nodes),
            known: sums.cpu_cores.known,
            unknown_nodes: sums.cpu_cores.unknown,
            at_least: at_least(&sums.cpu_cores, sums.nodes),
        },
        mem_bytes: bytes_total(sums.mem_bytes, sums.nodes),
        disk_bytes: bytes_total(sums.disk_bytes, sums.nodes),
        credit_nano_erg: nano_erg_total(credit, credit_parts),
        paid_nano_erg: nano_erg_total(paid_total, credit_parts),
        free_nano_erg: nano_erg_total(free_total, credit_parts),
        nodes,
        instances,
    })
}

/// A node in the node list of the user (`docs/celaut/ui.md`, section 4).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KnownNodeView {
    pub peer_id: String,
    /// The addresses (`host:port`) where the app reached the node, the last first.
    pub addresses: Vec<String>,
    /// The deposits of the app to this node, from every wallet, in nanoERG.
    pub deposited_nano_erg: u64,
}

fn known_node(data: &celaut_client::CelautData, peer_id: &str) -> Option<KnownNodeView> {
    let node = data.nodes.get(peer_id)?;
    Some(KnownNodeView {
        peer_id: peer_id.to_string(),
        addresses: node.addresses.clone(),
        deposited_nano_erg: data.deposited_nano_erg(peer_id),
    })
}

/// The node list of the user: the nodes in the sums of the home screen.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_known_nodes() -> Vec<KnownNodeView> {
    db().read(|d| {
        d.listed_nodes()
            .filter_map(|(peer_id, _)| known_node(d, peer_id))
            .collect()
    })
}

/// Add the node at `node` to the node list. The app checks the node first (its identity
/// and advertisement). A node that was removed comes back with its client id and its
/// deposits. If the node forgot the client id, the answer is a `ClientUnknown` error and
/// the node is not added.
#[flutter_rust_bridge::frb]
pub async fn celaut_add_node(node: NodeAddress) -> Result<KnownNodeView, CelautError> {
    let s = session(&node).await?;
    list_node(s.peer_id(), &key(&node))
}

/// Put the node `peer_id`, which the app just reached at `address` (`host:port`), in the
/// node list, with that address first.
pub(crate) fn list_node(peer_id: &str, address: &str) -> Result<KnownNodeView, CelautError> {
    db().update(|d| {
        if let Some(record) = d.nodes.get_mut(peer_id) {
            record.listed = true;
        }
        d.note_address(peer_id, address);
    })
    .map_err(storage_error)?;
    db().read(|d| known_node(d, peer_id))
        .ok_or_else(|| invalid("The node is not in the database after the check."))
}

/// Take the node `peer_id` out of the node list and out of the sums of the home screen.
/// Its record stays in the database: the client id, the deposits and the limit. Adding
/// the node again restores them.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_remove_node(peer_id: String) -> Result<(), CelautError> {
    let peer_id = peer_id.trim().to_ascii_lowercase();
    db().update(|d| match d.nodes.get_mut(&peer_id) {
        Some(node) => {
            node.listed = false;
            Ok(())
        }
        None => Err(invalid("This node is not in the node list.")),
    })
    .map_err(storage_error)?
}

#[cfg(test)]
mod tests {
    use super::*;
    use celaut_client::db::{DepositRecord, DepositStage, NodeRecord};

    #[test]
    fn a_removed_node_leaves_the_list_and_keeps_its_deposits() {
        let peer = "ab12".repeat(16);
        db().update(|d| {
            d.nodes.insert(
                peer.clone(),
                NodeRecord {
                    client_id: "c-remove".into(),
                    addresses: vec!["node.example:1".into()],
                    ..Default::default()
                },
            );
            d.deposits.insert(
                "remove-test".into(),
                DepositRecord {
                    peer_id: peer.clone(),
                    address: "node.example:1".into(),
                    deposit_token: "t".into(),
                    nano_erg: 7,
                    mu: "7".into(),
                    pay_to_address: "9f".into(),
                    tx_id: String::new(),
                    made_at: 1,
                    stage: DepositStage::PayableCalled {
                        tx_id: "a".into(),
                        accepted: true,
                    },
                },
            );
        })
        .unwrap();
        assert!(celaut_known_nodes().iter().any(|n| n.peer_id == peer));
        celaut_remove_node(peer.to_uppercase()).unwrap();
        assert!(!celaut_known_nodes().iter().any(|n| n.peer_id == peer));
        // The record and the deposit stay, so adding the node again restores them.
        db().read(|d| {
            assert_eq!(d.nodes[&peer].client_id, "c-remove");
            assert!(!d.nodes[&peer].listed);
            assert_eq!(d.deposited_nano_erg(&peer), 7);
        });
        assert!(celaut_remove_node("00".repeat(32)).is_err());
        db().update(|d| d.nodes.get_mut(&peer).unwrap().listed = true)
            .unwrap();
        let back = celaut_known_nodes();
        let back = back.iter().find(|n| n.peer_id == peer).unwrap();
        assert_eq!(back.deposited_nano_erg, 7);
    }

    #[tokio::test]
    async fn a_node_that_does_not_answer_is_unreachable_and_unknown() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let r = reach(&[format!("127.0.0.1:{port}"), "not an address".into()]).await;
        assert!(r.session.is_none());
        assert!(r.error.is_some());
        assert_eq!(r.credit_mu, None);
        let none = reach(&[]).await;
        assert!(none.error.is_some());
    }
}
