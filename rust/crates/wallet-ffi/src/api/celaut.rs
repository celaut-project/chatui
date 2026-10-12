//! Celaut nodes: connect to a node and read its advertisement (milestone M1).
//!
//! One async call. It opens a TLS connection, checks the identity in the certificate
//! of the node, makes a client id, asks for the `Peer` and checks its signature (see
//! `celaut-client`). The answer is plain data for the debug screen.

use std::sync::Arc;

use celaut_client::{
    connect_and_fetch, ClientError, FilePeerStore, MemoryPeerStore, NodeInfo, PeerError, PeerStore,
};
use celaut_proto::celaut::peer::Uri;
use celaut_proto::celaut::{ArchitectureResources, Contract, ContractRate, Sysresources};
use celaut_wire::{ConnectOptions, IdentityError, WireError};
use once_cell::sync::Lazy;

/// The last advertisement per node, for the life of the process. Used when the caller
/// gives no file.
static MEMORY_STORE: Lazy<Arc<MemoryPeerStore>> = Lazy::new(|| Arc::new(MemoryPeerStore::new()));

/// One key and its value, as text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyValueView {
    pub key: String,
    pub value: String,
}

/// One address of the node.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeUriView {
    pub ip: String,
    pub port: u32,
    /// Unix time in seconds after which the address can become wrong. 0 means no
    /// estimate.
    pub expiry_unix_timestamp: i64,
    /// For example `tcp`.
    pub transport: String,
    /// The first tag of each layer above the transport, bottom to top.
    pub protocols: Vec<String>,
}

/// One payment contract of the node.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PaymentContractView {
    /// The tags of the ledger, for example `ergo`.
    pub ledger: String,
    /// The MU for one base unit of the asset, as a decimal integer.
    pub mu_per_unit: String,
    /// The values that are specific to the ledger (for example `script`, `token_id`).
    /// Text when the bytes are printable text, else lowercase hex.
    pub details: Vec<KeyValueView>,
}

/// The most that the node supports for one architecture.
#[derive(Debug, Clone, PartialEq)]
pub struct NodeResourcesView {
    pub architecture: String,
    /// `cpu_quota / cpu_period` (the period is 100000 when absent).
    pub cpu_cores: Option<f64>,
    pub mem_limit_bytes: Option<i64>,
    pub disk_space_bytes: Option<i64>,
    /// The benchmark scores. An entry with no value shows an empty value.
    pub benchmark: Vec<KeyValueView>,
}

/// The advertisement of a node, after the checks of `celaut-client`.
#[derive(Debug, Clone, PartialEq)]
pub struct PeerInfoView {
    /// The identity of the node: 64 lowercase hex characters.
    pub peer_id: String,
    /// The time of the advertisement, in Unix seconds.
    pub ts: i64,
    pub uris: Vec<NodeUriView>,
    /// The rates of the node (`mu_per_call`), in MU, sorted by key.
    pub rates: Vec<KeyValueView>,
    pub payment_contracts: Vec<PaymentContractView>,
    pub resources: Vec<NodeResourcesView>,
    /// How many reputation proofs the advertisement has. M1 does not check them.
    pub reputation_proofs: u32,
}

/// What went wrong. The screen shows its own text for each kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CelautErrorKind {
    /// The host or the port is not valid.
    InvalidInput,
    /// No connection (DNS, TCP, TLS or HTTP/2).
    Unreachable,
    /// The node did not answer in time.
    Timeout,
    /// The node is not the expected one, or the advertisement is for another node.
    IdentityMismatch,
    /// The certificate has no valid identity.
    BadCertificate,
    /// The signature of the advertisement is missing or wrong.
    BadSignature,
    /// The advertisement is older than one that was accepted before.
    StaleTimestamp,
    /// The node signs with a scheme that the app does not support.
    UnsupportedScheme,
    /// The node asks for a proof of work that the app refuses or the node rejects.
    ProofOfWork,
    /// The node refused a call or sent an answer that cannot be used.
    Protocol,
    /// The file with the last advertisements failed.
    Storage,
}

