//! Celaut services on the free credit of a new client (milestone M2): quotes from
//! several nodes, start, a local port for a slot of the instance, and stop.
//!
//! The state lives in Rust for the life of the process: one session (client id) per
//! node address, and the started instances. Dart gets an instance id that is not the
//! instance token, so the token never leaves Rust. Nothing is stored on disk yet: when
//! the app stops, the instances keep running on the node until their balance ends.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use celaut_balancer::QuoteCache;
use celaut_client::session::parse_service_id;
use celaut_client::{
    new_client_id, quotes, ClientError, LocalPort, MemoryPeerStore, NodeSession, StartedInstance,
};
use celaut_proto::celaut::{Amount, Configuration, EstimatedCost};
use celaut_wire::{ConnectOptions, Connection, TunnelOpener, WireError};
use once_cell::sync::Lazy;

use super::celaut::{error_of, invalid, CelautError, CelautErrorKind};

pub(crate) type Session = Arc<NodeSession<Connection>>;

// The state stays in Rust: not part of the Dart API.
#[flutter_rust_bridge::frb(ignore)]
struct Running {
    session: Session,
    started: StartedInstance,
    ports: HashMap<u16, LocalPort>,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct State {
    sessions: HashMap<String, Session>,
    instances: HashMap<String, Running>,
}

static STATE: Lazy<Mutex<State>> = Lazy::new(|| Mutex::new(State::default()));
static QUOTES: Lazy<Mutex<QuoteCache>> = Lazy::new(|| Mutex::new(QuoteCache::new()));
static PEERS: Lazy<MemoryPeerStore> = Lazy::new(MemoryPeerStore::new);

fn state() -> Result<std::sync::MutexGuard<'static, State>, CelautError> {
    STATE.lock().map_err(|_| CelautError {
        kind: CelautErrorKind::Storage,
        message: "the state of the Celaut services is broken".into(),
    })
}

/// The address of a node.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeAddress {
    /// A name or an IP address without brackets.
    pub host: String,
    pub port: u16,
}

fn key(address: &NodeAddress) -> String {
    format!("{}:{}", address.host, address.port)
}

fn check(address: &NodeAddress) -> Result<(), CelautError> {
    let host = address.host.trim();
    if host.is_empty() || host.contains(|c: char| c.is_whitespace() || c == '/') {
        return Err(invalid(
            "The host is empty or has characters that a host cannot have.",
        ));
    }
    if address.port == 0 {
        return Err(invalid("The port must be from 1 to 65535."));
    }
    Ok(())
}

/// The configuration of a start: the defaults of the node, and the balance of the
/// instance at the start if `initial_mu` is given. The default of a node is one hour of
/// the resources of the service, which can be more than the free credit of a client.
fn configuration(initial_mu: Option<String>) -> Result<Configuration, CelautError> {
    let Some(text) = initial_mu
        .map(|t| t.trim().to_string())
        .filter(|t| !t.is_empty())
    else {
        return Ok(Configuration::default());
    };
    let amount = Amount { n: text };
    match celaut_balancer::amount(Some(&amount)) {
        Ok(0) | Err(_) => Err(invalid(
            "The start balance must be a whole number of MU, more than 0.",
        )),
        Ok(_) => Ok(Configuration {
            initial_mu: Some(amount),
            ..Default::default()
        }),
    }
}

fn service_id(text: &str) -> Result<[u8; 32], CelautError> {
    parse_service_id(text)
        .ok_or_else(|| invalid("The service id must be 64 hexadecimal characters."))
}

/// The session of `address`: the one that exists, or a new client on the node. A new
/// client gets the free credit of the node.
pub(crate) async fn session(address: &NodeAddress) -> Result<Session, CelautError> {
    check(address)?;
    let key = key(address);
    if let Some(s) = state()?.sessions.get(&key) {
        return Ok(s.clone());
    }
    let connection =
        Connection::connect(address.host.trim(), address.port, ConnectOptions::default())
            .await
            .map_err(|e| error_of(e.into()))?;
    let peer_id = connection.peer_id().to_string();
    let session = NodeSession::open(connection, &peer_id, &*PEERS)
        .await
        .map_err(error_of)?;
    let session = Arc::new(session);
    // Another call may have made one at the same time: keep the first.
    Ok(state()?.sessions.entry(key).or_insert(session).clone())
}

/// Forget the session of `address` after a connection error, so that the next call
/// connects again. Its balance on the node is lost with its client id.
pub(crate) fn forget_if_broken(address: &NodeAddress, error: &ClientError) {
    if matches!(error, ClientError::Wire(WireError::Connect(_))) {
        if let Ok(mut s) = STATE.lock() {
            s.sessions.remove(&key(address));
        }
    }
}

/// One quote, in the MU of the node and, if the node gives an ERG rate, in nanoERG.
#[derive(Debug, Clone, PartialEq)]
pub struct QuoteView {
    pub address: NodeAddress,
    pub peer_id: String,
    /// The cost of the start (charged by StartService), in MU of the node.
    pub cost_mu: String,
    pub init_maintenance_mu: String,
    pub max_maintenance_mu: String,
    pub maintenance_seconds_loop: i32,
    pub variance: f32,
    /// The cost for the comparison in nanoERG, or `None` if the node gives no ERG rate
    /// (then its price is not compared, and it comes last).
    pub compared_nano_erg: Option<String>,
}

