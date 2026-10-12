//! Shared helpers: the vectors from the nodo code, and a transport with fixed streams.
#![allow(dead_code)]

use std::collections::VecDeque;
use std::sync::Mutex;

use bee_rpc::buffer::buffer::Head;
use bee_rpc::buffer::Buffer;
use bee_rpc::frame::{serialize_part, ParseOptions, Parser, Part};
use celaut_proto::celaut::Peer;
use celaut_wire::{Transport, WireError};
use prost::Message;
use ring::signature::{Ed25519KeyPair, KeyPair};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct PowVector {
    pub challenge: String,
    pub difficulty: u32,
    pub solution: String,
    pub digest: String,
}

#[derive(Deserialize)]
pub struct PeerVector {
    pub name: String,
    pub peer_hex: String,
    pub public_key: String,
    pub ts: i64,
    pub digest: String,
    pub payload: String,
    pub signature: String,
}

#[derive(Deserialize)]
pub struct Vectors {
    pub identity_seed_hex: String,
    pub public_key: String,
    pub other_public_key: String,
    pub scheme_formal_hex: String,
    pub pow: Vec<PowVector>,
    pub peers: Vec<PeerVector>,
}

pub fn vectors() -> Vectors {
    serde_json::from_str(include_str!("../vectors/vectors.json")).expect("vectors.json")
}

impl PeerVector {
    pub fn peer(&self) -> Peer {
        let bytes = hex::decode(&self.peer_hex).expect("hex");
        Peer::decode(bytes.as_slice()).expect("Peer")
    }
}

/// Sign `peer` with the fixed identity of the vectors, as nodo does.
pub fn resign(peer: &mut Peer, v: &Vectors) {
    let seed = hex::decode(&v.identity_seed_hex).expect("seed");
    let pair = Ed25519KeyPair::from_seed_unchecked(&seed).expect("key");
    assert_eq!(hex::encode(pair.public_key().as_ref()), v.public_key);
    peer.public_key = v.public_key.clone();
    let digest = celaut_client::peer::content_digest(peer);
    let payload = celaut_client::peer::signed_payload(&peer.public_key, peer.ts, &digest);
    peer.signature = hex::encode(pair.sign(payload.as_bytes()).as_ref());
}

/// The Buffers of one message as a sender makes them.
pub fn stream_of(index: i32, message: &impl Message) -> Vec<Buffer> {
    serialize_part(&Part::new(index, message.encode_to_vec())).collect()
}

/// The same message cut in chunks of `size` bytes: head, chunks, separator.
pub fn chunked_stream_of(index: i32, message: &impl Message, size: usize) -> Vec<Buffer> {
    let data = message.encode_to_vec();
    let mut out = vec![Buffer {
        head: Some(Head {
            index,
            partitions: Vec::new(),
        }),
        ..Default::default()
    }];
    for piece in data.chunks(size) {
        out.push(Buffer {
            chunk: Some(piece.to_vec()),
            ..Default::default()
        });
    }
    out.push(Buffer {
        separator: Some(true),
        ..Default::default()
    });
    out
}

/// A transport that answers each call with the next fixed stream of Buffers. It parses
/// the stream with the bee-rpc parser, as the real call does, and records each request.
pub struct FixedStreams {
    answers: Mutex<VecDeque<Result<Vec<Buffer>, WireError>>>,
    pub requests: Mutex<Vec<(String, Vec<Part>)>>,
}

impl FixedStreams {
    pub fn new(answers: Vec<Vec<Buffer>>) -> Self {
        FixedStreams {
            answers: Mutex::new(answers.into_iter().map(Ok).collect()),
            requests: Mutex::new(Vec::new()),
        }
    }

    pub fn request(&self, n: usize) -> (String, Vec<Part>) {
        self.requests.lock().expect("lock")[n].clone()
    }

    pub fn calls(&self) -> usize {
        self.requests.lock().expect("lock").len()
    }
}

impl Transport for FixedStreams {
    async fn call(
        &self,
        method: &str,
        parts: Vec<Part>,
        accepted: &[i32],
    ) -> Result<Vec<Part>, WireError> {
        self.requests
            .lock()
            .expect("lock")
            .push((method.to_string(), parts));
        let answer = self
            .answers
            .lock()
            .expect("lock")
            .pop_front()
            .ok_or_else(|| WireError::Call("no more fixed answers".into()))??;
        let mut parser = Parser::new(ParseOptions::accepting(accepted.iter().copied()));
        let mut out = Vec::new();
        for buffer in answer {
            out.extend(
                parser
                    .push(buffer)
                    .map_err(|e| WireError::Call(e.to_string()))?,
            );
        }
        out.extend(
            parser
                .finish()
                .map_err(|e| WireError::Call(e.to_string()))?,
        );
        Ok(out)
    }
}
