//! End-to-end checks of the deposit against a real node (milestone M3). Both tests are
//! `#[ignore]`d and need environment variables. Steps and costs: `docs/celaut/deposit-e2e.md`.
//!
//! Reach the Gateway through a local port, for example an SSH port-forward:
//!
//! ```text
//! ssh -f -N -L 18460:127.0.0.1:53460 node-host
//! ```
//!
//! `node_read_only`: no transaction. `GenerateClient` (a new client with free credit),
//! `GetPeerInfo`, `GetMetrics` and one `GenerateDepositToken`. The node only writes the
//! token in its database; it expires after one hour.
//!
//! ```text
//! CELAUT_NODE_PORT=18460 cargo test -p wallet-ffi --lib node_read_only -- --ignored --nocapture
//! ```
//!
//! `deposit_end_to_end`: one deposit from the wallet of `CELAUT_E2E_MNEMONIC_FILE`.
//! Without `CELAUT_E2E_SEND=yes` it stops before the signature (dry run): it makes the
//! deposit token and the unsigned transaction, prints them, and cancels. With
//! `CELAUT_E2E_SEND=yes` it signs and sends a real mainnet transaction of
//! `CELAUT_E2E_NANO_ERG` nanoERG plus the fee. Do that only with an amount that a
//! maintainer approved.
//!
//! ```text
//! CELAUT_NODE_PORT=18460 CELAUT_E2E_MNEMONIC_FILE=/path/to/words.txt \
//!   CELAUT_E2E_NANO_ERG=10000000 [CELAUT_E2E_SEND=yes] \
//!   cargo test -p wallet-ffi --lib deposit_end_to_end -- --ignored --nocapture
//! ```
//!
//! Optional: `CELAUT_NODE_HOST` (default `127.0.0.1`), `CELAUT_E2E_ERGO_NODE` (the Ergo
//! node of the wallet; default: the list of the app), `CELAUT_E2E_EXPLORER` (default:
//! the explorer of nodo).

use super::*;

/// The most that the test sends, whatever the environment says: the default limit of a
/// node.
const E2E_CAP_NANO_ERG: u64 = DEFAULT_LIMIT_NANO_ERG;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

fn node() -> NodeAddress {
    let port = env("CELAUT_NODE_PORT")
        .expect("set CELAUT_NODE_PORT to the local port of the Gateway")
        .parse()
        .expect("CELAUT_NODE_PORT is a port");
    NodeAddress {
        host: env("CELAUT_NODE_HOST").unwrap_or_else(|| "127.0.0.1".into()),
        port,
    }
}

#[tokio::test]
#[ignore = "needs a running node; see the top of the file"]
async fn node_read_only() {
    let node = node();
    let info = celaut_deposit_node(node.clone())
        .await
        .expect("deposit node");
    println!("peer_id            {}", info.peer_id);
    println!("pay to             {}", info.pay_to_address);
    println!("MU per nanoERG     {}", info.mu_per_nano_erg);
    println!("client balance     {} MU", info.client_balance_mu);
    println!("limit              {} nanoERG", info.limit_nano_erg);

    let session = session(&node).await.expect("session");
    let erg = session.erg_payment().expect("ERG contract");
    println!("script             {}", hex::encode(&erg.script));
    let ledger = erg.contract.ledger.clone().unwrap_or_default();
    println!("ledger tags        {:?}", ledger.tags);
    println!("ledger formal\n{}", String::from_utf8_lossy(&ledger.formal));
    for kv in &erg.contract.xattrs {
        let value = kv.value.clone().unwrap_or_default();
        println!(
            "xattr {:<12} {}",
            kv.key,
            String::from_utf8(value.clone()).unwrap_or_else(|_| hex::encode(value))
        );
    }
    let token = session.deposit_token().await.expect("deposit token");
    println!("deposit token      {token} ({} bytes)", token.len());
    assert_eq!(token.len(), 36, "nodo gives the text of a UUID4");
    println!(
        "R4                 {}",
        ergo_tx::sigma::encode_sigma_coll_byte(token.as_bytes())
    );
}

#[tokio::test]
#[ignore = "needs a running node and a funded wallet; see the top of the file"]
async fn deposit_end_to_end() {
    let node = node();
    let nano_erg: u64 = env("CELAUT_E2E_NANO_ERG")
        .expect("set CELAUT_E2E_NANO_ERG to the approved amount")
        .parse()
        .expect("CELAUT_E2E_NANO_ERG is a whole number");
    assert!(
        nano_erg <= E2E_CAP_NANO_ERG,
        "the test sends at most {E2E_CAP_NANO_ERG} nanoERG"
    );
    let send = env("CELAUT_E2E_SEND").as_deref() == Some("yes");
    let words = std::fs::read_to_string(
        env("CELAUT_E2E_MNEMONIC_FILE").expect("set CELAUT_E2E_MNEMONIC_FILE"),
    )
    .expect("read the mnemonic file");
    let opened: serde_json::Value = serde_json::from_str(
        &crate::api::wallet_create(words.trim().to_string(), String::new()).expect("wallet"),
    )
    .expect("wallet JSON");
    let handle = opened["handle_id"].as_u64().expect("handle_id");
    let address = crate::api::derive_address(handle, 0).expect("address 0");
    println!("wallet address     {address}");

    let before = celaut_deposit_node(node.clone())
        .await
        .expect("deposit node");
    println!("node               {}", before.peer_id);
    println!("pay to             {}", before.pay_to_address);
    println!("balance before     {} MU", before.client_balance_mu);

    let prepared = celaut_deposit_prepare(
        handle,
        node.clone(),
        address.clone(),
        vec![address.clone()],
        address,
        nano_erg,
        env("CELAUT_E2E_ERGO_NODE"),
    )
    .await
    .expect("prepare");
    println!(
        "amount             {} nanoERG = {} MU",
        prepared.amount_nano_erg, prepared.amount_mu
    );
    println!("miner fee          {} nanoERG", prepared.miner_fee_nano_erg);
    println!("change             {} nanoERG", prepared.change_nano_erg);
    println!("deposit box id     {}", prepared.box_id);
    let details =
        crate::api::preparation_details(handle, prepared.preparation_id).expect("details");
    println!("unsigned tx        {details}");

    if !send {
        celaut_deposit_cancel(prepared.deposit_id).expect("cancel");
        println!("dry run: cancelled before the signature, nothing sent");
        return;
    }

    let sent: serde_json::Value = serde_json::from_str(
        &crate::api::send_erg(handle, prepared.preparation_id)
            .await
            .expect("send"),
    )
    .expect("send JSON");
    let tx_id = sent["tx_id"].as_str().expect("tx_id").to_string();
    println!("tx id              {tx_id}");

    let done = celaut_deposit_notify(prepared.deposit_id, tx_id, env("CELAUT_E2E_EXPLORER"))
        .await
        .expect("notify");
    println!("box                {}", done.box_id);
    println!(
        "accepted           {} {:?}",
        done.accepted, done.node_message
    );
    println!("balance after      {} MU", done.client_balance_mu);
    assert!(
        done.accepted,
        "the node refused the payment: {:?}",
        done.node_message
    );
    let before: u128 = before.client_balance_mu.parse().expect("balance before");
    let after: u128 = done.client_balance_mu.parse().expect("balance after");
    let bought: u128 = prepared.amount_mu.parse().expect("MU");
    assert_eq!(
        after,
        before + bought,
        "the balance grows by the MU of the deposit"
    );
}
