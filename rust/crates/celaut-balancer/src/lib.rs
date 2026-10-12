//! The execution balancer of a light client (`docs/celaut/balancer.md`): it puts the
//! quotes of several nodes in one unit, scores them as nodo does, and sorts them, best
//! first.
//!
//! - [`erg_rate`] and [`to_nano_erg`]: MU conversion. MU is local to each node; the
//!   `mu_per_unit` of its ERG payment contract says how many of its MU one nanoERG is
//!   worth. The client compares quotes in nanoERG (a client rate of 1 MU per nanoERG,
//!   the default of nodo), rounded up.
//! - [`cost_mu`] and [`score`]: the port of `nodo:src/balancers/estimated_cost_sorter`
//!   and `nodo:src/balancers/scoring.py`.
//! - [`rank`]: the order. A stable sort, so equal scores keep the order of the input.
//! - [`QuoteCache`]: the cache of `nodo:src/utils/tools/query_cache.py` (10 s, 4096
//!   entries).
//!
//! Not in this crate yet: the filter on the advertised resources (it needs the
//! resources of the service, which the client does not have before the catalog), and
//! the event log of local reputation. Until then the reputation terms are 0.
//!
//! Input from a peer must never make this crate panic.
#![forbid(unsafe_code)]
#![cfg_attr(
    not(test),
    deny(clippy::unwrap_used, clippy::expect_used, clippy::panic)
)]

use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

use celaut_proto::celaut::{Amount, EstimatedCost, Peer};

/// `balancers.COST_AVERAGE_VARIATION` of nodo (default 1).
pub const COST_AVERAGE_VARIATION: f64 = 1.0;
/// `SOCIALIZATION_FACTOR`: the weight of the local reputation.
pub const REPUTATION_WEIGHT: f64 = 2.0;
/// The half credit of the local reputation.
pub const REPUTATION_HALF_CREDIT: f64 = 50.0;
/// The weight of the on-chain reputation.
pub const ONCHAIN_WEIGHT: f64 = 0.3;
/// The weight of the donations.
pub const DONATION_WEIGHT: f64 = 0.3;

const HOUR_SECONDS: f64 = 3600.0;

/// An error of the balancer.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum BalancerError {
    /// An amount is not a decimal integer that is 0 or more.
    #[error("the amount {0:?} is not a decimal integer that is 0 or more")]
    BadAmount(String),
    /// An amount is too large for this client.
    #[error("the amount is too large")]
    TooLarge,
    /// The node has no ERG payment contract with a rate, so its MU cannot be compared.
    #[error("the node gives no rate for ERG")]
    NoErgRate,
}

/// The value of an `Amount`. An absent amount is 0.
pub fn amount(value: Option<&Amount>) -> Result<u128, BalancerError> {
    let Some(value) = value else { return Ok(0) };
    let text = value.n.trim();
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) {
        return Err(BalancerError::BadAmount(value.n.clone()));
    }
    text.parse::<u128>().map_err(|_| BalancerError::TooLarge)
}

/// The MU per nanoERG of the node: the `mu_per_unit` of its first payment contract on
/// the ledger `ergo` with the asset `ERG`.
pub fn erg_rate(peer: &Peer) -> Result<u128, BalancerError> {
    for rate in &peer.payment_contracts {
        let Some(contract) = &rate.contract else {
            continue;
        };
        let on_ergo = contract
            .ledger
            .as_ref()
            .and_then(|l| l.tags.first())
            .is_some_and(|t| t == "ergo");
        let erg = contract
            .xattrs
            .iter()
            .any(|e| e.key == "token_id" && e.value.as_deref() == Some(b"ERG".as_slice()));
        if on_ergo && erg {
            let mu = amount(rate.mu_per_unit.as_ref())?;
            if mu > 0 {
                return Ok(mu);
            }
        }
    }
    Err(BalancerError::NoErgRate)
}

