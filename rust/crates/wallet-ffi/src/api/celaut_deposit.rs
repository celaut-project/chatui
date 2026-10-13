//! Celaut deposits in ERG from one full wallet of the app (milestone M3).
//!
//! 1. [`celaut_deposit_node`]: the ERG payment contract of the node, the balance of the
//!    client, and the limit of the node.
//! 2. [`celaut_deposit_prepare`]: `GenerateDepositToken`, then a send preparation with
//!    one output to the script of the node, the amount, and the token in R4. The app
//!    shows it in the confirmation sheet and sends it with `send_erg`, as any send.
//! 3. [`celaut_deposit_notify`]: wait until the explorer of the node shows the box
//!    unspent (the mempool is enough), then `Payable` once.
//!
//! The deposit goes to the client id of the app on the node. The client ids, the
//! deposits and the limits are in the database of the app (`celaut_db`), one for all the
//! wallets, so a restart keeps them: a deposit that was sent can be checked by the node
//! after a restart. The user chooses the paying wallet at each deposit, and only a full
//! wallet can pay (`docs/celaut/ui.md`). The database does not record which wallet paid;
//! the history of that wallet has the transaction.
//!
//! The limit of a node is 1 ERG (`docs/celaut/ui.md`, section 3). It counts every
//! deposit of the app to that node, from any wallet and for any client id, that was
//! prepared, sent or not, until the user cancels it before the send. It is in the
//! database, so a restart keeps it. The user can set a lower limit, not a higher one.
//!
//! The explorer is fixed to the default of nodo (`NODO_DEFAULT_EXPLORER`). A node does
//! not advertise an explorer, and the app does not take one from the node.

use std::collections::HashMap;
use std::future::Future;
use std::sync::Mutex;
use std::time::Duration;

use celaut_client::db::{DepositRecord, DepositStage, EventKind, EventRecord};
use celaut_client::deposit::{
    find_deposit_box, unspent_boxes_url, DepositBox, NODO_DEFAULT_EXPLORER,
};
use celaut_client::{new_client_id, CelautData};
use citadel_core::constants::MIN_BOX_VALUE_NANO;
use once_cell::sync::Lazy;

use super::celaut::{error_of, invalid, CelautError, CelautErrorKind};
use super::celaut_db::{db, now_seconds, storage_error};
use super::celaut_service::{address_of_key, forget_if_broken, key, session, NodeAddress};

/// The limit of the deposits of the app to one node: 1 ERG. It is the default and the
/// largest limit.
pub const LIMIT_NANO_ERG: u64 = 1_000_000_000;

/// How long a node keeps a deposit token pending (`DEPOSIT_TOKEN_TTL` of nodo).
pub const DEPOSIT_TOKEN_SECONDS: u32 = 3600;

/// How long one call of [`celaut_deposit_notify`] waits for the box, and how often it
/// asks the explorer.
const WAIT_LIMIT: Duration = Duration::from_secs(600);
const WAIT_INTERVAL: Duration = Duration::from_secs(5);
const EXPLORER_TIMEOUT: Duration = Duration::from_secs(20);

/// The send preparation of each prepared deposit. It is in memory only: it ends with the
/// process, as the preparations of the wallet do.
static PREPARATIONS: Lazy<Mutex<HashMap<String, u64>>> = Lazy::new(|| Mutex::new(HashMap::new()));

fn preparation_of(deposit_id: &str) -> Option<u64> {
    PREPARATIONS
        .lock()
        .ok()
        .and_then(|p| p.get(deposit_id).copied())
}

fn forget_preparation(deposit_id: &str) {
    if let Ok(mut p) = PREPARATIONS.lock() {
        p.remove(deposit_id);
    }
}

/// The limit of the node `peer_id`, in nanoERG: 1 ERG, or a lower limit of the user.
fn limit(data: &CelautData, peer_id: &str) -> u64 {
    data.nodes
        .get(peer_id)
        .and_then(|n| n.deposit_limit_nano_erg)
        .map_or(LIMIT_NANO_ERG, |l| l.min(LIMIT_NANO_ERG))
}

/// Count `record` against the limit of its node and keep it, or refuse it.
fn reserve(
    data: &mut CelautData,
    deposit_id: &str,
    record: DepositRecord,
) -> Result<(), CelautError> {
    let limit = limit(data, &record.peer_id);
    let used = data.deposited_nano_erg(&record.peer_id);
    match used.checked_add(record.nano_erg) {
        Some(total) if total <= limit => {
            data.deposits.insert(deposit_id.to_string(), record);
            Ok(())
        }
        _ => Err(CelautError {
            kind: CelautErrorKind::LimitReached,
            message: format!(
                "{} nanoERG with the {used} nanoERG of the earlier deposits is more \
                 than the limit of this node, {limit} nanoERG",
                record.nano_erg
            ),
        }),
    }
}

