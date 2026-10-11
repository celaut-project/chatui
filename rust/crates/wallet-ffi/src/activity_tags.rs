//! Which kind of box a box is, for the activity list.
//!
//! A box is matched by the NFT it carries first (the ERG/USD oracle pool),
//! then by its script (Babel fee boxes). Anything else is untagged.
//!
//! Tags are the strings the app reads (`activity_classifier.dart` keeps the
//! same list): `babel`, `oracle`, and `argus_fee`.

/// The fee that the Argus wallet added to each transaction it built. This app
/// adds no fee; the tag only labels these outputs in the history of a wallet
/// that was used in Argus before.
const ARGUS_FEE_ADDRESS: &str = "9iArkadiaZAPVxbUp2XQ8SVA1zGA29rCPhbpVuUaaKW6fWspUZA";
const ARGUS_FEE_NANO: i64 = 1_100_000;

/// The ERG/USD oracle pool NFT (ERGUSD-NFT).
const ORACLE_POOL_NFT_ID: &str = "011d3364de07e5a26f0c4eef0852cddb387039a921b7154ef3cab22c6eda887f";

/// The protocol tag of one box (node JSON), or None for an ordinary box.
pub fn tag_box(b: &serde_json::Value) -> Option<String> {
    let tree = b["ergoTree"]
        .as_str()
        .unwrap_or_default()
        .to_ascii_lowercase();
    let assets = b["assets"].as_array();

    if b["value"].as_i64() == Some(ARGUS_FEE_NANO)
        && assets.is_none_or(|a| a.is_empty())
        && wallet_net::activity::box_address(b).as_deref() == Some(ARGUS_FEE_ADDRESS)
    {
        return Some(wallet_net::activity::ARGUS_FEE_TAG.to_string());
    }
    if assets.is_some_and(|a| a.iter().any(|a| a["tokenId"].as_str() == Some(ORACLE_POOL_NFT_ID))) {
        return Some("oracle".into());
    }
    if tree.is_empty() {
        return None;
    }
    if ergo_tx::babel_token_of(&tree).is_some() {
        return Some("babel".into());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn known_scripts_and_nfts_are_tagged() {
        let oracle = json!({"ergoTree": "00", "value": 1, "assets": [
            {"tokenId": ORACLE_POOL_NFT_ID, "amount": 1}]});
        assert_eq!(tag_box(&oracle).as_deref(), Some("oracle"));
        let fee = json!({"address": ARGUS_FEE_ADDRESS, "ergoTree": "00", "value": ARGUS_FEE_NANO, "assets": []});
        assert_eq!(tag_box(&fee).as_deref(), Some("argus_fee"));
        // The same address paid anything else is an ordinary payment.
        let paid = json!({"address": ARGUS_FEE_ADDRESS, "ergoTree": "00", "value": 5_000_000, "assets": []});
        assert_eq!(tag_box(&paid), None);
        let p2pk = json!({"ergoTree": "0008cd03e0e953d67d623597b372ee", "value": 1});
        assert_eq!(tag_box(&p2pk), None);
    }
}
