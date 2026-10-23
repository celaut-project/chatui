//! The call interface that the typed calls use.

use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

use bee_rpc::buffer::Buffer;
use bee_rpc::frame::Part;
use tokio_stream::Stream;

use crate::WireError;

/// Buffers that are already framed, for a relay: the input of
/// [`Transport::call_buffers`] and the answer of [`Transport::call_raw`].
pub type Buffers = Pin<Box<dyn Stream<Item = Result<Buffer, WireError>> + Send>>;

/// Counts what a call takes from a stream of Buffers: the Buffers, their bytes (the
/// encoded length of each Buffer, as it goes in a gRPC message), and if the stream came
/// to its end. Clone it to share it.
///
/// A call takes a Buffer of the service when it sends it, so the count is what the node
/// got, or one Buffer more if the call stopped while that Buffer was on its way.
#[derive(Clone, Debug, Default)]
pub struct SendCounter {
    state: std::sync::Arc<CounterState>,
}

#[derive(Debug, Default)]
struct CounterState {
    buffers: std::sync::atomic::AtomicU64,
    bytes: std::sync::atomic::AtomicU64,
    ended: std::sync::atomic::AtomicBool,
}

impl SendCounter {
    pub fn new() -> Self {
        SendCounter::default()
    }

    /// `input`, counted.
    pub fn wrap(&self, input: Buffers) -> Buffers {
        Box::pin(Counted {
            input,
            counter: self.clone(),
        })
    }

    /// The Buffers taken so far.
    pub fn buffers(&self) -> u64 {
        self.state
            .buffers
            .load(std::sync::atomic::Ordering::Acquire)
    }

    /// The bytes of the Buffers taken so far.
    pub fn bytes(&self) -> u64 {
        self.state.bytes.load(std::sync::atomic::Ordering::Acquire)
    }

    /// True if the call took the stream to its end.
    pub fn ended(&self) -> bool {
        self.state.ended.load(std::sync::atomic::Ordering::Acquire)
    }
}

struct Counted {
    input: Buffers,
    counter: SendCounter,
}

impl Stream for Counted {
    type Item = Result<Buffer, WireError>;

    fn poll_next(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Self::Item>> {
        use std::sync::atomic::Ordering;
        let item = std::task::ready!(self.input.as_mut().poll_next(cx));
        let state = &self.counter.state;
        match &item {
            Some(Ok(buffer)) => {
                state.buffers.fetch_add(1, Ordering::AcqRel);
                state
                    .bytes
                    .fetch_add(prost::Message::encoded_len(buffer) as u64, Ordering::AcqRel);
            }
            Some(Err(_)) => {}
            None => state.ended.store(true, Ordering::Release),
        }
        std::task::Poll::Ready(item)
    }
}

/// Asks the node to drop the rest of a block: the id is the hash of its expansion, from its
/// marker. True if the request was queued. See [`Transport::call_raw_skippable`].
pub type Skipper = std::sync::Arc<dyn Fn(&[u8]) -> bool + Send + Sync>;

/// The answer of [`Transport::call_raw_skippable`].
pub struct RawAnswer {
    /// The Buffers of the answer, as they are.
    pub buffers: Buffers,
    /// Asks the node to skip a block, if the transport can. A reader that does not need
    /// the content of a block (the filesystem of a service, to read what is around it) calls
    /// it with the id of the marker that it just read. The node drops the Buffers of the
    /// block that it has not sent, and still sends its end marker, once. The Buffers that
    /// were already on the way arrive too.
    pub skipper: Option<Skipper>,
}

/// Sends the parts of one request to a method of the Gateway and returns the parts
/// of the answer. `method` is the short name, for example `"GetPeerInfo"`.
///
/// `accepted` lists the head indices that the answer may have. An answer with another
/// index is an error (as in the Python reference).
pub trait Transport: Send + Sync {
    /// One call.
    fn call(
        &self,
        method: &str,
        parts: Vec<Part>,
        accepted: &[i32],
    ) -> impl Future<Output = Result<Vec<Part>, WireError>> + Send;

    /// [`Transport::call`] with its own time limit, for a call that can take long
    /// (`StartService`). A transport with no time limit ignores it.
    fn call_with_timeout(
        &self,
        method: &str,
        parts: Vec<Part>,
        accepted: &[i32],
        timeout: Duration,
    ) -> impl Future<Output = Result<Vec<Part>, WireError>> + Send {
        let _ = timeout;
        self.call(method, parts, accepted)
    }

    /// Send Buffers that are already framed, as they are, and return the parts of the
    /// answer. If `input` gives an error, the node gets markers that make it refuse the
    /// request (a cut input is never taken for a complete one), and the call returns
    /// that error. A transport that cannot do it gives an error.
    fn call_buffers(
        &self,
        method: &str,
        input: Buffers,
        accepted: &[i32],
        timeout: Duration,
    ) -> impl Future<Output = Result<Vec<Part>, WireError>> + Send {
        let _ = (method, input, accepted, timeout);
        async {
            Err(WireError::Protocol(
                "this transport cannot relay Buffers".into(),
            ))
        }
    }

    /// Send the parts of `head`, then the Buffers of `service` as they are (a service with
    /// the indices 4, 5 and 6 of `StartService`), and return the parts of the answer.
    ///
    /// The node can answer before the end of `service`: nodo does when the head or the
    /// Metadata names a service that it already has. Then a transport that can see it
    /// stops: it does not send the rest of `service`, and it resets the request (as
    /// nodo's own client drops the call), so the node never gets a clean end after a
    /// cut service. A failure of `service` is the same as in
    /// [`Transport::call_buffers`]: the node gets the cancel markers.
    ///
    /// The default sends `head` and all of `service` with [`Transport::call_buffers`].
    fn call_with_service(
        &self,
        method: &str,
        head: Vec<Part>,
        service: Buffers,
        accepted: &[i32],
        timeout: Duration,
    ) -> impl Future<Output = Result<Vec<Part>, WireError>> + Send {
        use tokio_stream::StreamExt;
        let head: Vec<Result<Buffer, WireError>> = head
            .iter()
            .flat_map(|p| bee_rpc::frame::serialize_part(p).collect::<Vec<_>>())
            .map(Ok)
            .collect();
        let input: Buffers = Box::pin(tokio_stream::iter(head).chain(service));
        self.call_buffers(method, input, accepted, timeout)
    }

    /// Send `parts`, and give the Buffers of the answer as they are, without
    /// rebuilding the blocks. A transport that cannot do it gives an error.
    fn call_raw(
        &self,
        method: &str,
        parts: Vec<Part>,
        timeout: Duration,
    ) -> impl Future<Output = Result<Buffers, WireError>> + Send {
        let _ = (method, parts, timeout);
        async {
            Err(WireError::Protocol(
                "this transport cannot give raw Buffers".into(),
            ))
        }
    }

    /// [`Transport::call_raw`], and a way to ask the node to skip a block. A transport that
    /// cannot ask gives the same Buffers and no skipper: the reader then gets the whole
    /// answer.
    fn call_raw_skippable(
        &self,
        method: &str,
        parts: Vec<Part>,
        timeout: Duration,
    ) -> impl Future<Output = Result<RawAnswer, WireError>> + Send {
        let raw = self.call_raw(method, parts, timeout);
        async move {
            Ok(RawAnswer {
                buffers: raw.await?,
                skipper: None,
            })
        }
    }
}