/// Give the amount of a deposit that was not sent back to the limit of its node.
fn release(deposit_id: &str) {
    forget_preparation(deposit_id);
    if let Err(e) = db().update(|d| {
        d.deposits.remove(deposit_id);
    }) {
        tracing::warn!("a released deposit stays in the database: {e}");
    }
}

fn unknown_deposit() -> CelautError {
    invalid("This deposit is not known. It was cancelled, or it was never sent.")
}

fn wallet_error(message: String) -> CelautError {
    CelautError {
        kind: CelautErrorKind::Wallet,
        message,
    }
}

/// The address (base58) of an ErgoTree, for the explorer.
fn address_of(script_hex: &str) -> Result<String, CelautError> {
    ergo_tx::address::ergo_tree_to_address(script_hex).map_err(|e| CelautError {
        kind: CelautErrorKind::Protocol,
        message: format!("the script of the node is not an Ergo address: {e}"),
    })
}

/// The ERG payment contract of a node, and what this app deposited there.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DepositNodeView {
    pub peer_id: String,
    /// The address that receives the deposits (from the `script` of the contract).
    pub pay_to_address: String,
    /// The MU of the node for one nanoERG.
    pub mu_per_nano_erg: String,
    /// The balance of the client of this app on the node, in MU.
    pub client_balance_mu: String,
    pub limit_nano_erg: u64,
    /// The deposits of the app to this node, from every wallet, in nanoERG.
    pub deposited_nano_erg: u64,
}

/// The ERG payment contract of the node, the balance of the client, and the limit.
#[flutter_rust_bridge::frb]
pub async fn celaut_deposit_node(node: NodeAddress) -> Result<DepositNodeView, CelautError> {
    let session = session(&node).await?;
    let erg = session.erg_payment().map_err(error_of)?;
    let pay_to_address = address_of(&hex::encode(&erg.script))?;
    let balance = match session.balance().await {
        Ok(b) => b,
        Err(e) => {
            forget_if_broken(&node, &e);
            return Err(error_of(e));
        }
    };
    let peer_id = session.peer_id().to_string();
    let (limit_nano_erg, deposited_nano_erg) =
        db().read(|d| (limit(d, &peer_id), d.deposited_nano_erg(&peer_id)));
    Ok(DepositNodeView {
        limit_nano_erg,
        deposited_nano_erg,
        peer_id,
        pay_to_address,
        mu_per_nano_erg: erg.mu_per_nano_erg.to_string(),
        client_balance_mu: balance.to_string(),
    })
}

/// Set a lower limit of the deposits to the node `peer_id`, in nanoERG. 0 stops the
/// deposits to that node. The limit cannot be more than 1 ERG. The node must be in the
/// database (check it first).
#[flutter_rust_bridge::frb]
pub fn celaut_set_deposit_limit(peer_id: String, limit_nano_erg: u64) -> Result<(), CelautError> {
    let peer_id = peer_id.trim().to_ascii_lowercase();
    if peer_id.len() != 64 || !peer_id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(invalid("The node id must be 64 hexadecimal characters."));
    }
    if limit_nano_erg > LIMIT_NANO_ERG {
        return Err(invalid("The limit of a node cannot be more than 1 ERG."));
    }
    db().update(|d| match d.nodes.get_mut(&peer_id) {
        Some(node) => {
            node.deposit_limit_nano_erg = Some(limit_nano_erg);
            Ok(())
        }
        None => Err(invalid("This node is not known. Check the node first.")),
    })
    .map_err(storage_error)?
}

/// A deposit that waits for the confirmation of the user.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DepositPreparedView {
    /// A local id for the calls below.
    pub deposit_id: String,
    /// The preparation for the confirmation sheet and `send_erg`.
    pub preparation_id: u64,
    pub peer_id: String,
    pub pay_to_address: String,
    pub amount_nano_erg: u64,
    /// The MU that the amount buys on the node.
    pub amount_mu: String,
    pub mu_per_nano_erg: String,
    pub miner_fee_nano_erg: i64,
    pub change_nano_erg: i64,
    pub input_count: u32,
    /// The id of the deposit transaction before the signature. The broadcast can have
    /// another id if a block comes before the send (see [`celaut_deposit_notify`]).
    pub tx_id: String,
    /// The id of the deposit box before the signature (empty if unknown). The same note
    /// applies.
    pub box_id: String,
    pub limit_nano_erg: u64,
    /// The deposits of the app to this node, this one included, in nanoERG.
    pub deposited_nano_erg: u64,
    /// The node refuses the payment if `Payable` comes later than this, after the token
    /// was made.
    pub token_seconds: u32,
}

