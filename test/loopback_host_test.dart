import 'package:discourse_native/src/foundation/loopback_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isLoopbackHost', () {
    test('accepts localhost names with case and an optional root dot', () {
      for (final host in [
        'localhost',
        'LOCALHOST',
        'localhost.',
        'dev.localhost',
        'DEV.LOCALHOST.',
        'nested.dev.localhost.',
      ]) {
        expect(isLoopbackHost(host), isTrue, reason: host);
      }
    });

    test('accepts canonical addresses throughout IPv4 loopback', () {
      for (final host in [
        '127.0.0.0',
        '127.0.0.1',
        '127.1.20.234',
        '127.255.255.255',
      ]) {
        expect(isLoopbackHost(host), isTrue, reason: host);
      }
    });

    test('accepts the IPv6 loopback address', () {
      expect(isLoopbackHost('::1'), isTrue);
    });

    for (final host in [
      '0127.0.0.1',
      '00127.0.0.1',
      '0x7f.0.0.1',
      '+127.0.0.1',
      '127.00.0.1',
      '127.0.01.1',
      '127.0.0.01',
      '127.0x0.0.1',
      '127.0.0.0x1',
      '127.+0.0.1',
      '127.0.-0.1',
      '127.0.0.+1',
      '127.1',
      '127.0.1',
      '2130706433',
      '0x7f000001',
      '017700000001',
    ]) {
      test('rejects noncanonical IPv4 spelling $host', () {
        expect(isLoopbackHost(host), isFalse);
      });
    }

    test('rejects a root dot on numeric addresses', () {
      for (final host in ['127.0.0.1.', '127.255.255.255.', '::1.']) {
        expect(isLoopbackHost(host), isFalse, reason: host);
      }
    });

    test('rejects malformed IPv4 octets', () {
      for (final host in [
        '',
        '127..0.1',
        '127.0.0.',
        '127.0.0.1.2',
        '127.256.0.1',
        '127.0.256.1',
        '127.0.0.256',
        '127.-1.0.1',
        '127.0.0.-1',
        ' 127.0.0.1',
        '127.0.0. 1',
        '127.0.0.1 ',
        '127.0.0.1\n',
        '127.0.0.١',
        '127.0.0.１',
      ]) {
        expect(isLoopbackHost(host), isFalse, reason: host);
      }
    });

    test('rejects overlong octets', () {
      for (var index = 0; index < 4; index++) {
        final octets = ['127', '0', '0', '1'];
        octets[index] = octets[index].padLeft(4096, '0');
        expect(
          isLoopbackHost(octets.join('.')),
          isFalse,
          reason: 'overlong octet $index',
        );
      }
    });

    test('rejects non-loopback addresses and unrelated names', () {
      for (final host in [
        '0.0.0.0',
        '126.255.255.255',
        '128.0.0.0',
        '192.168.1.2',
        '::2',
        '::ffff:127.0.0.1',
        'localhost.example.com',
        'dev.localhost.example.com',
        'localhost..',
      ]) {
        expect(isLoopbackHost(host), isFalse, reason: host);
      }
    });
  });
}
