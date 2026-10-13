//! The figures of the compute overview (`docs/celaut/ui.md`, section 2).
//!
//! - The compute that the reachable nodes **offer**: the sum of the advertised
//!   resources, not of the free resources. A node counts once, by its peer_id, also
//!   when the app reaches it at more than one address.
//! - A value that a node does not give is unknown, never 0. A sum with an unknown part
//!   is unknown; the known part and the number of unknown nodes are kept, so that the
//!   screen can choose how to show them.
//! - The credit on the nodes, in MU of each node and in nanoERG at the rate of that
//!   node. MU of two nodes are not added: MU is local to each node.

use std::collections::BTreeMap;

use celaut_proto::celaut::{ArchitectureResources, Peer};

/// The resources that one node advertises. `None` is a value that the node does not
/// give.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Offer {
    pub cpu_cores: Option<f64>,
    pub mem_bytes: Option<u64>,
    pub disk_bytes: Option<u64>,
}

/// One value of the advertisement of a node, for each architecture entry. A node can
/// give more than one entry (one per architecture). The overview takes the largest
/// entry for each value, so that two entries of one machine are not added.
fn largest<T: PartialOrd + Copy>(values: impl Iterator<Item = Option<T>>) -> Option<T> {
    values
        .flatten()
        .fold(None, |best: Option<T>, v| match best {
            Some(b) if b >= v => Some(b),
            _ => Some(v),
        })
}

/// The cores of one entry: `cpu_quota / cpu_period` (the period is 100000 when absent).
fn cores(entry: &ArchitectureResources) -> Option<f64> {
    let r = entry.resources.as_ref()?;
    let period = r.cpu_period.filter(|p| *p > 0).unwrap_or(100_000);
    r.cpu_quota.map(|q| q as f64 / period as f64)
}

/// The offer of a node from its advertisement.
pub fn offer_of(peer: &Peer) -> Offer {
    let entries = &peer.resources;
    Offer {
        cpu_cores: largest(entries.iter().map(cores)),
        mem_bytes: largest(
            entries
                .iter()
                .map(|e| e.resources.as_ref().and_then(|r| r.mem_limit)),
        ),
        disk_bytes: largest(
            entries
                .iter()
                .map(|e| e.resources.as_ref().and_then(|r| r.disk_space)),
        ),
    }
}

/// A sum where some parts can be unknown.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Total<T> {
    /// The sum of the known parts.
    pub known: T,
    /// How many parts are unknown.
    pub unknown: u32,
}

impl<T: Copy> Total<T> {
    /// The sum, or `None` if a part is unknown or there is no part.
    pub fn value(&self, parts: u32) -> Option<T> {
        (self.unknown == 0 && parts > 0).then_some(self.known)
    }
}

/// The compute that the reachable nodes offer.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Offered {
    /// The reachable nodes, each peer_id once.
    pub nodes: u32,
    pub cpu_cores: Total<f64>,
    pub mem_bytes: Total<u64>,
    pub disk_bytes: Total<u64>,
}

/// Add the offers of the reachable nodes. A peer_id that comes more than once counts
/// once (its first offer).
pub fn offered<'a>(offers: impl IntoIterator<Item = (&'a str, Offer)>) -> Offered {
    let mut unique: BTreeMap<&str, Offer> = BTreeMap::new();
    for (peer_id, offer) in offers {
        unique.entry(peer_id).or_insert(offer);
    }
    let mut total = Offered::default();
    for offer in unique.values() {
        total.nodes += 1;
        match offer.cpu_cores {
            Some(c) => total.cpu_cores.known += c,
            None => total.cpu_cores.unknown += 1,
        }
        match offer.mem_bytes {
            Some(m) => total.mem_bytes.known = total.mem_bytes.known.saturating_add(m),
            None => total.mem_bytes.unknown += 1,
        }
        match offer.disk_bytes {
            Some(d) => total.disk_bytes.known = total.disk_bytes.known.saturating_add(d),
            None => total.disk_bytes.unknown += 1,
        }
    }
    total
}

