//! Celaut services on the free credit of a new client (milestone M2): quotes from
//! several nodes, start, a local port for a slot of the instance, and stop.
//!
//! The client id of each node and the started instances are in the database of the app
//! (`celaut_db`), one for all the wallets. A restart of the app keeps them: the next
//! call to the node uses the same client id, and an instance can be stopped after a
//! restart. Dart gets an instance id that is not the instance token, so the token never
//! leaves Rust. The connections and the local ports are in memory only.
//!
//! Starting and stopping need a full wallet in the app (`docs/celaut/ui.md`); the screen
//! checks that, because this side has no wallet.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use celaut_balancer::QuoteCache;
use celaut_client::db::{InstanceRecord, NodeRecord, QuoteRecord};
use celaut_client::session::parse_service_id;
use celaut_client::{new_client_id, quotes, ClientError, LocalPort, NodeSession};
use celaut_proto::celaut::{Amount, Configuration, EstimatedCost};
use celaut_wire::{ConnectOptions, Connection, TunnelOpener, WireError};
use once_cell::sync::Lazy;

use super::celaut::{error_of, invalid, CelautError, CelautErrorKind};
use super::celaut_db::{db, now_seconds, storage_error};
use super::celaut_env::{resolve as resolve_environment, EnvChoice};

pub(crate) type Session = Arc<NodeSession<Connection>>;

// The state stays in Rust: not part of the Dart API.
#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct State {
    /// The connections, by node address.
    sessions: HashMap<String, Session>,
    /// The local ports of each instance, by instance id.
    ports: HashMap<String, HashMap<u16, LocalPort>>,
}

static STATE: Lazy<Mutex<State>> = Lazy::new(|| Mutex::new(State::default()));
static QUOTES: Lazy<Mutex<QuoteCache>> = Lazy::new(|| Mutex::new(QuoteCache::new()));
/// One new session at a time, so that two calls do not make two clients on one node.
static OPENING: Lazy<tokio::sync::Mutex<()>> = Lazy::new(|| tokio::sync::Mutex::new(()));

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

pub(crate) fn key(address: &NodeAddress) -> String {
    format!("{}:{}", address.host.trim(), address.port)
}

/// The address of `host:port` text from the database.
pub(crate) fn address_of_key(text: &str) -> Option<NodeAddress> {
    let (host, port) = text.rsplit_once(':')?;
    let port = port.parse().ok().filter(|p| *p != 0)?;
    (!host.is_empty()).then(|| NodeAddress {
        host: host.to_string(),
        port,
    })
}

