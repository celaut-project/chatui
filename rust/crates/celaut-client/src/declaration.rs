//! The environment variables that a service declares (`docs/celaut/env-variables.md`).
//!
//! A service declares them in `Service.container.environment_variables`, which is after
//! the filesystem of the container in the serialized message. The filesystem can be
//! hundreds of megabytes, so the Service part is not decoded as a message: this module
//! walks its protobuf fields as a stream, skips the bytes that it does not need, and
//! decodes only the entries of the declaration. It stops at the end of the container, so
//! it never reads the rest of the package.
//!
//! The Buffers are the ones of `GetService` or of a `.bee` file through
//! [`crate::package::read`]: the Service part is the object with the index 6, and its
//! bytes are its chunks in order, with the chunks of its blocks included.

use std::path::Path;

use bee_rpc::buffer::Buffer;
use celaut_proto::celaut::DataFormatKeyValue;
use celaut_wire::Buffers;
use prost::Message;
use tokio_stream::StreamExt;

use crate::package::{inspect, read, Cancel, PackageError};

/// The index of the Service part.
const SERVICE_INDEX: i32 = 6;

/// The largest entry of the declaration that is decoded.
const MAX_ENTRY: u64 = 256 * 1024;

/// How many variables a service can declare here. A larger declaration is refused.
pub const MAX_DECLARED: usize = 256;

/// A variable that a service declares.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Declared {
    pub name: String,
    /// The names of its format.
    pub tags: Vec<String>,
    /// The text that explains it.
    pub prose: String,
}

/// The bytes of the Service part, pulled one Buffer at a time.
struct ServiceBytes {
    input: Buffers,
    buf: Vec<u8>,
    pos: usize,
    /// The index of the object that is open, if one is.
    open: Option<i32>,
    ended: bool,
    /// The bytes of the Service part that were read, for the limit.
    consumed: u64,
    /// The bytes of the whole stream that were read, for the limit.
    seen: u64,
    limit: Option<u64>,
}

fn invalid(text: &str) -> PackageError {
    PackageError::Invalid(text.into())
}

impl ServiceBytes {
    fn new(input: Buffers, limit: Option<u64>) -> Self {
        ServiceBytes {
            input,
            buf: Vec::new(),
            pos: 0,
            open: None,
            ended: false,
            consumed: 0,
            seen: 0,
            limit,
        }
    }

    /// Read one more Buffer, and keep its bytes if it is part of the Service. False when
    /// the Service part is over (or the stream is).
    async fn pull(&mut self) -> Result<bool, PackageError> {
        if self.ended {
            return Ok(false);
        }
        let Some(item) = self.input.next().await else {
            self.ended = true;
            return Ok(false);
        };
        let buffer: Buffer = item?;
        self.seen += buffer.encoded_len() as u64;
        if self.limit.is_some_and(|l| self.seen > l) {
            return Err(invalid(
                "the service is too large to read its variables from a node",
            ));
        }
        let starts = buffer.head.is_some() || buffer.chunk.is_some() || buffer.block.is_some();
        if self.open.is_none() && starts {
            self.open = Some(buffer.head.as_ref().map_or(0, |h| h.index));
        }
        if self.open == Some(SERVICE_INDEX) {
            if let Some(chunk) = &buffer.chunk {
                if self.pos > 0 && self.pos == self.buf.len() {
                    self.buf.clear();
                    self.pos = 0;
                }
                self.buf.extend_from_slice(chunk);
            }
        }
        if buffer.separator == Some(true) || (self.open.is_some() && !starts) {
            if self.open == Some(SERVICE_INDEX) {
                self.ended = true;
            }
            self.open = None;
        }
        Ok(true)
    }

    /// Make sure that at least one byte is ready. False at the end of the Service part.
    async fn ready(&mut self) -> Result<bool, PackageError> {
        while self.pos >= self.buf.len() {
            if !self.pull().await? {
                return Ok(false);
            }
        }
        Ok(true)
    }

    async fn byte(&mut self) -> Result<Option<u8>, PackageError> {
        if !self.ready().await? {
            return Ok(None);
        }
        let b = self.buf[self.pos];
        self.pos += 1;
        self.consumed += 1;
        Ok(Some(b))
    }

