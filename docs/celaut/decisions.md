# Product decisions (2026-10-11)

- **Base:** fork of the Argus Ergo wallet (arkadianet/Argus, MIT), history kept.
- **Wallet scope:** one wallet with its seed, send and receive ERG and tokens, history,
  ErgoPay, payment notifications, ERG/USD from the on-chain oracle
  pool. Removed: AMM, SigmaUSD, Dexy, DuckPools, Rosen, SigmaFi, stake recovery, stealth,
  ZeroJoin, dApp browser, CoinGecko prices, the Argus app fee. Removed on 2026-10-16:
  more than one wallet, watch-only addresses and accounts, offline (cold) signing.
- **Updater:** reads the releases of celaut-project/chatui.
- **QR scanner:** flutter_zxing (no Google ML Kit).
- **App:** label "Chatui" (2026-10-23, Josemi; it was "Celaut"), applicationId
  `org.celaut.chatui` (unchanged). Android only (GrapheneOS
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
  [ui-chat-first.md](ui-chat-first.md), section 3. **Changed on 2026-10-23 (Josemi):** the
  lists hide the stopped instances by default, with a button that shows them; they stay in
  the database.
- **Payments:** a deposit per node. A separate client id per node, not linked to the
  others.
- **Access to instances:** `ServiceTunnel` through the node.
- **Chat:** a conversation screen with a launched service (for example an LLM) through
  `ServiceTunnel`. It does not use the `Chat` RPC of nodo, which is for peers only.
- **Phase 1:** trimmed wallet that builds for Android; Rust crates for the protocol and
  the balancer, with tests against a local node; a screen that launches a service by
  hash and shows the quotes.
- **Environment variables (2026-10-22, Josemi):** the app has a container of named values.
  When a service that declares variables is launched, the app asks for each one: choose
  one of the container, type it as UTF-8, or skip it (it is then absent from the
  configuration). Design in [env-variables.md](env-variables.md).
- **Peer invitation (2026-10-22, Josemi):** the app reads the QR code of nodo#579
  (`protos/invite.proto`) and connects to the node by the address that is most feasible on the
  current route, with the invited key pinned. See [invite.md](invite.md).
- **Service details and the chat check (2026-10-22, Josemi):** the app reads the Service as a
  stream and never keeps its filesystem. It shows what the service declares (prose, resources,
  interface, networks, variables) and, before a launch, warns if the interface is not the chat
  convention of Chatui. The title of the app is Chatui (2026-10-23, Josemi; it was Celaut Chatui), in lower
  case except the C, with "ui" in the other colour. See [service-info.md](service-info.md).
- **Chat attachments (2026-10-22, Josemi):** a message can carry image and audio files
  (JPEG, PNG, MP3, WAV; at most 4 files of 4 MiB each). A service that accepts them
  announces `accepts` in the history read, and the app shows the attach button only then.
  The files stay in memory only. The app does not play audio: a tap hands the file to the
  share sheet of the system. See [chat.md](chat.md) and
  [ui-chat-first.md](ui-chat-first.md), section 7.
- **Chat without a wait, with streaming (2026-10-23, Josemi):** a send (`POST`) replies at
  once with the user message, and the app reads the conversation (`GET`, with the filters
  `from`, `last` and `limit`) every 2 seconds while it waits for an answer, and every 10
  seconds otherwise. The user can send many messages at the same time. An answer can grow
  while the service makes it (`status` `streaming`), with the `reasoning` of the model
  apart from the `text` (the Claude remote service). A service that sends the whole answer
  stays valid. This is revision 5 of [chat.md](chat.md).
- **Specification of the chat interface (2026-10-22):** [chat.md](chat.md) is written in
  ASD-STE100, has a revision number (4 on that day, 5 since 2026-10-23), covers the protocol only, and has conformance
  tests (section 10). A service follows the interface if it passes them. The rules for the
  app are in [ui-chat-first.md](ui-chat-first.md).
- **Leaving a conversation (proposed on 2026-10-21, for Josemi to confirm):** Back goes to
  the list without a question. The instance runs on and the node keeps charging. Stop is
  in the menu, on the info page and on a long press. See
  [ui-chat-first.md](ui-chat-first.md), section 5.
- **Settings (2026-10-23, Josemi):** three sections. Ergo: the wallet, the Ergo network, the
  address book, the remote previews. Compute: the nodes, the deposit, the automatic top-up,
  Tor, the environment variables, the node check and the Celaut service screen. General:
  security and auto-lock, display, the first screen, About. There is no Developer group.
  The app has no setting for the language: it follows the language of the phone.
- **Sleep and the auto-lock (2026-10-23, Josemi):** a launch, a transfer of a service file
  and an import of a service file go on with the screen off or the app in the background:
  the foreground service holds the process and a partial wake lock while they run. The
  auto-lock still locks the wallet on time; while one of them runs it does not close its
  page. See [ui-chat-first.md](ui-chat-first.md), section 8.
- **Automatic top-up (2026-10-23, Josemi):** off by default. It moves credit that the app
  already has on a node to a running instance under a threshold (`ModifyDeposit`). It never
  makes an on-chain deposit: with too little credit it asks the user, and a deposit keeps its
  own confirmation and PIN. See [ui.md](ui.md), section 4b.
