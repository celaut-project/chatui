# Product and UI direction (2026-10-13)

This note tells developers how the app must look and how it must treat wallets and
instances. It follows [decisions.md](decisions.md). Josemi decided these points on
2026-10-13. Features that are not built yet (M4 and M5) must follow this note.

This note says what the app must do. PR #15 brought the code of M3 to this note. Where
the plan describes the code, it describes the code of `master`; this note wins when
they differ.

## 1. Wallets

**Decision of 2026-10-16 (Josemi), which replaces the two types of wallet of
2026-10-13:** the app holds **one** Ergo wallet, with its seed on this device. There are
no read-only (watch-only) wallets and no offline signing.

- With no wallet, the app offers to create a wallet or to restore one from its recovery
  phrase. With a wallet, it offers neither.
- To change the wallet, the user removes it in its settings (Settings, This wallet,
  Remove wallet), then creates or restores another one.
- **Migration at the update.** An earlier version can hold more than one wallet and
  watched addresses or accounts. At each start the app removes them
  (`app/lib/services/single_wallet.dart`):
  - the watched addresses, the watched accounts and their token tables;
  - the default payer of the deposits;
  - every wallet after the first of the user order of the wallets list, with its seed.
    This delete cannot be undone: the recovery phrase on paper is the only way back to
    such a wallet.

Rules:

- A wallet is **not** the owner of Celaut data. Instances, client ids, instance
  tokens, node sessions, quotes and the reputation event log are kept in **one
  database for the whole app**. There is no database per wallet. Do not add a
  `wallet_id` key to the Celaut tables.
- The wallet manages the instances (start, stop and any action that needs a signature)
  and pays the nodes (a deposit, M3). If the app has no wallet, the deposit screen says
  so and does not start, and the instance actions are disabled with the same message.
- The deposit screen shows the wallet that pays and its balance. Before a deposit signs,
  it asks for the PIN or fingerprint of the wallet, even if the wallet is already open.
- Start and stop need the wallet **open** (unlocked). If it is locked, the action asks
  the user to unlock it.
- The data of a node (deposit, client id, balance) does not record which wallet paid,
  except in the transaction history that the user can see (transaction id, address).
  After the user changes the wallet, a later deposit to the same node comes from the new
  wallet.

## 2. Home screen: what the user acts on

The compute view is the default home screen. The landing page of Celaut (branch
`celaut-design`) is the visual reference.

