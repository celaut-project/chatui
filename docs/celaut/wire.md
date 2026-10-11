# Wire protocol of the nodo Gateway (light client view)

A node also announces most of this at runtime in `Peer.uri[].protocol_stack` (layers
`tls`, `http2`, `grpc`, `bee-rpc`, `celaut-gateway`), from
`nodo:src/identity/transport_stack.py`. The per-RPC tables are in
`nodo:protos/gateway_bee.py`.

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

**Send one object** (`bee_rpc:client.py:937-1014`):

- Bytes = the serialized message. Index 0 is always raw bytes.
- Fewer than 1 MiB: one `Buffer{chunk, head{index}, separator=true}`.
- 1 MiB or more: `Buffer{head{index}}`, then chunks of 1 MiB or less, then
  `Buffer{separator=true}`.
- A client sends everything inline. It does not send blocks.

**Receive** (`bee_rpc:client.py:511-841`):

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
  not overlap. Block contents are chunks; concatenation gives the object.
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
| GetServiceEstimatedCost | 1 Client, 2 RecursionGuard, 3 Configuration, 4 `Metadata.HashTag.Hash`, 5 Metadata, 6 Service | 1 `EstimatedCost`, then a signal | client |
| StartService | same as above | signal, then 1 `ServiceInstance` | client |
| StopService | 1 `TokenMessage{instance token}` | 1 `Refund` | token |
| ModifyDeposit | 1 `ModifyDepositInput` | 1 `ModifyDepositOutput` | token |
| GetMetrics | 1 `TokenMessage{instance token or client_id}` | 1 `Metrics` | token |
| GetResourceAvailability | 1 `ArchitectureResources`, 2 `Client` | 1 `ResourceAvailability` | client |
| GetService | 1 Hash, 2 Client (send Client first) | 4 Hash, 5 Metadata, 6 Service | client |
| ServiceTunnel | 1 `TokenMessage{token, slot}`, then 0 bytes | 0 bytes | token |
| Observe | 1 `ObserveRequest` | 1 `ObserveEvent` (stream) | none |
| Chat | 1 `ChatMessage` | 1 `ChatAck` | peers only |

Notes:

- **GenerateClient** (`nodo:src/gateway/client_pow.py`): difficulty =
  `clients // 500`. With difficulty > 0, `client_id` must be 32 lowercase hex characters
  and the reply is `PoWRequired{challenge, difficulty}`. Retry with
  `Client{client_id, challenge, pow_solution}`. Proof of work: the hex of
  `blake2b-512(utf8(challenge) || utf8(solution))` must end with `difficulty` zeros. A
  new client gets free credit (`free_tier.CREDIT_MU_PER_NEW_CLIENT`, default 4 500 000 MU).
- **GetPeerInfo** needs a client, so call GenerateClient first.
- **StartService / GetServiceEstimatedCost** (`nodo:src/gateway/iterables/abstract_input_service_iterable.py`):
  send Client, Configuration, one Hash per hash type; Metadata and Service only if the
  node asks (no signal). For a quote, nodo sends only Client, Configuration and the
  hashes. StartService charges `EstimatedCost.cost` from the client balance. After the
  reply, half-close.
- **ServiceInstance.instance.uri_slot[].uri** can be empty (delegated or no host ports).
  Then use ServiceTunnel. Only instances that run on that node can be tunnelled.
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
   at 1 and `Client` at 2. The node checks the explorer
   (`/api/v1/boxes/unspent/unconfirmed/byAddress/{address}`).
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
