# Execution receipts

A node signs **execution receipts** (nodo#419, `nodo:docs/EXECUTION_RECEIPTS.md`). A
receipt is evidence against the node that signed it. It is never evidence for the node.
The app checks each receipt when it comes, keeps it, and lets the user export it.

## 1. What the node sends

| Kind | Where | What it signs |
|---|---|---|
| `start` | `ServiceInstance.receipt`, in the answer of `StartService` | the service, a salted digest of the environment variables, and the start amount (`initial_mu`) |
| `checkpoint` | `ServiceTunnel`, index 2 of the answer | the counters and two hash chains of the stream: the messages into the service (`in`) and out of it (`out`), and what the tunnel cost (`mu_charged`) |
| `close` | the same place, as the last receipt | the same fields; the stream stopped normally |

The node signs `celaut-execution-receipt:<peer_id>|<receipt_digest>` with its identity
key (Ed25519). `rust/crates/celaut-wire/src/receipt.rs` has the canonical text, the
digests, the chains and the check. Its tests use the vectors of
`nodo:tests/identity/test_execution_receipt.py`, and give the same bytes.

## 2. The tunnel

- The client sets `TokenMessage.receipts` on each tunnel. It accepts index 2 also when
  it did not ask: a bee-rpc reader refuses an index that it does not know, so this lets
  the node send receipts to all callers.
- Each message that the client sends at index 0 is one event of the `in` chain. Each
  message that it gets at index 0 is one event of the `out` chain. A payload is sent in
  pieces of 64 KiB or less, and each piece is one message.
- At each checkpoint, the client finds the state of its own chain with the same count,
  and compares the bytes and the head. The node can count fewer `in` messages than the
  client sent (they were still on the way), so the client keeps the state after each
  message since the last checkpoint that matched. A head that is not the client's head
  is a mismatch: the node signed data that the phone did not send or did not receive.
- The receipt must verify against the `peer_id` of the TLS connection and the token of
  the instance (`execution_name`).
- **A stream that the phone cancels has no close, and that is not a fault** (nodo
  cannot send after the cancel). The app shows "none (cancelled)", not an error.
- The node signs a checkpoint every 1 MiB or 5 s of traffic. After 65 536 messages with
  no checkpoint, the client stops the chain check of that stream (it is not called a
  fault) and still checks the signatures.

## 3. The start

The app checks the start receipt against what it sent:

- signed by the node of the connection, for the token of the instance;
- `service_id` is the SHA3-256 id of the service that the phone started;
- `envs_digest` is `blake2b_256(envs_salt || canonical envs)` of the variables that the
  phone sent (the last value of a name, no `__nodo_instance_name`), with the salt of the
  receipt;
- if the phone sent `Configuration.initial_mu`, the receipt has the same amount.

## 4. What the app keeps

The receipts are in the Celaut database (`CelautData.receipts`, by instance id), and
they go when the instance is deleted. For each instance:

- the start receipt;
- for each tunnel stream (64 streams at most, the oldest go first): the count of the
  checkpoints, the last checkpoint or the close (the highest `seq` is what a dispute
  reads), the receipts with a fault (8 at most), and whether the phone cancelled it.

The chains cannot be checked again later: the app does not keep the bytes. So the app
keeps what it found when the receipt came. The signature and the shape of each stored
receipt are checked again each time the app reads them, so a stored receipt that was
changed shows as a receipt that does not verify.

## 5. The info page

The info page of an instance has a **Receipts** part: the start (✓, ✗ or none), the
count of the checkpoints, the close of the tunnels (✓, "none (cancelled)" or "open"),
and each fault in red. **Export receipts** shares a JSON Lines file: one receipt on
each line, in the proto3 JSON form. This command checks it:

    nodo receipt verify receipts-<id>.jsonl --peer <peer_id> [--token <token>]

The file has no token: the token opens the instance.
