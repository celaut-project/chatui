import 'dart:io';

import 'package:argus_wallet/celaut/tunnel_http.dart';
import 'package:flutter_test/flutter_test.dart';

/// A local HTTP server that counts its TCP connections, as the node counts the
/// tunnel streams of a local port.
class CountingServer {
  CountingServer._(this.server);

  final HttpServer server;
  final connections = <int>{};
  String body = 'clever-turing';

  static Future<CountingServer> start() async {
    final s = CountingServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    s.server.listen((request) async {
      s.connections.add(request.connectionInfo!.remotePort);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      request.response
        ..headers.contentType = ContentType.text
        ..write(s.body);
      await request.response.close();
    });
    return s;
  }

  int get port => server.port;
  Future<void> close() => server.close(force: true);
}

void main() {
  late CountingServer server;
  late TunnelHttp http;
  setUp(() async {
    server = await CountingServer.start();
    http = TunnelHttp();
  });
  tearDown(() async {
    http.close();
    await server.close();
  });

  test('calls one after the other share one connection', () async {
    for (var i = 0; i < 3; i++) {
      final answer = await http.get(server.port, '/');
      expect(answer.status, 200);
      expect(answer.body, 'clever-turing');
    }
    expect(server.connections, hasLength(1));
  });

  test('calls at the same time wait for the one connection', () async {
    final answers = await Future.wait([
      for (var i = 0; i < 4; i++) http.get(server.port, '/whoami'),
    ]);
    expect(answers.map((a) => a.status), everyElement(200));
    expect(server.connections, hasLength(1));
  });

  test('close drops the connection, and the next call opens a new one', () async {
    await http.get(server.port, '/');
    http.close();
    http = TunnelHttp();
    await http.get(server.port, '/');
    expect(server.connections, hasLength(2));
  });

  test('a path without a slash gets one, and a long body is cut', () async {
    server.body = 'x' * (TunnelHttp.maxBody + 100);
    final answer = await http.get(server.port, 'big');
    expect(answer.body.length, TunnelHttp.maxBody);
    // The rest of the body was read, so the connection carries the next call.
    server.body = 'small';
    expect((await http.get(server.port, '/')).body, 'small');
    expect(server.connections, hasLength(1));
  });
}
