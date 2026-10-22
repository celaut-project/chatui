//! Regenerates `crates/celaut-proto/src/gen/` from the vendored `.proto` files.
//!
//! The generated code is committed, so a normal build (and the Android build) does
//! not need `protoc`. Run this after you update the protos:
//!
//! ```sh
//! cargo run -p gen-protos
//! ```

use std::path::PathBuf;

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../crates/celaut-proto");
    let protos = root.join("protos");
    let out = root.join("src/gen");
    std::fs::create_dir_all(&out).expect("create output directory");
    prost_build::Config::new()
        .out_dir(&out)
        .compile_protos(
            &[
                protos.join("buffer.proto"),
                protos.join("celaut.proto"),
                protos.join("invite.proto"),
            ],
            &[protos],
        )
        .expect("compile protos");
}