/// Check the output of the deposit in the prepared transaction: the script of the node,
/// the amount, and the token in R4. Then the output is what the node looks for.
fn check_deposit_output(
    unsigned: &ergo_tx::Eip12UnsignedTx,
    script_hex: &str,
    nano_erg: u64,
    r4: &str,
) -> Result<(), String> {
    let output = unsigned
        .outputs
        .first()
        .ok_or("the transaction has no output")?;
    if !output.ergo_tree.eq_ignore_ascii_case(script_hex) {
        return Err("the first output does not go to the script of the node".into());
    }
    if output.value != nano_erg.to_string() {
        return Err(format!(
            "the first output has {} nanoERG, not {nano_erg}",
            output.value
        ));
    }
    if output.additional_registers.get("R4").map(String::as_str) != Some(r4)
        || output.additional_registers.len() != 1
    {
        return Err("the first output does not have only the deposit token in R4".into());
    }
    if !output.assets.is_empty() {
        return Err("the first output has tokens".into());
    }
    Ok(())
}

/// Prepare a deposit of `amount_nano_erg` to the node: get a deposit token, and prepare a
/// send from the wallet with one output to the script of the node and the token in R4.
/// Show it with the confirmation sheet, send it with `send_erg`, then call
/// [`celaut_deposit_notify`]. Call [`celaut_deposit_cancel`] if the user does not confirm.
#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub async fn celaut_deposit_prepare(
    handle_id: u64,
    node: NodeAddress,
    sender_address: String,
    spend_addresses: Vec<String>,
    change_address: String,
    amount_nano_erg: u64,
    node_url: Option<String>,
) -> Result<DepositPreparedView, CelautError> {
    let amount = i64::try_from(amount_nano_erg)
        .ok()
        .filter(|a| *a >= MIN_BOX_VALUE_NANO)
        .ok_or_else(|| {
            invalid(&format!(
                "The amount must be at least {MIN_BOX_VALUE_NANO} nanoERG (0.001 ERG)."
            ))
        })?;
    let session = session(&node).await?;
    let erg = session.erg_payment().map_err(error_of)?;
    let amount_mu = erg
        .mu_for(amount_nano_erg)
        .map_err(|e| error_of(e.into()))?;
    let script_hex = hex::encode(&erg.script);
    let pay_to_address = address_of(&script_hex)?;
    let peer_id = session.peer_id().to_string();
    let deposit_id = new_client_id().map_err(error_of)?;
    let record = DepositRecord {
        peer_id: peer_id.clone(),
        address: key(&node),
        deposit_token: String::new(),
        nano_erg: amount_nano_erg,
        mu: amount_mu.to_string(),
        pay_to_address: pay_to_address.clone(),
        tx_id: String::new(),
        made_at: now_seconds(),
        stage: DepositStage::Prepared,
    };
    db().update(|d| reserve(d, &deposit_id, record))
        .map_err(storage_error)??;

    // From here, an error gives the reservation back.
    let token = match session.deposit_token().await {
        Ok(t) => t,
        Err(e) => {
            release(&deposit_id);
            forget_if_broken(&node, &e);
            return Err(error_of(e));
        }
    };
    if let Err(e) = erg.payment(&token, amount_nano_erg) {
        release(&deposit_id);
        return Err(error_of(e.into()));
    }
    let r4 = ergo_tx::sigma::encode_sigma_coll_byte(token.as_bytes());
    let registers = HashMap::from([("R4".to_string(), r4.clone())]);
    let prepared = match crate::api::prepare_registered_send(
        handle_id,
        &sender_address,
        &spend_addresses,
        &change_address,
        &pay_to_address,
        amount,
        &registers,
        node_url,
    )
    .await
    {
        Ok(p) => p,
        Err(e) => {
            release(&deposit_id);
            return Err(wallet_error(e));
        }
    };
    if let Err(e) = check_deposit_output(&prepared.unsigned_tx, &script_hex, amount_nano_erg, &r4) {
        crate::api::drop_preparation(prepared.preparation_id);
        release(&deposit_id);
        return Err(CelautError {
            kind: CelautErrorKind::Protocol,
            message: format!("the prepared deposit is wrong: {e}"),
        });
    }
    let (tx_id, box_id) = match ergo_tx::chain::derive_output_boxes(&prepared.unsigned_tx) {
        Ok((tx_id, outputs)) => (
            tx_id,
            outputs
                .into_iter()
                .next()
                .map(|b| b.box_id)
                .unwrap_or_default(),
        ),
        Err(e) => {
            crate::api::drop_preparation(prepared.preparation_id);
            release(&deposit_id);
            return Err(CelautError {
                kind: CelautErrorKind::Protocol,
                message: format!("the id of the deposit transaction is not known: {e}"),
            });
        }
    };
    let stored = db().update(|d| {
        if let Some(r) = d.deposits.get_mut(&deposit_id) {
            r.deposit_token = token.clone();
            r.tx_id = tx_id.clone();
        }
        (limit(d, &peer_id), d.deposited_nano_erg(&peer_id))
    });
    let (limit_nano_erg, deposited_nano_erg) = match stored {
        Ok(v) => v,
        Err(e) => {
            // Without the token in the database, a restart could not finish the deposit.
            crate::api::drop_preparation(prepared.preparation_id);
            release(&deposit_id);
            return Err(storage_error(e));
        }
    };
    if let Ok(mut p) = PREPARATIONS.lock() {
        p.insert(deposit_id.clone(), prepared.preparation_id);
    }
    Ok(DepositPreparedView {
        deposit_id,
        preparation_id: prepared.preparation_id,
        peer_id,
        pay_to_address,
        amount_nano_erg,
        amount_mu: amount_mu.to_string(),
        mu_per_nano_erg: erg.mu_per_nano_erg.to_string(),
        miner_fee_nano_erg: prepared.miner_fee,
        change_nano_erg: prepared.change_erg,
        input_count: u32::try_from(prepared.input_count).unwrap_or(u32::MAX),
        tx_id,
        box_id,
        limit_nano_erg,
        deposited_nano_erg,
        token_seconds: DEPOSIT_TOKEN_SECONDS,
    })
}

