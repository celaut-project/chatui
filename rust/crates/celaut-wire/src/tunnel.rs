//! `ServiceTunnel`: a byte stream to one port of an instance, through the node.
//!
//! The request is `TokenMessage{token, slot, receipts}` at index 1, then each payload at
//! index 0. The answer is the bytes of the service at index 0 (`docs/celaut/wire.md`,
//! section 5), and the signed checkpoints of the execution receipt at index 2
//! (nodo#419). The end of the request (a half-close) closes the write side of the TCP
//! connection from the node to the service.
//!
//! The node charges the instance `TUNNEL_OPEN_MU` for each stream, and then for the
//! traffic. One stream carries one TCP connection.
//!
//! # Receipts
//!
//! The client always asks for receipts (`TokenMessage.receipts`), and it accepts index 2
//! also when it did not ask: a node can send receipts to every caller. Each message
//! that this side sends at index 0 is one event of the `in` chain, and each message
//! that it gets at index 0 is one event of the `out` chain ([`crate::receipt`]). The
//! client keeps both chains, and checks each checkpoint against them: the node must
//! sign the bytes that this side sent and got. The result goes to a [`ReceiptSink`].
//! A stream that this side cancels gets no `close`, and that is not a fault.

use std::collections::VecDeque;
use std::str::FromStr;
use std::sync::{Arc, Mutex, PoisonError};

use bee_rpc::buffer::Buffer;
use bee_rpc::frame::{serialize_part, ParseOptions, Parser, Part};
use celaut_proto::celaut::{ExecutionReceipt, TokenMessage};
use prost::Message;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::codegen::http::uri::PathAndQuery;

use crate::receipt::{self, Chain, DIRECTION_IN, DIRECTION_OUT, KIND_CLOSE};
use crate::{Connection, WireError};

/// How many messages wait in each direction before the sender waits.
const QUEUE: usize = 16;

/// The largest payload in one Buffer. Under the one-Buffer limit of bee-rpc (1 MiB).
pub const MAX_PAYLOAD: usize = 64 * 1024;

/// The index of the payloads.
const BYTES: i32 = 0;
/// The index of the handshake in the request.
const HANDSHAKE: i32 = 1;
/// The index of the receipts in the answer.
const RECEIPT: i32 = 2;

/// How many messages of one direction the client keeps the heads of, between two
/// checkpoints that match. The node signs a checkpoint every 1 MiB or 5 s of traffic, so
/// this is a limit for a node that does not. Past it, the client stops the check of the
/// chains of the stream (it does not call that a fault) and still checks the signatures.
const MAX_MARKS: usize = 1 << 16;

/// One receipt of a tunnel stream, and what this side found in it.
#[derive(Debug, Clone, PartialEq)]
pub struct StreamReceipt {
    pub receipt: ExecutionReceipt,
    /// Why the receipt is not valid ([`receipt::problems`] against the node of the
    /// connection and the token), and the faults of the stream (a receipt after the
    /// close, a seq that does not go up). Empty when it is valid.
    pub problems: Vec<String>,
    /// The `in` chain of the receipt is not the chain of the messages that this side
    /// sent: the node signed data that this side did not send.
    pub sent_mismatch: bool,
    /// The `out` chain of the receipt is not the chain of the messages that this side
    /// got: the node signed data that this side did not get.
    pub got_mismatch: bool,
}

impl StreamReceipt {
    /// True if nothing is wrong with it.
    pub fn is_good(&self) -> bool {
        self.problems.is_empty() && !self.sent_mismatch && !self.got_mismatch
    }
}

/// What a tunnel tells its [`ReceiptSink`].
#[derive(Debug, Clone, PartialEq)]
pub enum ReceiptEvent {
    /// A checkpoint or the close of the stream, in the order of the stream.
    Receipt(StreamReceipt),
    /// The stream ended. `session` is the stream of the receipts, if one came. `closed`:
    /// a close came. `cancelled`: this side ended the stream (its reader went away);
    /// then the node sends no close, and that is not a fault.
    Ended {
        session: Option<String>,
        closed: bool,
        cancelled: bool,
    },
}

/// Gets the receipts of a tunnel. It is called from the task of the tunnel, so it must
/// not block for long.
pub type ReceiptSink = Arc<dyn Fn(ReceiptEvent) + Send + Sync>;

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
    /// Open a tunnel to port `slot` of the instance with `token`. The receipts of the
    /// stream go to `receipts`, if given. Must be called inside a Tokio runtime.
    fn open_tunnel(&self, token: &str, slot: u16, receipts: Option<ReceiptSink>) -> Tunnel;
}

impl TunnelOpener for Connection {
    fn open_tunnel(&self, token: &str, slot: u16, receipts: Option<ReceiptSink>) -> Tunnel {
        open(self.channel(), self.peer_id(), token, slot, receipts)
    }
}

