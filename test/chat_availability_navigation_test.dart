import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://chat.example';
const _user = DiscourseUser(id: 7, username: 'reader');
final _disabledUser = DiscourseUser(
  id: 8,
  username: 'chat-disabled',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: false),
  ),
);

SiteConfig _config({
  bool enabled = true,
  bool channels = true,
  bool anonymous = false,
}) => SiteConfig(
  plugins: PluginData.none.withValue(
    chatSettingsDataKey,
    ChatSettings(
      chatEnabled: enabled,
      publicChannelsEnabled: channels,
      anonymousChatAllowed: anonymous,
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
  });

  for (final (name, config, user, totalsAvailable, chat, channels, threads) in [
    (
      'unknown guest site',
      const SiteConfig.unknown(),
      null,
      false,
      false,
      false,
      false,
    ),
    (
      'disabled guest site',
      _config(enabled: false),
      null,
      false,
      false,
      false,
      false,
    ),
    (
      'guest excluded by allowed groups',
      _config(),
      null,
      false,
      false,
      false,
      false,
    ),
    (
      'allowed guest',
      _config(anonymous: true),
      null,
      false,
      true,
      false,
      false,
    ),
    (
      'unknown signed-in site',
      const SiteConfig.unknown(),
      _user,
      true,
      false,
      false,
      false,
    ),
    ('disabled account', _config(), _disabledUser, true, false, false, false),
    ('unavailable account', _config(), _user, false, false, false, false),
    (
      'disabled signed-in site',
      _config(enabled: false),
      _user,
      true,
      false,
      false,
      false,
    ),
    ('enabled account', _config(), _user, true, true, true, true),
    (
      'public channels disabled',
      _config(channels: false),
      _user,
      true,
      true,
      false,
      true,
    ),
  ]) {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      testWidgets('Chat navigation respects $name on ${platform.name}', (
        tester,
      ) async {
        final mobile = platform != TargetPlatform.linux;
        final authenticator = FakeAuthenticator();
        if (user != null) authenticator.keys[_site] = 'key';
        await pumpShell(
          tester,
          mobile ? phone : desktop,
          instances: [
            instance('chat.example').copyWith(user: user, config: config),
          ],
          authenticator: authenticator,
          pluginManifest: PluginManifest([
            ChatModule(apiFactory: (transport) => transport as ChatApi),
          ]),
          api: FakeDiscourseApi(
            user: user,
            totals: chatNotificationTotals(available: totalsAvailable),
            siteConfigs: {_site: config},
          ),
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        if (chat && user == null) {
          await shell.pluginSession
              .require(chatControllerService)
              .loadChannels(_site);
          await tester.pumpAndSettle();
        }
        if (mobile) {
          final dock = tester.widget<DMobileDock>(find.byType(DMobileDock));
          final keys = dock.places.map((place) => place.key).toSet();
          expect(keys.contains(const ValueKey('mobile-mode-panel/chat')), chat);
          expect(
            keys.contains(
              const ValueKey('mobile-mode-destination/chat-browse'),
            ),
            channels,
          );
          expect(
            keys.contains(
              const ValueKey('mobile-mode-destination/chat-my-threads'),
            ),
            threads,
          );
          if (chat) {
            await tester.tap(
              find.byKey(const ValueKey('mobile-mode-panel/chat')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ChatMobileSidebar), findsOneWidget);
            expect(
              find.byKey(const ValueKey('chat-inbox-channels-card')),
              channels ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('chat-inbox-threads-card')),
              threads ? findsOneWidget : findsNothing,
            );
          }
        } else {
          expect(
            find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            chat ? findsOneWidget : findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(platform));
    }
  }
}
