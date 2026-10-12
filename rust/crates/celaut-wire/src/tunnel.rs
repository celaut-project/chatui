//! `ServiceTunnel`: a byte stream to one port of an instance, through the node.
//!
//! The request is `TokenMessage{token, slot}` at index 1, then each payload at index 0.
//! The answer is the bytes of the service at index 0 (`docs/celaut/wire.md`, section 5).
//! The end of the request (a half-close) closes the write side of the TCP connection
//! from the node to the service.
//!
//! The node charges the instance `TUNNEL_OPEN_MU` for each stream, and then for the
//! traffic. One stream carries one TCP connection.

use std::str::FromStr;

use bee_rpc::buffer::Buffer;
use bee_rpc::frame::{serialize_part, ParseOptions, Parser, Part};
use celaut_proto::celaut::TokenMessage;
use prost::Message;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::codegen::http::uri::PathAndQuery;

use crate::{Connection, WireError};

/// How many messages wait in each direction before the sender waits.
const QUEUE: usize = 16;

/// The largest payload in one Buffer. Under the one-Buffer limit of bee-rpc (1 MiB).
pub const MAX_PAYLOAD: usize = 64 * 1024;

/// One open tunnel.
///
/// The call runs in a task of its own. It ends when the node ends the answer, when
/// [`Tunnel::from_service`] is dropped, or on an error. An error comes as the last item
/// of [`Tunnel::from_service`]. A refusal of the node (wrong token, a slot that the
/// instance does not have, no balance) comes that way too, because the node sends
/// nothing before the service sends bytes.
#[derive(Debug)]
pub struct Tunnel {
    /// Bytes to the service. Drop it to half-close.
    pub to_service: mpsc::Sender<Vec<u8>>,
    /// Bytes from the service.
    pub from_service: mpsc::Receiver<Result<Vec<u8>, WireError>>,
}

/// Opens tunnels. [`Connection`] opens them on the node; a test can replace it.
pub trait TunnelOpener: Send + Sync + 'static {
    /// Open a tunnel to port `slot` of the instance with `token`. Must be called inside
    /// a Tokio runtime.
    fn open_tunnel(&self, token: &str, slot: u16) -> Tunnel;
}

impl TunnelOpener for Connection {
    fn open_tunnel(&self, token: &str, slot: u16) -> Tunnel {
        let (to_service, to_rx) = mpsc::channel(QUEUE);
        let (from_tx, from_service) = mpsc::channel(QUEUE);
        let handshake = TokenMessage {
            token: token.to_string(),
            slot: Some(slot.to_string()),
        };
        let channel = self.channel();
        tokio::spawn(async move {
            if let Err(e) = run(channel, handshake, to_rx, &from_tx).await {
                let _ = from_tx.send(Err(e)).await;
            }
        });
        Tunnel {
            to_service,
            from_service,
        }
    }
}

/// The Buffers of the request: the handshake, then the payloads. Empty payloads are not
/// sent (a receiver drops a part with no bytes).
pub fn request_buffers(handshake: &TokenMessage, payloads: &[Vec<u8>]) -> Vec<Buffer> {
    let mut out: Vec<Buffer> = serialize_part(&Part::new(1, handshake.encode_to_vec())).collect();
    for payload in payloads {
        out.extend(payload_buffers(payload));
    }
    out
}

fn payload_buffers(payload: &[u8]) -> Vec<Buffer> {
    payload
        .chunks(MAX_PAYLOAD)
        .flat_map(|piece| serialize_part(&Part::new(0, piece.to_vec())).collect::<Vec<_>>())
        .collect()
}

/// Ends the task that sends the request when the call ends.
struct AbortOnDrop(tokio::task::JoinHandle<()>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

fn status(e: tonic::Status) -> WireError {
    WireError::Call(format!("{:?}: {}", e.code(), e.message()))
}

async fn run(
    channel: tonic::transport::Channel,
    handshake: TokenMessage,
    mut to_rx: mpsc::Receiver<Vec<u8>>,
    from_tx: &mpsc::Sender<Result<Vec<u8>, WireError>>,
) -> Result<(), WireError> {
    let (buffer_tx, buffer_rx) = mpsc::channel::<Buffer>(QUEUE);
    for buffer in request_buffers(&handshake, &[]) {
        buffer_tx
            .send(buffer)
            .await
            .map_err(|_| WireError::Call("the tunnel closed".to_string()))?;
    }
    let sender = tokio::spawn(async move {
        while let Some(payload) = to_rx.recv().await {
            for buffer in payload_buffers(&payload) {
                if buffer_tx.send(buffer).await.is_err() {
                    return;
                }
            }
        }
        // `buffer_tx` is dropped here: the request ends (half-close).
    });
    let _sender = AbortOnDrop(sender);

    let path = PathAndQuery::from_str("/celaut.Gateway/ServiceTunnel")
        .map_err(|e| WireError::Call(e.to_string()))?;
    let mut client = tonic::client::Grpc::new(channel);
    client
        .ready()
        .await
        .map_err(|e| WireError::Connect(e.to_string()))?;
    let codec = tonic_prost::ProstCodec::<Buffer, Buffer>::default();
    let mut response = client
        .streaming(
            tonic::Request::new(ReceiverStream::new(buffer_rx)),
            path,
            codec,
        )
        .await
        .map_err(status)?
        .into_inner();

    let mut parser = Parser::new(ParseOptions::accepting([0]));
    loop {
        let message = tokio::select! {
            message = response.message() => message.map_err(status)?,
            // The reader is gone: dropping the response cancels the call.
            _ = from_tx.closed() => return Ok(()),
        };
        let Some(buffer) = message else { break };
        let parts = parser
            .push(buffer)
            .map_err(|e| WireError::Protocol(e.to_string()))?;
        if !forward(parts, from_tx).await {
            return Ok(());
        }
    }
    let parts = parser
        .finish()
        .map_err(|e| WireError::Protocol(e.to_string()))?;
    forward(parts, from_tx).await;
    Ok(())
}

/// Send the bytes of the parts to the reader. False when the reader is gone.
async fn forward(parts: Vec<Part>, to: &mpsc::Sender<Result<Vec<u8>, WireError>>) -> bool {
    for part in parts {
        if part.index == 0 && !part.data.is_empty() && to.send(Ok(part.data)).await.is_err() {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_handshake_comes_first_then_the_payloads_at_index_0() {
        let handshake = TokenMessage {
            token: "tok".into(),
            slot: Some("8080".into()),
        };
        let big = vec![7u8; MAX_PAYLOAD + 10];
        let buffers = request_buffers(&handshake, &[b"GET / HTTP/1.1\r\n\r\n".to_vec(), vec![], big]);
        let indices: Vec<i32> = buffers
            .iter()
            .map(|b| b.head.as_ref().map(|h| h.index).unwrap())
            .collect();
        // The empty payload is not sent; the big one is two Buffers.
        assert_eq!(indices, vec![1, 0, 0, 0]);
        let first = TokenMessage::decode(buffers[0].chunk.as_deref().unwrap()).unwrap();
        assert_eq!(first, handshake);
        assert!(buffers.iter().all(|b| b.separator == Some(true)));
        assert_eq!(buffers[3].chunk.as_ref().unwrap().len(), 10);
    }
}