/// Open a tunnel on `channel`, to a node with this `peer_id`: the receipts must be
/// signed by it. [`Connection`] gives both; a test gives its own channel.
pub fn open(
    channel: tonic::transport::Channel,
    peer_id: &str,
    token: &str,
    slot: u16,
    receipts: Option<ReceiptSink>,
) -> Tunnel {
    let (to_service, to_rx) = mpsc::channel(QUEUE);
    let (from_tx, from_service) = mpsc::channel(QUEUE);
    let handshake = handshake(token, slot);
    let checker = Arc::new(Mutex::new(Checker::new(peer_id, token)));
    tokio::spawn(async move {
        let cancelled = match run(
            channel,
            handshake,
            to_rx,
            &from_tx,
            &checker,
            receipts.as_ref(),
        )
        .await
        {
            Ok(cancelled) => cancelled,
            Err(e) => {
                let _ = from_tx.send(Err(e)).await;
                false
            }
        };
        if let Some(sink) = &receipts {
            let checker = checker.lock().unwrap_or_else(PoisonError::into_inner);
            sink(ReceiptEvent::Ended {
                session: checker.session.clone(),
                closed: checker.closed,
                cancelled,
            });
        }
    });
    Tunnel {
        to_service,
        from_service,
    }
}

/// The handshake of a tunnel: the token, the slot, and the receipts, which the client
/// always asks for.
pub fn handshake(token: &str, slot: u16) -> TokenMessage {
    TokenMessage {
        token: token.to_string(),
        slot: Some(slot.to_string()),
        receipts: true,
    }
}

/// The messages of one direction as this side saw them: the chain, and its state after
/// each message since the last checkpoint that matched.
#[derive(Debug)]
struct Seen {
    direction: &'static str,
    chain: Chain,
    /// `(events, bytes, head)` at the last checkpoint that matched, then after each
    /// message.
    marks: VecDeque<(u64, u64, String)>,
    /// True after more than [`MAX_MARKS`] messages with no checkpoint: the chains of the
    /// stream are not checked any more.
    unchecked: bool,
}

impl Seen {
    fn new(direction: &'static str) -> Self {
        let chain = Chain::default();
        Seen {
            direction,
            marks: VecDeque::from([(0, 0, chain.head.clone())]),
            chain,
            unchecked: false,
        }
    }

    fn push(&mut self, payload: &[u8]) {
        self.chain.push(self.direction, payload);
        if self.unchecked {
            return;
        }
        if self.marks.len() > MAX_MARKS {
            self.unchecked = true;
            self.marks.clear();
            return;
        }
        let c = &self.chain;
        self.marks.push_back((c.events, c.bytes, c.head.clone()));
    }

    /// Whether the node's `(events, bytes, head)` is a state of this chain. On a match,
    /// the states before it are dropped: the next checkpoint counts at least as many.
    fn matches(&mut self, events: u64, bytes: u64, head: &str) -> bool {
        if self.unchecked {
            return true;
        }
        let Some(first) = self.marks.front().map(|m| m.0) else {
            return true;
        };
        let Some(index) = events
            .checked_sub(first)
            .and_then(|i| usize::try_from(i).ok())
        else {
            return false;
        };
        let Some((_, b, h)) = self.marks.get(index) else {
            return false;
        };
        if *b != bytes || h != head {
            return false;
        }
        self.marks.drain(..index);
        true
    }
}

/// Checks the receipts of one stream against what this side sent and got.
#[derive(Debug)]
struct Checker {
    peer_id: String,
    token: String,
    sent: Seen,
    got: Seen,
    session: Option<String>,
    last_seq: u64,
    closed: bool,
}

impl Checker {
    fn new(peer_id: &str, token: &str) -> Self {
        Checker {
            peer_id: peer_id.to_string(),
            token: token.to_string(),
            sent: Seen::new(DIRECTION_IN),
            got: Seen::new(DIRECTION_OUT),
            session: None,
            last_seq: 0,
            closed: false,
        }
    }

    fn check(&mut self, receipt: ExecutionReceipt) -> StreamReceipt {
        let mut problems = receipt::problems(&receipt, Some(&self.peer_id), Some(&self.token));
        if problems.is_empty() && receipt.kind == receipt::KIND_START {
            problems.push("a start receipt in a tunnel stream".into());
        }
        if !problems.is_empty() {
            // Not signed by the node, or not for this token: its counters say nothing.
            return StreamReceipt {
                receipt,
                problems,
                sent_mismatch: false,
                got_mismatch: false,
            };
        }
        if self.closed {
            problems.push("a receipt after the close of the stream".into());
        }
        match &self.session {
            Some(session) if *session != receipt.session => {
                problems.push("the session of the stream changes".into());
            }
            Some(_) => {}
            None => self.session = Some(receipt.session.clone()),
        }
        if receipt.seq <= self.last_seq {
            problems.push(format!(
                "seq {} does not come after seq {}",
                receipt.seq, self.last_seq
            ));
        }
        self.last_seq = self.last_seq.max(receipt.seq);
        let sent_mismatch =
            !self
                .sent
                .matches(receipt.in_events, receipt.in_bytes, &receipt.in_head);
        let got_mismatch =
            !self
                .got
                .matches(receipt.out_events, receipt.out_bytes, &receipt.out_head);
        if receipt.kind == KIND_CLOSE {
            self.closed = true;
        }
        StreamReceipt {
            receipt,
            problems,
            sent_mismatch,
            got_mismatch,
        }
    }
}

