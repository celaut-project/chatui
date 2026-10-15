//! The filter on the advertised resources (`docs/celaut/balancer.md`, section Filter).
//!
//! It is the port of `nodo:src/utils/cost_functions/architecture_resources.py`
//! (`ask_of` and `request_misfit`), `nodo:src/utils/benchmark.py` (`shortfalls`) and
//! `nodo:src/utils/arch_guard.py` (`arch_from_tags`).
//!
//! Before it asks a node for a quote, the balancer holds what the service asks against
//! the last `Peer.resources` that the node announced. It skips only what can never fit:
//! the node does not run the architecture, a limit is above its announced ceiling, or a
//! required benchmark is above its announced score. A node that announced nothing is
//! asked as before, and so is a request with no known architecture. A ceiling or a score
//! that the node did not announce is no reason to skip it.
//!
//! The functions are pure. The client has the hash of a service, not its resources, so
//! the caller must give a [`ServiceAsk`] from a source that has them (the spec of the
//! service). Without an ask, nothing is skipped.

use std::collections::BTreeMap;
use std::fmt;

use celaut_proto::celaut::service::container::{Architecture, Resources};
use celaut_proto::celaut::{ArchitectureResources, Sysresources};

/// The CFS period when `cpu_period` is absent or 0 (`host_limits.DEFAULT_CPU_PERIOD_US`).
const DEFAULT_CPU_PERIOD_US: u64 = 100_000;

/// The primitives that a node names (`benchmark.SCORE_KEYS`).
const SCORE_KEYS: [&str; 6] = [
    "int_ops_per_sec",
    "flt_ops_per_sec",
    "mem_bandwidth_64mib_bytes_per_sec",
    "mem_bandwidth_256mib_bytes_per_sec",
    "mem_bandwidth_1gib_bytes_per_sec",
    "sha256_hashes_per_sec",
];

/// The canonical tag of an architecture tag (`arch_guard.ARCH_ALIASES`), or `None`. The
/// tag is trimmed and compared in lowercase.
pub fn normalize_arch_tag(tag: &str) -> Option<&'static str> {
    match tag.trim().to_lowercase().as_str() {
        "linux/amd64" | "amd64" | "x86_64" => Some("linux/amd64"),
        "linux/arm64" | "arm64" | "arm_64" | "aarch64" => Some("linux/arm64"),
        _ => None,
    }
}

/// The canonical tag that the first recognised entry of `tags` names, or `None`. It does
/// not ask whether this device can run the architecture: it reads what a node announced
/// or what a service needs.
pub fn arch_from_tags(tags: &[String]) -> Option<&'static str> {
    tags.iter().find_map(|t| normalize_arch_tag(t))
}

/// What a service asks of a node: its architecture and one [`Sysresources`]. The limits
/// are the `at_most` of the service (the worst case, so a node that supports it supports
/// any smaller start), and the benchmark is the `at_init` minimum for each core.
#[derive(Debug, Clone, PartialEq)]
pub struct ServiceAsk {
    /// The canonical architecture of the service. `None` if the service names none that
    /// this client knows: then no node is skipped.
    pub architecture: Option<&'static str>,
    /// The limits and the minimum scores.
    pub resources: Sysresources,
}

impl ServiceAsk {
    /// The ask of a service from its `Container.architecture` and `Container.resources`.
    pub fn of(architecture: Option<&Architecture>, resources: Option<&Resources>) -> Self {
        ServiceAsk {
            architecture: architecture.and_then(|a| arch_from_tags(&a.tags)),
            resources: resources.map(ask_of).unwrap_or_default(),
        }
    }

    /// Why a node that announced `announced` could never run the service. Empty if the
    /// node is to be asked.
    pub fn misfits(&self, announced: &[ArchitectureResources]) -> Vec<Misfit> {
        request_misfit(announced, self.architecture, &self.resources)
    }
}

/// The shape that a service's `Container.Resources` asks a node about: the `at_most`
/// limits, with no benchmark, and the benchmark of `at_init` (`ask_of`).
pub fn ask_of(resources: &Resources) -> Sysresources {
    let mut ask = resources.at_most.clone().unwrap_or_default();
    ask.benchmark.clear();
    if let Some(at_init) = &resources.at_init {
        ask.benchmark.extend(at_init.benchmark.iter().cloned());
    }
    ask
}

