import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/voice/voice_icons.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

const registry = PluginRegistry([VoicePlugin()]);

DiscourseNotification voiceNotification({
  bool call = false,
  Map<String, dynamic> data = const {},
}) => DiscourseNotification.fromJson({
  'id': 1,
  'notification_type': 1000,
  'data': {'call': call ? true : null, ...data},
});

void main() {
  test('Voice owns room invitation wording, icon and inviter route', () {
    final resolved = registry.resolveNotification(
      voiceNotification(
        data: const {
          'display_username': 'Sam',
          'room_name': 'Team Room',
          'room_slug': 'team-room',
        },
      ),
    );

    expect(resolved.presentation.actor, 'Sam');
    expect(resolved.presentation.phrase, 'invited you to join Team Room');
    expect(resolved.presentation.icon, DIcons.microphoneLines);
    expect(resolved.path, '/voice/r/team-room/invited-by/sam');
  });

  test('Voice distinguishes incoming calls from room invitations', () {
    final resolved = registry.resolveNotification(
      voiceNotification(
        call: true,
        data: const {
          'display_username': 'sam',
          'room_name': 'Direct call',
          'room_slug': 'call-1',
        },
      ),
    );

    expect(resolved.presentation.actor, 'sam');
    expect(resolved.presentation.phrase, 'is calling you');
    expect(resolved.presentation.icon, VoiceIcons.phone);
    expect(resolved.path, '/voice/r/call-1/invited-by/sam');
  });

  test('malformed Voice payload stays visible without an unsafe route', () {
    final resolved = registry.resolveNotification(
      voiceNotification(data: const {'room_name': 'Team Room'}),
    );

    expect(resolved.presentation.actor, 'Someone');
    expect(resolved.presentation.phrase, 'invited you to join Team Room');
    expect(resolved.path, isNull);
  });
}