/// The error of [`celaut_peer_info`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CelautError {
    pub kind: CelautErrorKind,
    /// The technical reason, in English.
    pub message: String,
}

pub(crate) fn error_of(e: ClientError) -> CelautError {
    use CelautErrorKind as K;
    let kind = match &e {
        ClientError::Wire(WireError::Identity(IdentityError::PeerMismatch { .. })) => {
            K::IdentityMismatch
        }
        ClientError::Wire(WireError::Identity(_)) => K::BadCertificate,
        ClientError::Wire(WireError::Connect(_)) => K::Unreachable,
        ClientError::Wire(WireError::Timeout) => K::Timeout,
        ClientError::Wire(WireError::Call(_) | WireError::Protocol(_)) => K::Protocol,
        ClientError::Peer(PeerError::KeyMismatch { .. }) => K::IdentityMismatch,
        ClientError::Peer(PeerError::StaleTs { .. }) => K::StaleTimestamp,
        ClientError::Peer(PeerError::UnsupportedScheme) => K::UnsupportedScheme,
        ClientError::Peer(_) => K::BadSignature,
        ClientError::Store(_) => K::Storage,
        ClientError::PowTooHard(_) | ClientError::PowRejected => K::ProofOfWork,
        ClientError::Protocol(_) | ClientError::Random | ClientError::Amount(_) => K::Protocol,
    };
    CelautError {
        kind,
        message: e.to_string(),
    }
}

pub(crate) fn invalid(message: &str) -> CelautError {
    CelautError {
        kind: CelautErrorKind::InvalidInput,
        message: message.to_string(),
    }
}

/// Text when the bytes are printable UTF-8, else lowercase hex.
fn show_bytes(bytes: &[u8]) -> String {
    match std::str::from_utf8(bytes) {
        Ok(text) if !text.is_empty() && !text.chars().any(char::is_control) => text.to_string(),
        _ => hex_text(bytes),
    }
}

