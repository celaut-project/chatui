//! The quotes of several nodes for one service, best first (`docs/celaut/balancer.md`).

use std::sync::Mutex;
use std::time::{Duration, Instant};

use celaut_balancer::{cost_mu, rank, Candidate, QuoteCache, QuoteKey, Ranked, Standing};
use celaut_proto::celaut::Configuration;
use celaut_proto::Message;
use celaut_wire::{Transport, WireError};

use crate::{ClientError, NodeSession};

/// The time limit of one quote, as in nodo.
pub const QUOTE_TIMEOUT: Duration = Duration::from_secs(10);

/// A node that gave no quote.
#[derive(Debug)]
pub struct QuoteFailure {
    /// The identity of the node.
    pub peer_id: String,
    /// Why.
    pub error: ClientError,
}

/// The answer of [`quotes`].
#[derive(Debug, Default)]
pub struct Quotes {
    /// The quotes, best first.
    pub ranked: Vec<Ranked>,
    /// The nodes that refused, failed or did not answer in time. They are not
    /// candidates.
    pub failures: Vec<QuoteFailure>,
}

/// Ask each node for the price of the service, all at the same time, and rank the
/// answers. A quote of the last 10 seconds comes from `cache`, so that a repeated
/// question makes no call (the node limits the calls of a client).
pub async fn quotes<T: Transport>(
    sessions: &[&NodeSession<T>],
    service_id: [u8; 32],
    configuration: &Configuration,
    cache: &Mutex<QuoteCache>,
) -> Quotes {
    let encoded = configuration.encode_to_vec();
    let asks = sessions.iter().map(|session| {
        let key = QuoteKey {
            peer_id: session.peer_id().to_string(),
            service_id,
            configuration: encoded.clone(),
        };
        async move {
            let cached = cache
                .lock()
                .ok()
                .and_then(|c| c.get(&key, Instant::now()));
            let quote = match cached {
                Some(quote) => Ok(quote),
                None => {
                    let ask = session.quote(service_id, configuration.clone());
                    match tokio::time::timeout(QUOTE_TIMEOUT, ask).await {
                        Err(_) => Err(ClientError::Wire(WireError::Timeout)),
                        Ok(Err(e)) => Err(e),
                        Ok(Ok(quote)) => {
                            if let Ok(mut c) = cache.lock() {
                                c.put(key, quote.clone(), Instant::now());
                            }
                            Ok(quote)
                        }
                    }
                }
            };
            (session, quote)
        }
    });
    let answers = futures::future::join_all(asks).await;

    let mut candidates = Vec::new();
    let mut failures = Vec::new();
    for (session, answer) in answers {
        match answer {
            Ok(quote) => match cost_mu(&quote) {
                Err(e) => failures.push(QuoteFailure {
                    peer_id: session.peer_id().to_string(),
                    error: ClientError::Amount(e),
                }),
                Ok(_) => candidates.push(Candidate {
                    peer_id: session.peer_id().to_string(),
                    quote,
                    mu_per_nano_erg: session.mu_per_nano_erg(),
                    standing: Standing::default(),
                }),
            },
            Err(error) => failures.push(QuoteFailure {
                peer_id: session.peer_id().to_string(),
                error,
            }),
        }
    }
    Quotes {
        ranked: rank(candidates),
        failures,
    }
}
