import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/new_tab_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://chat.example';
const _user = DiscourseUser(id: 7, username: 'reader');
const _channel = ChatChannel(
  id: 9,
  title: 'General discussion',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
);

Finder _heading(String label) => find.descendant(
  of: find.byType(NewTabPage).first,
  matching: find.byKey(ValueKey('start-page-section-link-$label')),
);

Finder _recent(String tabId) => find.descendant(
  of: find.byType(NewTabPage).first,
  matching: find.byKey(ValueKey('start-page-recent-closed-$tabId')),
);

SiteConfig _config({bool channels = true, bool threads = true}) => SiteConfig(
  plugins: PluginData.none.withValue(
    chatSettingsDataKey,
    ChatSettings(
      chatEnabled: true,
      publicChannelsEnabled: channels,
      threadsEnabled: threads,
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
  });

  testWidgets('Start Chat headings follow site settings and account access', (
    tester,
  ) async {
    final sites = [
      instance('chat.example').copyWith(user: _user, config: _config()),
      instance(
        'threads.example',
      ).copyWith(user: _user, config: _config(channels: false)),
      instance(
        'channels.example',
      ).copyWith(user: _user, config: _config(threads: false)),
      instance('guest.example').copyWith(config: _config()),
      instance('disabled.example').copyWith(
        user: DiscourseUser(
          id: 8,
          username: 'chat-disabled',
          plugins: PluginData.none.withValue(
            chatCurrentUserDataKey,
            const ChatCurrentUser(hasChatEnabled: false),
          ),
        ),
        config: _config(),
      ),
    ];
    await pumpShell(
      tester,
      desktop,
      instances: sites,
      authenticator: FakeAuthenticator()
        ..keys.addAll({
          for (final site in sites.where((site) => site.user != null))
            site.url: site.url,
        }),
      pluginManifest: PluginManifest([
        ChatModule(apiFactory: (transport) => transport as ChatApi),
      ]),
      api:
          FakeDiscourseApi(
              totals: chatNotificationTotals(available: true),
              siteConfigs: {for (final site in sites) site.url: site.config},
            )
            ..accounts.addAll({
              for (final site in sites.where((site) => site.user != null))
                site.url: site.user!,
            }),
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MainContent).first),
    );

    for (final (index, channels, threads) in [
      (0, true, true),
      (1, false, true),
      (2, true, false),
      (3, true, false),
      (4, false, false),
      (0, true, true),
    ]) {
      shell.selectInstance(index);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      expect(_heading('Channels'), channels ? findsOneWidget : findsNothing);
      expect(_heading('Threads'), threads ? findsOneWidget : findsNothing);
    }

    for (final (label, route) in [
      ('Channels', ChatPlugin.browseRouteId),
      ('Threads', ChatPlugin.myThreadsRouteId),
    ]) {
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(_heading(label)));
      await tester.pumpAndSettle();
      await tester.tap(_heading(label));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, route);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'Start filters current channel labels and reopens a closed channel',
    (tester) async {
      final config = _config();
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance('chat.example').copyWith(user: _user, config: config),
        ],
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        pluginManifest: PluginManifest([
          ChatModule(apiFactory: (transport) => transport as ChatApi),
        ]),
        api: FakeDiscourseApi(
          user: _user,
          totals: chatNotificationTotals(available: true),
          siteConfigs: {_site: config},
          chatChannelsBySite: {
            _site: const ChatChannels(public: [_channel]),
          },
          chatChannelsById: const {9: _channel},
        ),
      );
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      await shell.pluginSession
          .require(chatControllerService)
          .loadChannels(_site);
      shell.createTab();
      shell.pushContent(
        const ContentRoute(
          destination: ExtensionDestination('chat-c-9'),
          title: 'Old channel title',
          icon: DIcons.hashtag,
        ),
      );
      final channelTab = shell.activeTabId!;
      shell.closeTab(channelTab);
      shell.createTab();
      shell.pushContent(
        const ContentRoute(
          destination: ExtensionDestination('chat-c-9-t-31'),
          title: 'Incident thread',
          icon: DIcons.comments,
        ),
      );
      final threadTab = shell.activeTabId!;
      shell.closeTab(threadTab);
      shell.pushContent(ContentRoute.newTab());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _recent(channelTab),
          matching: find.text(_channel.title),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _recent(threadTab),
          matching: find.text('Incident thread'),
        ),
        findsOneWidget,
      );
      final startTab = shell.activeTabId!;
      shell.search.setStartPageQuery(_site, startTab, 'GENERAL');
      await tester.pumpAndSettle();
      expect(_recent(channelTab), findsOneWidget);
      expect(_recent(threadTab), findsNothing);
      expect(_heading('Channels'), findsOneWidget);
      expect(_heading('Threads'), findsOneWidget);

      shell.search.setStartPageQuery(_site, startTab, 'incident');
      await tester.pumpAndSettle();
      expect(_recent(channelTab), findsNothing);
      expect(_recent(threadTab), findsOneWidget);
      shell.search.setStartPageQuery(_site, startTab, '');
      await tester.pumpAndSettle();
      await tester.tap(_recent(channelTab));
      await tester.pumpAndSettle();
      expect(shell.activeTabId, channelTab);
      expect(shell.currentContent?.id, 'chat-c-9');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
