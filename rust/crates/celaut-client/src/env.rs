//! The environment variables of a service (`docs/celaut/env-variables.md`): the rules
//! for a name and a value, and the pairs of a start.
//!
//! The rules are the ones of the node: it gives a variable to the process only if its
//! name is a C identifier and its value has no NUL byte, and it reserves the name
//! `__nodo_instance_name`. The container of the app and the pairs of a start follow the
//! same rules, so a value that the app accepts is a value that the node can use.

use celaut_proto::celaut::BytesKeyValue;

/// The name that the node reserves for the name of the instance.
pub const RESERVED_NAME: &str = "__nodo_instance_name";

/// How many variables the container holds.
pub const MAX_VARIABLES: usize = 256;

/// The longest value, in bytes.
pub const MAX_VALUE_BYTES: usize = 8 * 1024;

/// The longest name, in bytes.
pub const MAX_NAME_BYTES: usize = 256;

/// Why a name or a value is refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum EnvError {
    #[error("The name is empty.")]
    EmptyName,
    #[error("The name is longer than {MAX_NAME_BYTES} bytes.")]
    LongName,
    #[error("The name must start with a letter or _ and have only letters, digits and _.")]
    BadName,
    #[error("The name {RESERVED_NAME} is reserved for the name of the instance.")]
    ReservedName,
    #[error("The value is empty.")]
    EmptyValue,
    #[error("The value is longer than {MAX_VALUE_BYTES} bytes.")]
    LongValue,
    #[error("The value cannot have a NUL character.")]
    NulInValue,
    #[error("There are already {MAX_VARIABLES} variables. Delete one first.")]
    TooMany,
    #[error("The variable has a repeated name.")]
    RepeatedName,
}

/// Check a name: a C identifier that is not reserved.
pub fn check_name(name: &str) -> Result<(), EnvError> {
    let mut chars = name.chars();
    let first = chars.next().ok_or(EnvError::EmptyName)?;
    if name.len() > MAX_NAME_BYTES {
        return Err(EnvError::LongName);
    }
    let starts = first == '_' || first.is_ascii_alphabetic();
    if !starts || !chars.all(|c| c == '_' || c.is_ascii_alphanumeric()) {
        return Err(EnvError::BadName);
    }
    if name == RESERVED_NAME {
        return Err(EnvError::ReservedName);
    }
    Ok(())
}

/// Check a value: text with at least one byte, no NUL, and a limited size.
pub fn check_value(value: &str) -> Result<(), EnvError> {
    if value.is_empty() {
        return Err(EnvError::EmptyValue);
    }
    if value.len() > MAX_VALUE_BYTES {
        return Err(EnvError::LongValue);
    }
    if value.contains('\0') {
        return Err(EnvError::NulInValue);
    }
    Ok(())
}

/// The entries of `Configuration.environment_variables` for these pairs, in the order
/// given. A pair that repeats a name is an error of the caller, so it is refused here.
pub fn entries(pairs: &[(String, String)]) -> Result<Vec<BytesKeyValue>, EnvError> {
    let mut seen = std::collections::BTreeSet::new();
    let mut out = Vec::with_capacity(pairs.len());
    for (name, value) in pairs {
        check_name(name)?;
        check_value(value)?;
        if !seen.insert(name.as_str()) {
            return Err(EnvError::RepeatedName);
        }
        out.push(BytesKeyValue {
            key: name.clone(),
            value: Some(value.as_bytes().to_vec()),
        });
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_name_is_a_c_identifier_that_is_not_reserved() {
        for good in ["A", "_", "API_KEY", "_x1", "a9"] {
            assert_eq!(check_name(good), Ok(()), "{good}");
        }
        assert_eq!(check_name(""), Err(EnvError::EmptyName));
        for bad in ["1A", "A-B", "A B", "ñ", "A.B", "A=B"] {
            assert_eq!(check_name(bad), Err(EnvError::BadName), "{bad}");
        }
        assert_eq!(check_name(RESERVED_NAME), Err(EnvError::ReservedName));
        assert_eq!(
            check_name(&"A".repeat(MAX_NAME_BYTES + 1)),
            Err(EnvError::LongName)
        );
        assert_eq!(check_name(&"A".repeat(MAX_NAME_BYTES)), Ok(()));
    }

    #[test]
    fn a_value_is_text_without_nul_and_with_a_limit() {
        assert_eq!(check_value("sk-1 ñ \n"), Ok(()));
        assert_eq!(check_value(""), Err(EnvError::EmptyValue));
        assert_eq!(check_value("a\0b"), Err(EnvError::NulInValue));
        assert_eq!(
            check_value(&"a".repeat(MAX_VALUE_BYTES + 1)),
            Err(EnvError::LongValue)
        );
        assert_eq!(check_value(&"a".repeat(MAX_VALUE_BYTES)), Ok(()));
    }

    #[test]
    fn the_entries_keep_the_order_and_the_bytes() {
        let e = entries(&[("B".into(), "2".into()), ("A".into(), "ñ".into())]).unwrap();
        assert_eq!(e[0].key, "B");
        assert_eq!(e[1].value.as_deref(), Some("ñ".as_bytes()));
        assert!(entries(&[]).unwrap().is_empty());
    }

    #[test]
    fn a_pair_that_the_node_would_ignore_is_refused() {
        assert!(entries(&[("1".into(), "x".into())]).is_err());
        assert!(entries(&[("A".into(), "x".into()), ("A".into(), "y".into())]).is_err());
        assert!(entries(&[("A".into(), String::new())]).is_err());
    }
}
