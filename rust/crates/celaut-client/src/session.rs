//! One node and one client id on it (milestone M2).
//!
//! A [`NodeSession`] makes the client id once ([`crate::obtain_client_id`]), checks the
//! advertisement of the node with it, and keeps both. The node gives a new client its
//! free credit (`free_tier.CREDIT_MU_PER_NEW_CLIENT`), so each new session starts with
//! that balance.

use celaut_balancer::{amount, erg_rate};
use celaut_proto::celaut::{Configuration, EstimatedCost, Instance, Payment};
use celaut_wire::gateway::{
    generate_deposit_token, get_metrics, get_service_estimated_cost, payable, start_service,
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
