//! The identity of a node in its TLS certificate (`docs/celaut/wire.md`, section 1;
//! `nodo:src/identity/tls_identity.py`).
//!
//! The certificate has a throwaway P-256 key and an extension with the OID
//! [`HOST_KEY_EXTENSION_OID`]. The contents of the extension are the ASCII text
//! `"<public key hex>:<signature hex>"`. The public key is the Ed25519 key of the node:
//! its `peer_id`. The signature is Ed25519 by that key over
//! `"CELAUT" + hex(DER SubjectPublicKeyInfo of the certificate)`.
//!
//! [`peer_id_from_certificate`] checks the extension. [`IdentityVerifier`] does it in a
//! TLS handshake and, as rustls requires, checks the handshake signature with the key
//! of the certificate. Together they prove that the server holds the private key of a
//! certificate that the identity key authorized. The chain, the name and the dates of
//! the certificate are not checked: nothing in them has a meaning here.

use std::sync::{Arc, Mutex, PoisonError};

use ring::signature::{UnparsedPublicKey, ED25519};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, WebPkiSupportedAlgorithms};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};

use crate::IdentityError;

/// The OID `2.25.276125094420857322236898758448456352855`, DER contents.
const OID_DER: [u8; 20] = [
    0x69, 0x83, 0x9f, 0xbb, 0xe1, 0x8f, 0xe0, 0xe7, 0x9a, 0xf5, 0x87, 0xab, 0xc6, 0xb0, 0xa3, 0xe7,
    0xcc, 0xbd, 0x88, 0x57,
];

/// The OID of the identity extension, in dotted form.
pub const HOST_KEY_EXTENSION_OID: &str = "2.25.276125094420857322236898758448456352855";

/// The prefix of the signed text (`tls_identity._SIGNATURE_PREFIX`).
const SIGNATURE_PREFIX: &str = "CELAUT";

/// The SNI name of every node (`tls_identity.TLS_SERVER_NAME`).
pub const TLS_SERVER_NAME: &str = "celaut-node";

/// One DER element: the tag, the contents, and all of its bytes.
struct Tlv<'a> {
    tag: u8,
    content: &'a [u8],
    full: &'a [u8],
}

/// Read one element from the start of `input`. Returns it and the bytes after it.
/// Accepts only a one-byte tag and a definite length of up to 4 bytes.
fn read_tlv(input: &[u8]) -> Option<(Tlv<'_>, &[u8])> {
    let tag = *input.first()?;
    if tag & 0x1f == 0x1f {
        return None;
    }
    let first = *input.get(1)?;
    let (len, header) = if first < 0x80 {
        (usize::from(first), 2)
    } else {
        let count = usize::from(first & 0x7f);
        if count == 0 || count > 4 {
            return None;
        }
        let bytes = input.get(2..2 + count)?;
        let len = bytes.iter().fold(0usize, |n, b| (n << 8) | usize::from(*b));
        (len, 2 + count)
    };
    let end = header.checked_add(len)?;
    let full = input.get(..end)?;
    let content = input.get(header..end)?;
    Some((Tlv { tag, content, full }, input.get(end..)?))
}

/// Read one element and move `rest` after it.
fn take<'a>(rest: &mut &'a [u8], what: &'static str) -> Result<Tlv<'a>, IdentityError> {
    let (tlv, after) = read_tlv(rest).ok_or(IdentityError::BadCertificate(what))?;
    *rest = after;
    Ok(tlv)
}

/// The SubjectPublicKeyInfo (all bytes of the element) and the value of the identity
/// extension of a certificate.
fn spki_and_extension(der: &[u8]) -> Result<(&[u8], &[u8]), IdentityError> {
    let bad = IdentityError::BadCertificate;
    let (cert, rest) = read_tlv(der).ok_or(bad("not a DER element"))?;
    if cert.tag != 0x30 || !rest.is_empty() {
        return Err(bad("not a certificate"));
    }
    let (tbs, _) = read_tlv(cert.content).ok_or(bad("no tbsCertificate"))?;
    if tbs.tag != 0x30 {
        return Err(bad("no tbsCertificate"));
    }
    let mut rest = tbs.content;
    let mut item = take(&mut rest, "no serial number")?;
    if item.tag == 0xa0 {
        item = take(&mut rest, "no serial number")?; // The version was first.
    }
    if item.tag != 0x02 {
        return Err(bad("no serial number"));
    }
    // Signature algorithm, issuer, validity, subject.
    for what in [
        "no signature algorithm",
        "no issuer",
        "no validity",
        "no subject",
    ] {
        if take(&mut rest, what)?.tag != 0x30 {
            return Err(bad(what));
        }
    }
    let spki = take(&mut rest, "no public key")?;
    if spki.tag != 0x30 {
        return Err(bad("no public key"));
    }
    let spki_full = spki.full;
    // Unique identifiers [1] and [2], then the extensions [3].
    let mut extensions = None;
    while !rest.is_empty() {
        let tlv = take(&mut rest, "bad field")?;
        if tlv.tag == 0xa3 {
            extensions = Some(tlv.content);
        }
    }
    let extensions = extensions.ok_or(IdentityError::NoExtension)?;
    let (list, trailing) = read_tlv(extensions).ok_or(bad("bad extensions"))?;
    if list.tag != 0x30 || !trailing.is_empty() {
        return Err(bad("bad extensions"));
    }

    let mut found: Option<&[u8]> = None;
    let mut rest = list.content;
    while !rest.is_empty() {
        let (ext, after) = read_tlv(rest).ok_or(bad("bad extension"))?;
        rest = after;
        if ext.tag != 0x30 {
            return Err(bad("bad extension"));
        }
        let (oid, body) = read_tlv(ext.content).ok_or(bad("bad extension"))?;
        if oid.tag != 0x06 || oid.content != OID_DER {
            continue;
        }
        // The optional "critical" flag, then the OCTET STRING.
        let (mut value, mut tail) = read_tlv(body).ok_or(bad("bad extension"))?;
        if value.tag == 0x01 {
            (value, tail) = read_tlv(tail).ok_or(bad("bad extension"))?;
        }
        if value.tag != 0x04 || !tail.is_empty() {
            return Err(bad("bad extension"));
        }
        // A second copy is refused, as nodo refuses it.
        if found.replace(value.content).is_some() {
            return Err(IdentityError::BadExtension(
                "the extension is present twice",
            ));
        }
    }
    let value = found.ok_or(IdentityError::NoExtension)?;
    Ok((spki_full, value))
}

