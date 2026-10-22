import 'dart:typed_data';

/// What a QR code gave: its text, and its bytes.
///
/// The peer invitation of nodo (`docs/celaut/invite.md`) is binary: a protobuf in byte mode,
/// so its bytes are not text, and the text that a decoder makes from them is not the data.
/// A code of text (a node address) has both.
class ScannedCode {
  const ScannedCode({this.text, this.bytes});

  /// A code of text, as the tests and the callers that read only text have it.
  const ScannedCode.text(String this.text) : bytes = null;

  final String? text;
  final Uint8List? bytes;
}

/// True if [bytes] begin as the invitation of nodo does: field 1, `public_key`, with 32
/// bytes. A protobuf writer puts the fields in order, so the key comes first. The text of a
/// QR code of an address cannot begin so (a new line and a space). The check is only for
/// the choice between the two forms: Rust reads the invitation and refuses what is not one.
bool looksLikeInvite(Uint8List? bytes) =>
    bytes != null && bytes.length > 34 && bytes[0] == 0x0a && bytes[1] == 0x20;