pub(crate) fn check(address: &NodeAddress) -> Result<(), CelautError> {
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
pub(crate) fn configuration(initial_mu: Option<String>) -> Result<Configuration, CelautError> {
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

/// The configuration of a start: the one of [`configuration`] with the environment
/// variables that the user chose. Only a start has them; a quote uses [`configuration`].
pub(crate) fn start_configuration(
    initial_mu: Option<String>,
    environment: &[EnvChoice],
) -> Result<Configuration, CelautError> {
    let mut configuration = configuration(initial_mu)?;
    configuration.environment_variables = resolve_environment(environment)?;
    Ok(configuration)
}

pub(crate) fn service_id(text: &str) -> Result<[u8; 32], CelautError> {
    parse_service_id(text)
        .ok_or_else(|| invalid("The service id must be 64 hexadecimal characters."))
}

/// Check the node on `connection` with the client id that the database has for it, or
/// with a new client (which gets the free credit of the node) that goes into the
/// database. The client id is in the database before the session is used, so that a
/// deposit to it is never lost.
///
/// If the node does not know the stored client id, the answer is a
/// [`CelautErrorKind::ClientUnknown`] error, and nothing changes: the user chooses
/// between [`celaut_new_client`] and a retry later (`docs/celaut/ui.md`, section 3).
pub(crate) async fn open_session(
    connection: Connection,
    address_key: &str,
) -> Result<NodeSession<Connection>, CelautError> {
    let _one = OPENING.lock().await;
    let db = db();
    let peer_id = connection.peer_id().to_string();
    let stored = db.read(|d| d.nodes.get(&peer_id).map(|n| n.client_id.clone()));
    let session = match stored.filter(|c| !c.is_empty()) {
        Some(client_id) => NodeSession::resume(connection, &peer_id, client_id, &*db)
            .await
            .map_err(error_of)?,
        None => new_client_session(connection, &peer_id).await?,
    };
    db.update(|d| d.note_address(&peer_id, address_key))
        .map_err(storage_error)?;
    Ok(session)
}

/// A new client on the node (`GenerateClient`), kept in the database at once. An old
/// client id of the node goes to its earlier ids. Then the balance of the new client is
/// read: it is the free credit of the node.
async fn new_client_session(
    connection: Connection,
    peer_id: &str,
) -> Result<NodeSession<Connection>, CelautError> {
    let db = db();
    let session = NodeSession::open(connection, peer_id, &*db)
        .await
        .map_err(error_of)?;
    let client_id = session.client_id().to_string();
    let keep = |free: Option<u128>| {
        db.update(|d| match d.nodes.get_mut(peer_id) {
            Some(node) if node.client_id == client_id => {
                node.free_credit_mu = free.map(|f| f.to_string());
            }
            Some(node) => node.replace_client(client_id.clone(), free),
            None => {
                d.nodes.insert(
                    peer_id.to_string(),
                    NodeRecord::new_client(client_id.clone(), free),
                );
            }
        })
        .map_err(storage_error)
    };
    keep(None)?;
    if let Ok(free) = session.balance().await {
        keep(Some(free))?;
    }
    Ok(session)
}

/// The client of the app on a node after [`celaut_new_client`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewClientView {
    pub peer_id: String,
    /// The free credit of the new client, in MU of the node. `None` is unknown.
    pub free_credit_mu: Option<String>,
    /// How many client ids of this node the app used before. Their balance is lost for
    /// the app.
    pub earlier_clients: u32,
}

/// Make a new client on the node, after the node forgot the stored client id and the
/// user chose "New client". The balance of the old client is lost for the app. The
/// deposits of the node and its limit stay in the database.
#[flutter_rust_bridge::frb]
pub async fn celaut_new_client(node: NodeAddress) -> Result<NewClientView, CelautError> {
    check(&node)?;
    let key = key(&node);
    let connection = Connection::connect(node.host.trim(), node.port, ConnectOptions::default())
        .await
        .map_err(|e| error_of(e.into()))?;
    let session = {
        let _one = OPENING.lock().await;
        let peer_id = connection.peer_id().to_string();
        new_client_session(connection, &peer_id).await?
    };
    let peer_id = session.peer_id().to_string();
    db().update(|d| d.note_address(&peer_id, &key))
        .map_err(storage_error)?;
    {
        // A connection at another address of this node still has the old client id.
        let mut s = state()?;
        s.sessions.retain(|_, open| open.peer_id() != peer_id);
        s.sessions.insert(key, Arc::new(session));
    }
    Ok(db().read(|d| {
        let node = d.nodes.get(&peer_id);
        NewClientView {
            peer_id: peer_id.clone(),
            free_credit_mu: node.and_then(|n| n.free_credit_mu.clone()),
            earlier_clients: node
                .map(|n| u32::try_from(n.earlier_client_ids.len()).unwrap_or(u32::MAX))
                .unwrap_or(0),
        }
    }))
}

/// The session of `address`: the open one, or a new connection with the client id of
/// the node from the database (or a new client on the node).
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
    let session = Arc::new(open_session(connection, &key).await?);
    // Another call may have made one at the same time: keep the first.
    Ok(state()?.sessions.entry(key).or_insert(session).clone())
}

/// Forget the connection of `address` after a connection error, so that the next call
/// connects again. The client id stays in the database.
pub(crate) fn forget_if_broken(address: &NodeAddress, error: &ClientError) {
    if matches!(error, ClientError::Wire(WireError::Connect(_))) {
        if let Ok(mut s) = STATE.lock() {
            s.sessions.remove(&key(address));
        }
    }
}

/// One quote, in the MU of the node and, if the node gives an ERG rate, in nanoERG. An
/// amount that the node did not give is empty (the screen shows "unknown", not 0).
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
    /// The balance of this client on the node, in MU of the node (empty if the app could
    /// not read it). The app compares it with `cost_mu` before it asks the node to start
    /// the service.
    pub client_balance_mu: String,
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

/// The amount as text, or empty if the node did not give it.
pub(crate) fn n(amount: &Option<Amount>) -> String {
    amount.as_ref().map(|a| a.n.clone()).unwrap_or_default()
}

