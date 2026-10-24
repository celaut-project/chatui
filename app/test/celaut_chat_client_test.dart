import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:argus_wallet/celaut/tunnel_http.dart';
import 'package:flutter_test/flutter_test.dart';

/// A local service that follows `docs/celaut/chat.md` (revision 5), with switches to break
/// it. It echoes each user message in an assistant message, as a whole answer or as an
/// answer that grows.
class EchoService {
  EchoService._(this.server);

  final HttpServer server;
  final connections = <int>{};
  final messages = <Map<String, Object>>[];

  /// The `from` of each read of the history that the service got.
  final reads = <String>[];

  /// The next POST is applied, but the connection is closed with no reply.
  bool dropNextAnswer = false;

  /// The next POST is not applied, and the connection is closed with no reply.
  bool dropNextPostBeforeApply = false;

  /// The next POST gets this status with no change to the history.
  int? failNextWith;

  /// The next GET gets this body with status 200.
  String? nextHistoryBody;

  /// The answer starts after this wait: a slow service. The user message is there before.
  Duration? answerDelay;

  /// The answer never starts.
  bool answerNever = false;

  /// The answer is an open message that the test makes grow with [grow] and [finish].
  bool streaming = false;

  /// The next POST waits for this to complete before anything is applied.
  Completer<void>? holdNextPost;

  /// The most messages in the answer to a read, or null for all of them.
  int? maxPerRead;

  /// The wait before a file is given.
  Duration fileDelay = Duration.zero;

  /// The reads of files that the service got.
  int fileReads = 0;

  /// The kinds that the service says it accepts in each read of the history.
  List<String>? accepts;

  /// The files of the messages, by `seq` and index.
  final files = <(int, int), List<int>>{};

  static Future<EchoService> start({int port = 0}) async {
    final s = EchoService._(await HttpServer.bind(InternetAddress.loopbackIPv4, port));
    s.server.listen(s._handle);
    return s;
  }

  int get port => server.port;

  Future<void> close() => server.close(force: true);

  /// The user messages.
  List<Map<String, Object>> get users => [
        for (final m in messages)
          if (m['role'] == 'user') m,
      ];

  /// Add [text] and [reasoning] at the end of the open message at [seq].
  void grow(int seq, {String text = '', String reasoning = ''}) {
    final m = messages[seq];
    m['text'] = (m['text'] as String) + text;
    m['reasoning'] = (m['reasoning'] as String) + reasoning;
  }

  /// The open message at [seq] ends, as done or as failed.
  void finish(int seq, {String status = 'done'}) => messages[seq]['status'] = status;

