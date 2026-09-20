import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);
final _bar = find.byKey(const ValueKey('mobile-bottom-bar'));
final _header = find.byKey(const ValueKey('mobile-header'));

Future<ShellController> _pumpMobile(
  WidgetTester tester, {
  Size size = phone,
  bool voice = false,
}) async {
  final config = SiteConfig(
    plugins: PluginData.none
        .withValue(
          chatSettingsDataKey,
          const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
        )
        .withValue(voiceSettingsDataKey, VoiceClientConfig(enabled: voice)),
  );
  await pumpShell(
    tester,
    size,
    pluginManifest: PluginManifest([
      ...bundledWidgetTestManifest.modules,
      if (voice) const VoiceModule.withoutDiagnostics(),
    ]),
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Meta',
      ).copyWith(user: _user, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: _user,
      totals: chatNotificationTotals(available: true),
      siteConfigs: {_site: config},
      pluginResponses: {
        if (voice)
          'GET /voice/rooms.json': {
            'rooms': [
              {
                'id': 7,
                'name': 'Watercooler',
                'slug': 'watercooler',
                'room_type': 'conference',
                'active_participants': <Object>[],
              },
            ],
            'can_create_room': true,
          },
      },
      feeds: const {
        '/latest.json': [
          Topic(id: 7, title: 'Shared topic card', slug: 'shared'),
        ],
      },
      topics: {7: topicPayload(id: 7, title: 'Shared topic card')},
      chatMessagesByKey: {
        FakeDiscourseApi.chatMessagesKey(10): (
          messages: const [],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
      chatChannelsBySite: {
        _site: const ChatChannels(
          public: [
            ChatChannel(
              id: 9,
              title: 'General',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
            ),
          ],
          direct: [
            ChatChannel(
              id: 10,
              title: 'sam',
              kind: ChatChannelKind.directMessage,
              users: [ChatUser(id: 2, username: 'sam')],
              membership: ChatMembership(following: true),
            ),
          ],
        ),
      },
    ),
  );
  final shell = ShellScope.read(tester.element(find.byType(MobileForumRoot)));
  if (voice) {
    await shell.pluginSession
        .require(voiceControllerService)
        .ensureLoaded(_site);
    await tester.pumpAndSettle();
  }
  return shell;
}

void _expectPage() {
  expect(_bar, findsNothing);
  expect(_header, findsNothing);
  expect(find.byType(InstanceRail), findsNothing);
  expect(find.byType(ShellTitleBar), findsNothing);
  expect(find.byType(ForumTabsBar), findsNothing);
}

void _mobileTest(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: const TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  }),
);