pub(crate) fn quote_view(address: NodeAddress, peer_id: String, q: &EstimatedCost) -> QuoteView {
    QuoteView {
        address,
        peer_id,
        cost_mu: n(&q.cost),
        init_maintenance_mu: n(&q.init_maintenance_cost),
        max_maintenance_mu: n(&q.max_maintenance_cost),
        maintenance_seconds_loop: q.maintenance_seconds_loop,
        variance: q.variance,
        compared_nano_erg: None,
        client_balance_mu: String::new(),
    }
}

/// How long the app waits for the balance of the client on a node that already quoted.
const BALANCE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(5);

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
    let at = now_seconds();
    let stored = db().update(|d| {
        for r in &answer.ranked {
            d.add_quote(QuoteRecord {
                peer_id: r.candidate.peer_id.clone(),
                service_id: hex::encode(id),
                cost_mu: n(&r.candidate.quote.cost),
                at,
            });
        }
    });
    if let Err(e) = stored {
        tracing::warn!("the quotes are not stored: {e}");
    }
    // The balance of the client on each node that quoted, read at the same time. A node
    // that does not answer in time leaves it unknown; that never stops a launch.
    let balances = futures::future::join_all(answer.ranked.iter().map(|r| {
        let peer_id = r.candidate.peer_id.clone();
        let session = open
            .iter()
            .find(|(_, s)| s.peer_id() == peer_id)
            .map(|(_, s)| s.clone());
        async move {
            let session = session?;
            tokio::time::timeout(BALANCE_TIMEOUT, session.balance())
                .await
                .ok()?
                .ok()
        }
    }))
    .await;
    let quotes = answer
        .ranked
        .iter()
        .zip(balances)
        .map(|(r, balance)| {
            let peer_id = r.candidate.peer_id.clone();
            let mut view = quote_view(address_of(&peer_id), peer_id, &r.candidate.quote);
            view.compared_nano_erg = r.cost_nano_erg.map(|c| format!("{c:.0}"));
            view.client_balance_mu = balance.map(|b| b.to_string()).unwrap_or_default();
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
    /// The ports that follow the chat convention (`docs/celaut/chat.md`), a part of
    /// `slots`. The chat screen uses the first one.
    pub chat_slots: Vec<u16>,
    /// The balance of this client on the node after the start, in MU (empty if
    /// unknown).
    pub client_balance_mu: String,
}

/// Start the service on the node. The node charges the quote to the balance of the
/// client of the app on that node. The node runs it itself (no delegation). The
/// instance goes into the database of the app.
///
/// `environment` has the values of the environment variables of the service
/// (`docs/celaut/env-variables.md`). Only a start carries them: a quote never does, so
/// a node that only prices the service does not read them. A variable that the user
/// skipped is not in the list, so it is not in the configuration.
#[flutter_rust_bridge::frb]
pub async fn celaut_start_service(
    node: NodeAddress,
    service_id_hex: String,
    initial_mu: Option<String>,
    environment: Vec<EnvChoice>,
) -> Result<InstanceView, CelautError> {
    let id = service_id(&service_id_hex)?;
    let configuration = start_configuration(initial_mu, &environment)?;
    let session = session(&node).await?;
    let before = session.balance().await.ok();
    let started = match session.start(id, configuration).await {
        Ok(s) => s,
        Err(e) => {
            forget_if_broken(&node, &e);
            return Err(error_of(e));
        }
    };
    let after = session.balance().await.ok();
    let instance_id = new_client_id().map_err(error_of)?;
    let record = InstanceRecord {
        peer_id: session.peer_id().to_string(),
        address: key(&node),
        token: started.token.clone(),
        service_id: hex::encode(id),
        slots: started.slots(),
        chat_slots: started.chat_slots(),
        started_at: now_seconds(),
        start_charge_mu: match (before, after) {
            (Some(b), Some(a)) if b >= a => Some((b - a).to_string()),
            _ => None,
        },
        name: None,
        stopped_at: None,
        refund_mu: None,
    };
    let view = InstanceView {
        instance_id: instance_id.clone(),
        peer_id: record.peer_id.clone(),
        slots: record.slots.clone(),
        chat_slots: record.chat_slots.clone(),
        client_balance_mu: after.map(|b| b.to_string()).unwrap_or_default(),
    };
    db().update(|d| {
        d.instances.insert(instance_id, record);
    })
    .map_err(storage_error)?;
    Ok(view)
}

fn unknown_instance() -> CelautError {
    invalid("This instance is not known. It was deleted.")
}

fn stopped_instance() -> CelautError {
    invalid("This instance was stopped.")
}

/// The instance `instance_id` from the database, and a session on its node. A stopped
/// instance has none: the node does not run it.
async fn instance(instance_id: &str) -> Result<(Session, InstanceRecord), CelautError> {
    let record = db()
        .read(|d| d.instances.get(instance_id).cloned())
        .ok_or_else(unknown_instance)?;
    if record.stopped_at.is_some() {
        return Err(stopped_instance());
    }
    let address = address_of_key(&record.address).ok_or_else(|| CelautError {
        kind: CelautErrorKind::Storage,
        message: format!(
            "the address of the instance is not valid: {}",
            record.address
        ),
    })?;
    let session = session(&address).await?;
    if session.peer_id() != record.peer_id {
        return Err(CelautError {
            kind: CelautErrorKind::IdentityMismatch,
            message: format!(
                "the node at {} is now {}, not the node of the instance {}",
                record.address,
                session.peer_id(),
                record.peer_id
            ),
        });
    }
    Ok((session, record))
}

/// An instance in the database, without its token.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstanceListView {
    pub instance_id: String,
    pub peer_id: String,
    /// The address (`host:port`) of the node.
    pub address: String,
    pub service_id: String,
    pub slots: Vec<u16>,
    /// The ports that follow the chat convention, a part of `slots`.
    pub chat_slots: Vec<u16>,
    /// The time of the start, in Unix seconds.
    pub started_at: i64,
    /// What the start took from the balance of the client, in MU (empty if unknown).
    pub start_charge_mu: String,
    /// The name of the skill or the service file at the start (empty if unknown).
    pub name: String,
    /// The time of the stop, in Unix seconds; none while the instance runs.
    pub stopped_at: Option<i64>,
    /// What the node gave back at the stop, in MU (empty if unknown or not stopped).
    pub refund_mu: String,
}

