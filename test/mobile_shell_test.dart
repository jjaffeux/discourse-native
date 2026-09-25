import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/badge_fixtures.dart';
import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 7,
  username: 'reader',
  hidePresence: false,
  canCreateTopic: true,
  canSendPrivateMessages: true,
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);
final _bar = find.byKey(const ValueKey('mobile-bottom-bar'));
final _header = find.byKey(const ValueKey('mobile-header'));

Future<ShellController> pumpMobileShellFixture(
  WidgetTester tester, {
  Size size = phone,
  bool voice = false,
  bool events = false,
  bool chat = true,
  int chatUnreadCount = 0,
  TopicPayload? topic,
  ChatChannels? conversations,
}) async {
  final config = SiteConfig(
    userStatusEnabled: true,
    plugins: PluginData.none
        .withValue(
          chatSettingsDataKey,
          ChatSettings(
            chatEnabled: chat,
            publicChannelsEnabled: true,
            threadsEnabled: true,
          ),
        )
        .withValue(voiceSettingsDataKey, VoiceClientConfig(enabled: voice))
        .withValue(eventSettingsKey, EventSettings(enabled: events)),
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
      doNotDisturbUntil: DateTime.now().add(const Duration(minutes: 30)),
      customSidebarSectionsBySite: const {
        _site: [
          SidebarSection(
            id: 'custom-1',
            title: 'Team links',
            destinations: [
              SidebarDestination(
                id: 'custom-1-link',
                label: 'Handbook',
                icon: DIcons.link,
                url: '/t/shared/7',
              ),
            ],
          ),
        ],
      },
      totals: chatNotificationTotals(available: true),
      siteConfigs: {_site: config},
      pluginResponses: {
        'GET /badges.json?only_listable=true': badgeCatalogWire,
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
      topics: {7: topic ?? topicPayload(id: 7, title: 'Shared topic card')},
      composerCapabilities: const TopicComposerCapabilities(canTagTopics: true),
      topicTagSearches: const {
        '': TopicTagSearch(tags: [TopicTag(id: 1, name: 'show-and-tell')]),
      },
      chatMessagesByKey: {
        FakeDiscourseApi.chatMessagesKey(10): (
          messages: const [],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
      chatChannelsBySite: {
        _site:
            conversations ??
            ChatChannels(
              hasThreads: true,
              public: [
                ChatChannel(
                  id: 9,
                  title: 'General',
                  kind: ChatChannelKind.category,
                  membership: const ChatMembership(following: true),
                  tracking: ChatTracking(unreadCount: chatUnreadCount),
                ),
              ],
              direct: const [
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

void _expectPage({bool focusedChat = false}) {
  expect(_bar, focusedChat ? findsNothing : findsOneWidget);
  expect(_header, findsOneWidget);
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

Future<void> _selectChatKind(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('chat-inbox-kind-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _selectChatActivity(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('chat-inbox-activity-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  _mobileTest('Voice keeps the redesigned Chat inbox and its filters', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, voice: true, chatUnreadCount: 4);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatMobileSidebar), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-presence-menu')), findsOneWidget);
    // Check painted geometry separately from the invisible touch targets.
    // A missing size on either custom trigger used to inflate it to 44px.
    for (final (key, height) in [
      ('chat-inbox-activity-filter', 30.75),
      ('chat-inbox-kind-filter', 30.75),
      ('user-presence-menu', 24.0),
    ]) {
      final control = find.byKey(ValueKey(key));
      final surface = find.descendant(
        of: control,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AnimatedContainer &&
              widget.decoration is DButtonDecoration,
        ),
      );
      expect(tester.getSize(surface).height, height, reason: key);
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
    }
    expect(find.text('Starred channels'), findsNothing);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('sam'), findsOneWidget);

    await _selectChatActivity(tester, 'Unread');
    expect(find.text('General'), findsOneWidget);
    expect(find.text('sam'), findsNothing);
    await _selectChatKind(tester, 'Direct messages');
    expect(find.text('No unread conversations.'), findsOneWidget);
    await _selectChatActivity(tester, 'Recent');
    expect(find.text('sam'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('the Chat tab offers Start a message in the tab bar', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester);
    final action = find.byKey(const ValueKey('mobile-panel-action'));
    expect(action, findsNothing);

    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-bottom-bar')),
        matching: action,
      ),
      findsOneWidget,
    );

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-new-direct-message-dialog')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  _mobileTest('chat filters the mixed recent list and live unread state', (
    tester,
  ) async {
    final now = DateTime.now();
    ChatChannel channel(
      int id,
      String title,
      int minutes, {
      bool dm = false,
      int unread = 0,
      bool starred = false,
      bool muted = false,
    }) => ChatChannel(
      id: id,
      title: title,
      kind: dm ? ChatChannelKind.directMessage : ChatChannelKind.category,
      membership: ChatMembership(
        following: true,
        starred: starred,
        muted: muted,
      ),
      tracking: ChatTracking(unreadCount: unread),
      lastMessageId: id * 10,
      lastMessageAt: now.subtract(Duration(minutes: minutes)),
      lastMessageUserId: dm ? 4 : 7,
      lastMessagePreview: 'Will follow up in the morning.',
    );
    await pumpMobileShellFixture(
      tester,
      conversations: ChatChannels(
        public: [
          channel(1, 'general', 8),
          channel(2, 'baking', 3, unread: 4, starred: true),
          channel(3, 'muted', 6, unread: 9, muted: true),
        ],
        direct: [
          channel(4, 'flourpower', 1, dm: true, unread: 3),
          channel(5, 'verdant_vera', 4, dm: true, starred: true),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    Finder row(int id) => find.byKey(ValueKey('chat-inbox-channel-$id'));
    final positions = [
      4,
      2,
      5,
      3,
      1,
    ].map((id) => tester.getTopLeft(row(id)).dy).toList();
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.text('4 new messages'), findsOneWidget);
    expect(find.text('3 new messages'), findsOneWidget);
    expect(find.text('9 new messages'), findsNothing);
    expect(find.text('you: Will follow up in the morning.'), findsNWidgets(2));
    await _selectChatActivity(tester, 'Unread');
    expect(row(2), findsOneWidget);
    expect(row(4), findsOneWidget);
    for (final id in [1, 3, 5]) {
      expect(row(id), findsNothing);
    }
    await _selectChatKind(tester, 'Channels');
    expect(row(2), findsOneWidget);
    expect(row(4), findsNothing);
    await _selectChatKind(tester, 'Direct messages');
    expect(row(2), findsNothing);
    expect(row(4), findsOneWidget);
    FakeSiteTracker.built
        .singleWhere((tracker) => tracker.siteUrl == _site)
        .deliverPluginMessage('/chat/user-tracking-state/7', {
          'channel_id': 4,
          'last_read_message_id': 40,
          'unread_count': 0,
          'mention_count': 0,
          'watched_threads_unread_count': 0,
        });
    await tester.pumpAndSettle();
    expect(row(4), findsNothing);
    expect(find.text('No unread conversations.'), findsOneWidget);
    await _selectChatActivity(tester, 'Recent');
    expect(row(4), findsOneWidget);
    expect(row(5), findsOneWidget);
    await _selectChatKind(tester, 'All');
    for (final id in [1, 2, 3, 4, 5]) {
      expect(row(id), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'chat status menu edits status, toggles presence and pauses notifications',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('user-presence-menu'));
      expect(
        tester.widget<DButton>(trigger).density,
        DButtonDensity.compactToolbar,
      );
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.text('Set a custom status'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Pause notifications'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();
      expect(shell.hidePresenceFor(_site), isTrue);
      expect(find.text('Offline'), findsOneWidget);
      await tester.tap(find.text('Offline'));
      await tester.pumpAndSettle();
      expect(shell.hidePresenceFor(_site), isFalse);
      await tester.tap(find.text('Pause notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Pause notifications for…'), findsOneWidget);
      await tester.tap(find.text('30 minutes'));
      await tester.pumpAndSettle();
      expect(
        shell.doNotDisturb.stateFor(_site).isActiveAt(DateTime.now()),
        isTrue,
      );
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause notifications'));
      await tester.pumpAndSettle();
      expect(
        shell.doNotDisturb.stateFor(_site).isActiveAt(DateTime.now()),
        isFalse,
      );
      await tester.tap(find.text('Set a custom status'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'In the garden');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(shell.currentInstance?.user?.status?.description, 'In the garden');
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('user-menu-row-user-status')),
          matching: find.text('In the garden'),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('chat filters fit a narrow phone and enlarged text', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, size: const Size(320, 740));
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    await _selectChatKind(tester, 'Channels');
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await _selectChatActivity(tester, 'Unread');
    expect(find.text('No unread conversations.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('topics startup keeps chat mounted but inactive until selected', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final chatPanel = find.byWidgetPredicate(
      (widget) => widget is InstanceSidebar && widget.panelOwner == 'chat',
      skipOffstage: false,
    );
    void expectChatActive(bool active) {
      expect(chatPanel, findsOneWidget);
      final offstage = tester.widget<Offstage>(
        find
            .ancestor(
              of: chatPanel,
              matching: find.byType(Offstage, skipOffstage: false),
            )
            .first,
      );
      expect(offstage.offstage, !active);
      expect(tester.takeException(), isNull);
    }

    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expectChatActive(false);
    final initialPanel = tester.element(chatPanel);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    expectChatActive(true);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
    await tester.pumpAndSettle();
    expectChatActive(false);
    expect(tester.element(chatPanel), same(initialPanel));
    expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
  });

  _mobileTest(
    'persistent header and independent buttons surround the content',
    (tester) async {
      await pumpMobileShellFixture(tester, size: phone, events: true);
      final panel = find.byKey(const ValueKey('mobile-content-panel'));
      expect(
        tester.getRect(_header).bottom,
        lessThanOrEqualTo(tester.getRect(panel).top),
      );
      expect(find.descendant(of: panel, matching: _header), findsNothing);
      expect(find.byType(InstanceRail), findsNothing);
      expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
      double right = -1;
      for (final tab in [
        'topics',
        'panel/chat',
        'messages',
        'users',
        'destination/events-upcoming',
        'more',
      ]) {
        final button = find.byKey(ValueKey('mobile-mode-$tab'));
        final rect = tester.getRect(button);
        expect(rect.left, greaterThan(right));
        expect(rect.right, lessThanOrEqualTo(phone.width));
        right = rect.right;
        expect(
          tester.widget<DButton>(button).density,
          DButtonDensity.mobileNavigation,
        );
        final icon = find.descendant(of: button, matching: find.byType(DIcon));
        expect(tester.getSize(icon), const Size(18, 18));
        final glyph = find.descendant(
          of: icon,
          matching: find.byType(SvgPicture),
        );
        expect(tester.getSize(glyph).longestSide, 18);
      }
      expect(
        find.descendant(of: _bar, matching: find.byType(DTabList<String>)),
        findsNothing,
      );
      for (final key in [
        UserMenuButton.bellKey,
        UserMenuButton.avatarKey,
        const ValueKey('forum-identity-button'),
        const ValueKey('mobile-search-button'),
      ]) {
        expect(
          find.descendant(of: _header, matching: find.byKey(key)),
          findsOneWidget,
        );
      }
      final menu = tester.getRect(
        find.byKey(const ValueKey('mobile-menu-button')),
      );
      final identity = tester.getRect(
        find.byKey(const ValueKey('forum-identity-button')),
      );
      final search = tester.getRect(
        find.byKey(const ValueKey('mobile-search-button')),
      );
      final bell = tester.getRect(find.byKey(UserMenuButton.bellKey));
      final avatar = tester.getRect(find.byKey(UserMenuButton.avatarKey));
      expect(identity.left - menu.right, DSpacing.controlGap);
      expect(bell.left - search.right, DSpacing.controlGap);
      expect(avatar.left - bell.right, DSpacing.controlGap);
      final menuIcon = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile-menu-button')),
          matching: find.byIcon(Icons.menu),
        ),
      );
      expect(menuIcon.center.dx, menu.center.dx);
      expect(
        tester
            .widget<DButton>(
              find.byKey(const ValueKey('forum-identity-button')),
            )
            .size,
        DButtonSize.regular,
      );
      expect(
        tester.widget<DButton>(find.byKey(UserMenuButton.avatarKey)).size,
        DButtonSize.regular,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'tab unread counts sit at the bottom center and pass taps through',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester, chatUnreadCount: 32);
      final button = find.byKey(const ValueKey('mobile-mode-panel/chat'));
      final badge = find.byKey(const ValueKey('chat-sidebar-unread-badge'));
      void expectPosition() {
        final buttonRect = tester.getRect(button);
        final badgeRect = tester.getRect(badge);
        expect(badgeRect.center.dx, buttonRect.center.dx);
        expect(badgeRect.bottom, buttonRect.bottom - DSpacing.xxs);
      }

      expectPosition();
      expect(find.text('32'), findsOneWidget);
      await tester.tapAt(tester.getCenter(badge));
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.tab, const MobileTab.panel('chat'));
      expectPosition();
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'tab buttons visibly morph throughout selection and deselection',
    (tester) async {
      await pumpMobileShellFixture(tester);
      final button = find.byKey(const ValueKey('mobile-mode-panel/chat'));
      final surface = find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AnimatedContainer &&
              widget.decoration is DButtonDecoration,
        ),
      );
      final painted = find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && widget.decoration is DButtonDecoration,
        ),
      );
      double radius() =>
          (tester.widget<DecoratedBox>(painted).decoration as DButtonDecoration)
              .borderRadius
              .topLeft
              .x;

      final circleRadius = radius();
      expect(circleRadius, 22);
      expect(
        tester.widget<AnimatedContainer>(surface).duration,
        const Duration(milliseconds: 240),
      );

      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final earlyRadius = radius();
      expect(earlyRadius, inExclusiveRange(14, 22));
      await tester.pump(const Duration(milliseconds: 60));
      final halfwayRadius = radius();
      expect(halfwayRadius, lessThan(earlyRadius));
      await tester.pumpAndSettle();
      final selectedRadius = radius();

      expect(selectedRadius, lessThan(halfwayRadius));
      expect(halfwayRadius, lessThan(circleRadius));
      expect(selectedRadius, 14);

      await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(radius(), inExclusiveRange(14, 22));
      await tester.pumpAndSettle();
      expect(radius(), 22);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'navigation page exposes Forum categories/tags and custom Shortcuts',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
      await tester.pumpAndSettle();
      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(DSheetContent), findsNothing);
      expect(_bar, findsNothing);
      expect(_header, findsOneWidget);
      expect(find.byKey(const ValueKey('mobile-content-panel')), findsNothing);
      expect(find.text('Forum'), findsOneWidget);
      expect(find.text('Shortcuts'), findsOneWidget);
      for (final label in ['Topics', 'Messages', 'Users', 'Handbook']) {
        expect(sidebarDestination(label), findsNothing);
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile-navigation-page')),
          matching: find.text('Categories'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Shortcuts'));
      await tester.pumpAndSettle();
      expect(sidebarDestination('Handbook'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile-navigation-page')),
          matching: find.text('Categories'),
        ),
        findsNothing,
      );
      await tester.tap(sidebarDestination('Handbook'));
      await tester.pumpAndSettle();
      expect(find.byType(InstanceRail), findsNothing);
      expect(shell.currentContent?.topicId, 7);
      expect(_bar, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('navigation pushes the content and restores the same page', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final menu = find.byKey(const ValueKey('mobile-menu-button'));
    final page = find.byType(MainContent, skipOffstage: false);
    final originalPage = tester.element(page);
    final visit = shell.mobileNavigation.entryId;
    final header = tester.getRect(_header);
    final content = tester.getRect(
      find.byKey(const ValueKey('mobile-content-panel')),
    );

    for (final open in [true, false]) {
      await tester.tap(menu);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final incoming = tester.widget<Transform>(
        find.byKey(const ValueKey('history-incoming-tab')),
      );
      final outgoing = tester.widget<Transform>(
        find.byKey(const ValueKey('history-outgoing-tab')),
      );
      final direction = open ? -1 : 1;
      expect(incoming.transform.getTranslation().x * direction, greaterThan(0));
      expect(outgoing.transform.getTranslation().x * direction, lessThan(0));
      expect(tester.getRect(_header), header);
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.entryId, same(visit));
      expect(tester.element(page), same(originalPage));
      expect(shell.mobileNavigation.sidebarOpen, open);
      expect(_bar, open ? findsNothing : findsOneWidget);
      expect(find.byType(MainContent), open ? findsNothing : findsOneWidget);
      if (open) {
        final navigation = tester.getRect(
          find.byKey(const ValueKey('mobile-navigation-page')),
        );
        expect(navigation.left, content.left);
        expect(navigation.right, content.right);
        expect(navigation.top, content.top);
        expect(navigation.bottom, greaterThan(content.bottom));
      }
    }
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(shell.mobileNavigation.entryId, same(visit));
    expect(tester.element(page), same(originalPage));
    expect(tester.takeException(), isNull);
  });

  _mobileTest('system Back closes navigation before leaving the topic', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    final visit = shell.mobileNavigation.entryId;
    expect(shell.currentContent?.topicId, 7);
    expect(shell.canPopContent, isTrue);
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(shell.mobileNavigation.entryId, same(visit));
    expect(shell.currentContent?.topicId, 7);
    expect(_bar, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 600.0]) {
    _mobileTest('navigation uses the full $width viewport with large text', (
      tester,
    ) async {
      await pumpMobileShellFixture(tester, size: Size(width, 844));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
      await tester.pumpAndSettle();
      final navigation = tester.getRect(
        find.byKey(const ValueKey('mobile-navigation-page')),
      );
      expect(navigation.width, width - 2 * DSpacing.xs);
      expect(_bar, findsNothing);
      expect(find.text('Shortcuts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  _mobileTest('Forum destinations return from Chat to the Topics tab', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(sidebarDestination('All categories'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'all-categories');
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(shell.canPopContent, isFalse);
    expect(find.byType(InstanceRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('contextual actions follow the active tab and open composers', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final topic = find.byKey(const ValueKey('mobile-new-topic'));
    expect(topic, findsOneWidget);
    expect(tester.getRect(topic).right, tester.getRect(_bar).right);
    expect(tester.getCenter(topic).dy, tester.getCenter(_bar).dy);
    expect(
      find.descendant(of: topic, matching: find.text('New topic')),
      findsNothing,
    );
    await tester.tap(topic);
    await tester.pumpAndSettle();
    expect(shell.visibleComposer, isNotNull);
    shell.closeComposer();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    expect(topic, findsNothing);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-messages')));
    await tester.pumpAndSettle();
    final message = find.byKey(const ValueKey('new-message-button'));
    expect(message, findsOneWidget);
    await tester.tap(message);
    await tester.pumpAndSettle();
    expect(shell.visibleComposer, isNotNull);
    expect(shell.visibleComposer!.target.isPrivateMessage, isTrue);
    expect(shell.visibleComposer!.target.targetRecipients, '');
    expect(tester.takeException(), isNull);
  });

  _mobileTest('creation labels collapse while every action stays on one row', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, events: true);
    for (final tab in ['topics', 'messages']) {
      await tester.tap(find.byKey(ValueKey('mobile-mode-$tab')));
      await tester.pumpAndSettle();
      final action = find.byKey(
        ValueKey(tab == 'topics' ? 'mobile-new-topic' : 'new-message-button'),
      );
      for (final width in [600.0, 390.0, 320.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        expect(tester.widget<DButton>(action).label is! Text, width < 600);
        expect(tester.getCenter(action).dy, tester.getCenter(_bar).dy);
        expect(tester.getRect(action).right, tester.getRect(_bar).right);
        expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
        for (final name in [
          'topics',
          'panel/chat',
          'messages',
          'users',
          'destination/events-upcoming',
          'more',
        ]) {
          final button = find.byKey(ValueKey('mobile-mode-$name'));
          expect(tester.getCenter(button).dy, tester.getCenter(action).dy);
        }
        expect(tester.takeException(), isNull);
      }
      // At narrow widths the tab row scrolls while creation stays pinned right.
      final more = find.byKey(const ValueKey('mobile-mode-more'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      expect(tester.getRect(more).right, lessThan(tester.getRect(action).left));
      tester.view.physicalSize = phone;
      await tester.pumpAndSettle();
    }
  });

  _mobileTest('More opens groups, badges and bookmarks using shared pages', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    for (final (label, id) in [
      ('Groups', 'groups'),
      ('Badges', 'badges'),
      ('Bookmarks', 'user-bookmarks'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('mobile-mode-more')));
      await tester.pumpAndSettle();
      for (final item in ['Groups', 'Badges', 'Bookmarks']) {
        expect(
          find.descendant(
            of: find.byType(DDropdownMenuItem),
            matching: find.text(item),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.descendant(
          of: find.byType(DDropdownMenuItem),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, id);
      expect(shell.mobileNavigation.tab, MobileTab.more);
      expect(
        find.descendant(
          of: find.byType(MainContent),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
      _expectPage();
    }
    expect(find.byType(BookmarkSection), findsOneWidget);
    expect(shell.bookmarksFor(_site).loaded, isTrue);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('users and events keep their own page headings', (tester) async {
    await pumpMobileShellFixture(tester, events: true);
    for (final (tab, heading, duplicate) in [
      ('users', 'Users', 'Users'),
      ('destination/events-upcoming', 'Events', 'Upcoming events'),
    ]) {
      final button = find.byKey(ValueKey('mobile-mode-$tab'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(MainContent),
          matching: find.text(heading),
        ),
        findsOneWidget,
      );
      if (duplicate != heading) {
        expect(
          find.descendant(
            of: find.byType(MainContent),
            matching: find.text(duplicate),
          ),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  _mobileTest('unavailable optional plugins have no navigation button', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, chat: false);
    expect(find.byKey(const ValueKey('mobile-mode-panel/chat')), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile-mode-destination/events-upcoming')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mobile-mode-topics')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('site changes clear unavailable tabs and private actions', (
    tester,
  ) async {
    final config = SiteConfig(
      plugins: PluginData.none
          .withValue(chatSettingsDataKey, const ChatSettings(chatEnabled: true))
          .withValue(eventSettingsKey, const EventSettings(enabled: true)),
    );
    final anonymousConfig = SiteConfig(
      userDirectoryEnabled: false,
      plugins: PluginData.none.withValue(
        chatSettingsDataKey,
        const ChatSettings(chatEnabled: false),
      ),
    );
    await pumpShell(
      tester,
      phone,
      instances: [
        instance('meta.discourse.org').copyWith(user: _user, config: config),
        instance('public.example').copyWith(config: anonymousConfig),
      ],
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      api: FakeDiscourseApi(
        user: _user,
        totals: chatNotificationTotals(available: true),
        siteConfigs: {_site: config, 'https://public.example': anonymousConfig},
      ),
    );
    final shell = ShellScope.read(tester.element(find.byType(MobileForumRoot)));
    await tester.tap(
      find.byKey(const ValueKey('mobile-mode-destination/events-upcoming')),
    );
    await tester.pumpAndSettle();
    expect(
      shell.mobileNavigation.tab,
      const MobileTab.destination('events-upcoming'),
    );
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    shell.selectInstance(1);
    await tester.pump();
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(find.byKey(const ValueKey('mobile-navigation-page')), findsNothing);
    expect(find.byKey(const ValueKey('history-outgoing-tab')), findsNothing);
    await tester.pumpAndSettle();
    for (final tab in [
      'panel/chat',
      'messages',
      'users',
      'destination/events-upcoming',
    ]) {
      expect(find.byKey(ValueKey('mobile-mode-$tab')), findsNothing);
    }
    expect(find.byKey(const ValueKey('mobile-new-topic')), findsNothing);
    expect(find.byKey(const ValueKey('new-message-button')), findsNothing);
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(shell.canPopContent, isFalse);
    expect(shell.canForwardContent, isFalse);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('server capabilities do not expose plugins absent from the app', (
    tester,
  ) async {
    final config = SiteConfig(
      plugins: PluginData.none
          .withValue(chatSettingsDataKey, const ChatSettings(chatEnabled: true))
          .withValue(eventSettingsKey, const EventSettings(enabled: true)),
    );
    await pumpShell(
      tester,
      phone,
      pluginManifest: const PluginManifest([]),
      instances: [
        instance('meta.discourse.org').copyWith(user: _user, config: config),
      ],
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      api: FakeDiscourseApi(
        user: _user,
        totals: chatNotificationTotals(available: true),
        siteConfigs: {_site: config},
      ),
    );
    expect(find.byKey(const ValueKey('mobile-mode-panel/chat')), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile-mode-destination/events-upcoming')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'tab movement carries the panel in visual order and keeps chrome still',
    (tester) async {
      await pumpMobileShellFixture(tester, events: true);
      final header = tester.getRect(_header);
      final bar = tester.getRect(_bar);
      final panel = find.byKey(const ValueKey('mobile-content-panel'));
      for (final (from, to, direction) in [
        ('messages', 'panel/chat', -1),
        ('messages', 'users', 1),
        ('destination/events-upcoming', 'topics', -1),
      ]) {
        await tester.tap(find.byKey(ValueKey('mobile-mode-$from')));
        await tester.pumpAndSettle();
        final restingPanel = tester.getRect(panel);
        await tester.tap(find.byKey(ValueKey('mobile-mode-$to')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final incoming = tester.widget<Transform>(
          find.byKey(const ValueKey('history-incoming-tab')),
        );
        final outgoing = tester.widget<Transform>(
          find.byKey(const ValueKey('history-outgoing-tab')),
        );
        expect(
          incoming.transform.getTranslation().x * direction,
          greaterThan(0),
        );
        expect(outgoing.transform.getTranslation().x * direction, lessThan(0));
        expect(
          (tester.getRect(panel).left - restingPanel.left) * direction,
          greaterThan(0),
        );
        expect(tester.getRect(_header), header);
        expect(tester.getRect(_bar), bar);
        expect(
          find.byType(MainContent).evaluate().length,
          lessThanOrEqualTo(1),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(panel), restingPanel);
        expect(
          find.byKey(const ValueKey('history-incoming-tab')),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'voice rooms remain in navigation without replacing the Chat inbox',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester, voice: true);
      final voice = shell.pluginSession.require(voiceControllerService);
      expect(find.byKey(const ValueKey('mobile-mode-voice')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      expect(find.text('Watercooler'), findsNothing);
      expect(find.byType(InstanceRail), findsNothing);
      expect(voice.call, isNull);
      await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
      await tester.pumpAndSettle();
      expect(find.text('Voice rooms'), findsOneWidget);
      expect(find.text('Watercooler'), findsOneWidget);
      expect(find.text('Starred channels'), findsNothing);
      voice.forget(_site);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mobile-mode-voice')), findsNothing);
      expect(find.text('Voice rooms'), findsNothing);
      expect(find.text('Watercooler'), findsNothing);
      await tester.tap(find.byTooltip('Close navigation'));
      await tester.pumpAndSettle();
      expect(find.byType(InstanceRail), findsNothing);
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      expect(shell.mobileNavigation.panelOwner, 'chat');
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'header retains bell and logo actions; search is a dedicated page',
    (tester) async {
      await pumpMobileShellFixture(tester);
      expect(_bar, findsOneWidget);
      expect(_header, findsOneWidget);
      expect(find.byType(InstanceRail), findsNothing);
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

  _mobileTest('leaving home removes a forum menu that is still fading out', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(const ValueKey('forum-identity-button')));
    await tester.pumpAndSettle();
    expect(find.text('Open forum in browser'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    shell.pushContent(
      ContentRoute.topic(
        topicId: 7,
        slug: 'shared',
        title: 'Shared topic card',
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    _expectPage();
    expect(
      find.text('Open forum in browser', skipOffstage: false),
      findsNothing,
    );
    expect(find.text('Remove forum', skipOffstage: false), findsNothing);

    shell.handleBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('forum-identity-button')));
    await tester.pumpAndSettle();
    expect(find.text('Open forum in browser'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'topics have their own history and switching tabs starts a fresh journey',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      expect(shell.canPopContent, isFalse);
      await tester.tap(find.byKey(const ValueKey('topic-card-7')));
      await tester.pumpAndSettle();
      _expectPage();
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
      expect(shell.canPopContent, isFalse);
      expect(shell.handleForward(), isTrue);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 7);
      await tester.tap(find.byKey(const ValueKey('mobile-mode-users')));
      await tester.pumpAndSettle();
      expect(find.byType(UsersPage), findsOneWidget);
      expect(shell.canPopContent, isFalse);
      expect(shell.canForwardContent, isFalse);
      _expectPage();
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('chat focus collapses tabs and blur restores them', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    await _selectChatKind(tester, 'Direct messages');
    await tester.tap(find.text('sam').first);
    await tester.pumpAndSettle();
    final composer = tester
        .widget<ComposerEditor>(find.byType(ComposerEditor))
        .composer;
    composer.focus.unfocus();
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
    final panel = find.byKey(const ValueKey('mobile-content-panel'));
    final initialHeight = tester.getSize(panel).height;
    composer.focus.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getSize(panel).height, greaterThan(initialHeight));
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
    expect(composer.focus.hasFocus, isTrue);
    composer.focus.unfocus();
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
    expect(tester.getSize(panel).height, initialHeight);
    composer.focus.requestFocus();
    await tester.pumpAndSettle();
    shell.handleBack();
    await tester.pumpAndSettle();
    expect(_bar, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'chat mixes conversations and restores the selected type filter',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
      await tester.pumpAndSettle();
      expect(find.byType(InstanceRail), findsNothing);
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      expect(find.text('sam'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      await _selectChatKind(tester, 'Direct messages');
      expect(find.text('sam'), findsWidgets);
      await tester.tap(find.text('sam').first);
      await tester.pumpAndSettle();
      _expectPage(focusedChat: true);
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
      _expectPage(focusedChat: true);
      expect(shell.currentContent?.id, contains('10'));
      shell.handleBack();
      await tester.pumpAndSettle();
      expect(_bar, findsOneWidget);
      expect(find.text('DMs'), findsOneWidget);
      expect(find.text('General'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('chat retains Browse channels and My threads navigation', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    expect(find.text('Browse channels'), findsOneWidget);
    expect(find.text('My threads'), findsOneWidget);
    await tester.tap(find.text('Browse channels'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-browse');
    shell.handleBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('My threads'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-my-threads');
    shell.handleBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatMobileSidebar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('filters replace the tab root without adding Back steps', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    await shell.selectTopicListMode(TopicListMode.unread);
    await tester.pumpAndSettle();
    expect(shell.currentTopicListMode, TopicListMode.unread);
    expect(shell.canPopContent, isFalse);
    expect(shell.canForwardContent, isFalse);
    _expectPage();
    expect(tester.takeException(), isNull);
  });

  _mobileTest('edge history gestures move content while chrome remains fixed', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    shell.pushContent(
      const ContentRoute(id: 'users', title: 'Users', icon: DIcons.user),
    );
    await tester.pumpAndSettle();
    final header = tester.getRect(_header);
    final bar = tester.getRect(_bar);
    final origin = tester.getTopLeft(find.byType(UsersPage));
    final back = await tester.startGesture(const Offset(8, 400));
    await back.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byType(UsersPage)).dx - origin.dx, 120);
    expect(tester.getRect(_header), header);
    expect(tester.getRect(_bar), bar);
    await back.up();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(shell.handleForward(), isTrue);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'users');
    expect(tester.takeException(), isNull);
  });

  _mobileTest('tablet retains mobile navigation with no desktop tab strip', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, size: const Size(1024, 768));
    expect(_bar, findsOneWidget);
    expect(find.byType(ShellTitleBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
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
    final shell = await pumpMobileShellFixture(
      tester,
      size: const Size(320, 720),
    );
    await tester.tap(find.byKey(UserMenuButton.bellKey));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(shell.canPopContent, isFalse);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    await _selectChatKind(tester, 'Direct messages');
    expect(find.byKey(const ValueKey('chat-inbox-browse')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-forum-settings')), findsNothing);
    expect(find.byKey(const ValueKey('mobile-new-topic')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('forum-identity-header')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('forum-identity-settings')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('forum-identity-header')));
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
