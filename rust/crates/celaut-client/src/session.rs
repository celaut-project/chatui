//! One node and one client id on it (milestone M2).
//!
//! A [`NodeSession`] makes the client id once ([`crate::obtain_client_id`]), checks the
//! advertisement of the node with it, and keeps both. The node gives a new client its
//! free credit (`free_tier.CREDIT_MU_PER_NEW_CLIENT`), so each new session starts with
//! that balance.

use celaut_balancer::{amount, erg_rate};
use celaut_proto::celaut::{Configuration, EstimatedCost, Instance, Payment};
use celaut_wire::gateway::{
    generate_deposit_token, get_metrics, get_service_estimated_cost,
    get_service_estimated_cost_with_service, get_service_raw, payable, start_service,
    stop_service, ServiceRequest,
};
use celaut_wire::Transport;

use crate::deposit::{check_deposit_token, ErgPayment};
use crate::{fetch_node_info_as, obtain_client_id, ClientError, NodeInfo, PeerStore};

/// A service instance that this client started.
#[derive(Debug, Clone, PartialEq)]
pub struct StartedInstance {
    /// The instance token. It is a bearer secret: whoever has it can stop the
    /// instance and use its balance.
    pub token: String,
    /// The ports of the instance and their addresses.
    pub instance: Instance,
}

impl StartedInstance {
    /// The internal ports of the instance (`Instance.uri_slot[].internal_port`), the
    /// slots that `ServiceTunnel` accepts.
    pub fn slots(&self) -> Vec<u16> {
        self.instance
            .uri_slot
            .iter()
            .filter_map(|s| u16::try_from(s.internal_port).ok())
            .collect()
    }

    /// The slots that follow the chat convention (`docs/celaut/chat.md`, section 2), in
    /// the order of `Service.Api`. The client uses the first one.
    pub fn chat_slots(&self) -> Vec<u16> {
        chat_slots(&self.instance)
    }
}

/// The tag of the HTTP protocol in a protocol stack.
const HTTP_TAG: &str = "http";
/// The tag of the chat convention in a protocol stack. It has no version.
const CHAT_TAG: &str = "chat";

/// The slots of `instance` that follow the chat convention: a port of `Service.Api`
/// with the transport `tcp`, and a protocol stack that has `http` and, above it, `chat`
/// (the stack is written bottom to top). A slot counts only if the instance has that
/// port, because `ServiceTunnel` accepts only the ports of the instance.
pub fn chat_slots(instance: &Instance) -> Vec<u16> {
    let Some(api) = instance.api.as_ref() else {
        return Vec::new();
    };
    let has = |tags: &[String], tag: &str| tags.iter().any(|t| t == tag);
    let mut found = Vec::new();
    for slot in &api.slot {
        let tcp = slot.transport.as_ref().is_some_and(|t| has(&t.tags, "tcp"));
        let http = slot.protocol_stack.iter().position(|p| has(&p.tags, HTTP_TAG));
        let chat = slot.protocol_stack.iter().rposition(|p| has(&p.tags, CHAT_TAG));
        let follows = matches!((http, chat), (Some(h), Some(c)) if h < c);
        let Ok(port) = u16::try_from(slot.port) else {
            continue;
        };
        let reachable = instance
            .uri_slot
            .iter()
            .any(|u| u16::try_from(u.internal_port) == Ok(port));
        if tcp && follows && reachable && !found.contains(&port) {
            found.push(port);
        }
    }
    found
}

/// A client on one node.
#[derive(Debug)]
pub struct NodeSession<T: Transport> {
    transport: T,
    client_id: String,
    info: NodeInfo,
}

impl<T: Transport> NodeSession<T> {
    /// Make a client id on the node and check its advertisement. `peer_id` is the
    /// identity that the TLS certificate proved.
    pub async fn open(
        transport: T,
        peer_id: &str,
        store: &dyn PeerStore,
    ) -> Result<Self, ClientError> {
        let client_id = obtain_client_id(&transport).await?;
        let info = fetch_node_info_as(&transport, &client_id, peer_id, store).await?;
        Ok(NodeSession {
            transport,
            client_id,
            info,
        })
    }

    /// A session with the client id that the app already has on the node, so that its
    /// balance on the node stays usable. The advertisement is checked as in
    /// [`NodeSession::open`].
    pub async fn resume(
        transport: T,
        peer_id: &str,
        client_id: String,
        store: &dyn PeerStore,
    ) -> Result<Self, ClientError> {
        let info = fetch_node_info_as(&transport, &client_id, peer_id, store).await?;
        Ok(NodeSession {
            transport,
            client_id,
            info,
        })
    }

