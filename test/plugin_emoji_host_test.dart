import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugins/chat/chat_emoji_usage.dart';
import 'package:discourse_native/src/plugins/plugin_services.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_emoji_usage.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'emoji preference hosts isolate plugin contexts and share skin tone',
    () async {
      final persistence = _MemoryEmojiPersistence();
      final rawStore = EmojiPickerStore(persistence: persistence);
      final shell = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.example')]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        emojiPickerStore: rawStore,
        trackers: FakeSiteTracker.reset(),
        plugins: installedPlugins,
        ownsApi: false,
      );
      addTearDown(shell.dispose);

      final chat = shell.pluginSession.require(chatEmojiHostService);
      final reactions = shell.pluginSession.require(reactionsEmojiHostService);

      expect(chat.preferences, isNot(isA<EmojiPickerStore>()));
      expect(reactions.preferences, isNot(same(chat.preferences)));

      await chat.preferences.trackEmoji(
        siteUrl: _site,
        context: chatEmojiUsageContext,
        emoji: 'wave',
      );
      await reactions.preferences.trackEmoji(
        siteUrl: _site,
        context: reactionsEmojiUsageContext,
        emoji: 'tada',
      );

      for (final attempt in <Future<void> Function()>[
        () => chat.preferences.trackEmoji(
          siteUrl: _site,
          context: reactionsEmojiUsageContext,
          emoji: 'foreign',
        ),
        () => reactions.preferences.clearHistory(
          siteUrl: _site,
          context: chatEmojiUsageContext,
        ),
        () => chat.preferences.trackEmoji(
          siteUrl: _site,
          context: const EmojiUsageContext(
            owner: PluginId('chat'),
            name: 'invalid/context',
          ),
          emoji: 'foreign',
        ),
      ]) {
        expect(attempt, throwsA(isA<PluginInstallationException>()));
      }

      final catalog = SiteEmojiCatalog(
        groups: [
          SiteEmojiGroup(
            id: 'people',
            emojis: const [
              SiteEmoji(name: 'wave', url: 'https://cdn.example/wave.png'),
              SiteEmoji(name: 'tada', url: 'https://cdn.example/tada.png'),
            ],
          ),
        ],
      );
      expect(
        await chat.preferences.favoriteEmojiCodes(
          siteUrl: _site,
          context: chatEmojiUsageContext,
          catalog: catalog,
        ),
        ['wave'],
      );
      expect(
        await reactions.preferences.favoriteEmojiCodes(
          siteUrl: _site,
          context: reactionsEmojiUsageContext,
          catalog: catalog,
        ),
        ['tada'],
      );

      await chat.preferences.writeSkinTone(
        siteUrl: _site,
        tone: EmojiSkinTone.t5,
      );
      expect(
        await reactions.preferences.readSkinTone(siteUrl: _site),
        EmojiSkinTone.t5,
      );
    },
  );
}

final class _MemoryEmojiPersistence implements EmojiPickerPersistence {
  final Map<String, String> values = {};

  @override
  Future<String?> readPreferences({required String siteUrl}) async =>
      values[siteUrl];

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async {
    values[siteUrl] = encoded;
    return true;
  }
}