**Decision of 2026-10-16 (Josemi), which replaces the order of 2026-10-13 ("compute
first"):** the home screen shows only what the user acts on. The figures and the detail of
each node are one tap away. In this order:

1. **Running instances**, only when there are some: they cost money now. Each has its cost
   so far and a stop action. With no instance, nothing is shown.
2. **Run a service**: one button. It opens a screen of its own with the catalog of skills,
   the service files of the user and the import of a file
   (`app/lib/ui/celaut/run_service_screen.dart`). The catalog is read only there.
3. **One card of state**, three lines, each opens its detail:
   - the nodes: "N of M nodes ready · cores · memory", with a coloured dot (all ready,
     some, none). It opens the Nodes screen;
   - the credit on the nodes, in ERG with its USD value. It opens the Nodes screen;
   - the ERG of the wallet, with its USD value. It opens the page of the wallet; with no
     wallet, the screen that creates or restores one.
   A node that forgot the client of the app shows its action under the nodes line,
   because the user must choose (section 3).

Not on the home screen any more: the big figure of the cores, memory and disk as separate
figures, the note "offered, not free", the paid and the free credit
apart, the USD source note, the card of each node (address, MU, rate, latency, reasons) and
"Check now". The Nodes screen has the card of each node: its availability (section 4), its
credit from the last overview, the action for a forgotten client, and "Check now".

**Load.** The home screen shows the last overview at once when it opens again (it is kept
in memory), with a thin line while it asks the nodes; on the first open it says that it
loads, and the button and the wallets do not wait. The overview gives each node 5 seconds
for each step (20 through Tor), not 15: one node that does not answer no longer holds the
screen for 30 seconds. The home screen does not check the nodes in the background (the
overview records one check for each node it asks); the Nodes screen checks them while it is
open. The catalog keeps its answers for 5 minutes, and gives the last answer when the
explorer fails.

Rules for the numbers:

- Sums are over **advertised** resources, not free resources. Say "offered", not
  "free", unless the node tells how much is free.
- A sum with a missing part reads "at least X (N nodes unknown)". The data keeps the
  known part and the number of nodes without the value.
- A node that advertises several architecture entries counts with its **largest**
  entry, not the sum of them. The largest entry has the most memory; with equal
  memory, the most cores; then the most disk. A known value is larger than an unknown
  value. The values of different entries are not mixed.
- Do not add the resources of one node twice when the node is reachable through more
  than one URI. The key is the peer_id.
- Show a value as "unknown" when it is missing. Do not show 0.
- ERG and MU are different units. Show both where money is shown, with the rate of the
  node that the value uses (see M3 in the plan).

### Run a service

The button "Run a service" of the home screen opens its screen
(`app/lib/ui/celaut/run_service_screen.dart`, with the section
`app/lib/ui/celaut/run_service_section.dart`). It lists the skills of the catalog with a
search field. A skill opens a sheet with its services, best first, and the node that the
balancer would use with its start cost. Run needs the wallet open.

- The screen lists every skill of the catalog; the search narrows the list.
- Run asks first: "Run <name>?", with what a running instance costs and the node that the
  balancer would use now with its start cost (or that no node gave a price yet). Run in
  the list of the service files of the user asks in the same way. The launch again after
  a transfer of the service does not ask a second time.

- Run asks every node of the Nodes list for a quote and starts the service on the first
  node that works (`launchService`). Nodes whose last checks failed twice in a row are not
  asked, unless that would leave no node. A node where the credit of the app is less than
  the price is not asked to start.
- If the service has a chat slot, the conversation opens. If not, a message shows and the
  instance appears in the list of the home screen.
- If no node starts it, a sheet says why for each node: the reason and what to do (the text
  of the error kind), the numbers for a credit problem with a button to the deposit screen,
  "left out" for the nodes that were not asked, and the original text of the node under
  "Details". A node that forgot the client id gives the usual choice; the app never makes a
  new client by itself.

## 3. What this changes in the milestones

| Milestone | Change |
|---|---|
| M3 | The deposit uses the wallet of the app. The confirmation screen shows the wallet, ERG and MU |
| M4 | The conversation screen and the instance list read from the single database. Starting or stopping an instance needs the wallet open |
| Home | The home screen follows section 2. Do it with the first screen that needs the node data (M3), or in its own PR before it |
| Storage | The Celaut store (client ids, instance tokens) is one encrypted store for the app, as the plan already says. See plan section 3 |
| Client ids | If a node forgets a stored client id, the app shows the error and asks the user: create a new client (the old balance is lost) or retry later. It never creates a client silently |
| Per-node limit | 1 ERG per node. It counts all deposits of the app to that node, from any wallet, and is kept across restarts |

## 4. Known nodes and the explorer

- The app keeps an **explicit list of nodes**, with add and remove. A node is added by
  address or QR code, or comes from the on-chain directory (decisions.md).
- Removing a node takes it out of the sums of the home screen. Its deposits and client
  id are kept, so adding it back restores them.
- The Ergo explorer is fixed to the nodo default. A node does not advertise an
  explorer, and the app does not poll one from the node.

### Availability of the nodes

Each node card on the home screen has a line with the availability of the node, from the
checks that the Rust core keeps in the Celaut database (`celaut-client/src/health.rs`):

| State | Line |
|---|---|
| Available | "Available · 42 ms" |
| Slow (3 s or more) | "Slow · 4200 ms", in the warning colour |
| Unreachable | "Not answering · Last answer 2 h ago" (or "It has never answered"), then the reason in words (the text of the error kind) and the text of the node or of the transport in a smaller muted line |
| Not checked yet | "Not checked yet" |

A coloured dot goes with the text and never replaces it. While a check runs, the line adds
"Checking…".

When the home screen is open, the app asks the core every minute to check the nodes that are
due, and when the app is in use again. The core decides which node is due: a node that works
is checked every 5 minutes, and a node that fails later and later (30 s up to 15 minutes);
through Tor the times are three times longer. A check has a limit of 5 seconds (25 through
Tor). "Check now" under the node cards checks all the nodes. A check changes only the node
cards: the overview (the figures) is not loaded again. Nothing is checked while Tor is
starting or has failed.

## 5. Open items

- The exact layout, colors and motion of the compute screen. Use the celaut-design
  landing page as the reference, and ask Josemi for anything it does not show.

Ask Josemi before you decide anything not written here.
