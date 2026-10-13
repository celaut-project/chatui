# End-to-end check of the deposit (M3)

This check sends real ERG on Ergo mainnet. Do it only after a maintainer approves the
amount. nodo does not accept the Ergo testnet (plan, section 7, question 5).

Nothing in CI runs it. The automated tests make no transaction.

## What the check proves

One deposit from the wallet of the app to our own node: the deposit token from the
node, the transaction with the token in R4, the box on the explorer of the node, one
`Payable`, and the new balance of the client on the node.

## Amount and cost

| Item | Amount | Where it goes |
|---|---|---|
| Deposit | 0.01 ERG (10 000 000 nanoERG) | The hot wallet of our node. We keep it: the node is ours |
| MU that it buys | 10 000 000 MU (`MU_PER_NANOERG` is 1 on our node) | The client of the app on the node |
| Miner fee of the deposit | 0.0011 ERG (`TX_FEE_NANO`) | Miners. This is the cost |
| Funding of the test wallet (path A only) | 0.02 ERG from the funding wallet, fee 0.0011 ERG | The test wallet. About 0.0089 ERG stays in it after the deposit |

- Path A (the app, recommended): total out of the funding wallet 0.0211 ERG. Cost in
  fees: 0.0022 ERG, or 0.0033 ERG if the rest of the test wallet goes back to the
  funding wallet. 0.01 ERG moves to the node wallet.
- Path B (the Rust test, no app): total out of the paying wallet 0.0111 ERG. Cost in
  fees: 0.0011 ERG. 0.01 ERG moves to the node wallet.

The limit of a node in the app is 0.05 ERG by default. The Rust test refuses more than
that.

## The node

Our node needs no change for the check. On 2026-10-13 (nodo `ec1274d`) it already
advertises an ERG payment contract on mainnet, because `ledgers.ergo` is in its config
and Java is installed. Check these values before the test. Do not change the config
for the test.

| Key | Value | Why |
|---|---|---|
| `network.DELEGATE_EXECUTION` | `false` | With `true`, the node can pay other nodes from its wallet by itself |
| `ledgers.ergo.payments.DONATION_PERCENTAGE` | `"0"` | No donation payment from the deposit |
| `ledgers.ergo.payments.COLD_WALLET` | `""` | No sweep of the hot wallet |
| `general_flags.SUBMIT_REPUTATION_AT_INIT` | `false` | No reputation transaction at a restart |
| `general_flags.SIMULATE_PAYMENTS` | `false` | The node checks the real explorer |
| `ledgers.ergo.payments.MU_PER_NANOERG` | `1` | 1 nanoERG buys 1 MU |

Read-only check of the node (no transaction):

```sh
ssh -f -N -L 18460:127.0.0.1:53460 node-host
cd rust
CELAUT_NODE_PORT=18460 cargo test -p wallet-ffi --lib node_read_only -- --ignored --nocapture
```

It prints the peer_id, the address that receives the deposits, the rate, the ledger
declaration (it must have `network=mainnet` and `payment.deposit_token=R4 …`), and one
deposit token. Result on 2026-10-13: pay-to address
`9gYud7au5rwN42SmqChYL78idvBUXNxK9T2CK4DDU1ZnkYwk88Q`, 1 MU per nanoERG, a token of 36
characters, free credit 4 500 000 MU. That address had no box, so the deposit box will
be the only box that the node reads.

Before and after the test, on the node: `nodo doctor` (0 FAIL), `nft list table inet nodo`
and the hash of `config.yaml` stay the same.

## Path A: the app in the Android emulator (recommended)

1. Build and install the debug APK on the emulator (AOSP image, no Google services).
   Forward the Gateway to the host: `ssh -f -N -L 18460:127.0.0.1:53460 node-host`. The
   emulator reaches the host at `10.0.2.2`.
2. In the app, create a new wallet (the test wallet), a full wallet. Send 0.02 ERG to
   its first address from the funding wallet. Wait for one confirmation. Keep it open.
3. Dry run, no transaction: Settings, Developer, Celaut deposit. The paying wallet is
   the test wallet (only full wallets are offered). Node `10.0.2.2:18460`,
   Check the node. The card shows the pay-to address above, 1 MU per nanoERG and
   4 500 000 MU. Amount 0.01, Prepare the deposit. The sheet shows 0.01 ERG, 10,000,000 MU,
   the fee 0.0011 ERG and the pay-to address. Tap Cancel. The node got a deposit token
   only; it expires after one hour.
4. The deposit: Prepare the deposit again, then Deposit. The balance on the node belongs
   to the client id of the app on that node, which is in the Celaut database of the app,
   so a restart does not lose it; a sent deposit that waits for the node is listed on
   the screen after a restart. The screen shows the
   transaction id, then "The app waits until the explorer shows the box", then "The
   node accepted the deposit. Balance of the client: 14,500,000 MU".
5. Optional: in Celaut service, start `tiny` on the same node with a start balance of
   5 000 000 MU (more than the free credit), call it, and stop it. The refund comes back
   to the same client.
6. Optional: send the rest of the test wallet back to the funding wallet (0.0011 ERG fee).

## Path B: the Rust test (no app)

The same Rust code without the screens. It reads the recovery phrase from a file on the
machine that runs it.

```sh
cd rust
# Dry run: deposit token and unsigned transaction, printed and cancelled. No signature.
CELAUT_NODE_PORT=18460 CELAUT_E2E_MNEMONIC_FILE=/path/to/words.txt \
  CELAUT_E2E_NANO_ERG=10000000 \
  cargo test -p wallet-ffi --lib deposit_end_to_end -- --ignored --nocapture
# The deposit: the same command with CELAUT_E2E_SEND=yes
```

The test checks that the node accepts the payment and that the balance of the client
grows by 10 000 000 MU.

## What to record

The transaction id, the box id, the balance before and after, the node log lines of the
payment (`Check payment process to …`, `Payment is valid.`), and the state of the node
after the test.