/// The instances that the app started, whichever wallet was open: the ones that run,
/// and the stopped ones that the user did not delete.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_instances() -> Vec<InstanceListView> {
    db().read(|d| {
        d.instances
            .iter()
            .map(|(id, r)| InstanceListView {
                instance_id: id.clone(),
                peer_id: r.peer_id.clone(),
                address: r.address.clone(),
                service_id: r.service_id.clone(),
                slots: r.slots.clone(),
                chat_slots: r.chat_slots.clone(),
                started_at: r.started_at,
                start_charge_mu: r.start_charge_mu.clone().unwrap_or_default(),
                name: r.name.clone().unwrap_or_default(),
                stopped_at: r.stopped_at,
                refund_mu: r.refund_mu.clone().unwrap_or_default(),
            })
            .collect()
    })
}

/// Keep the name that the user saw at the start (the skill or the service file), so
/// that the list of conversations shows it after a restart. An empty name removes it.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_name_instance(instance_id: String, name: String) -> Result<(), CelautError> {
    let name = name.trim().to_string();
    let known = db()
        .update(|d| match d.instances.get_mut(&instance_id) {
            Some(r) => {
                r.name = (!name.is_empty()).then_some(name);
                true
            }
            None => false,
        })
        .map_err(storage_error)?;
    if known {
        Ok(())
    } else {
        Err(unknown_instance())
    }
}

/// Delete a stopped instance: take it out of the database. The user asks for it on a
/// stopped row of the list. An instance that was not stopped is refused and kept: the
/// app never forgets the token of an instance that may still run, even if its node
/// does not answer (`docs/celaut/decisions.md`).
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_forget_instance(instance_id: String) -> Result<(), CelautError> {
    let removed = db()
        .update(|d| match d.instances.get(&instance_id) {
            None => Err(unknown_instance()),
            Some(r) if r.stopped_at.is_none() => Err(invalid(
                "This instance was not stopped. Stop it before you delete it.",
            )),
            Some(_) => {
                d.instances.remove(&instance_id);
                Ok(())
            }
        })
        .map_err(storage_error)?;
    removed?;
    drop(state()?.ports.remove(&instance_id));
    Ok(())
}

