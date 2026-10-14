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

  group('QR code of a node (wire.md section 6)', () {
    test('reads the celaut URI', () {
      expect(
        parseNodeQr('celaut://node?addr=203.0.113.7:53460').value,
        const HostPort('203.0.113.7', 53460),
      );
      expect(
        parseNodeQr(' CELAUT://Node/?addr=node.example.org:9000 \n').value,
        const HostPort('node.example.org', 9000),
      );
      // Percent-encoded IPv6 and an unknown parameter, which is ignored.
      expect(
        parseNodeQr('celaut://node?v=2&addr=%5B2001%3Adb8%3A%3A7%5D%3A8090&peer=ab').value,
        const HostPort('2001:db8::7', 8090),
      );
      expect(parseNodeQr('celaut://node?addr=[::1]:8090').value, const HostPort('::1', 8090));
    });

    test('reads a bare host:port', () {
      expect(parseNodeQr('10.0.2.2:18460').value, const HostPort('10.0.2.2', 18460));
      expect(parseNodeQr('[::1]:8090').value, const HostPort('::1', 8090));
    });

    test('refuses other text', () {
      for (final text in [
        'celaut://node',
        'celaut://node/',
        'celaut://node?',
        'celaut://node?addr=',
        'celaut://node?addr',
        'celaut://node?address=h:1',
        'celaut://node?addr=h:1&addr=g:2',
        'celaut://node?addr=tls://h:1',
        'celaut://node?addr=h:1#x',
        'celaut://node:7?addr=h:1',
        'celaut://user@node?addr=h:1',
        'celaut://nodes?addr=h:1',
        'celaut://node/x?addr=h:1',
        'celaut://node?addr=%zz',
        'celaut:node?addr=h:1',
        'tls://h:1',
        'https://example.org:443/',
        'ergopay://example.org/pay',
        '9fJKzKwb3cy9mTa8sBR9iTkFSf2eZrTy2wgPBCcLaprh4g9eUwi',
        'node.example',
      ]) {
        final r = parseNodeQr(text);
        expect(r.value, isNull, reason: text);
        expect(r.error, HostPortError.invalid, reason: text);
      }
    });

    test('a bad port is a port error, as in the address field', () {
      expect(parseNodeQr('h:0').error, HostPortError.port);
      expect(parseNodeQr('celaut://node?addr=h:70000').error, HostPortError.port);
      expect(parseNodeQr('ergopay:abc').error, HostPortError.port);
      expect(parseNodeQr('  ').error, HostPortError.empty);
    });
  });
}