    /// The identity of the node.
    pub fn peer_id(&self) -> &str {
        &self.info.peer_id
    }

    /// The checked advertisement of the node.
    pub fn info(&self) -> &NodeInfo {
        &self.info
    }

    /// The client id on this node. A bearer secret, as an instance token.
    pub fn client_id(&self) -> &str {
        &self.client_id
    }

    /// The transport to the node.
    pub fn transport(&self) -> &T {
        &self.transport
    }

    /// The MU per nanoERG of the node, if it gives a rate for ERG.
    pub fn mu_per_nano_erg(&self) -> Option<u128> {
        erg_rate(&self.info.peer).ok()
    }

    /// The request for a service, with the guard of a light client (no delegation).
    pub fn request(&self, service_id: [u8; 32], configuration: Configuration) -> ServiceRequest {
        ServiceRequest {
            client_id: self.client_id.clone(),
            service_id,
            configuration,
        }
    }

    /// `GetServiceEstimatedCost`.
    pub async fn quote(
        &self,
        service_id: [u8; 32],
        configuration: Configuration,
    ) -> Result<EstimatedCost, ClientError> {
        let request = self.request(service_id, configuration);
        Ok(get_service_estimated_cost(&self.transport, &request).await?)
    }

    /// `GetService`: the Buffers of the service, as the node sends them, for another
    /// node (`crate::package`). A node that does not have the service gives nothing.
    pub async fn get_service(&self, service_id: [u8; 32]) -> Result<celaut_wire::Buffers, ClientError> {
        Ok(get_service_raw(&self.transport, &self.client_id, service_id).await?)
    }

    /// `GetServiceEstimatedCost` with the service: the node stores `service`, and gives
    /// the price. After it, the node has the service, and the other calls need only its
    /// hash.
    pub async fn quote_with_service(
        &self,
        service_id: [u8; 32],
        configuration: Configuration,
        service: celaut_wire::Buffers,
    ) -> Result<EstimatedCost, ClientError> {
        let request = self.request(service_id, configuration);
        Ok(get_service_estimated_cost_with_service(&self.transport, &request, service).await?)
    }

    /// `StartService`. The node charges the cost to the balance of this client.
    pub async fn start(
        &self,
        service_id: [u8; 32],
        configuration: Configuration,
    ) -> Result<StartedInstance, ClientError> {
        let request = self.request(service_id, configuration);
        let answer = start_service(&self.transport, &request).await?;
        Ok(StartedInstance {
            token: answer.token,
            instance: answer.instance.unwrap_or_default(),
        })
    }

    /// `StopService`. Gives the refund in MU of the node: the unused balance of the
    /// instance, which goes back to this client.
    pub async fn stop(&self, token: &str) -> Result<u128, ClientError> {
        let refund = stop_service(&self.transport, token).await?;
        Ok(amount(refund.amount.as_ref())?)
    }

    /// `GetMetrics` for this client: its balance in MU of the node.
    pub async fn balance(&self) -> Result<u128, ClientError> {
        let metrics = get_metrics(&self.transport, &self.client_id).await?;
        Ok(amount(metrics.balance.as_ref())?)
    }

    /// `GetMetrics` for an instance: its balance in MU of the node.
    pub async fn instance_balance(&self, token: &str) -> Result<u128, ClientError> {
        let metrics = get_metrics(&self.transport, token).await?;
        Ok(amount(metrics.balance.as_ref())?)
    }

    /// The ERG payment contract of the node, from the checked advertisement.
    pub fn erg_payment(&self) -> Result<ErgPayment, ClientError> {
        Ok(ErgPayment::of(&self.info.peer)?)
    }

    /// `GenerateDepositToken` for this client. The node only writes the token in its
    /// database; nothing goes on a ledger. The token is checked before it is given,
    /// because the wallet writes it on the ledger.
    pub async fn deposit_token(&self) -> Result<String, ClientError> {
        let token = generate_deposit_token(&self.transport, &self.client_id).await?;
        check_deposit_token(&token)?;
        Ok(token)
    }

    /// `Payable` for this client. The node checks a deposit token once only: call it
    /// when the deposit box is visible on the explorer of the node.
    pub async fn payable(&self, payment: &Payment) -> Result<(), ClientError> {
        Ok(payable(&self.transport, &self.client_id, payment).await?)
    }
}