/// The nanoERG value of `mu` MU of a node with `mu_per_nano_erg` MU per nanoERG,
/// rounded down. `None` if the node gives no rate.
pub fn nano_erg_of(mu: u128, mu_per_nano_erg: Option<u128>) -> Option<u128> {
    let rate = mu_per_nano_erg.filter(|r| *r > 0)?;
    Some(mu / rate)
}

/// The credit of the app on the nodes in nanoERG, from the credit of each node
/// (`None` if unknown: the node is unreachable, or gives no balance or no rate). Each
/// peer_id counts once.
pub fn credit_nano_erg<'a>(
    nodes: impl IntoIterator<Item = (&'a str, Option<u128>)>,
) -> Total<u128> {
    let mut unique: BTreeMap<&str, Option<u128>> = BTreeMap::new();
    for (peer_id, value) in nodes {
        unique.entry(peer_id).or_insert(value);
    }
    let mut total: Total<u128> = Total::default();
    for value in unique.values() {
        match value {
            Some(v) => total.known = total.known.saturating_add(*v),
            None => total.unknown += 1,
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;
    use celaut_proto::celaut::Sysresources;

    fn entry(quota: Option<u64>, mem: Option<u64>, disk: Option<u64>) -> ArchitectureResources {
        ArchitectureResources {
            resources: Some(Sysresources {
                cpu_quota: quota,
                mem_limit: mem,
                disk_space: disk,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    fn offer(cpu: Option<f64>, mem: Option<u64>, disk: Option<u64>) -> Offer {
        Offer {
            cpu_cores: cpu,
            mem_bytes: mem,
            disk_bytes: disk,
        }
    }

    #[test]
    fn a_node_at_two_addresses_counts_once() {
        let a = offer(Some(2.0), Some(4), Some(10));
        let b = offer(Some(1.0), Some(1), Some(1));
        let total = offered([("peer-a", a), ("peer-b", b), ("peer-a", a)]);
        assert_eq!(total.nodes, 2);
        assert_eq!(total.cpu_cores.value(total.nodes), Some(3.0));
        assert_eq!(total.mem_bytes.value(total.nodes), Some(5));
        assert_eq!(total.disk_bytes.value(total.nodes), Some(11));
    }

    #[test]
    fn a_missing_value_is_unknown_not_zero() {
        let total = offered([
            ("peer-a", offer(Some(2.0), None, Some(10))),
            ("peer-b", offer(Some(1.0), Some(8), Some(1))),
        ]);
        assert_eq!(total.mem_bytes.value(total.nodes), None);
        assert_eq!(total.mem_bytes.known, 8);
        assert_eq!(total.mem_bytes.unknown, 1);
        assert_eq!(total.cpu_cores.value(total.nodes), Some(3.0));
        // No reachable node: nothing is known, which is not 0.
        let none = offered(std::iter::empty());
        assert_eq!(none.nodes, 0);
        assert_eq!(none.cpu_cores.value(none.nodes), None);
    }

    #[test]
    fn the_offer_of_a_node_takes_the_largest_entry() {
        let peer = Peer {
            resources: vec![
                entry(Some(200_000), Some(1 << 30), None),
                entry(Some(400_000), Some(1 << 20), None),
            ],
            ..Default::default()
        };
        let o = offer_of(&peer);
        assert_eq!(o.cpu_cores, Some(4.0));
        assert_eq!(o.mem_bytes, Some(1 << 30));
        assert_eq!(o.disk_bytes, None);
        assert_eq!(offer_of(&Peer::default()), Offer::default());
    }

    #[test]
    fn the_credit_uses_the_rate_of_each_node() {
        assert_eq!(nano_erg_of(10_000_000, Some(1)), Some(10_000_000));
        assert_eq!(nano_erg_of(10, Some(3)), Some(3));
        assert_eq!(nano_erg_of(10, Some(0)), None);
        assert_eq!(nano_erg_of(10, None), None);
        let total = credit_nano_erg([("a", Some(5)), ("b", None), ("a", Some(7)), ("c", Some(1))]);
        assert_eq!(total.known, 6);
        assert_eq!(total.unknown, 1);
        assert_eq!(total.value(3), None);
        assert_eq!(credit_nano_erg([("a", Some(5))]).value(1), Some(5));
    }
}
