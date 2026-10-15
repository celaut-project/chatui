//! The calls that move a whole service: `GetService` as raw Buffers, and a quote that
//! carries the service. A fake transport records what the node would get.

use std::sync::Mutex;
use std::time::Duration;

use bee_rpc::buffer::Buffer;
use bee_rpc::frame::{serialize_part, ParseOptions, Parser, Part};
use celaut_proto::celaut::metadata::hash_tag::Hash;
use celaut_proto::celaut::{Client, Configuration, EstimatedCost};
use celaut_wire::gateway::{
    get_service_estimated_cost_with_service, get_service_raw, ServiceRequest, SERVICE_TRANSFER_TIMEOUT,
    SHA3_256_TYPE,
};
use celaut_wire::{Buffers, Transport, WireError};
use prost::Message;
use tokio_stream::StreamExt;

#[derive(Default)]
struct Fake {
    /// What the node got: method, parts (parsed) and the time limit.
    seen: Mutex<Vec<(String, Vec<Part>, Duration)>>,
    /// The answer of `call_raw`.
    raw: Mutex<Vec<Buffer>>,
}

impl Transport for Fake {
    async fn call(&self, _: &str, _: Vec<Part>, _: &[i32]) -> Result<Vec<Part>, WireError> {
        Err(WireError::Protocol("not used".into()))
    }

    async fn call_buffers(
        &self,
        method: &str,
        mut input: Buffers,
        accepted: &[i32],
        timeout: Duration,
    ) -> Result<Vec<Part>, WireError> {
        let mut parser = Parser::new(ParseOptions::accepting([1, 2, 3, 4, 5, 6]));
        let mut parts = Vec::new();
        while let Some(item) = input.next().await {
            parts.extend(parser.push(item?).unwrap());
        }
        parts.extend(parser.finish().unwrap());
        self.seen
            .lock()
            .unwrap()
            .push((method.to_string(), parts, timeout));
        assert_eq!(accepted, [1]);
        let cost = EstimatedCost::default();
        Ok(vec![Part::new(1, cost.encode_to_vec())])
    }

    async fn call_raw(
        &self,
        method: &str,
        parts: Vec<Part>,
        timeout: Duration,
    ) -> Result<Buffers, WireError> {
        self.seen
            .lock()
            .unwrap()
            .push((method.to_string(), parts, timeout));
        let raw = self.raw.lock().unwrap().clone();
        Ok(Box::pin(tokio_stream::iter(raw.into_iter().map(Ok))))
    }
}

const ID: [u8; 32] = [9u8; 32];

#[tokio::test]
async fn get_service_asks_with_the_hash_and_the_client_and_gives_the_buffers_as_they_are() {
    let fake = Fake::default();
    let answer: Vec<Buffer> = serialize_part(&Part::new(6, b"service".to_vec())).collect();
    *fake.raw.lock().unwrap() = answer.clone();
    let mut got = get_service_raw(&fake, "client-1", ID).await.unwrap();
    let mut buffers = Vec::new();
    while let Some(b) = got.next().await {
        buffers.push(b.unwrap());
    }
    assert_eq!(buffers, answer);

    let seen = fake.seen.lock().unwrap();
    let (method, parts, timeout) = &seen[0];
    assert_eq!(method, "GetService");
    assert_eq!(*timeout, SERVICE_TRANSFER_TIMEOUT);
    assert_eq!(parts.iter().map(|p| p.index).collect::<Vec<_>>(), [1, 2]);
    let hash = Hash::decode(parts[0].data.as_slice()).unwrap();
    assert_eq!((hash.r#type.as_slice(), hash.value.as_slice()), (SHA3_256_TYPE.as_slice(), ID.as_slice()));
    assert_eq!(Client::decode(parts[1].data.as_slice()).unwrap().client_id, "client-1");
}

#[tokio::test]
async fn a_quote_with_the_service_sends_the_request_first_then_the_service() {
    let fake = Fake::default();
    let request = ServiceRequest {
        client_id: "client-1".into(),
        service_id: ID,
        configuration: Configuration {
            initial_mu: Some(celaut_proto::celaut::Amount { n: "1".into() }),
            ..Default::default()
        },
    };
    let mut service: Vec<Buffer> = serialize_part(&Part::new(5, b"metadata".to_vec())).collect();
    service.extend(serialize_part(&Part::new(6, vec![3u8; 3 * bee_rpc::CHUNK_SIZE])));
    let input: Buffers = Box::pin(tokio_stream::iter(service.into_iter().map(Ok)));
    get_service_estimated_cost_with_service(&fake, &request, input)
        .await
        .unwrap();

    let seen = fake.seen.lock().unwrap();
    let (method, parts, timeout) = &seen[0];
    assert_eq!(method, "GetServiceEstimatedCost");
    assert_eq!(*timeout, SERVICE_TRANSFER_TIMEOUT);
    // Client, guard, configuration and hash, as a quote without the service; then the
    // Metadata and the Service.
    assert_eq!(parts.iter().map(|p| p.index).collect::<Vec<_>>(), [1, 2, 3, 4, 5, 6]);
    assert_eq!(parts[5].data.len(), 3 * bee_rpc::CHUNK_SIZE);
}

#[tokio::test]
async fn an_error_of_the_service_stream_is_the_error_of_the_quote() {
    struct Failing;
    impl Transport for Failing {
        async fn call(&self, _: &str, _: Vec<Part>, _: &[i32]) -> Result<Vec<Part>, WireError> {
            unreachable!()
        }
        async fn call_buffers(
            &self,
            _: &str,
            mut input: Buffers,
            _: &[i32],
            _: Duration,
        ) -> Result<Vec<Part>, WireError> {
            while let Some(item) = input.next().await {
                item?;
            }
            Ok(vec![])
        }
    }
    let request = ServiceRequest {
        client_id: "c".into(),
        service_id: ID,
        configuration: Configuration::default(),
    };
    let input: Buffers = Box::pin(tokio_stream::iter(vec![Err(WireError::Relay("cut".into()))]));
    let error = get_service_estimated_cost_with_service(&Failing, &request, input)
        .await
        .unwrap_err();
    assert!(matches!(error, WireError::Relay(ref t) if t == "cut"), "{error}");
}

#[tokio::test]
async fn a_transport_that_cannot_relay_says_so() {
    struct Plain;
    impl Transport for Plain {
        async fn call(&self, _: &str, _: Vec<Part>, _: &[i32]) -> Result<Vec<Part>, WireError> {
            Ok(vec![])
        }
    }
    assert!(get_service_raw(&Plain, "c", ID).await.is_err());
}
