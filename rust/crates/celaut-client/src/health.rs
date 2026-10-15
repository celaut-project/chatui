//! Whether a node is available (milestone M4).
//!
//! The app asks each node of its list for a small answer from time to time, and keeps the
//! result in the Celaut database: when the check was, how long the node took, and why it
//! failed. This module is the model. It has no connection: the check itself is in the
//! FFI crate.
//!
//! - A node is **available** when its last check worked and was fast enough, **slow** when
//!   it worked but took long, and **unreachable** when the last check failed. A node that
//!   was never checked is **unknown**.
//! - A node that fails is checked again later and later (a back-off), so that a node that
//!   is down does not use the battery or the data of the phone. With Tor, everything is
//!   slower, so the times are longer.
//! - The reason of a failure is kept as a short kind and the text of the node.

use serde::{Deserialize, Serialize};

/// A check that takes at least this long, in milliseconds, makes the node slow.
pub const SLOW_MS: u32 = 3_000;

/// Seconds between two checks of a node that works.
const OK_INTERVAL_S: i64 = 300;

/// Seconds to wait after the first, second, third… failure in a row. The last value
/// stays for the next failures.
const FAILURE_DELAYS_S: [i64; 6] = [30, 60, 120, 300, 600, 900];

/// With Tor, the times are this many times longer: a circuit is slow and it costs the
/// network.
const TOR_FACTOR: i64 = 3;

/// A limit for one check in seconds, and the same with Tor.
pub const CHECK_TIMEOUT_S: u64 = 5;
pub const CHECK_TIMEOUT_TOR_S: u64 = 25;

/// What the last checks say about a node.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Availability {
    /// The node was never checked.
    Unknown,
    /// The last check worked.
    Available,
    /// The last check worked and was slow.
    Slow,
    /// The last check failed.
    Unreachable,
}

/// The result of the checks of one node. It is part of the record of the node in the
/// database; every field has a default, so an old database loads.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Health {
    /// The time of the last check, in Unix seconds. 0 if there was none.
    #[serde(default)]
    pub checked_at: i64,
    /// The time of the last check that worked, in Unix seconds. 0 if there was none.
    #[serde(default)]
    pub last_ok_at: i64,
    /// The time that the last working check took, in milliseconds.
    #[serde(default)]
    pub latency_ms: Option<u32>,
    /// How many checks failed in a row. 0 if the last one worked.
    #[serde(default)]
    pub failures: u32,
    /// Why the last check failed, as the name of an error kind of the FFI crate.
    #[serde(default)]
    pub error_kind: Option<String>,
    /// The text of the last failure.
    #[serde(default)]
    pub error: Option<String>,
}

impl Health {
    pub fn availability(&self) -> Availability {
        if self.checked_at == 0 {
            Availability::Unknown
        } else if self.failures > 0 {
            Availability::Unreachable
        } else if self.latency_ms.is_some_and(|ms| ms >= SLOW_MS) {
            Availability::Slow
        } else {
            Availability::Available
        }
    }

    /// The check at `now` worked and took `latency_ms`.
    pub fn record_ok(&mut self, now: i64, latency_ms: u32) {
        self.checked_at = now;
        self.last_ok_at = now;
        self.latency_ms = Some(latency_ms);
        self.failures = 0;
        self.error_kind = None;
        self.error = None;
    }

    /// The check at `now` failed. The last working time and the latency stay: the screen
    /// can say "it worked 2 hours ago".
    pub fn record_failure(&mut self, now: i64, kind: &str, error: &str) {
        self.checked_at = now;
        self.failures = self.failures.saturating_add(1);
        self.error_kind = Some(kind.to_string());
        self.error = Some(error.to_string());
    }

