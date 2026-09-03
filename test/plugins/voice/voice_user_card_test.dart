import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:discourse_native/src/plugins/voice/voice_user_card.dart';
import 'package:flutter_test/flutter_test.dart';

const registry = PluginRegistry([VoicePlugin()]);
const site = 'https://voice.example';

void main() {
  test("Voice reads the site's call permission off the user card", () {
    expect(
      registry
          .readUserCard(const {'voice_can_call': true}, site)
          .get(voiceUserCardKey)
          ?.canCall,
      isTrue,
    );
    expect(
      registry
          .readUserCard(const {'voice_can_call': false}, site)
          .get(voiceUserCardKey)
          ?.canCall,
      isFalse,
    );
  });

  test('a card without the field says nothing about calling', () {
    expect(
      registry
          .readUserCard(const {'username': 'kim'}, site)
          .get(voiceUserCardKey),
      isNull,
    );
  });
}
