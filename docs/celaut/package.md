# Give a service to a node that does not have it

A node runs only the services that it has. A node that does not have a service
refuses a quote or a start with "This node does not have the service X, and the request
does not contain it". The request can contain it: `StartService` and
`GetServiceEstimatedCost` take the service in their indices 4 (hashes), 5 (Metadata) and
6 (Service, with its blocks). This note says how the app does it.

## Where the app gets a service

1. **A node that has it.** `GetService` gives the indices 4, 5 and 6, the same as
   `StartService`, so the answer can go to another node as it is. A node that has the
   service is one that gave a quote, or one that refused for another reason (closed,
   no room, no credit). `GetService` needs a client id on that node.
2. **A `.celaut.bee` file** that `nodo export` wrote. It has the Metadata at index 1 and
   the Service at index 2; the app gives them the indices 5 and 6.

The skill catalog does not give a source for a package today (`docs/celaut/catalog.md`).

## How it moves

- The app keeps the service in a `.bee` file in its private storage (`packages/`), and
  reads it while it sends it. A service is never in memory: the Buffers go from the
  answer of one node, or from the file, to the next node as they are, with their blocks.
- The app gives the service with a **quote** (`GetServiceEstimatedCost`): the node
  stores the service, then answers with the price. After that the node has it, and the
  launch works as usual, with the hash only. A node can store the service and still
  refuse the quote, for example for an architecture that it does not run.
- A transfer that fails or that the user cancels must not leave half a service on the
  node: nodo does not check the hash of a service when it stores it, and at a clean end
  of a request it takes a cut message for a complete one. So the app sends **cancel
  markers** before it ends the request (bee-rpc 0.2: block A opens, block B opens, block A
  closes). nodo refuses them with `IntersectionError`, and does not store the service.

## The Bee-RPC part

bee-rpc-over-grpc-rs 0.2 has two calls for a relay (`grpc::call_buffers`,
`grpc::call_raw`) and the cancel markers. 0.2.1 makes the error of the input come first
when the node refuses the markers before its first answer, as nodo does.

## Code

| Where | What |
|---|---|
| `rust/crates/celaut-wire` | `Transport::call_buffers` and `call_raw`; `gateway::get_service_raw` and `get_service_estimated_cost_with_service`; `WireError::Relay` |
| `rust/crates/celaut-client/src/package.rs` | Save the answer of `GetService` to a `.bee` file, inspect a file (layout, service id), read it for a node, and cancel |
| `rust/crates/wallet-ffi/src/api/celaut_package.rs` | `celaut_fetch_service`, `celaut_inspect_package`, `celaut_send_service`, `celaut_transfer_progress`, `celaut_cancel_transfer` |

## Checks

- `celaut-client/tests/package.rs`: save, inspect, read with the indices of a node, a
  `nodo export` file, a node that does not have the service, an error and a cancel that
  leave no file, a cut file, files that are not packages.
- `celaut-wire/tests/relay_calls.rs`: what the node gets, in order.
- `celaut-client/tests/nodo_service.rs` (ignored; needs nodo, see its header), against two
  real nodo Gateways (nodo master `5649c2c`, bee_rpc v0.0.2), on 2026-10-15:
  - the app gives a service of 3 MiB to node A with a quote, and A stores it;
  - `GetService` of A gives it back (3 145 981 bytes);
  - a transfer from that file to node B that is cut in the middle of the Service is
    refused, and B does not keep it;
  - the whole transfer from the file makes B store it, and `GetService` of B gives the
    same bytes;
  - a first transfer cut in the Service is not stored.
  The quotes themselves were refused (the test service declares no architecture, and the
  test Gateway has no manager): the transfer works, the price is the business of the node.
- Not checked: a service that nodo splits into blocks (the service of the test was too
  small for that; the blocks are checked in bee-rpc against the vectors of the reference),
  a phone, and mobile data.
