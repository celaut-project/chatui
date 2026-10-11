# Celaut client plan

This plan puts the Celaut part of chatui into milestones. The design is in the notes
in `docs/celaut/` (decisions, wire, balancer, catalog). This plan follows those
decisions and does not change them. Each milestone ends with a check that a reviewer
can run.

## 0. Status and next tasks

Updated on 2026-10-11, master at `160d24c`.

| Item | Status |
|---|---|
| M0: build from source, CI on master, debug APK in CI | Done. Merged in `5c3b2b3` (PR #1). CI run 38156157458 on master passed (rust, flutter, android) |
| `celaut-proto` and the design notes (`docs/celaut/`) | Done. Merged from `celaut-crates` in `160d24c`. Make new PRs into master. Do not use `celaut-crates` again |
| M0b: trimmed wallet and new identity | Not started on master. Start from master (see M0b in section 5) |
| M1 to M5 | Not started |

Do the next tasks in this order. Each task is one PR into master.

1. **M0b**, see section 5. It changes many files, so do it before the Celaut code.
2. **wire.md corrections:** apply section 8 to `docs/celaut/wire.md`. This is a
   small PR, and it can go in parallel with M0b.
3. **M1**, then **M2**. The protocol crates do not depend on M0b. You can start
   `celaut-wire` before M0b is merged, but make the PR after M0b.
4. **M3**, **M4**, then **M5** if Josemi agrees.

Some open questions in section 7 block a milestone. Get an answer before you start
that milestone:

| Question | Blocks |
|---|---|
| 3. First text service | M4 |
| 4. Delegation | Nothing now; M2 uses `remaining_hops: 1` |
| 5. Test node, credit and testnet | The end-to-end checks of M2 and M3 |
| 7. Tor | M5 |
| 9. Release key | The first release APK (M0b updater check) |

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
  ├─ celaut-wire      TLS identity check, gRPC, bee-rpc framing
  │    └─ celaut-proto    prost types (exists on celaut-crates)
  ├─ celaut-balancer  port of the nodo execution balancer (balancer.md)
  ├─ celaut-catalog   node directory and skills catalog from the explorer (catalog.md)
  └─ wallet-core / ergo-tx   deposit transaction (needs an R4 register on one output)
```

Crates to add in `rust/crates/`:

| Crate | Content | Dependencies |
|---|---|---|
| `celaut-proto` | Gateway types. Exists on `celaut-crates` | prost 0.14 |
| `celaut-wire` | rustls `ServerCertVerifier` that checks the identity extension (wire.md section 1) and returns the peer_id; one generic bidi call `call(method, [(index, bytes)]) -> [(index, bytes)]` over `buffer.Buffer`; bee-rpc send and receive (wire.md section 2), including blocks and the signal | tonic 0.14 (no generated stubs, because each method is `stream Buffer -> stream Buffer`), tokio-rustls, rustls 0.23 with ring (already in the workspace) |
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

**M1: connect to a node and show its advertisement.** `celaut-wire` and the first
part of `celaut-client`: TLS with the identity check, GenerateClient (with PoW),
GetPeerInfo. Verify the `Peer` signature: Ed25519 over
`"<public_key>|<ts>|<content_digest>"` (`nodo:protos/celaut.proto:725-731`, digest in
`nodo:src/identity/node_identity.py`), `public_key` equal to the peer_id of the
certificate, and `ts` greater than the last one seen. A debug screen: enter `host:port`, show peer_id, URIs, rates, payment
contracts and resources. Check: an integration test against a nodo that we run
ourselves (M1 starts no service, so a node without KVM can be enough if its Gateway
starts); unit tests with fixed bee-rpc streams and a fixed certificate.

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
  for a delegated one (open question 4).

Each TCP connection through the local port is one ServiceTunnel stream and pays
`TUNNEL_OPEN_MU`, so the Dart side keeps HTTP connections alive.

A new client gets free credit (`free_tier.CREDIT_MU_PER_NEW_CLIENT`, default
4 500 000 MU). `pricing.BUILD_MU` (10 000 000 MU) is more than that, so the service
must already be built on the node, or the test node gives more credit. Check: on our
own node (x86_64 with KVM), start a small HTTP service, call it through the local port
from the app, stop it, and see the refund.

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
leaves. Check: a conversation with the first text service that we choose (open
question 3).

**M5: privacy** (after M4, if Josemi agrees). Optional Tor for outbound connections,
so that a node does not see the IP address of the phone. It does not hide the node;
onion addresses for nodes are nodo work (open question 7).

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

## 7. Open questions for Josemi

1. **"Celaut node implementation" in the description:** is the app a light client
   only (decisions.md says so), or is a later "light node" role intended (for example
   to relay requests or announce itself)? Should the description change?
2. **Order of work:** answered. `celaut-crates` is merged into master, and all new
   work comes as PRs into master. The order is in section 0.
3. **First service for M4:** which text service do we use (an LLM service, or a
   simple echo or translation service for the first test)? Which protocol does it
   speak on its slot: plain HTTP with JSON, an OpenAI-compatible API, or gRPC?
   A small convention for "chat" services would let the app talk to any of them.
4. **Delegation:** with `remaining_hops: 1` the app uses only the nodes that it calls
   directly. Is that correct for the light client, or should nodo relay ServiceTunnel
   to a delegated instance (for example, accept the alias token and forward)?
5. **Test node and ledger:** can the M2 and M3 tests use our own node with a larger
   `CREDIT_MU_PER_NEW_CLIENT`? `general_flags.SIMULATE_PAYMENTS` is payer-side only
   (a node does not accept a simulated Payable). Does nodo accept deposits on the
   Ergo testnet, so that M3 can be tested with no real ERG?
6. **Package upload from the phone:** decisions.md says the user can upload a package.
   Is that `.celaut.bee` import through StartService indices 5 and 6, for nodes that
   do not have the service? Size limits on mobile data?
7. **Tor:** is client-side Tor (hide the phone) wanted in the app, or only onion
   addresses for nodes in nodo? If the app uses Tor, is a Rust Tor client (Arti)
   acceptable, given the size of the APK?
8. **Node directory:** few nodes publish their address on-chain
   (`SUBMIT_NETWORK_ADDRESS_TO_REPUTATION_PROOF`). Is a list of bootstrap nodes in
   the app acceptable, or only on-chain boxes and user input?
9. **Releases:** which key signs the release APK, and who keeps it? Does CI sign, or
   does a maintainer sign the CI build by hand?

## 8. Notes for `docs/celaut/wire.md`

Checked against nodo dev `e3d12301`:

- nodo now pins bee-rpc-over-grpc-py v0.0.2 (nested blocks, up to 32 levels). The
  `bee_rpc:client.py` line numbers in wire.md are from v0.0.1.
- Observe needs the instance token (`gateway_bee.py` declares `token`), not "none".
- Section 3: "uri can be empty (delegated …), then use ServiceTunnel" does not work for
  a delegated instance (see M2).
- Add the StartService send order, the Peer signature check and the Payable conditions
  from M1 to M3 above.
