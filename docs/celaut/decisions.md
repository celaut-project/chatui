# Product decisions (2026-10-11)

- **Base:** fork of the Argus Ergo wallet (arkadianet/Argus, MIT), history kept.
- **Wallet scope:** one wallet with its seed, send and receive ERG and tokens, history,
  ErgoPay, payment notifications, ERG/USD from the on-chain oracle
  pool. Removed: AMM, SigmaUSD, Dexy, DuckPools, Rosen, SigmaFi, stake recovery, stealth,
  ZeroJoin, dApp browser, CoinGecko prices, the Argus app fee. Removed on 2026-10-16:
  more than one wallet, watch-only addresses and accounts, offline (cold) signing.
- **Updater:** reads the releases of celaut-project/chatui.
- **QR scanner:** flutter_zxing (no Google ML Kit).
- **App:** label "Celaut", applicationId `org.celaut.chatui`. Android only (GrapheneOS
  without Play Services must work). APK built in GitHub Actions, published in GitHub
  Releases. UI in English and Spanish.
- **No third-party services:** no Firebase or similar. Ergo data comes from public Ergo
  nodes and explorers that the user can change.
- **Role on the network:** client only. The app never calls `IntroducePeer`.
- **Balancer:** Rust crate in `rust/crates/`, a port of nodo's execution balancer
  (quotes, sort, architecture/resource filter, on-chain reputation, quote cache). It is
  written so that nodo can use it later (PyO3).
- **Reputation for a new client:** the app keeps its own event log, as nodo does. While
  the log is empty, each opinion publisher gets credibility 1, limited by its burned ERG.
  After that, the app uses the nodo formula.
- **Node discovery:** reputation-proof boxes that nodes publish about themselves (see
  [catalog.md](catalog.md)), plus nodes that the user adds by address or QR code.
- **Service catalog:** celaut-project/skills. The user picks a skill. The app selects
  the service with the highest score. The user can also launch by service hash, or
  upload a package from the phone.
- **Wallets and storage (2026-10-16, replaces 2026-10-13):** the app holds one Ergo
  wallet, with its seed. There are no read-only wallets. The wallet manages instances
  (start, stop) and pays nodes. All Celaut data is in one database (no database per
  wallet). See [ui.md](ui.md), section 1.
- **Home screen (2026-10-13):** it shows the compute that the connected nodes offer
  (sum of their resources) and the money for compute first. The ERG of each wallet is
  second level. See [ui.md](ui.md). **Proposed on 2026-10-21, for Josemi to confirm:** the
  first screen is the Chats tab, and the compute view is the Compute tab
  ([ui-chat-first.md](ui-chat-first.md)).
- **Navigation (2026-10-21, Josemi):** a bottom bar with four tabs: Chats, Wallet,
  Compute, Settings. Each tab keeps its state; back on another tab goes to Chats. The
  conversation and the info page of an instance open over the bar. See
  [ui-chat-first.md](ui-chat-first.md), section 2.
- **Checks of the list of conversations (2026-10-21, Josemi):** the list asks the nodes
  when it opens, when the user comes back to it, and on a pull. It does not poll.
- **Instances are kept (2026-10-21, Josemi):** the app never forgets an instance or its
  token on its own, or because its node does not answer. A stopped instance stays in the
  database until the user deletes it; only a stopped instance can be deleted
  (`celaut_forget_instance` refuses the others). See
  [ui-chat-first.md](ui-chat-first.md), section 3.
- **Payments:** a deposit per node. A separate client id per node, not linked to the
  others.
- **Access to instances:** `ServiceTunnel` through the node.
- **Chat:** a conversation screen with a launched service (for example an LLM) through
  `ServiceTunnel`. It does not use the `Chat` RPC of nodo, which is for peers only.
- **Phase 1:** trimmed wallet that builds for Android; Rust crates for the protocol and
  the balancer, with tests against a local node; a screen that launches a service by
  hash and shows the quotes.