/// One reason why a node could never admit a request.
#[derive(Debug, Clone, PartialEq)]
pub enum Misfit {
    /// The node announced resources, but none for the architecture of the service.
    NotRun {
        /// The architecture of the service.
        architecture: String,
        /// The architectures that the node announced, sorted. `?` is an entry whose
        /// tags name no known architecture.
        announced: Vec<String>,
    },
    /// The memory limit is above the announced ceiling.
    MemLimit {
        /// The bytes that the service asks.
        asked: u64,
        /// The bytes that the node announced.
        cap: u64,
    },
    /// The disk space is above the announced ceiling.
    DiskSpace {
        /// The bytes that the service asks.
        asked: u64,
        /// The bytes that the node announced.
        cap: u64,
    },
    /// The cores are above the announced ceiling.
    Cores {
        /// The cores that the service asks.
        asked: f64,
        /// The cores that the node announced.
        cap: f64,
    },
    /// A required benchmark is above the announced score.
    Benchmark {
        /// The architecture of the service.
        architecture: String,
        /// The primitive that the service requires.
        key: String,
        /// The minimum per core and second.
        required: u64,
        /// The score that the node announced.
        measured: u64,
        /// The key of the score, if it is not `key` (a bandwidth is read against the
        /// next larger working set that the node measured).
        over: Option<String>,
    },
}

impl fmt::Display for Misfit {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Misfit::NotRun {
                architecture,
                announced,
            } => write!(
                f,
                "it does not run {architecture} (it announced {})",
                announced.join(", ")
            ),
            Misfit::MemLimit { asked, cap } => {
                write!(f, "mem_limit {asked} is above its announced {cap}")
            }
            Misfit::DiskSpace { asked, cap } => {
                write!(f, "disk_space {asked} is above its announced {cap}")
            }
            Misfit::Cores { asked, cap } => {
                write!(f, "{asked:.2} cores is above its announced {cap:.2}")
            }
            Misfit::Benchmark {
                architecture,
                key,
                required,
                measured,
                over,
            } => {
                let over = over
                    .as_ref()
                    .map(|k| format!(" (over {k})"))
                    .unwrap_or_default();
                write!(
                    f,
                    "Insufficient per-core resources.at_init.benchmark.{key}. Requested: \
                     {required} per core per second, measured by the peer for \
                     {architecture}: {measured}{over}."
                )
            }
        }
    }
}

/// A CFS pair in cores, or 0 when no quota is declared (`host_limits.requested_cores`).
fn requested_cores(quota: Option<u64>, period: Option<u64>) -> f64 {
    let quota = quota.unwrap_or(0);
    if quota == 0 {
        return 0.0;
    }
    let period = match period {
        Some(p) if p != 0 => p,
        _ => DEFAULT_CPU_PERIOD_US,
    };
    quota as f64 / period as f64
}

/// The working set in bytes that `mem_bandwidth_<n><kib|mib|gib>_bytes_per_sec` names
/// (`benchmark.mem_bandwidth_working_set`). `n` is a number that is 1 or more, with no
/// leading zero. A number too large for `u128` is the largest value.
fn mem_bandwidth_working_set(key: &str) -> Option<u128> {
    let middle = key
        .strip_prefix("mem_bandwidth_")?
        .strip_suffix("_bytes_per_sec")?;
    let (digits, unit) = middle.split_at(middle.find(|c: char| !c.is_ascii_digit())?);
    let unit: u128 = match unit {
        "kib" => 1 << 10,
        "mib" => 1 << 20,
        "gib" => 1 << 30,
        _ => return None,
    };
    if digits.starts_with('0') || digits.is_empty() {
        return None;
    }
    let n: u128 = digits.parse().unwrap_or(u128::MAX);
    Some(n.saturating_mul(unit))
}

/// Whether a node can name `key`: a primitive that it knows, or a bandwidth over some
/// size (`benchmark.is_recognised`).
fn is_recognised(key: &str) -> bool {
    SCORE_KEYS.contains(&key) || mem_bandwidth_working_set(key).is_some()
}

