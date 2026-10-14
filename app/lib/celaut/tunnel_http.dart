import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The answer of one HTTP call through a tunnel port.
class TunnelAnswer {
  const TunnelAnswer(this.status, this.body);

  final int status;
  final String body;
}

/// HTTP calls to the local port of an instance (127.0.0.1).
///
/// Each TCP connection to that port is one `ServiceTunnel` stream, and the node
/// charges each stream (`TUNNEL_OPEN_MU`). So one client keeps one connection alive
/// and sends all its calls on it, one after the other: [HttpClient] reuses an idle
/// connection, and `maxConnectionsPerHost = 1` stops it from opening a second one
/// while a call runs.
class TunnelHttp {
  TunnelHttp({Duration idleTimeout = const Duration(minutes: 5)})
      : _client = HttpClient()
          ..maxConnectionsPerHost = 1
          ..idleTimeout = idleTimeout
          // The port is on this device: never through a proxy.
          ..findProxy = ((_) => 'DIRECT');

  final HttpClient _client;

  /// The most bytes of a body that are kept.
  static const maxBody = 64 * 1024;

  /// `GET path` on `127.0.0.1:port`. The whole body is read, so that the
  /// connection can carry the next call; only the first [maxBody] bytes are kept.
  Future<TunnelAnswer> get(
    int port,
    String path, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _call('GET', port, path, null, timeout);

  /// `POST path` on `127.0.0.1:port` with [json] as the body (`application/json`).
  /// It reads the answer as [get] does.
  Future<TunnelAnswer> postJson(
    int port,
    String path,
    Object json, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _call('POST', port, path, json, timeout);

  Future<TunnelAnswer> _call(
    String method,
    int port,
    String path,
    Object? json,
    Duration timeout,
  ) async {
    final target = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('http://127.0.0.1:$port$target');
    Future<TunnelAnswer> call() async {
      final request = await _client.openUrl(method, uri);
      request.persistentConnection = true;
      if (json != null) {
        final bytes = utf8.encode(jsonEncode(json));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close();
      final kept = BytesBuilder(copy: false);
      await for (final chunk in response) {
        final room = maxBody - kept.length;
        if (room > 0) kept.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
      }
      return TunnelAnswer(
        response.statusCode,
        utf8.decode(kept.takeBytes(), allowMalformed: true),
      );
    }

    return call().timeout(timeout);
  }

  /// Close the connection. The next call opens a new one (a new stream).
  void close() => _client.close(force: true);
}