/// Forget a deposit that the user did not confirm, or whose send did not use the
/// preparation, and give its amount back to the limit of the node. A deposit that was
/// sent cannot be cancelled.
#[flutter_rust_bridge::frb]
pub fn celaut_deposit_cancel(deposit_id: String) -> Result<(), CelautError> {
    let stage = db()
        .read(|d| d.deposits.get(&deposit_id).map(|r| r.stage.clone()))
        .ok_or_else(unknown_deposit)?;
    let preparation = preparation_of(&deposit_id);
    let waits = preparation.is_some_and(crate::api::preparation_waits);
    let before_payable = matches!(stage, DepositStage::Prepared | DepositStage::Sent { .. });
    if !before_payable || !waits {
        return Err(invalid(
            "This deposit was sent. Wait for it with the explorer, then the node checks it.",
        ));
    }
    if let Some(id) = preparation {
        crate::api::drop_preparation(id);
    }
    forget_preparation(&deposit_id);
    db().update(|d| {
        d.deposits.remove(&deposit_id);
    })
    .map_err(storage_error)
}

/// Call this just before `send_erg` of the deposit. The deposit is then "sent" in the
/// database, with the transaction id that was known before the signature, so that a
/// stop of the app during the send does not lose it: after a restart the deposit is in
/// [`celaut_sent_deposits`]. [`celaut_deposit_notify`] replaces that id with the id of
/// the broadcast. If the send fails without the use of the preparation,
/// [`celaut_deposit_cancel`] still works.
#[flutter_rust_bridge::frb]
pub fn celaut_deposit_sending(deposit_id: String) -> Result<String, CelautError> {
    if !preparation_of(&deposit_id).is_some_and(crate::api::preparation_waits) {
        return Err(unknown_deposit());
    }
    db().update(|d| match d.deposits.get_mut(&deposit_id) {
        Some(r) if r.stage == DepositStage::Prepared => {
            r.stage = DepositStage::Sent {
                tx_id: r.tx_id.clone(),
            };
            Ok(r.tx_id.clone())
        }
        Some(r) => match &r.stage {
            DepositStage::Sent { tx_id } => Ok(tx_id.clone()),
            _ => Err(invalid("The node already checked this deposit.")),
        },
        None => Err(unknown_deposit()),
    })
    .map_err(storage_error)?
}

/// A deposit that was sent and that the node did not check yet.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DepositSentView {
    pub deposit_id: String,
    pub peer_id: String,
    /// The address (`host:port`) of the node.
    pub address: String,
    pub tx_id: String,
    pub amount_nano_erg: u64,
    pub amount_mu: String,
    /// The time of the preparation, in Unix seconds.
    pub made_at: i64,
    /// True if the deposit token expired: the node refuses this deposit now.
    pub expired: bool,
}

/// The deposits that were sent and that the node did not check yet, also from an
/// earlier run of the app. Finish each with [`celaut_deposit_notify`].
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_sent_deposits() -> Vec<DepositSentView> {
    db().read(|d| {
        d.deposits
            .iter()
            .filter_map(|(id, r)| match &r.stage {
                DepositStage::Sent { tx_id } => Some(DepositSentView {
                    deposit_id: id.clone(),
                    peer_id: r.peer_id.clone(),
                    address: r.address.clone(),
                    tx_id: tx_id.clone(),
                    amount_nano_erg: r.nano_erg,
                    amount_mu: r.mu.clone(),
                    made_at: r.made_at,
                    expired: now_seconds().saturating_sub(r.made_at)
                        > i64::from(DEPOSIT_TOKEN_SECONDS),
                }),
                _ => None,
            })
            .collect()
    })
}

/// The end of a deposit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DepositDoneView {
    pub deposit_id: String,
    pub tx_id: String,
    /// The box of the deposit on the explorer.
    pub box_id: String,
    /// True if the node accepted the payment.
    pub accepted: bool,
    /// The answer of the node if it refused the payment.
    pub node_message: Option<String>,
    /// The balance of the client on the node after `Payable`, in MU (empty if unknown).
    pub client_balance_mu: String,
}

