//! The call interface that the typed calls use.

use std::future::Future;

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
}
