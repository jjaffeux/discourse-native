import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/emoji_usage.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/plugins/chat/chat_emoji_usage.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_emoji_usage.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.example';
final _catalog = SiteEmojiCatalog(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('emoji preference hosts isolate plugin histories', () async {
    final (:chat, :reactions) = _hosts();

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

    expect(
      await chat.preferences.favoriteEmojiCodes(
        siteUrl: _site,
        context: chatEmojiUsageContext,
        catalog: _catalog,
      ),
      ['wave'],
    );
    expect(
      await reactions.preferences.favoriteEmojiCodes(
        siteUrl: _site,
        context: reactionsEmojiUsageContext,
        catalog: _catalog,
      ),
      ['tada'],
    );
  });

  test('emoji preference hosts reject foreign and malformed contexts', () {
    final (:chat, :reactions) = _hosts();
    final attempts = <({String name, Future<void> Function() run})>[
      (
        name: 'Chat using the Reactions context',
        run: () => chat.preferences.trackEmoji(
          siteUrl: _site,
          context: reactionsEmojiUsageContext,
          emoji: 'foreign',
        ),
      ),
      (
        name: 'Reactions using the Chat context',
        run: () => reactions.preferences.clearHistory(
          siteUrl: _site,
          context: chatEmojiUsageContext,
        ),
      ),
      (
        name: 'Chat using a malformed context name',
        run: () => chat.preferences.trackEmoji(
          siteUrl: _site,
          context: const EmojiUsageContext(
            owner: PluginId('chat'),
            name: 'invalid/context',
          ),
          emoji: 'foreign',
        ),
      ),
    ];

    for (final attempt in attempts) {
      expect(
        attempt.run,
        throwsA(isA<PluginInstallationException>()),
        reason: attempt.name,
      );
    }
  });

  test('emoji preference hosts share the forum skin tone', () async {
    final (:chat, :reactions) = _hosts();

    await chat.preferences.writeSkinTone(
      siteUrl: _site,
      tone: EmojiSkinTone.t5,
    );

    expect(
      await reactions.preferences.readSkinTone(siteUrl: _site),
      EmojiSkinTone.t5,
    );
  });
}

({PluginEmojiHost chat, PluginEmojiHost reactions}) _hosts() {
  final rawStore = EmojiPickerStore(persistence: _MemoryEmojiPersistence());
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
  return (
    chat: shell.pluginSession.require(chatEmojiHostService),
    reactions: shell.pluginSession.require(reactionsEmojiHostService),
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