void main() {
  _mobileTest('available modes stay scoped and revoked Voice returns home', (
    tester,
  ) async {
    final shell = await _pumpMobile(tester, voice: true);
    final voice = shell.pluginSession.require(voiceControllerService);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-voice')));
    await tester.pumpAndSettle();
    expect(find.text('Watercooler'), findsOneWidget);
    expect(find.byType(InstanceRail), findsNothing);
    expect(voice.call, isNull);
    voice.forget(_site);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-mode-voice')), findsNothing);
    expect(find.byType(InstanceRail), findsOneWidget);
    expect(shell.mobileNavigation.panelOwner, isNull);
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'home has rail, bell and desktop logo actions; search is a dedicated page',
    (tester) async {
      await _pumpMobile(tester);
      expect(_bar, findsOneWidget);
      expect(_header, findsOneWidget);
      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byKey(UserMenuButton.bellKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.avatarKey), findsOneWidget);
      expect(find.byKey(ForumSearch.inputKey), findsNothing);
      expect(find.text('Filter'), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-panel-tabs')), findsNothing);
      await tester.tap(find.byKey(UserMenuButton.bellKey));
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('forum-identity-button')));
      await tester.pumpAndSettle();
      expect(find.text('Open forum in browser'), findsOneWidget);
      expect(find.text('Remove forum'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(_bar, findsNothing);
      final route = ModalRoute.of(
        tester.element(find.byKey(ForumSearch.inputKey)),
      )!;
      expect(route, isA<PageRoute<void>>());
      expect(route.settings.name, '/search');
      expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
      expect(route.opaque, isTrue);
      final fullHeight = tester
          .getSize(find.byKey(ForumSearch.panelKey))
          .height;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(ForumSearch.panelKey)).height,
        lessThan(fullHeight),
      );
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'test');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('mobile-search-back')));
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(_bar, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.inputKey), findsNothing);
      expect(_bar, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'topic cards and users fill the screen; back and forward return to home',
    (tester) async {
      final shell = await _pumpMobile(tester);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();
      _expectPage();
      expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
      expect(tester.getSize(find.byType(MainContent)).width, phone.width);
      await tester.tap(find.byKey(const ValueKey('topic-card-7')));
      await tester.pumpAndSettle();
      _expectPage();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(_bar, findsOneWidget);
      expect(shell.handleForward(), isTrue);
      await tester.pumpAndSettle();
      _expectPage();
      shell.handleBack();
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Users'));
      await tester.pumpAndSettle();
      _expectPage();
      expect(find.byType(UsersPage), findsOneWidget);
      expect(find.byType(DSheetContent), findsNothing);
      expect(shell.canForwardContent, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('chat uses Channels and DMs and restores the chosen subtab', (
    tester,
  ) async {
    final shell = await _pumpMobile(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-chat')));
    await tester.pumpAndSettle();
    expect(find.byType(InstanceRail), findsNothing);
    expect(find.byType(ChatDrawerChannelsView), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    await tester.tap(find.text('DMs'));
    await tester.pumpAndSettle();
    expect(find.text('sam'), findsWidgets);
    await tester.tap(find.text('sam').first);
    await tester.pumpAndSettle();
    _expectPage();
    expect(shell.currentContent?.id, contains('10'));
    shell.pushContent(
      ContentRoute.topic(
        topicId: 7,
        slug: 'shared',
        title: 'Shared topic card',
      ),
    );
    await tester.pumpAndSettle();
    _expectPage();
    expect(shell.handleBack(), isTrue);
    await tester.pumpAndSettle();
    _expectPage();
    expect(shell.currentContent?.id, contains('10'));
    shell.handleBack();
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
    expect(
      tester
          .widget<ChatDrawerChannelsView>(find.byType(ChatDrawerChannelsView))
          .kind,
      ChatDrawerChannelListKind.directMessages,
    );
    expect(tester.takeException(), isNull);
  });

  _mobileTest('Start chatting opens a full page and returns to DMs', (
    tester,
  ) async {
    final shell = await _pumpMobile(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DMs'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('chat-drawer-new-message-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start chatting'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('chat-new-direct-message-channel-10')),
    );
    await tester.pumpAndSettle();
    _expectPage();
    expect(shell.currentContent?.id, contains('10'));
    expect(find.text('Start chatting'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
    expect(
      tester
          .widget<ChatDrawerChannelsView>(find.byType(ChatDrawerChannelsView))
          .kind,
      ChatDrawerChannelListKind.directMessages,
    );
    expect(tester.takeException(), isNull);
  });

  _mobileTest('list filters replace the page and system Back returns home', (
    tester,
  ) async {
    final shell = await _pumpMobile(tester);
    await tester.tap(sidebarDestination('Topics'));
    await tester.pumpAndSettle();
    await shell.selectTopicListMode(TopicListMode.unread);
    await tester.pumpAndSettle();
    _expectPage();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
    expect(shell.handleForward(), isTrue);
    await tester.pumpAndSettle();
    expect(shell.currentTopicListMode, TopicListMode.unread);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('edge swipes navigate, body and vertical swipes do not', (
    tester,
  ) async {
    final shell = await _pumpMobile(tester);
    await tester.tap(sidebarDestination('Users'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(190, 400), const Offset(120, 0));
    await tester.pumpAndSettle();
    _expectPage();
    await tester.dragFrom(const Offset(5, 400), const Offset(80, 120));
    await tester.pumpAndSettle();
    _expectPage();
    await tester.dragFrom(const Offset(5, 400), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
    await tester.dragFrom(const Offset(385, 400), const Offset(-120, 0));
    await tester.pumpAndSettle();
    _expectPage();
    expect(shell.currentContent?.id, 'users');
    expect(tester.takeException(), isNull);
  });

  _mobileTest('tablet retains mobile navigation with no desktop tab strip', (
    tester,
  ) async {
    await _pumpMobile(tester, size: const Size(1024, 768));
    expect(_bar, findsOneWidget);
    expect(find.byType(ShellTitleBar), findsNothing);
    await tester.tap(sidebarDestination('Topics'));
    await tester.pumpAndSettle();
    _expectPage();
    expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  _mobileTest('narrow large text keeps settings and keyboard search usable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final shell = await _pumpMobile(tester, size: const Size(320, 720));
    await tester.tap(find.byKey(UserMenuButton.bellKey));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.atRoot, isTrue);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DMs'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-drawer-new-message-action')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mobile-forum-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('forum-settings-close')));
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.panelOwner, 'chat');
    await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('mobile-search-back')));
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
  });
}
