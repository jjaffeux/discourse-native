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
  group('Chat wire decoding', () {
    test('decodes site-settings keys into typed data', () {
      final config = SiteConfig.fromSettings(const {
        'chat_enabled': false,
        'chat_allow_uploads': false,
        'chat_search_enabled': true,
        'enable_public_channels': false,
        'chat_threads_enabled': false,
        'chat_preferred_index': 'my_threads',
        'chat_channel_retention_days': 180,
        'chat_dm_retention_days': 30,
        'chat_max_direct_message_users': 35,
        'chat_separate_sidebar_mode': 'fullscreen',
      }, extensions: _registry);

      expect(
        config.chatSettings,
        const ChatSettings(
          chatEnabled: false,
          uploadsEnabled: false,
          searchEnabled: true,
          publicChannelsEnabled: false,
          threadsEnabled: false,
          preferredIndex: ChatPreferredIndex.myThreads,
          channelRetentionDays: 180,
          directMessageRetentionDays: 30,
          maximumDirectMessageUsers: 35,
          separateSidebarMode: ChatSeparateSidebarMode.fullscreen,
        ),
      );
    });

    test('decodes current-user keys into immutable typed data', () {
      const models = DiscourseModelCodec(extensions: _registry);
      final user = models.currentUser(const {
        'id': 7,
        'username': 'sam',
        'has_chat_enabled': true,
        'can_chat': true,
        'can_direct_message': true,
        'ignored_users': ['hawk', false, 'kris', null],
        'custom_fields': {'last_chat_channel_id': '42'},
        'user_option': {
          'chat_header_indicator_preference': 'only_mentions',
          'chat_separate_sidebar_mode': 'always',
        },
      }, 'https://forum.example');

      expect(
        user.chatCurrentUser,
        const ChatCurrentUser(
          hasChatEnabled: true,
          canChat: true,
          canDirectMessage: true,
          headerIndicatorPreference: ChatHeaderIndicatorPreference.onlyMentions,
          separateSidebarMode: ChatSeparateSidebarMode.always,
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
      expect(absent.canChat, isFalse);
      expect(absent.canDirectMessage, isFalse);
      expect(
        absent.chatSeparateSidebarMode,
        ChatSeparateSidebarMode.siteDefault,
      );
    });

    test(
      'keeps legacy settings enabled unless chat is explicitly disabled',
      () {
        expect(ChatSettings.fromSettings(const {}).chatEnabled, isTrue);
        expect(ChatSettings.fromStored(const {}).chatEnabled, isTrue);
        expect(
          ChatSettings.fromStored(const {'chatEnabled': false}).chatEnabled,
          isFalse,
        );
        expect(
          chatSettingsPersistenceCodec.encode(
            const ChatSettings(chatEnabled: false),
          ),
          containsPair('chatEnabled', false),
        );
      },
    );

    test('decodes every supported separate-sidebar wire value', () {
      const siteModes = {
        'never': ChatSeparateSidebarMode.never,
        'always': ChatSeparateSidebarMode.always,
        'fullscreen': ChatSeparateSidebarMode.fullscreen,
      };
      for (final entry in siteModes.entries) {
        expect(
          ChatSettings.fromSettings({
            'chat_separate_sidebar_mode': entry.key,
          }).separateSidebarMode,
          entry.value,
        );
      }

      for (final mode in ChatSeparateSidebarMode.values) {
        expect(
          ChatCurrentUser.fromCurrentUser({
            'user_option': {'chat_separate_sidebar_mode': mode.wireName},
          }).separateSidebarMode,
          mode,
        );
      }
    });

    test('decodes every preferred-index wire value and defaults safely', () {
      const cases = {
        'channels': ChatPreferredIndex.channels,
        'direct_messages': ChatPreferredIndex.directMessages,
        'my_threads': ChatPreferredIndex.myThreads,
      };
      for (final entry in cases.entries) {
        expect(
          ChatSettings.fromSettings({
            'chat_preferred_index': entry.key,
          }).preferredIndex,
          entry.value,
        );
      }

      for (final malformed in [null, true, 7, 'unknown']) {
        expect(
          ChatSettings.fromSettings({
            'chat_preferred_index': malformed,
          }).preferredIndex,
          ChatPreferredIndex.channels,
        );
      }
      expect(
        const ChatSettings(preferredIndex: ChatPreferredIndex.channels),
        isNot(
          const ChatSettings(preferredIndex: ChatPreferredIndex.directMessages),
        ),
      );
    });

    test('uses safe defaults for absent and malformed sidebar modes', () {
      for (final malformed in [null, true, 7, 'sometimes', 'default']) {
        expect(
          ChatSettings.fromSettings({
            'chat_separate_sidebar_mode': malformed,
          }).separateSidebarMode,
          ChatSeparateSidebarMode.never,
        );
      }

      expect(
        ChatCurrentUser.fromCurrentUser(const {
          'user_option': {'chat_separate_sidebar_mode': null},
        }).separateSidebarMode,
        ChatSeparateSidebarMode.siteDefault,
      );
      for (final malformed in [true, 7, 'sometimes']) {
        expect(
          ChatCurrentUser.fromCurrentUser({
            'user_option': {'chat_separate_sidebar_mode': malformed},
          }).separateSidebarMode,
          ChatSeparateSidebarMode.never,
        );
      }
    });

    test('resolves default against the site setting and honors overrides', () {
      for (final siteMode in const [
        ChatSeparateSidebarMode.never,
        ChatSeparateSidebarMode.always,
        ChatSeparateSidebarMode.fullscreen,
      ]) {
        expect(
          effectiveChatSeparateSidebarMode(
            settings: ChatSettings(separateSidebarMode: siteMode),
            currentUser: const ChatCurrentUser(),
          ),
          siteMode,
        );
        expect(
          effectiveChatSeparateSidebarMode(
            settings: ChatSettings(separateSidebarMode: siteMode),
          ),
          siteMode,
        );
      }

      for (final userMode in const [
        ChatSeparateSidebarMode.never,
        ChatSeparateSidebarMode.always,
        ChatSeparateSidebarMode.fullscreen,
      ]) {
        expect(
          effectiveChatSeparateSidebarMode(
            settings: const ChatSettings(
              separateSidebarMode: ChatSeparateSidebarMode.fullscreen,
            ),
            currentUser: ChatCurrentUser(separateSidebarMode: userMode),
          ),
          userMode,
        );
      }
    });
  });

  group('Chat persistence and migration', () {
    test('round-trips namespaced settings and user data without flat keys', () {
      final config = SiteConfig.fromJson({
        'plugins': {
          chatSettingsDataKey.id: const {
            'uploadsEnabled': false,
            'searchEnabled': true,
            'channelRetentionDays': 90,
            'directMessageRetentionDays': 14,
            'maximumDirectMessageUsers': 30,
            'separateSidebarMode': 'fullscreen',
            'preferredIndex': 'direct_messages',
          },
        },
      }, extensions: _registry);
      final user = DiscourseUser.fromJson({
        'username': 'sam',
        'plugins': {
          chatCurrentUserDataKey.id: const {
            'hasChatEnabled': true,
            'canChat': true,
            'canDirectMessage': true,
            'headerIndicatorPreference': 'dm_and_mentions',
            'separateSidebarMode': 'always',
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
          'maximumDirectMessageUsers': 30,
          'separateSidebarMode': 'fullscreen',
          'preferredIndex': 'direct_messages',
        },
      });
      expect(storedUser, isNot(contains('hasChatEnabled')));
      expect(storedUser, isNot(contains('chatHeaderIndicatorPreference')));
      expect(storedUser, isNot(contains('lastChatChannelId')));
      expect(storedUser['plugins'], {
        chatCurrentUserDataKey.id: {
          'hasChatEnabled': true,
          'canChat': true,
          'canDirectMessage': true,
          'headerIndicatorPreference': 'dm_and_mentions',
          'separateSidebarMode': 'always',
          'lastChannelId': 17,
          'ignoredUsernames': ['hawk', 'kris'],
        },
      });

      expect(SiteConfig.fromJson(storedConfig, extensions: _registry), config);
      expect(DiscourseUser.fromJson(storedUser, extensions: _registry), user);
    });

    test('round-trips every separate-sidebar mode through stored data', () {
      for (final mode in const [
        ChatSeparateSidebarMode.never,
        ChatSeparateSidebarMode.always,
        ChatSeparateSidebarMode.fullscreen,
      ]) {
        final settings = ChatSettings(separateSidebarMode: mode);
        expect(
          chatSettingsPersistenceCodec.decode(
            chatSettingsPersistenceCodec.encode(settings),
          ),
          settings,
        );
      }

      for (final mode in ChatSeparateSidebarMode.values) {
        final currentUser = ChatCurrentUser(separateSidebarMode: mode);
        expect(
          chatCurrentUserPersistenceCodec.decode(
            chatCurrentUserPersistenceCodec.encode(currentUser),
          ),
          currentUser,
        );
      }
    });

    test('round-trips every preferred index through stored data', () {
      for (final preferredIndex in ChatPreferredIndex.values) {
        final settings = ChatSettings(preferredIndex: preferredIndex);
        expect(
          chatSettingsPersistenceCodec.decode(
            chatSettingsPersistenceCodec.encode(settings),
          ),
          settings,
        );
      }
    });

    test('migrates legacy flat values into namespaces', () {
      final config = SiteConfig.fromJson(const {
        'chatUploadsEnabled': false,
        'chatSearchEnabled': true,
        'chatChannelRetentionDays': 45,
        'chatDmRetentionDays': 7,
        'chatMaximumDirectMessageUsers': 12,
        'chatPreferredIndex': 'my_threads',
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
          maximumDirectMessageUsers: 12,
          preferredIndex: ChatPreferredIndex.myThreads,
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

    test('merges legacy ignored users into an existing namespace', () {
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
          'separateSidebarMode': 'default',
          'lastChannelId': 42,
          'ignoredUsernames': ['hawk', 'kris'],
        },
      });
    });

    test('keeps namespaced ignored users authoritative during migration', () {
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

    test('preserves opaque current-user data through core-only storage', () {
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
  });

  group('Chat feature policy', () {
    test('uses typed settings and current-user data', () {
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
  });
}
