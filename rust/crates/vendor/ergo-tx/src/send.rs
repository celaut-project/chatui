//! Simple wallet send (ERG and/or token) transaction builder.
//!
//! Builds an EIP-12 unsigned tx for Nautilus/ErgoPay signing. Does not manage keys.

use std::collections::HashMap;

use crate::eip12::{Eip12Asset, Eip12InputBox, Eip12Output, Eip12UnsignedTx};

use citadel_core::constants::{MIN_BOX_VALUE_NANO as MIN_BOX_VALUE, TX_FEE_NANO as TX_FEE};

#[derive(Debug, thiserror::Error)]
pub enum SendError {
    #[error("No inputs provided")]
    NoInputs,

    #[error("Must send ERG and/or a token")]
    EmptySend,

    #[error("Send ERG amount must be at least {min} nanoERG (min box value)")]
    BelowMinBoxValue { min: i64 },

    #[error("Token amount must be greater than zero")]
    ZeroTokenAmount,

    #[error("Insufficient ERG: have {have} nanoERG, need {need} nanoERG")]
    InsufficientErg { have: i64, need: i64 },

    #[error("Insufficient tokens: have {have} of {token_id}, need {need}")]
    InsufficientTokens {
        token_id: String,
        have: u64,
        need: u64,
    },

    #[error("Token change requires at least {min} nanoERG leftover, have {have}. Add ERG to fund the change box and preserve unsent tokens.")]
    TokenChangeInsufficientErg { have: i64, min: i64 },

    #[error("Change amount {change} nanoERG is below minimum box value of {min} nanoERG")]
    ChangeBelowMin { change: i64, min: i64 },

    #[error("Input ERG total exceeds the representable range")]
    ErgTotalOverflow,

    #[error("Total held amount of token {token_id} exceeds the representable range")]
    TokenTotalOverflow { token_id: String },

    #[error("{0}")]
    ChangeBox(String),

    #[error("Bad recipient registers: {0}")]
    BadRegisters(String),
}

#[derive(Debug)]
pub struct SendSummary {
    pub recipient_erg: i64,
    pub token_id: Option<String>,
    pub token_amount: Option<u64>,
    pub change_erg: i64,
    pub miner_fee: i64,
    pub input_count: usize,
}

#[derive(Debug)]
pub struct SendBuildResult {
    pub unsigned_tx: Eip12UnsignedTx,
    pub summary: SendSummary,
}

/// Build an EIP-12 unsigned send tx from already-selected inputs.
///
/// - `send_erg` is the ERG attached to the recipient output (must be >= MIN_BOX_VALUE).
/// - Optional token is placed on the recipient output.
/// - Leftover ERG/tokens go to `change_ergo_tree` (wallet primary address).
pub fn build_send_tx(
    user_inputs: &[Eip12InputBox],
    recipient_ergo_tree: &str,
    change_ergo_tree: &str,
    send_erg: i64,
    send_token: Option<(&str, u64)>,
    current_height: i32,
) -> Result<SendBuildResult, SendError> {
    build_send_tx_with_registers(
        user_inputs,
        recipient_ergo_tree,
        change_ergo_tree,
        send_erg,
        send_token,
        &HashMap::new(),
        current_height,
    )
}

/// The register names that an output can have, in order. Ergo needs them without a
/// gap from R4: R5 only with R4, R6 only with R5, and so on.
const REGISTER_NAMES: [&str; 6] = ["R4", "R5", "R6", "R7", "R8", "R9"];

/// Check the registers of an output: names from R4 without a gap, and each value the
/// hex of a serialized Sigma constant (not empty, an even number of hex digits).
fn check_registers(registers: &HashMap<String, String>) -> Result<(), SendError> {
    if registers.len() > REGISTER_NAMES.len() {
        return Err(SendError::BadRegisters(format!(
            "{} registers, at most {}",
            registers.len(),
            REGISTER_NAMES.len()
        )));
    }
    for name in registers.keys() {
        if !REGISTER_NAMES.contains(&name.as_str()) {
            return Err(SendError::BadRegisters(format!(
                "{name} is not a register from R4 to R9"
            )));
        }
    }
    for name in &REGISTER_NAMES[..registers.len()] {
        let Some(value) = registers.get(*name) else {
            return Err(SendError::BadRegisters(format!(
                "{name} is missing: registers start at R4 and have no gap"
            )));
        };
        let bytes = hex::decode(value)
            .map_err(|_| SendError::BadRegisters(format!("{name} is not hexadecimal")))?;
        if bytes.is_empty() {
            return Err(SendError::BadRegisters(format!("{name} is empty")));
        }
    }
    Ok(())
}

