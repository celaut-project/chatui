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
        async { Err(WireError::Protocol("this transport cannot relay Buffers".into())) }
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
        async { Err(WireError::Protocol("this transport cannot give raw Buffers".into())) }
    }
}