/// A service id from 64 hexadecimal characters.
pub fn parse_service_id(text: &str) -> Option<[u8; 32]> {
    let text = text.trim();
    if text.len() != 64 {
        return None;
    }
    let bytes = hex::decode(text.to_ascii_lowercase()).ok()?;
    bytes.try_into().ok()
}

#[cfg(test)]
mod chat_slot_tests {
    use super::*;
    use celaut_proto::celaut::instance::UriSlot;
    use celaut_proto::celaut::service::api::{Protocol, Slot};
    use celaut_proto::celaut::service::Api;

    fn protocol(tags: &[&str]) -> Protocol {
        Protocol {
            tags: tags.iter().map(|t| t.to_string()).collect(),
            ..Default::default()
        }
    }

    fn slot(port: i32, transport: &str, stack: &[&[&str]]) -> Slot {
        Slot {
            port,
            transport: Some(protocol(&[transport])),
            protocol_stack: stack.iter().map(|tags| protocol(tags)).collect(),
            ..Default::default()
        }
    }

    /// An instance with these `Service.Api` slots, and every port in `uri_slot`.
    fn instance(slots: Vec<Slot>) -> Instance {
        let uri_slot = slots
            .iter()
            .map(|s| UriSlot {
                internal_port: s.port,
                uri: Vec::new(),
            })
            .collect();
        Instance {
            api: Some(Api {
                slot: slots,
                ..Default::default()
            }),
            uri_slot,
        }
    }

    #[test]
    fn http_then_chat_is_a_chat_slot() {
        let i = instance(vec![slot(8080, "tcp", &[&["http"], &["chat"]])]);
        assert_eq!(chat_slots(&i), vec![8080]);
    }

    #[test]
    fn the_slots_keep_the_order_of_the_api_and_other_slots_are_left_out() {
        let i = instance(vec![
            slot(22, "tcp", &[&["ssh"]]),
            slot(9000, "tcp", &[&["http", "json"], &["chat", "text"]]),
            slot(8080, "tcp", &[&["tls"], &["http"], &["chat"]]),
            slot(8081, "tcp", &[&["http"]]),
        ]);
        assert_eq!(chat_slots(&i), vec![9000, 8080]);
    }

    #[test]
    fn chat_below_http_or_without_http_is_not_a_chat_slot() {
        let i = instance(vec![
            slot(1, "tcp", &[&["chat"], &["http"]]),
            slot(2, "tcp", &[&["chat"]]),
            slot(3, "tcp", &[&["grpc"], &["chat"]]),
        ]);
        assert!(chat_slots(&i).is_empty());
    }

    #[test]
    fn a_udp_slot_is_not_a_chat_slot() {
        let i = instance(vec![slot(8080, "udp", &[&["http"], &["chat"]])]);
        assert!(chat_slots(&i).is_empty());
        let mut no_transport = slot(8080, "tcp", &[&["http"], &["chat"]]);
        no_transport.transport = None;
        assert!(chat_slots(&instance(vec![no_transport])).is_empty());
    }

    #[test]
    fn a_port_that_the_instance_does_not_have_is_left_out() {
        let mut i = instance(vec![slot(8080, "tcp", &[&["http"], &["chat"]])]);
        i.uri_slot.clear();
        assert!(chat_slots(&i).is_empty());
    }

    #[test]
    fn a_port_that_is_not_a_u16_is_left_out() {
        let i = instance(vec![
            slot(0x1_0000, "tcp", &[&["http"], &["chat"]]),
            slot(-1, "tcp", &[&["http"], &["chat"]]),
        ]);
        assert!(chat_slots(&i).is_empty());
    }

    #[test]
    fn a_repeated_port_counts_once() {
        let i = instance(vec![
            slot(8080, "tcp", &[&["http"], &["chat"]]),
            slot(8080, "tcp", &[&["http"], &["chat"]]),
        ]);
        assert_eq!(chat_slots(&i), vec![8080]);
    }

    #[test]
    fn an_instance_with_no_api_has_no_chat_slot() {
        let i = Instance {
            api: None,
            uri_slot: Vec::new(),
        };
        assert!(chat_slots(&i).is_empty());
    }

    #[test]
    fn started_instance_gives_its_chat_slots() {
        let started = StartedInstance {
            token: "t".into(),
            instance: instance(vec![slot(8080, "tcp", &[&["http"], &["chat"]])]),
        };
        assert_eq!(started.chat_slots(), vec![8080]);
        assert_eq!(started.slots(), vec![8080]);
    }
}