/// A port on 127.0.0.1 for the slot of the instance. The same port while the
/// instance runs. Each TCP connection to it opens one `ServiceTunnel` stream, which
/// the node charges (`TUNNEL_OPEN_MU`): keep HTTP connections alive.
#[flutter_rust_bridge::frb]
pub async fn celaut_open_tunnel(instance_id: String, slot: u16) -> Result<u16, CelautError> {
    if let Some(port) = state()?.ports.get(&instance_id).and_then(|p| p.get(&slot)) {
        return Ok(port.port());
    }
    let (session, record) = instance(&instance_id).await?;
    if !record.slots.contains(&slot) {
        return Err(invalid("The instance has no such slot."));
    }
    let opener: Arc<dyn TunnelOpener> = Arc::new(session.transport().clone());
    let port = LocalPort::bind(opener, record.token.clone(), slot)
        .await
        .map_err(|e| CelautError {
            kind: CelautErrorKind::Unreachable,
            message: format!("cannot open a local port: {e}"),
        })?;
    let mut s = state()?;
    Ok(s.ports
        .entry(instance_id)
        .or_default()
        .entry(slot)
        .or_insert(port)
        .port())
}

/// The state of an instance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstanceStatusView {
    /// The balance of the instance on the node, in MU.
    pub instance_balance_mu: String,
    /// What the instance cost so far, in MU: what the start took from the client,
    /// less what the instance still has. Empty if unknown.
    pub cost_so_far_mu: String,
    /// How many tunnel streams the local ports opened (one per TCP connection).
    pub streams_opened: u64,
    /// The last error of a tunnel stream, if any.
    pub last_tunnel_error: Option<String>,
}

/// What an instance cost so far: the charge of the start less the balance that the
/// instance still has. `None` if the charge is not known.
pub(crate) fn cost_so_far(start_charge_mu: Option<&str>, instance_balance: u128) -> Option<u128> {
    let charge: u128 = start_charge_mu?.parse().ok()?;
    Some(charge.saturating_sub(instance_balance))
}

/// The balance of the instance and the use of its tunnels.
#[flutter_rust_bridge::frb]
pub async fn celaut_instance_status(
    instance_id: String,
) -> Result<InstanceStatusView, CelautError> {
    let (session, record) = instance(&instance_id).await?;
    let (streams, last) = {
        let s = state()?;
        let ports = s.ports.get(&instance_id);
        (
            ports.map_or(0, |p| p.values().map(LocalPort::streams_opened).sum()),
            ports.and_then(|p| p.values().find_map(LocalPort::last_error)),
        )
    };
    let balance = session
        .instance_balance(&record.token)
        .await
        .map_err(error_of)?;
    Ok(InstanceStatusView {
        instance_balance_mu: balance.to_string(),
        cost_so_far_mu: cost_so_far(record.start_charge_mu.as_deref(), balance)
            .map(|c| c.to_string())
            .unwrap_or_default(),
        streams_opened: streams,
        last_tunnel_error: last,
    })
}

/// What a stop gives back.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StopView {
    /// The unused balance of the instance that the node gave back to the client, in MU.
    pub refund_mu: String,
    /// The balance of the client after the stop, in MU (empty if unknown).
    pub client_balance_mu: String,
}