/// `mu` of a node with `mu_per_nano_erg` as nanoERG, rounded up (an amount that the
/// client owes). The rate must not be 0.
pub fn to_nano_erg(mu: u128, mu_per_nano_erg: u128) -> u128 {
    if mu_per_nano_erg == 0 {
        return mu;
    }
    mu.div_ceil(mu_per_nano_erg)
}

/// nanoERG as MU of a node, rounded down (an amount that the client gives).
pub fn to_node_mu(nano_erg: u128, mu_per_nano_erg: u128) -> Result<u128, BalancerError> {
    nano_erg
        .checked_mul(mu_per_nano_erg)
        .ok_or(BalancerError::TooLarge)
}

/// `trunc(cost * (1 + variance * k))`, as `variance_cost_normalization` of nodo.
fn vcnorm(cost: u128, variance: f32) -> f64 {
    (cost as f64 * (1.0 + f64::from(variance) * COST_AVERAGE_VARIATION)).trunc()
}

/// The cost of a quote for the comparison, in the unit of its amounts:
/// `trunc(vcnorm(cost) + mean(per_hour(init), per_hour(max)))`, where
/// `per_hour(a) = trunc(vcnorm(a) * 3600 / maintenance_seconds_loop)`, or 0 when the loop
/// is 0 or less. As in nodo, the arithmetic is in floating point.
pub fn cost_mu(quote: &EstimatedCost) -> Result<f64, BalancerError> {
    let variance = quote.variance;
    let per_hour = |a: Option<&Amount>| -> Result<f64, BalancerError> {
        let seconds = quote.maintenance_seconds_loop;
        if seconds <= 0 {
            return Ok(0.0);
        }
        Ok((vcnorm(amount(a)?, variance) * HOUR_SECONDS / f64::from(seconds)).trunc())
    };
    let init = per_hour(quote.init_maintenance_cost.as_ref())?;
    let max = per_hour(quote.max_maintenance_cost.as_ref())?;
    Ok((vcnorm(amount(quote.cost.as_ref())?, variance) + (init + max) / 2.0).trunc())
}

/// `x / (|x| + half)`.
pub fn reputation_factor(reputation: f64, half_credit: f64) -> f64 {
    let half = if half_credit == 0.0 {
        REPUTATION_HALF_CREDIT
    } else {
        half_credit.abs()
    };
    reputation / (reputation.abs() + half)
}

/// What the client knows about a node besides its price. All 0 for now.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Standing {
    /// Local reputation, from the events of this client.
    pub reputation: f64,
    /// On-chain reputation, already in (-1, 1).
    pub onchain: f64,
    /// Donation bonus, already in [0, 1).
    pub donation: f64,
}

/// `-ln(cost) + W_r * f(r, H_r) + W_o * o + W_d * d`. A cost of 0 or less is `+inf`
/// (a free offer is the best one). Higher is better.
pub fn score(cost: f64, standing: Standing) -> f64 {
    if cost <= 0.0 {
        return f64::INFINITY;
    }
    -cost.ln()
        + REPUTATION_WEIGHT * reputation_factor(standing.reputation, REPUTATION_HALF_CREDIT)
        + ONCHAIN_WEIGHT * standing.onchain
        + DONATION_WEIGHT * standing.donation
}

/// One quote of one node.
#[derive(Debug, Clone, PartialEq)]
pub struct Candidate {
    /// The identity of the node.
    pub peer_id: String,
    /// The answer of `GetServiceEstimatedCost`, in the MU of the node.
    pub quote: EstimatedCost,
    /// The MU per nanoERG of the node. `None` if the node gives no ERG rate.
    pub mu_per_nano_erg: Option<u128>,
    /// What the client knows about the node.
    pub standing: Standing,
}

/// A candidate after the score.
#[derive(Debug, Clone, PartialEq)]
pub struct Ranked {
    /// The candidate.
    pub candidate: Candidate,
    /// The cost for the comparison ([`cost_mu`]) in nanoERG. `None` when the node has no
    /// ERG rate: then its price cannot be compared with the others.
    pub cost_nano_erg: Option<f64>,
    /// The score. `None` with `cost_nano_erg`.
    pub score: Option<f64>,
}

