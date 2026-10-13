//! The data of the compute overview of the home screen (`docs/celaut/ui.md`, section 2):
//! the compute that the nodes of the app offer, the credit of the app on them, and the
//! instances that run with their cost so far.
//!
//! The nodes are the ones in the database of the app (one per peer_id). A node that does
//! not answer is counted as unreachable, and its values are unknown, never 0.

use std::time::Duration;

use celaut_client::overview::{credit_nano_erg, nano_erg_of, offer_of, offered, Offer, Total};

use super::celaut::CelautError;
use super::celaut_db::db;
use super::celaut_service::{address_of_key, cost_so_far, session, Session};

/// How long the overview waits for one node.
const NODE_TIMEOUT: Duration = Duration::from_secs(15);

/// A sum where some parts can be unknown. `total` is `None` (the screen shows
/// "unknown") if a part is unknown or there is no part; `known` and `unknown_nodes` are
/// the known part and the number of unknown parts.
#[derive(Debug, Clone, PartialEq)]
pub struct CoresTotalView {
    pub total: Option<f64>,
    pub known: f64,
    pub unknown_nodes: u32,
}

/// [`CoresTotalView`] for a number of bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BytesTotalView {
    pub total: Option<i64>,
    pub known: i64,
    pub unknown_nodes: u32,
}

/// [`CoresTotalView`] for nanoERG, as text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NanoErgTotalView {
    pub total: Option<String>,
    pub known: String,
    pub unknown_nodes: u32,
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
    pub nodes: Vec<NodeComputeView>,
    pub instances: Vec<RunningInstanceView>,
}

fn to_i64(v: Option<u64>) -> Option<i64> {
    v.map(|v| i64::try_from(v).unwrap_or(i64::MAX))
}

fn bytes_total(t: Total<u64>, parts: u32) -> BytesTotalView {
    BytesTotalView {
        total: to_i64(t.value(parts)),
        known: i64::try_from(t.known).unwrap_or(i64::MAX),
        unknown_nodes: t.unknown,
    }
}

#[flutter_rust_bridge::frb(ignore)]
struct Reached {
    session: Option<Session>,
    address: String,
    error: Option<String>,
    credit_mu: Option<u128>,
}

/// A session on the node at one of its addresses, the last one first.
async fn reach(addresses: &[String]) -> Reached {
    let mut last_error = None;
    for text in addresses {
        let Some(address) = address_of_key(text) else {
            continue;
        };
        match tokio::time::timeout(NODE_TIMEOUT, session(&address)).await {
            Ok(Ok(s)) => {
                let credit_mu = match tokio::time::timeout(NODE_TIMEOUT, s.balance()).await {
                    Ok(Ok(b)) => Some(b),
                    _ => None,
                };
                return Reached {
                    session: Some(s),
                    address: text.clone(),
                    error: None,
                    credit_mu,
                };
            }
            Ok(Err(e)) => last_error = Some(e.message),
            Err(_) => last_error = Some("the node did not answer in time".into()),
        }
    }
    Reached {
        session: None,
        address: addresses.first().cloned().unwrap_or_default(),
        error: Some(last_error.unwrap_or_else(|| "the app has no address of this node".into())),
        credit_mu: None,
    }
}

/// Ask every node of the app for its advertisement and the balance of the client, and
/// every instance for its balance. The nodes are asked at the same time.
#[flutter_rust_bridge::frb]
pub async fn celaut_compute_overview() -> Result<ComputeOverviewView, CelautError> {
    let data = db().snapshot();
    let asks = data.nodes.iter().map(|(peer_id, node)| async move {
        let mut addresses = node.addresses.clone();
        addresses.dedup();
        (peer_id.clone(), reach(&addresses).await)
    });
    let reached = futures::future::join_all(asks).await;

    let mut nodes = Vec::new();
    let mut offers: Vec<(String, Offer)> = Vec::new();
    let mut credits: Vec<(String, Option<u128>)> = Vec::new();
    let mut unreachable = 0u32;
    for (peer_id, r) in &reached {
        let (offer, rate) = match &r.session {
            // The session checked that the advertisement is from this peer_id.
            Some(s) if s.peer_id() == peer_id => {
                (Some(offer_of(&s.info().peer)), s.mu_per_nano_erg())
            }
            _ => (None, None),
        };
        let credit_nano = r.credit_mu.and_then(|mu| nano_erg_of(mu, rate));
        match offer {
            Some(o) => offers.push((peer_id.clone(), o)),
            None => unreachable += 1,
        }
        credits.push((peer_id.clone(), credit_nano));
        let o = offer.unwrap_or_default();
        nodes.push(NodeComputeView {
            peer_id: peer_id.clone(),
            address: r.address.clone(),
            reachable: offer.is_some(),
            error: if offer.is_some() {
                None
            } else {
                r.error
                    .clone()
                    .or_else(|| Some("the node is now another node".into()))
            },
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
    let credit_parts = u32::try_from(credits.len()).unwrap_or(u32::MAX);

    let mut instances = Vec::new();
    for (instance_id, record) in &data.instances {
        let found = reached
            .iter()
            .find(|(p, _)| *p == record.peer_id)
            .and_then(|(_, r)| r.session.clone());
        let balance = match &found {
            Some(s) => {
                match tokio::time::timeout(NODE_TIMEOUT, s.instance_balance(&record.token)).await {
                    Ok(Ok(b)) => Some(b),
                    _ => None,
                }
            }
            None => None,
        };
        let cost = balance.and_then(|b| cost_so_far(record.start_charge_mu.as_deref(), b));
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
        },
        mem_bytes: bytes_total(sums.mem_bytes, sums.nodes),
        disk_bytes: bytes_total(sums.disk_bytes, sums.nodes),
        credit_nano_erg: NanoErgTotalView {
            total: credit.value(credit_parts).map(|n| n.to_string()),
            known: credit.known.to_string(),
            unknown_nodes: credit.unknown,
        },
        nodes,
        instances,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
