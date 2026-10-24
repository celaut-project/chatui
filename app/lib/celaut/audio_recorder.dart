import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'chat_client.dart';

/// Records a voice message for a chat. One recording at a time: [start], then [stop] (the
/// recording as a WAV attachment) or [cancel] (nothing is kept).
abstract class AudioRecorderService {
  /// Starts to record. Returns false, and records nothing, if the user denies the
  /// microphone permission or the device cannot record.
  Future<bool> start();

  /// Ends the recording and returns it as `audio/wav`, or null if no recording is open or
  /// it has no sound.
  Future<OutgoingAttachment?> stop();

  /// Ends the recording and drops its sound.
  Future<void> cancel();

  /// The length of the open recording, about every 200 ms. It ends after [stop] or
  /// [cancel], and it also ends when the recording stops by itself at the size limit. Each
  /// recording has its own stream: read it after [start] gives true. When it ends without
  /// a call to [stop] or [cancel], the limit is reached: call [stop] to get the sound.
  Stream<Duration> get elapsed;
}

/// The format of a recording: PCM 16-bit little-endian, 16 kHz, mono.
const int audioSampleRate = 16000;
const int _bytesPerSecond = audioSampleRate * 2;
const int _wavHeaderBytes = 44;

/// The bytes of a recording that fit in an attachment, with the WAV header.
const int maxAudioPcmBytes = ChatClient.maxAttachmentBytes - _wavHeaderBytes;

/// The length of the sound in [pcmBytes] bytes of PCM.
Duration pcmDuration(int pcmBytes) =>
    Duration(microseconds: pcmBytes * 1000000 ~/ _bytesPerSecond);

/// Wraps PCM 16-bit mono 16 kHz in a WAV (RIFF) file.
Uint8List encodeWav(Uint8List pcm) {
  final out = ByteData(_wavHeaderBytes + pcm.length);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // fmt chunk size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, audioSampleRate, Endian.little);
  out.setUint32(28, _bytesPerSecond, Endian.little);
  out.setUint16(32, 2, Endian.little); // block align
  out.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  out.setUint32(40, pcm.length, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(_wavHeaderBytes, bytes.length, pcm);
  return bytes;
}

/// The recorder of the app, on the `record` package. It reads the PCM stream into memory
/// (no file on the disk) and builds the WAV at [stop]. It stops by itself when the next
/// block would pass [ChatClient.maxAttachmentBytes]; [stop] still returns what it has.
class RecordAudioRecorder implements AudioRecorderService {
  RecordAudioRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  // The plugin can reuse the buffer of a block: the builder copies each block.
  final BytesBuilder _pcm = BytesBuilder();
  StreamController<Duration> _elapsed = StreamController<Duration>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  bool _open = false;
  bool _starting = false;
  bool _disposed = false;

  @override
  Stream<Duration> get elapsed => _elapsed.stream;

  @override
  Future<bool> start() async {
    if (_open || _starting || _disposed) return false;
    _starting = true;
    try {
      if (!await _recorder.hasPermission() || _disposed) return false;
      _pcm.clear();
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: audioSampleRate,
        numChannels: 1,
      ));
      if (_disposed) {
        // The screen closed while the microphone opened: close it again.
        await _recorder.stop();
        return false;
      }
      if (_elapsed.isClosed) _elapsed = StreamController<Duration>.broadcast();
      _open = true;
      _sub = stream.listen(_onData, onError: (Object _) => unawaited(_end()));
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!_elapsed.isClosed) _elapsed.add(pcmDuration(_pcm.length));
      });
      return true;
    } on Object {
      await _end();
      return false;
    } finally {
      _starting = false;
    }
  }

  void _onData(Uint8List block) {
    if (!_open) return;
    final room = maxAudioPcmBytes - _pcm.length;
    if (block.length >= room) {
      // Keep whole samples only, and stop: the limit is reached.
      _pcm.add(Uint8List.sublistView(block, 0, room - room % 2));
      unawaited(_end(keep: true));
    } else {
      _pcm.add(block);
    }
  }

  /// Stops the capture. [keep] false drops the sound.
  Future<void> _end({bool keep = false}) async {
    final wasOpen = _open;
    _open = false;
    _ticker?.cancel();
    _ticker = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    if (wasOpen) {
      try {
        await _recorder.stop();
      } on Object {
        // The recorder is already stopped.
      }
    }
    if (!keep) _pcm.clear();
    // The stream of the length ends with the recording.
    if (!_elapsed.isClosed) await _elapsed.close();
  }

  @override
  Future<OutgoingAttachment?> stop() async {
    await _end(keep: true);
    final pcm = _pcm.takeBytes();
    if (pcm.isEmpty) return null;
    return OutgoingAttachment(
      mime: 'audio/wav',
      bytes: encodeWav(pcm),
      name: 'voice.wav',
    );
  }

  @override
  Future<void> cancel() => _end();

  /// Frees the recorder.
  Future<void> dispose() async {
    _disposed = true;
    await _end();
    await _recorder.dispose();
  }
}