    /// A varint. `None` if the Service part ends before its first byte.
    async fn varint(&mut self) -> Result<Option<u64>, PackageError> {
        let mut value = 0u64;
        for shift in (0..64).step_by(7) {
            let Some(b) = self.byte().await? else {
                return if shift == 0 {
                    Ok(None)
                } else {
                    Err(invalid("the Service is cut"))
                };
            };
            value |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Ok(Some(value));
            }
        }
        Err(invalid("a varint of the Service is too long"))
    }

    async fn need_varint(&mut self) -> Result<u64, PackageError> {
        self.varint()
            .await?
            .ok_or_else(|| invalid("the Service is cut"))
    }

    async fn take(&mut self, n: u64) -> Result<Vec<u8>, PackageError> {
        let n = usize::try_from(n).map_err(|_| invalid("a field is too long"))?;
        let mut out = Vec::with_capacity(n.min(64 * 1024));
        while out.len() < n {
            if !self.ready().await? {
                return Err(invalid("the Service is cut"));
            }
            let take = (n - out.len()).min(self.buf.len() - self.pos);
            out.extend_from_slice(&self.buf[self.pos..self.pos + take]);
            self.pos += take;
            self.consumed += take as u64;
        }
        Ok(out)
    }

    async fn skip(&mut self, mut n: u64) -> Result<(), PackageError> {
        while n > 0 {
            if !self.ready().await? {
                return Err(invalid("the Service is cut"));
            }
            let take = n.min((self.buf.len() - self.pos) as u64);
            self.pos += take as usize;
            self.consumed += take;
            n -= take;
        }
        Ok(())
    }

    /// Skip the value of a field of this wire type.
    async fn skip_value(&mut self, wire_type: u64) -> Result<(), PackageError> {
        match wire_type {
            0 => {
                self.need_varint().await?;
                Ok(())
            }
            1 => self.skip(8).await,
            2 => {
                let len = self.need_varint().await?;
                self.skip(len).await
            }
            5 => self.skip(4).await,
            _ => Err(invalid(
                "the Service has a field of a wire type that is not valid",
            )),
        }
    }
}

/// Read `Service.container.environment_variables` from the Buffers of a service. No
/// container, or no declaration, gives an empty list. With `limit`, a stream of more
/// bytes than that before the declaration is an error (a node can send a service of
/// gigabytes).
pub async fn declared_variables(
    input: Buffers,
    limit: Option<u64>,
) -> Result<Vec<Declared>, PackageError> {
    let mut src = ServiceBytes::new(input, limit);
    while let Some(tag) = src.varint().await? {
        let (field, wire_type) = (tag >> 3, tag & 7);
        if field != 2 || wire_type != 2 {
            src.skip_value(wire_type).await?;
            continue;
        }
        let len = src.need_varint().await?;
        let end = src.consumed.saturating_add(len);
        let mut declared = Vec::new();
        while src.consumed < end {
            let tag = src.need_varint().await?;
            let (field, wire_type) = (tag >> 3, tag & 7);
            if field != 7 || wire_type != 2 {
                src.skip_value(wire_type).await?;
                continue;
            }
            let size = src.need_varint().await?;
            if size > MAX_ENTRY {
                return Err(invalid("an entry of the declaration is too large"));
            }
            let entry = DataFormatKeyValue::decode(src.take(size).await?.as_slice())
                .map_err(|e| PackageError::Invalid(format!("a declared variable: {e}")))?;
            let format = entry.value.unwrap_or_default();
            declared.push(Declared {
                name: entry.key,
                tags: format.tags,
                prose: format.prose,
            });
            if declared.len() > MAX_DECLARED {
                return Err(invalid("the service declares too many variables"));
            }
        }
        if src.consumed != end {
            return Err(invalid("the container of the Service is cut"));
        }
        return Ok(declared);
    }
    Ok(Vec::new())
}

