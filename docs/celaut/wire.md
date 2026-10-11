# Wire protocol of the nodo Gateway (light client view)

A node also announces most of this at runtime in `Peer.uri[].protocol_stack` (layers
`tls`, `http2`, `grpc`, `bee-rpc`, `celaut-gateway`), from
`nodo:src/identity/transport_stack.py`. The per-RPC tables are in
`nodo:protos/gateway_bee.py`.

The `nodo:` line numbers are from nodo dev `e3d12301`. The protos and `gateway_bee.py`
are the same as at `b5c1e8a5`, the commit that `celaut-proto` pins.

## 1. Transport

- **Port:** no fixed default. `network.GATEWAY_PORT: auto` picks a free port on the first
  start. Clients learn it from `Peer.uri[].port`.
- **TLS only for a remote client.** The TLS port binds `[::]`. The plaintext port
  (`GATEWAY_PORT + 1`) binds only the guest bridge or loopback (`nodo:src/serve.py:376-401`).
- **gRPC:** path `/celaut.Gateway/<Method>`, `application/grpc`, no custom metadata.
  Every method is `stream buffer.Buffer -> stream buffer.Buffer`. Errors are non-OK
  statuses with readable text.
- **TLS:** TLS 1.3, ALPN `h2`, SNI `celaut-node`, no client certificate. The server
  certificate is self-signed P-256 and changes when the node restarts.
- **Node identity in the certificate** (`nodo:src/identity/tls_identity.py`):
  - Extension OID `2.25.276125094420857322236898758448456352855`, not critical.
  - Its OCTET STRING contents are ASCII `"<pubkey_hex>:<sig_hex>"`.
  - `pubkey_hex` is the 64-character lowercase hex of an Ed25519 key. It is the
    **peer_id**. Reject a non-canonical spelling.
  - `sig_hex` is Ed25519 over UTF-8 `"CELAUT" + hex(DER SubjectPublicKeyInfo)`.
  - A Rust client verifies this in a custom rustls `ServerCertVerifier` and checks the
    TLS 1.3 handshake signature normally. That pins the certificate.

## 2. bee-rpc framing

`buffer.Buffer` (`nodo:protos/buffer.proto`): `chunk=1`, `separator=2`, `signal=3`,
`head=4 {index}`, `block=5`, `skip=6`. All are proto3 `optional`.

nodo pins bee-rpc-over-grpc-py **v0.0.2** (`nodo:bash/requirements.txt:15`). The
`bee_rpc:client.py` line numbers below are from v0.0.2.

**Send one object** (`bee_rpc:client.py:967-1156`, `serialize_to_buffer`):

- Bytes = the serialized message. Index 0 is always raw bytes.
- Fewer than 1 MiB: one `Buffer{chunk, head{index}, separator=true}`.
- 1 MiB or more: `Buffer{head{index}}`, then chunks of 1 MiB or less, then
  `Buffer{separator=true}`.
- A client sends everything inline. It does not send blocks.

**Receive** (`bee_rpc:client.py:617-965`, `parse_from_buffer`):

- An object starts at a Buffer with `head`, `chunk` or `block`. It ends at
  `separator=true`, or at a Buffer with no `chunk`, no `head` and no `block`.
- `head.index` selects the type. With no head: index 1 if the table has it, else 0. An
  unknown index is an error.
- An object with 0 bytes is dropped, except when index 1 is `buffer.Empty`. So an
  all-default proto3 message never arrives. "Nothing received" can mean "all-default
  message".
- `signal=true` toggles "pause/resume sending". In StartService and
  GetServiceEstimatedCost the server sends one signal to mean "I have the service, stop
  uploading". It never sends the resume.
- Blocks: `Buffer{block}` opens a block, the same hashes close it; they can nest and must
  not overlap. Block contents are chunks; concatenation gives the object. A receiver
  accepts up to 32 levels of nesting (`MAX_BLOCK_NESTING`, `bee_rpc:client.py:317`).
  A deeper block is an error.
- `skip` (receiver to sender) is optional. A client can ignore it.
- A request ends when the client half-closes its side.

**Hash types** (`nodo:src/utils/hashing.py`): the type id is the digest of the empty
input. SHA3-256 = `a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a`.
The node registry uses SHA3-256.

## 3. RPCs

Auth "client" = `client_id` must exist on the node (rate limit 120 calls / 60 s per
client). Auth "token" = possession of an instance token.

| RPC | Request indices | Response indices | Auth |
|---|---|---|---|
| GenerateClient | 1 `Client` (optional) | 1 `Client` or 2 `PoWRequired` | none |
| GetPeerInfo | 1 `Client` | 1 `Peer` | client |
| GenerateDepositToken | 1 `Client` | 1 `TokenMessage` | client |
| Payable | 1 `Payment`, 2 `Client` | 1 `buffer.Empty` | client |
| GetServiceEstimatedCost | 1 Client, 2 RecursionGuard, 3 Configuration, 4 `Metadata.HashTag.Hash`, 5 Metadata, 6 Service | signal, then 1 `EstimatedCost` | client |
| StartService | same as above | signal, then 1 `ServiceInstance` | client |
| StopService | 1 `TokenMessage{instance token}` | 1 `Refund` | token |
| ModifyDeposit | 1 `ModifyDepositInput` | 1 `ModifyDepositOutput` | token |
| GetMetrics | 1 `TokenMessage{instance token or client_id}` | 1 `Metrics` | token |
| GetResourceAvailability | 1 `ArchitectureResources`, 2 `Client` | 1 `ResourceAvailability` | client |
| GetService | 1 Hash, 2 Client (send Client first) | 4 Hash, 5 Metadata, 6 Service | client |
| ServiceTunnel | 1 `TokenMessage{token, slot}`, then 0 bytes | 0 bytes | token |
| Observe | 1 `ObserveRequest{instance_id = instance token}` | 1 `ObserveEvent` (stream) | token |
| Chat | 1 `ChatMessage` | 1 `ChatAck` | peers only |