/// Score the candidates and sort them, best first. A quote whose amounts cannot be
/// read is dropped. Candidates with no ERG rate come after all the others, in their
/// input order: the client can still use them (M2 runs on free credit), but it cannot
/// compare their price.
pub fn rank(candidates: Vec<Candidate>) -> Vec<Ranked> {
    let mut priced = Vec::new();
    let mut unpriced = Vec::new();
    for candidate in candidates {
        let Ok(cost) = cost_mu(&candidate.quote) else {
            continue;
        };
        match candidate.mu_per_nano_erg.filter(|r| *r > 0) {
            Some(rate) => {
                let cost = (cost / rate as f64).ceil();
                let score = score(cost, candidate.standing);
                priced.push(Ranked {
                    candidate,
                    cost_nano_erg: Some(cost),
                    score: Some(score),
                });
            }
            None => unpriced.push(Ranked {
                candidate,
                cost_nano_erg: None,
                score: None,
            }),
        }
    }
    // Stable: equal scores keep the input order. NaN cannot come from the arithmetic
    // above, but it would sort last.
    priced.sort_by(|a, b| {
        let (a, b) = (a.score.unwrap_or(f64::NAN), b.score.unwrap_or(f64::NAN));
        b.partial_cmp(&a).unwrap_or_else(|| a.is_nan().cmp(&b.is_nan()))
    });
    priced.extend(unpriced);
    priced
}

/// The time that a quote stays in the cache.
pub const QUOTE_TTL: Duration = Duration::from_secs(10);
/// The most quotes in the cache.
pub const QUOTE_CACHE_SIZE: usize = 4096;

/// The key of a quote: the node, the service and the configuration as sent (bytes).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct QuoteKey {
    /// The identity of the node.
    pub peer_id: String,
    /// The service id.
    pub service_id: [u8; 32],
    /// The encoded `Configuration`, in the MU of the node.
    pub configuration: Vec<u8>,
}

/// Quotes for [`QUOTE_TTL`], at most [`QUOTE_CACHE_SIZE`]. When it is full, the oldest
/// entry goes. A cache stops repeated calls (the node puts a client that makes more than
/// 120 calls in 60 s in quarantine).
#[derive(Debug, Default)]
pub struct QuoteCache {
    entries: HashMap<QuoteKey, (Instant, EstimatedCost)>,
    order: VecDeque<(Instant, QuoteKey)>,
}

impl QuoteCache {
    /// An empty cache.
    pub fn new() -> Self {
        Self::default()
    }

    /// The quote for `key`, if it is younger than [`QUOTE_TTL`] at `now`.
    pub fn get(&self, key: &QuoteKey, now: Instant) -> Option<EstimatedCost> {
        self.entries
            .get(key)
            .filter(|(at, _)| now.saturating_duration_since(*at) < QUOTE_TTL)
            .map(|(_, quote)| quote.clone())
    }

    /// Keep `quote` for `key` from `now`.
    pub fn put(&mut self, key: QuoteKey, quote: EstimatedCost, now: Instant) {
        self.entries.insert(key.clone(), (now, quote));
        self.order.push_back((now, key));
        // Drop the stale entries of the queue, and the oldest when the cache is full.
        while let Some((at, key)) = self.order.front() {
            let current = self.entries.get(key).map(|(t, _)| *t);
            let replaced = current != Some(*at);
            let expired = now.saturating_duration_since(*at) >= QUOTE_TTL;
            let full = self.entries.len() > QUOTE_CACHE_SIZE;
            if !(replaced || expired || full) {
                break;
            }
            if !replaced {
                self.entries.remove(key);
            }
            self.order.pop_front();
        }
    }

    /// How many quotes are in the cache.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// True when the cache is empty.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}