/// The same for a package file: the library file of a service, or a file that was
/// fetched from a node.
pub async fn declared_variables_of_file(path: &Path) -> Result<Vec<Declared>, PackageError> {
    let info = inspect(path).await?;
    if !info.has_service {
        return Err(invalid("the file has no Service part"));
    }
    declared_variables(read(path.to_path_buf(), info.layout, Cancel::new()), None).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use bee_rpc::buffer::buffer::Head;
    use celaut_proto::celaut::service::Container;
    use celaut_proto::celaut::{DataFormat, Service};

    fn varint(mut v: u64, out: &mut Vec<u8>) {
        while v >= 0x80 {
            out.push((v as u8 & 0x7f) | 0x80);
            v >>= 7;
        }
        out.push(v as u8);
    }

    fn declaration(names: &[&str]) -> Vec<DataFormatKeyValue> {
        names
            .iter()
            .map(|n| DataFormatKeyValue {
                key: n.to_string(),
                value: Some(DataFormat {
                    tags: vec!["text".into()],
                    prose: format!("the {n}"),
                    formal: Vec::new(),
                }),
            })
            .collect()
    }

    /// A Service whose filesystem has `fs` bytes, followed by the declaration.
    fn service(fs: usize, names: &[&str]) -> Vec<u8> {
        let container = Container {
            filesystem: vec![7u8; fs],
            environment_variables: declaration(names),
            ..Default::default()
        };
        Service {
            prose: "a service".into(),
            container: Some(container),
            ..Default::default()
        }
        .encode_to_vec()
    }

    fn stream(buffers: Vec<Buffer>) -> Buffers {
        Box::pin(tokio_stream::iter(buffers.into_iter().map(Ok)))
    }

    fn head(index: i32) -> Option<Head> {
        Some(Head {
            index,
            partitions: Vec::new(),
        })
    }

    /// The parts of a package: a Metadata part, then the Service in chunks of `size`
    /// bytes, with a block marker in the middle.
    fn package(bytes: &[u8], size: usize) -> Buffers {
        let mut out = vec![Buffer {
            head: head(5),
            chunk: Some(vec![1, 2, 3]),
            separator: Some(true),
            ..Default::default()
        }];
        out.push(Buffer {
            head: head(SERVICE_INDEX),
            ..Default::default()
        });
        for (i, part) in bytes.chunks(size).enumerate() {
            if i == 1 {
                out.push(Buffer {
                    block: Some(Default::default()),
                    ..Default::default()
                });
            }
            out.push(Buffer {
                chunk: Some(part.to_vec()),
                ..Default::default()
            });
        }
        out.push(Buffer {
            separator: Some(true),
            ..Default::default()
        });
        stream(out)
    }

    #[tokio::test]
    async fn the_declaration_is_read_after_a_large_filesystem() {
        let bytes = service(300_000, &["API_KEY", "DB_PASSWORD"]);
        for size in [1, 7, 4096, 1 << 20] {
            let got = declared_variables(package(&bytes, size), None)
                .await
                .unwrap();
            assert_eq!(got.len(), 2, "chunks of {size}");
            assert_eq!(got[0].name, "API_KEY");
            assert_eq!(got[0].tags, vec!["text".to_string()]);
            assert_eq!(got[1].prose, "the DB_PASSWORD");
        }
    }

    #[tokio::test]
    async fn a_service_with_no_declaration_gives_an_empty_list() {
        let bytes = service(10, &[]);
        assert!(declared_variables(package(&bytes, 4), None)
            .await
            .unwrap()
            .is_empty());
        let none = Service {
            prose: "no container".into(),
            ..Default::default()
        }
        .encode_to_vec();
        assert!(declared_variables(package(&none, 4), None)
            .await
            .unwrap()
            .is_empty());
        // No Service part at all.
        assert!(declared_variables(stream(vec![]), None)
            .await
            .unwrap()
            .is_empty());
    }

    #[tokio::test]
    async fn the_limit_stops_a_service_that_is_too_large() {
        let bytes = service(50_000, &["A"]);
        let err = declared_variables(package(&bytes, 4096), Some(10_000))
            .await
            .unwrap_err();
        assert!(err.to_string().contains("too large"), "{err}");
        assert_eq!(
            declared_variables(package(&bytes, 4096), Some(1 << 20))
                .await
                .unwrap()
                .len(),
            1
        );
    }

    #[tokio::test]
    async fn a_cut_service_is_an_error_and_never_a_panic() {
        let bytes = service(1000, &["A", "B"]);
        for cut in [1, 3, 500, bytes.len() - 3] {
            let result = declared_variables(package(&bytes[..cut], 64), None).await;
            assert!(result.is_err() || result.unwrap().len() < 2, "cut at {cut}");
        }
        let mut junk = Vec::new();
        varint((2 << 3) | 2, &mut junk);
        varint(1 << 40, &mut junk);
        junk.extend_from_slice(&[0xff; 32]);
        assert!(declared_variables(package(&junk, 8), None).await.is_err());
        // A group wire type is not valid.
        assert!(declared_variables(package(&[0x0b], 8), None).await.is_err());
    }

    #[tokio::test]
    async fn another_part_with_the_same_bytes_is_not_the_service() {
        let bytes = service(10, &["A"]);
        let mut other = vec![Buffer {
            head: head(5),
            chunk: Some(bytes.clone()),
            separator: Some(true),
            ..Default::default()
        }];
        other.push(Buffer {
            head: head(SERVICE_INDEX),
            chunk: Some(service(0, &["B"])),
            separator: Some(true),
            ..Default::default()
        });
        let got = declared_variables(stream(other), None).await.unwrap();
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].name, "B");
    }

    /// A real package, for a manual check: `CELAUT_TEST_BEE=/path/to/service.bee cargo
    /// test -p celaut-client --lib real_package -- --ignored --nocapture`.
    #[tokio::test]
    #[ignore = "needs a .bee file"]
    async fn real_package() {
        let path = std::env::var("CELAUT_TEST_BEE").expect("set CELAUT_TEST_BEE");
        let started = std::time::Instant::now();
        let got = declared_variables_of_file(Path::new(&path)).await.unwrap();
        println!("{got:?} in {:?}", started.elapsed());
    }
}
