import 'package:discourse_native/src/plugins/voice/voice_livekit_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('requireSafeLiveKitEndpoint', () {
    test('accepts secure WebSocket and HTTPS endpoints', () {
      for (final value in [
        'wss://livekit.example.com',
        'wss://livekit.example.com:7880/region',
        'https://livekit.example.com/region',
        'WSS://LIVEKIT.EXAMPLE.COM/region',
      ]) {
        expect(
          requireSafeLiveKitEndpoint(value),
          Uri.parse(value),
          reason: value,
        );
      }
    });

    test('accepts plaintext endpoints only on loopback hosts', () {
      for (final value in [
        'ws://localhost:7880',
        'http://dev.localhost:7880',
        'ws://LOCALHOST.:7880',
        'ws://127.0.0.1:7880',
        'http://127.255.255.254:7880',
        'ws://[::1]:7880',
      ]) {
        expect(
          requireSafeLiveKitEndpoint(value),
          Uri.parse(value),
          reason: value,
        );
      }
    });

    test('rejects plaintext endpoints on non-loopback hosts', () {
      for (final value in [
        'ws://livekit.example.com',
        'http://192.168.1.2',
        'ws://localhost.example.com',
        'http://127.0.0.999',
        'ws://127.0.0',
      ]) {
        expect(
          () => requireSafeLiveKitEndpoint(value),
          throwsA(isA<UnsafeLiveKitEndpointException>()),
          reason: value,
        );
      }
    });

    test('rejects missing authority or host', () {
      for (final value in [
        '',
        'wss:livekit.example.com',
        'wss:///rtc',
        '//livekit.example.com',
      ]) {
        expect(
          () => requireSafeLiveKitEndpoint(value),
          throwsA(isA<UnsafeLiveKitEndpointException>()),
          reason: value,
        );
      }
    });

    test('rejects userinfo on secure and loopback endpoints', () {
      for (final value in [
        'wss://reader@livekit.example.com',
        'https://reader:password@livekit.example.com',
        'ws://reader:password@localhost:7880',
      ]) {
        expect(
          () => requireSafeLiveKitEndpoint(value),
          throwsA(isA<UnsafeLiveKitEndpointException>()),
          reason: value,
        );
      }
    });

    test('rejects malformed endpoints and unsupported schemes', () {
      for (final value in [
        'wss://[::1',
        'wss://livekit.example.com:abc',
        'wss://livekit.example.com:65536',
        'wss://livekit.example.com/#fragment',
        'ftp://livekit.example.com',
        'file://livekit.example.com/rtc',
      ]) {
        expect(
          () => requireSafeLiveKitEndpoint(value),
          throwsA(isA<UnsafeLiveKitEndpointException>()),
          reason: value,
        );
      }
    });

    test('does not retain rejected userinfo in the exception', () {
      Object? error;
      try {
        requireSafeLiveKitEndpoint(
          'wss://reader:should-not-leak@livekit.example.com',
        );
      } catch (caught) {
        error = caught;
      }

      expect(error, isA<UnsafeLiveKitEndpointException>());
      expect(error.toString(), isNot(contains('should-not-leak')));
    });
  });
}
