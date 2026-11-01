//! HTTP requests to a web slot of an instance through the tunnel, with no local port
//! (step 2 of #79). The WebView of the app answers the requests of a page with these
//! calls, so nothing listens on 127.0.0.1.
//!
//! An open `HttpTunnel` stays in Rust, in a table, and Dart holds only its handle (a
//! number that is not reused). The token of the instance and the node connection never
//! reach Dart. Requests of one handle share one `ServiceTunnel` stream, so the node
//! charges `TUNNEL_OPEN_MU` once for the page. Close the handle when the page closes.
//! A handle is also closed when its instance is stopped or deleted.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use celaut_client::{HttpTunnel, HttpTunnelError};
use celaut_wire::TunnelOpener;
use once_cell::sync::Lazy;

use super::celaut::{invalid, CelautError, CelautErrorKind};
use super::celaut_service::instance;

/// The open tunnels by handle, with the instance of each.
static TUNNELS: Lazy<Mutex<HashMap<u64, (String, Arc<HttpTunnel>)>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));
/// The next handle. Handles start at 1 and are never reused, so a closed handle stays
/// unknown.
static NEXT: AtomicU64 = AtomicU64::new(1);

fn tunnels(
) -> Result<std::sync::MutexGuard<'static, HashMap<u64, (String, Arc<HttpTunnel>)>>, CelautError> {
    TUNNELS.lock().map_err(|_| CelautError {
        kind: CelautErrorKind::Storage,
        message: "the state of the HTTP tunnels is broken".into(),
    })
}

/// A header of a request or an answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpHeader {
    pub name: String,
    pub value: String,
}

/// The answer to a request, whole.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpAnswer {
    pub status: u16,
    /// In the order received.
    pub headers: Vec<HttpHeader>,
    pub body: Vec<u8>,
}

fn error_of_http(e: HttpTunnelError) -> CelautError {
    let kind = match &e {
        HttpTunnelError::InvalidRequest(_) => CelautErrorKind::InvalidInput,
        HttpTunnelError::Tunnel(_) => CelautErrorKind::Unreachable,
        HttpTunnelError::Timeout(_) => CelautErrorKind::Timeout,
        HttpTunnelError::Http(_) | HttpTunnelError::BodyTooLarge { .. } => {
            CelautErrorKind::Protocol
        }
    };
    CelautError {
        kind,
        message: e.to_string(),
    }
}

fn register(instance_id: String, tunnel: HttpTunnel) -> Result<u64, CelautError> {
    let handle = NEXT.fetch_add(1, Ordering::Relaxed);
    tunnels()?.insert(handle, (instance_id, Arc::new(tunnel)));
    Ok(handle)
}

/// Open an HTTP tunnel to `slot` of the instance. Gives its handle. No stream opens
/// until the first request. The slot must be one of the instance. Close the handle with
/// [`celaut_http_close`].
#[flutter_rust_bridge::frb]
pub async fn celaut_http_open(instance_id: String, slot: u16) -> Result<u64, CelautError> {
    let (session, record) = instance(&instance_id).await?;
    if !record.slots.contains(&slot) {
        return Err(invalid("The instance has no such slot."));
    }
    let opener: Arc<dyn TunnelOpener> = Arc::new(session.transport().clone());
    let sink = super::celaut_receipts::sink(instance_id.clone());
    let tunnel = HttpTunnel::new(opener, record.token.clone(), slot, Some(sink));
    register(instance_id, tunnel)
}

/// Send one request and give the whole answer. `path_and_query` starts with `/`.
/// `Host` is `localhost` if not given; `Content-Length`, `Transfer-Encoding` and
/// `Connection` are not taken from `headers`. A closed handle is an `InvalidInput` error.
/// The body of the answer is limited to 64 MiB.
#[flutter_rust_bridge::frb]
pub async fn celaut_http_request(
    handle: u64,
    method: String,
    path_and_query: String,
    headers: Vec<HttpHeader>,
    body: Vec<u8>,
) -> Result<HttpAnswer, CelautError> {
    let tunnel = tunnels()?
        .get(&handle)
        .map(|(_, t)| t.clone())
        .ok_or_else(|| invalid("This HTTP tunnel is closed."))?;
    let headers: Vec<(String, String)> = headers.into_iter().map(|h| (h.name, h.value)).collect();
    let answer = tunnel
        .request(&method, &path_and_query, &headers, body)
        .await
        .map_err(error_of_http)?;
    Ok(HttpAnswer {
        status: answer.status,
        headers: answer
            .headers
            .into_iter()
            .map(|(name, value)| HttpHeader { name, value })
            .collect(),
        body: answer.body,
    })
}