fn hex_text(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn uri_view(uri: &Uri) -> NodeUriView {
    let first_tag = |tags: &[String]| tags.first().cloned().unwrap_or_default();
    NodeUriView {
        ip: uri.ip.clone(),
        port: u32::try_from(uri.port).unwrap_or_default(),
        expiry_unix_timestamp: uri.expiry_unix_timestamp,
        transport: uri
            .transport
            .as_ref()
            .map(|t| first_tag(&t.tags))
            .unwrap_or_default(),
        protocols: uri
            .protocol_stack
            .iter()
            .map(|p| first_tag(&p.tags))
            .collect(),
    }
}

fn contract_view(rate: &ContractRate) -> PaymentContractView {
    let contract: Contract = rate.contract.clone().unwrap_or_default();
    let ledger = contract.ledger.unwrap_or_default();
    let mut details: Vec<KeyValueView> = contract
        .xattrs
        .iter()
        .map(|e| KeyValueView {
            key: e.key.clone(),
            value: show_bytes(e.value.as_deref().unwrap_or_default()),
        })
        .collect();
    details.sort_by(|a, b| a.key.cmp(&b.key));
    PaymentContractView {
        ledger: ledger.tags.join(", "),
        mu_per_unit: rate.mu_per_unit.clone().unwrap_or_default().n,
        details,
    }
}

fn to_i64(value: Option<u64>) -> Option<i64> {
    value.map(|v| i64::try_from(v).unwrap_or(i64::MAX))
}

fn resources_view(entry: &ArchitectureResources) -> NodeResourcesView {
    let architecture = entry.architecture.clone().unwrap_or_default().tags;
    let r: Sysresources = entry.resources.clone().unwrap_or_default();
    let period = r.cpu_period.filter(|p| *p > 0).unwrap_or(100_000);
    NodeResourcesView {
        architecture: architecture.first().cloned().unwrap_or_default(),
        cpu_cores: r.cpu_quota.map(|q| q as f64 / period as f64),
        mem_limit_bytes: to_i64(r.mem_limit),
        disk_space_bytes: to_i64(r.disk_space),
        benchmark: r
            .benchmark
            .iter()
            .map(|e| KeyValueView {
                key: e.key.clone(),
                value: e.value.map(|v| v.to_string()).unwrap_or_default(),
            })
            .collect(),
    }
}

fn view_of(info: &NodeInfo) -> PeerInfoView {
    let peer = &info.peer;
    let mut rates: Vec<KeyValueView> = peer
        .mu_per_call
        .iter()
        .map(|e| KeyValueView {
            key: e.key.clone(),
            value: e.value.clone().unwrap_or_default().n,
        })
        .collect();
    rates.sort_by(|a, b| a.key.cmp(&b.key));
    PeerInfoView {
        peer_id: info.peer_id.clone(),
        ts: peer.ts,
        uris: peer.uri.iter().map(uri_view).collect(),
        rates,
        payment_contracts: peer.payment_contracts.iter().map(contract_view).collect(),
        resources: peer.resources.iter().map(resources_view).collect(),
        reputation_proofs: u32::try_from(peer.reputation_proofs.len()).unwrap_or(u32::MAX),
    }
}

/// Connect to a Celaut node and read its advertisement.
///
/// `host` is a name or an IP address without brackets. `expected_peer_id` is the
/// identity that the node must prove, if the caller knows it. `store_path` is a file
/// for the last accepted advertisement of each node. With `None`, the app keeps them in
/// memory until it stops.
#[flutter_rust_bridge::frb]
pub async fn celaut_peer_info(
    host: String,
    port: u16,
    expected_peer_id: Option<String>,
    store_path: Option<String>,
) -> Result<PeerInfoView, CelautError> {
    let host = host.trim().to_string();
    if host.is_empty() || host.contains(|c: char| c.is_whitespace() || c == '/') {
        return Err(invalid(
            "The host is empty or has characters that a host cannot have.",
        ));
    }
    if port == 0 {
        return Err(invalid("The port must be from 1 to 65535."));
    }
    let expected = expected_peer_id
        .map(|id| id.trim().to_string())
        .filter(|id| !id.is_empty());
    let store: Arc<dyn PeerStore> = match store_path {
        Some(path) => Arc::new(FilePeerStore::new(path)),
        None => MEMORY_STORE.clone(),
    };
    let options = ConnectOptions {
        expected_peer_id: expected,
        ..Default::default()
    };
    connect_and_fetch(&host, port, options, store.as_ref())
        .await
        .map(|info| view_of(&info))
        .map_err(error_of)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bytes_show_as_text_or_hex() {
        assert_eq!(show_bytes(b"ERG"), "ERG");
        assert_eq!(show_bytes(&[0x00, 0x08, 0xcd]), "0008cd");
        assert_eq!(show_bytes(&[]), "");
        assert_eq!(show_bytes(b"a\nb"), "610a62");
    }

    #[tokio::test]
    async fn bad_input_is_refused_before_any_connection() {
        let err = celaut_peer_info(" ".into(), 80, None, None)
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        let err = celaut_peer_info("a/b".into(), 80, None, None)
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        let err = celaut_peer_info("localhost".into(), 0, None, None)
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
    }

    #[tokio::test]
    async fn a_closed_port_is_unreachable() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let err = celaut_peer_info("127.0.0.1".into(), port, None, None)
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::Unreachable);
    }

    #[test]
    fn errors_get_a_kind() {
        let e = error_of(ClientError::Peer(PeerError::StaleTs { ts: 1, last: 2 }));
        assert_eq!(e.kind, CelautErrorKind::StaleTimestamp);
        let e = error_of(ClientError::Wire(WireError::Identity(
            IdentityError::PeerMismatch {
                expected: "a".into(),
                actual: "b".into(),
            },
        )));
        assert_eq!(e.kind, CelautErrorKind::IdentityMismatch);
        let e = error_of(ClientError::Wire(WireError::Identity(
            IdentityError::NoExtension,
        )));
        assert_eq!(e.kind, CelautErrorKind::BadCertificate);
        let e = error_of(ClientError::Peer(PeerError::BadSignature));
        assert_eq!(e.kind, CelautErrorKind::BadSignature);
        let e = error_of(ClientError::Wire(WireError::Timeout));
        assert_eq!(e.kind, CelautErrorKind::Timeout);
    }
}