fn lock(checker: &Mutex<Checker>) -> std::sync::MutexGuard<'_, Checker> {
    checker.lock().unwrap_or_else(PoisonError::into_inner)
}

/// The Buffers of the request: the handshake, then the payloads. Empty payloads are not
/// sent (a receiver drops a part with no bytes).
pub fn request_buffers(handshake: &TokenMessage, payloads: &[Vec<u8>]) -> Vec<Buffer> {
    let mut out: Vec<Buffer> =
        serialize_part(&Part::new(HANDSHAKE, handshake.encode_to_vec())).collect();
    for payload in payloads {
        for piece in payload.chunks(MAX_PAYLOAD) {
            out.extend(piece_buffers(piece));
        }
    }
    out
}

/// The Buffers of one message at index 0. The node sees one message, which is one event
/// of the `in` chain.
fn piece_buffers(piece: &[u8]) -> Vec<Buffer> {
    serialize_part(&Part::new(BYTES, piece.to_vec())).collect()
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

/// The call. Gives true if it ended because the reader went away (a cancel).
async fn run(
    channel: tonic::transport::Channel,
    handshake: TokenMessage,
    mut to_rx: mpsc::Receiver<Vec<u8>>,
    from_tx: &mpsc::Sender<Result<Vec<u8>, WireError>>,
    checker: &Arc<Mutex<Checker>>,
    sink: Option<&ReceiptSink>,
) -> Result<bool, WireError> {
    let (buffer_tx, buffer_rx) = mpsc::channel::<Buffer>(QUEUE);
    for buffer in request_buffers(&handshake, &[]) {
        buffer_tx
            .send(buffer)
            .await
            .map_err(|_| WireError::Call("the tunnel closed".to_string()))?;
    }
    let sent = checker.clone();
    let sender = tokio::spawn(async move {
        while let Some(payload) = to_rx.recv().await {
            for piece in payload.chunks(MAX_PAYLOAD) {
                // Into the chain before it goes: a checkpoint never counts a message
                // that this side has not counted yet.
                lock(&sent).sent.push(piece);
                for buffer in piece_buffers(piece) {
                    if buffer_tx.send(buffer).await.is_err() {
                        return;
                    }
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

    // Index 2 is accepted also when the client did not ask for it: a bee-rpc reader
    // refuses an index that it does not know, and the node can send receipts to all.
    let mut parser = Parser::new(ParseOptions::accepting([BYTES, RECEIPT]));
    loop {
        let message = tokio::select! {
            message = response.message() => message.map_err(status)?,
            // The reader is gone: dropping the response cancels the call.
            _ = from_tx.closed() => return Ok(true),
        };
        let Some(buffer) = message else { break };
        let parts = parser
            .push(buffer)
            .map_err(|e| WireError::Protocol(e.to_string()))?;
        if !forward(parts, from_tx, checker, sink).await {
            return Ok(true);
        }
    }
    let parts = parser
        .finish()
        .map_err(|e| WireError::Protocol(e.to_string()))?;
    if !forward(parts, from_tx, checker, sink).await {
        return Ok(true);
    }
    Ok(false)
}

/// Send the bytes of the parts to the reader, and the receipts to the sink. False when
/// the reader is gone.
async fn forward(
    parts: Vec<Part>,
    to: &mpsc::Sender<Result<Vec<u8>, WireError>>,
    checker: &Mutex<Checker>,
    sink: Option<&ReceiptSink>,
) -> bool {
    for part in parts {
        match part.index {
            BYTES => {
                // Every message is an event of the chain, an empty one too.
                lock(checker).got.push(&part.data);
                if !part.data.is_empty() && to.send(Ok(part.data)).await.is_err() {
                    return false;
                }
            }
            RECEIPT => {
                let checked = match ExecutionReceipt::decode(part.data.as_slice()) {
                    Ok(r) => lock(checker).check(r),
                    Err(e) => StreamReceipt {
                        receipt: ExecutionReceipt::default(),
                        problems: vec![format!("cannot read a receipt: {e}")],
                        sent_mismatch: false,
                        got_mismatch: false,
                    },
                };
                if let Some(sink) = sink {
                    sink(ReceiptEvent::Receipt(checked));
                }
            }
            _ => {}
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_handshake_comes_first_then_the_payloads_at_index_0() {
        let handshake = handshake("tok", 8080);
        assert!(handshake.receipts);
        let big = vec![7u8; MAX_PAYLOAD + 10];
        let buffers = request_buffers(
            &handshake,
            &[b"GET / HTTP/1.1\r\n\r\n".to_vec(), vec![], big],
        );
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
