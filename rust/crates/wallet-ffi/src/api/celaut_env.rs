//! The environment variables of a service (`docs/celaut/env-variables.md`): the
//! container of the app, and the variables that a service declares.
//!
//! The container is in the Celaut database, which is encrypted. A value leaves Rust only
//! through [`celaut_env_get`], when the user asks to see or to edit it. A launch names a
//! variable of the container and Rust reads its value ([`EnvChoice`]), so the value does
//! not go through Dart. No value is in a log, an event or the text of an error.

use std::path::PathBuf;

use celaut_client::declaration::{declared_variables, declared_variables_of_file, Declared};
use celaut_client::env::{check_name, check_value, entries, EnvError};
use celaut_proto::celaut::BytesKeyValue;

use super::celaut::{error_of, invalid, CelautError};
use super::celaut_db::{db, now_seconds, storage_error};
use super::celaut_package::package_error;
use super::celaut_service::{forget_if_broken, service_id, session, NodeAddress};

/// The most that the app reads from a node to find the declaration of a service, in
/// bytes. A node sends the whole service, and the declaration is after its filesystem.
pub(crate) const NODE_READ_LIMIT: u64 = 128 * 1024 * 1024;

fn refused(e: EnvError) -> CelautError {
    invalid(&e.to_string())
}

/// One variable of the container, without its value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnvNameView {
    pub name: String,
    /// The time of the last change, in Unix seconds.
    pub changed_at: i64,
}

/// The variables of the container, by name.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_env_names() -> Vec<EnvNameView> {
    db().read(|d| {
        d.env_variables
            .iter()
            .map(|(name, r)| EnvNameView {
                name: name.clone(),
                changed_at: r.changed_at,
            })
            .collect()
    })
}

/// The value of a variable of the container, or none if there is no such variable.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_env_get(name: String) -> Option<String> {
    db().read(|d| d.env_variables.get(&name).map(|r| r.value.clone()))
}

/// Add a variable, or replace the value of the one with this name. A name is a C
/// identifier that is not `__nodo_instance_name`; a value is text of 1 to 8192 bytes
/// with no NUL character; the container holds 256 variables.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_env_set(name: String, value: String) -> Result<(), CelautError> {
    db().update(|d| d.set_env(&name, &value, now_seconds()))
        .map_err(storage_error)?
        .map_err(refused)
}

/// Remove a variable. A name that is not there is not an error.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_env_delete(name: String) -> Result<(), CelautError> {
    db().update(|d| {
        d.env_variables.remove(&name);
    })
    .map_err(storage_error)
}

/// A variable that a service declares.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeclaredVariableView {
    pub name: String,
    /// The names of its format.
    pub tags: Vec<String>,
    /// The text that explains it (empty if the service gives none).
    pub prose: String,
}

fn view_of(d: Declared) -> DeclaredVariableView {
    DeclaredVariableView {
        name: d.name,
        tags: d.tags,
        prose: d.prose,
    }
}

/// The variables that the service declares, in the order of its declaration. The app
/// reads them from the file of the service in the library if it has one. If not, from
/// `node` (a node that has the service), which sends the service: it stops after
/// 128 MiB, with an error. A service that declares nothing gives an empty list.
#[flutter_rust_bridge::frb]
pub async fn celaut_service_declaration(
    service_id_hex: String,
    node: Option<NodeAddress>,
) -> Result<Vec<DeclaredVariableView>, CelautError> {
    let id = service_id(&service_id_hex)?;
    let library = db()
        .read(|d| {
            d.packages
                .get(&hex::encode(id))
                .map(|p| PathBuf::from(&p.path))
        })
        .filter(|p| p.is_file());
    let declared = if let Some(path) = library {
        declared_variables_of_file(&path)
            .await
            .map_err(package_error)?
    } else {
        let node = node.ok_or_else(|| invalid("There is no node to read the service from."))?;
        let s = session(&node).await?;
        let raw = s.get_service(id).await.map_err(|e| {
            forget_if_broken(&node, &e);
            error_of(e)
        })?;
        declared_variables(raw, Some(NODE_READ_LIMIT))
            .await
            .map_err(package_error)?
    };
    Ok(declared.into_iter().map(view_of).collect())
}

