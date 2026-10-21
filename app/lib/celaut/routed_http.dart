import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../bridge/api/celaut_network.dart';

/// The route has no way out: Tor is on and its proxy is not ready, or it failed.
class RouteBlocked implements IOException {
  const RouteBlocked(this.reason);

  /// Why, in English, from the Rust core.
  final String reason;

  @override
  String toString() => 'No connection: $reason';
}

/// The SOCKS5 proxy refused the connection or did not speak SOCKS5.
class SocksFailure implements IOException {
  const SocksFailure(this.message);

  final String message;

  @override
  String toString() => 'SOCKS5: $message';
}

/// An HTTP client for the code of the Dart side that makes its own requests (the
/// updater of the app). It follows the network route of the Rust core at the moment that
/// it is built: direct, through the SOCKS5 proxy (Tor), or with no way out. With Tor on,
/// it never connects directly (`docs/celaut/network.md`). The environment proxies are
/// never used. Build a new client for each use: a client keeps the route that it had.
///
/// Through the proxy, only HTTPS works: the proxy opens the connection, and the TLS of
/// the request goes inside it. The proxy looks up the names.
http.Client routedHttpClient({NetworkProxyView Function()? readRoute, SecurityContext? context}) =>
    IOClient(routedIoClient((readRoute ?? celautNetworkProxy)(), context: context));

/// The `dart:io` client of [routedHttpClient] for [route].
HttpClient routedIoClient(NetworkProxyView route, {SecurityContext? context}) {
  final client = HttpClient(context: context)..findProxy = (_) => 'DIRECT';
  switch (route.kind) {
    case NetworkProxyKind.direct:
      break;
    case NetworkProxyKind.socks:
      client.connectionFactory = (url, _, _) {
        if (url.scheme != 'https') {
          return Future.error(SocksFailure('only HTTPS goes through the proxy, not ${url.scheme}'));
        }
        return Future.value(ConnectionTask.fromSocket(_throughSocks(route, url, context), () {}));
      };
    case NetworkProxyKind.blocked:
      client.connectionFactory = (_, _, _) => Future.error(RouteBlocked(route.reason));
  }
  return client;
}

const _socksTimeout = Duration(seconds: 60);

Future<Socket> _throughSocks(NetworkProxyView proxy, Uri url, SecurityContext? context) async {
  final socket = await Socket.connect(proxy.host, proxy.port, timeout: _socksTimeout);
  final reader = _Reader(socket);
  try {
    await _handshake(socket, reader, proxy, url.host, url.hasPort ? url.port : 443)
        .timeout(_socksTimeout);
    // The proxy sends nothing more before the TLS of the server, so no byte is lost.
    reader.pause();
    return await SecureSocket.secure(socket, host: url.host, context: context);
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}

/// RFC 1928 and RFC 1929: no authentication or a user name and a password, then CONNECT
/// with the name of the host, so that the proxy looks it up.
Future<void> _handshake(Socket socket, _Reader reader, NetworkProxyView proxy, String host, int port) async {
  final withPassword = proxy.user.isNotEmpty;
  socket.add(withPassword ? [5, 1, 2] : [5, 1, 0]);
  final method = await reader.take(2);
  if (method[0] != 5) throw const SocksFailure('the proxy does not speak SOCKS5');
  if (method[1] == 2 && withPassword) {
    final user = utf8.encode(proxy.user);
    final password = utf8.encode(proxy.password);
    if (user.length > 255 || password.length > 255) {
      throw const SocksFailure('the user name or the password is too long');
    }
    socket.add([1, user.length, ...user, password.length, ...password]);
    final auth = await reader.take(2);
    if (auth[1] != 0) throw const SocksFailure('the proxy refused the user name and the password');
  } else if (method[1] != 0) {
    throw const SocksFailure('the proxy accepts no method that the app offers');
  }
  final name = utf8.encode(host);
  if (name.isEmpty || name.length > 255) throw SocksFailure('not a host name: $host');
  socket.add([5, 1, 0, 3, name.length, ...name, port >> 8, port & 0xff]);
  final reply = await reader.take(4);
  if (reply[1] != 0) throw SocksFailure('the proxy could not connect (code ${reply[1]})');
  final addressLength = switch (reply[3]) {
    1 => 4,
    4 => 16,
    3 => (await reader.take(1))[0],
    _ => throw const SocksFailure('the proxy sent an unknown address type'),
  };
  await reader.take(addressLength + 2);
}

/// Reads exact byte counts from a socket during the handshake.
class _Reader {
  _Reader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.add(data);
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
    );
  }

  late final StreamSubscription<Uint8List> _subscription;
  final _buffer = BytesBuilder();
  Completer<void>? _waiting;
  Object? _error;
  bool _done = false;

  void _wake() {
    final waiting = _waiting;
    _waiting = null;
    waiting?.complete();
  }

  Future<Uint8List> take(int count) async {
    while (_buffer.length < count) {
      if (_error != null) throw _error!;
      if (_done) throw const SocksFailure('the proxy closed the connection');
      await (_waiting = Completer<void>()).future;
    }
    final all = _buffer.takeBytes();
    _buffer.add(Uint8List.sublistView(all, count));
    return Uint8List.sublistView(all, 0, count);
  }

  void pause() => _subscription.pause();
}
