import 'package:argus_wallet/celaut/host_port.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads host:port', () {
    expect(parseHostPort('203.0.113.7:8090').value, const HostPort('203.0.113.7', 8090));
    expect(parseHostPort(' node.example.org:9000 ').value, const HostPort('node.example.org', 9000));
    expect(parseHostPort('localhost:1').value, const HostPort('localhost', 1));
    expect(parseHostPort('localhost:65535').value, const HostPort('localhost', 65535));
  });

  test('reads an IPv6 address in brackets and drops a scheme', () {
    expect(parseHostPort('[::1]:8090').value, const HostPort('::1', 8090));
    expect(parseHostPort('[2001:db8::7]:8090').value?.toString(), '[2001:db8::7]:8090');
    expect(parseHostPort('tls://node.example:7/').value, const HostPort('node.example', 7));
  });

  test('refuses what is not host:port', () {
    expect(parseHostPort('').error, HostPortError.empty);
    expect(parseHostPort('   ').error, HostPortError.empty);
    expect(parseHostPort('node.example').error, HostPortError.invalid);
    expect(parseHostPort(':8090').error, HostPortError.invalid);
    expect(parseHostPort('::1:8090').error, HostPortError.invalid);
    expect(parseHostPort('[::1]').error, HostPortError.invalid);
    expect(parseHostPort('[::1').error, HostPortError.invalid);
    expect(parseHostPort('a b:80').error, HostPortError.invalid);
    expect(parseHostPort('a/b:80').error, HostPortError.invalid);
  });

  test('refuses a port that is not 1 to 65535', () {
    for (final text in ['h:0', 'h:65536', 'h:-1', 'h:abc', 'h:', 'h:80x', 'h:+80', 'h:8 0']) {
      expect(parseHostPort(text).error, HostPortError.port, reason: text);
    }
  });
}
