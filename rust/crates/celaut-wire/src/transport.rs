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
