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

  group('libwebrtc candidate strings', () {
    test('keep a full IPv6 address whose groups look like the tail', () {
      // Candidate::ToString() (not the sensitive form) prints the whole
      // address, so its colon-separated numeric groups sit just before the
      // credentials and must not be mistaken for them.
      expect(
        VoiceDiagnosticsRedactor.scrub(
          'Invalid candidate: Cand[:1:1:udp:2122262783:'
          '[2001:db8:0:1:2:3:4:5]:5000:host:[::]:0:'
          'Zt7UfragZz9:Zt7PwdZz90123456789abcd:0:0:0]',
        ),
        'Invalid candidate: Cand[:1:1:udp:2122262783:'
        '[2001:db8:0:1:2:3:4:5]:5000:host:[::]:0:'
        '<redacted>:<redacted>:0:0:0]',
      );
    });

    test('redact an unrecognised shape to the end of its line', () {
      // A ufrag with a colon, as a remote peer could send, moves the
      // password out of its field; so would a new field in a later release.
      expect(
        VoiceDiagnosticsRedactor.scrub(
          'Duplicate candidate: Cand[:1:1:udp:1:198.51.100.x:5000:host::0:'
          'odd:Zt7UfragZz9:Zt7PwdZz90123456789abcd:0:0:0] trailing\n'
          'next line survives',
        ),
        'Duplicate candidate: Cand[<redacted>]\nnext line survives',
      );
    });

    test('redact the password after an empty ufrag label', () {
      expect(
        VoiceDiagnosticsRedactor.scrub(
          'Cannot gather candidates because ICE parameters are empty '
          'ufrag:  pwd: Zt7PwdZz90123456789abcd\n',
        ),
        'Cannot gather candidates because ICE parameters are empty '
        'ufrag:  pwd: <redacted>\n',
      );
    });

    test('leave credential-free native log lines intact', () {
      const lines =
          '(port.cc:1011): Port[1049c8a00:0:1:0:host:'
          'Net[en0:192.168.1.x/24:Wifi:id=1]]: Port deleted\n'
          '(transport_description.cc:67): ICE pwd must be between 22 and 256 '
          'characters long.\n'
          '(p2p_transport_channel.cc:1573): Candidates[0] pruned; '
          'passwordless check skipped\n';
      expect(VoiceDiagnosticsRedactor.scrub(lines), lines);
    });
  });
}