/// Close the local ports of the instance and stop it on the node. When the node
/// confirms the stop, the database marks the instance stopped, with the refund; it
/// stays there until the user deletes it ([`celaut_forget_instance`]).
#[flutter_rust_bridge::frb]
pub async fn celaut_stop_service(instance_id: String) -> Result<StopView, CelautError> {
    let (session, record) = instance(&instance_id).await?;
    drop(state()?.ports.remove(&instance_id));
    let refund = session.stop(&record.token).await.map_err(error_of)?;
    db().update(|d| {
        if let Some(r) = d.instances.get_mut(&instance_id) {
            r.stopped_at = Some(now_seconds());
            r.refund_mu = Some(refund.to_string());
        }
    })
    .map_err(storage_error)?;
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
        let err = celaut_start_service(node, id.clone(), None, vec![])
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        let node = NodeAddress {
            host: "127.0.0.1".into(),
            port: 1,
        };
        let err = celaut_start_service(node.clone(), "xyz".into(), None, vec![])
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        let err = celaut_quote_service(vec![], id.clone(), None)
            .await
            .unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        for bad in ["0", "-5", "1.5", "lots"] {
            let err = celaut_start_service(node.clone(), id.clone(), Some(bad.into()), vec![])
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
    fn an_instance_keeps_its_name() {
        let id = "name-test-instance".to_string();
        db().update(|d| {
            d.instances.insert(
                id.clone(),
                InstanceRecord {
                    peer_id: "ab".repeat(32),
                    token: "token".into(),
                    ..Default::default()
                },
            );
        })
        .unwrap();
        let name_of = |id: &str| {
            celaut_instances()
                .into_iter()
                .find(|i| i.instance_id == id)
                .map(|i| i.name)
        };
        assert_eq!(name_of(&id).as_deref(), Some(""));
        celaut_name_instance(id.clone(), " Echo chat ".into()).unwrap();
        assert_eq!(name_of(&id).as_deref(), Some("Echo chat"));
        celaut_name_instance(id.clone(), " ".into()).unwrap();
        assert_eq!(name_of(&id).as_deref(), Some(""));
        let err = celaut_name_instance("nope".into(), "x".into()).unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        drop(db().update(|d| d.instances.remove(&id)));
    }

    #[test]
    fn only_a_stopped_instance_can_be_deleted() {
        let id = "delete-test-instance".to_string();
        db().update(|d| {
            d.instances.insert(
                id.clone(),
                InstanceRecord {
                    peer_id: "ab".repeat(32),
                    token: "token".into(),
                    ..Default::default()
                },
            );
        })
        .unwrap();
        let listed = |id: &str| celaut_instances().into_iter().find(|i| i.instance_id == id);

        // A running instance, or one whose node does not answer: refused, and kept with
        // its token.
        let err = celaut_forget_instance(id.clone()).unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
        assert!(err.message.contains("not stopped"), "{}", err.message);
        assert_eq!(listed(&id).unwrap().stopped_at, None);
        assert_eq!(
            db().read(|d| d.instances[&id].token.clone()),
            "token".to_string()
        );

        // Stopped: it stays in the list, with the refund, until the user deletes it.
        db().update(|d| {
            let r = d.instances.get_mut(&id).unwrap();
            r.stopped_at = Some(42);
            r.refund_mu = Some("700".into());
        })
        .unwrap();
        let view = listed(&id).unwrap();
        assert_eq!((view.stopped_at, view.refund_mu.as_str()), (Some(42), "700"));
        celaut_forget_instance(id.clone()).unwrap();
        assert!(listed(&id).is_none());
        let err = celaut_forget_instance(id).unwrap_err();
        assert_eq!(err.kind, CelautErrorKind::InvalidInput);
    }

    #[tokio::test]
    async fn a_stopped_instance_is_not_asked_for() {
        let id = "stopped-test-instance".to_string();
        db().update(|d| {
            d.instances.insert(
                id.clone(),
                InstanceRecord {
                    peer_id: "ab".repeat(32),
                    address: "127.0.0.1:1".into(),
                    token: "token".into(),
                    slots: vec![8080],
                    stopped_at: Some(1),
                    ..Default::default()
                },
            );
        })
        .unwrap();
        for err in [
            celaut_stop_service(id.clone()).await.unwrap_err(),
            celaut_instance_status(id.clone()).await.unwrap_err(),
            celaut_open_tunnel(id.clone(), 8080).await.unwrap_err(),
        ] {
            assert_eq!(err.kind, CelautErrorKind::InvalidInput);
            assert_eq!(err.message, "This instance was stopped.");
        }
        celaut_forget_instance(id).unwrap();
    }

    #[test]
    fn only_a_start_carries_the_environment_variables() {
        let typed = |name: &str, text: &str| EnvChoice {
            name: name.into(),
            container: None,
            text: Some(text.into()),
        };
        // No choice: the same message as before the variables existed.
        assert_eq!(
            start_configuration(None, &[]).unwrap(),
            Configuration::default()
        );
        let c = start_configuration(Some("5".into()), &[typed("B", "2"), typed("A", "1")]).unwrap();
        assert_eq!(c.initial_mu, Some(Amount { n: "5".into() }));
        let names: Vec<_> = c.environment_variables.iter().map(|e| e.key.as_str()).collect();
        assert_eq!(names, ["B", "A"]);
        // A quote never has them.
        assert!(configuration(Some("5".into()))
            .unwrap()
            .environment_variables
            .is_empty());
        // A bad choice is refused before any node is asked.
        let err = start_configuration(None, &[typed("1", "x")]).unwrap_err();
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
