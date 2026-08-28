import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _registry = PluginRegistry([ChatPlugin()]);

void main() {
  test('installed plugin decodes Chat site-settings wire keys', () {
    final config = SiteConfig.fromSettings(const {
      'chat_allow_uploads': false,
      'chat_search_enabled': true,
      'chat_channel_retention_days': 180,
      'chat_dm_retention_days': 30,
    }, extensions: _registry);

    expect(
      config.chatSettings,
      const ChatSettings(
        uploadsEnabled: false,
        searchEnabled: true,
        channelRetentionDays: 180,
        directMessageRetentionDays: 30,
      ),
    );
  });

  test('installed plugin decodes Chat current-user wire keys', () {
    const models = DiscourseModelCodec(extensions: _registry);
    final user = models.currentUser(const {
      'id': 7,
      'username': 'sam',
      'has_chat_enabled': true,
      'ignored_users': ['hawk', false, 'kris', null],
      'custom_fields': {'last_chat_channel_id': '42'},
      'user_option': {'chat_header_indicator_preference': 'only_mentions'},
    }, 'https://forum.example');

    expect(
      user.chatCurrentUser,
      const ChatCurrentUser(
        hasChatEnabled: true,
        headerIndicatorPreference: ChatHeaderIndicatorPreference.onlyMentions,
        lastChannelId: 42,
        ignoredUsernames: ['hawk', 'kris'],
      ),
    );
    expect(user.ignoredUsernames, ['hawk', 'kris']);
    expect(() => user.ignoredUsernames.add('lee'), throwsUnsupportedError);

    final absent = models.currentUser(const {
      'username': 'sam',
    }, 'https://forum.example');
    expect(absent.chatCurrentUser?.hasChatEnabled, isFalse);
  });

  test('namespaced settings and current user round-trip without flat keys', () {
    final config = SiteConfig.fromJson({
      'plugins': {
        chatSettingsDataKey.id: const {
          'uploadsEnabled': false,
          'searchEnabled': true,
          'channelRetentionDays': 90,
          'directMessageRetentionDays': 14,
        },
      },
    }, extensions: _registry);
    final user = DiscourseUser.fromJson({
      'username': 'sam',
      'plugins': {
        chatCurrentUserDataKey.id: const {
          'hasChatEnabled': true,
          'headerIndicatorPreference': 'dm_and_mentions',
          'lastChannelId': 17,
          'ignoredUsernames': ['hawk', 'kris'],
        },
      },
    }, extensions: _registry);

    final storedConfig = config.toJson(extensions: _registry);
    final storedUser = user.toJson(extensions: _registry);
    expect(storedConfig, isNot(contains('chatSearchEnabled')));
    expect(storedConfig['plugins'], {
      chatSettingsDataKey.id: {
        'uploadsEnabled': false,
        'searchEnabled': true,
        'channelRetentionDays': 90,
        'directMessageRetentionDays': 14,
      },
    });
    expect(storedUser, isNot(contains('hasChatEnabled')));
    expect(storedUser, isNot(contains('chatHeaderIndicatorPreference')));
    expect(storedUser, isNot(contains('lastChatChannelId')));
    expect(storedUser['plugins'], {
      chatCurrentUserDataKey.id: {
        'hasChatEnabled': true,
        'headerIndicatorPreference': 'dm_and_mentions',
        'lastChannelId': 17,
        'ignoredUsernames': ['hawk', 'kris'],
      },
    });

    expect(SiteConfig.fromJson(storedConfig, extensions: _registry), config);
    expect(DiscourseUser.fromJson(storedUser, extensions: _registry), user);
  });

  test('legacy flat values migrate into Chat namespaces', () {
    final config = SiteConfig.fromJson(const {
      'chatUploadsEnabled': false,
      'chatSearchEnabled': true,
      'chatChannelRetentionDays': 45,
      'chatDmRetentionDays': 7,
    }, extensions: _registry);
    final user = DiscourseUser.fromJson(const {
      'username': 'sam',
      'hasChatEnabled': false,
      'chatHeaderIndicatorPreference': 'never',
      'lastChatChannelId': 9,
      'ignoredUsernames': ['hawk', false, 'kris', null],
    }, extensions: _registry);

    expect(
      config.chatSettings,
      const ChatSettings(
        uploadsEnabled: false,
        searchEnabled: true,
        channelRetentionDays: 45,
        directMessageRetentionDays: 7,
      ),
    );
    expect(
      user.chatCurrentUser,
      const ChatCurrentUser(
        hasChatEnabled: false,
        headerIndicatorPreference: ChatHeaderIndicatorPreference.never,
        lastChannelId: 9,
        ignoredUsernames: ['hawk', 'kris'],
      ),
    );
    expect(
      config.toJson(extensions: _registry)['plugins'],
      contains(chatSettingsDataKey.id),
    );
    expect(
      user.toJson(extensions: _registry)['plugins'],
      contains(chatCurrentUserDataKey.id),
    );
  });

  test('legacy ignored users merge into an existing Chat namespace', () {
    final user = DiscourseUser.fromJson({
      'id': 7,
      'username': 'sam',
      'ignoredUsernames': const ['hawk', false, 'kris'],
      'plugins': {
        chatCurrentUserDataKey.id: const {
          'hasChatEnabled': true,
          'headerIndicatorPreference': 'only_mentions',
          'lastChannelId': 42,
        },
      },
    }, extensions: _registry);

    expect(
      user.chatCurrentUser,
      const ChatCurrentUser(
        hasChatEnabled: true,
        headerIndicatorPreference: ChatHeaderIndicatorPreference.onlyMentions,
        lastChannelId: 42,
        ignoredUsernames: ['hawk', 'kris'],
      ),
    );

    final stored = user.toJson(extensions: _registry);
    expect(stored, isNot(contains('ignoredUsernames')));
    expect(stored['plugins'], {
      chatCurrentUserDataKey.id: {
        'hasChatEnabled': true,
        'headerIndicatorPreference': 'only_mentions',
        'lastChannelId': 42,
        'ignoredUsernames': ['hawk', 'kris'],
      },
    });
  });

  test('namespaced ignored users remain authoritative during migration', () {
    final user = DiscourseUser.fromJson({
      'username': 'sam',
      'ignoredUsernames': const ['legacy'],
      'plugins': {
        chatCurrentUserDataKey.id: const {
          'ignoredUsernames': ['namespaced'],
        },
      },
    }, extensions: _registry);

    expect(user.ignoredUsernames, ['namespaced']);
  });

  test('core-only storage preserves opaque Chat current-user data', () {
    const coreModels = DiscourseModelCodec.core();
    final held = DiscourseUser.fromJson({
      'id': 7,
      'username': 'sam',
      'plugins': {
        chatCurrentUserDataKey.id: const {
          'hasChatEnabled': true,
          'ignoredUsernames': ['hawk'],
          'futureShape': {
            'nested': [1, 'two', null],
          },
        },
      },
    });
    final incoming = coreModels.currentUser(const {
      'id': 7,
      'username': 'sam',
      'ignored_users': ['new-live-value'],
    }, 'https://forum.example');

    final merged = coreModels.preserveUnknownCurrentUser(held, incoming);
    expect(merged.chatCurrentUser, isNull);
    expect(merged.toJson()['plugins'], {
      chatCurrentUserDataKey.id: {
        'hasChatEnabled': true,
        'ignoredUsernames': ['hawk'],
        'futureShape': {
          'nested': [1, 'two', null],
        },
      },
    });

    final restored = DiscourseUser.fromJson(
      merged.toJson(),
      extensions: _registry,
    );
    expect(restored.ignoredUsernames, ['hawk']);
  });

  test('Chat-owned policies use typed Chat data', () {
    final disabledSettings = SiteConfig(
      plugins: SiteConfig.fromSettings(const {
        'chat_allow_uploads': false,
      }, extensions: _registry).plugins,
    );
    final disabledUser = DiscourseUser.fromJson(const {
      'username': 'sam',
      'hasChatEnabled': false,
    }, extensions: _registry);

    final composerPolicy = const ChatPlugin().createComposerTarget(
      const ComposerTargetRequest(
        kind: ChatPlugin.messageComposerTarget,
        siteUrl: 'https://forum.example',
        title: 'Chat',
        data: {ChatPlugin.composerChannelId: 9},
      ),
      ComposerTargetContext(
        siteSettings: disabledSettings.plugins,
        currentUser: PluginData.none,
      ),
    );

    expect(composerPolicy.uploadsEnabled, isFalse);
    expect(
      _registry.currentUserFeatureEnabled('chat', disabledUser.plugins),
      isFalse,
    );
    expect(
      _registry.currentUserFeatureEnabled(
        'chat',
        const DiscourseUser(username: 'old').plugins,
      ),
      isTrue,
    );
    expect(
      PluginRegistry.empty.currentUserFeatureEnabled(
        'chat',
        disabledUser.plugins,
      ),
      isFalse,
    );
  });
}
