# Product and UI direction (2026-10-13)

This note tells developers how the app must look and how it must treat wallets and
instances. It follows [decisions.md](decisions.md). Josemi decided these points on
2026-10-13. Features that are not built yet (M3 to M5) must follow this note.

## 1. Wallets

The app holds more than one wallet. A wallet has one of two types:

| Type | Has the seed | Can sign | Use |
|---|---|---|---|
| Full wallet | yes | yes | Pay nodes, send ERG and tokens |
| Read-only wallet (watch-only) | no | no | See balance and history |

Both types exist in the app today (watch-only accounts, `watch_account_service.dart`).
Keep both.

Rules:

- A wallet is **not** the owner of Celaut data. Instances, client ids, instance
  tokens, node sessions, quotes and the reputation event log are kept in **one
  database for the whole app**. There is no database per wallet. Do not add a
  `wallet_id` key to the Celaut tables.
- Every wallet, full or read-only, is shown in the Celaut screens. All of them can be
  used to manage instances (see them, see the cost, stop them), because the instance
  belongs to the app, not to a wallet.
- A wallet matters only when the app **pays a node** (a deposit, M3). The app then
  uses **one** wallet for that payment. Only a full wallet can pay. A read-only wallet
  is not offered in the payment choice. If the app has no full wallet, the deposit
  screen says so and does not start.
- The payment wallet is chosen at the time of the deposit. The deposit screen shows
  which wallet pays and its balance. A default wallet can be saved in the settings.
- The data of a node (deposit, client id, balance) does not record which wallet paid,
  except in the transaction history that the user can see (transaction id, address).
  A later deposit to the same node can come from another wallet.

## 2. Home screen: compute first, ERG second

Today the home screen is a wallet screen: it shows the wallets and how much ERG each
one holds. The app is now a client for compute, so the home screen changes its focus.

The home screen must show, in this order of importance:

1. **Available compute.** The sum of the resources that all connected nodes offer:
   CPU (cores), memory, disk, and the number of nodes. The data comes from the
   advertisement of each node (`GetPeerInfo`, resources). A node that is not
   connected is not counted. Show the number of nodes that are counted and the number
   that are not reachable. Do not hide the difference.
2. **Money for compute.** The ERG that the user owns (all wallets), and the credit
   that is already deposited on nodes (MU, and its ERG value). This is the value that
   can pay for compute.
3. **Running instances.** The instances now running, with the cost so far, and a
   stop action.

The ERG amount of each wallet moves to a second level. It is not on the first view of
the home screen. The user reaches it from a wallets entry (a list of wallets with
their type, balance and history). Send, receive, ErgoPay and cold signing stay in the
wallet screens and do not change.

Rules for the numbers:

- Sums are over **advertised** resources, not free resources. Say "offered", not
  "free", unless the node tells how much is free.
- Do not add the resources of one node twice when the node is reachable through more
  than one URI. The key is the peer_id.
- Show a value as "unknown" when it is missing. Do not show 0.
- ERG and MU are different units. Show both where money is shown, with the rate of the
  node that the value uses (see M3 in the plan).

## 3. What this changes in the milestones

| Milestone | Change |
|---|---|
| M3 | The deposit uses one full wallet that the user chooses. The confirmation screen shows the wallet, ERG and MU. Only full wallets are in the choice |
| M4 | The conversation screen and the instance list read from the single database. They do not depend on a wallet |
| Home | The home screen follows section 2. Do it with the first screen that needs the node data (M3), or in its own PR before it |
| Storage | The Celaut store (client ids, instance tokens) is one encrypted store for the app, as the plan already says. See plan section 3 |

## 4. Not decided

- The exact layout, colors and motion of the home screen. The landing page design of
  Celaut (branch `celaut-design`) is the visual reference.
- How the app shows the resources of a node that gives only a partial advertisement.
- Whether the home screen shows a money value in USD (the oracle pool price exists).

Ask Josemi before you decide one of these.
