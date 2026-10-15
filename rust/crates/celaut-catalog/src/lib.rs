//! The skill catalog of Celaut (`docs/celaut/catalog.md`): skills, the services that
//! cover them, and the ranking of those services.
//!
//! The data is on Ergo, in "opinion boxes" of the reputation-system contract
//! (celaut-project/skills publishes and reads them):
//!
//! - [`parse`] turns the JSON of a box of the explorer into a [`parse::Skill`],
//!   [`parse::Coverage`], [`parse::Benchmark`] or [`parse::BenchResult`]. A box that cannot
//!   be read is left out: it is never an error.
//! - [`rank`] gives the services of a skill a score, as `skills:src/lib/scoreGlobal.ts`
//!   does.
//! - [`fetch`] asks an [`fetch::Explorer`] for the boxes and the reputations, and puts
//!   the two together. The crate makes no HTTP call itself: the app implements
//!   [`fetch::Explorer`].

pub mod fetch;
pub mod parse;
pub mod rank;

/// The fixed template hash of the reputation-system contract
/// (`docs/celaut/catalog.md`).
pub const ERGO_TREE_TEMPLATE_HASH: &str =
    "e84b95d84a30df33aa258fe2b9d24c3e75e27a67c6453983c19703029112d147";

/// The type NFT of a skill box (R4), on mainnet (`skills:src/lib/api.ts`).
pub const SKILL_TYPE: &str = "ffce59c01b9c0c245005f9c2daf817607e912a3ececd5f61aaba48d30230f60c";
/// The type NFT of a coverage box.
pub const COVERAGE_TYPE: &str = "1da6799e935cbb0fb14d359f06f23854c3d1bd509508948cc01b7b018dbbbdf5";
/// The type NFT of a benchmark box.
pub const BENCHMARK_TYPE: &str = "f6480184daf3b7750a58e58319e12adc5266bd986eec0f57ac451c995a30f54d";
/// The type NFT of a result box.
pub const RESULT_TYPE: &str = "49b26dc06b1680769477264d2e8e9bf561005236cde3097630bffcff631b7aef";
