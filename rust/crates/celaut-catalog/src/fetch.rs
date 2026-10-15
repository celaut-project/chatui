//! Read the catalog from the explorer. The crate makes no HTTP call: the app gives an
//! [`Explorer`] (`wallet-ffi` does, with reqwest) and this module asks it for the boxes
//! and the reputations.
//!
//! The reads are bounded: a skill costs one request for its coverages, one for its
//! benchmarks, one for the results of each benchmark, and at most
//! [`MAX_REPUTATION_TOKENS`] for the reputation of the publishers.

use std::collections::HashSet;
use std::future::Future;

use futures::stream::{self, StreamExt};
use serde_json::Value;

use crate::parse::{
    parse_benchmark, parse_coverage, parse_result, parse_skill, BenchResult, Benchmark, Coverage,
    Skill,
};
use crate::rank::{rank_services, Reputations, ServiceScore, SkillData};
use crate::{BENCHMARK_TYPE, COVERAGE_TYPE, RESULT_TYPE, SKILL_TYPE};

/// How many requests run at the same time.
pub const MAX_PARALLEL: usize = 4;

/// The most reputation tokens that one skill reads. A token over the limit has no
/// reputation (0) in the ranking.
pub const MAX_REPUTATION_TOKENS: usize = 64;

/// Why the catalog could not be read.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CatalogError {
    /// The explorer did not answer, or its answer is not usable.
    #[error("the explorer did not answer: {0}")]
    Explorer(String),
    /// The skill id is not 64 hexadecimal characters.
    #[error("the skill id is not 64 hexadecimal characters")]
    BadSkillId,
}

/// The explorer of Ergo.
pub trait Explorer: Sync {
    /// Every unspent box of the reputation-system contract that has `type_nft` in R4
    /// and, if there is a `subject`, that id in R5. All the pages.
    fn boxes(
        &self,
        type_nft: &str,
        subject: Option<&str>,
    ) -> impl Future<Output = Result<Vec<Value>, CatalogError>> + Send;

    /// The reputation of a profile: the sum of the values, in nanoERG, of the unspent
    /// boxes that hold `token_id`.
    fn token_value(&self, token_id: &str) -> impl Future<Output = Result<f64, CatalogError>> + Send;
}

/// The skills of the catalog, in the order of the explorer.
pub async fn load_skills<E: Explorer>(explorer: &E) -> Result<Vec<Skill>, CatalogError> {
    let boxes = explorer.boxes(SKILL_TYPE, None).await?;
    let mut seen = HashSet::new();
    Ok(boxes
        .iter()
        .filter_map(parse_skill)
        .filter(|s| seen.insert(s.box_id.clone()))
        .collect())
}

/// The coverages, the benchmarks and the results of a skill.
pub async fn load_skill_data<E: Explorer>(
    explorer: &E,
    skill_box_id: &str,
) -> Result<SkillData, CatalogError> {
    let id = skill_id(skill_box_id)?;
    let coverages: Vec<Coverage> = explorer
        .boxes(COVERAGE_TYPE, Some(&id))
        .await?
        .iter()
        .filter_map(parse_coverage)
        .collect();
    let benchmarks: Vec<Benchmark> = explorer
        .boxes(BENCHMARK_TYPE, Some(&id))
        .await?
        .iter()
        .filter_map(parse_benchmark)
        .filter(|b| b.skill_box_id == id)
        .collect();
    // Owned ids, not references: a closure over `&Benchmark` makes the future fail the
    // `Send` check of flutter_rust_bridge ("implementation of `FnOnce` is not general
    // enough").
    let ids: Vec<String> = benchmarks.iter().map(|b| b.id.clone()).collect();
    let per_benchmark: Vec<Result<Vec<Value>, CatalogError>> = stream::iter(ids)
        .map(|id| async move { explorer.boxes(RESULT_TYPE, Some(&id)).await })
        .buffered(MAX_PARALLEL)
        .collect()
        .await;
    let mut results: Vec<BenchResult> = Vec::new();
    for boxes in per_benchmark {
        results.extend(boxes?.iter().filter_map(parse_result));
    }
    Ok(SkillData {
        coverages,
        benchmarks,
        results,
    })
}

/// The reputation of the publishers in `data`. A token that the explorer does not
/// answer for, and a token over [`MAX_REPUTATION_TOKENS`], is left out: it has 0.
pub async fn load_reputations<E: Explorer>(explorer: &E, data: &SkillData) -> Reputations {
    let mut tokens: Vec<String> = Vec::new();
    let mut seen = HashSet::new();
    let profiles = data
        .coverages
        .iter()
        .map(|c| &c.profile)
        .chain(data.benchmarks.iter().map(|b| &b.profile))
        .chain(data.results.iter().map(|r| &r.profile));
    for token in profiles.flatten() {
        if tokens.len() < MAX_REPUTATION_TOKENS && seen.insert(token.clone()) {
            tokens.push(token.clone());
        }
    }
    let values: Vec<(String, Result<f64, CatalogError>)> = stream::iter(tokens)
        .map(|token| async move {
            let value = explorer.token_value(&token).await;
            (token, value)
        })
        .buffer_unordered(MAX_PARALLEL)
        .collect()
        .await;
    Reputations(
        values
            .into_iter()
            .filter_map(|(token, value)| Some((token, value.ok()?)))
            .collect(),
    )
}

/// The services of a skill with their scores, best first.
pub async fn load_skill_services<E: Explorer>(
    explorer: &E,
    skill_box_id: &str,
) -> Result<Vec<ServiceScore>, CatalogError> {
    let data = load_skill_data(explorer, skill_box_id).await?;
    let reputations = load_reputations(explorer, &data).await;
    Ok(rank_services(&data, &reputations))
}

fn skill_id(id: &str) -> Result<String, CatalogError> {
    let id = id.trim().to_ascii_lowercase();
    if id.len() == 64 && id.bytes().all(|b| b.is_ascii_hexdigit()) {
        Ok(id)
    } else {
        Err(CatalogError::BadSkillId)
    }
}
