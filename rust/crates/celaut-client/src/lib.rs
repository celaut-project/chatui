//! Celaut client, first part (milestone M1): ask a node for its advertisement.
//!
//! The steps of [`fetch_node_info`]:
//!
//! 1. `GenerateClient`, with the proof of work if the node asks for it ([`pow`]).
//! 2. `GetPeerInfo`.
//! 3. Check the `Peer`: the signature, the key equal to the identity that the TLS
//!    certificate proved, and the `ts` against the last advertisement that this app
//!    accepted from that node ([`peer`], [`store`]).
//!
//! The client id is not kept. M1 uses it for the one `GetPeerInfo` call and drops it.
//! A store for client ids comes with the milestone that needs them (M2).
//!
//! Input from a peer must never make this crate panic.
#![forbid(unsafe_code)]
#![cfg_attr(
    not(test),
    deny(clippy::unwrap_used, clippy::expect_used, clippy::panic)
)]

pub mod peer;
pub mod pow;
pub mod store;

use celaut_proto::celaut::{Client, Peer};
use celaut_wire::gateway::{generate_client, get_peer_info, GenerateClientReply};
use celaut_wire::{ConnectOptions, Connection, Transport, WireError};

pub use peer::PeerError;
pub use store::{FilePeerStore, MemoryPeerStore, PeerStore, Seen, StoreError};

/// Every error of this crate.
#[derive(Debug, thiserror::Error)]
pub enum ClientError {
    /// The connection or a call failed.
    #[error(transparent)]
    Wire(#[from] WireError),
    /// The advertisement of the node is not acceptable.
    #[error(transparent)]
    Peer(#[from] PeerError),
    /// The store of last-seen values failed.
    #[error(transparent)]
    Store(#[from] StoreError),
    /// The node asks for more work than this client does.
    #[error("the node asks for a proof of work of difficulty {0}, which is too much work")]
    PowTooHard(u32),
    /// The node did not accept the proof of work, or asked for it again.
    #[error("the node did not accept the proof of work")]
    PowRejected,
    /// The answer of the node is not usable.
    #[error("unexpected answer: {0}")]
    Protocol(String),
    /// No random numbers from the system.
    #[error("the system gave no random numbers")]
    Random,
}

/// The advertisement of a node, after the checks.
#[derive(Debug, Clone, PartialEq)]
pub struct NodeInfo {
    /// The identity of the node (Ed25519 key, 64 lowercase hex characters). It is the
    /// one that the TLS certificate proved.
    pub peer_id: String,
    /// The `Peer`, signed by that identity.
    pub peer: Peer,
}

/// A new client id: the 32 lowercase hex characters of a random UUID4.
pub fn new_client_id() -> Result<String, ClientError> {
    use ring::rand::{SecureRandom, SystemRandom};
    let mut bytes = [0u8; 16];
    SystemRandom::new()
        .fill(&mut bytes)
        .map_err(|_| ClientError::Random)?;
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    Ok(hex::encode(bytes))
}

/// `GenerateClient`, with the proof of work when the node asks for it. Gives the
/// client id.
pub async fn obtain_client_id<T: Transport>(transport: &T) -> Result<String, ClientError> {
    let proposed = new_client_id()?;
    let request = Client {
        client_id: proposed.clone(),
        ..Default::default()
    };
    let required = match generate_client(transport, &request).await? {
        GenerateClientReply::Client(client) => return accepted_client(client),
        GenerateClientReply::PowRequired(required) => required,
    };

    // The node uses the difficulty in the challenge, not its copy.
    let challenge = required.challenge;
    let difficulty = pow::challenge_difficulty(&challenge)
        .or_else(|| u32::try_from(required.difficulty).ok())
        .ok_or_else(|| ClientError::Protocol("the proof of work has no difficulty".into()))?;
    if difficulty > pow::MAX_DIFFICULTY {
        return Err(ClientError::PowTooHard(difficulty));
    }
    let work = challenge.clone();
    let solution = tokio::task::spawn_blocking(move || pow::solve_pow(&work, difficulty))
        .await
        .map_err(|e| ClientError::Protocol(format!("the proof of work stopped: {e}")))??;

    let retry = Client {
        client_id: proposed,
        challenge: Some(challenge),
        pow_solution: Some(solution),
        ..Default::default()
    };
    match generate_client(transport, &retry).await? {
        GenerateClientReply::Client(client) => accepted_client(client),
        GenerateClientReply::PowRequired(_) => Err(ClientError::PowRejected),
    }
}

fn accepted_client(client: Client) -> Result<String, ClientError> {
    if client.client_id.is_empty() {
        return Err(ClientError::Protocol(
            "the node gave an empty client id".into(),
        ));
    }
    Ok(client.client_id)
}

/// Get the `Peer` of the node on `transport` and check it. `certificate_peer_id` is the
/// identity that the TLS certificate proved.
///
/// The `ts` is stored only after every check passed.
pub async fn fetch_node_info<T: Transport>(
    transport: &T,
    certificate_peer_id: &str,
    store: &dyn PeerStore,
) -> Result<NodeInfo, ClientError> {
    let client_id = obtain_client_id(transport).await?;
    let peer = get_peer_info(transport, &client_id).await?;
    let digest = peer::verify_signature(&peer, certificate_peer_id)?;
    let last = store.get(certificate_peer_id)?;
    peer::check_ts(last.as_ref(), peer.ts, &digest)?;
    store.put(
        certificate_peer_id,
        Seen {
            ts: peer.ts,
            digest,
        },
    )?;
    Ok(NodeInfo {
        peer_id: certificate_peer_id.to_string(),
        peer,
    })
}

/// Connect to `host:port`, check the certificate, and call [`fetch_node_info`].
pub async fn connect_and_fetch(
    host: &str,
    port: u16,
    options: ConnectOptions,
    store: &dyn PeerStore,
) -> Result<NodeInfo, ClientError> {
    let connection = Connection::connect(host, port, options).await?;
    fetch_node_info(&connection, connection.peer_id(), store).await
}
