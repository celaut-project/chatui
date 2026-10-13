# Product and UI direction (2026-10-13)

This note tells developers how the app must look and how it must treat wallets and
instances. It follows [decisions.md](decisions.md). Josemi decided these points on
2026-10-13. Features that are not built yet (M4 and M5) must follow this note.

This note says what the app must do. The code of M3 (PR #13) was written before the
answers of section 3 to 5 and differs in these points: the per-node limit is 0.05 ERG
(it must be 1 ERG), the compute home is behind a developer setting (it must be the
default), the home figures do not yet split full and read-only ERG, and there is no
node list. PR #15 brings the code to this note. Where the plan describes the code, it
describes the code of `master`; this note wins when they differ.

## 1. Wallets

The app holds more than one wallet. A wallet has one of two types:

| Type | Has the seed | Can sign | Use |
|---|---|---|---|
| Full wallet | yes | yes | Manage instances, pay nodes, send ERG and tokens |
| Read-only wallet (watch-only) | no | no | See balance and history only |

Both types exist in the app today (watch-only accounts, `watch_account_service.dart`).
Keep both.
Read-only wallets never start, stop or pay for an instance.

Rules:

- A wallet is **not** the owner of Celaut data. Instances, client ids, instance
  tokens, node sessions, quotes and the reputation event log are kept in **one
  database for the whole app**. There is no database per wallet. Do not add a
  `wallet_id` key to the Celaut tables.
- Instances are managed only with a **full wallet**: start, stop and any action that
  needs a signature or the seed. A read-only wallet cannot manage instances, because it
  has no seed. The instance data itself is still app-wide (see the rule above), so a
  full wallet can manage any instance the app holds, whichever wallet started it.
- A full wallet is also the only kind that **pays a node** (a deposit, M3). The app
  uses **one** full wallet for each payment. A read-only wallet is not offered in the
  payment choice. If the app has no full wallet, the deposit screen says so and does
  not start, and instance actions that need a full wallet are disabled with the same
  message.
- Read-only wallets are still shown in the Celaut screens, for balance and history
  only.
- The payment wallet is chosen at the time of the deposit. The deposit screen shows
  which wallet pays and its balance. A default wallet can be saved in the settings.
- Before a deposit signs, the deposit screen asks for the PIN or fingerprint of the
  chosen wallet, even if that wallet is already open.
- Start and stop need a full wallet that is **open** (unlocked), not only one that
  exists. If it is locked, the action asks the user to unlock it.
- The data of a node (deposit, client id, balance) does not record which wallet paid,
  except in the transaction history that the user can see (transaction id, address).
  A later deposit to the same node can come from another wallet.

## 2. Home screen: compute first, ERG second

Today the home screen is a wallet screen: it shows the wallets and how much ERG each
one holds. The app is now a client for compute, so the home screen changes its focus.

The compute view is the default home screen from the first release that has it. The
landing page of Celaut (branch `celaut-design`) is the visual reference.

The home screen must show, in this order of importance:

1. **Available compute.** The sum of the resources that all known nodes offer:
   CPU (cores), memory, disk, and the number of nodes. The data comes from the
   advertisement of each node (`GetPeerInfo`, resources). The nodes come from the
   app's explicit node list (see section 4). A node that is not reachable is not
   counted. Show the number of nodes that are counted and the number that are not
   reachable. Do not hide the difference.
2. **Money for compute.** Two separate figures, with distinct labels:
   - ERG in full wallets, which can pay for compute.
   - ERG in read-only wallets (watched addresses and accounts), which cannot pay.
   Also show the credit already deposited on nodes, in MU and in ERG. Show the free
   credit of each new client as a separate figure from the credit the user paid.
   The USD value of the ERG is shown here too, from the oracle pool price.
3. **Running instances.** The instances now running, with the cost so far, and a
   stop action.

The ERG amount of each wallet moves to a second level. It is not on the first view of
the home screen. The user reaches it from a wallets entry (a list of wallets with
their type, balance and history). Send, receive, ErgoPay and cold signing stay in the
wallet screens and do not change.

Rules for the numbers:

- Sums are over **advertised** resources, not free resources. Say "offered", not
  "free", unless the node tells how much is free.
- A sum with a missing part reads "at least X (N nodes unknown)". The data keeps the
  known part and the number of nodes without the value.
- A node that advertises several architecture entries counts with its **largest**
  entry, not the sum of them.
- Do not add the resources of one node twice when the node is reachable through more
  than one URI. The key is the peer_id.
- Show a value as "unknown" when it is missing. Do not show 0.
- ERG and MU are different units. Show both where money is shown, with the rate of the
  node that the value uses (see M3 in the plan).

## 3. What this changes in the milestones

| Milestone | Change |
|---|---|
| M3 | The deposit uses one full wallet that the user chooses. The confirmation screen shows the wallet, ERG and MU. Only full wallets are in the choice |
| M4 | The conversation screen and the instance list read from the single database. Starting or stopping an instance needs a full wallet |
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

## 5. Open items

- The exact layout, colors and motion of the compute screen. Use the celaut-design
  landing page as the reference, and ask Josemi for anything it does not show.

Ask Josemi before you decide anything not written here.