/// A node that gave no quote.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuoteFailureView {
    pub address: NodeAddress,
    pub kind: CelautErrorKind,
    pub message: String,
}

/// The quotes, best first, and the nodes that failed.
#[derive(Debug, Clone, PartialEq)]
pub struct QuotesView {
    pub quotes: Vec<QuoteView>,
    pub failures: Vec<QuoteFailureView>,
}

fn n(amount: &Option<Amount>) -> String {
    amount
        .as_ref()
        .map(|a| a.n.clone())
        .unwrap_or_else(|| "0".into())
}

fn quote_view(address: NodeAddress, peer_id: String, q: &EstimatedCost) -> QuoteView {
    QuoteView {
        address,
        peer_id,
        cost_mu: n(&q.cost),
        init_maintenance_mu: n(&q.init_maintenance_cost),
        max_maintenance_mu: n(&q.max_maintenance_cost),
        maintenance_seconds_loop: q.maintenance_seconds_loop,
        variance: q.variance,
        compared_nano_erg: None,
    }
}

/// Ask each node for the price of the service, and give the quotes best first
/// (`docs/celaut/balancer.md`). The nodes must already have the service.
#[flutter_rust_bridge::frb]
pub async fn celaut_quote_service(
    nodes: Vec<NodeAddress>,
    service_id_hex: String,
    initial_mu: Option<String>,
) -> Result<QuotesView, CelautError> {
    let id = service_id(&service_id_hex)?;
    let configuration = configuration(initial_mu)?;
    if nodes.is_empty() {
        return Err(invalid("Give at least one node."));
    }
    let mut failures = Vec::new();
    let mut open: Vec<(NodeAddress, Session)> = Vec::new();
    let connects = nodes
        .iter()
        .map(|a| async move { (a.clone(), session(a).await) });
    for (address, result) in futures::future::join_all(connects).await {
        match result {
            Ok(s) => open.push((address, s)),
            Err(e) => failures.push(QuoteFailureView {
                address,
                kind: e.kind,
                message: e.message,
            }),
        }
    }
    let sessions: Vec<&NodeSession<Connection>> = open.iter().map(|(_, s)| s.as_ref()).collect();
    let answer = quotes(&sessions, id, &configuration, &QUOTES).await;
    let address_of = |peer_id: &str| {
        open.iter()
            .find(|(_, s)| s.peer_id() == peer_id)
            .map(|(a, _)| a.clone())
            .unwrap_or(NodeAddress {
                host: String::new(),
                port: 0,
            })
    };
    for failure in answer.failures {
        let address = address_of(&failure.peer_id);
        forget_if_broken(&address, &failure.error);
        let e = error_of(failure.error);
        failures.push(QuoteFailureView {
            address,
            kind: e.kind,
            message: e.message,
        });
    }
    let quotes = answer
        .ranked
        .iter()
        .map(|r| {
            let peer_id = r.candidate.peer_id.clone();
            let mut view = quote_view(address_of(&peer_id), peer_id, &r.candidate.quote);
            view.compared_nano_erg = r.cost_nano_erg.map(|c| format!("{c:.0}"));
            view
        })
        .collect();
    Ok(QuotesView { quotes, failures })
}

/// A started instance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstanceView {
    /// A local id for the calls below. It is not the instance token.
    pub instance_id: String,
    pub peer_id: String,
    /// The internal ports of the instance, for [`celaut_open_tunnel`].
    pub slots: Vec<u16>,
    /// The balance of this client on the node after the start, in MU.
    pub client_balance_mu: String,
}

/// Start the service on the node. The node charges the quote to the free credit of the
/// client. The node runs it itself (no delegation).
#[flutter_rust_bridge::frb]
pub async fn celaut_start_service(
    node: NodeAddress,
    service_id_hex: String,
    initial_mu: Option<String>,
) -> Result<InstanceView, CelautError> {
    let id = service_id(&service_id_hex)?;
    let configuration = configuration(initial_mu)?;
    let session = session(&node).await?;
    let started = match session.start(id, configuration).await {
        Ok(s) => s,
        Err(e) => {
            forget_if_broken(&node, &e);
            return Err(error_of(e));
        }
    };
    let balance = session
        .balance()
        .await
        .map(|b| b.to_string())
        .unwrap_or_default();
    let instance_id = new_client_id().map_err(error_of)?;
    let view = InstanceView {
        instance_id: instance_id.clone(),
        peer_id: session.peer_id().to_string(),
        slots: started.slots(),
        client_balance_mu: balance,
    };
    state()?.instances.insert(
        instance_id,
        Running {
            session,
            started,
            ports: HashMap::new(),
        },
    );
    Ok(view)
}

fn unknown_instance() -> CelautError {
    invalid("This instance is not known. It was stopped, or the app restarted.")
}

