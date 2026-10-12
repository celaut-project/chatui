/// A host and a port that the user typed.
class HostPort {
  const HostPort(this.host, this.port);

  final String host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is HostPort && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => host.contains(':') ? '[$host]:$port' : '$host:$port';
}

/// Why [parseHostPort] refused the text.
enum HostPortError { empty, invalid, port }

/// Parse `host:port`, `[ipv6]:port`, or the same with a leading `grpc://`,
/// `https://` or `tls://`. The port is required: a Celaut node has no fixed port.
({HostPort? value, HostPortError? error}) parseHostPort(String input) {
  var text = input.trim();
  if (text.isEmpty) return (value: null, error: HostPortError.empty);
  text = text.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
  if (text.endsWith('/')) text = text.substring(0, text.length - 1);

  String host;
  String portText;
  if (text.startsWith('[')) {
    final close = text.indexOf(']');
    if (close < 0 || text.length < close + 3 || text[close + 1] != ':') {
      return (value: null, error: HostPortError.invalid);
    }
    host = text.substring(1, close);
    portText = text.substring(close + 2);
  } else {
    final colon = text.lastIndexOf(':');
    if (colon < 0) return (value: null, error: HostPortError.invalid);
    host = text.substring(0, colon);
    portText = text.substring(colon + 1);
    // A bare IPv6 address has no way to show the port.
    if (host.contains(':')) return (value: null, error: HostPortError.invalid);
  }
  if (host.isEmpty || RegExp(r'[\s/]').hasMatch(host)) {
    return (value: null, error: HostPortError.invalid);
  }
  final port = int.tryParse(portText);
  if (port == null || port < 1 || port > 65535 || !RegExp(r'^\d+$').hasMatch(portText)) {
    return (value: null, error: HostPortError.port);
  }
  return (value: HostPort(host, port), error: null);
}
