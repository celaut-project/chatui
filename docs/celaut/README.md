# Celaut light client: design notes

These notes are the reference for the Celaut part of chatui. The app is an Android
light client of Celaut. It talks to Celaut nodes (celaut-project/nodo) as a client,
never as a peer, and it pays them from its own Ergo wallet.

Sources read for these notes:

- celaut-project/nodo at `b5c1e8a5` (paths below start with `nodo:`).
- bee-rpc-over-grpc-py v0.0.1/v0.0.2 (`bee_rpc:`).
- celaut-project/skills at its `main` branch of 2026-10-11 (`skills:`).

| File | Content |
|---|---|
| [decisions.md](decisions.md) | Product decisions |
| [wire.md](wire.md) | Transport, TLS identity, bee-rpc framing, Gateway RPCs, client lifecycle, deposits, ServiceTunnel |
| [balancer.md](balancer.md) | Execution balancer: candidates, filters, scoring, MU conversion, cache, reputation |
| [catalog.md](catalog.md) | Node directory and service catalog on Ergo (reputation proofs, Skill DB) |
| [ui.md](ui.md) | Wallets (full and read-only), one database for instances, home screen focused on compute |
| [chat.md](chat.md) | Chat convention for M4: HTTP with JSON, history in the service, numbered messages |
