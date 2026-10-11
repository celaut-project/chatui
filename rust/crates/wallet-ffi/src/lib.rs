#![allow(unexpected_cfgs)]

mod activity_tags;
#[cfg(test)]
mod activity_fixture_tests;

pub mod api;
mod api_ergopay_impl;
pub mod error;

mod frb_generated;
