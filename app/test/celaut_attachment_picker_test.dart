import 'dart:typed_data';

import 'package:argus_wallet/celaut/attachment_picker.dart';
import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:flutter_test/flutter_test.dart';

OutgoingAttachment _file(String name, {int size = 4}) =>
    OutgoingAttachment(mime: 'audio/wav', bytes: Uint8List(size), name: name);

void main() {
  test('only the four types that every service accepts have a media type', () {
    expect(attachmentMime('a.JPG'), 'image/jpeg');
    expect(attachmentMime('a.jpeg'), 'image/jpeg');
    expect(attachmentMime('a.png'), 'image/png');
    expect(attachmentMime('a.mp3'), 'audio/mpeg');
    expect(attachmentMime('a.wav'), 'audio/wav');
    for (final other in ['webp', 'gif', 'm4a', 'aac', 'ogg', 'heic']) {
      expect(attachmentMime('a.$other'), isNull);
    }
    expect(attachmentMime('noextension'), isNull);
  });

  group('selectAttachments', () {
    test('keeps the good files and counts the others by reason', () {
      final picked = selectAttachments(
        [
          _file('a.wav'),
          _file('a.wav'),
          _file('empty.wav', size: 0),
          _file('big.wav', size: ChatClient.maxAttachmentBytes + 1),
          _file('b.wav'),
          _file('c.wav'),
          _file('d.wav'),
          _file('e.wav'),
        ],
        const [],
        unreadable: 1,
      );
      expect(picked.files.map((f) => f.name), ['a.wav', 'b.wav', 'c.wav', 'd.wav']);
      expect(picked.duplicates, 1);
      expect(picked.invalid, 3);
      expect(picked.tooMany, 1);
      expect(picked.skipped, 5);
    });

    test('a file of the same name and another size is not a duplicate', () {
      final picked = selectAttachments([_file('a.wav', size: 5)], [_file('a.wav')]);
      expect(picked.files, hasLength(1));
      expect(picked.skipped, 0);
    });

    test('counts the files that the message already has', () {
      final picked = selectAttachments(
          [_file('c.wav'), _file('d.wav')], [_file('a.wav'), _file('b.wav'), _file('x.wav')]);
      expect(picked.files.map((f) => f.name), ['c.wav']);
      expect(picked.tooMany, 1);
    });

    test('a file of exactly the limit stays', () {
      final picked =
          selectAttachments([_file('a.wav', size: ChatClient.maxAttachmentBytes)], const []);
      expect(picked.files, hasLength(1));
    });
  });
}
