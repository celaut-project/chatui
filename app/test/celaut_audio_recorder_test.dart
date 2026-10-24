import 'dart:async';
import 'dart:typed_data';

import 'package:argus_wallet/celaut/audio_recorder.dart';
import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recorder for the tests of the UI: no microphone.
class FakeAudioRecorder implements AudioRecorderService {
  FakeAudioRecorder({this.permitted = true, Uint8List? pcm})
      : pcm = pcm ?? Uint8List(3200);

  final bool permitted;
  final Uint8List pcm;
  final _elapsed = StreamController<Duration>.broadcast();
  bool open = false;

  @override
  Stream<Duration> get elapsed => _elapsed.stream;

  @override
  Future<bool> start() async => open = permitted;

  @override
  Future<OutgoingAttachment?> stop() async {
    if (!open) return null;
    open = false;
    return OutgoingAttachment(
        mime: 'audio/wav', bytes: encodeWav(pcm), name: 'voice.wav');
  }

  @override
  Future<void> cancel() async => open = false;
}

void main() {
  test('encodeWav writes a RIFF header for 16 kHz mono 16 bit', () {
    final wav = encodeWav(Uint8List.fromList([1, 2, 3, 4]));
    final d = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(d.getUint32(4, Endian.little), 36 + 4);
    expect(d.getUint16(22, Endian.little), 1);
    expect(d.getUint32(24, Endian.little), 16000);
    expect(d.getUint32(28, Endian.little), 32000);
    expect(d.getUint16(34, Endian.little), 16);
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    expect(d.getUint32(40, Endian.little), 4);
    expect(wav.sublist(44), [1, 2, 3, 4]);
  });

  test('a full recording fits in an attachment', () {
    final wav = encodeWav(Uint8List(maxAudioPcmBytes));
    expect(wav.length, ChatClient.maxAttachmentBytes);
  });

  test('pcmDuration counts 32000 bytes per second', () {
    expect(pcmDuration(32000), const Duration(seconds: 1));
    expect(pcmDuration(16000), const Duration(milliseconds: 500));
  });

  test('the fake returns false when the permission is denied', () async {
    final r = FakeAudioRecorder(permitted: false);
    expect(await r.start(), isFalse);
    expect(await r.stop(), isNull);
  });

  test('the fake records, stops and cancels', () async {
    final r = FakeAudioRecorder();
    expect(await r.start(), isTrue);
    final a = await r.stop();
    expect(a!.mime, 'audio/wav');
    expect(a.bytes.length, 44 + 3200);
    expect(await r.start(), isTrue);
    await r.cancel();
    expect(await r.stop(), isNull);
  });
}