/// A port on 127.0.0.1 for the slot of the instance. The same port while the
/// instance runs. Each TCP connection to it opens one `ServiceTunnel` stream, which
/// the node charges (`TUNNEL_OPEN_MU`): keep HTTP connections alive.
#[flutter_rust_bridge::frb]
pub async fn celaut_open_tunnel(instance_id: String, slot: u16) -> Result<u16, CelautError> {
    let (opener, token) = {
        let s = state()?;
        let running = s.instances.get(&instance_id).ok_or_else(unknown_instance)?;
        if let Some(port) = running.ports.get(&slot) {
            return Ok(port.port());
        }
        if !running.started.slots().contains(&slot) {
            return Err(invalid("The instance has no such slot."));
        }
        let opener: Arc<dyn TunnelOpener> = Arc::new(running.session.transport().clone());
        (opener, running.started.token.clone())
    };
    let port = LocalPort::bind(opener, token, slot)
        .await
        .map_err(|e| CelautError {
            kind: CelautErrorKind::Unreachable,
            message: format!("cannot open a local port: {e}"),
        })?;
    let mut s = state()?;
    let running = s
        .instances
        .get_mut(&instance_id)
        .ok_or_else(unknown_instance)?;
    Ok(running.ports.entry(slot).or_insert(port).port())
}

/// The state of an instance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstanceStatusView {
    /// The balance of the instance on the node, in MU.
    pub instance_balance_mu: String,
    /// How many tunnel streams the local ports opened (one per TCP connection).
    pub streams_opened: u64,
    /// The last error of a tunnel stream, if any.
    pub last_tunnel_error: Option<String>,
}

/// The balance of the instance and the use of its tunnels.
#[flutter_rust_bridge::frb]
pub async fn celaut_instance_status(
    instance_id: String,
) -> Result<InstanceStatusView, CelautError> {
    let (session, token, streams, last) = {
        let s = state()?;
        let running = s.instances.get(&instance_id).ok_or_else(unknown_instance)?;
        let streams = running.ports.values().map(LocalPort::streams_opened).sum();
        let last = running.ports.values().find_map(LocalPort::last_error);
        (
            running.session.clone(),
            running.started.token.clone(),
            streams,
            last,
        )
    };
    let balance = session.instance_balance(&token).await.map_err(error_of)?;
    Ok(InstanceStatusView {
        instance_balance_mu: balance.to_string(),
        streams_opened: streams,
        last_tunnel_error: last,
    })
}

/// What a stop gives back.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StopView {
    /// The unused balance of the instance that the node gave back to the client, in MU.
    pub refund_mu: String,
    /// The balance of the client after the stop, in MU.
    pub client_balance_mu: String,
}

/// Close the local ports of the instance and stop it on the node.
#[flutter_rust_bridge::frb]
pub async fn celaut_stop_service(instance_id: String) -> Result<StopView, CelautError> {
    let running = state()?
        .instances
        .remove(&instance_id)
        .ok_or_else(unknown_instance)?;
    let Running {
        session,
        started,
        ports,
    } = running;
    drop(ports);
    let refund = session.stop(&started.token).await.map_err(error_of)?;
    let balance = session
        .balance()
        .await
        .map(|b| b.to_string())
        .unwrap_or_default();
    Ok(StopView {
        refund_mu: refund.to_string(),
        client_balance_mu: balance,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn bad_input_is_refused_before_any_connection() {
        let node = NodeAddress {
            host: "localhost".into(),
            port: 0,
        };
        let id = "ab".repeat(32);
        let err = celaut_start_service(node, id.clone(), None)
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        let node = NodeAddress {
            host: "127.0.0.1".into(),
            port: 1,
        };
        let err = celaut_start_service(node.clone(), "xyz".into(), None)
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        let err = celaut_quote_service(vec![], id.clone(), None)
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        for bad in ["0", "-5", "1.5", "lots"] {
            let err = celaut_start_service(node.clone(), id.clone(), Some(bad.into()))
                .await
                .unwrap_err();
            assert_eq!(err.kind, CelautErrorKind::InvalidInput, "{bad}");
        }
        let err = celaut_open_tunnel("nope".into(), 80).await.unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        let err = celaut_stop_service("nope".into()).await.unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
    }

    #[test]
    fn the_start_balance_goes_in_the_configuration() {
        assert_eq!(configuration(None).unwrap(), Configuration::default());
        assert_eq!(
            configuration(Some(" ".into())).unwrap(),
            Configuration::default()
        );
        let c = configuration(Some(" 1000000 ".into())).unwrap();
        assert_eq!(c.initial_mu.unwrap().n, "1000000");
    }

    #[tokio::test]
    async fn a_closed_node_is_a_failure_of_the_quote() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let node = NodeAddress {
            host: "127.0.0.1".into(),
            port,
        };
        let answer = celaut_quote_service(vec![node.clone()], "ab".repeat(32), None)
            .await
            .unwrap();
        assert!(answer.quotes.is_empty());
        assert_eq!(answer.failures.len(), 1);
        assert_eq!(answer.failures[0].address, node);
        assert_eq!(answer.failures[0].kind, CelautErrorKind::Unreachable);
    }
}
