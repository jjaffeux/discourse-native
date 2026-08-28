import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_resenha/src/resenha_hashtag.dart';
import 'package:discourse_resenha/src/resenha_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Resenha owns the room hashtag presentation', () {
    final registry = PluginRegistry.validated(const [ResenhaPlugin()]);
    final presentation = registry.pluginHashtagPresentation(
      HashtagPresentationRequest(
        type: resenhaRoomHashtagKind.wireType,
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
