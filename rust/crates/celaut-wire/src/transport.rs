//! The call interface that the typed calls use.

use std::future::Future;
use std::time::Duration;

use bee_rpc::frame::Part;

use crate::WireError;

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
}
