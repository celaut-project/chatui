//! The proof of work of `GenerateClient` (`nodo:src/gateway/client_pow.py`).
//!
//! The rule: the lowercase hex of `blake2b-512(utf8(challenge) || utf8(solution))`
//! ends with `difficulty` zero characters. The solution is a decimal counter. The
//! node counts from 0 and takes the first one that works (`solve_pow`), and so does
//! this code.

use blake2::{Blake2b512, Digest};

use crate::ClientError;

/// The most work that this client does. A difficulty of 6 is about 16 million
/// hashes. The node can ask for 64 (`MAX_DIFFICULTY`), and that never ends.
pub const MAX_DIFFICULTY: u32 = 6;

/// `Blake2b(challenge || solution).hexdigest()` (`pow_digest`).
pub fn pow_digest(challenge: &str, solution: &str) -> String {
    let mut hasher = Blake2b512::new();
    hasher.update(challenge.as_bytes());
    hasher.update(solution.as_bytes());
    hex::encode(hasher.finalize())
}

/// Whether `solution` answers `challenge` at `difficulty` (`verify_solution`).
/// A difficulty of 0 accepts any solution.
pub fn verify_solution(challenge: &str, solution: &str, difficulty: u32) -> bool {
    if difficulty == 0 {
        return true;
    }
    let digest = pow_digest(challenge, solution);
    let zeros = usize::try_from(difficulty).unwrap_or(usize::MAX);
    digest.len() >= zeros && digest.bytes().rev().take(zeros).all(|b| b == b'0')
}

/// The smallest counter that solves `challenge` (`solve_pow`). An empty solution for
/// difficulty 0. Refuses a difficulty above [`MAX_DIFFICULTY`].
///
/// This takes CPU time. Call it from a blocking thread.
pub fn solve_pow(challenge: &str, difficulty: u32) -> Result<String, ClientError> {
    if difficulty == 0 {
        return Ok(String::new());
    }
    if difficulty > MAX_DIFFICULTY {
        return Err(ClientError::PowTooHard(difficulty));
    }
    let mut counter: u64 = 0;
    loop {
        let solution = counter.to_string();
        if verify_solution(challenge, &solution, difficulty) {
            return Ok(solution);
        }
        counter += 1;
    }
}

/// The difficulty in a challenge `client_id:nonce:difficulty:mac`. The node uses this
/// one and not the copy in `PoWRequired.difficulty`.
pub fn challenge_difficulty(challenge: &str) -> Option<u32> {
    let mut fields = challenge.split(':');
    let (_, _, difficulty, _, rest) = (
        fields.next()?,
        fields.next()?,
        fields.next()?,
        fields.next()?,
        fields.next(),
    );
    if rest.is_some() {
        return None;
    }
    difficulty.parse().ok()
}