/// Close the tunnel: its stream ends and the handle is not valid any more. A handle
/// that is closed already, or never was, is not an error. A request that is in flight
/// finishes first.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_http_close(handle: u64) {
    let removed = tunnels().ok().and_then(|mut t| t.remove(&handle));
    drop(removed);
}

/// Close the tunnels of an instance (it stopped or was deleted).
pub(crate) fn close_instance(instance_id: &str) {
    let removed: Vec<_> = match tunnels() {
        Ok(mut t) => {
            let handles: Vec<u64> = t
                .iter()
                .filter(|(_, (id, _))| id == instance_id)
                .map(|(h, _)| *h)
                .collect();
            handles.iter().filter_map(|h| t.remove(h)).collect()
        }
        Err(_) => return,
    };
    drop(removed);
}

#[cfg(test)]
mod tests {
    use super::*;
    use celaut_wire::{ReceiptSink, Tunnel};
    use tokio::sync::mpsc;

    /// Answers each request with a fixed answer, on one stream.
    struct Fake;

    impl TunnelOpener for Fake {
        fn open_tunnel(&self, _token: &str, _slot: u16, _r: Option<ReceiptSink>) -> Tunnel {
            let (to_service, mut to_rx) = mpsc::channel::<Vec<u8>>(16);
            let (from_tx, from_service) = mpsc::channel(16);
            tokio::spawn(async move {
                while to_rx.recv().await.is_some() {
                    let answer = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nX-A: b\r\n\r\nhi";
                    if from_tx.send(Ok(answer.to_vec())).await.is_err() {
                        break;
                    }
                }
            });
            Tunnel {
                to_service,
                from_service,
            }
        }
    }

    fn fake_handle(instance: &str) -> u64 {
        let opener: Arc<dyn TunnelOpener> = Arc::new(Fake);
        register(
            instance.into(),
            HttpTunnel::new(opener, "t".into(), 80, None),
        )
        .unwrap()
    }

    async fn get(handle: u64, path: &str) -> Result<HttpAnswer, CelautError> {
        celaut_http_request(handle, "GET".into(), path.into(), vec![], vec![]).await
    }

    #[tokio::test]
    async fn open_refuses_an_unknown_instance() {
        let err = celaut_http_open("http-nope".into(), 80).await.unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
    }

    #[tokio::test]
    async fn a_handle_answers_until_it_is_closed() {
        let handle = fake_handle("http-life");
        let answer = get(handle, "/").await.unwrap();
        assert_eq!(answer.status, 200);
        assert_eq!(answer.body, b"hi");
        assert!(answer.headers.contains(&HttpHeader {
            name: "x-a".into(),
            value: "b".into()
        }));
        // The same stream carries the next request.
        assert_eq!(get(handle, "/b").await.unwrap().status, 200);
        celaut_http_close(handle);
        let err = get(handle, "/").await.unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        assert_eq!(err.message, "This HTTP tunnel is closed.");
        // Closing again, or a handle that never was, is fine.
        celaut_http_close(handle);
        celaut_http_close(u64::MAX);
    }

    #[tokio::test]
    async fn a_bad_request_is_refused_and_the_handle_stays() {
        let handle = fake_handle("http-bad");
        for (method, path) in [("GE T", "/"), ("GET", "no-slash"), ("GET", "/a b")] {
            let err = celaut_http_request(handle, method.into(), path.into(), vec![], vec![])
                .await
                .unwrap_err();
            assert_eq!(err.kind, CelautErrorKind::InvalidInput, "{method} {path}");
        }
        let err = celaut_http_request(
            handle,
            "GET".into(),
            "/".into(),
            vec![HttpHeader {
                name: "bad name".into(),
                value: "x".into(),
            }],
            vec![],
        )
        .await
        .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        assert_eq!(get(handle, "/").await.unwrap().status, 200);
        celaut_http_close(handle);
    }

    #[tokio::test]
    async fn the_tunnels_of_an_instance_close_together() {
        let a = fake_handle("http-inst-a");
        let b = fake_handle("http-inst-a");
        let other = fake_handle("http-inst-b");
        close_instance("http-inst-a");
        assert!(get(a, "/").await.is_err());
        assert!(get(b, "/").await.is_err());
        assert_eq!(get(other, "/").await.unwrap().status, 200);
        celaut_http_close(other);
    }

    #[test]
    fn handles_are_not_reused() {
        let a = NEXT.fetch_add(1, Ordering::Relaxed);
        let b = NEXT.fetch_add(1, Ordering::Relaxed);
        assert!(b > a && a >= 1);
    }
}
