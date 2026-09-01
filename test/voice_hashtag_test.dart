import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_hashtag.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Voice owns the room hashtag presentation', () {
    final registry = PluginRegistry.validated(const [VoicePlugin()]);
    final presentation = registry.pluginHashtagPresentation(
      HashtagPresentationRequest(
        type: voiceRoomHashtagKind.wireType,
        style: HashtagStyle.emoji,
        icon: 'headphones',
        emoji: 'studio_microphone',
        colorValues: const [0xFF112233],
      ),
    );

    expect(presentation, isNotNull);
    expect(presentation!.type, 'room');
    expect(presentation.style, HashtagStyle.emoji);
    expect(presentation.icon, 'headphones');
    expect(presentation.emoji, 'studio_microphone');
    expect(presentation.fallbackIcon, DIcons.microphoneLines);
    expect(presentation.colorPolicy, HashtagColorPolicy.none);
    expect(presentation.colorValues, isEmpty);
  });
}
