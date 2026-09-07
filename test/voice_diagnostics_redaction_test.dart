import 'package:discourse_native/src/plugins/voice/voice_diagnostics_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final encoded in [
    '%FF',
    '%C3',
    '%ED%A0%80',
    '%F4%90%80%80',
    '%80',
    '%C0%AF',
  ]) {
    test(
      'invalid UTF-8 query names cannot interrupt Voice diagnostics: $encoded',
      () {
        expect(
          VoiceDiagnosticsRedactor.scrub(
            'WebSocket failed: wss://voice.example/rtc?$encoded=SECRET#private',
          ),
          'WebSocket failed: wss://voice.example/rtc?invalid-query-name',
        );
        expect(
          VoiceDiagnosticsRedactor.data({
            'url': 'turn:voice.example?$encoded=SECRET#private',
          }),
          {'url': 'turn:voice.example?invalid-query-name'},
        );
      },
    );
  }

  test('encoded query separators cannot retain a Voice credential', () {
    expect(
      VoiceDiagnosticsRedactor.scrub(
        'wss://voice.example/rtc?code%3DSECRET&room=private',
      ),
      'wss://voice.example/rtc?code&room',
    );
  });

  for (final name in [
    'user_api_key',
    'push_token',
    'one_time_password',
    'app_secret',
  ]) {
    test('redacts a sensitive suffix in the wire field $name', () {
      final safe = VoiceDiagnosticsRedactor.scrub(
        '$name=SECRET participantId=42 transport=mesh',
      );

      expect(safe, isNot(contains('SECRET')));
      expect(safe, contains('<redacted>'));
      expect(safe, contains('participantId=42 transport=mesh'));
    });
  }
}