  Future<void> _reply(HttpResponse response, int status, Object body) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    try {
      await response.close();
    } on Object {
      // The client gave up and closed the connection.
    }
  }

  Future<void> _handle(HttpRequest request) async {
    connections.add(request.connectionInfo!.remotePort);
    final response = request.response;
    final file = RegExp(r'^/chat/messages/(\d+)/attachments/(\d+)$').firstMatch(request.uri.path);
    if (file != null) {
      fileReads++;
      await Future<void>.delayed(fileDelay);
      final bytes = files[(int.parse(file.group(1)!), int.parse(file.group(2)!))];
      if (bytes == null) {
        await _reply(response, 404, {'error': 'not_found'});
        return;
      }
      response
        ..statusCode = 200
        ..headers.contentType = ContentType('image', 'png')
        ..add(bytes);
      await response.close();
      return;
    }
    if (request.uri.path != '/chat/messages') {
      await _reply(response, 404, {'error': 'not_found'});
      return;
    }
    if (request.method == 'GET') {
      final override = nextHistoryBody;
      if (override != null) {
        nextHistoryBody = null;
        response
          ..statusCode = 200
          ..write(override);
        await response.close();
        return;
      }
      reads.add(request.uri.query);
      final query = request.uri.queryParameters;
      var from = int.parse(query['from'] ?? '0');
      if (query['last'] != null) from = max(0, messages.length - int.parse(query['last']!));
      var chosen = messages.skip(from);
      final limit = [
        if (query['limit'] != null) int.parse(query['limit']!),
        if (maxPerRead != null) maxPerRead!,
      ];
      if (limit.isNotEmpty) chosen = chosen.take(limit.reduce(min));
      await _reply(response, 200, {
        'count': messages.length,
        if (accepts != null) 'accepts': accepts,
        'messages': chosen.toList(),
      });
      return;
    }
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
    final hold = holdNextPost;
    if (hold != null) {
      holdNextPost = null;
      await hold.future;
    }
    if (dropNextPostBeforeApply) {
      dropNextPostBeforeApply = false;
      final socket = await response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    final status = failNextWith;
    if (status != null) {
      failNextWith = null;
      await _reply(response, status, {'error': 'x', 'message': 'for the user'});
      return;
    }
    final cid = body['cid'] as String?;
    if (cid != null) {
      for (final m in messages) {
        if (m['cid'] == cid) {
          await _reply(response, 200, {'count': messages.length, 'message': m});
          return;
        }
      }
    }
    final text = body['text'] as String;
    final sent = (body['attachments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final user = <String, Object>{
      'seq': messages.length,
      'role': 'user',
      'text': text,
      'status': 'done',
      if (cid != null) 'cid': cid,
      if (sent.isNotEmpty)
        'attachments': [
          for (var i = 0; i < sent.length; i++)
            {
              'kind': (sent[i]['mime'] as String).split('/').first,
              'mime': sent[i]['mime'],
              if (sent[i]['name'] != null) 'name': sent[i]['name'],
              'size': base64Decode(sent[i]['data'] as String).length,
            },
        ],
    };
    for (var i = 0; i < sent.length; i++) {
      files[(messages.length, i)] = base64Decode(sent[i]['data'] as String);
    }
    messages.add(user);
    unawaited(_answer(user));
    if (dropNextAnswer) {
      dropNextAnswer = false;
      final socket = await response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    await _reply(response, 200, {'count': messages.length, 'message': user});
  }

  /// The answer to [user]: after the reply of the send, as the convention says.
  Future<void> _answer(Map<String, Object> user) async {
    await Future<void>.delayed(answerDelay ?? Duration.zero);
    if (answerNever) return;
    messages.add({
      'seq': messages.length,
      'role': 'assistant',
      'text': streaming ? '' : user['text']!,
      if (streaming) 'reasoning': '',
      'status': streaming ? 'streaming' : 'done',
      'reply_to': user['seq']!,
    });
  }
}

void main() {
  late EchoService service;
  late TunnelHttp http;
  late ChatClient chat;

  setUp(() async {
    service = await EchoService.start();
    http = TunnelHttp();
    chat = ChatClient(port: service.port, http: http);
  });
  tearDown(() async {
    http.close();
    await service.close();
  });

  Matcher kind(ChatErrorKind k) => throwsA(isA<ChatException>().having((e) => e.kind, 'kind', k));

  /// Let the service make its answers, then read them.
  Future<void> answered([ChatClient? client]) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await (client ?? chat).sync();
  }

  test('a send gives the user message at once and does not wait for the answer', () async {
    service.answerNever = true;
    await chat.send('Hello');
    expect(chat.messages.map((m) => m.role), ['user']);
    expect(chat.messages.single.text, 'Hello');
    expect(chat.awaitingAnswer, isTrue);
  });

  test('the answer comes with the next read', () async {
    await chat.send('Hello');
    await answered();
    expect(chat.count, 2);
    expect(chat.messages.map((m) => m.role), ['user', 'assistant']);
    expect(chat.messages.map((m) => m.text), ['Hello', 'Hello']);
    expect(chat.messages.last.replyTo, 0);
    expect(chat.awaitingAnswer, isFalse);
  });

  test('messages are numbered and share one connection', () async {
    await chat.send('one');
    await answered();
    await chat.send('two');
    await answered();
    expect(chat.messages.map((m) => m.seq), [0, 1, 2, 3]);
    expect(service.connections, hasLength(1));
  });

  test('sends at the same time are all taken, and each has its own cid', () async {
    await Future.wait([chat.send('a'), chat.send('b'), chat.send('c')]);
    await answered();
    expect(chat.messages.map((m) => m.seq), [0, 1, 2, 3, 4, 5]);
    expect(chat.messages.where((m) => m.fromUser).map((m) => m.text), ['a', 'b', 'c']);
    final cids = chat.messages.where((m) => m.fromUser).map((m) => m.cid).toSet();
    expect(cids, hasLength(3));
    expect(cids.every((c) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(c!)), isTrue);
  });

  test('a message sent while an answer is made is taken, and it is not out of order', () async {
    service.answerDelay = const Duration(milliseconds: 100);
    await chat.send('a');
    await chat.send('b');
    // The two answers come later, so the user messages have the seq 0 and 1.
    expect(chat.messages.map((m) => m.seq), [0, 1]);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await chat.sync();
    expect(chat.messages.map((m) => m.role), ['user', 'user', 'assistant', 'assistant']);
    expect(chat.messages.where((m) => !m.fromUser).map((m) => m.replyTo), [0, 1]);
  });

  test('an answer that comes first makes a gap that the send reads', () async {
    // The answer to an earlier message is added between two sends.
    service.messages.add({'seq': 0, 'role': 'user', 'text': 'x', 'status': 'done'});
    service.answerNever = true;
    await chat.send('y');
    expect(chat.messages.map((m) => m.seq), [0, 1]);
    expect(chat.messages.last.text, 'y');
  });

  group('an instance that has just started', () {
    Future<int> freePort() async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    }

    test('is read again, with longer waits, until the service answers', () async {
      final port = await freePort();
      final late = ChatClient(port: port, http: http);
      final waits = <Duration>[];
      EchoService? started;
      await late.syncWhenStarted(
        wait: (d) async {
          waits.add(d);
          if (waits.length == 2) started = await EchoService.start(port: port);
        },
      );
      addTearDown(() => started?.close());
      expect(waits, const [Duration(seconds: 2), Duration(seconds: 3)]);
      expect(late.count, 0);
      await late.send('hi');
      await late.sync();
      expect(late.messages.map((m) => m.text), ['hi', 'hi']);
    });

    test('gives up after the limit as unreachable', () async {
      final late = ChatClient(port: await freePort(), http: http);
      final waits = <Duration>[];
      await expectLater(
        late.syncWhenStarted(limit: const Duration(seconds: 10), wait: (d) async => waits.add(d)),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.unreachable)),
      );
      expect(waits, const [Duration(seconds: 2), Duration(seconds: 3), Duration(seconds: 5)]);
    });

    test('the waits stay at 10 seconds after the first ones', () async {
      final late = ChatClient(port: await freePort(), http: http);
      final waits = <Duration>[];
      await expectLater(
        late.syncWhenStarted(limit: const Duration(seconds: 45), wait: (d) async => waits.add(d)),
        throwsA(isA<ChatException>()),
      );
      expect(waits.map((d) => d.inSeconds), [2, 3, 5, 8, 10, 10, 10]);
    });

    test('an answer that does not follow the convention is not read again', () async {
      service.nextHistoryBody = 'not json';
      final waits = <Duration>[];
      await expectLater(
        chat.syncWhenStarted(wait: (d) async => waits.add(d)),
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badAnswer)),
      );
      expect(waits, isEmpty);
    });
  });

  test('sync reads the history of a running instance', () async {
    await ChatClient(port: service.port, http: http).send('one');
    await answered();
    await chat.sync();
    expect(chat.messages.map((m) => m.text), ['one', 'one']);
    await chat.sync();
    expect(chat.count, 2);
  });

  group('an answer that grows', () {
    setUp(() => service.streaming = true);

    test('is replaced at each read, with the reasoning apart from the text', () async {
      await chat.send('think');
      await answered();
      var answer = chat.messages.last;
      expect(answer.isOpen, isTrue);
      expect(answer.text, '');
      expect(chat.awaitingAnswer, isTrue);

      service.grow(1, reasoning: 'Let me see. ');
      await chat.sync();
      service.grow(1, reasoning: 'Yes.', text: 'Hel');
      await chat.sync();
      answer = chat.messages.last;
      expect(answer.reasoning, 'Let me see. Yes.');
      expect(answer.text, 'Hel');
      expect(chat.count, 2);

      service.grow(1, text: 'lo');
      service.finish(1);
      await chat.sync();
      answer = chat.messages.last;
      expect(answer.text, 'Hello');
      expect(answer.isOpen, isFalse);
      expect(answer.isFailed, isFalse);
      expect(chat.awaitingAnswer, isFalse);
    });

    test('is read from its own seq, and from the end when no message is open', () async {
      await chat.send('think');
      await answered();
      service.reads.clear();
      await chat.sync();
      service.grow(1, text: 'a');
      await chat.sync();
      service.finish(1);
      await chat.sync();
      await chat.sync();
      // Two reads from the open message, one that ends it, then from the end.
      expect(service.reads, ['from=1', 'from=1', 'from=1', 'from=2']);
    });

    test('a final message is not changed by a later read', () async {
      await chat.send('think');
      await answered();
      service.grow(1, text: 'done');
      service.finish(1);
      await chat.sync();
      service.messages[1]['text'] = 'changed';
      await chat.sync();
      expect(chat.messages.last.text, 'done');
    });

    test('a failed answer keeps what it has and ends the wait', () async {
      await chat.send('think');
      await answered();
      service.grow(1, text: 'Half');
      service.finish(1, status: 'failed');
      await chat.sync();
      expect(chat.messages.last.isFailed, isTrue);
      expect(chat.messages.last.text, 'Half');
      expect(chat.awaitingAnswer, isFalse);
    });

    test('a message is still sent while an answer grows', () async {
      await chat.send('one');
      await answered();
      await chat.send('two');
      await answered();
      expect(chat.messages.map((m) => m.role), ['user', 'assistant', 'user', 'assistant']);
      expect(chat.messages.where((m) => m.isOpen), hasLength(2));
    });
  });

  test('a message with an unknown status is a bad answer', () async {
    service.nextHistoryBody = jsonEncode({
      'count': 1,
      'messages': [
        {'seq': 0, 'role': 'assistant', 'text': 'x', 'status': 'later'},
      ],
    });
    await expectLater(chat.sync(), kind(ChatErrorKind.badAnswer));
  });

  group('pinned', () {
    Future<void> read(Map<String, Object?> message) async {
      service.nextHistoryBody = jsonEncode({
        'count': 1,
        'messages': [message],
      });
      await chat.sync();
    }

    test('pinned is false if the field is absent', () async {
      await read({'seq': 0, 'role': 'assistant', 'text': 'x'});
      expect(chat.messages.single.pinned, isFalse);
    });

    test('an assistant message can be pinned', () async {
      await read({'seq': 0, 'role': 'assistant', 'text': 'x', 'pinned': true});
      expect(chat.messages.single.pinned, isTrue);
    });

    test('a value of pinned that is not a boolean is a bad answer', () async {
      for (final value in [1, 'true', null.toString(), []]) {
        service.nextHistoryBody = jsonEncode({
          'count': 1,
          'messages': [
            {'seq': 0, 'role': 'assistant', 'text': 'x', 'pinned': value},
          ],
        });
        await expectLater(chat.sync(), kind(ChatErrorKind.badAnswer));
      }
    });

    test('a pinned user message is a bad answer', () async {
      service.nextHistoryBody = jsonEncode({
        'count': 1,
        'messages': [
          {'seq': 0, 'role': 'user', 'text': 'x', 'pinned': true},
        ],
      });
      await expectLater(chat.sync(), kind(ChatErrorKind.badAnswer));
    });

    test('pinned false on a user message is valid', () async {
      await read({'seq': 0, 'role': 'user', 'text': 'x', 'pinned': false});
      expect(chat.messages.single.pinned, isFalse);
    });
  });

  test('a lost reply is found in the history by its cid, and the message is not sent twice',
      () async {
    service.dropNextAnswer = true;
    service.answerNever = true;
    await chat.send('one');
    expect(chat.messages.map((m) => m.text), ['one']);
    expect(service.users, hasLength(1));
  });

  test('a send that did not reach the service is sent again, with the same cid', () async {
    service.dropNextPostBeforeApply = true;
    await chat.send('one');
    expect(chat.messages.map((m) => m.text), ['one']);
    expect(service.users, hasLength(1));
  });

  test('a send that times out is sent again, and the service adds it once', () async {
    final hold = service.holdNextPost = Completer<void>();
    final slow = ChatClient(
      port: service.port,
      http: http,
      sendTimeout: const Duration(milliseconds: 200),
    );
    await slow.send('late');
    // The first request is applied at last: its cid is there, so nothing is added.
    hold.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.users, hasLength(1));
    expect(slow.messages.map((m) => m.text), ['late']);
  });

  test('statuses of the convention become error kinds', () async {
    for (final entry in {
      400: ChatErrorKind.badRequest,
      413: ChatErrorKind.historyFull,
      503: ChatErrorKind.busy,
      500: ChatErrorKind.other,
    }.entries) {
      service.failNextWith = entry.key;
      await expectLater(
        chat.send('x'),
        throwsA(isA<ChatException>()
            .having((e) => e.kind, 'kind', entry.value)
            .having((e) => e.status, 'status', entry.key)
            .having((e) => e.message, 'message', 'for the user')),
      );
    }
    expect(chat.count, 0);
  });

  test('a reply to a send with no message is a bad answer', () async {
    service.failNextWith = 200;
    await expectLater(chat.send('x'), kind(ChatErrorKind.badAnswer));
  });

  test('a history with a gap is a bad answer', () async {
    service.nextHistoryBody = jsonEncode({
      'count': 5,
      'messages': [
        {'seq': 3, 'role': 'user', 'text': 'x'},
      ],
    });
    await expectLater(chat.sync(), kind(ChatErrorKind.badAnswer));
    expect(chat.count, 0);
  });

  test('an answer that is not JSON is a bad answer', () async {
    service.nextHistoryBody = 'not json';
    await expectLater(chat.sync(), kind(ChatErrorKind.badAnswer));
  });

  test('a read that is shorter than the history is followed by another read', () async {
    for (var i = 0; i < 5; i++) {
      service.messages.add({'seq': i, 'role': i.isEven ? 'user' : 'assistant', 'text': '$i'});
    }
    service.maxPerRead = 2;
    await chat.sync();
    expect(chat.count, 5);
    expect(service.reads, ['from=0', 'from=2', 'from=4']);
  });

  test('a read with no message while the service has more is not read again and again', () async {
    service.messages.add({'seq': 0, 'role': 'user', 'text': 'x'});
    service.maxPerRead = 0;
    await expectLater(chat.sync(), kind(ChatErrorKind.badAnswer));
  });

  group('attachments', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
    OutgoingAttachment image({String name = 'tree.png'}) =>
        OutgoingAttachment(mime: 'image/png', bytes: png, name: name);

    test('the read of the history gives the kinds that the service accepts', () async {
      await chat.sync();
      expect(chat.accepts, isEmpty);
      service.accepts = ['image', 'audio', 'video'];
      await chat.sync();
      expect(chat.accepts, {'image', 'audio'});
    });

    test('a send with a file and no text works, and keeps the bytes', () async {
      service.accepts = ['image'];
      await chat.sync();
      await chat.send('', attachments: [image()]);
      final user = chat.messages.first;
      expect(user.text, '');
      expect(user.attachments.single.kind, 'image');
      expect(user.attachments.single.name, 'tree.png');
      expect(user.attachments.single.size, png.length);
      final before = service.connections.length;
      expect(await chat.readAttachment(0, 0), png);
      expect(service.connections, hasLength(before));
    });

    test('a file of another message is read from the service once', () async {
      service.accepts = ['image'];
      service.files[(0, 0)] = png;
      service.messages.add({
        'seq': 0,
        'role': 'assistant',
        'text': 'a picture',
        'attachments': [
          {'kind': 'image', 'mime': 'image/png', 'size': png.length},
        ],
      });
      await chat.sync();
      expect(await chat.readAttachment(0, 0), png);
      service.files.clear();
      expect(await chat.readAttachment(0, 0), png);
    });

    test('a file that is not there is an error with its status', () async {
      await expectLater(
        chat.readAttachment(0, 3),
        throwsA(isA<ChatException>().having((e) => e.status, 'status', 404)),
      );
    });

    test('nothing is sent if the service accepts text only', () async {
      await chat.sync();
      await expectLater(
        chat.send('x', attachments: [image()]),
        kind(ChatErrorKind.unsupportedMedia),
      );
      expect(service.messages, isEmpty);
    });

    test('nothing is sent if the kind is not accepted or the file is not valid', () async {
      service.accepts = ['image'];
      await chat.sync();
      final audio = OutgoingAttachment(mime: 'audio/wav', bytes: png);
      final pdf = OutgoingAttachment(mime: 'application/pdf', bytes: png);
      final empty = OutgoingAttachment(mime: 'image/png', bytes: Uint8List(0));
      final big = OutgoingAttachment(
        mime: 'image/png',
        bytes: Uint8List(ChatClient.maxAttachmentBytes + 1),
      );
      await expectLater(chat.send('x', attachments: [audio]), kind(ChatErrorKind.unsupportedMedia));
      await expectLater(chat.send('x', attachments: [pdf]), kind(ChatErrorKind.unsupportedMedia));
      await expectLater(chat.send('x', attachments: [empty]), kind(ChatErrorKind.badRequest));
      await expectLater(chat.send('x', attachments: [big]), kind(ChatErrorKind.badRequest));
      await expectLater(
        chat.send('x', attachments: List.filled(ChatClient.maxAttachments + 1, image())),
        kind(ChatErrorKind.badRequest),
      );
      await expectLater(chat.send(''), kind(ChatErrorKind.badRequest));
      expect(service.messages, isEmpty);
    });

    test('status 415 is unsupported media', () async {
      service.accepts = ['image'];
      await chat.sync();
      service.failNextWith = 415;
      await expectLater(
        chat.send('x', attachments: [image()]),
        kind(ChatErrorKind.unsupportedMedia),
      );
    });

    test('a lost reply after a send with a file is found in the history', () async {
      service.accepts = ['image'];
      await chat.sync();
      service.dropNextAnswer = true;
      await chat.send('look', attachments: [image()]);
      expect(chat.messages.first.attachments, hasLength(1));
      expect(await chat.readAttachment(0, 0), png);
      expect(service.users, hasLength(1));
    });

    test('a history with a file of a kind that is not defined is a bad answer', () async {
      service.nextHistoryBody = jsonEncode({
        'count': 1,
        'messages': [
          {
            'seq': 0,
            'role': 'user',
            'text': '',
            'attachments': [
              {'kind': 'video', 'mime': 'video/mp4', 'size': 3},
            ],
          },
        ],
      });
      await expectLater(chat.sync(), kind(ChatErrorKind.badAnswer));
    });
  });

  test('a send waits 2 minutes for its reply, and the reads follow the pace of the wait', () {
    expect(ChatClient.defaultSendTimeout, const Duration(minutes: 2));
    expect(ChatClient.pollWaiting, const Duration(seconds: 2));
    expect(ChatClient.pollIdle, const Duration(seconds: 10));
  });

  test('a history longer than 64 KiB is read whole', () async {
    final text = 'x' * 40000;
    for (var i = 0; i < 6; i += 2) {
      service.messages
        ..add({'seq': i, 'role': 'user', 'text': text})
        ..add({'seq': i + 1, 'role': 'assistant', 'text': text});
    }
    await chat.sync();
    expect(chat.count, 6);
  });

  test('the safe name of a file drops paths, control characters and dots', () {
    String? safe(String? name) =>
        ChatAttachment(kind: 'image', mime: 'image/png', size: 1, name: name).safeName;
    expect(safe('../../databases/x.db'), 'x.db');
    expect(safe(r'..\..\a\b.png'), 'b.png');
    expect(safe('a\u0000b\n.png'), 'ab.png');
    expect(safe('tree.png'), 'tree.png');
    expect(safe('..'), isNull);
    expect(safe('dir/'), isNull);
    expect(safe(''), isNull);
    expect(safe(null), isNull);
    expect(safe('${'a' * 101}.png'), isNull);
  });

  group('files in memory', () {
    final big = List<int>.filled(ChatClient.maxAttachmentBytes, 7);

    test('past 24 MiB the files of the other messages are dropped, and read again', () async {
      for (var seq = 0; seq < 7; seq++) {
        service.files[(seq, 0)] = big;
      }
      for (var seq = 0; seq < 6; seq++) {
        await chat.readAttachment(seq, 0);
      }
      // 24 MiB: still the limit, nothing dropped.
      await chat.readAttachment(0, 0);
      expect(service.fileReads, 6);
      await chat.readAttachment(6, 0);
      expect(service.fileReads, 7);
      // The last one stays; the first has to come again.
      await chat.readAttachment(6, 0);
      expect(service.fileReads, 7);
      await chat.readAttachment(0, 0);
      expect(service.fileReads, 8);
    });

    test('reads of files wait for a send that is queued', () async {
      for (var seq = 0; seq < 3; seq++) {
        service.files[(seq, 0)] = [1, 2, 3];
      }
      service.fileDelay = const Duration(milliseconds: 150);
      final order = <String>[];
      final reads = [
        for (var seq = 0; seq < 3; seq++)
          chat.readAttachment(seq, 0).then((_) => order.add('read$seq')),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final send = chat.send('now').then((_) => order.add('send'));
      await Future.wait([...reads, send]);
      expect(order, ['read0', 'send', 'read1', 'read2']);
    });
  });

  test('a service that is gone is unreachable', () async {
    final port = service.port;
    await service.close();
    final gone = ChatClient(port: port, http: http);
    await expectLater(gone.send('x'), kind(ChatErrorKind.unreachable));
    expect(gone.count, 0);
  });
}
