//! The typed Gateway calls of milestone M1.
//!
//! Indices come from `nodo:protos/gateway_bee.py` (`GATEWAY_RPCS`).

use bee_rpc::frame::Part;
use celaut_proto::celaut::{Client, Peer, PoWRequired};
use prost::Message;

use crate::{Transport, WireError};

/// What `GenerateClient` answers.
#[derive(Debug, Clone, PartialEq)]
pub enum GenerateClientReply {
    /// A new client (index 1).
    Client(Client),
    /// The node asks for a proof of work first (index 2).
    PowRequired(PoWRequired),
}

fn decode<M: Message + Default>(part: &Part, what: &str) -> Result<M, WireError> {
    M::decode(part.data.as_slice())
        .map_err(|e| WireError::Protocol(format!("{what} does not decode: {e}")))
}

/// `GenerateClient`: send one `Client` (index 1), get a `Client` (1) or a
/// `PoWRequired` (2).
pub async fn generate_client<T: Transport>(
    transport: &T,
    request: &Client,
) -> Result<GenerateClientReply, WireError> {
    let parts = vec![Part::new(1, request.encode_to_vec())];
    let answer = transport.call("GenerateClient", parts, &[1, 2]).await?;
    // The first part with a message index. Index 0 is raw bytes: not used here.
    for part in &answer {
        match part.index {
            1 => return Ok(GenerateClientReply::Client(decode(part, "the Client")?)),
            2 => {
                return Ok(GenerateClientReply::PowRequired(decode(
                    part,
                    "the PoWRequired",
                )?))
            }
            _ => {}
        }
    }
    Err(WireError::Protocol(
        "GenerateClient gave no Client and no PoWRequired".to_string(),
    ))
}

/// `GetPeerInfo`: send a `Client` that has the id (index 1), get a `Peer` (1).
///
/// The caller must check the signature of the `Peer`. This function does not.
pub async fn get_peer_info<T: Transport>(
    transport: &T,
    client_id: &str,
) -> Result<Peer, WireError> {
    let client = Client {
        client_id: client_id.to_string(),
        ..Default::default()
    };
    let parts = vec![Part::new(1, client.encode_to_vec())];
    let answer = transport.call("GetPeerInfo", parts, &[1]).await?;
    match answer.iter().find(|p| p.index == 1) {
        Some(part) => decode(part, "the Peer"),
        None => Err(WireError::Protocol("GetPeerInfo gave no Peer".to_string())),
    }
}