/// The key and the score that `key` is held against: its own score, or for a bandwidth
/// with no score the score over the smallest working set that is at least as large
/// (`benchmark._score_for`). `None` if there is no score to hold it against.
fn score_for<'a>(key: &'a str, scores: &'a BTreeMap<String, u64>) -> Option<(&'a str, u64)> {
    if let Some(own) = scores.get(key) {
        return Some((key, *own));
    }
    let wanted = mem_bandwidth_working_set(key)?;
    scores
        .iter()
        .filter_map(|(other, value)| {
            let size = mem_bandwidth_working_set(other)?;
            (size >= wanted).then_some((size, other.as_str(), *value))
        })
        .min_by(|a, b| (a.0, a.1).cmp(&(b.0, b.1)))
        .map(|(_, other, value)| (other, value))
}

/// The entries of a benchmark as key and value. An entry with no value says nothing and
/// is left out. A repeated key keeps its last value.
fn benchmark_map(sys: &Sysresources) -> BTreeMap<String, u64> {
    sys.benchmark
        .iter()
        .filter_map(|e| e.value.map(|v| (e.key.clone(), v)))
        .collect()
}

/// Why a node that announced `announced` could never admit the request, in the order of
/// nodo: the architecture, then memory, disk, cores, and the benchmarks sorted by key.
/// Empty means that the node is to be asked: it announced nothing, or the architecture
/// of the request is unknown, or nothing that it announced is below the request
/// (`request_misfit`).
pub fn request_misfit(
    announced: &[ArchitectureResources],
    architecture: Option<&str>,
    ask: &Sysresources,
) -> Vec<Misfit> {
    let Some(architecture) = architecture else {
        return Vec::new();
    };
    if announced.is_empty() {
        return Vec::new();
    }
    let tags_of = |e: &ArchitectureResources| {
        e.architecture
            .as_ref()
            .and_then(|a| arch_from_tags(&a.tags))
    };
    let Some(entry) = announced
        .iter()
        .find(|e| tags_of(e) == Some(architecture))
    else {
        let mut tags: Vec<String> = announced
            .iter()
            .map(|e| tags_of(e).unwrap_or("?").to_string())
            .collect();
        tags.sort();
        tags.dedup();
        return vec![Misfit::NotRun {
            architecture: architecture.to_string(),
            announced: tags,
        }];
    };

    let cap = entry.resources.clone().unwrap_or_default();
    let mut found = Vec::new();
    if let (Some(cap), Some(asked)) = (cap.mem_limit, ask.mem_limit) {
        if asked > cap {
            found.push(Misfit::MemLimit { asked, cap });
        }
    }
    if let (Some(cap), Some(asked)) = (cap.disk_space, ask.disk_space) {
        if asked > cap {
            found.push(Misfit::DiskSpace { asked, cap });
        }
    }
    let asked_cores = requested_cores(ask.cpu_quota, ask.cpu_period);
    if cap.cpu_quota.is_some() && asked_cores != 0.0 {
        let cap_cores = requested_cores(cap.cpu_quota, cap.cpu_period);
        if asked_cores > cap_cores {
            found.push(Misfit::Cores {
                asked: asked_cores,
                cap: cap_cores,
            });
        }
    }
    let scores = benchmark_map(&cap);
    for (key, required) in benchmark_map(ask) {
        if !is_recognised(&key) {
            continue;
        }
        let Some((score_key, measured)) = score_for(&key, &scores) else {
            continue;
        };
        if measured < required {
            let over = (score_key != key).then(|| score_key.to_string());
            found.push(Misfit::Benchmark {
                architecture: architecture.to_string(),
                key,
                required,
                measured,
                over,
            });
        }
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;
    use celaut_proto::celaut::Uint64KeyValue;

    const GIB: u64 = 1 << 30;

    fn tags(tags: &[&str]) -> Option<Architecture> {
        Some(Architecture {
            tags: tags.iter().map(|t| t.to_string()).collect(),
            ..Default::default()
        })
    }

    fn bench(entries: &[(&str, u64)]) -> Vec<Uint64KeyValue> {
        entries
            .iter()
            .map(|(k, v)| Uint64KeyValue {
                key: k.to_string(),
                value: Some(*v),
            })
            .collect()
    }

    fn announced(arch: &[&str], resources: Sysresources) -> ArchitectureResources {
        ArchitectureResources {
            architecture: tags(arch),
            resources: Some(resources),
        }
    }

    fn amd64(resources: Sysresources) -> Vec<ArchitectureResources> {
        vec![announced(&["linux/amd64"], resources)]
    }

    fn scores(entries: &[(&str, u64)]) -> Sysresources {
        Sysresources {
            benchmark: bench(entries),
            ..Default::default()
        }
    }

    fn required(entries: &[(&str, u64)]) -> Sysresources {
        scores(entries)
    }

    fn misfit(announced: &[ArchitectureResources], ask: &Sysresources) -> Vec<Misfit> {
        request_misfit(announced, Some("linux/amd64"), ask)
    }

    fn ceilings() -> Sysresources {
        Sysresources {
            mem_limit: Some(GIB),
            disk_space: Some(10 * GIB),
            cpu_quota: Some(200_000),
            cpu_period: Some(100_000),
            ..Default::default()
        }
    }

    #[test]
    fn the_aliases_of_an_architecture_name_the_canonical_tag() {
        for tag in ["linux/amd64", "amd64", "x86_64", " X86_64 ", "AMD64"] {
            assert_eq!(normalize_arch_tag(tag), Some("linux/amd64"), "{tag}");
        }
        for tag in ["linux/arm64", "arm64", "arm_64", "aarch64", "Linux/ARM64"] {
            assert_eq!(normalize_arch_tag(tag), Some("linux/arm64"), "{tag}");
        }
        for tag in ["", "riscv64", "linux/386"] {
            assert_eq!(normalize_arch_tag(tag), None, "{tag}");
        }
    }

    #[test]
    fn the_first_recognised_tag_wins() {
        let t = |tags: &[&str]| tags.iter().map(|t| t.to_string()).collect::<Vec<_>>();
        assert_eq!(
            arch_from_tags(&t(&["riscv", "aarch64", "x86_64"])),
            Some("linux/arm64")
        );
        assert_eq!(arch_from_tags(&t(&["riscv"])), None);
        assert_eq!(arch_from_tags(&[]), None);
    }

    #[test]
    fn the_ask_has_the_at_most_limits_and_the_at_init_benchmark() {
        let resources = Resources {
            at_init: Some(Sysresources {
                mem_limit: Some(1),
                benchmark: bench(&[("int_ops_per_sec", 500_000)]),
                ..Default::default()
            }),
            at_most: Some(Sysresources {
                mem_limit: Some(GIB),
                cpu_quota: Some(100_000),
                benchmark: bench(&[("int_ops_per_sec", 7)]),
                ..Default::default()
            }),
        };
        let ask = ask_of(&resources);
        assert_eq!(ask.mem_limit, Some(GIB));
        assert_eq!(ask.cpu_quota, Some(100_000));
        assert_eq!(ask.benchmark, bench(&[("int_ops_per_sec", 500_000)]));
    }

    #[test]
    fn the_ask_with_no_at_most_or_no_at_init_is_empty_of_that_part() {
        let only_init = Resources {
            at_init: Some(scores(&[("flt_ops_per_sec", 3)])),
            at_most: None,
        };
        let ask = ask_of(&only_init);
        assert_eq!(ask.mem_limit, None);
        assert_eq!(ask.benchmark, bench(&[("flt_ops_per_sec", 3)]));
        let only_most = Resources {
            at_init: None,
            at_most: Some(Sysresources {
                disk_space: Some(5),
                benchmark: bench(&[("flt_ops_per_sec", 3)]),
                ..Default::default()
            }),
        };
        let ask = ask_of(&only_most);
        assert_eq!(ask.disk_space, Some(5));
        assert!(ask.benchmark.is_empty());
        assert_eq!(ask_of(&Resources::default()), Sysresources::default());
    }

    #[test]
    fn a_service_ask_names_the_architecture_by_its_first_known_tag() {
        let ask = ServiceAsk::of(tags(&["riscv", "aarch64"]).as_ref(), None);
        assert_eq!(ask.architecture, Some("linux/arm64"));
        assert_eq!(ask.resources, Sysresources::default());
        assert_eq!(ServiceAsk::of(None, None).architecture, None);
    }

    #[test]
    fn a_node_that_announced_nothing_is_asked() {
        let ask = Sysresources {
            mem_limit: Some(u64::MAX),
            ..Default::default()
        };
        assert!(misfit(&[], &ask).is_empty());
    }

    #[test]
    fn a_request_with_no_known_architecture_is_asked() {
        let ask = Sysresources {
            mem_limit: Some(u64::MAX),
            ..Default::default()
        };
        assert!(request_misfit(&amd64(ceilings()), None, &ask).is_empty());
    }

    #[test]
    fn an_architecture_that_the_node_does_not_announce_is_skipped() {
        let announced = vec![announced(&["linux/arm64"], Sysresources::default())];
        let found = misfit(&announced, &Sysresources::default());
        assert_eq!(
            found,
            vec![Misfit::NotRun {
                architecture: "linux/amd64".into(),
                announced: vec!["linux/arm64".into()],
            }]
        );
        let text = found[0].to_string();
        assert!(text.contains("does not run linux/amd64"), "{text}");
        assert!(text.contains("linux/arm64"), "{text}");
    }

    #[test]
    fn an_unknown_announced_architecture_is_named_with_a_question_mark_once() {
        let announced = vec![
            announced(&["riscv"], Sysresources::default()),
            announced(&["mips"], Sysresources::default()),
            announced(&["arm64"], Sysresources::default()),
        ];
        let found = misfit(&announced, &Sysresources::default());
        assert_eq!(
            found,
            vec![Misfit::NotRun {
                architecture: "linux/amd64".into(),
                announced: vec!["?".into(), "linux/arm64".into()],
            }]
        );
    }

    #[test]
    fn an_alias_in_the_announcement_still_matches() {
        let announced = vec![announced(&["x86_64"], Sysresources::default())];
        assert!(misfit(&announced, &Sysresources::default()).is_empty());
    }

    #[test]
    fn an_entry_with_no_architecture_never_matches() {
        let announced = vec![ArchitectureResources {
            architecture: None,
            resources: Some(ceilings()),
        }];
        let found = misfit(&announced, &Sysresources::default());
        assert!(matches!(found.as_slice(), [Misfit::NotRun { .. }]));
    }

    #[test]
    fn memory_above_the_ceiling_is_skipped_and_equal_is_not() {
        let announced = amd64(ceilings());
        let above = Sysresources {
            mem_limit: Some(2 * GIB),
            ..Default::default()
        };
        assert_eq!(
            misfit(&announced, &above),
            vec![Misfit::MemLimit {
                asked: 2 * GIB,
                cap: GIB
            }]
        );
        let equal = Sysresources {
            mem_limit: Some(GIB),
            ..Default::default()
        };
        assert!(misfit(&announced, &equal).is_empty());
    }

    #[test]
    fn disk_above_the_ceiling_is_skipped_and_equal_is_not() {
        let announced = amd64(ceilings());
        let above = Sysresources {
            disk_space: Some(20 * GIB),
            ..Default::default()
        };
        assert_eq!(
            misfit(&announced, &above),
            vec![Misfit::DiskSpace {
                asked: 20 * GIB,
                cap: 10 * GIB
            }]
        );
        let equal = Sysresources {
            disk_space: Some(10 * GIB),
            ..Default::default()
        };
        assert!(misfit(&announced, &equal).is_empty());
    }

    #[test]
    fn cores_above_the_ceiling_are_skipped_and_equal_are_not() {
        let announced = amd64(ceilings());
        let above = Sysresources {
            cpu_quota: Some(400_000),
            cpu_period: Some(100_000),
            ..Default::default()
        };
        assert_eq!(
            misfit(&announced, &above),
            vec![Misfit::Cores {
                asked: 4.0,
                cap: 2.0
            }]
        );
        let equal = Sysresources {
            cpu_quota: Some(200_000),
            cpu_period: Some(100_000),
            ..Default::default()
        };
        assert!(misfit(&announced, &equal).is_empty());
    }

    #[test]
    fn cores_use_a_period_of_100000_when_it_is_absent_or_zero() {
        // The ceiling is 2 cores with no period.
        let announced = amd64(Sysresources {
            cpu_quota: Some(200_000),
            ..Default::default()
        });
        let three = |period| Sysresources {
            cpu_quota: Some(300_000),
            cpu_period: period,
            ..Default::default()
        };
        assert_eq!(
            misfit(&announced, &three(None)),
            vec![Misfit::Cores {
                asked: 3.0,
                cap: 2.0
            }]
        );
        assert_eq!(misfit(&announced, &three(Some(0))).len(), 1);
        // The same quota with a period of 200000 is 1.5 cores, which fits.
        assert!(misfit(&announced, &three(Some(200_000))).is_empty());
        // A ceiling with period 0 is read as 100000 too.
        let zero_period = amd64(Sysresources {
            cpu_quota: Some(100_000),
            cpu_period: Some(0),
            ..Default::default()
        });
        assert_eq!(misfit(&zero_period, &three(None)).len(), 1);
    }

    #[test]
    fn a_request_with_no_quota_asks_no_cores() {
        let announced = amd64(ceilings());
        // A quota of 0 is "no quota", whatever the period.
        let zero = Sysresources {
            cpu_quota: Some(0),
            cpu_period: Some(1),
            ..Default::default()
        };
        assert!(misfit(&announced, &zero).is_empty());
        assert!(misfit(&announced, &Sysresources::default()).is_empty());
    }

    #[test]
    fn a_ceiling_with_quota_zero_rules_out_any_request_for_cores() {
        let announced = amd64(Sysresources {
            cpu_quota: Some(0),
            ..Default::default()
        });
        let one = Sysresources {
            cpu_quota: Some(100_000),
            ..Default::default()
        };
        assert_eq!(
            misfit(&announced, &one),
            vec![Misfit::Cores {
                asked: 1.0,
                cap: 0.0
            }]
        );
    }

    #[test]
    fn a_request_within_every_ceiling_is_asked() {
        let ask = Sysresources {
            mem_limit: Some(GIB),
            disk_space: Some(GIB),
            cpu_quota: Some(100_000),
            cpu_period: Some(100_000),
            ..Default::default()
        };
        assert!(misfit(&amd64(ceilings()), &ask).is_empty());
    }

    #[test]
    fn a_ceiling_that_the_node_did_not_announce_is_no_reason_to_skip() {
        let ask = Sysresources {
            mem_limit: Some(u64::MAX),
            disk_space: Some(u64::MAX),
            cpu_quota: Some(u64::MAX),
            ..Default::default()
        };
        assert!(misfit(&amd64(Sysresources::default()), &ask).is_empty());
        let no_resources = vec![ArchitectureResources {
            architecture: tags(&["amd64"]),
            resources: None,
        }];
        assert!(misfit(&no_resources, &ask).is_empty());
    }

    #[test]
    fn a_limit_that_the_request_does_not_make_is_no_reason_to_skip() {
        assert!(misfit(&amd64(ceilings()), &Sysresources::default()).is_empty());
    }

    #[test]
    fn every_reason_is_reported_in_the_order_of_nodo() {
        let ask = Sysresources {
            mem_limit: Some(2 * GIB),
            disk_space: Some(20 * GIB),
            cpu_quota: Some(400_000),
            benchmark: bench(&[("int_ops_per_sec", 5)]),
            ..Default::default()
        };
        let mut cap = ceilings();
        cap.benchmark = bench(&[("int_ops_per_sec", 1)]);
        let found = misfit(&amd64(cap), &ask);
        assert!(matches!(
            found.as_slice(),
            [
                Misfit::MemLimit { .. },
                Misfit::DiskSpace { .. },
                Misfit::Cores { .. },
                Misfit::Benchmark { .. }
            ]
        ));
    }

    #[test]
    fn a_required_benchmark_above_the_announced_score_is_skipped() {
        let announced = amd64(scores(&[("int_ops_per_sec", 20_000)]));
        let found = misfit(&announced, &required(&[("int_ops_per_sec", 500_000)]));
        assert_eq!(
            found,
            vec![Misfit::Benchmark {
                architecture: "linux/amd64".into(),
                key: "int_ops_per_sec".into(),
                required: 500_000,
                measured: 20_000,
                over: None,
            }]
        );
        let text = found[0].to_string();
        assert!(text.contains("int_ops_per_sec"), "{text}");
        assert!(text.contains("by the peer for linux/amd64: 20000"), "{text}");
        assert!(!text.contains("(over"), "{text}");
    }

    #[test]
    fn a_score_equal_to_the_requirement_fits() {
        let announced = amd64(scores(&[("sha256_hashes_per_sec", 100)]));
        assert!(misfit(&announced, &required(&[("sha256_hashes_per_sec", 100)])).is_empty());
        assert_eq!(
            misfit(&announced, &required(&[("sha256_hashes_per_sec", 101)])).len(),
            1
        );
    }

    #[test]
    fn a_primitive_that_the_node_did_not_measure_is_asked() {
        let announced = amd64(scores(&[("int_ops_per_sec", 20_000)]));
        let ask = required(&[("flt_ops_per_sec", 1_000_000_000_000)]);
        assert!(misfit(&announced, &ask).is_empty());
    }

    #[test]
    fn an_unknown_primitive_is_not_enforced_even_when_the_node_has_a_score() {
        let announced = amd64(scores(&[("quantum_ops_per_sec", 1)]));
        assert!(misfit(&announced, &required(&[("quantum_ops_per_sec", 9)])).is_empty());
    }

    #[test]
    fn an_entry_with_no_value_says_nothing() {
        let mut cap = Sysresources::default();
        cap.benchmark.push(Uint64KeyValue {
            key: "int_ops_per_sec".into(),
            value: None,
        });
        let mut ask = Sysresources::default();
        ask.benchmark.push(Uint64KeyValue {
            key: "int_ops_per_sec".into(),
            value: None,
        });
        assert!(misfit(&amd64(cap), &required(&[("int_ops_per_sec", 5)])).is_empty());
        assert!(misfit(&amd64(scores(&[("int_ops_per_sec", 1)])), &ask).is_empty());
    }

    #[test]
    fn the_benchmarks_are_reported_sorted_by_key() {
        let announced = amd64(scores(&[]));
        let cap = scores(&[("int_ops_per_sec", 1), ("flt_ops_per_sec", 1)]);
        let ask = required(&[("int_ops_per_sec", 5), ("flt_ops_per_sec", 5)]);
        let found = misfit(&amd64(cap), &ask);
        let keys: Vec<&str> = found
            .iter()
            .map(|m| match m {
                Misfit::Benchmark { key, .. } => key.as_str(),
                _ => "",
            })
            .collect();
        assert_eq!(keys, ["flt_ops_per_sec", "int_ops_per_sec"]);
        assert!(misfit(&announced, &ask).is_empty());
    }

    const KEY_256: &str = "mem_bandwidth_256mib_bytes_per_sec";
    const KEY_1GIB: &str = "mem_bandwidth_1gib_bytes_per_sec";
    const KEY_64: &str = "mem_bandwidth_64mib_bytes_per_sec";

    #[test]
    fn a_bandwidth_is_judged_over_the_working_set_that_it_names() {
        let slow = amd64(scores(&[(KEY_256, 100_000_000)]));
        let ask = required(&[(KEY_256, 1_000_000_000)]);
        let found = misfit(&slow, &ask);
        assert!(matches!(
            found.as_slice(),
            [Misfit::Benchmark { key, over: None, .. }] if key == KEY_256
        ));
        let fast = amd64(scores(&[(KEY_256, 10_000_000_000)]));
        assert!(misfit(&fast, &ask).is_empty());
    }

    #[test]
    fn a_bandwidth_with_no_score_of_its_own_uses_the_next_larger_working_set() {
        let ask = required(&[(KEY_256, 1_000_000_000)]);
        let fast = amd64(scores(&[(KEY_1GIB, 1_000_000_000_000)]));
        assert!(misfit(&fast, &ask).is_empty());
        let slow = amd64(scores(&[(KEY_1GIB, 100_000_000)]));
        let found = misfit(&slow, &ask);
        assert!(matches!(
            found.as_slice(),
            [Misfit::Benchmark { over: Some(o), measured: 100_000_000, .. }] if o == KEY_1GIB
        ));
        assert!(found[0].to_string().contains(&format!("(over {KEY_1GIB})")));
    }

    #[test]
    fn a_bandwidth_over_a_smaller_working_set_says_nothing_about_a_larger_one() {
        let ask = required(&[(KEY_256, 1_000_000_000)]);
        assert!(misfit(&amd64(scores(&[(KEY_64, 1)])), &ask).is_empty());
    }

    #[test]
    fn a_bandwidth_over_a_working_set_larger_than_any_measured_is_not_enforced() {
        let ask = required(&[("mem_bandwidth_4gib_bytes_per_sec", 1_000_000_000_000)]);
        assert!(misfit(&amd64(scores(&[(KEY_1GIB, 1)])), &ask).is_empty());
    }

    #[test]
    fn the_smallest_larger_working_set_is_the_one_that_counts() {
        // 1 GiB is fast and 256 MiB is slow: a requirement over 64 MiB reads 256 MiB.
        let announced = amd64(scores(&[(KEY_256, 10), (KEY_1GIB, 1_000_000)]));
        let found = misfit(&announced, &required(&[(KEY_64, 100)]));
        assert!(matches!(
            found.as_slice(),
            [Misfit::Benchmark { over: Some(o), measured: 10, .. }] if o == KEY_256
        ));
    }

    #[test]
    fn a_bandwidth_in_other_units_is_recognised_and_compared_by_size() {
        // 1024kib is 1 MiB: the next larger measured set is 64 MiB.
        let announced = amd64(scores(&[(KEY_64, 5)]));
        let ask = required(&[("mem_bandwidth_1024kib_bytes_per_sec", 6)]);
        assert_eq!(misfit(&announced, &ask).len(), 1);
        let ask = required(&[("mem_bandwidth_1024kib_bytes_per_sec", 5)]);
        assert!(misfit(&announced, &ask).is_empty());
    }

    #[test]
    fn the_names_of_a_bandwidth_are_checked() {
        assert_eq!(
            mem_bandwidth_working_set("mem_bandwidth_64mib_bytes_per_sec"),
            Some(64 << 20)
        );
        assert_eq!(
            mem_bandwidth_working_set("mem_bandwidth_2gib_bytes_per_sec"),
            Some(2 << 30)
        );
        for bad in [
            "mem_bandwidth_0mib_bytes_per_sec",
            "mem_bandwidth_064mib_bytes_per_sec",
            "mem_bandwidth_mib_bytes_per_sec",
            "mem_bandwidth_64tib_bytes_per_sec",
            "mem_bandwidth_64mib_bytes",
            "mem_bandwidth_64_bytes_per_sec",
            "int_ops_per_sec",
        ] {
            assert_eq!(mem_bandwidth_working_set(bad), None, "{bad}");
        }
        // A number that does not fit in u128 is the largest working set.
        let huge = format!("mem_bandwidth_{}gib_bytes_per_sec", "9".repeat(60));
        assert_eq!(mem_bandwidth_working_set(&huge), Some(u128::MAX));
        assert!(is_recognised(&huge));
    }

    #[test]
    fn the_emulated_architecture_is_judged_by_its_own_scores() {
        let announced = vec![
            announced(&["linux/amd64"], scores(&[("int_ops_per_sec", 900_000)])),
            announced(&["linux/arm64"], scores(&[("int_ops_per_sec", 20_000)])),
        ];
        let ask = required(&[("int_ops_per_sec", 500_000)]);
        assert!(request_misfit(&announced, Some("linux/amd64"), &ask).is_empty());
        assert_eq!(request_misfit(&announced, Some("linux/arm64"), &ask).len(), 1);
    }

    #[test]
    fn the_first_entry_of_an_architecture_is_the_one_that_counts() {
        let announced = vec![
            announced(&["amd64"], scores(&[("int_ops_per_sec", 1)])),
            announced(&["x86_64"], scores(&[("int_ops_per_sec", 1_000_000)])),
        ];
        let ask = required(&[("int_ops_per_sec", 500_000)]);
        assert_eq!(misfit(&announced, &ask).len(), 1);
    }

    #[test]
    fn a_service_ask_is_held_against_the_announcement() {
        let resources = Resources {
            at_init: Some(scores(&[("int_ops_per_sec", 500_000)])),
            at_most: Some(Sysresources {
                mem_limit: Some(2 * GIB),
                ..Default::default()
            }),
        };
        let ask = ServiceAsk::of(tags(&["linux/amd64"]).as_ref(), Some(&resources));
        let mut cap = ceilings();
        cap.benchmark = bench(&[("int_ops_per_sec", 900_000)]);
        let found = ask.misfits(&amd64(cap));
        assert!(matches!(found.as_slice(), [Misfit::MemLimit { .. }]));
        // A service that names no known architecture skips no node.
        let unknown = ServiceAsk::of(tags(&["riscv"]).as_ref(), Some(&resources));
        assert!(unknown.misfits(&amd64(ceilings())).is_empty());
    }

    #[test]
    fn the_cores_text_has_two_decimals() {
        let text = Misfit::Cores {
            asked: 1.5,
            cap: 1.0,
        }
        .to_string();
        assert_eq!(text, "1.50 cores is above its announced 1.00");
        assert_eq!(
            Misfit::MemLimit { asked: 3, cap: 2 }.to_string(),
            "mem_limit 3 is above its announced 2"
        );
        assert_eq!(
            Misfit::DiskSpace { asked: 3, cap: 2 }.to_string(),
            "disk_space 3 is above its announced 2"
        );
    }
}
