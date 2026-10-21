import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut_network.dart';
import 'package:argus_wallet/celaut/routed_http.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

// A self-signed certificate for `localhost`, only for these tests (P-256, valid to 2126).
const _cert = '''
-----BEGIN CERTIFICATE-----
MIIBODCB36ADAgECAgkAu0eBo7IYI9YwCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJ
bG9jYWxob3N0MCAXDTI2MTAyMTE1MzE0N1oYDzIxMjYwOTI3MTUzMTQ3WjAUMRIw
EAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQl0EoR
AHxZXqUzaJznJF1kplmAeL1oxSuY4Uo+HKRTxMz/AyzNVZKcAeiQvvi68WUt4Fvw
W7DYRWnqe2SaapGboxgwFjAUBgNVHREEDTALgglsb2NhbGhvc3QwCgYIKoZIzj0E
AwIDSAAwRQIhAPNJcmzg19yQolPaImiM9grHSzkFP/rTL4Hkw2g/yNCeAiA4b8to
oj4AUaWIN/RJs769rDOVa3jFWEZsDUkao8QnNA==
-----END CERTIFICATE-----
''';

const _key = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgGiWIJsPcixWVbVaU
7VWAyVsfoEUd1dUfsOPCjQ8eARShRANCAAQl0EoRAHxZXqUzaJznJF1kplmAeL1o
xSuY4Uo+HKRTxMz/AyzNVZKcAeiQvvi68WUt4FvwW7DYRWnqe2SaapGb
-----END PRIVATE KEY-----
''';

SecurityContext _trustTest() =>
    SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(utf8.encode(_cert));

NetworkProxyView _route(
  NetworkProxyKind kind, {
  int port = 0,
  String user = '',
  String password = '',
  String reason = '',
}) =>
    NetworkProxyView(
      kind: kind,
      host: kind == NetworkProxyKind.socks ? '127.0.0.1' : '',
      port: port,
      user: user,
      password: password,
      reason: reason,
    );

/// A SOCKS5 proxy on the loopback that asks for a user name and a password and maps
/// `localhost` to 127.0.0.1. It records each CONNECT.
class _Proxy {
  _Proxy(this._server, {required this.user, required this.password}) {
    _server.listen(_serve);
  }

  static Future<_Proxy> start({String user = 'u', String password = 'p'}) async =>
      _Proxy(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), user: user, password: password);

  final ServerSocket _server;
  final String user;
  final String password;
  final connects = <String>[];
  int get port => _server.port;

  Future<void> _serve(Socket client) async {
    final input = StreamIterator(client);
    final buffer = BytesBuilder();
    Future<Uint8List> take(int n) async {
      while (buffer.length < n) {
        if (!await input.moveNext()) throw StateError('closed');
        buffer.add(input.current);
      }
      final all = buffer.takeBytes();
      buffer.add(all.sublist(n));
      return all.sublist(0, n);
    }

    try {
      final hello = await take(2);
      final methods = await take(hello[1]);
      if (!methods.contains(2)) {
        client.add([5, 0xff]);
        await client.close();
        return;
      }
      client.add([5, 2]);
      final auth = await take(2);
      final u = utf8.decode(await take(auth[1]));
      final p = utf8.decode(await take((await take(1))[0]));
      if (u != user || p != password) {
        client.add([1, 1]);
        await client.close();
        return;
      }
      client.add([1, 0]);
      final head = await take(5);
      final host = utf8.decode(await take(head[4]));
      final portBytes = await take(2);
      final port = portBytes[0] << 8 | portBytes[1];
      connects.add('$host:$port');
      final upstream = await Socket.connect(host == 'localhost' ? '127.0.0.1' : host, port);
      client.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
      final rest = buffer.takeBytes();
      if (rest.isNotEmpty) upstream.add(rest);
      unawaited(upstream.cast<List<int>>().pipe(client).catchError((_) {}));
      while (await input.moveNext()) {
        upstream.add(input.current);
      }
      await upstream.close();
    } catch (_) {
      client.destroy();
    }
  }

  Future<void> close() => _server.close();
}

void main() {
  late HttpServer server;
  late int requests;

  setUp(() async {
    requests = 0;
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(_cert))
      ..usePrivateKeyBytes(utf8.encode(_key));
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    server.listen((request) {
      requests++;
      request.response
        ..write('hello ${request.headers.value('user-agent')}')
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri url() => Uri.https('localhost:${server.port}', '/');

  test('a direct route connects from the phone', () async {
    final client = routedHttpClient(readRoute: () => _route(NetworkProxyKind.direct), context: _trustTest());
    final response = await client.get(url(), headers: {'user-agent': 'Celaut'});
    client.close();
    expect(response.statusCode, 200);
    expect(response.body, 'hello Celaut');
  });

  test('through the proxy: the user name and the password, the name of the host, then TLS', () async {
    final proxy = await _Proxy.start(user: 'u1', password: 'p1');
    addTearDown(proxy.close);
    final client = routedHttpClient(
      readRoute: () => _route(NetworkProxyKind.socks, port: proxy.port, user: 'u1', password: 'p1'),
      context: _trustTest(),
    );
    final response = await client.get(url(), headers: {'user-agent': 'Celaut'});
    client.close();
    expect(response.statusCode, 200);
    expect(response.body, 'hello Celaut');
    expect(proxy.connects, ['localhost:${server.port}'], reason: 'the proxy looks up the name');
  });

  test('a wrong password fails, and nothing goes direct', () async {
    final proxy = await _Proxy.start(user: 'u1', password: 'p1');
    addTearDown(proxy.close);
    final client = routedHttpClient(
      readRoute: () => _route(NetworkProxyKind.socks, port: proxy.port, user: 'u1', password: 'wrong'),
      context: _trustTest(),
    );
    await expectLater(client.get(url()), throwsA(isA<SocksFailure>()));
    client.close();
    expect(requests, 0);
    expect(proxy.connects, isEmpty);
  });

  test('a proxy that is not there fails, and nothing goes direct', () async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = unused.port;
    await unused.close();
    final client = routedHttpClient(
      readRoute: () => _route(NetworkProxyKind.socks, port: port),
      context: _trustTest(),
    );
    await expectLater(client.get(url()), throwsA(anything));
    client.close();
    expect(requests, 0);
  });

  test('a blocked route fails with its reason, and nothing goes out', () async {
    final client = routedHttpClient(
      readRoute: () => _route(NetworkProxyKind.blocked, reason: 'Tor is starting'),
      context: _trustTest(),
    );
    await expectLater(
      client.get(url()),
      throwsA(isA<RouteBlocked>().having((e) => e.reason, 'reason', 'Tor is starting')),
    );
    client.close();
    expect(requests, 0);
  });

  test('through the proxy, plain HTTP is refused', () async {
    final proxy = await _Proxy.start();
    addTearDown(proxy.close);
    final client = routedHttpClient(
      readRoute: () => _route(NetworkProxyKind.socks, port: proxy.port, user: 'u', password: 'p'),
    );
    await expectLater(client.get(Uri.http('localhost:${server.port}', '/')), throwsA(isA<SocksFailure>()));
    client.close();
    expect(proxy.connects, isEmpty);
  });

  test('the update check through a blocked route says that Tor is not ready', () async {
    final client = routedHttpClient(
      readRoute: () => _route(NetworkProxyKind.blocked, reason: 'Tor is starting'),
    );
    await expectLater(
      fetchLatestRelease(client),
      throwsA(isA<UpdateException>().having((e) => e.message, 'message', appL10n.updateErrorRouteBlocked)),
    );
    client.close();
  });
}
