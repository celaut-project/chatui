# Celaut client plan

This plan puts the Celaut part of chatui into milestones. The design is in the notes
in `docs/celaut/` (decisions, wire, balancer, catalog). This plan follows those
decisions and does not change them. Each milestone ends with a check that a reviewer
can run.

## 0. Status and next tasks

Updated on 2026-10-12, master at `c7044fe` plus the M2 PR.

| Item | Status |
|---|---|
| M0: build from source, CI on master, debug APK in CI | Done. Merged in `5c3b2b3` (PR #1). CI run 38156157458 on master passed (rust, flutter, android) |
| `celaut-proto` and the design notes (`docs/celaut/`) | Done. Merged from `celaut-crates` in `160d24c`. Make new PRs into master. Do not use `celaut-crates` again |
| M0b: trimmed wallet and new identity | Done. Merged in PR #3 (section 5). Spanish is a separate PR after it |
| `bee-rpc-over-grpc-rs` | M1a done. Tag `v0.1.0` (`a832abc`) has the whole API: frames, blocks, signal, skip, hashes and the generic bidi call over tonic. `celaut-wire` uses it as a git dependency. Its license is GPL-3.0-only, and chatui is GPL-3.0-only too (section 7, question 10) |
| M1: connect to a node and show its advertisement | Done. Merged in PR #9 |
| M2: quote, start, tunnel, stop on free credit | Done, in review (PR #11). `celaut-wire` (the M2 calls and `ServiceTunnel`), `celaut-balancer`, `celaut-client` (node sessions, quotes, the local port), the FFI functions in `api/celaut_service.rs` and the debug screen (Settings, Developer). Checked on our own node, from the client crate and from the app in the Android emulator (see M2 in section 5). Not tested: a phone, a node on the internet, more than one node |
| M3 to M5 | Not started |
| Open questions (section 7) | Answered on 2026-10-11 and 2026-10-12 |

Do the next tasks in this order. Each task is one PR into master.

1. **M0b**, see section 5. Done (PR #3).
2. **wire.md corrections:** section 8. Done (PR #2). The M1 PR adds the `ts` rule and
   the signature scheme to wire.md.
3. **bee-rpc in Rust** (M1a): the repo
   [bee-rpc-protocol/bee-rpc-over-grpc-rs](https://github.com/bee-rpc-protocol/bee-rpc-over-grpc-rs).
   Done: tag `v0.1.0`.
4. **M1**: done (PR #9). **M2**: done, in review (PR #11).
5. **M3**, **M4**, then **M5**.

Josemi answered all the open questions on 2026-10-11 and 2026-10-12 (section 7).

Measured by the author of PR #1 on 2026-10-11, master at `802dd55`, macOS arm64,
Rust 1.99.0, Flutter 3.41.2, NDK 28.2.13676358:

| Check | Result |
|---|---|
| `cargo test --workspace` | pass: 1042 passed, 0 failed, 15 ignored |
| `cargo clippy --workspace` | pass (14 warnings) |
| `cargo clippy --workspace --all-targets` | 1 error in a test of vendored `ergo-tx` (`babel.rs:663`, the empty range `2..1` is on purpose) |
| `flutter analyze` | no issues |
| `flutter test` | pass: 1704 passed, 3 skipped |
| `flutter build apk --debug` | pass; the APK has `libwallet_ffi.so` for arm64-v8a and x86_64 |
| `celaut-crates`: `cargo build -p celaut-proto` | pass; `cargo run -p gen-protos` gives no diff |
| nodo protos since `b5c1e8a5` | no change up to nodo dev `e3d12301` |

## 1. Goal

An Android app that uses Celaut services with no intermediary:

1. Find nodes (on-chain directory, or an address or QR code from the user).
2. Find services (celaut-project/skills catalog, or a service hash).
3. Get quotes from the nodes, select one with the balancer, and launch the service.
4. Pay the node from the wallet of the app (one deposit and one client id per node).
5. Use the service through `ServiceTunnel`, for example in a conversation screen.

## 2. Non-goals

- Run services on the phone. Android has no KVM for guests, and nodo needs
  cloud-hypervisor or QEMU on Linux. The app is a client, never a peer
  (it never calls `IntroducePeer`).
- Pack services on the phone. Upload of a package that already exists is in scope
  later; the build of a package is not.
- Operator features of nodo (peer chat, reputation submits for the node,
  configuration of a node).
- iOS and desktop builds.
- Escrow or trustless payment. A deposit is a plain payment to the key of the node.
  The risk is limited by the amount (see section 6).

## 3. What the app can do on a phone

| Topic | Fact | Effect |
|---|---|---|
| Network | The app only opens outbound TLS connections to the Gateway port | NAT and carrier-grade NAT are not a problem. No inbound port is necessary |
| Instance access | `uri_slot` is often empty; `ServiceTunnel` goes through the node | All service traffic goes through the node and is charged to the instance |
| Background | Android stops background sockets and processes | A long tunnel needs a foreground service. Instances continue on the node; the app keeps their tokens and stops them |
| Storage | Instance tokens and client ids are bearer secrets | Keep them encrypted, as the seed is today |
| Size | The native library is 32 MB per ABI now | Removing the DeFi crates (decisions.md) makes it smaller. Tor (section 6) makes it larger |

## 4. Architecture

```
Flutter UI (app/lib/celaut/...)
  │  flutter_rust_bridge (wallet-ffi, new module api_celaut)
  ▼
celaut-client   connect, client ids, quotes, start/stop, deposits, tunnels
  ├─ celaut-wire      TLS identity check, gRPC; uses bee-rpc (external crate)
  │    └─ celaut-proto    prost types (exists on celaut-crates)
  ├─ celaut-balancer  port of the nodo execution balancer (balancer.md)
  ├─ celaut-catalog   node directory and skills catalog from the explorer (catalog.md)
  └─ wallet-core / ergo-tx   deposit transaction (needs an R4 register on one output)
```

Crates to add in `rust/crates/`:

| Crate | Content | Dependencies |
|---|---|---|
| `celaut-proto` | Gateway types. Exists on `celaut-crates` | prost 0.14 |
| `celaut-wire` | rustls `ServerCertVerifier` that checks the identity extension (wire.md section 1) and returns the peer_id; the Celaut calls on top of the `bee-rpc` crate (repo `bee-rpc-over-grpc-rs`: framing, blocks, signal, generic bidi call; wire.md section 2). Not ported in this repo | tonic 0.14 (no generated stubs, because each method is `stream Buffer -> stream Buffer`), tokio-rustls, rustls 0.23 with ring (already in the workspace) |
| `celaut-client` | Typed RPCs, PoW of GenerateClient (blake2b-512), a store for client ids and instance tokens per peer_id, a quote cache, a local TCP listener on 127.0.0.1 that sends each connection through `ServiceTunnel` | celaut-wire, blake2 |
| `celaut-balancer` | Filter, score, MU conversion, event log (balancer.md) | celaut-proto |
| `celaut-catalog` | Explorer queries for node boxes and skills; ranking (catalog.md) | wallet-net (explorer HTTP) |

The FRB surface stays small and uses plain types:

```
celaut_add_node(uri) -> NodeInfo { peer_id, uris, rates, payment_methods, resources }
celaut_quotes(service_hash, config) -> Vec<Quote>        // balancer output, best first
celaut_start(peer_id, service_hash, config) -> Instance  // token stays in Rust
celaut_stop(instance_id) -> Refund
celaut_open_tunnel(instance_id, slot) -> u16             // local port for Dart HTTP
celaut_deposit_prepare(peer_id, amount_mu) -> unsigned tx for the existing sign screen
celaut_deposit_notify(peer_id, deposit_id) -> Balance
celaut_events() -> Stream<CelautEvent>                   // FRB StreamSink
```

A local port lets the Dart side use a normal HTTP client (or a WebView) for a service,
and keeps the gRPC and bee-rpc code in Rust.

## 5. Milestones

Each milestone is one or more PRs into master. Feature code waits for the review of
this plan.

**M0: build is green** (done, PR #1). The Gradle build makes `libwallet_ffi.so` from
source. CI runs on master and builds the debug APK. Check: the CI `android` job.

**M0b: trimmed wallet and new identity** (decisions.md). Remove the DeFi crates and
screens, the dApp browser, the CoinGecko prices and the app fee. Label "Celaut",
applicationId `org.celaut.chatui`, flutter_zxing scanner, updater on the
celaut-project/chatui releases. Check: the APK runs on GrapheneOS without Play
Services; `flutter test` and `cargo test` pass.

Start M0b from master. A partial trim exists on the machine of Josemi, but it will
not be pushed. Do not wait for it.

Items that are not done yet (master at `160d24c`):

- `namespace` and `applicationId` are `com.argus.argus_wallet`
  (`app/android/app/build.gradle.kts`). Change both to `org.celaut.chatui`, and move
  `MainActivity` to the new package.
- `android:label` is "Argus" (`app/android/app/src/main/AndroidManifest.xml`).
- The updater reads `arkadianet/Argus` (`app/lib/build_info.dart`,
  `app/lib/services/update_service.dart`).
- `mobile_scanner` is still used in `app/lib/ui/scan_screen.dart`. Replace it with
  `flutter_zxing`.
- CoinGecko is still used in `app/lib/ui/home/erg_price_feed.dart`,
  `home_models.dart` and `settings/display_settings_page.dart`. Use only the oracle
  pool price.
- The app fee is still in `rust/crates/vendor/ergo-tx/src/dev_fee.rs` and its callers
  (`send.rs`, `tx_helpers.rs`, `utxo_management.rs`, `wallet-ffi/src/api.rs`,
  `api_ergopay_impl.rs`). Remove it, and remove the tests that expect a fee output.
- Spanish: decisions.md asks for English and Spanish. The app has no localization
  now (no `flutter_localizations`, no ARB files). Add it in a separate PR after M0b,
  before M1 adds new screens.

Also check that `scripts/release_check.sh` and the CI APK check still pass with the
new applicationId.

**M1a: bee-rpc in Rust** (repo `bee-rpc-over-grpc-rs`). Steps 2 to 7 of its
`PORTING.md`, one PR per step. An AI agent can do them: give it `PROMPT.md`; its
rules are in `AGENT_GUIDE.md`. Check: the tests of each step pass in CI (vectors
generated from the Python v0.0.2 reference), and the interop tests with a Python
peer pass.

**M1: connect to a node and show its advertisement.** Uses the `bee-rpc` crate (git
dependency on the tag `v0.1.0`, then a release). `celaut-wire` and the first part of
`celaut-client`: TLS with the identity check, GenerateClient (with PoW), GetPeerInfo.
Verify the `Peer` signature: Ed25519 over `"<public_key>|<ts>|<content_digest>"`
(`nodo:protos/celaut.proto:725-731`, digest in `nodo:src/identity/node_identity.py`),
`public_key` equal to the peer_id of the certificate, and `ts` not older than the last
one seen. A debug screen (Settings, Developer): enter `host:port`, show peer_id, URIs,
rates, payment contracts and resources. Check: an integration test against a nodo that
we run ourselves (M1 starts no service, so a node without KVM is enough if its Gateway
starts); unit tests with fixed bee-rpc streams and a fixed certificate.

Done in M1:

- `celaut-wire`: the identity check (`IdentityVerifier`, a rustls `ServerCertVerifier`;
  TLS 1.3 only, ring, no aws-lc), a tonic channel on it, the `Transport` trait, and
  the typed calls `generate_client` and `get_peer_info`.
- `celaut-client`: the proof of work, the port of `canonical_peer_content_digest`, the
  check of the `Peer`, and a store of the last advertisement per peer_id (memory or one
  JSON file). It keeps no client id: M1 uses it for one call and drops it.
- FFI: `celaut_peer_info(host, port, expected_peer_id, store_path)`. The debug screen
  passes no `store_path` yet, because the app has no data directory (`path_provider`
  is not a dependency), so the app keeps the last `ts` values in memory.
- Tests: known-answer vectors made with the nodo Python code
  (`celaut-client/tests/vectors/generate.py`), certificates made with it
  (`celaut-wire/tests/data/make_certs.py`), and a test that runs the real `Gateway()` of
  nodo (`celaut-client/tests/nodo.rs`, `#[ignore]`, with instructions at the top of the
  file). That test needs no root and no KVM: `nodo_gateway.py` serves the Gateway on a
  local TLS port without firewall, manager or services.

Facts from nodo dev `e3d12301` that differ from the first notes:

- A node serves the same signed `Peer` again for up to 60 seconds
  (`_SIGNED_PEER_TTL_S`, `nodo:src/gateway/utils.py`), so a second `GetPeerInfo` gives
  the same `ts`. The client accepts an equal `ts` when the content digest is also equal
  (the same message), and refuses an older `ts`, or an equal `ts` with another digest.
- The node checks `Peer.signature_scheme` before the key (`speaks_our_signature_scheme`).
  The client does the same: one component that names Ed25519 as nodo defines it.
- The digest covers the expiry and the transport of each URI, the reputation proofs,
  the scheme and every resource field with its presence. `benchmark` is sorted by the
  text of each entry, and a repeated key stays (it is not "sorted by key").
- GenerateClient: the client proposes a random UUID4 as `client_id`. With a proof of
  work the node uses the id in the challenge, and the difficulty in the challenge
  (the third field), not `PoWRequired.difficulty`. The client refuses a difficulty
  above 6 (about 16 million hashes); nodo accepts up to 64.

**M2: quote, start a service and call it through a tunnel, with no payment.**
GetServiceEstimatedCost on each known node, the balancer, StartService, StopService,
GetMetrics, ServiceTunnel with the local port. Two rules from nodo dev:

- Send Client, RecursionGuard and Configuration before the Hash. The node starts the
  work on the message that makes the service known, and ignores a later Configuration
  (`nodo:src/gateway/iterables/abstract_input_service_iterable.py:96-106`).
- Send `RecursionGuard{token: "", remaining_hops: 1}`. The node then runs the service
  itself and does not delegate it. A delegated instance has no path for a phone:
  ServiceTunnel accepts only tokens of local instances
  (`nodo:src/tunneling/rpc_tunnel.py:346-351`), and the node gives an alias token
  for a delegated one (decision 4 in section 7).

Each TCP connection through the local port is one ServiceTunnel stream and pays
`TUNNEL_OPEN_MU`, so the Dart side keeps HTTP connections alive.

A new client gets free credit (`free_tier.CREDIT_MU_PER_NEW_CLIENT`, default
4 500 000 MU). `pricing.BUILD_MU` (10 000 000 MU) is more than that, so the service
must already be built on the node, or the test node gives more credit. Check: on our
own node (x86_64 with KVM), start a small HTTP service, call it through the local port
from the app, stop it, and see the refund.

What M2 has (PR #11):

- `celaut-wire`: GetServiceEstimatedCost, StartService (time limit 600 s),
  StopService and GetMetrics. `ServiceRequest::parts` sends Client (1), RecursionGuard
  (2), Configuration (3, only if it has bytes) and the Hash (4), in this order.
  ServiceTunnel: `TokenMessage{token, slot}` at index 1, then the bytes at index 0 in
  pieces of 64 KiB. The end of the request half-closes the connection to the service.
- `celaut-balancer`: the port of `estimated_cost_sorter` and `scoring.py`. Quotes are
  compared in nanoERG with the `mu_per_unit` of the ERG contract of each node (rounded
  up). A node with no ERG rate comes last. A stable sort, and a quote cache (10 s, 4096
  entries). Not yet: the filter on the advertised resources, and reputation events (0).
- `celaut-client`: `NodeSession` (one client id per node, in memory only), `quotes`
  (all nodes at the same time, 10 s each), and `LocalPort` on 127.0.0.1: one
  ServiceTunnel stream per TCP connection, half-close in both directions, the last
  error kept.
- FFI (`api/celaut_service.rs`): quote, start (with an optional start balance), open a
  local port, status, stop. Client ids and instance tokens stay in Rust; Dart gets an
  instance id.
- Dart: `TunnelHttp` (one `HttpClient`, one connection per port, no proxy) and the
  debug screen "Celaut service" (Settings, Developer).

Facts from nodo dev `ec1274d` (the node of the check):

- The start cost is the build (`BUILD_MU`, only if the node has no built container
  for the service) plus the start balance of the instance. A service in the registry
  is not built before its first run.
- Without `Configuration.initial_mu`, the start balance is one hour of the resources of
  the service: 5 000 683 MU for the test service on our node, more than the free
  credit. So the app sends `initial_mu` (the screen proposes 1 000 000 MU), and the
  node quotes and charges that amount. This works because Configuration comes before
  the Hash.
- StopService gives the unused balance of the instance back to the client at once, and
  GetMetrics of the client shows it.
- GetMetrics with the token of a stopped instance is an error ("Invalid token"), not a
  balance of 0.

Check on 2026-10-12, on our node (x86_64 with KVM, nodo dev `ec1274d`, default
config: free credit 4 500 000 MU, `BUILD_MU` 10 000 000 MU). Service: `tiny` of
demo-service (`9b0e4e45d3b078451984895891402a24b24a7f4112522592d7b3e2326aecb4c4`), an HTTP server on port 3030. The Gateway
port came through an SSH port-forward, with no new firewall rule.

- The node had `tiny` in its registry, but not built: the first quote was 14 389 612
  MU. One `nodo execute` on the node built it, and was stopped at once. No change of
  the config and no restart.
- `cargo test -p celaut-client --test real_node -- --ignored`, start balance
  1 000 000 MU: new client 4 500 000 MU; quote 1 000 000 MU, then 11 990 MU every 10 s;
  start: slot 3030, client 3 500 000 MU; three GETs through the local port on one TCP
  connection: HTTP 200 each time, 1 stream; instance 986 400 MU before the calls and
  976 400 MU after (one `TUNNEL_OPEN_MU`); stop: refund 976 399 MU; client
  3 500 000 MU before the stop and 4 476 399 MU after.
- From the app (debug APK in the arm64 AOSP emulator, the node at `10.0.2.2`): quote,
  start, local port, three calls (HTTP 200, 1 stream), stop: refund 940 074 MU, client
  4 440 074 MU.
- After the check: `nodo doctor` 23 OK and 0 FAIL or WARN; `nft list table inet nodo`
  and `config.yaml` as before; no instance or tunnel of the check left. What stays on
  the node: the built container of `tiny`, and the test clients in its database.

**M3: deposit with the wallet.** GenerateDepositToken, an Ergo transaction with one
output to the node script and the token in R4 (the send path in `ergo-tx/src/send.rs`
writes no registers today), the existing confirmation and sign screens, wait until the
box is on the explorer, then Payable once. The node needs no confirmation: the box can
be in the mempool, but it must be unspent and visible on the explorer of the node.
`Payment.contract` must be the `Contract` from GetPeerInfo without a change, because
the node compares its declaration. A per-node limit and a confirmation screen
that shows ERG and MU. Check: unit tests of the transaction; one end-to-end test on our
own node only after approval of the amount (see section 6).

**M4: conversation screen.** Select a skill or a service hash, launch it, and talk to
it through the tunnel. Show the cost so far, and stop the instance when the user
leaves. First write the "chat" convention (HTTP with JSON, decision 3 in section 7).
Check: a conversation with a simple echo service that follows it.

**M5: privacy** (after M4). Optional Tor (Arti, off by default) for outbound connections,
so that a node does not see the IP address of the phone. It does not hide the node;
onion addresses for nodes are nodo work (decision 7 in section 7).

## 6. Risks

| Risk | Mitigation |
|---|---|
| Payment to a dishonest node: the deposit is a plain payment, and the node can keep it | Small deposits, a per-node limit, local reputation events (balancer.md), refunds through StopService |
| `Payable` is one attempt only | Call it only after the box is on the explorer that the node uses; keep the deposit token and the transaction id so that the user can see what happened |
| Loss of instance tokens or client ids loses the balance on the node | Encrypted storage; StopService when the app closes the conversation |
| Keys on the device | The seed stays in Rust and Android Keystore as today. The app adds no new long-term key: a client id is a random bearer id per node |
| Mobile networks drop long gRPC streams | Reconnect the tunnel; keep requests to a service short, or let the service resume |
| Rate limit: more than 120 calls in 60 s per client puts the client in quarantine for 300 s | Quote cache (10 s), no polling loops |
| Delegated instances cannot be reached from a phone | `remaining_hops: 1` (M2); a nodo change if delegation is wanted later |
| Tunnel cost (open fee 10 000 MU, 2 000 000 MU per GiB) | Show the cost; stop idle instances |
| Privacy: each node sees the IP address of the phone and links its calls by client id | One client id per node (decisions.md); Tor in M5 |
| Protocol drift from nodo dev | `celaut-proto/protos/SOURCE` pins the commit; a CI job can compare it with nodo dev |
| Real funds in tests | No transaction in automated tests. Manual tests on our own node only, with an amount that a maintainer approves first |

## 7. Decisions on the open questions (2026-10-11)

1. **Role:** the app is a light client only. It never acts as a peer. The repository
   description is now "Android light client for Celaut, with an Ergo wallet".
2. **Order of work:** `celaut-crates` is merged into master, and all new work comes
   as PRs into master. The order is in section 0.
3. **First service for M4:** a simple echo (or translation) service over HTTP with
   JSON, with a small "chat" convention that a later LLM service also follows.
   Write the convention down in M4 before the screen.
4. **Delegation:** no delegation. The app sends `remaining_hops: 1`, so the node
   that it calls runs the service. A nodo change to relay ServiceTunnel comes only if
   delegation is wanted later.
5. **Tests of M2 and M3:** our own node with a large `CREDIT_MU_PER_NEW_CLIENT` for
   M2 (not needed in the end: the M2 check runs on the default credit, see M2 in
   section 5). For M3: nodo does not accept the Ergo testnet (answer of 2026-10-12).
   Mainnet fees are small enough, so the M3 end-to-end test uses one small real
   deposit on mainnet, with an amount that is approved first (section 6).
6. **Package upload:** import a `.celaut.bee` that already exists, through
   StartService indices 5 and 6, for a node that does not have the service. Show the
   size and warn on mobile data. This needs the send side of blocks in
   `bee-rpc-over-grpc-rs`, which is not in its current plan.
7. **Tor:** optional, with Arti (Rust), off by default, in M5 after M4.
8. **Node directory:** no bootstrap list in the app. Only on-chain node boxes and
   nodes that the user adds by address or QR code.
9. **Release key:** changed on 2026-10-12. CI signs the release APKs with a key used
   only for chatui. The key is in the secrets of the GitHub environment `release`,
   which accepts only tags `v*` and needs Josemi's approval before each signing job.
   Steps: set `appVersion` and `appBuildNumber` in `build_info.dart` and `pubspec.yaml`,
   merge, then push the tag `v<appVersion>`. The `release` workflow builds the APKs,
   waits for the approval, signs them, runs `release_check.sh apks` and creates a
   prerelease. The updater ignores prereleases, so mark a release as latest only after
   the test on GrapheneOS.

10. **License (decided, 2026-10-12):** `bee-rpc` is GPL-3.0-only and the app links it
    into `libwallet_ffi.so`. Josemi decided that chatui is GPL-3.0-only. `LICENSE` has
    the text, and `NOTICE.md` keeps the MIT notice of Argus, from which chatui is
    forked. The workspace `license` is `GPL-3.0-only`.

## 8. Notes for `docs/celaut/wire.md`

Checked against nodo dev `e3d12301`:

- nodo now pins bee-rpc-over-grpc-py v0.0.2 (nested blocks, up to 32 levels). The
  `bee_rpc:client.py` line numbers in wire.md are from v0.0.1.
- Observe needs the instance token (`gateway_bee.py` declares `token`), not "none".
- Section 3: "uri can be empty (delegated …), then use ServiceTunnel" does not work for
  a delegated instance (see M2).
- Add the StartService send order, the Peer signature check and the Payable conditions
  from M1 to M3 above.
