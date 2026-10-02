import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/category_notifications.dart';
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
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/d_icon_glyph.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Future<void> _tapDockTab(
  WidgetTester tester,
  String tab, {
  bool settle = true,
}) async {
  final button = find.byKey(ValueKey('mobile-mode-$tab'));
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button);
  } else {
    final label = switch (tab) {
      'panel/chat' => 'Chat',
      'messages' => 'Messages',
      'users' => 'Users',
      'destination/events-upcoming' => 'Events',
      _ => throw StateError('No dock menu label for $tab'),
    };
    await tester.tap(find.byKey(const ValueKey('mobile-mode-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DDropdownMenuItem),
        matching: find.text(label),
      ),
    );
  }
  if (settle) await tester.pumpAndSettle();
}

Future<ShellController> pumpMobileShellFixture(
  WidgetTester tester, {
  Size size = phone,
  bool voice = false,
  bool events = false,
  bool chat = true,
  int chatUnreadCount = 0,
  TopicPayload? topic,
  PluginManifest? pluginManifest,
  ChatChannels? conversations,
  List<Topic>? topics,
  List<ChatMessage>? chatMessages,
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
    pluginManifest:
        pluginManifest ??
        PluginManifest([
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
      feeds: {
        '/latest.json':
            topics ??
            const [Topic(id: 7, title: 'Shared topic card', slug: 'shared')],
        '/new.json': const [
          Topic(id: 7, title: 'Shared topic card', slug: 'shared'),
        ],
        '/c/support/42.json': const [
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
          messages: chatMessages ?? const [],
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

void _expectPage() {
  expect(_bar, findsOneWidget);
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

const _teamUrl = 'https://team.discourse.org';
final _persistedTopic = ContentRoute.topic(
  topicId: 42,
  slug: 'persisted',
  title: 'Persisted topic',
);

/// A mobile shell on the first of [twoSites], with a persisted workspace for
/// the second one that shows a topic above a non-default feed.
Future<
  ({
    ShellController shell,
    FakeDiscourseApi api,
    _RecordingSiteActivator activator,
  })
>
_forumSwitchFixture() async {
  final api = FakeDiscourseApi(
    feeds: const {'/latest.json': [], '/hot.json': []},
    topics: {42: topicPayload(id: 42, title: 'Persisted topic')},
  );
  final activator = _RecordingSiteActivator();
  final plugins = PluginInstaller.install(
    PluginManifest([_SiteActivationModule(activator)]),
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore(twoSites),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore([
      ForumWorkspace(
        siteUrl: _teamUrl,
        accountIdentity: 'anonymous',
        activeTabId: 'persisted',
        tabs: [
          ForumTab(
            id: 'persisted',
            rootDestinationId: 'hot',
            contentStack: [
              ContentRoute.topicList(TopicListMode.popular),
              _persistedTopic,
            ],
          ),
        ],
      ),
    ]),
    forumTabsEnabled: false,
    mobileNavigationEnabled: true,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    plugins: plugins,
  );
  addTearDown(() async {
    shell.dispose();
    await plugins.close();
  });
  await shell.load();
  await pumpEventQueue();
  return (shell: shell, api: api, activator: activator);
}

final class _SiteActivationModule implements PluginModule {
  const _SiteActivationModule(this.activator);

  final _RecordingSiteActivator activator;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('site-activation-test'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _SiteActivationLifecycle(),
        capabilities: [activator],
      ),
      requires: const [],
    );
  }
}

final class _SiteActivationLifecycle extends PluginSessionLifecycle {}

final class _RecordingSiteActivator implements PluginSiteActivator {
  final List<String> sites = [];

  @override
  void activatePluginSite(String siteUrl, {required bool connected}) =>
      sites.add(siteUrl);
}

void main() {
  group('forum switching', () {
    test(
      'activates the site once and never loads the replaced persisted route',
      () async {
        final (:shell, :api, :activator) = await _forumSwitchFixture();
        final feedsBeforeSwitch = api.feedPaths.length;
        activator.sites.clear();

        shell.selectInstance(1);
        await pumpEventQueue();

        expect(shell.currentContent?.id, 'latest');
        expect(api.feedPaths.sublist(feedsBeforeSwitch), ['/latest.json']);
        expect(api.topicsOpened, isEmpty);
        expect(activator.sites, [_teamUrl]);
      },
    );

    test(
      'returns to the default route when the current forum is reselected',
      () async {
        final (:shell, :api, :activator) = await _forumSwitchFixture();
        shell.selectInstance(1);
        shell.pushContent(_persistedTopic);
        await pumpEventQueue();
        expect(shell.currentContent?.id, _persistedTopic.id);
        final feedsBeforeReselect = api.feedPaths.length;
        final topicsBeforeReselect = api.topicsOpened.length;
        activator.sites.clear();

        shell.selectInstance(1);
        await pumpEventQueue();

        expect(shell.currentContent?.id, 'latest');
        expect(api.feedPaths.sublist(feedsBeforeReselect), ['/latest.json']);
        expect(api.topicsOpened, hasLength(topicsBeforeReselect));
        expect(activator.sites, [_teamUrl]);
      },
    );
  });

  _mobileTest(
    'scrolling Topics hides the tab bar and gives the page its space',
    (tester) async {
      final shell = await pumpMobileShellFixture(
        tester,
        topics: [
          for (var id = 1; id <= 50; id++)
            Topic(
              id: id,
              title: 'Scrollable topic $id',
              slug: 'scrollable-$id',
            ),
        ],
      );
      final panel = find.byKey(const ValueKey('mobile-content-panel'));
      final page = tester.element(find.byType(TopicListView));
      final originalPanel = tester.getRect(panel);
      final originalHeader = tester.getRect(_header);
      final list = find.byType(TopicListView);
      await tester.drag(list, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      expect(tester.getRect(panel).bottom, greaterThan(originalPanel.bottom));
      expect(tester.getRect(_header), originalHeader);
      expect(tester.element(list), same(page));
      await tester.drag(list, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(_bar.hitTestable(), findsOneWidget);
      expect(tester.getRect(panel), originalPanel);
      await tester.drag(list, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      expect(_bar.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'scrolling the Chat inbox hides and restores the shared tab bar',
    (tester) async {
      await pumpMobileShellFixture(
        tester,
        conversations: ChatChannels(
          public: [
            for (var id = 1; id <= 40; id++)
              ChatChannel(
                id: id,
                title: 'Channel $id',
                kind: ChatChannelKind.category,
                membership: const ChatMembership(following: true),
              ),
          ],
          direct: const [],
        ),
      );
      await _tapDockTab(tester, 'panel/chat');
      final list = find.descendant(
        of: find.byType(ChatMobileSidebar),
        matching: find.byType(ListView),
      );
      expect(list, findsOneWidget);
      await tester.drag(list, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      await tester.drag(list, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(_bar.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('chat scrolling hides destinations while keeping Send in place', (
    tester,
  ) async {
    await pumpMobileShellFixture(
      tester,
      chatMessages: [
        for (var id = 1; id <= 50; id++)
          ChatMessage(
            id: id,
            channelId: 10,
            cooked: '<p>Scrollable chat message $id</p>',
            author: ChatMessageAuthor(
              id: id % 2 + 1,
              username: 'reader${id % 2}',
            ),
            createdAt: DateTime(2026, 10, 1).add(Duration(minutes: id)),
          ),
      ],
    );
    await _tapDockTab(tester, 'panel/chat');
    await _selectChatKind(tester, 'Direct messages');
    await tester.tap(find.text('sam').first);
    await tester.pumpAndSettle();
    final messages = find.byType(DMessageScrollerViewport);
    final start = find.byKey(const ValueKey('mobile-mode-start'));
    final send = find.byKey(const ValueKey('chat-composer-send'));
    final originalSend = tester.getRect(send);
    final originalBar = tester.getRect(_bar);
    // Chat begins at its newest messages. Read older messages, then down again.
    await tester.drag(messages, const Offset(0, 320));
    await tester.pumpAndSettle();
    await tester.drag(messages, const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(start.hitTestable(), findsNothing);
    expect(send.hitTestable(), findsOneWidget);
    expect(tester.getRect(send), originalSend);
    expect(tester.getRect(_bar), originalBar);
    await tester.enterText(
      find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byType(TextField),
      ),
      'Send remains available',
    );
    await tester.pumpAndSettle();
    expect(start.hitTestable(), findsNothing);
    expect(tester.widget<DButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ComposerEditor>(find.byType(ComposerEditor))
          .composer
          .text
          .text,
      isEmpty,
    );
    await tester.drag(messages, const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(start.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
      expect(tester.getRect(control), tester.getRect(surface));
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
      find.byKey(const ValueKey('chat-new-direct-message-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-new-direct-message-dialog')),
      findsNothing,
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
    expect(find.text('4 messages'), findsOneWidget);
    expect(find.text('3 messages'), findsOneWidget);
    expect(find.text('9 messages'), findsNothing);
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
      expect(tester.widget<DButton>(trigger).size, DControlSize.chip);
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

  _mobileTest('Start opens the start page from another mobile tab', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final start = find.byKey(const ValueKey('mobile-mode-start'));
    expect(start, findsOneWidget);
    expect(
      tester.getRect(start).left,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('mobile-mode-topics'))).left,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(shell.mobileNavigation.tab, MobileTab.start);
    expect(shell.currentContent?.isNewTab, isTrue);
    expect(find.byKey(const ValueKey('start-page-content')), findsOneWidget);
    expect(shell.canPopContent, isFalse);

    final chromeLogo = find.descendant(
      of: _header,
      matching: find.byKey(const ValueKey('forum-identity-logo')),
    );
    final startHeading = find.byKey(const ValueKey('start-page-heading'));
    final startOptions = find.descendant(
      of: startHeading,
      matching: find.byKey(const ValueKey('start-page-forum-options')),
    );
    expect(chromeLogo, findsOneWidget);
    expect(startOptions, findsOneWidget);
    expect(
      find.descendant(of: startHeading, matching: find.text('Meta')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('start-page-forum-website')),
      findsOneWidget,
    );
    await tester.tap(chromeLogo);
    await tester.pumpAndSettle();
    expect(find.text('Open forum in browser'), findsNothing);
    await tester.tap(startOptions);
    await tester.pumpAndSettle();
    expect(find.text('Open forum in browser'), findsOneWidget);
    expect(find.text('Remove forum'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
      for (final tab in ['start', 'topics', 'panel/chat', 'more']) {
        final button = find.byKey(ValueKey('mobile-mode-$tab'));
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(right));
        expect(rect.right, lessThanOrEqualTo(phone.width));
        right = rect.right;
        expect(
          find.descendant(of: button, matching: find.byType(DButton)),
          findsOneWidget,
        );
        expect(tester.widget<DMobileDockItem>(button).label, isNotEmpty);
        final icon = find.descendant(of: button, matching: find.byType(DIcon));
        expect(tester.getSize(icon), const Size(20, 20));
        final glyph = find.descendant(
          of: icon,
          matching: find.byType(TintedIconGlyph),
        );
        expect(tester.getSize(glyph).longestSide, 20);
      }
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Topics'), findsWidgets);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(
        find.descendant(of: _bar, matching: find.byType(DTabList<String>)),
        findsNothing,
      );
      for (final key in [
        UserMenuButton.bellKey,
        UserMenuButton.avatarKey,
        const ValueKey('forum-identity-logo'),
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
        find.byKey(const ValueKey('forum-identity-logo')),
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
        tester.getSize(find.byKey(const ValueKey('forum-identity-logo'))),
        const Size.square(32),
      );
      expect(
        tester.widget<DButton>(find.byKey(UserMenuButton.avatarKey)).size,
        DButtonSize.regular,
      );
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('tab unread counts sit beside the label within one tap target', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester, chatUnreadCount: 32);
    final button = find.byKey(const ValueKey('mobile-mode-panel/chat'));
    final badge = find.byKey(const ValueKey('chat-mobile-unread-badge'));
    void expectPosition() {
      final buttonRect = tester.getRect(button);
      final badgeRect = tester.getRect(badge);
      final labelRect = tester.getRect(
        find.descendant(of: button, matching: find.text('Chat')),
      );
      expect(badgeRect.left, greaterThanOrEqualTo(labelRect.right));
      expect(badgeRect.center.dy, closeTo(labelRect.center.dy, 1));
      expect(badgeRect.right, lessThanOrEqualTo(buttonRect.right));
    }

    expectPosition();
    expect(find.text('32'), findsOneWidget);
    await tester.tapAt(tester.getCenter(badge));
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.tab, const MobileTab.panel('chat'));
    expectPosition();
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'tab icon capsule fills when selected and clears when deselected',
    (tester) async {
      await pumpMobileShellFixture(tester);
      final button = find.byKey(const ValueKey('mobile-mode-panel/chat'));
      final capsule = find.descendant(
        of: button,
        matching: find.byKey(const ValueKey('mobile-dock-capsule')),
      );
      Color? fill() =>
          (tester.widget<AnimatedContainer>(capsule).decoration
                  as BoxDecoration)
              .color;
      expect(fill(), Colors.transparent);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(fill(), isNot(Colors.transparent));
      expect(tester.getSize(capsule), const Size(44, 30));

      await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
      await tester.pumpAndSettle();
      expect(fill(), Colors.transparent);
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
      final sidebar = find.descendant(
        of: find.byKey(const ValueKey('mobile-navigation-page')),
        matching: find.byType(DSidebar),
      );
      expect(
        tester.widget<DSidebar>(sidebar).backgroundColor,
        DTokens.of(tester.element(sidebar)).muted,
      );
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byType(ForumIdentityHeader),
        ),
        findsNothing,
      );
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

  _mobileTest('an open topic subscribes to its live channels until left', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final tracker = FakeSiteTracker.built.singleWhere(
      (tracker) => tracker.siteUrl == _site,
    );
    expect(shell.desktopPanelsEnabled, isFalse);
    expect(tracker.watchedTopic, isNull);

    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();

    expect(shell.currentContent?.topicId, 7);
    expect(tracker.watchedTopic, 7);
    expect(tracker.watchedChannels, contains('/topic/7'));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(tracker.watchedTopic, isNull);
    expect(tracker.watchedChannels, isEmpty);
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
    expect(tester.getRect(topic).right, lessThan(tester.getRect(_bar).right));
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
    await _tapDockTab(tester, 'messages');
    final message = find.byKey(const ValueKey('new-message-button'));
    expect(message, findsOneWidget);
    await tester.tap(message);
    await tester.pumpAndSettle();
    expect(shell.visibleComposer, isNotNull);
    expect(shell.visibleComposer!.target.isPrivateMessage, isTrue);
    expect(shell.visibleComposer!.target.targetRecipients, '');
    expect(tester.takeException(), isNull);
  });

  _mobileTest('leaving a topic replaces Reply with the Chat creation action', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      topic: topicPayload(id: 7, canCreatePost: true),
    );
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-topic-reply')), findsOneWidget);

    await _tapDockTab(tester, 'panel/chat');
    // Panel roots keep the shared content route parked behind the panel.
    expect(shell.currentContent?.isTopic, isTrue);
    expect(shell.mobileNavigation.atRoot, isTrue);
    expect(find.byKey(const ValueKey('mobile-topic-reply')), findsNothing);
    final action = find.byKey(const ValueKey('mobile-panel-action'));
    expect(action, findsOneWidget);
    expect(
      tester
          .widget<DIcon>(
            find.descendant(of: action, matching: find.byType(DIcon)),
          )
          .icon,
      DIcons.plus,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-new-direct-message-sheet')),
      findsOneWidget,
    );
    expect(shell.visibleComposer, isNull);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('identical plus buttons stay still while their actions update', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final fades = find.descendant(
      of: find.byType(DActionTransition),
      matching: find.byType(FadeTransition),
    );
    final originalAnimation = tester.widget<FadeTransition>(fades).opacity;
    for (final (tab, key) in [
      ('panel/chat', 'mobile-panel-action'),
      ('messages', 'new-message-button'),
      ('topics', 'mobile-new-topic'),
      ('panel/chat', 'mobile-panel-action'),
    ]) {
      await _tapDockTab(tester, tab, settle: false);
      await tester.pump();
      expect(fades, findsOneWidget, reason: tab);
      final animation = tester.widget<FadeTransition>(fades).opacity;
      expect(animation, same(originalAnimation), reason: tab);
      expect(animation.value, 1, reason: tab);
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      expect(animation.value, 1, reason: tab);
    }
    // The visually identical button must use Chat's latest callback.
    await tester.tap(find.byKey(const ValueKey('mobile-panel-action')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-new-direct-message-sheet')),
      findsOneWidget,
    );
    expect(shell.visibleComposer, isNull);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('wide dock keeps creation actions icon-only when tabs change', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, size: const Size(800, 1000));
    final topic = find.byKey(const ValueKey('mobile-new-topic'));
    expect(
      find.descendant(of: topic, matching: find.text('New topic')),
      findsNothing,
    );
    expect(tester.widget<DButton>(topic).tooltip, 'New topic');
    await _tapDockTab(tester, 'messages', settle: false);
    await tester.pump();
    final message = find.byKey(const ValueKey('new-message-button'));
    expect(
      find.descendant(of: message, matching: find.text('New message')),
      findsNothing,
    );
    expect(tester.widget<DButton>(message).tooltip, 'New message');
    await tester.pump(const Duration(milliseconds: 60));
    expect(topic, findsNothing);
    expect(
      tester
          .widget<FadeTransition>(
            find
                .ancestor(of: message, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value,
      1,
    );
    await tester.pumpAndSettle();
    expect(topic, findsNothing);
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'trailing actions animate across routes while dock slots stay put',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      final topic = find.byKey(const ValueKey('mobile-new-topic'));
      final start = find.byKey(const ValueKey('mobile-mode-start'));
      final startRect = tester.getRect(start);
      final actionCenter = tester.getCenter(topic);
      await tester.tap(start);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(topic, findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: topic, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, inExclusiveRange(0, 1));
      expect(tester.getRect(start), startRect);
      await tester.tapAt(actionCenter);
      expect(shell.visibleComposer, isNull);
      await tester.pumpAndSettle();
      expect(topic, findsNothing);

      await _tapDockTab(tester, 'topics', settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(of: topic, matching: find.byType(FadeTransition))
                  .first,
            )
            .opacity
            .value,
        inExclusiveRange(0, 1),
      );
      expect(tester.getRect(start), startRect);
      // Replace an action before its entrance has finished.
      await _tapDockTab(tester, 'panel/chat', settle: false);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(topic, findsNothing);
      expect(find.byKey(const ValueKey('mobile-panel-action')), findsOneWidget);
      expect(tester.getRect(start), startRect);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('Home to topic and back animates the contextual action', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      topic: topicPayload(id: 7, canCreatePost: true),
    );
    await _tapDockTab(tester, 'start');
    final transition = find.descendant(
      of: _bar,
      matching: find.byType(DActionTransition),
    );
    final element = tester.element(transition);
    final dockRect = tester.getRect(
      find.byKey(const ValueKey('mobile-mode-start')),
    );
    shell.openTopic(
      const Topic(id: 7, slug: 'shared', title: 'Shared topic card'),
    );
    await tester.pump();
    await tester.pump();
    final reply = find.byKey(const ValueKey('mobile-topic-reply'));
    for (var frame = 0; frame < 20 && reply.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(reply, findsOneWidget);
    expect(tester.element(transition), same(element));
    await tester.pump(const Duration(milliseconds: 60));
    Rect paintedReply() {
      final box = tester.renderObject<RenderBox>(reply);
      return Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      );
    }

    final entering = paintedReply();
    expect(
      tester
          .widget<FadeTransition>(
            find
                .ancestor(of: reply, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value,
      inExclusiveRange(0, 1),
    );
    await tester.pumpAndSettle();
    final settled = paintedReply();
    expect(entering.width, lessThan(settled.width * .92));
    expect(entering.center.dx, closeTo(settled.center.dx, .001));
    expect(entering.center.dy, closeTo(settled.center.dy, .001));
    expect(
      tester.getRect(find.byKey(const ValueKey('mobile-mode-start'))),
      dockRect,
    );
    expect(shell.handleBack(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(reply, findsOneWidget);
    expect(paintedReply().width, lessThan(settled.width));
    expect(paintedReply().center.dx, closeTo(settled.center.dx, .001));
    expect(paintedReply().center.dy, closeTo(settled.center.dy, .001));
    expect(
      tester
          .widget<FadeTransition>(
            find
                .ancestor(of: reply, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value,
      inExclusiveRange(0, 1),
    );
    await tester.pumpAndSettle();
    expect(reply, findsNothing);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('dock slots keep their geometry across every tab', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, events: true);
    for (final width in [320.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      Map<Key?, Rect>? expected;
      // Start has no trailing action, Topics and Messages each have their
      // own, and Chat carries its panel action: none may move a slot.
      for (final tab in [
        'start',
        'topics',
        'panel/chat',
        'messages',
        'start',
      ]) {
        await _tapDockTab(tester, tab);
        final slots = {
          for (final item
              in find
                  .descendant(of: _bar, matching: find.byType(DMobileDockItem))
                  .evaluate())
            item.widget.key: tester.getRect(
              find.byElementPredicate((e) => e == item),
            ),
        };
        expect(slots, expected ?? slots, reason: '$tab at $width');
        expected ??= slots;
      }
    }
    expect(tester.takeException(), isNull);
  });

  _mobileTest('list page actions sit with the list, not in the dock', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final dock = tester.getRect(find.byKey(const ValueKey('mobile-mode-more')));
    final row = find.byKey(const ValueKey('topic-list-feed-row'));

    await shell.selectTopicListMode(TopicListMode.newActivity);
    await tester.pumpAndSettle();
    final dismiss = find.byKey(const ValueKey('dismiss-new-topics'));
    expect(find.descendant(of: row, matching: dismiss), findsOneWidget);
    expect(find.descendant(of: _bar, matching: dismiss), findsNothing);

    shell.openCategory(
      const TopicCategory(
        id: 42,
        name: 'Support',
        slug: 'support',
        color: '3188CC',
      ),
    );
    await tester.pumpAndSettle();
    final notifications = find.byType(CategoryNotificationLevelButton);
    expect(find.descendant(of: row, matching: notifications), findsOneWidget);
    expect(find.descendant(of: _bar, matching: notifications), findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('mobile-mode-more'))),
      dock,
    );
    expect(tester.takeException(), isNull);
  });

  _mobileTest('creation actions stay icon-only and on one row at every width', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, events: true);
    for (final tab in ['topics', 'messages']) {
      await _tapDockTab(tester, tab);
      final action = find.byKey(
        ValueKey(tab == 'topics' ? 'mobile-new-topic' : 'new-message-button'),
      );
      for (final width in [800.0, 600.0, 390.0, 320.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        expect(tester.widget<DButton>(action).label is! Text, isTrue);
        expect(tester.getCenter(action).dy, tester.getCenter(_bar).dy);
        expect(
          tester.getRect(action).right,
          lessThan(tester.getRect(_bar).right),
        );
        expect(tester.getSize(action), const Size(44, 44));
        for (final button
            in find
                .descendant(of: _bar, matching: find.byType(DMobileDockItem))
                .evaluate()) {
          expect(
            tester.getCenter(find.byElementPredicate((e) => e == button)).dy,
            tester.getCenter(action).dy,
          );
        }
        expect(tester.takeException(), isNull);
      }
      // At narrow widths More retains the spilled destinations and creation
      // stays pinned on the right.
      final more = find.byKey(const ValueKey('mobile-mode-more'));
      expect(tester.getRect(more).right, lessThan(tester.getRect(action).left));
      expect(find.byKey(const ValueKey('mobile-mode-users')), findsNothing);
      tester.view.physicalSize = phone;
      await tester.pumpAndSettle();
    }
  });

  _mobileTest('circular dock actions share evenly spaced columns with tabs', (
    tester,
  ) async {
    await pumpMobileShellFixture(
      tester,
      topic: topicPayload(id: 7, canCreatePost: true),
    );
    for (final width in [320.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      for (final (tab, key) in [
        ('topics', 'mobile-new-topic'),
        ('messages', 'new-message-button'),
        ('panel/chat', 'mobile-panel-action'),
        ('topics', 'mobile-topic-reply'),
      ]) {
        await _tapDockTab(tester, tab);
        if (key == 'mobile-topic-reply') {
          await tester.tap(find.byKey(const ValueKey('topic-card-7')));
          await tester.pumpAndSettle();
        }
        final action = find.byKey(ValueKey(key));
        final icon = find.descendant(of: action, matching: find.byType(DIcon));
        final dockIcon = find.descendant(
          of: find.byKey(const ValueKey('mobile-mode-topics')),
          matching: find.byType(DIcon),
        );
        expect(tester.widget<DButton>(action).label is! Text, isTrue);
        expect(tester.getSize(action), const Size(44, 44));
        expect(tester.getSize(icon), tester.getSize(dockIcon));
        expect(
          tester.getCenter(icon).dx,
          closeTo(tester.getCenter(action).dx, .5),
        );
        final centers = [
          for (final item in find.byType(DMobileDockItem).evaluate())
            tester.getCenter(find.byElementPredicate((e) => e == item)).dx,
          tester.getCenter(action).dx,
        ];
        final bar = tester.getRect(_bar);
        final columnWidth = bar.width / centers.length;
        for (var i = 0; i < centers.length; i++) {
          expect(centers[i], closeTo(bar.left + columnWidth * (i + .5), .01));
        }
        final surface = find.descendant(
          of: action,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedContainer &&
                widget.decoration is DButtonDecoration,
          ),
        );
        expect(tester.getRect(surface), tester.getRect(action));
        expect(tester.takeException(), isNull);
      }
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
    expect(shell.accountActivity.bookmarkListFor(_site).loaded, isTrue);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('More owns spilled destinations until the dock has room', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester, events: true);
    expect(find.byKey(const ValueKey('mobile-mode-users')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-more')));
    await tester.pumpAndSettle();
    for (final label in ['Messages', 'Users', 'Events']) {
      expect(
        find.descendant(
          of: find.byType(DDropdownMenuItem),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(
        of: find.byType(DDropdownMenuItem),
        matching: find.text('Users'),
      ),
    );
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.tab, MobileTab.users);
    expect(
      tester
          .widget<DMobileDockItem>(
            find.byKey(const ValueKey('mobile-mode-more')),
          )
          .selected,
      isTrue,
    );

    tester.view.physicalSize = const Size(700, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-mode-users')), findsOneWidget);
    expect(
      tester
          .widget<DMobileDockItem>(
            find.byKey(const ValueKey('mobile-mode-users')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<DMobileDockItem>(
            find.byKey(const ValueKey('mobile-mode-more')),
          )
          .selected,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  _mobileTest('large labels spill into More without clipping the action', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMobileShellFixture(tester, size: const Size(320, 720));
    final more = find.byKey(const ValueKey('mobile-mode-more'));
    final action = find.byKey(const ValueKey('mobile-new-topic'));
    expect(more, findsOneWidget);
    expect(tester.getRect(more).right, lessThan(tester.getRect(action).left));
    expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(action).width, tester.getSize(action).height);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DDropdownMenuItem),
        matching: find.text('Chat'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  _mobileTest('users and events keep their own page headings', (tester) async {
    await pumpMobileShellFixture(tester, events: true);
    for (final (tab, heading, duplicate) in [
      ('users', 'Users', 'Users'),
      ('destination/events-upcoming', 'Events', 'Upcoming events'),
    ]) {
      await _tapDockTab(tester, tab);
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
    await _tapDockTab(tester, 'destination/events-upcoming');
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
        await _tapDockTab(tester, from);
        final restingPanel = tester.getRect(panel);
        await _tapDockTab(tester, to, settle: false);
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
      // The mixed inbox lists rooms beneath its conversations.
      expect(
        find.descendant(
          of: find.byType(ChatMobileSidebar),
          matching: find.byKey(const ValueKey('chat-inbox-room-7')),
        ),
        findsOneWidget,
      );
      expect(find.text('General'), findsOneWidget);
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
    'header retains account actions and a static logo; search is a dedicated page',
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
      expect(find.byType(DSheetContent), findsNothing);
      expect(find.byType(UserMenuPanel), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsNothing);
      await tester.tap(find.byKey(const ValueKey('forum-identity-logo')));
      await tester.pumpAndSettle();
      expect(find.text('Open forum in browser'), findsNothing);
      expect(find.text('Remove forum'), findsNothing);
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

  _mobileTest('forum identity stays logo-only and inert across mobile widths', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    try {
      final shell = await pumpMobileShellFixture(tester);
      final identity = find.byType(ForumIdentityHeader);
      final logo = find.byKey(const ValueKey('forum-identity-logo'));

      void expectStaticLogo() {
        expect(
          find.descendant(of: _header, matching: identity),
          findsOneWidget,
        );
        expect(tester.getSize(logo), const Size.square(32));
        expect(
          find.descendant(of: identity, matching: find.text('Meta')),
          findsNothing,
        );
        expect(
          find.descendant(of: identity, matching: find.byType(DButton)),
          findsNothing,
        );
        expect(
          find.descendant(of: identity, matching: find.byType(DDropdownMenu)),
          findsNothing,
        );
        expect(
          find.descendant(of: identity, matching: find.byType(Tooltip)),
          findsNothing,
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Meta')),
          matchesSemantics(label: 'Meta', isImage: true),
        );
      }

      for (final size in [const Size(320, 720), phone, const Size(1024, 768)]) {
        tester.view.physicalSize = size;
        for (final scale in [1.0, 2.0]) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          expectStaticLogo();
          final content = shell.currentContent;
          await tester.tap(logo);
          await tester.pumpAndSettle();
          expect(shell.currentContent, same(content));
          expect(shell.mobileNavigation.sidebarOpen, isFalse);
          expect(find.text('Open forum in browser'), findsNothing);
          expect(find.text('Remove forum'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }

      shell.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'shared',
          title: 'Shared topic card',
        ),
      );
      await tester.pumpAndSettle();
      expectStaticLogo();
      await tester.tap(logo);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 7);
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expectStaticLogo();
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
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
      await _tapDockTab(tester, 'users');
      expect(find.byType(UsersPage), findsOneWidget);
      expect(shell.canPopContent, isFalse);
      expect(shell.canForwardContent, isFalse);
      _expectPage();
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('chat focus keeps navigation and Send in the bottom bar', (
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
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).height, initialHeight);
    expect(_bar, findsOneWidget);
    final send = find.byKey(const ValueKey('chat-composer-send'));
    expect(find.descendant(of: _bar, matching: send), findsOneWidget);
    expect(tester.widget<DButton>(send).onPressed, isNull);
    await tester.enterText(
      find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byType(TextField),
      ),
      'Hello from mobile',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(composer.text.text, isEmpty);
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
      _expectPage();
      expect(
        find.descendant(
          of: _bar,
          matching: find.byKey(const ValueKey('chat-composer-send')),
        ),
        findsOneWidget,
      );
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
      expect(find.byKey(const ValueKey('chat-composer-send')), findsNothing);
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      _expectPage();
      expect(
        find.descendant(
          of: _bar,
          matching: find.byKey(const ValueKey('chat-composer-send')),
        ),
        findsOneWidget,
      );
      expect(shell.currentContent?.id, contains('10'));
      shell.handleBack();
      await tester.pumpAndSettle();
      expect(_bar, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chat-inbox-kind-filter')),
          matching: find.text('Direct messages'),
        ),
        findsOneWidget,
      );
      expect(find.text('General'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('chat retains Browse channels and Browse threads navigation', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    final navigation = find.byKey(const ValueKey('chat-browse-navigation'));
    Finder peer(String label) =>
        find.descendant(of: navigation, matching: find.text(label));
    expect(find.text('Browse chats'), findsOneWidget);
    expect(peer('Channels'), findsOneWidget);
    expect(peer('Threads'), findsOneWidget);
    await tester.tap(peer('Channels'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-browse');
    shell.handleBack();
    await tester.pumpAndSettle();
    await tester.tap(peer('Threads'));
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

  _mobileTest('root edge swipes open and close navigation across mobile tabs', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final header = tester.getRect(_header);
    for (final tab in ['topics', 'start', 'panel/chat', 'messages', 'users']) {
      await _tapDockTab(tester, tab);
      expect(shell.mobileNavigation.tab.name, tab);
      expect(shell.canPopContent, isFalse);
      final history = shell.mobileNavigation.historyId;
      final visit = shell.mobileNavigation.entryId;
      final content = shell.currentContent;
      final panel = tester.element(
        find.byKey(const ValueKey('mobile-content-panel')),
      );
      final navigationPage = find.byKey(
        const ValueKey('mobile-navigation-page'),
        skipOffstage: false,
      );
      final navigationElement = tester.element(navigationPage);
      expect(find.byType(InstanceRail), findsNothing);

      final open = await tester.startGesture(const Offset(8, 400));
      await open.moveBy(
        const Offset(120, 0),
        timeStamp: const Duration(milliseconds: 200),
      );
      await tester.pump();
      expect(shell.mobileNavigation.sidebarOpen, isFalse);
      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.text('Forum'), findsOneWidget);
      expect(tester.element(navigationPage), same(navigationElement));
      expect(tester.getRect(_header), header);
      await open.up();
      await tester.pump();
      await tester.pump(DMotion.change);
      expect(shell.mobileNavigation.sidebarOpen, isTrue);
      expect(find.byKey(const ValueKey('history-incoming-tab')), findsNothing);
      expect(find.byKey(const ValueKey('history-outgoing-tab')), findsNothing);
      expect(tester.element(navigationPage), same(navigationElement));
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.sidebarOpen, isTrue, reason: tab);
      expect(find.byType(InstanceRail), findsOneWidget);
      expect(_bar, findsNothing);

      final page = tester.getRect(
        find.byKey(const ValueKey('mobile-navigation-page')),
      );
      final close = await tester.startGesture(Offset(page.right - 4, 400));
      await close.moveBy(
        const Offset(-120, 0),
        timeStamp: const Duration(milliseconds: 200),
      );
      await tester.pump();
      expect(shell.mobileNavigation.sidebarOpen, isTrue);
      final preview = tester.widget<RawImage>(find.byType(RawImage));
      expect(preview.image, isNotNull);
      expect(preview.fit, BoxFit.fitWidth);
      expect(tester.getRect(_header), header);
      await close.up();
      await tester.pump();
      await tester.pump(DMotion.change);
      expect(shell.mobileNavigation.sidebarOpen, isFalse);
      expect(find.byKey(const ValueKey('history-incoming-tab')), findsNothing);
      expect(find.byKey(const ValueKey('history-outgoing-tab')), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.element(navigationPage), same(navigationElement));
      expect(shell.mobileNavigation.sidebarOpen, isFalse, reason: tab);
      expect(shell.mobileNavigation.tab.name, tab);
      expect(shell.mobileNavigation.historyId, same(history));
      expect(shell.mobileNavigation.entryId, same(visit));
      expect(shell.currentContent, same(content));
      expect(shell.canPopContent, isFalse);
      expect(shell.canForwardContent, isFalse);
      expect(
        tester.element(find.byKey(const ValueKey('mobile-content-panel'))),
        same(panel),
      );
      _expectPage();
    }
    expect(tester.takeException(), isNull);
  });

  _mobileTest('rail swipes preserve Back and Forward visits', (tester) async {
    final shell = await pumpMobileShellFixture(tester);
    final root = shell.mobileNavigation.entryId;
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    final topic = shell.mobileNavigation.entryId;
    final page = tester.getRect(
      find.byKey(const ValueKey('mobile-content-panel')),
    );
    Future<void> swipe(bool right) async {
      final gesture = await tester.startGesture(
        Offset(right ? page.right - 4 : page.left + 4, 400),
      );
      await gesture.moveBy(
        Offset(right ? -120 : 120, 0),
        timeStamp: const Duration(milliseconds: 200),
      );
      await tester.pump();
      if (right) {
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await swipe(false);
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(shell.mobileNavigation.entryId, same(root));
    expect(shell.currentContent?.id, 'latest');
    expect(shell.canForwardContent, isTrue);
    await swipe(false);
    expect(shell.mobileNavigation.sidebarOpen, isTrue);
    await swipe(true);
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(shell.mobileNavigation.entryId, same(root));
    expect(shell.currentContent?.id, 'latest');
    expect(shell.canForwardContent, isTrue);
    await swipe(true);
    expect(shell.mobileNavigation.entryId, same(topic));
    expect(shell.currentContent?.topicId, 7);

    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    await swipe(true);
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(shell.mobileNavigation.entryId, same(topic));
    expect(shell.currentContent?.topicId, 7);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('short and cancelled rail swipes retain the current surface', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final visit = shell.mobileNavigation.entryId;
    final page = tester.getRect(
      find.byKey(const ValueKey('mobile-content-panel')),
    );
    for (final open in [false, true]) {
      if (open) {
        await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
        await tester.pumpAndSettle();
      }
      for (final cancel in [false, true]) {
        final gesture = await tester.startGesture(
          Offset(open ? page.right - 4 : page.left + 4, 400),
        );
        await gesture.moveBy(
          Offset(open ? -30 : 30, 0),
          timeStamp: const Duration(milliseconds: 400),
        );
        await tester.pump();
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(shell.mobileNavigation.sidebarOpen, open);
        expect(shell.mobileNavigation.entryId, same(visit));
      }
    }
    expect(tester.takeException(), isNull);
  });

  _mobileTest('topic feed refreshes redraw the list without the chrome', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    expect(shell.currentFeedId, 'latest');
    var shellNotifications = 0;
    void countShellNotification() => shellNotifications++;
    shell.addListener(countShellNotification);
    addTearDown(() => shell.removeListener(countShellNotification));
    var feedNotifications = 0;
    void countFeedNotification() => feedNotifications++;
    shell.topicFeeds.addListener(countFeedNotification);
    addTearDown(() => shell.topicFeeds.removeListener(countFeedNotification));

    // The header and bar are render-object elements, which report no rebuild
    // of their own; a rebuilt root shows up in the components beneath them.
    Iterable<Element> subtree(Finder root) => find
        .descendant(of: root, matching: find.byWidgetPredicate((_) => true))
        .evaluate();
    final dockItems = find.byType(DMobileDockItem).evaluate().toList();
    expect(dockItems, hasLength(greaterThanOrEqualTo(4)));
    final panels = find
        .byType(InstanceSidebar, skipOffstage: false)
        .evaluate()
        .toList();
    expect(panels, isNotEmpty);
    final chrome = {
      ...subtree(_header),
      ...subtree(_bar),
      ...dockItems,
      ...panels,
      tester.element(find.byType(MobileHistoryGestures)),
    };
    final list = tester.element(find.byType(TopicListView));
    final rebuilt = <Element>{};
    final previousRebuildCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previousRebuildCallback?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previousRebuildCallback);

    final refresh = shell.loadFeed('latest', force: true);
    await tester.pump();
    await refresh;
    await tester.pump();

    expect(feedNotifications, greaterThan(0));
    expect(shellNotifications, 0);
    expect(rebuilt, contains(list));
    expect(rebuilt.intersection(chrome), isEmpty);
    expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
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
    expect(find.byType(UserMenuPanel), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(UserMenuPanel), findsNothing);
    expect(shell.canPopContent, isFalse);
    await _tapDockTab(tester, 'panel/chat');
    await _selectChatKind(tester, 'Direct messages');
    expect(
      find.byKey(const ValueKey('chat-browse-navigation')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-forum-settings')), findsNothing);
    expect(find.byKey(const ValueKey('mobile-new-topic')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('forum-identity-logo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('forum-identity-settings')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('forum-identity-logo')));
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
