# Node directory and service catalog on Ergo

Both use the reputation-system contract `reputation_proof.es`
(github.com/reputation-systems/reputation-system). Every entity is an "opinion box".

**Read path:** Ergo Explorer only:

```
POST {explorer}/api/v1/boxes/unspent/search?offset={o}&limit=100
{"ergoTreeTemplateHash": "<hash>", "registers": {"R4": "<type NFT hex>", "R5": "<hex>"}, "assets": []}
```

Register values are in rendered form (raw hex, no `0e` and length prefix). The template
hash is required. Read all pages, until a page has fewer items than the limit.

## Register layout

| Register | Content |
|---|---|
| R4 | Type NFT id |
| R5 | The subject (peer_id, skill box id, benchmark box id, service id, …) |
| R6 | Locked flag |
| R7 | Owner proposition bytes (`0008cd` + 33-byte key) |
| R8 | Polarity (true = positive) |
| R9 | UTF-8 content (JSON) |

`assets[0]` is the reputation token of the publisher.

## Node directory

There is no registry contract for nodes. The closest thing is the box that a node
publishes about itself (`nodo:src/reputation_system/contracts/ergo/transaction.py`):

- R4 = Celaut node type NFT
  `64060577c3393e0e3cf8938ec8e6a2002ded27ece17750aa5add7d5c3e1227ba`.
- R5 = the node's peer_id.
- R9 = the node's signed `Peer` as protobuf JSON: one URI (IP, port), `public_key`,
  `signature`, `ts`. No payment contracts or resources: get those with GetPeerInfo.
- Only nodes with `SUBMIT_NETWORK_ADDRESS_TO_REPUTATION_PROOF: true` publish an
  address.
- The canonical ErgoTree and address are in `nodo:src/reputation_system/envs.py`.
  Filter boxes on the exact ErgoTree, not only the template.

## Service catalog: celaut-project/skills

Type NFT ids (mainnet, `skills:src/lib/api.ts:39-48`), template hash
`e84b95d84a30df33aa258fe2b9d24c3e75e27a67c6453983c19703029112d147`:

| Entity | Type NFT | R5 | R9 |
|---|---|---|---|
| Skill | `ffce59c0…f60c` | empty | `{name, prose, formal, tags, domain, extended_skill_boxes, source_hash}` |
| Coverage | `1da6799e…bdf5` | skill box id | `{skill_box_id, benchmark_id, service_id}` |
| Benchmark | `f6480184…f54d` | skill box id | `{name, case_descriptors, performance_metrics[{name, higher_is_better}]}` |
| Result | `49b26dc0…7aef` | benchmark box id | `{benchmark_id, service_id, data[{case_meta, metrics_values}]}` |

- A skill id is its box id. A service id is a 64-hex string (probably the SHA3-256
  service hash of nodo; the repo does not say).
- Services of a skill = Coverage boxes about the skill, plus services that have Results
  in its benchmarks (direct coverages first, deduplicated). Coverages about a benchmark
  are runners; ignore them.
- Profile reputation = sum of `value` (nanoERG) of the unspent boxes that hold the
  profile token (`GET /api/v1/boxes/unspent/byTokenId/{tokenId}`).

**Ranking** (`skills:src/lib/scoreGlobal.ts`):

```
W(r)      = 0.5 + 0.5 * sign(r) * ln(1 + |r|) / ln(1 + N_max)    (0.5 if N_max <= 0)
N(x)      = (x - min) / (max - min)   (inverted if lower is better; 0.5 if max == min)
P_r       = Σ_m (1/M) * N(median of the result's case values for m)
C_r       = 0.4 * W(uploader) + 0.6 * W(result reputation)
P(S, B)   = Σ C_r * P_r / Σ C_r
Perf(S)   = Σ_B W(bench rep) * P(S, B) / Σ_B W(bench rep)
score(S)  = Perf null ? W_S : 0.7 * Perf + 0.3 * W_S     (W_S = W(coverage reputation))
```

Sort by score, then coverage reputation, descending.

**Known gaps in skills:** the dApp reads only the first 100 boxes per query; "Run" only
copies `nodo execute <id>`; no package source works today (the file-source lookup has
its arguments swapped and no source boxes exist for the live services). The app can
launch a catalog service only on nodes that have it or can get it from their peers.
