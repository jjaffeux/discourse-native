import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_chat_message.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI installs independently when optional Chat is absent', () async {
    final installed = PluginInstaller.install(
      const PluginManifest([discourseAiModule]),
    );
    await installed.close();
  });
  test(
    'Chat receives one AI-owned decoder only when that plugin is installed',
    () async {
      final chatOnly = PluginInstaller.install(
        const PluginManifest([chatModule]),
      );
      final withAi = PluginInstaller.install(
        const PluginManifest([chatModule, discourseAiModule]),
      );
      addTearDown(chatOnly.close);
      addTearDown(withAi.close);
      final empty = ChatMessageCodec(
        chatOnly
            .staticContributionsFor(const PluginId('chat'))
            .contributions(chatMessageContributions),
      );
      final codec = ChatMessageCodec(
        withAi
            .staticContributionsFor(const PluginId('chat'))
            .contributions(chatMessageContributions),
      );
      const wire = {'id': 1, 'chat_channel_id': 9, 'ai_llm_name': 'Model C'};
      expect(empty.decode(wire, 'https://example.org').plugins.isEmpty, isTrue);
      expect(
        codec
            .decode(wire, 'https://example.org')
            .plugins
            .get(const AiChatMessageContribution().key)
            ?.model,
        'Model C',
      );
      expect(
        () => ChatMessageCodec([
          const AiChatMessageContribution(),
          const AiChatMessageContribution(),
        ]),
        throwsArgumentError,
      );
    },
  );
}
