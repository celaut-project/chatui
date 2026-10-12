//! Proof of work against the known answers of `client_pow.py`.

mod common;

use celaut_client::pow::{challenge_difficulty, pow_digest, solve_pow, verify_solution};
use celaut_client::{pow, ClientError};

#[test]
fn digest_and_solution_equal_nodo() {
    let vectors = common::vectors();
    assert_eq!(vectors.pow.len(), 4);
    for v in &vectors.pow {
        assert_eq!(
            pow_digest(&v.challenge, &v.solution),
            v.digest,
            "difficulty {}",
            v.difficulty
        );
        assert_eq!(v.digest.len(), 128); // blake2b-512
        assert!(v.digest.ends_with(&"0".repeat(v.difficulty as usize)));
        assert!(verify_solution(&v.challenge, &v.solution, v.difficulty));
        // The first counter that works: the same one as nodo.
        assert_eq!(solve_pow(&v.challenge, v.difficulty).unwrap(), v.solution);
        assert_eq!(challenge_difficulty(&v.challenge), Some(v.difficulty));
    }
}

#[test]
fn wrong_solution_is_not_verified() {
    let v = &common::vectors().pow[2];
    let other = (v.solution.parse::<u64>().unwrap() + 1).to_string();
    assert!(!verify_solution(&v.challenge, &other, v.difficulty));
    assert!(!verify_solution(&v.challenge, "", v.difficulty));
    // A harder rule is not met by the solution of an easier one, in general.
    assert!(verify_solution(&v.challenge, "", 0));
}

#[test]
fn difficulty_zero_and_limit() {
    assert_eq!(solve_pow("any", 0).unwrap(), "");
    assert!(matches!(
        solve_pow("any", pow::MAX_DIFFICULTY + 1),
        Err(ClientError::PowTooHard(7))
    ));
    assert!(matches!(
        solve_pow("any", 64),
        Err(ClientError::PowTooHard(64))
    ));
}

#[test]
fn challenge_difficulty_reads_the_third_field() {
    assert_eq!(challenge_difficulty("a:b:3:c"), Some(3));
    assert_eq!(challenge_difficulty("a:b:x:c"), None);
    assert_eq!(challenge_difficulty("a:b:3"), None);
    assert_eq!(challenge_difficulty("a:b:3:c:d"), None);
    assert_eq!(challenge_difficulty("a:b:-3:c"), None);
    assert_eq!(challenge_difficulty(""), None);
}
