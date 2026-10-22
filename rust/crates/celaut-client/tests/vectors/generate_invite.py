"""Vectors for the peer invitation (`src/invite.rs`), written from `protos/invite.proto`.

    python3 generate_invite.py > invite_vectors.json

Standalone: it needs only the Python standard library. It writes the protobuf wire
format by hand (field 1 `public_key`, field 2 `addr`; in `Addr`: 1 `tags`, 2 `formal`,
3 `data`) and the address formats of nodo#579 (`src/utils/peer_invite.py`, nodo dev
f4dcb3b2): ip4 is 4 bytes and a big-endian port, ip6 is 16 and a port, `tor-onion-v3` is
the 32-byte key and a port, `dns` is the ASCII host and a port.

The checks of nodo that a vector for it must pass are in its tests
(`tests/test_peer_invite.py`): the sizes (49 bytes for one ip4 and a key, under 150 for
ip4, ip6 and onion), the refusals, and that an unknown tag is ignored. The keys and the
onion address of nodo's test (`bytes(range(100, 132))`) are used here too.
"""
import base64
import hashlib
import ipaddress
import json
import struct

KEY = bytes(range(32))
ONION_KEY = bytes(range(100, 132))


def varint(n):
    out = bytearray()
    while n >= 0x80:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)
    return bytes(out)


def field(number, payload):
    return varint(number << 3 | 2) + varint(len(payload)) + payload


def addr(tags, data, formal=b""):
    out = b"".join(field(1, t.encode()) for t in tags)
    if formal:
        out += field(2, formal)
    return out + field(3, data)


def invite(addrs, key=KEY):
    return field(1, key) + b"".join(field(2, a) for a in addrs)


def port(n):
    return struct.pack(">H", n)


def onion_text(key):
    checksum = hashlib.sha3_256(b".onion checksum" + key + b"\x03").digest()[:2]
    return base64.b32encode(key + checksum + b"\x03").decode().lower() + ".onion"


IP4 = addr(["ip4"], ipaddress.ip_address("203.0.113.7").packed + port(8090))
IP6 = addr(["ip6"], ipaddress.ip_address("2001:db8::1").packed + port(8091))
ONION = addr(["tor-onion-v3"], ONION_KEY + port(8092))
DNS = addr(["dns"], b"node.example.org" + port(8093))
UNKNOWN = addr(["quic9"], b"anything")

valid = {
    "ip4": (invite([IP4]), ["203.0.113.7:8090"]),
    "all_kinds": (
        invite([IP4, IP6, ONION, DNS]),
        ["203.0.113.7:8090", "[2001:db8::1]:8091", f"{onion_text(ONION_KEY)}:8092", "node.example.org:8093"],
    ),
    "unknown_tag_is_ignored": (invite([UNKNOWN, IP4]), ["203.0.113.7:8090"]),
    "synonym_tags": (
        invite([addr(["quic9", "ip4"], ipaddress.ip_address("1.2.3.4").packed + port(5))]),
        ["1.2.3.4:5"],
    ),
    "formal_is_accepted": (
        invite([addr(["ip4"], ipaddress.ip_address("1.2.3.4").packed + port(258), b"a=b\nc=d=e\n")]),
        ["1.2.3.4:258"],
    ),
    "only_unknown": (invite([UNKNOWN]), []),
    "dns_with_a_dot_at_the_end": (invite([addr(["dns"], b"a.example." + port(1))]), ["a.example.:1"]),
}

ip4 = ipaddress.ip_address("1.2.3.4").packed
refused = {
    "short_key": invite([IP4], key=b"\x01" * 31),
    "no_key": b"".join(field(2, a) for a in [IP4]),
    "ip4_with_four_bytes": invite([addr(["ip4"], b"\x01\x02\x03\x04")]),
    "ip4_with_five_bytes": invite([addr(["ip4"], b"\x01\x02\x03\x04\x00")]),
    "ip6_with_wrong_length": invite([addr(["ip6"], b"\x00" * 17)]),
    "onion_with_wrong_length": invite([addr(["tor-onion-v3"], b"\x00" * 33)]),
    "dns_too_short": invite([addr(["dns"], b"\x00\x01")]),
    "dns_with_a_space": invite([addr(["dns"], b"a b.example" + port(1))]),
    "dns_that_is_an_ip": invite([addr(["dns"], b"1.2.3.4" + port(80))]),
    "dns_that_is_an_onion": invite([addr(["dns"], b"abc.onion" + port(80))]),
    "dns_not_ascii": invite([addr(["dns"], "ñandú.example".encode() + port(80))]),
    "dns_with_an_empty_label": invite([addr(["dns"], b"a..b" + port(1))]),
    "dns_with_a_leading_hyphen": invite([addr(["dns"], b"-x.example" + port(1))]),
    "formal_without_equals": invite([addr(["ip4"], ip4 + port(1), b"no-equals")]),
    "formal_with_an_empty_key": invite([addr(["ip4"], ip4 + port(1), b"=1")]),
    "formal_with_a_repeated_key": invite([addr(["ip4"], ip4 + port(1), b"a=1\na=2")]),
    "formal_not_utf8": invite([addr(["ip4"], ip4 + port(1), b"\xff\xfe=1")]),
    "not_a_message": b"\x0a\xff\xff\xff\xff\x0f",
    "empty": b"",
}

print(
    json.dumps(
        {
            "key": KEY.hex(),
            "onion_key": ONION_KEY.hex(),
            "onion": onion_text(ONION_KEY),
            "sizes": {"ip4": len(valid["ip4"][0]), "three": len(invite([IP4, IP6, ONION]))},
            "valid": {k: {"hex": raw.hex(), "targets": t} for k, (raw, t) in valid.items()},
            "refused": {k: raw.hex() for k, raw in refused.items()},
        },
        indent=2,
        sort_keys=True,
    )
)
