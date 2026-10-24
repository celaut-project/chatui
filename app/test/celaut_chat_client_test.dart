import 'dart:typed_data';

import 'package:argus_wallet/celaut/chat/gen/chat.pbgrpc.dart' as pb;
import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:argus_wallet/celaut/sha3.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';

import 'support/fake_chat_service.dart';

/// Wait until [condition] is true. The fake service and the client run in this isolate.
Future<void> until(bool Function() condition, {String what = 'condition'}) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timeout while it waited for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Uint8List bytes(int n, [int seed = 1]) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + seed) & 255]);

void main() {
  late FakeChatService svc;
  late TcpProxy proxy;
  late ChatClient chat;
  var booted = false;

  Future<void> boot({
    Duration ackEvery = const Duration(milliseconds: 150),
    Duration stableAfter = const Duration(seconds: 10),
    Duration callTimeout = const Duration(seconds: 5),
  }) async {
    final port = await svc.start();
    proxy = TcpProxy(port);
    await proxy.start();
    booted = true;
    chat = ChatClient(
      port: proxy.port,
      reconnectWaits: const [Duration(milliseconds: 60)],
      stableAfter: stableAfter,
      ackEvery: ackEvery,
      callTimeout: callTimeout,
      channelBackoff: (_) => const Duration(milliseconds: 50),
    );
  }

  setUp(() {
    svc = FakeChatService();
    booted = false;
  });
  tearDown(() async {
    if (!booted) return;
    await chat.close();
    await proxy.stop();
    await svc.stop();
  });

  group('sha3_256', () {
    test('matches the vectors of NIST', () {
      expect(hex(sha3_256([])), 'a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a');
      expect(hex(sha3_256('abc'.codeUnits)), '3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532');
      expect(
        hex(sha3_256(('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq').codeUnits)),
        '41c0dba2a9d6240849100376a8235e2c82e1b9998a999e21db32dd97496d3376',
      );
      // The type of a hash is the digest of an empty input (`docs/celaut/chat.md`, 6.4).
      expect(ChatClient.sha3Type, sha3_256([]));
    });
  });

  group('history', () {
    test('sync reads capabilities and the history from 1, and the table of replies', () async {
      final u = svc.user('hello', key: 'k1');
      svc.assistant('hi', replyTo: u.messageId, reasoning: 'think', pinned: true);
      svc.user('again');
      svc.assistant('stopped', status: pb.MessageStatus.MESSAGE_STATUS_CANCELLED);
      svc.assistant('later', replyTo: 'unknown', status: pb.MessageStatus.MESSAGE_STATUS_FAILED);
      await boot();
      await chat.sync();
      expect(chat.count, 5);
      expect(chat.accepts, {'image', 'audio'});
      final m = chat.messages;
      expect(m.map((e) => e.seq), [1, 2, 3, 4, 5]);
      expect(m[0].cid, 'k1');
      expect(m[0].fromUser, isTrue);
      expect(m[1].replyTo, 1);
      expect(m[1].reasoning, 'think');
      expect(m[1].text, 'hi');
      expect(m[1].pinned, isTrue);
      expect(m[3].isCancelled, isTrue);
      expect(m[3].isOpen, isFalse);
      expect(m[4].isFailed, isTrue);
      expect(m[4].replyTo, isNull);
      expect(svc.reads.first, 0);
      expect(svc.capabilityCalls, 1);
      expect(chat.awaitingAnswer, isFalse);
    });

    test('a read that is shorter than the history is read again until it is empty', () async {
      for (var i = 0; i < 5; i++) {
        svc.user('m$i');
      }
      svc.readLimit = 2;
      await boot();
      await chat.sync();
      expect(chat.count, 5);
      expect(svc.reads, [0, 2, 4, 5]);
    });

    test('a gap in a read is a bad answer', () async {
      svc.user('a');
      svc.gapInReads = true;
      await boot();
      await expectLater(
        chat.sync(),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badAnswer)),
      );
    });

    test('a message above the limit of the client is a bad answer', () async {
      svc.user('x' * (ChatClient.maxMessageBytes + 10));
      await boot();
      await expectLater(
        chat.sync(),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badAnswer)),
      );
    });

    test('a message of another conversation is ignored', () async {
      svc.user('a');
      svc.user('b').conversationId = 'other';
      await boot();
      await chat.sync();
      expect(chat.count, 1);
    });

    test('an unreachable service is unreachable', () async {
      final port = await svc.start();
      await svc.stop();
      proxy = TcpProxy(port);
      await proxy.start();
      booted = true;
      chat = ChatClient(
        port: proxy.port,
        callTimeout: const Duration(seconds: 1),
        channelBackoff: (_) => const Duration(milliseconds: 20),
      );
      await expectLater(
        chat.sync(),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.unreachable)),
      );
    });

    test('syncWhenStarted calls again with the waits until the service listens', () async {
      final port = await svc.start();
      await svc.stop();
      proxy = TcpProxy(port);
      await proxy.start();
      booted = true;
      chat = ChatClient(
        port: proxy.port,
        callTimeout: const Duration(seconds: 1),
        channelBackoff: (_) => const Duration(milliseconds: 20),
      );
      final waits = <Duration>[];
      svc.user('ready');
      await chat.syncWhenStarted(wait: (d) async {
        waits.add(d);
        if (waits.length == 2) await svc.start(port);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(waits, ChatClient.startWaits.take(2).toList());
      expect(chat.count, 1);
    });
  });

  group('stream', () {
    test('the events change the messages, and the client does not read', () async {
      final u = svc.user('q');
      final a = svc.assistant('', replyTo: u.messageId, status: pb.MessageStatus.MESSAGE_STATUS_IN_PROGRESS);
      await boot();
      var notices = 0;
      chat.addListener(() => notices++);
      await chat.sync();
      await until(() => chat.streaming, what: 'stream ready');
      // The first open message is where the stream starts: `after_sequence` 1.
      expect(svc.subscribes, [1]);
      expect(chat.awaitingAnswer, isTrue);
      final reads = svc.reads.length;

      svc.emitDelta(a.messageId, reasoning: 'think');
      svc.emitDelta(a.messageId, text: 'Hel');
      svc.emitDelta(a.messageId, text: 'lo');
      await until(() => chat.messages.last.text == 'Hello');
      expect(chat.messages.last.reasoning, 'think');
      expect(chat.messages.last.isOpen, isTrue);

      svc.setStatus(a.messageId, pb.MessageStatus.MESSAGE_STATUS_COMPLETED);
      await until(() => !chat.messages.last.isOpen);
      expect(chat.messages.last.status, ChatMessage.statusDone);
      expect(chat.awaitingAnswer, isFalse);
      expect(notices, greaterThan(0));

      // A delta of a final message, and of a message that the client does not have.
      svc.emitDelta(a.messageId, text: '!');
      svc.emit(pb.ServerEvent(messageDelta: pb.MessageDelta(messageId: 'nope', textAppend: 'x')));
      // A new message, whole.
      final b = svc.user('next');
      svc.emitCreated(b);
      await until(() => chat.count == 3);
      expect(chat.messages[1].text, 'Hello');

      // A final message does not change when the service creates it again.
      svc.emitCreated(svc.msgs[1]..content.first.text.text = 'changed');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(chat.messages[1].text, 'Hello');

      // `sync` does nothing while the stream is open.
      await chat.sync();
      expect(svc.reads.length, reads);
      expect(svc.connects, 1);
      expect(proxy.connections, 1);
    });

    test('pinned changes for any message, and the user can pin', () async {
      final u = svc.user('q');
      svc.assistant('a', replyTo: u.messageId);
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      expect(chat.messages.any((m) => m.pinned), isFalse);

      svc.setPinned('m1', true);
      await until(() => chat.messages.first.pinned);
      expect(chat.messages.first.fromUser, isTrue);
      expect(chat.messages.first.status, ChatMessage.statusDone);

      await chat.setPinned(chat.messages[1], true);
      expect(chat.messages[1].pinned, isTrue);
      expect(svc.pinCalls, 1);
      svc.setPinned('m1', false);
      await until(() => !chat.messages.first.pinned);
      expect(chat.messages[1].pinned, isTrue);
      expect(chat.messages[1].text, 'a');

      await expectLater(
        chat.setPinned(const ChatMessage(seq: 9, role: 'user', text: '', id: 'zz'), true),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badRequest)),
      );
    });

    test('a message that is cancelled is final', () async {
      final u = svc.user('q');
      final a = svc.assistant('part', replyTo: u.messageId, status: pb.MessageStatus.MESSAGE_STATUS_IN_PROGRESS);
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      svc.setStatus(a.messageId, pb.MessageStatus.MESSAGE_STATUS_CANCELLED);
      await until(() => chat.messages.last.isCancelled);
      expect(chat.messages.last.text, 'part');
      expect(chat.awaitingAnswer, isFalse);
    });

    test('a gap in the events opens the stream again from the last message', () async {
      svc.user('a');
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      // The service skips message 2.
      svc.user('b');
      final c = svc.user('c');
      svc.emitCreated(c);
      await until(() => svc.subscribes.length == 2);
      await until(() => chat.count == 3);
      expect(svc.subscribes, [1, 1]);
      expect(svc.connects, 2);
    });

    test('a service with no Connect: no stream, and the client reads', () async {
      svc.connectError = GrpcError.unimplemented();
      svc.user('a');
      await boot();
      await chat.sync();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(chat.streaming, isFalse);
      expect(svc.connects, 1, reason: 'no new try');
      svc.user('b');
      await chat.sync();
      expect(chat.count, 2);
      expect(svc.reads.length, greaterThan(2));
    });

    test('a lost connection: the stream opens again and replays the open message', () async {
      final u = svc.user('q');
      final a = svc.assistant('one', replyTo: u.messageId, status: pb.MessageStatus.MESSAGE_STATUS_IN_PROGRESS);
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      proxy.drop();
      await until(() => !chat.streaming, what: 'stream lost');
      // The service goes on while the client has no stream.
      svc.emitDelta(a.messageId, text: ' two');
      svc.setStatus(a.messageId, pb.MessageStatus.MESSAGE_STATUS_COMPLETED);
      await until(() => chat.streaming, what: 'stream again');
      await until(() => !chat.messages.last.isOpen);
      expect(chat.messages.last.text, 'one two');
      // `after_sequence` is the `sequence` of the first open message, minus 1.
      expect(svc.subscribes, [1, 1]);
      expect(proxy.connections, 2);
      // The next stream starts at the last message, as no message is open.
      proxy.drop();
      await until(() => svc.subscribes.length == 3);
      expect(svc.subscribes.last, 2);
    });

    test('acknowledge: only when the value rises, and at most once in the interval', () async {
      final u = svc.user('q');
      svc.assistant('a', replyTo: u.messageId);
      final open = svc.assistant('', status: pb.MessageStatus.MESSAGE_STATUS_IN_PROGRESS);
      await boot(ackEvery: const Duration(milliseconds: 400));
      await chat.sync();
      await until(() => chat.streaming);
      List<int> acks() => [
            for (final e in svc.streamEvents)
              if (e.hasAcknowledge()) e.acknowledge.lastSequence.toInt(),
          ];
      await until(() => acks().isNotEmpty);
      // Messages 1 and 2 are final, message 3 is open.
      expect(acks(), [2]);
      svc.setStatus(open.messageId, pb.MessageStatus.MESSAGE_STATUS_COMPLETED);
      final sentAt = DateTime.now();
      final u2 = svc.user('q2');
      svc.emitCreated(u2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(acks(), [2], reason: 'the interval is not over');
      await until(() => acks().length == 2);
      expect(DateTime.now().difference(sentAt), greaterThan(const Duration(milliseconds: 250)));
      expect(acks(), [2, 4]);
      // The same value is not sent again.
      svc.emitDelta(u2.messageId, text: '');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(acks(), [2, 4]);
      // Each event has an event_id, and they are all different.
      final ids = [for (final e in svc.streamEvents) e.eventId];
      expect(ids.every((i) => i.isNotEmpty), isTrue);
      expect(ids.toSet().length, ids.length);
    });
  });

  group('send', () {
    test('over the stream when it is open, with event_id and idempotency_key', () async {
      svc.autoAnswer = true;
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      await chat.send('hello');
      expect(svc.unarySends, isEmpty);
      final e = svc.streamEvents.firstWhere((e) => e.hasSendMessage());
      expect(e.eventId, isNotEmpty);
      expect(e.sendMessage.idempotencyKey, matches(RegExp(r'^[A-Za-z0-9_-]{1,64}$')));
      expect(e.sendMessage.content.single.text.text, 'hello');
      await until(() => chat.count == 2);
      expect(chat.messages[0].cid, e.sendMessage.idempotencyKey);
      expect(chat.messages[1].replyTo, 1);
      expect(chat.messages.map((m) => m.seq), [1, 2]);
    });

    test('with SendMessage when the stream is not open, and each send has a new key', () async {
      svc.autoAnswer = true;
      await boot();
      await chat.send('one');
      await chat.send('two');
      expect(svc.capabilityCalls, 1, reason: 'capabilities first');
      expect(svc.unarySends.length, 2);
      expect(svc.unarySends[0].idempotencyKey, isNot(svc.unarySends[1].idempotencyKey));
      // The reply of the first send is user message 1. The answer was not read yet.
      expect(chat.messages.first.text, 'one');
      expect(chat.messages.first.seq, 1);
      // The second send is at 3: the client reads the gap, and the answer to it.
      expect(chat.messages.map((m) => m.text), ['one', 'echo: one', 'two', 'echo: two']);
      expect(proxy.connections, 1);
    });

    test('errors of the service map to the kinds of section 9', () async {
      await boot();
      for (final (text, kind) in [
        ('bad', ChatErrorKind.badRequest),
        ('busy', ChatErrorKind.busy),
        ('full', ChatErrorKind.historyFull),
        ('media', ChatErrorKind.unsupportedMedia),
      ]) {
        await expectLater(
          chat.send(text),
          throwsA(isA<ChatException>().having((e) => e.kind, text, kind)),
          reason: 'unary $text',
        );
      }
      expect(chat.count, 0);
      svc.sendErrors.add(chatError(StatusCode.internal, 'service_error'));
      await expectLater(
        chat.send('x'),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.other)),
      );
      svc.sendErrors.add(GrpcError.unimplemented());
      await expectLater(
        chat.send('x'),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.other)),
      );
    });

    test('ProtocolError with the event_id fails that send, and the stream stays open', () async {
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      for (final (text, kind) in [
        ('bad', ChatErrorKind.badRequest),
        ('busy', ChatErrorKind.busy),
        ('full', ChatErrorKind.historyFull),
        ('media', ChatErrorKind.unsupportedMedia),
      ]) {
        await expectLater(
          chat.send(text),
          throwsA(isA<ChatException>().having((e) => e.kind, text, kind)),
          reason: 'stream $text',
        );
      }
      expect(chat.streaming, isTrue);
      expect(svc.unarySends, isEmpty);
      expect(svc.connects, 1);
      await chat.send('fine');
      expect(chat.messages.single.text, 'fine');
    });

    test('a reply that is lost: the client reads, finds the key, and does not send again', () async {
      await boot();
      svc.failAfterApply = GrpcError.unavailable();
      await chat.send('once');
      expect(svc.unarySends.length, 1);
      expect(svc.msgs.length, 1);
      expect(chat.messages.single.text, 'once');
    });

    test('a send that did not arrive: the client sends again with the same key, once', () async {
      await boot();
      svc.sendErrors.add(GrpcError.deadlineExceeded());
      await chat.send('twice');
      expect(svc.unarySends.length, 2);
      expect(svc.unarySends[0].idempotencyKey, svc.unarySends[1].idempotencyKey);
      expect(svc.msgs.length, 1);
      // The second try fails too: unreachable.
      svc.sendErrors
        ..add(GrpcError.unavailable())
        ..add(GrpcError.unavailable());
      await expectLater(
        chat.send('never'),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.unreachable)),
      );
      expect(svc.unarySends.length, 4);
      expect(svc.msgs.length, 1);
    });

    test('the stream breaks after a send over the stream: the client follows 6.3', () async {
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      svc.onStreamSend = proxy.drop;
      await chat.send('over');
      expect(svc.msgs.length, 1, reason: 'no second message');
      expect(chat.messages.single.text, 'over');
      await until(() => chat.streaming, what: 'stream again');
    });

    test('limits of the client: nothing goes to the service', () async {
      svc.caps = pb.Capabilities(
        acceptedMimeTypes: ['image/png'],
        maxTextBytes: 10,
        maxFilesPerMessage: 1,
        maxFileBytes: Int64(100),
      );
      await boot();
      Future<void> bad(Future<void> f, ChatErrorKind kind) => expectLater(
            f,
            throwsA(isA<ChatException>().having((e) => e.kind, 'kind', kind)),
          );
      await bad(chat.send(''), ChatErrorKind.badRequest);
      await bad(chat.send('12345678901'), ChatErrorKind.badRequest);
      await bad(chat.send('é' * 6), ChatErrorKind.badRequest, );
      final png = OutgoingAttachment(mime: 'image/png', bytes: bytes(50));
      await bad(chat.send('', attachments: [png, png]), ChatErrorKind.badRequest);
      await bad(
        chat.send('', attachments: [OutgoingAttachment(mime: 'image/png', bytes: bytes(101))]),
        ChatErrorKind.badRequest,
      );
      await bad(
        chat.send('', attachments: [OutgoingAttachment(mime: 'image/png', bytes: Uint8List(0))]),
        ChatErrorKind.badRequest,
      );
      await bad(
        chat.send('', attachments: [OutgoingAttachment(mime: 'image/jpeg', bytes: bytes(5))]),
        ChatErrorKind.unsupportedMedia,
      );
      await bad(
        chat.send('', attachments: [OutgoingAttachment(mime: 'image/gif', bytes: bytes(5))]),
        ChatErrorKind.unsupportedMedia,
      );
      await bad(
        chat.send('', attachments: [OutgoingAttachment(mime: 'application/pdf', bytes: bytes(5))]),
        ChatErrorKind.unsupportedMedia,
      );
      expect(svc.unarySends, isEmpty);
      expect(svc.queries, isEmpty);
      expect(chat.accepts, {'image'});
    });

    test('defaults of the limits when the service sends 0', () async {
      svc.caps = pb.Capabilities(acceptedMimeTypes: ['image/png']);
      await boot();
      await chat.send('é' * 8192);
      await expectLater(
        chat.send('é' * 8193),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badRequest)),
      );
      final png = OutgoingAttachment(mime: 'image/png', bytes: bytes(10));
      await expectLater(
        chat.send('', attachments: List.filled(5, png)),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badRequest)),
      );
    });
  });

  group('files', () {
    test('query, upload in chunks of 64 KiB, then send; a file that is there is not uploaded', () async {
      await boot();
      final big = OutgoingAttachment(mime: 'image/PNG; x=1', bytes: bytes(150 * 1024), name: 'big.png');
      final small = OutgoingAttachment(mime: 'audio/wav', bytes: bytes(1000, 7));
      svc.files[hex(sha3_256(small.bytes))] = small.bytes;
      await chat.send('look', attachments: [big, small]);
      expect(svc.queries.single, [hex(sha3_256(big.bytes)), hex(sha3_256(small.bytes))]);
      expect(svc.uploads.length, 1);
      expect(svc.chunkSizes, [65536, 65536, 150 * 1024 - 2 * 65536]);
      final sent = svc.unarySends.single;
      expect(sent.content.length, 3);
      expect(sent.content[0].text.text, 'look');
      final ref = sent.content[1].image.file;
      expect(ref.mimeType, 'image/png');
      expect(ref.sizeBytes.toInt(), 150 * 1024);
      expect(ref.filename, 'big.png');
      expect(ref.hashes.single.type, ChatClient.sha3Type);
      expect(ref.hashes.single.value, sha3_256(big.bytes));
      expect(sent.content[2].audio.file.mimeType, 'audio/wav');
      // The message in the list has the files, and the bytes are in memory.
      final m = chat.messages.single;
      expect(m.attachments.map((a) => (a.kind, a.mime, a.size)), [
        ('image', 'image/png', 150 * 1024),
        ('audio', 'audio/wav', 1000),
      ]);
      expect(await chat.readAttachment(1, 0), big.bytes);
      expect(svc.downloads, 0);
    });

    test('a send with a file and no text, over the stream', () async {
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      final f = OutgoingAttachment(mime: 'image/jpeg', bytes: bytes(300));
      await chat.send('', attachments: [f]);
      expect(svc.streamEvents.where((e) => e.hasSendMessage()).single.sendMessage.content.single.hasImage(), isTrue);
      expect(proxy.connections, 1, reason: 'the stream, the query and the upload share one connection');
    });

    test('download checks the hash, and keeps the bytes once', () async {
      final data = bytes(70000, 3);
      svc.files[hex(sha3_256(data))] = data;
      final ref = pb.FileReference(
        hashes: [pb.Hash(type: ChatClient.sha3Type, value: sha3_256(data))],
        mimeType: 'image/png',
        sizeBytes: Int64(data.length),
      );
      svc.user('', extra: [pb.ContentPart(image: pb.ImageContent(file: ref))]);
      await boot();
      await chat.sync();
      final got = await Future.wait([chat.readAttachment(1, 0), chat.readAttachment(1, 0)]);
      expect(got[0], data);
      expect(await chat.readAttachment(1, 0), data);
      expect(svc.downloads, 1);
    });

    test('a download with the wrong bytes is a bad answer and is not kept', () async {
      final data = bytes(1000);
      svc.files[hex(sha3_256(data))] = data;
      final ref = pb.FileReference(
        hashes: [pb.Hash(type: ChatClient.sha3Type, value: sha3_256(data))],
        mimeType: 'image/png',
        sizeBytes: Int64(data.length),
      );
      svc.user('', extra: [pb.ContentPart(image: pb.ImageContent(file: ref))]);
      await boot();
      await chat.sync();
      Future<void> bad() => expectLater(
            chat.readAttachment(1, 0),
            throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badAnswer)),
          );
      svc.downloadOverride = bytes(1000, 9);
      await bad();
      svc.downloadOverride = bytes(2000);
      await bad();
      svc.downloadOverride = bytes(10);
      await bad();
      svc.downloadOverride = null;
      expect(await chat.readAttachment(1, 0), data);
    });

    test('a message without a SHA3-256 hash gives no file; a file that is not there is an error', () async {
      final ref = pb.FileReference(
        hashes: [pb.Hash(type: [1, 2, 3], value: [4])],
        mimeType: 'image/png',
        sizeBytes: Int64(4),
      );
      svc.user('', extra: [pb.ContentPart(image: pb.ImageContent(file: ref))]);
      final missing = pb.FileReference(
        hashes: [pb.Hash(type: ChatClient.sha3Type, value: bytes(32))],
        mimeType: 'image/png',
        sizeBytes: Int64(4),
      );
      svc.user('', extra: [pb.ContentPart(image: pb.ImageContent(file: missing))]);
      await boot();
      await chat.sync();
      await expectLater(
        chat.readAttachment(1, 0),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badAnswer)),
      );
      await expectLater(
        chat.readAttachment(2, 0),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badRequest)),
      );
      await expectLater(chat.readAttachment(7, 0), throwsA(isA<ChatException>()));
    });

    test('file_missing: upload again and send again with the same key, once', () async {
      await boot();
      final f = OutgoingAttachment(mime: 'image/png', bytes: bytes(500));
      svc.fileMissingTimes = 1;
      await chat.send('x', attachments: [f]);
      expect(svc.unarySends.length, 2);
      expect(svc.unarySends[0].idempotencyKey, svc.unarySends[1].idempotencyKey);
      expect(svc.uploads.length, 2, reason: 'uploaded again, without a query');
      expect(svc.queries.length, 1);
      expect(chat.count, 1);
      // It fails again: the user is told, and the client does not try a third time.
      svc.fileMissingTimes = 5;
      await expectLater(
        chat.send('y', attachments: [f]),
        throwsA(isA<ChatException>().having((e) => e.reason, 'reason', 'file_missing')),
      );
      expect(svc.unarySends.length, 4);
    });

    test('an upload that the service refuses', () async {
      await boot();
      svc.uploadError = chatError(StatusCode.invalidArgument, 'hash_mismatch');
      await expectLater(
        chat.send('', attachments: [OutgoingAttachment(mime: 'image/png', bytes: bytes(10))]),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badRequest)),
      );
      svc.uploadError = chatError(StatusCode.invalidArgument, 'unsupported_media');
      await expectLater(
        chat.send('', attachments: [OutgoingAttachment(mime: 'image/png', bytes: bytes(10))]),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.unsupportedMedia)),
      );
      expect(svc.unarySends, isEmpty);
    });

    test('the cache keeps at most 24 MiB for other messages', () async {
      await boot();
      final a = OutgoingAttachment(mime: 'image/png', bytes: bytes(4 * 1024 * 1024));
      for (var i = 0; i < 7; i++) {
        await chat.send('', attachments: [OutgoingAttachment(mime: 'image/png', bytes: bytes(4 * 1024 * 1024, i + 1))]);
      }
      expect(a.bytes.length, 4 * 1024 * 1024);
      // The first files were dropped, and the service gives them again.
      expect(await chat.readAttachment(1, 0), bytes(4 * 1024 * 1024, 1));
      expect(svc.downloads, 1);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('close', () {
    test('close ends the stream and the connection, and the listeners get no more', () async {
      svc.user('a');
      await boot();
      await chat.sync();
      await until(() => chat.streaming);
      var notices = 0;
      chat.addListener(() => notices++);
      await chat.close();
      await until(() => svc.openStreams == 0, what: 'stream closed');
      svc.emitCreated(svc.user('b'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notices, 0);
      expect(chat.count, 1);
    });
  });
}
