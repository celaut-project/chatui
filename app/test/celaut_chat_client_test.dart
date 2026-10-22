import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:argus_wallet/celaut/chat_client.dart';
import 'package:argus_wallet/celaut/tunnel_http.dart';
import 'package:flutter_test/flutter_test.dart';

/// A local echo service that follows `docs/celaut/chat.md`, with switches to break it.
class EchoService {
  EchoService._(this.server);

  final HttpServer server;
  final connections = <int>{};
  final messages = <Map<String, Object>>[];

  /// The next POST is applied, but the connection is closed with no answer.
  bool dropNextAnswer = false;

  /// The next POST gets this status with no change to the history.
  int? failNextWith;

  /// The next GET gets this body with status 200.
  String? nextHistoryBody;

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

  Future<void> _reply(HttpResponse response, int status, Object body) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    connections.add(request.connectionInfo!.remotePort);
    final response = request.response;
    final file = RegExp(r'^/chat/messages/(\d+)/attachments/(\d+)$').firstMatch(request.uri.path);
    if (file != null) {
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
      final from = int.parse(request.uri.queryParameters['from'] ?? '0');
      await _reply(response, 200, {
        'count': messages.length,
        if (accepts != null) 'accepts': accepts,
        'messages': messages.skip(from).toList(),
      });
      return;
    }
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
    final status = failNextWith;
    if (status != null) {
      failNextWith = null;
      await _reply(response, status, {'error': 'x', 'message': 'for the user'});
      return;
    }
    if (body['expect'] != messages.length) {
      await _reply(response, 409, {'error': 'out_of_sync', 'count': messages.length});
      return;
    }
    final text = body['text'] as String;
    final sent = (body['attachments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final user = {
      'seq': messages.length,
      'role': 'user',
      'text': text,
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
    final reply = {'seq': messages.length, 'role': 'assistant', 'text': text};
    messages.add(reply);
    if (dropNextAnswer) {
      dropNextAnswer = false;
      final socket = await response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    await _reply(response, 200, {'count': messages.length, 'messages': [user, reply]});
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

  test('send adds the user message and the echo', () async {
    await chat.send('Hello');
    expect(chat.count, 2);
    expect(chat.messages.map((m) => m.role), ['user', 'assistant']);
    expect(chat.messages.map((m) => m.text), ['Hello', 'Hello']);
  });

  test('messages are numbered and share one connection', () async {
    await chat.send('one');
    await chat.send('two');
    expect(chat.messages.map((m) => m.seq), [0, 1, 2, 3]);
    expect(service.connections, hasLength(1));
  });

  test('sends at the same time run one after the other', () async {
    await Future.wait([chat.send('a'), chat.send('b'), chat.send('c')]);
    expect(chat.messages.map((m) => m.seq), [0, 1, 2, 3, 4, 5]);
    expect(chat.messages.where((m) => m.fromUser).map((m) => m.text), ['a', 'b', 'c']);
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
    await chat.sync();
    expect(chat.messages.map((m) => m.text), ['one', 'one']);
    await chat.sync();
    expect(chat.count, 2);
  });

  test('a lost answer is read from the history, and the message is not sent twice', () async {
    service.dropNextAnswer = true;
    await chat.send('one');
    expect(chat.messages.map((m) => m.text), ['one', 'one']);
    expect(service.messages, hasLength(2));
  });

  test('out of sync reads the history, then the send counts as done if it is there', () async {
    // Another client wrote the same text as the next message.
    service.messages
      ..add({'seq': 0, 'role': 'user', 'text': 'one'})
      ..add({'seq': 1, 'role': 'assistant', 'text': 'one'});
    await chat.send('one');
    expect(chat.count, 2);
    expect(service.messages, hasLength(2));
  });

  test('out of sync with another message in the history throws and sends nothing', () async {
    service.messages
      ..add({'seq': 0, 'role': 'user', 'text': 'other'})
      ..add({'seq': 1, 'role': 'assistant', 'text': 'other'});
    await expectLater(
      chat.send('one'),
      throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.unreachable)),
    );
    expect(chat.count, 2);
    expect(service.messages, hasLength(2));
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

  test('a history with a gap is a bad answer', () async {
    service.nextHistoryBody = jsonEncode({
      'count': 5,
      'messages': [
        {'seq': 3, 'role': 'user', 'text': 'x'},
      ],
    });
    await expectLater(
      chat.sync(),
      throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badAnswer)),
    );
    expect(chat.count, 0);
  });

  test('an answer that is not JSON is a bad answer', () async {
    service.nextHistoryBody = 'not json';
    await expectLater(
      chat.sync(),
      throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.badAnswer)),
    );
  });

  group('attachments', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
    OutgoingAttachment image({String name = 'tree.png'}) =>
        OutgoingAttachment(mime: 'image/png', bytes: png, name: name);

    Matcher kind(ChatErrorKind k) =>
        throwsA(isA<ChatException>().having((e) => e.kind, 'kind', k));

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

    test('a lost answer after a send with a file is found in the history', () async {
      service.accepts = ['image'];
      await chat.sync();
      service.dropNextAnswer = true;
      await chat.send('look', attachments: [image()]);
      expect(chat.count, 2);
      expect(await chat.readAttachment(0, 0), png);
      expect(service.messages, hasLength(2));
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

  test('a service that is gone is unreachable', () async {
    await service.close();
    await expectLater(
      chat.send('x'),
      throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.unreachable)),
    );
  });
}
