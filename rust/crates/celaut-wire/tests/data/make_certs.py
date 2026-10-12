"""Make the test certificates of celaut-wire, with the nodo code.

Run from a nodo checkout (nodo dev e3d12301 was used):

    PYTHONPATH=<nodo> python3 make_certs.py <output directory>

It needs the nodo requirements (cryptography 50). Every key is fixed and every ECDSA
signature is deterministic, so the output is the same on each run. The private keys
are public test keys. Never use them for anything else.

Files:

- node.der, node.key.der: a certificate as `tls_identity._build_certificate` makes it
  (P-256 key, identity extension), and the PKCS#8 key of the certificate.
- node.peer_id: the identity key (peer_id) of node.der, as lowercase hex.
- other.der: the same, for another identity key. Its key is node.key.der too, so the
  handshake test can present it with the same server key.
- no-extension.der: a certificate without the identity extension.
- bad-signature.der: the extension names the identity of node.der, but the signature is
  from another identity key.
- uppercase.der: the extension has the public key in uppercase hex (not canonical).
- no-colon.der: the extension has no ":" separator.
- not-ascii.der: the extension is not ASCII.

The script checks node.der and the other files with `peer_id_from_certificate` of nodo.
"""
import datetime
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.x509.oid import NameOID

from src.identity import tls_identity as tls

IDENTITY_SEED = bytes([7] * 32)
OTHER_SEED = bytes([9] * 32)
TLS_KEY_SCALAR = 0x1F2E3D4C5B6A79880123456789ABCDEF0FEDCBA9876543210123456789ABCDE


def identity(seed):
    key = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
    pub = key.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    ).hex()
    return key, pub


def build(tls_key, extension_value):
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, tls.TLS_SERVER_NAME)])
    builder = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(tls_key.public_key())
        .serial_number(0x1234567890ABCDEF)
        .not_valid_before(tls._NOT_VALID_BEFORE)
        .not_valid_after(tls._NOT_VALID_AFTER)
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .add_extension(
            x509.SubjectAlternativeName([x509.DNSName(tls.TLS_SERVER_NAME)]), critical=False
        )
    )
    if extension_value is not None:
        builder = builder.add_extension(
            x509.UnrecognizedExtension(tls.HOST_KEY_EXTENSION_OID, extension_value),
            critical=False,
        )
    cert = builder.sign(tls_key, hashes.SHA256(), ecdsa_deterministic=True)
    return cert.public_bytes(serialization.Encoding.DER)


def main(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    tls_key = ec.derive_private_key(TLS_KEY_SCALAR, ec.SECP256R1())
    spki = tls_key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    payload = tls._host_key_payload(spki).encode("utf-8")
    key, pub = identity(IDENTITY_SEED)
    other_key, other_pub = identity(OTHER_SEED)

    files = {
        "node.der": build(tls_key, f"{pub}:{key.sign(payload).hex()}".encode("ascii")),
        "other.der": build(tls_key, f"{other_pub}:{other_key.sign(payload).hex()}".encode("ascii")),
        "no-extension.der": build(tls_key, None),
        "bad-signature.der": build(tls_key, f"{pub}:{other_key.sign(payload).hex()}".encode("ascii")),
        "uppercase.der": build(tls_key, f"{pub.upper()}:{key.sign(payload).hex()}".encode("ascii")),
        "no-colon.der": build(tls_key, pub.encode("ascii")),
        "not-ascii.der": build(tls_key, b"\xff\xfe:00"),
    }
    expected = {
        "node.der": pub,
        "other.der": other_pub,
    }
    for name, der in files.items():
        (out / name).write_bytes(der)
        try:
            got = tls.peer_id_from_certificate(der)
        except tls.CertificateError as e:
            got = None
            print(f"{name}: refused by nodo: {e}")
        if name in expected:
            assert got == expected[name], name
        else:
            assert got is None, name
    (out / "node.key.der").write_bytes(tls_key.private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ))
    (out / "node.peer_id").write_text(pub + "\n")
    (out / "other.peer_id").write_text(other_pub + "\n")


main(sys.argv[1])