    /// The time when the next check is due, in Unix seconds. A node that was never
    /// checked is due at once.
    pub fn next_check_at(&self, tor: bool) -> i64 {
        if self.checked_at == 0 {
            return 0;
        }
        let wait = if self.failures == 0 {
            OK_INTERVAL_S
        } else {
            let i = (self.failures as usize - 1).min(FAILURE_DELAYS_S.len() - 1);
            FAILURE_DELAYS_S[i]
        };
        self.checked_at + wait * if tor { TOR_FACTOR } else { 1 }
    }

    /// True if the next check is due at `now`.
    pub fn is_due(&self, now: i64, tor: bool) -> bool {
        now >= self.next_check_at(tor)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_node_that_was_never_checked_is_unknown_and_due() {
        let h = Health::default();
        assert_eq!(h.availability(), Availability::Unknown);
        assert!(h.is_due(0, false));
        assert!(h.is_due(1_000, true));
    }

    #[test]
    fn a_fast_check_is_available_and_a_slow_one_is_slow() {
        let mut h = Health::default();
        h.record_ok(100, 120);
        assert_eq!(h.availability(), Availability::Available);
        assert_eq!(h.latency_ms, Some(120));
        h.record_ok(200, SLOW_MS - 1);
        assert_eq!(h.availability(), Availability::Available);
        h.record_ok(300, SLOW_MS);
        assert_eq!(h.availability(), Availability::Slow);
    }

    #[test]
    fn a_failure_makes_the_node_unreachable_and_keeps_the_last_good_time() {
        let mut h = Health::default();
        h.record_ok(100, 50);
        h.record_failure(400, "timeout", "the node did not answer in time");
        assert_eq!(h.availability(), Availability::Unreachable);
        assert_eq!(h.failures, 1);
        assert_eq!(h.last_ok_at, 100);
        assert_eq!(h.checked_at, 400);
        assert_eq!(h.error_kind.as_deref(), Some("timeout"));
        assert_eq!(h.latency_ms, Some(50));
        // A working check clears the failure.
        h.record_ok(500, 60);
        assert_eq!(h.availability(), Availability::Available);
        assert_eq!(h.failures, 0);
        assert!(h.error.is_none() && h.error_kind.is_none());
    }

    #[test]
    fn a_working_node_is_checked_every_five_minutes() {
        let mut h = Health::default();
        h.record_ok(1_000, 10);
        assert_eq!(h.next_check_at(false), 1_300);
        assert!(!h.is_due(1_299, false));
        assert!(h.is_due(1_300, false));
    }

    #[test]
    fn a_node_that_keeps_failing_is_checked_later_and_later_up_to_a_limit() {
        let mut h = Health::default();
        let mut waits = Vec::new();
        for i in 0..9 {
            h.record_failure(1_000, "unreachable", "x");
            waits.push(h.next_check_at(false) - 1_000);
            assert_eq!(h.failures, i + 1);
        }
        assert_eq!(waits, [30, 60, 120, 300, 600, 900, 900, 900, 900]);
    }

    #[test]
    fn with_tor_the_times_are_three_times_longer() {
        let mut h = Health::default();
        h.record_ok(0 + 1, 10);
        assert_eq!(h.next_check_at(true) - 1, 900);
        h.record_failure(1_000, "timeout", "x");
        assert_eq!(h.next_check_at(true) - 1_000, 90);
    }

    #[test]
    fn many_failures_do_not_overflow() {
        let mut h = Health {
            checked_at: 1,
            failures: u32::MAX,
            ..Default::default()
        };
        h.record_failure(2, "x", "y");
        assert_eq!(h.failures, u32::MAX);
        assert_eq!(h.next_check_at(false), 2 + 900);
    }

    #[test]
    fn an_old_record_without_health_fields_loads_with_defaults() {
        let h: Health = serde_json::from_str("{}").unwrap();
        assert_eq!(h, Health::default());
        let h: Health = serde_json::from_str(r#"{"checked_at": 5, "failures": 2}"#).unwrap();
        assert_eq!((h.checked_at, h.failures), (5, 2));
    }
}