Notes:

- **GenerateClient** (`nodo:src/gateway/client_pow.py`): difficulty =
  `clients // 500`. With difficulty > 0, `client_id` must be 32 lowercase hex characters
  and the reply is `PoWRequired{challenge, difficulty}`. Retry with
  `Client{client_id, challenge, pow_solution}`. Proof of work: the hex of
  `blake2b-512(utf8(challenge) || utf8(solution))` must end with `difficulty` zeros. A
  new client gets free credit (`free_tier.CREDIT_MU_PER_NEW_CLIENT`, default 4 500 000 MU).
- **GetPeerInfo** needs a client, so call GenerateClient first. Verify the `Peer`
  before you use it (`nodo:protos/celaut.proto:722-731` and `:777-779`):
  - `public_key` is 64 lowercase hex characters and is equal to the peer_id of the TLS
    certificate.
  - `signature` is Ed25519 by `public_key` over UTF-8
    `"<public_key>|<ts>|<content_digest>"` (`nodo:src/identity/node_identity.py:651-660`).
  - `content_digest` is the lowercase hex of blake2b-256 over the canonical text of all
    the other fields of the Peer (`canonical_peer_content_digest`,
    `nodo:src/identity/node_identity.py:570-648`).
  - `ts` (field 99) is more than the `ts` of the last Peer that the app accepted for the
    same `public_key`.
- **StartService / GetServiceEstimatedCost** (`nodo:src/gateway/iterables/abstract_input_service_iterable.py`):
  send in this order: Client, `RecursionGuard{token: "", remaining_hops: 1}`,
  Configuration, then one Hash per hash type. Send Metadata and Service only if the
  node asks (no signal). The node starts the work on the message that makes the
  service known (a Hash or the Metadata when the node has the service, else the
  Service). Then it sends the signal, and after it the reply. It ignores a
  Configuration or a RecursionGuard that comes later (lines 93-106 and 157-194). For a
  quote, nodo sends only Client, Configuration and the hashes. StartService charges
  `EstimatedCost.cost` from the client balance. After the reply, half-close.
- **RecursionGuard:** `remaining_hops: 1` makes the node run the service itself. It
  does not delegate it. A light client must send it: a delegated instance has no path
  for a phone (see the next item).
- **ServiceInstance.instance.uri_slot[].uri** can be empty (no host ports). Then use
  ServiceTunnel. ServiceTunnel accepts only the token of an instance that runs on that
  node (`nodo:src/tunneling/rpc_tunnel.py:346-351`). For a delegated instance the node
  gives an alias token, and ServiceTunnel refuses it. A delegated instance is not
  reachable from the app.
- **Observe** takes the instance token in `ObserveRequest.instance_id`
  (`nodo:protos/gateway_bee.py:153-157`, `nodo:src/gateway/iterables/observe_iterable.py`).
- **Chat** answers `stored=false, "client_id … is not associated with any peer"` to a
  light client (`nodo:src/manager/chat.py:164-184`).

## 4. Client lifecycle and Ergo deposit

1. TLS channel; the peer_id comes from the certificate.
2. `GenerateClient` → `client_id` (solve PoW if asked).
3. `GetPeerInfo` → `Peer.payment_contracts`. Take the `ContractRate` with
   `contract.ledger.tags[0] == "ergo"` and xattr `token_id == "ERG"`. Xattr `script` is
   the node's P2PK ErgoTree. `mu_per_unit` is MU per nanoERG (default 1).
4. `GenerateDepositToken` → a UUID string with hyphens. It expires after 3600 s.
5. Ergo transaction: one output with `ergoTree = script`, value at least
   `amount_mu / mu_per_unit` nanoERG (minimum box value 1 000 000), `R4 = Coll[Byte]`
   of the UTF-8 deposit token.
6. **`Payable`** with `Payment{deposit_token, contract (echo it unchanged), amount=MU}`
   at 1 and `Client` at 2 (`nodo:src/gateway/gateway.py:291-313`,
   `nodo:src/payment_system/payment_process.py:883-964`). The node accepts the payment
   only if all of these are true:
   - The deposit token is `pending` (not expired, not used) and belongs to a client
     that exists.
   - `contract.ledger` is the same declaration as the ledger of the node, and the
     contract selects a payment method of the node. A changed `Contract` fails, so send
     the one from GetPeerInfo without a change.
   - The address of `script` is the wallet address of the node.
   - The explorer of the node
     (`/api/v1/boxes/unspent/unconfirmed/byAddress/{address}`) shows an unspent box with
     the deposit token in R4 and a value of at least the amount in nanoERG. The box needs
     no confirmation: it can be in the mempool
     (`nodo:src/payment_system/contracts/ergo/interface.py:956-1018`).

   **One attempt only:** the token becomes `payed` or `rejected`. Call it only after
   the box is visible on the explorer.
7. Balance: `GetMetrics(TokenMessage{token=client_id})`.
8. ServiceTunnel charges the instance: open fee 10 000 MU and 2 000 000 MU per GiB.
   StopService refunds the unused instance balance to the client.

## 5. ServiceTunnel bytes

- Request: `Buffer{head{1}, chunk=TokenMessage{token, slot="<internal port>"}, separator}`,
  then each payload as `Buffer{head{0}, chunk, separator}` (`head.index=0` is required).
- Response: `Buffer{head{0}, chunk (64 KiB or less), separator}`.
- TCP: message boundaries carry no meaning. UDP: one message = one datagram.
- Half-closing the request closes the write side of the TCP connection to the service.