/// Ask `fetch` for the boxes until one has `token` in R4, for at most `limit`.
async fn wait_for_box<F, Fut>(
    fetch: F,
    token: &str,
    interval: Duration,
    limit: Duration,
) -> Option<DepositBox>
where
    F: Fn() -> Fut,
    Fut: Future<Output = Result<serde_json::Value, String>>,
{
    let start = tokio::time::Instant::now();
    loop {
        if let Ok(boxes) = fetch().await {
            if let Some(found) = find_deposit_box(&boxes, token) {
                return Some(found);
            }
        }
        if start.elapsed() + interval > limit {
            return None;
        }
        tokio::time::sleep(interval).await;
    }
}

async fn fetch_boxes(url: &str) -> Result<serde_json::Value, String> {
    let client = wallet_net::http::client_builder()
        .timeout(EXPLORER_TIMEOUT)
        .build()
        .map_err(|e| e.to_string())?;
    let response = client.get(url).send().await.map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    response
        .json::<serde_json::Value>()
        .await
        .map_err(|e| e.to_string())
}

/// Keep `tx_id` as the transaction of a sent deposit. The id from before the signature
/// can be different: the signer sets the creation height of the outputs to the height
/// of the chain, so a new block between the preparation and the send changes the id.
/// The deposit token finds the box, not the id.
fn keep_broadcast_tx_id(deposit_id: &str, tx_id: &str) -> Result<(), CelautError> {
    db().update(|d| {
        if let Some(r) = d.deposits.get_mut(deposit_id) {
            if matches!(r.stage, DepositStage::Sent { .. }) {
                r.stage = DepositStage::Sent {
                    tx_id: tx_id.to_string(),
                };
            }
        }
    })
    .map_err(storage_error)
}