fn is_canonical_key(text: &str) -> bool {
    text.len() == 64
        && text
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// The `peer_id` that a DER certificate proves, or the reason why it proves none.
pub fn peer_id_from_certificate(der: &[u8]) -> Result<String, IdentityError> {
    let (spki, value) = spki_and_extension(der)?;
    let text = std::str::from_utf8(value)
        .ok()
        .filter(|t| t.is_ascii())
        .ok_or(IdentityError::BadExtension("not ASCII"))?;
    let (public_key, signature) = text
        .split_once(':')
        .ok_or(IdentityError::BadExtension("no ':' separator"))?;
    if !is_canonical_key(public_key) {
        return Err(IdentityError::NonCanonicalKey);
    }
    let bad_signature = || IdentityError::BadSignature(public_key.to_string());
    let key = hex::decode(public_key).map_err(|_| IdentityError::NonCanonicalKey)?;
    let signature = hex::decode(signature).map_err(|_| bad_signature())?;
    let payload = format!("{SIGNATURE_PREFIX}{}", hex::encode(spki));
    UnparsedPublicKey::new(&ED25519, key)
        .verify(payload.as_bytes(), &signature)
        .map_err(|_| bad_signature())?;
    Ok(public_key.to_string())
}

#[derive(Debug, Default)]
struct State {
    /// The identity that the last accepted certificate proved.
    seen: Option<String>,
    /// Why the last certificate was refused.
    refused: Option<IdentityError>,
}

/// A rustls verifier for the certificate of a Celaut node.
///
/// It accepts a certificate only if its identity extension is valid. With an expected
/// `peer_id`, it also refuses another identity. It keeps the first identity that it
/// accepted, and refuses a different one later: a connection that tonic makes again
/// (after a drop) must go to the same node.
#[derive(Debug)]
pub struct IdentityVerifier {
    expected: Option<String>,
    algorithms: WebPkiSupportedAlgorithms,
    state: Mutex<State>,
}

impl IdentityVerifier {
    /// A new verifier. `expected` is the `peer_id` that the node must prove, if known.
    pub fn new(expected: Option<String>, algorithms: WebPkiSupportedAlgorithms) -> Arc<Self> {
        Arc::new(IdentityVerifier {
            expected,
            algorithms,
            state: Mutex::new(State::default()),
        })
    }

    fn state(&self) -> std::sync::MutexGuard<'_, State> {
        // A panic cannot leave this state half written.
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// The identity of the node, once a certificate was accepted.
    pub fn peer_id(&self) -> Option<String> {
        self.state().seen.clone()
    }

    /// Why the last certificate was refused. Takes the value.
    pub fn take_refusal(&self) -> Option<IdentityError> {
        self.state().refused.take()
    }

    fn check(&self, der: &[u8]) -> Result<(), IdentityError> {
        let actual = peer_id_from_certificate(der)?;
        let pinned = self
            .expected
            .as_ref()
            .or(self.state().seen.as_ref())
            .cloned();
        if let Some(expected) = pinned {
            if expected != actual {
                return Err(IdentityError::PeerMismatch { expected, actual });
            }
        }
        self.state().seen = Some(actual);
        Ok(())
    }
}

impl ServerCertVerifier for IdentityVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        match self.check(end_entity.as_ref()) {
            Ok(()) => Ok(ServerCertVerified::assertion()),
            Err(e) => {
                self.state().refused = Some(e.clone());
                Err(rustls::Error::InvalidCertificate(
                    rustls::CertificateError::Other(rustls::OtherError(Arc::new(e))),
                ))
            }
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(message, cert, dss, &self.algorithms)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(message, cert, dss, &self.algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}