/// The value for one declared variable, as the user chose it. A variable that the user
/// skipped is not given at all, so it is not in the configuration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnvChoice {
    /// The name that the service gets.
    pub name: String,
    /// The name of the variable of the container whose value to use.
    pub container: Option<String>,
    /// A value that the user typed, as UTF-8 text.
    pub text: Option<String>,
}

/// The entries of the configuration for the choices. Exactly one of `container` and
/// `text` must be set for each choice.
pub(crate) fn resolve(choices: &[EnvChoice]) -> Result<Vec<BytesKeyValue>, CelautError> {
    let mut pairs = Vec::with_capacity(choices.len());
    for choice in choices {
        check_name(&choice.name).map_err(refused)?;
        let value = match (&choice.container, &choice.text) {
            (Some(from), None) => db()
                .read(|d| d.env_variables.get(from).map(|r| r.value.clone()))
                .ok_or_else(|| {
                    invalid(&format!(
                        "The variable {from} of the container does not exist. It was deleted."
                    ))
                })?,
            (None, Some(text)) => {
                check_value(text).map_err(refused)?;
                text.clone()
            }
            _ => {
                return Err(invalid(&format!(
                    "The variable {} needs a variable of the container or a typed value, not both and not none.",
                    choice.name
                )))
            }
        };
        pairs.push((choice.name.clone(), value));
    }
    entries(&pairs).map_err(refused)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn choice(name: &str, container: Option<&str>, text: Option<&str>) -> EnvChoice {
        EnvChoice {
            name: name.into(),
            container: container.map(Into::into),
            text: text.map(Into::into),
        }
    }

    #[test]
    fn the_container_adds_replaces_and_removes() {
        celaut_env_delete("T_ONE".into()).unwrap();
        celaut_env_set("T_ONE".into(), "a".into()).unwrap();
        celaut_env_set("T_ONE".into(), "b".into()).unwrap();
        assert_eq!(celaut_env_get("T_ONE".into()).as_deref(), Some("b"));
        let names = celaut_env_names();
        assert_eq!(names.iter().filter(|n| n.name == "T_ONE").count(), 1);
        celaut_env_delete("T_ONE".into()).unwrap();
        assert_eq!(celaut_env_get("T_ONE".into()), None);
        celaut_env_delete("T_ONE".into()).unwrap();
    }

    #[test]
    fn a_bad_name_or_value_is_refused_with_its_reason() {
        let e = celaut_env_set("1X".into(), "a".into()).unwrap_err();
        assert!(e.message.contains("start with a letter"), "{}", e.message);
        let e = celaut_env_set("T_X".into(), "".into()).unwrap_err();
        assert!(e.message.contains("empty"), "{}", e.message);
        assert_eq!(celaut_env_get("T_X".into()), None);
        assert!(celaut_env_set("__nodo_instance_name".into(), "a".into()).is_err());
    }

    #[test]
    fn a_choice_of_the_container_gets_its_value_and_a_typed_one_its_text() {
        celaut_env_set("T_SECRET".into(), "s3cr€t".into()).unwrap();
        let got = resolve(&[
            choice("API_KEY", Some("T_SECRET"), None),
            choice("MODE", None, Some("fast")),
        ])
        .unwrap();
        assert_eq!(got.len(), 2);
        assert_eq!(got[0].key, "API_KEY");
        assert_eq!(got[0].value.as_deref(), Some("s3cr€t".as_bytes()));
        assert_eq!(got[1].value.as_deref(), Some(b"fast".as_slice()));
        assert!(resolve(&[]).unwrap().is_empty());
        celaut_env_delete("T_SECRET".into()).unwrap();
    }

    #[test]
    fn a_wrong_choice_is_refused_and_its_error_has_no_value() {
        celaut_env_set("T_GONE".into(), "hunter2".into()).unwrap();
        celaut_env_delete("T_GONE".into()).unwrap();
        let e = resolve(&[choice("A", Some("T_GONE"), None)]).unwrap_err();
        assert!(e.message.contains("T_GONE"));
        assert!(resolve(&[choice("A", None, None)]).is_err());
        assert!(resolve(&[choice("A", Some("X"), Some("y"))]).is_err());
        assert!(resolve(&[choice("1A", None, Some("y"))]).is_err());
        let e = resolve(&[choice("A", None, Some("a\0b"))]).unwrap_err();
        assert!(!e.message.contains("a\0b"));
        assert!(resolve(&[choice("A", None, Some("1")), choice("A", None, Some("2"))]).is_err());
    }
}