/// After `send_erg` gave `tx_id`: wait until the explorer shows the deposit box unspent
/// (the mempool is enough), then call `Payable` once. If the node accepts the payment,
/// the MU of the deposit go to the paid credit of the node in the database.
///
/// The explorer is the default of nodo (`https://api.ergoplatform.com`), as on the node:
/// it is fixed, and the node does not advertise one. If the box does not come in 10
/// minutes, the answer is a `Timeout` and nothing was sent to the node: call this again
/// later, before the deposit token expires.
#[flutter_rust_bridge::frb]
pub async fn celaut_deposit_notify(
    deposit_id: String,
    tx_id: String,
) -> Result<DepositDoneView, CelautError> {
    let tx_id = tx_id.trim().to_ascii_lowercase();
    if tx_id.len() != 64 || !tx_id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(invalid(
            "The transaction id must be 64 hexadecimal characters.",
        ));
    }
    let record = db()
        .read(|d| d.deposits.get(&deposit_id).cloned())
        .ok_or_else(unknown_deposit)?;
    match &record.stage {
        DepositStage::Prepared => {
            if preparation_of(&deposit_id).is_none_or(crate::api::preparation_waits) {
                return Err(invalid("This deposit was not sent yet."));
            }
            let sent = DepositStage::Sent {
                tx_id: tx_id.clone(),
            };
            db().update(|d| {
                if let Some(r) = d.deposits.get_mut(&deposit_id) {
                    r.stage = sent;
                }
            })
            .map_err(storage_error)?;
            forget_preparation(&deposit_id);
        }
        DepositStage::Sent { .. } => keep_broadcast_tx_id(&deposit_id, &tx_id)?,
        DepositStage::PayableCalled { .. } => {
            return Err(invalid("The node already checked this deposit."));
        }
    }
    let token = record.deposit_token.clone();
    let nano_erg = record.nano_erg;

    let url = unspent_boxes_url(NODO_DEFAULT_EXPLORER, &record.pay_to_address);
    let Some(found) = wait_for_box(|| fetch_boxes(&url), &token, WAIT_INTERVAL, WAIT_LIMIT).await
    else {
        return Err(CelautError {
            kind: CelautErrorKind::Timeout,
            message: format!(
                "the explorer does not show the deposit box yet. Nothing was sent to the \
                 node. Wait again before the deposit token expires ({DEPOSIT_TOKEN_SECONDS} s \
                 after it was made)."
            ),
        });
    };
    if found.value < nano_erg {
        return Err(CelautError {
            kind: CelautErrorKind::Protocol,
            message: format!(
                "the box with the deposit token has {} nanoERG, not {nano_erg}. Nothing was \
                 sent to the node.",
                found.value
            ),
        });
    }

    let node = address_of_key(&record.address).ok_or_else(|| CelautError {
        kind: CelautErrorKind::Storage,
        message: format!("the address of the node is not valid: {}", record.address),
    })?;
    let session = session(&node).await?;
    if session.peer_id() != record.peer_id {
        return Err(CelautError {
            kind: CelautErrorKind::IdentityMismatch,
            message: format!(
                "the node at {} is now {}, not the node of the deposit {}. Nothing was sent \
                 to the node.",
                record.address,
                session.peer_id(),
                record.peer_id
            ),
        });
    }
    let payment = session
        .erg_payment()
        .and_then(|erg| Ok(erg.payment(&token, nano_erg)?))
        .map_err(error_of)?;

    // One attempt only: the stage changes in the database before the call.
    let once = db()
        .update(|d| match d.deposits.get_mut(&deposit_id) {
            Some(r) if matches!(r.stage, DepositStage::Sent { .. }) => {
                r.stage = DepositStage::PayableCalled {
                    tx_id: tx_id.clone(),
                    accepted: false,
                };
                Ok(())
            }
            Some(_) => Err(invalid("The node already checked this deposit.")),
            None => Err(unknown_deposit()),
        })
        .map_err(storage_error)?;
    once?;
    let (accepted, node_message) = match session.payable(&payment).await {
        Ok(()) => (true, None),
        Err(e) => {
            forget_if_broken(&node, &e);
            (false, Some(e.to_string()))
        }
    };
    let logged = db().update(|d| {
        if let Some(r) = d.deposits.get_mut(&deposit_id) {
            r.stage = DepositStage::PayableCalled {
                tx_id: tx_id.clone(),
                accepted,
            };
        }
        if accepted {
            if let (Some(node), Ok(mu)) = (d.nodes.get_mut(&record.peer_id), record.mu.parse()) {
                node.add_paid(mu);
            }
        }
        d.add_event(EventRecord {
            peer_id: record.peer_id.clone(),
            kind: if accepted {
                EventKind::PaymentCommunicated
            } else {
                EventKind::PaymentNotAcknowledged
            },
            at: now_seconds(),
        });
    });
    if let Err(e) = logged {
        tracing::warn!("the answer of the node to the deposit is not stored: {e}");
    }
    let client_balance_mu = session
        .balance()
        .await
        .map(|b| b.to_string())
        .unwrap_or_default();
    Ok(DepositDoneView {
        deposit_id,
        tx_id,
        box_id: found.box_id,
        accepted,
        node_message,
        client_balance_mu,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    const PEER: &str = "aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11";

    fn record(peer_id: &str, nano_erg: u64) -> DepositRecord {
        DepositRecord {
            peer_id: peer_id.into(),
            address: "node:1".into(),
            deposit_token: String::new(),
            nano_erg,
            mu: nano_erg.to_string(),
            pay_to_address: "9f".into(),
            tx_id: "ab".repeat(32),
            made_at: 0,
            stage: DepositStage::Prepared,
        }
    }

    #[test]
    fn the_limit_counts_every_prepared_deposit() {
        let mut d = CelautData::default();
        assert_eq!(limit(&d, PEER), 1_000_000_000);
        reserve(&mut d, "a", record(PEER, 600_000_000)).unwrap();
        reserve(&mut d, "b", record(PEER, 400_000_000)).unwrap();
        let err = reserve(&mut d, "c", record(PEER, 1)).unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::LimitReached);
        assert_eq!(d.deposited_nano_erg(PEER), 1_000_000_000);
        d.deposits.remove("b");
        reserve(&mut d, "b", record(PEER, 400_000_000)).unwrap();
        d.nodes.insert(
            PEER.into(),
            celaut_client::db::NodeRecord {
                client_id: "c".into(),
                deposit_limit_nano_erg: Some(0),
                ..Default::default()
            },
        );
        assert_eq!(
            reserve(&mut d, "d", record(PEER, 1)).unwrap_err().kind,
            CelautErrorKind::LimitReached
        );
        assert_eq!(
            reserve(&mut d, "e", record(PEER, u64::MAX))
                .unwrap_err()
                .kind,
            CelautErrorKind::LimitReached
        );
        // Another node has its own limit.
        reserve(&mut d, "f", record(&"bb".repeat(32), 1_000_000)).unwrap();
        assert_eq!(d.deposited_nano_erg("cc"), 0);
    }

    #[test]
    fn the_limit_needs_a_known_node() {
        assert!(celaut_set_deposit_limit("ab".into(), 1).is_err());
        assert!(celaut_set_deposit_limit("zz".repeat(32), 1).is_err());
        let peer = "cd".repeat(32);
        let err = celaut_set_deposit_limit(peer.clone(), 7).unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        db().update(|d| {
            d.nodes.insert(
                peer.clone(),
                celaut_client::db::NodeRecord {
                    client_id: "c".into(),
                    ..Default::default()
                },
            );
        })
        .unwrap();
        celaut_set_deposit_limit(peer.to_uppercase(), 7).unwrap();
        assert_eq!(db().read(|d| limit(d, &peer)), 7);
        // Not more than 1 ERG.
        let err = celaut_set_deposit_limit(peer.clone(), LIMIT_NANO_ERG + 1).unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        celaut_set_deposit_limit(peer.clone(), LIMIT_NANO_ERG).unwrap();
        assert_eq!(db().read(|d| limit(d, &peer)), LIMIT_NANO_ERG);
        // A higher limit in a database of an earlier version counts as 1 ERG.
        db().update(|d| d.nodes.get_mut(&peer).unwrap().deposit_limit_nano_erg = Some(u64::MAX))
            .unwrap();
        assert_eq!(db().read(|d| limit(d, &peer)), LIMIT_NANO_ERG);
    }

    #[test]
    fn the_limit_counts_the_deposits_of_every_wallet_after_a_restart() {
        let dir = std::env::temp_dir().join(format!(
            "celaut-limit-{}",
            &super::super::celaut_db::celaut_new_database_key().unwrap()[..16]
        ));
        let path = dir.join("celaut.db");
        let key = [9u8; 32];
        {
            let db = celaut_client::CelautDb::open(&path, &key).unwrap();
            // Wallet A pays 0.7 ERG, then wallet B pays 0.2 ERG. The database records no
            // wallet: both count for the node. One deposit was refused by the node, one
            // was for a client id that the node forgot: they count too.
            db.update(|d| {
                let mut a = record(PEER, 700_000_000);
                a.stage = DepositStage::PayableCalled {
                    tx_id: "a".into(),
                    accepted: true,
                };
                let mut b = record(PEER, 200_000_000);
                b.stage = DepositStage::Sent { tx_id: "b".into() };
                let mut refused = record(PEER, 50_000_000);
                refused.stage = DepositStage::PayableCalled {
                    tx_id: "c".into(),
                    accepted: false,
                };
                reserve(d, "wallet-a", a).unwrap();
                reserve(d, "wallet-b", b).unwrap();
                reserve(d, "refused", refused).unwrap();
            })
            .unwrap();
        }
        // The restart: a new open of the same file.
        let db = celaut_client::CelautDb::open(&path, &key).unwrap();
        db.update(|d| {
            assert_eq!(d.deposited_nano_erg(PEER), 950_000_000);
            assert_eq!(
                reserve(d, "more", record(PEER, 60_000_000))
                    .unwrap_err()
                    .kind,
                CelautErrorKind::LimitReached
            );
            reserve(d, "last", record(PEER, 50_000_000)).unwrap();
        })
        .unwrap();
    }

    #[test]
    fn a_sent_deposit_is_listed_and_a_prepared_one_is_not() {
        let peer = "ce".repeat(32);
        let mut sent = record(&peer, 2_000_000);
        sent.stage = DepositStage::Sent {
            tx_id: "ab".repeat(32),
        };
        db().update(|d| {
            d.deposits.insert("sent-1".into(), sent);
            d.deposits
                .insert("prepared-1".into(), record(&peer, 1_000_000));
        })
        .unwrap();
        let listed: Vec<_> = celaut_sent_deposits()
            .into_iter()
            .filter(|v| v.peer_id == peer)
            .collect();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].deposit_id, "sent-1");
        assert_eq!(listed[0].tx_id, "ab".repeat(32));
        // A prepared deposit without its preparation (an earlier run) cannot cancel or
        // be notified: it was never sent.
        assert!(celaut_deposit_cancel("prepared-1".into()).is_err());
    }

    #[test]
    fn the_id_of_the_broadcast_replaces_the_id_before_the_signature() {
        let peer = "cf".repeat(32);
        let mut sent = record(&peer, 2_000_000);
        sent.stage = DepositStage::Sent {
            tx_id: "ab".repeat(32),
        };
        db().update(|d| {
            d.deposits.insert("sent-2".into(), sent);
            d.deposits
                .insert("prepared-2".into(), record(&peer, 1_000_000));
        })
        .unwrap();
        keep_broadcast_tx_id("sent-2", &"cd".repeat(32)).unwrap();
        keep_broadcast_tx_id("prepared-2", &"cd".repeat(32)).unwrap();
        db().read(|d| {
            assert_eq!(
                d.deposits["sent-2"].stage,
                DepositStage::Sent {
                    tx_id: "cd".repeat(32)
                }
            );
            assert_eq!(d.deposits["prepared-2"].stage, DepositStage::Prepared);
        });
    }

    #[tokio::test]
    async fn bad_input_is_refused_before_any_connection() {
        let node = NodeAddress {
            host: "127.0.0.1".into(),
            port: 1,
        };
        for amount in [0, 999_999, u64::MAX] {
            let err = celaut_deposit_prepare(
                1,
                node.clone(),
                "9f".into(),
                vec![],
                "9f".into(),
                amount,
                None,
            )
            .await
            .unwrap_err();
            assert_eq!(err.kind, CelautErrorKind::InvalidInput, "{amount}");
        }
        let err = celaut_deposit_notify("nope".into(), "ab".repeat(32))
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        let err = celaut_deposit_notify("nope".into(), "tx".into())
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        assert_eq!(
            celaut_deposit_cancel("nope".into()).unwrap_err().kind,
            CelautErrorKind::InvalidInput
        );
    }

    fn deposit_box(token: &str, value: u64) -> serde_json::Value {
        serde_json::json!([{
            "boxId": "b0",
            "value": value,
            "additionalRegisters": {"R4": {"renderedValue": hex::encode(token)}},
        }])
    }

    #[tokio::test]
    async fn the_wait_asks_the_explorer_until_the_box_comes() {
        let calls = AtomicUsize::new(0);
        let found = wait_for_box(
            || {
                let n = calls.fetch_add(1, Ordering::SeqCst);
                async move {
                    match n {
                        0 => Err("HTTP 503".to_string()),
                        1 => Ok(serde_json::json!([])),
                        _ => Ok(deposit_box("tok", 10_000_000)),
                    }
                }
            },
            "tok",
            Duration::from_millis(1),
            Duration::from_secs(5),
        )
        .await;
        assert_eq!(
            found,
            Some(DepositBox {
                box_id: "b0".into(),
                value: 10_000_000
            })
        );
        assert_eq!(calls.load(Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn the_wait_ends_at_the_limit() {
        let calls = AtomicUsize::new(0);
        let found = wait_for_box(
            || {
                calls.fetch_add(1, Ordering::SeqCst);
                async { Ok(deposit_box("other", 10_000_000)) }
            },
            "tok",
            Duration::from_millis(5),
            Duration::from_millis(30),
        )
        .await;
        assert_eq!(found, None);
        assert!(calls.load(Ordering::SeqCst) >= 2);
    }

    /// Two P2PK trees: the node and the wallet.
    fn trees() -> (String, String) {
        use ergo_lib::ergotree_ir::serialization::SigmaSerializable;
        use ergo_lib::wallet::secret_key::SecretKey;
        let tree = || {
            let address = SecretKey::random_dlog().get_address_from_public_image();
            hex::encode(address.script().unwrap().sigma_serialize_bytes().unwrap())
        };
        (tree(), tree())
    }

    fn input(tree: &str, value: u64) -> ergo_tx::Eip12InputBox {
        ergo_tx::Eip12InputBox {
            box_id: "11".repeat(32),
            transaction_id: "22".repeat(32),
            index: 0,
            value: value.to_string(),
            ergo_tree: tree.to_string(),
            assets: vec![],
            creation_height: 1_000_000,
            additional_registers: HashMap::new(),
            extension: HashMap::new(),
        }
    }

    #[test]
    fn the_deposit_transaction_has_the_token_in_r4_of_the_node_output() {
        use ergo_lib::ergotree_ir::chain::ergo_box::NonMandatoryRegisterId;
        use ergo_lib::ergotree_ir::mir::constant::TryExtractInto;

        let token = "1b4e28ba-2fa1-41d2-883f-0016d3cca427";
        let (node, wallet) = trees();
        let r4 = ergo_tx::sigma::encode_sigma_coll_byte(token.as_bytes());
        assert_eq!(r4, format!("0e24{}", hex::encode(token)));
        let registers = HashMap::from([("R4".to_string(), r4.clone())]);
        let built = ergo_tx::build_send_tx_with_registers(
            &[input(&wallet, 100_000_000)],
            &node,
            &wallet,
            10_000_000,
            None,
            &registers,
            1_600_000,
        )
        .unwrap();
        check_deposit_output(&built.unsigned_tx, &node, 10_000_000, &r4).unwrap();
        assert!(check_deposit_output(&built.unsigned_tx, &wallet, 10_000_000, &r4).is_err());
        assert!(check_deposit_output(&built.unsigned_tx, &node, 10_000_001, &r4).is_err());
        assert!(check_deposit_output(&built.unsigned_tx, &node, 10_000_000, "0e00").is_err());

        // ergo-lib reads the register back as the UTF-8 bytes of the token.
        let unsigned = ergo_tx::chain::to_unsigned_transaction(&built.unsigned_tx).unwrap();
        let outputs: Vec<_> = unsigned.output_candidates.iter().collect();
        assert_eq!(outputs.len(), 3); // node, change, fee
        let value = outputs[0]
            .additional_registers
            .get_constant(NonMandatoryRegisterId::R4)
            .unwrap()
            .unwrap();
        let bytes: Vec<u8> = value.v.try_extract_into::<Vec<u8>>().unwrap();
        assert_eq!(bytes, token.as_bytes());
        assert_eq!(outputs[0].value.as_u64(), &10_000_000);
        assert!(outputs[1].additional_registers.is_empty());
        assert_eq!(
            built.summary.change_erg,
            100_000_000 - 10_000_000 - citadel_core::constants::TX_FEE_NANO
        );
        // The deposit box before the signature has the token in R4.
        let (_, boxes) = ergo_tx::chain::derive_output_boxes(&built.unsigned_tx).unwrap();
        assert_eq!(boxes[0].additional_registers["R4"], r4);
    }
}

#[cfg(test)]
#[path = "celaut_deposit_e2e.rs"]
mod e2e;
