# Execution balancer (port of nodo)

Source: `nodo:src/balancers/execution_balancer/execution_balancer.py`,
`nodo:src/balancers/estimated_cost_sorter`, `nodo:src/balancers/scoring.py`.

## Pipeline

1. Candidates: every known node. (nodo also adds `local`; the light client does not run
   services, so it has no local candidate.)
2. Skip a node if its announcement says it cannot run the request (filter below).
3. Ask each remaining node `GetServiceEstimatedCost` (timeout 10 s). Convert the
   configuration to the node's MU before, and the quote to local MU after. A node with no
   shared payment method, an error or a refusal is not a candidate.
4. Score each quote and sort, best first (stable sort: equal scores keep insertion order).
5. The caller tries the candidates in order and uses the first that launches.

## Filter (`nodo:src/utils/cost_functions/architecture_resources.py`)

**Status.** The filter is ported and tested (`celaut-balancer`, `filter.rs`; the call is
`celaut_client::quotes_for` with a `ServiceAsk`). It is **not used in the real flow yet**:
the app has the hash of a service, not its resources (`resources.at_most`,
`resources.at_init`, the architecture). Without a `ServiceAsk`, `quotes` skips no node.
The filter needs the spec of the service: from a catalog entry or from a package that the
user uploads. Until a caller has it, a node is never skipped by the filter, and the first
check of a node is its own answer to `GetServiceEstimatedCost`.

What the port does, in the order of nodo (`request_misfit`):

- The node announced nothing, or the architecture of the service is unknown: ask the node.
- No entry for the architecture: skip (`NotRun`). The first entry whose tags name the
  architecture is the one that counts.
- `mem_limit` or `disk_space`: skip only if both sides have the value and the ask is more
  than the ceiling. An equal value fits.
- Cores: skip if the ask has a quota, the ceiling has a quota, and the ask is more than the
  ceiling. A period that is absent or 0 is 100000. A ceiling with quota 0 is 0 cores.
- Benchmarks, sorted by key: see below.
- A reason is a typed `Misfit`. A node with no reason is asked.


- `ask` = copy of `resources.at_most` without benchmarks, plus `at_init.benchmark`.
- Announcement = `Peer.resources` (repeated `ArchitectureResources`) from GetPeerInfo.
- Empty announcement or unknown service architecture: do not skip.
- No entry for the architecture: skip ("does not run …").
- Skip if `mem_limit` or `disk_space` is set on both sides and ask > cap.
- Cores = `cpu_quota / (cpu_period or 100000)` (0 if quota is 0). Skip if the cap has
  `cpu_quota`, the ask is not 0 and ask > cap.
- Benchmarks (`nodo:src/utils/benchmark.py`): keys `int_ops_per_sec`,
  `flt_ops_per_sec`, `sha256_hashes_per_sec`, `mem_bandwidth_<N>(kib|mib|gib)_bytes_per_sec`.
  For a memory key with no own score, use the smallest measured working set that is at
  least the required size. Unknown or unmeasured keys are not enforced. Skip if
  score < minimum.
- Architecture tags (`nodo:src/utils/arch_guard.py`): `linux/amd64|amd64|x86_64` →
  `linux/amd64`; `linux/arm64|arm64|arm_64|aarch64` → `linux/arm64`. First known tag wins.

## Score

```
vcnorm(c, v)  = trunc(c * (1 + v * k))                 k = COST_AVERAGE_VARIATION = 1
per_hour(a)   = 0 if s <= 0 else trunc(vcnorm(a, variance) * 3600 / s)
                s = maintenance_seconds_loop
cost_mu       = trunc(vcnorm(cost, variance)
                      + mean(per_hour(init_maintenance_cost), per_hour(max_maintenance_cost)))

score         = +inf if cost_mu <= 0
              = -ln(cost_mu) + W_r * f(r, H_r) + W_o * ô + W_d * d̂
f(x, h)       = x / (|x| + h)
```

Defaults: `W_r = SOCIALIZATION_FACTOR = 2`, `H_r = 50`, `W_o = 0.3`, `H_o = 5 ERG`,
publisher cap 5 ERG, `W_d = 0.3`. A weight W can overcome a price ratio of e^W.

- **r (local reputation):** `score * (1 + ln(index))` from the client's own event log.
  Events in nodo: +10 payment communicated, −100 payment not acknowledged, −1 failed
  payment call, −100 GetPeerInfo failure (once per outage), −100 GetService timeout,
  −1000 wrong hash.
- **ô (on-chain reputation):** for publisher p and subject s:
  `v = Σ ±(box tokens / assigned tokens of p)` (sign from R8),
  `c = cred(p) * sign(v) * min(|v| * burned_ERG(p), CAP)`, `S = Σ_p c`,
  `ô = S / (|S| + H_o)`. `cred(p)` = cosine similarity between p's verdicts and the
  client's own `f(r, H_r)`, clamped to [0, 1]. **Light client change:** while the
  client has no events, `cred(p) = 1`.
- **d̂ (donations):** nodo-specific. The light client uses 0 for now.

## MU conversion (`nodo:src/payment_system/mu_conversion.py`)

- Payment method key: `(ledger tag, sha3_256(contract_type).hex, token_id)`. The first
  method that both sides have is used.
- `convert(amount, from, to)` = `amount * to / from`, integers of any size.
- Configuration sent to a node: round down. Quote received: round up.

## Quote cache (`nodo:src/utils/tools/query_cache.py`)

TTL 10 s, at most 4096 entries, LRU. Key = sha256 over namespace `"peer-quote"`, the
peer id, the configuration in the node's MU and the metadata with sorted hashes
(each part: length as 8-byte big endian, then bytes).

## The least time of a launch (2026-10-23, Josemi)

The confirmation of a launch has a field: the least time that the instance must run. A
quote is the build plus the start balance that the request asks for (nodo #563), and a node
charges `init_maintenance_cost` once each `maintenance_seconds_loop`. So for a time `T`:

- balance(q, T) = (ceil(T / loop) + 1) × ceil(init_maintenance × (1 + variance)). The extra
  period is the one that runs at the end; `1 + variance` is nodo's
  `variance_cost_normalization` with k = 1 (`launcher.dart`, `survivalBalanceMu`).
- The launch asks the nodes once with the default balance (1 000 000 MU) to learn their
  prices, then again with the largest balance(q, T) of the quotes. Each node then quotes
  the build plus that balance, and the start pays that quote. A node gives back what the
  instance did not use at the stop.
- The confirmation shows the estimate for the best node before any second quote: its
  quote less the default balance, plus balance(q, T). With no time, it shows the default
  balance and how long that lasts on the best node.
- A node that gives no price per period (loop 0, or no amount) gets the default balance.
- The time holds at the price of the quote. nodo prices each maintenance period against the
  load of its host at that moment (a scarcity surcharge, up to the `scarcity_max_multiplier`
  that it advertises), and it takes the tunnel connections (`TUNNEL_OPEN_MU`) and their
  traffic (`NET_MU_PER_GIB`) from the same balance. On 2026-10-23, on our node with the
  emulator and a build on the same host, an instance funded for 10 minutes ran out after
  about 7. The confirmation says so; the automatic top-up ([ui.md](ui.md), section 4b) is the
  answer for a long conversation.

The app keeps the last time that the user typed (`celaut_min_survival_minutes_v1`). It must
be from 1 minute to 30 days.