/// [`build_send_tx`] with registers on the recipient output.
///
/// `recipient_registers` maps register names ("R4" to "R9") to the hex of a serialized
/// Sigma constant (for example [`crate::sigma::encode_sigma_coll_byte`]). Only the
/// recipient output gets them; the change outputs get none.
pub fn build_send_tx_with_registers(
    user_inputs: &[Eip12InputBox],
    recipient_ergo_tree: &str,
    change_ergo_tree: &str,
    send_erg: i64,
    send_token: Option<(&str, u64)>,
    recipient_registers: &HashMap<String, String>,
    current_height: i32,
) -> Result<SendBuildResult, SendError> {
    check_registers(recipient_registers)?;
    if user_inputs.is_empty() {
        return Err(SendError::NoInputs);
    }

    let sending_token = send_token.is_some();
    if send_erg <= 0 && !sending_token {
        return Err(SendError::EmptySend);
    }
    if send_erg < MIN_BOX_VALUE {
        return Err(SendError::BelowMinBoxValue { min: MIN_BOX_VALUE });
    }
    if let Some((_, amt)) = send_token {
        if amt == 0 {
            return Err(SendError::ZeroTokenAmount);
        }
    }

    let total_erg: i64 = user_inputs
        .iter()
        .map(|b| b.value.parse::<i64>().unwrap_or(0))
        .try_fold(0i64, i64::checked_add)
        .ok_or(SendError::ErgTotalOverflow)?;

    let mut token_totals: HashMap<String, u64> = HashMap::new();
    for input in user_inputs {
        for asset in &input.assets {
            let amount = asset.amount.parse::<u64>().unwrap_or(0);
            let entry = token_totals.entry(asset.token_id.clone()).or_insert(0);
            *entry = entry
                .checked_add(amount)
                .ok_or_else(|| SendError::TokenTotalOverflow {
                    token_id: asset.token_id.clone(),
                })?;
        }
    }

    if let Some((token_id, amount)) = send_token {
        let have = token_totals.get(token_id).copied().unwrap_or(0);
        if have < amount {
            return Err(SendError::InsufficientTokens {
                token_id: token_id.to_string(),
                have,
                need: amount,
            });
        }
    }

    let min_needed = send_erg + TX_FEE;
    if total_erg < min_needed {
        return Err(SendError::InsufficientErg {
            have: total_erg,
            need: min_needed,
        });
    }

    let remainder = total_erg - send_erg - TX_FEE;

    // Subtract sent token from totals for change
    if let Some((token_id, amount)) = send_token {
        if let Some(balance) = token_totals.get_mut(token_id) {
            *balance = balance.saturating_sub(amount);
            if *balance == 0 {
                token_totals.remove(token_id);
            }
        }
    }

    let has_change_tokens = !token_totals.is_empty();
    // Dust change (0 < remainder < min box value) folds into the miner fee
    // instead of failing the send — a slightly higher fee beats a stranded
    // transfer. Token-bearing change still requires a full min-value box.
    let dust_to_fee = if !has_change_tokens && remainder > 0 && remainder < MIN_BOX_VALUE {
        remainder
    } else {
        0
    };
    let change_remainder = remainder - dust_to_fee;
    let need_change = change_remainder > 0 || has_change_tokens;

    if has_change_tokens && remainder < MIN_BOX_VALUE {
        return Err(SendError::TokenChangeInsufficientErg {
            have: remainder,
            min: MIN_BOX_VALUE,
        });
    }

    let effective_fee = TX_FEE + dust_to_fee;

    let recipient_assets: Vec<Eip12Asset> = match send_token {
        Some((token_id, amount)) => vec![Eip12Asset::new(token_id, amount as i64)],
        None => vec![],
    };

    let mut outputs = Vec::with_capacity(4);
    outputs.push(Eip12Output {
        value: send_erg.to_string(),
        ergo_tree: recipient_ergo_tree.to_string(),
        assets: recipient_assets,
        creation_height: current_height,
        additional_registers: recipient_registers.clone(),
    });

    let change_erg = if need_change {
        let change_value = if change_remainder > 0 {
            change_remainder
        } else {
            MIN_BOX_VALUE
        };
        let change_assets: Vec<Eip12Asset> = token_totals
            .into_iter()
            .map(|(id, amt)| Eip12Asset::new(id, amt as i64))
            .collect();
        outputs.extend(
            crate::token_outputs(
                change_value as u64,
                change_ergo_tree,
                change_assets,
                current_height,
                MIN_BOX_VALUE as u64,
            )
            .map_err(|e| match e {
                crate::ChangeOutputError::NotEnoughErg {
                    min_value,
                    available,
                } => SendError::TokenChangeInsufficientErg {
                    have: available as i64,
                    min: min_value as i64,
                },
                other => SendError::ChangeBox(other.to_string()),
            })?,
        );
        change_value
    } else {
        0
    };

    outputs.push(Eip12Output::fee(effective_fee, current_height));

    let unsigned_tx = Eip12UnsignedTx {
        inputs: user_inputs.to_vec(),
        data_inputs: vec![],
        outputs,
    };

    Ok(SendBuildResult {
        unsigned_tx,
        summary: SendSummary {
            recipient_erg: send_erg,
            token_id: send_token.map(|(id, _)| id.to_string()),
            token_amount: send_token.map(|(_, amt)| amt),
            change_erg,
            miner_fee: effective_fee,
            input_count: user_inputs.len(),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::eip12::Eip12Asset;
    use std::collections::HashMap;

    const USER_TREE: &str = "0008cduser";
    const RECIPIENT_TREE: &str = "0008cdrecip";

    fn make_box(value: &str, assets: Vec<(&str, &str)>) -> Eip12InputBox {
        Eip12InputBox {
            box_id: "b".to_string(),
            transaction_id: "t".to_string(),
            index: 0,
            value: value.to_string(),
            ergo_tree: USER_TREE.to_string(),
            assets: assets
                .into_iter()
                .map(|(id, amt)| Eip12Asset {
                    token_id: id.to_string(),
                    amount: amt.to_string(),
                })
                .collect(),
            creation_height: 1,
            additional_registers: HashMap::new(),
            extension: HashMap::new(),
        }
    }

    #[test]
    fn send_erg_only() {
        let inputs = vec![make_box("10000000000", vec![])]; // 10 ERG
        let result = build_send_tx(
            &inputs,
            RECIPIENT_TREE,
            USER_TREE,
            2_000_000_000, // 2 ERG
            None,
            50000,
        )
        .unwrap();

        assert_eq!(result.summary.recipient_erg, 2_000_000_000);
        assert_eq!(result.summary.miner_fee, TX_FEE);
        assert_eq!(
            result.summary.change_erg,
            10_000_000_000 - 2_000_000_000 - TX_FEE
        );
        assert_eq!(result.unsigned_tx.outputs.len(), 3); // recipient + change + fee
        assert_eq!(result.unsigned_tx.outputs[0].ergo_tree, RECIPIENT_TREE);
        assert_eq!(result.unsigned_tx.outputs[1].ergo_tree, USER_TREE);
    }

    #[test]
    fn send_token_with_min_erg() {
        let inputs = vec![make_box("5000000000", vec![("tok_a", "100")])];
        let result = build_send_tx(
            &inputs,
            RECIPIENT_TREE,
            USER_TREE,
            MIN_BOX_VALUE,
            Some(("tok_a", 40)),
            50000,
        )
        .unwrap();

        assert_eq!(result.summary.token_amount, Some(40));
        assert_eq!(result.unsigned_tx.outputs[0].assets.len(), 1);
        assert_eq!(result.unsigned_tx.outputs[0].assets[0].amount, "40");
        // change keeps remaining 60 tokens
        assert_eq!(result.unsigned_tx.outputs[1].assets.len(), 1);
        assert_eq!(result.unsigned_tx.outputs[1].assets[0].amount, "60");
    }

    #[test]
    fn reject_below_min_box() {
        let inputs = vec![make_box("10000000000", vec![])];
        let err =
            build_send_tx(&inputs, RECIPIENT_TREE, USER_TREE, 500_000, None, 50000).unwrap_err();
        assert!(matches!(err, SendError::BelowMinBoxValue { .. }));
    }

    #[test]
    fn reject_insufficient_token() {
        let inputs = vec![make_box("5000000000", vec![("tok_a", "10")])];
        let err = build_send_tx(
            &inputs,
            RECIPIENT_TREE,
            USER_TREE,
            MIN_BOX_VALUE,
            Some(("tok_a", 50)),
            50000,
        )
        .unwrap_err();
        assert!(matches!(err, SendError::InsufficientTokens { .. }));
    }

    #[test]
    fn exact_spend_no_change() {
        // send + fee exactly consumes inputs, no leftover tokens
        let send = 5_000_000_000i64;
        let inputs = vec![make_box(&(send + TX_FEE).to_string(), vec![])];
        let result = build_send_tx(&inputs, RECIPIENT_TREE, USER_TREE, send, None, 50000).unwrap();
        assert_eq!(result.summary.change_erg, 0);
        assert_eq!(result.unsigned_tx.outputs.len(), 2); // recipient + fee only
    }

    #[test]
    fn dust_change_folds_into_miner_fee() {
        // Leftover 900_000 nanoERG is below MIN_BOX_VALUE (1_000_000): instead
        // of erroring, it joins the miner fee and no change box is emitted.
        let send = 9_998_000_000i64;
        let inputs = vec![make_box("10000000000", vec![])];
        let result = build_send_tx(&inputs, RECIPIENT_TREE, USER_TREE, send, None, 50000).unwrap();
        assert_eq!(result.summary.change_erg, 0);
        assert_eq!(result.summary.miner_fee, TX_FEE + 900_000);
        assert_eq!(result.unsigned_tx.outputs.len(), 2); // recipient + fee only
    }

    #[test]
    fn a_wallet_with_more_tokens_than_a_box_holds_gets_split_change() {
        let ids: Vec<String> = (0..123).map(|i| format!("tok{i:04}")).collect();
        let assets: Vec<(&str, &str)> = ids.iter().map(|id| (id.as_str(), "7")).collect();
        let inputs = vec![make_box("5000000000", assets)];
        let built =
            build_send_tx(&inputs, RECIPIENT_TREE, USER_TREE, 1_000_000_000, None, 1).unwrap();
        let change: Vec<_> = built
            .unsigned_tx
            .outputs
            .iter()
            .filter(|o| o.ergo_tree == USER_TREE)
            .collect();
        assert_eq!(change.len(), 2);
        assert!(change
            .iter()
            .all(|o| o.assets.len() <= crate::MAX_TOKENS_PER_BOX));
        assert_eq!(change.iter().map(|o| o.assets.len()).sum::<usize>(), 123);
        let out_total: i64 = built
            .unsigned_tx
            .outputs
            .iter()
            .map(|o| o.value.parse::<i64>().unwrap())
            .sum();
        assert_eq!(
            out_total, 5_000_000_000,
            "ERG is conserved across the split"
        );
        assert_eq!(
            built.summary.change_erg,
            5_000_000_000 - 1_000_000_000 - TX_FEE
        );
    }

    fn r4(text: &str) -> HashMap<String, String> {
        HashMap::from([(
            "R4".to_string(),
            crate::sigma::encode_sigma_coll_byte(text.as_bytes()),
        )])
    }

    #[test]
    fn registers_go_on_the_recipient_output_only() {
        let token = "1b4e28ba-2fa1-41d2-883f-0016d3cca427";
        let inputs = vec![make_box("1000000000", vec![("tok_a", "5")])];
        let built = build_send_tx_with_registers(
            &inputs,
            RECIPIENT_TREE,
            USER_TREE,
            10_000_000,
            None,
            &r4(token),
            50000,
        )
        .unwrap();
        let outputs = &built.unsigned_tx.outputs;
        assert_eq!(outputs.len(), 3); // recipient + change + fee
        let expected = format!("0e24{}", hex::encode(token));
        assert_eq!(outputs[0].ergo_tree, RECIPIENT_TREE);
        assert_eq!(outputs[0].value, "10000000");
        assert!(outputs[0].assets.is_empty());
        assert_eq!(outputs[0].additional_registers.len(), 1);
        assert_eq!(outputs[0].additional_registers["R4"], expected);
        // The change keeps the tokens and gets no register.
        assert_eq!(outputs[1].ergo_tree, USER_TREE);
        assert!(outputs[1].additional_registers.is_empty());
        assert_eq!(outputs[1].assets.len(), 1);
        assert!(outputs[2].additional_registers.is_empty());
        assert_eq!(built.summary.recipient_erg, 10_000_000);
        assert_eq!(built.summary.miner_fee, TX_FEE);
        assert_eq!(
            built.summary.change_erg,
            1_000_000_000 - 10_000_000 - TX_FEE
        );
        let out_total: i64 = outputs
            .iter()
            .map(|o| o.value.parse::<i64>().unwrap())
            .sum();
        assert_eq!(out_total, 1_000_000_000, "ERG is conserved");
    }

    #[test]
    fn a_send_without_registers_writes_none() {
        let inputs = vec![make_box("10000000000", vec![])];
        let built =
            build_send_tx(&inputs, RECIPIENT_TREE, USER_TREE, 2_000_000_000, None, 1).unwrap();
        assert!(built
            .unsigned_tx
            .outputs
            .iter()
            .all(|o| o.additional_registers.is_empty()));
    }

    #[test]
    fn dust_change_with_registers_still_folds_into_the_fee() {
        let send = 10_000_000i64;
        let inputs = vec![make_box(&(send + TX_FEE + 400_000).to_string(), vec![])];
        let built = build_send_tx_with_registers(
            &inputs,
            RECIPIENT_TREE,
            USER_TREE,
            send,
            None,
            &r4("t"),
            1,
        )
        .unwrap();
        assert_eq!(built.unsigned_tx.outputs.len(), 2); // recipient + fee
        assert_eq!(built.summary.miner_fee, TX_FEE + 400_000);
        assert_eq!(
            built.unsigned_tx.outputs[0].additional_registers["R4"],
            "0e0174"
        );
    }

    #[test]
    fn registers_start_at_r4_and_have_no_gap() {
        let inputs = vec![make_box("10000000000", vec![])];
        let value = crate::sigma::encode_sigma_coll_byte(b"x");
        let cases: Vec<HashMap<String, String>> = vec![
            HashMap::from([("R5".to_string(), value.clone())]),
            HashMap::from([
                ("R4".to_string(), value.clone()),
                ("R6".to_string(), value.clone()),
            ]),
            HashMap::from([("R3".to_string(), value.clone())]),
            HashMap::from([("R4".to_string(), "0e0".to_string())]),
            HashMap::from([("R4".to_string(), "zz".to_string())]),
            HashMap::from([("R4".to_string(), String::new())]),
        ];
        for registers in cases {
            let err = build_send_tx_with_registers(
                &inputs,
                RECIPIENT_TREE,
                USER_TREE,
                MIN_BOX_VALUE,
                None,
                &registers,
                1,
            )
            .unwrap_err();
            assert!(
                matches!(err, SendError::BadRegisters(_)),
                "{registers:?}: {err}"
            );
        }
        let two = HashMap::from([
            ("R4".to_string(), value.clone()),
            ("R5".to_string(), value.clone()),
        ]);
        let built = build_send_tx_with_registers(
            &inputs,
            RECIPIENT_TREE,
            USER_TREE,
            MIN_BOX_VALUE,
            None,
            &two,
            1,
        )
        .unwrap();
        assert_eq!(built.unsigned_tx.outputs[0].additional_registers, two);
    }

    #[test]
    fn registers_do_not_change_the_checks_of_the_amounts() {
        let inputs = vec![make_box("5000000", vec![])];
        let err = build_send_tx_with_registers(
            &inputs,
            RECIPIENT_TREE,
            USER_TREE,
            5_000_000,
            None,
            &r4("t"),
            1,
        )
        .unwrap_err();
        assert!(matches!(err, SendError::InsufficientErg { .. }));
        let err = build_send_tx_with_registers(
            &inputs,
            RECIPIENT_TREE,
            USER_TREE,
            500_000,
            None,
            &r4("t"),
            1,
        )
        .unwrap_err();
        assert!(matches!(err, SendError::BelowMinBoxValue { .. }));
    }

    #[test]
    fn split_change_short_of_erg_is_a_token_change_error() {
        let ids: Vec<String> = (0..123).map(|i| format!("tok{i:04}")).collect();
        let assets: Vec<(&str, &str)> = ids.iter().map(|id| (id.as_str(), "7")).collect();
        let inputs = vec![make_box(
            &(1_000_000_000 + TX_FEE + 1_500_000).to_string(),
            assets,
        )];
        let err =
            build_send_tx(&inputs, RECIPIENT_TREE, USER_TREE, 1_000_000_000, None, 1).unwrap_err();
        match err {
            SendError::TokenChangeInsufficientErg { have, min } => {
                assert_eq!(have, 1_500_000);
                assert!(
                    min > 2 * MIN_BOX_VALUE,
                    "two boxes, each at its per-byte floor: {min}"
                );
            }
            other => panic!("{other}"),
        }
    }
}
