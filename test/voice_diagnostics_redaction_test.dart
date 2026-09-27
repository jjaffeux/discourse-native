import 'package:discourse_native/src/plugins/voice/voice_diagnostics_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

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

  test('a sandboxed macOS home also redacts the account home it is in', () {
    const container =
        '/Users/jane/Library/Containers/org.discourse.native/Data';

    expect(
      VoiceDiagnosticsRedactor.scrub(
        "Cannot copy file to '/Users/jane/Downloads/voice.jsonl' "
        '$container/tmp/voice-export.jsonl /Users/bob/Downloads/voice.jsonl',
        homeDirectory: container,
      ),
      "Cannot copy file to '<home>/Downloads/voice.jsonl' "
      '<home>/tmp/voice-export.jsonl /Users/bob/Downloads/voice.jsonl',
    );
    expect(
      VoiceDiagnosticsRedactor.data({
        'path': '/Users/jane/Downloads/voice.jsonl',
      }, homeDirectory: container),
      {'path': '<home>/Downloads/voice.jsonl'},
    );
  });

  test('a home outside a sandbox container redacts only itself', () {
    expect(
      VoiceDiagnosticsRedactor.scrub(
        '/Users/jane/work/voice.jsonl /Users/jane/Downloads/voice.jsonl',
        homeDirectory: '/Users/jane/work',
      ),
      '<home>/voice.jsonl /Users/jane/Downloads/voice.jsonl',
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

  group('ICE server configurations', () {
    // Deep capture records every LiveKit log line, including the transport's
    // `[PCTransport] creating ${rtcConfig.toMap()}`. That map keeps each
    // server's `urls` as a nested list, ahead of its username.
    const config = livekit.RTCConfiguration(
      iceServers: [
        livekit.RTCIceServer(
          urls: [
            'turn:turn.example:3478?transport=udp',
            'turns:turn.example:443?transport=tcp',
          ],
          username: 'map-turn-username-secret',
          credential: 'map-turn-credential-secret',
        ),
        livekit.RTCIceServer(
          urls: ['turn:relay.example:3478?transport=udp'],
          username: 'second-turn-username-secret',
          credential: 'second-turn-credential-secret',
        ),
      ],
      iceTransportPolicy: livekit.RTCIceTransportPolicy.relay,
    );
    final transportLine = '[PCTransport] creating ${config.toMap()}';

    void expectRedacted(String safe) {
      for (final secret in const [
        'map-turn-username-secret',
        'map-turn-credential-secret',
        'second-turn-username-secret',
        'second-turn-credential-secret',
      ]) {
        expect(safe, isNot(contains(secret)), reason: secret);
      }
      for (final useful in const [
        '[PCTransport] creating {sdpSemantics: unified-plan',
        'urls: [turn:turn.example:3478?transport, '
            'turns:turn.example:443?transport]',
        'urls: [turn:relay.example:3478?transport]',
        'username: <redacted>',
      ]) {
        expect(safe, contains(useful), reason: useful);
      }
    }

    test('redact every username in the LiveKit transport config line', () {
      expect(transportLine, contains('map-turn-username-secret'));

      expectRedacted(VoiceDiagnosticsRedactor.scrub(transportLine));
    });

    test('redact a username in a config line cut short', () {
      final cut = transportLine.substring(
        0,
        transportLine.indexOf('map-turn-username-secret') +
            'map-turn-username-secret'.length,
      );

      final safe = VoiceDiagnosticsRedactor.scrub(cut);

      expect(safe, isNot(contains('map-turn-username-secret')));
      expect(safe, endsWith('username: <redacted>'));
    });

    test('redact every username in the protobuf join response form', () {
      final safe = VoiceDiagnosticsRedactor.scrub(
        'SignalJoinResponseEvent(response: room: {\n'
        '  name: voice\n'
        '}\n'
        'iceServers: {\n'
        '  urls: turn:turn.example:3478?transport=udp\n'
        '  urls: turns:turn.example:443?transport=tcp\n'
        '  username: proto-turn-username-secret\n'
        '  credential: proto-turn-credential-secret\n'
        '}\n'
        'iceServers: {\n'
        '  urls: turn:relay.example:3478?transport=udp\n'
        '  username: proto-second-username-secret\n'
        '}\n'
        ')',
      );

      for (final secret in const [
        'proto-turn-username-secret',
        'proto-turn-credential-secret',
        'proto-second-username-secret',
      ]) {
        expect(safe, isNot(contains(secret)), reason: secret);
      }
      expect(safe, contains('urls: turns:turn.example:443?transport\n'));
      expect(safe, contains('name: voice\n'));
    });

    test('re-redact a leaked username when a persisted record loads', () {
      final record = VoiceDiagnosticRecord.fromJson({
        'writerId': 'writer',
        'sequence': 1,
        'timestampUtc': '2026-09-27T12:00:00.000Z',
        'captureId': 'capture',
        'event': 'sdk.livekit.log',
        'component': 'livekit_sdk',
        'severity': 'debug',
        'message': transportLine,
        'data': {'level': 'FINE'},
        'truncated': false,
      });

      expectRedacted(record!.message!);
    });
  });
}
