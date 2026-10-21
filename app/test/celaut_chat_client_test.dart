import 'dart:convert';
import 'dart:io';

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
    final user = {'seq': messages.length, 'role': 'user', 'text': text};
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

  test('a service that is gone is unreachable', () async {
    await service.close();
    await expectLater(
      chat.send('x'),
      throwsA(isA<ChatException>().having((e) => e.kind, 'kind', ChatErrorKind.unreachable)),
    );
  });
}
