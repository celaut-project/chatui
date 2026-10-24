import 'dart:typed_data';

/// The SHA3-256 hash of [data] (FIPS 202), 32 bytes.
///
/// The hash of a file of the chat (`docs/celaut/chat.md`, section 6.4) is SHA3-256, and
/// `package:crypto` has SHA-2 only. This function uses the 64-bit integers of the Dart VM,
/// so it does not run in a browser. Tests check it against the vectors of NIST.
Uint8List sha3_256(List<int> data) {
  const rate = 136; // bytes: 200 - 2 * 32
  final state = List<int>.filled(25, 0);

  void absorb(Uint8List block) {
    final words = block.buffer.asByteData(block.offsetInBytes, block.lengthInBytes);
    for (var i = 0; i < rate ~/ 8; i++) {
      state[i] ^= words.getUint64(i * 8, Endian.little);
    }
    _keccakF(state);
  }

  final bytes = data is Uint8List ? data : Uint8List.fromList(data);
  var offset = 0;
  while (bytes.length - offset >= rate) {
    absorb(Uint8List.sublistView(bytes, offset, offset + rate));
    offset += rate;
  }
  // The last block: the rest, the domain bits 01 and the padding 10*1.
  final last = Uint8List(rate)..setRange(0, bytes.length - offset, bytes, offset);
  last[bytes.length - offset] ^= 0x06;
  last[rate - 1] ^= 0x80;
  absorb(last);

  final out = ByteData(32);
  for (var i = 0; i < 4; i++) {
    out.setUint64(i * 8, state[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

const _roundConstants = <int>[
  0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000, //
  0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
  0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
  0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
  0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
  0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
];

/// The rotation of each lane, in the order that [_piLane] visits them.
const _rotations = <int>[
  1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44, //
];
const _piLane = <int>[
  10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1, //
];

int _rotl(int x, int n) => (x << n) | (x >>> (64 - n));

void _keccakF(List<int> a) {
  final c = List<int>.filled(5, 0);
  for (var round = 0; round < 24; round++) {
    // Theta.
    for (var x = 0; x < 5; x++) {
      c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20];
    }
    for (var x = 0; x < 5; x++) {
      final d = c[(x + 4) % 5] ^ _rotl(c[(x + 1) % 5], 1);
      for (var y = 0; y < 25; y += 5) {
        a[y + x] ^= d;
      }
    }
    // Rho and pi.
    var t = a[1];
    for (var i = 0; i < 24; i++) {
      final j = _piLane[i];
      final next = a[j];
      a[j] = _rotl(t, _rotations[i]);
      t = next;
    }
    // Chi.
    for (var y = 0; y < 25; y += 5) {
      for (var x = 0; x < 5; x++) {
        c[x] = a[y + x];
      }
      for (var x = 0; x < 5; x++) {
        a[y + x] = c[x] ^ (~c[(x + 1) % 5] & c[(x + 2) % 5]);
      }
    }
    // Iota.
    a[0] ^= _roundConstants[round];
  }
}
