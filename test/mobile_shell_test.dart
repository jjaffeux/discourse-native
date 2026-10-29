import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/category_notifications.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/draft_list.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/mobile_place_order.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_list_actions.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/shell/user_summary.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/d_icon_glyph.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/badge_fixtures.dart';
import 'support/bundled_plugins.dart';
import 'support/button_surface.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
DiscourseUser _reader({bool staff = false}) => DiscourseUser(
  id: 7,
  username: 'reader',
  hidePresence: false,
  canCreateTopic: true,
  canSendPrivateMessages: true,
  staff: staff,
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);
final _user = _reader();
final _bar = find.byKey(const ValueKey('mobile-bottom-bar'));
final _header = find.byKey(const ValueKey('mobile-header'));

/// What grows the bar into its panel: the ⋮, or the current page standing
/// where the ⋮ was because the bar has no column for it.
final _moreTrigger = find.descendant(
  of: _bar,
  matching: find.byWidgetPredicate(
    (widget) => widget is DMobileDockItem && widget.hasPopup,
  ),
);

/// Look A's page card: as round at its top as the bar, 22 at its foot.
void _expectPageRadius(BorderRadiusGeometry? geometry) => expect(
  geometry,
  const BorderRadius.vertical(
    top: Radius.circular(31),
    bottom: Radius.circular(22),
  ),
);

Future<void> _loadChromeCaptureFonts(WidgetTester tester) async {
  if (!const bool.fromEnvironment('captureMobileChrome')) return;
  await tester.runAsync(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
}

Future<void> _captureChrome(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('captureMobileChrome')) return;
  await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      tester.view.physicalSize.width.toInt(),
      tester.view.physicalSize.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/inset-body-${Theme.of(tester.element(_header)).platform.name}-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    scene.dispose();
  });
}

Future<void> _chatWheel(
  WidgetTester tester,
  Finder messages,
  double delta,
) async {
  // The shared chrome holds its fully shown/hidden state before a reversal.
  await tester.pump(const Duration(milliseconds: 450));
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(messages),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
}

final _panel = find.byKey(DMobileDock.panelKey);
final _dim = find.byKey(DMobileDock.dimKey);

/// The labels on the bar, left to right.
List<String> _dockLabels(WidgetTester tester) => [
  for (final element
      in find
          .descendant(
            of: find.byKey(const ValueKey('mobile-dock-surface')),
            matching: find.byType(DMobileDockItem),
          )
          .evaluate())
    if (element.widget.key != DMobileDock.moreKey)
      (element.widget as DMobileDockItem).label,
];

/// The names on the panel's tiles, you excepted.
List<String> _panelLabels(WidgetTester tester) => [
  for (final element
      in find
          .descendant(of: _panel, matching: find.byType(DMobileDockItem))
          .evaluate())
    if (element.widget.key !=
        DMobileDock.tileKey(const ValueKey('mobile-mode-profile')))
      (element.widget as DMobileDockItem).label,
];

/// The panel's tile for the place called [label].
Finder _panelTile(String label) => find.descendant(
  of: _panel,
  matching: find.widgetWithText(DMobileDockItem, label),
);

/// Grows the bar into its panel and returns every place in the order a
/// person meets them: the bar first, then the panel.
Future<List<String>> _placesInOrder(WidgetTester tester) async {
  await tester.tap(_moreTrigger);
  await tester.pumpAndSettle();
  return [..._dockLabels(tester), ..._panelLabels(tester)];
}

/// Picks a place from the panel.
Future<void> _chooseFromPanel(WidgetTester tester, String label) async {
  await tester.tap(_moreTrigger);
  await tester.pumpAndSettle();
  await tester.tap(_panelTile(label));
  await tester.pumpAndSettle();
}

const _topicDraft = UserDraft(
  key: 'new_topic',
  sequence: 1,
  title: 'Unfinished topic',
  data: ComposerDraft(
    reply: 'A reply',
    action: ComposerDraft.createTopicAction,
    title: 'Unfinished topic',
  ),
);

Future<void> _tapDockTab(
  WidgetTester tester,
  String tab, {
  bool settle = true,
}) async {
  final button = find.byKey(ValueKey('mobile-mode-$tab'));
  // The panel from the previous choice may still be closing over the bar,
  // its ⋮ out of reach until it has.
  if (_panel.evaluate().isNotEmpty) await tester.pumpAndSettle();
  if (button.hitTestable().evaluate().isNotEmpty) {
    await tester.tap(button);
  } else {
    final label = switch (tab) {
      'panel/chat' => 'Chat',
      'messages' => 'Inbox',
      'users' => 'Users',
      'destination/events-upcoming' => 'Events',
      'destination/user-bookmarks' => 'Bookmarks',
      'destination/summary' => 'Summary',
      'destination/activity' => 'Activity',
      _ => throw StateError('No panel label for $tab'),
    };
    await tester.tap(_moreTrigger);
    await tester.pumpAndSettle();
    await tester.tap(_panelTile(label));
  }
  if (settle) await tester.pumpAndSettle();
}

Future<ShellController> pumpMobileShellFixture(
  WidgetTester tester, {
  Size size = phone,
  bool voice = false,
  bool events = false,
  bool chat = true,
  DiscourseUser? user,
  int chatUnreadCount = 0,
  TopicPayload? topic,
  PluginManifest? pluginManifest,
  ChatChannels? conversations,
  List<Topic>? topics,
  List<TopicCategory> sidebarCategories = const [],
  List<Topic> moreTopics = const [],
  Completer<void>? moreTopicsGate,
  List<ChatMessage>? chatMessages,
  ChatThread? chatThread,
  ChatChannelBrowsePage? chatBrowsePage,
  Map<String, ChatThreadPage> channelThreadPages = const {},
  Map<String, dynamic>? board,
  Map<String, Map<String, dynamic>> pluginResponses = const {},
  FakeForumTabStore? forumTabs,
  Key? key,
  void Function(FakeDiscourseApi api)? onApi,
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
        .withValue(eventSettingsKey, EventSettings(enabled: events))
        .withValue(boardsSettingsKey, BoardsSettings(enabled: board != null)),
  );
  final account = user ?? _user;
  final api = FakeDiscourseApi(
    user: account,
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
      if (board != null) ...{
        'GET /boards/api/boards.json': {
          'boards': [board['board']],
        },
        'GET /boards/api/boards/${(board['board'] as Map)['id']}.json': board,
      },
      if (voice)
        'GET /live/rooms.json': {
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
      ...pluginResponses,
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
      if (moreTopics.isNotEmpty) '/latest.json?page=1': moreTopics,
    },
    feedCategoriesByPath: {'/latest.json': sidebarCategories},
    nextPages: {
      if (moreTopics.isNotEmpty) '/latest.json': '/latest.json?page=1',
    },
    feedGates: {'/latest.json?page=1': ?moreTopicsGate},
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
      if (chatThread != null)
        'thread-10-${chatThread.id}': (
          messages: chatMessages ?? const [],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
    },
    chatBrowsePagesByKey: {FakeDiscourseApi.chatBrowseKey(): ?chatBrowsePage},
    chatChannelThreadPagesByKey: channelThreadPages,
    chatThreadsByKey: {
      for (final thread in [?chatThread])
        FakeDiscourseApi.chatThreadKey(10, thread.id): thread,
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
  );
  onApi?.call(api);
  await pumpShell(
    tester,
    size,
    pluginManifest:
        pluginManifest ??
        PluginManifest([
          ...bundledWidgetTestManifest.modules,
          if (voice) const VoiceModule(),
        ]),
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Meta',
      ).copyWith(user: account, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: api,
    forumTabs: forumTabs,
    key: key,
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

/// The label of the place the bar marks as the current page, null when it
/// marks none.
String? _markedPlace(WidgetTester tester) => tester
    .widget<DMobileDock>(_bar)
    .places
    .where((place) => place.selected)
    .singleOrNull
    ?.label;

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
  if (const bool.fromEnvironment('captureMobileChrome') ||
      const bool.fromEnvironment('captureMobileSidebar') ||
      Platform.environment['CHAT_HEADER_EXPORT_DIR'] != null) {
    // Keep the channel alive through app disposal between capture variants.
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('org.discourse.native/notification_opens');
    setUpAll(
      () => messenger.setMockMethodCallHandler(channel, (_) async => null),
    );
    tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));
  }
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
      final title = find.byKey(const ValueKey('topic-list-title'));
      expect(title.hitTestable(), findsOneWidget);
      await tester.timedDrag(
        list,
        const Offset(0, -240),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(title.hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey('mobile-dock-reveal')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getRect(panel), originalPanel);
      expect(tester.getRect(_header), originalHeader);
      expect(tester.element(list), same(page));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.drag(list, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(title.hitTestable(), findsOneWidget);
      expect(_bar.hitTestable(), findsOneWidget);
      expect(tester.getRect(panel), originalPanel);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.drag(list, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile-dock-reveal')).hitTestable(),
        findsOneWidget,
      );
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      expect(_bar.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('returning from Chat keeps the scrolled topic row stable', (
    tester,
  ) async {
    late FakeDiscourseApi api;
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await pumpMobileShellFixture(
      tester,
      onApi: (value) => api = value,
      topics: [
        for (var id = 1; id <= 100; id++)
          Topic(
            id: id,
            title: 'Scrollable topic $id ' * (id % 4 + 1),
            slug: 'scrollable-$id',
            excerpt: 'A discussion with a variable length excerpt. ' * (id % 3),
          ),
      ],
    );
    final list = find.byType(TopicListView);
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: list,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable && widget.axis == Axis.vertical,
                ),
              )
              .first,
        )
        .position;
    await tester.drag(list, const Offset(0, -1500));
    await tester.pumpAndSettle();
    await _chatWheel(tester, list, -100);
    expect(position().pixels, greaterThan(1000));
    final visibleRow = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              RegExp(
                r'^topic-card-\d+$',
              ).hasMatch((widget.key! as ValueKey<String>).value),
        )
        .evaluate()
        .firstWhere((element) {
          final rect = tester.getRect(
            find.byElementPredicate((e) => e == element),
          );
          return rect.top > 200 && rect.bottom < 650;
        });
    final row = find.byKey(visibleRow.widget.key!);
    final requests = api.feedPaths.length;
    api.feedGates['/latest.json'] = gate;
    await _tapDockTab(tester, 'panel/chat');
    expect(find.byType(ChatMobileSidebar), findsOneWidget);
    await _tapDockTab(tester, 'topics', settle: false);
    double? firstTop;
    double? firstOffset;
    for (var frame = 0; frame < 30; frame++) {
      if (frame == 5) gate.complete();
      await tester.pump(const Duration(milliseconds: 16));
      firstOffset ??= position().pixels;
      expect(firstOffset, greaterThan(1000));
      expect(
        position().pixels,
        closeTo(firstOffset, .5),
        reason: 'frame $frame',
      );
      expect(row, findsOneWidget, reason: 'frame $frame');
      final top = tester.getTopLeft(row).dy;
      // Returning shows the heading again; the row must then stay still
      // throughout the tab transition and a delayed server response.
      firstTop ??= top;
      expect(top, closeTo(firstTop, .5), reason: 'frame $frame');
      expect(find.byType(TopicListLoadingSkeleton), findsNothing);
    }
    expect(api.feedPaths, hasLength(requests));

    // An explicit reselect still asks the server for fresh topics.
    await _tapDockTab(tester, 'topics');
    expect(api.feedPaths, hasLength(requests + 1));
    expect(api.feedPaths.last, '/latest.json');
    expect(tester.takeException(), isNull);
  });

  _mobileTest('Topics keeps the dock compact across a delayed infinite page', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    List<Topic> topics(int first, int last) => [
      for (var id = first; id <= last; id++)
        Topic(id: id, title: 'Scrollable topic $id', slug: 'scrollable-$id'),
    ];
    final shell = await pumpMobileShellFixture(
      tester,
      topics: topics(1, 50),
      moreTopics: topics(51, 100),
      moreTopicsGate: gate,
    );
    final list = find.byType(TopicListView);
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: list,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    );
    final chrome = DScrollChrome.maybeOf(scroll.context)!;
    await tester.drag(list, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(chrome.hiddenFraction, 1);
    expect(shell.currentFeed!.hasMore, isTrue);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 100000),
      ),
    );
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(chrome.hiddenFraction, 1);
    }
    expect(shell.currentFeed!.loadingMore, isTrue);
    expect(scroll.position.extentAfter, closeTo(0, 1));
    gate.complete();
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(chrome.hiddenFraction, 1);
    }
    expect(shell.currentFeed!.topicIds, hasLength(100));
    expect(shell.currentFeed!.hasMore, isFalse);
    expect(scroll.position.extentAfter, greaterThan(0));
    await _chatWheel(tester, list, 100);
    expect(chrome.hiddenFraction, 1);
    await _chatWheel(tester, list, -100);
    expect(chrome.hiddenFraction, 0);
    await _chatWheel(tester, list, 100);
    expect(chrome.hiddenFraction, 1);
    await _chatWheel(tester, list, 100000);
    expect(chrome.hiddenFraction, 0);
    expect(tester.takeException(), isNull);
  });

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
      expect(
        find.byKey(const ValueKey('mobile-dock-reveal')).hitTestable(),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.drag(list, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(_bar.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('a short channel swipe hides both its header and the tab bar', (
    tester,
  ) async {
    final exportDirectory = Platform.environment['CHAT_HEADER_EXPORT_DIR'];
    if (exportDirectory != null) {
      await (FontLoader(
        'Open Sans',
      )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
      await (FontLoader('Lato')
            ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
          .load();
    }
    Future<void> capture(String state) async {
      if (exportDirectory == null) return;
      await tester.runAsync(() async {
        final builder = ui.SceneBuilder();
        tester.binding.renderViews.first.debugLayer!.addToScene(builder);
        final scene = builder.build();
        final image = await scene.toImage(
          tester.view.physicalSize.width.toInt(),
          tester.view.physicalSize.height.toInt(),
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(exportDirectory).create(recursive: true);
        await File(
          '$exportDirectory/mobile-channel-${Theme.of(tester.element(_header)).platform.name}-$state.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        scene.dispose();
      });
    }

    final shell = await pumpMobileShellFixture(
      tester,
      conversations: const ChatChannels(
        public: [
          ChatChannel(
            id: 10,
            title: 'Support',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
          ),
        ],
        direct: [],
      ),
      chatMessages: [
        for (var id = 1; id <= 20; id++)
          ChatMessage(
            id: id,
            channelId: 10,
            cooked: '<p>Message $id</p>',
            author: const ChatMessageAuthor(id: 2, username: 'sam'),
            createdAt: DateTime(2026, 10, 1).add(Duration(minutes: id)),
          ),
      ],
    );
    if (exportDirectory != null) {
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(
          font: ForumFont.openSans,
          interfaceFont: ForumFont.openSans,
        ),
      );
      await tester.pumpAndSettle();
    }
    await _tapDockTab(tester, 'panel/chat');
    shell.openChatChannel(10);
    await tester.pumpAndSettle();
    final messages = find.byType(DMessageScrollerViewport);
    final scroll = tester
        .widget<DMessageScrollerViewport>(messages)
        .scrollController!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(scroll.position.maxScrollExtent, greaterThan(180));
    expect(
      scroll.position.maxScrollExtent,
      lessThan(scroll.position.viewportDimension),
    );
    // Exercise less overflow than an ordinary page's 120px cutoff as well as
    // less than two screens. Only this active channel should set the policy.
    tester.view.physicalSize = Size(
      phone.width,
      phone.height + scroll.position.maxScrollExtent - 100,
    );
    await tester.pumpAndSettle();
    expect(scroll.position.maxScrollExtent, closeTo(100, .01));
    scroll.jumpTo(scroll.position.maxScrollExtent - 10);
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('content-header-title-action'));
    expect(title.hitTestable(), findsOneWidget);
    await capture('shown');
    await tester.timedDrag(
      messages,
      const Offset(0, -80),
      const Duration(milliseconds: 1000),
    );
    await tester.pumpAndSettle();
    expect(
      title.hitTestable(),
      findsNothing,
      reason:
          'offset=${scroll.offset}, max=${scroll.position.maxScrollExtent}, chrome=${DScrollChrome.maybeOf(tester.element(messages))?.hiddenFraction}',
    );
    expect(
      find.byKey(const ValueKey('mobile-mode-topics')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile-dock-reveal')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-composer-send')).hitTestable(),
      findsOneWidget,
    );
    await capture('hidden');
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'channel scrolling retracts navigation and keeps Send available',
    (tester) async {
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
      final topics = find.byKey(const ValueKey('mobile-mode-topics'));
      final send = find.byKey(const ValueKey('chat-composer-send'));
      final originalSend = tester.getRect(send);
      final originalBar = tester.getRect(_bar);
      final scroll = tester
          .widget<DMessageScrollerViewport>(messages)
          .scrollController!;
      scroll.jumpTo(700);
      await tester.pumpAndSettle();
      await _chatWheel(tester, messages, 160);
      expect(topics.hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey('content-header-title-action')).hitTestable(),
        findsNothing,
      );
      expect(send.hitTestable(), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(ComposerEditor),
          matching: find.byType(TextField),
        ),
        'Send remains available',
      );
      await tester.pumpAndSettle();
      expect(send.hitTestable(), findsOneWidget);
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
      // Sending refocuses the full composer. Resume reading before checking
      // the shared scroll reversal slack.
      expect(topics.hitTestable(), findsNothing);
      tester
          .widget<ComposerEditor>(find.byType(ComposerEditor))
          .composer
          .focus
          .unfocus();
      await tester.pumpAndSettle();
      await _chatWheel(tester, messages, 160);
      await _chatWheel(tester, messages, -20);
      expect(topics.hitTestable(), findsNothing);
      expect(send.hitTestable(), findsOneWidget);
      // Reverse past the shared chrome's 40px slack.
      await _chatWheel(tester, messages, -80);
      expect(topics.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('content-header-title-action')).hitTestable(),
        findsOneWidget,
      );
      final restoredSend = tester.getRect(send);
      expect(restoredSend.size, originalSend.size);
      expect(restoredSend.left, originalSend.left);
      // Floating-dock clearance is measured to half a logical pixel.
      expect(restoredSend.top, closeTo(originalSend.top, .5));
      expect(tester.getRect(_bar), originalBar);
      expect(tester.takeException(), isNull);
    },
  );

  for (final thread in [false, true]) {
    for (final readOnly in [false, true]) {
      _mobileTest(
        '${thread ? 'thread' : 'public channel'} scrolling shares topic header '
        'visibility (read only: $readOnly)',
        (tester) async {
          final shell = await pumpMobileShellFixture(
            tester,
            conversations: ChatChannels(
              public: [
                ChatChannel(
                  id: 10,
                  title: 'Support',
                  kind: ChatChannelKind.category,
                  status: readOnly
                      ? ChatChannelStatus.readOnly
                      : ChatChannelStatus.open,
                  membership: const ChatMembership(following: true),
                  threadingEnabled: true,
                ),
              ],
              direct: const [],
            ),
            chatThread: thread
                ? const ChatThread(
                    id: 3,
                    channelId: 10,
                    title: 'Support thread',
                    status: 'open',
                    replyCount: 49,
                  )
                : null,
            chatMessages: [
              for (var id = 1; id <= 50; id++)
                ChatMessage(
                  id: id,
                  channelId: 10,
                  threadId: thread ? 3 : null,
                  cooked: '<p>Scrollable message $id</p>',
                  author: ChatMessageAuthor(
                    id: id % 2 + 1,
                    username: 'reader${id % 2}',
                  ),
                  createdAt: DateTime(2026, 10, 1).add(Duration(minutes: id)),
                ),
            ],
          );
          await _tapDockTab(tester, 'panel/chat');
          if (thread) {
            shell.openChatThread(siteUrl: _site, channelId: 10, threadId: 3);
          } else {
            shell.openChatChannel(10);
          }
          await tester.pumpAndSettle();
          final messages = find.byType(DMessageScrollerViewport);
          expect(messages, findsOneWidget);
          final scroll = tester
              .widget<DMessageScrollerViewport>(messages)
              .scrollController!;
          final topics = find.byKey(const ValueKey('mobile-mode-topics'));
          final panel = find.byKey(const ValueKey('mobile-content-panel'));
          final originalBar = tester.getRect(_bar);
          final title = find.text(thread ? 'Support thread' : 'Support');
          final originalPanel = tester.getRect(panel);
          final send = find.byKey(const ValueKey('chat-composer-send'));
          expect(send, readOnly ? findsNothing : findsOneWidget);
          final streamElement = tester.element(messages);
          scroll.jumpTo(700);
          await tester.pumpAndSettle();
          expect(title.hitTestable(), findsOneWidget);
          await tester.timedDrag(
            messages,
            const Offset(0, -160),
            const Duration(milliseconds: 300),
          );
          await tester.pumpAndSettle();
          expect(topics.hitTestable(), findsNothing);
          expect(title.hitTestable(), findsNothing);
          expect(send.hitTestable(), readOnly ? findsNothing : findsOneWidget);
          expect(tester.getRect(panel).bottom, originalPanel.bottom);
          expect(tester.element(messages), same(streamElement));
          await _chatWheel(tester, messages, -20);
          expect(topics.hitTestable(), findsNothing);
          expect(title.hitTestable(), findsNothing);
          await _chatWheel(tester, messages, -80);
          expect(topics.hitTestable(), findsOneWidget);
          expect(title.hitTestable(), findsOneWidget);
          expect(tester.getRect(_bar), originalBar);
          // The physical bottom reveals navigation even without reversing.
          await _chatWheel(tester, messages, 100);
          expect(title.hitTestable(), findsNothing);
          await _chatWheel(tester, messages, 2000);
          expect(scroll.offset, 0);
          expect(title.hitTestable(), findsOneWidget);
          expect(topics.hitTestable(), findsOneWidget);
          await tester.tap(topics);
          await tester.pumpAndSettle();
          expect(shell.mobileNavigation.tab, MobileTab.topics);
          expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  _mobileTest('Voice keeps the redesigned Chat inbox and its filters', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, voice: true, chatUnreadCount: 4);
    await _tapDockTab(tester, 'panel/chat');
    await tester.pumpAndSettle();

    expect(find.byType(ChatMobileSidebar), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-presence-menu')), findsOneWidget);
    // Compact presets grow with the mobile text baseline. Their hit areas
    // must still match the painted controls exactly.
    for (final (key, size) in [
      ('chat-inbox-activity-filter', DControlSize.filter),
      ('chat-inbox-kind-filter', DControlSize.filter),
      ('user-presence-menu', DControlSize.filter),
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
      final context = tester.element(control);
      expect(
        tester.getSize(surface).height,
        DControlStyle.scaledHeight(size, MediaQuery.textScalerOf(context)),
        reason: key,
      );
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

    await _tapDockTab(tester, 'panel/chat');
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
    await _tapDockTab(tester, 'panel/chat');
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
    // Muting does not override unread tracking supplied by the server.
    expect(find.text('9 messages'), findsOneWidget);
    expect(
      find.descendant(
        of: row(1),
        matching: find.text('you: Will follow up in the morning.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row(5),
        matching: find.text('Will follow up in the morning.'),
      ),
      findsOneWidget,
    );
    await _selectChatActivity(tester, 'Unread');
    expect(row(2), findsOneWidget);
    expect(row(3), findsOneWidget);
    expect(row(4), findsOneWidget);
    for (final id in [1, 5]) {
      expect(row(id), findsNothing);
    }
    await _selectChatKind(tester, 'Channels');
    expect(row(2), findsOneWidget);
    expect(row(3), findsOneWidget);
    expect(row(4), findsNothing);
    await _selectChatKind(tester, 'Direct messages');
    expect(row(2), findsNothing);
    expect(row(3), findsNothing);
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
      await _tapDockTab(tester, 'panel/chat');
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('user-presence-menu'));
      expect(tester.widget<DButton>(trigger).size, DControlSize.filter);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.text('Set a custom status'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Pause notifications'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();
      expect(shell.hidePresenceFor(_site), isTrue);
      final presence = find.byKey(const ValueKey('user-menu-hide-presence'));
      expect(
        tester.widget<DDropdownMenuCheckboxItem>(presence).checked,
        isFalse,
      );
      await tester.tap(presence);
      await tester.pumpAndSettle();
      expect(shell.hidePresenceFor(_site), isFalse);
      await tester.tap(find.text('Pause notifications'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('do-not-disturb-halfHour')),
        findsOneWidget,
      );
      await tester.tap(find.text('30 minutes'));
      await tester.pumpAndSettle();
      expect(
        shell.doNotDisturb.stateFor(_site).isActiveAt(DateTime.now()),
        isTrue,
      );
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpause notifications'));
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
    await _tapDockTab(tester, 'panel/chat');
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
    await _tapDockTab(tester, 'panel/chat');
    await tester.pumpAndSettle();
    expectChatActive(true);
    await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
    await tester.pumpAndSettle();
    expectChatActive(false);
    expect(tester.element(chatPanel), same(initialPanel));
    expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
  });

  for (final bottom in [0.0, 34.0]) {
    _mobileTest(
      'all mobile roots run their body to the screen edge ($bottom)',
      (tester) async {
        tester.view.padding = FakeViewPadding(top: 44, bottom: bottom);
        tester.view.viewPadding = FakeViewPadding(top: 44, bottom: bottom);
        final shell = await pumpMobileShellFixture(tester);
        void expectBody() {
          final body = find.byKey(const ValueKey('mobile-content-panel'));
          expect(tester.getRect(body).bottom, phone.height);
          expect(tester.getRect(body).top, tester.getRect(_header).bottom + 6);
          final surface = find
              .descendant(of: body, matching: find.byType(DPageSurface))
              .first;
          _expectPageRadius(tester.widget<DPageSurface>(surface).borderRadius);
          final page = tester.element(body);
          expect(MediaQuery.paddingOf(page).bottom, bottom);
          final dock = tester.getRect(
            find.byKey(const ValueKey('mobile-dock-surface')),
          );
          // The app's baseline text scale grows the 50 row a little.
          final growth = MediaQuery.textScalerOf(page).scale(11) - 11;
          final row = tester.getRect(
            find.byKey(const ValueKey('mobile-mode-topics')),
          );
          expect(row.height, closeTo(50 + growth, .01));
          expect(row.top, closeTo(dock.top + 6, .01));
          if (bottom > 0) {
            // The bar runs the screen's width down to its foot, its row held
            // 30 above the bottom edge by its own padding.
            expect(dock.left, 0);
            expect(dock.right, phone.width);
            expect(dock.bottom, closeTo(phone.height, .01));
            expect(dock.height, closeTo(86 + growth, .01));
            expect(row.bottom, closeTo(phone.height - 30, .01));
            expect(
              DScrollChrome.bottomInsetOf(page),
              closeTo(dock.height + 6, .01),
            );
          } else {
            expect(dock.left, 6);
            expect(dock.right, phone.width - 6);
            expect(dock.bottom, closeTo(phone.height - 6, .01));
            expect(dock.height, closeTo(62 + growth, .01));
            expect(
              DScrollChrome.bottomInsetOf(page),
              closeTo(dock.height + 12, .01),
            );
          }
        }

        expectBody();
        await _tapDockTab(tester, 'destination/user-bookmarks');
        expectBody();
        await _tapDockTab(tester, 'panel/chat');
        expectBody();
        shell.selectMobileDestination(
          MobileTab.users,
          const SidebarDestination(
            id: 'users',
            label: 'Users',
            icon: DIcons.users,
          ),
        );
        await tester.pumpAndSettle();
        expectBody();
        expect(find.byType(UsersPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _mobileTest('the phone ground is the bar\'s own fill', (tester) async {
    final shell = await pumpMobileShellFixture(tester);
    for (final mode in [AppThemeMode.dark, AppThemeMode.light]) {
      await shell.forumSettings.setThemeMode(_site, mode);
      await tester.pumpAndSettle();
      final canvas = find.byKey(const ValueKey('forum-window-canvas'));
      final ground =
          (tester.widget<DecoratedBox>(canvas).decoration as BoxDecoration)
              .color!;
      final bar = find.byKey(const ValueKey('mobile-dock-surface'));
      final fill =
          (tester.widget<AnimatedContainer>(bar).decoration as BoxDecoration)
              .color!;
      final tokens = DTokens.of(tester.element(canvas));
      expect(ground, tokens.wellFill, reason: mode.name);
      expect(fill, ground, reason: mode.name);
      expect(ground.a, 1);
      expect(
        Oklab.of(ground).lightness,
        closeTo(Oklab.of(tokens.background).lightness - .08, .005),
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final mode in [AppThemeMode.dark, AppThemeMode.light]) {
    for (final scale in [1.0, 1.5]) {
      _mobileTest(
        'body and plugin page keep their corners and dock at $scale text '
        '${mode.name} flat',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _loadChromeCaptureFonts(tester);
          final shell = await pumpMobileShellFixture(tester);
          await shell.forumSettings.setThemeMode(_site, mode);
          await shell.forumSettings.setThemes(
            _site,
            ForumThemePreferences.preset('dracula'),
          );
          await shell.forumSettings.setShared(
            shell.forumSettings.shared.copyWith(),
          );
          await tester.pumpAndSettle();
          final body = find.byKey(const ValueKey('mobile-content-panel'));
          final bodyElement = tester.element(body);
          BorderRadiusGeometry? bodyRadius() => tester
              .widget<DPageSurface>(
                find
                    .descendant(of: body, matching: find.byType(DPageSurface))
                    .first,
              )
              .borderRadius;

          final topics = find.byKey(const ValueKey('mobile-mode-topics'));
          final label = find.descendant(
            of: topics,
            matching: find.text('Topics'),
          );
          final glyph = find.descendant(
            of: topics,
            matching: find.byType(DIcon),
          );
          final button = find.descendant(
            of: topics,
            matching: find.byType(DButton),
          );
          final before = (
            dockHeight: tester.getSize(_bar).height,
            buttonHeight: tester.getSize(button).height,
            labelSize: tester.getSize(label),
            glyphSize: tester.getSize(glyph),
          );
          _expectPageRadius(bodyRadius());
          await _captureChrome(tester, 'dock-topics-$scale-${mode.name}-flat');
          shell.openChatChannel(10);
          await tester.pumpAndSettle();
          expect(tester.element(body), same(bodyElement));
          expect(tester.getSize(_bar).height, before.dockHeight);
          expect(tester.getSize(button).height, before.buttonHeight);
          expect(tester.getSize(label), before.labelSize);
          expect(tester.getSize(glyph), before.glyphSize);
          _expectPageRadius(bodyRadius());
          final sheet = find
              .descendant(
                of: find.byType(DSheetContent),
                matching: find.byType(DPageSurface),
              )
              .first;
          _expectPageRadius(tester.widget<DPageSurface>(sheet).borderRadius);
          await _captureChrome(tester, 'dock-chat-$scale-${mode.name}-flat');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  _mobileTest('Topics shares the rounded inset mobile body', (tester) async {
    await _loadChromeCaptureFonts(tester);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
    final shell = await pumpMobileShellFixture(
      tester,
      size: const Size(390, 844),
    );
    for (final mode in [AppThemeMode.dark, AppThemeMode.light]) {
      await shell.forumSettings.setThemeMode(_site, mode);
      await shell.forumSettings.setThemes(
        _site,
        ForumThemePreferences.preset('dracula'),
      );
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(
          font: ForumFont.lato,
          interfaceFont: ForumFont.lato,
        ),
      );
      await tester.pumpAndSettle();
      await _captureChrome(tester, 'topics-${mode.name}-flat');
      final body = find.byKey(const ValueKey('mobile-content-panel'));
      expect(tester.getRect(body).bottom, 844);
      expect(tester.getRect(body).top, tester.getRect(_header).bottom + 6);
      final surface = find
          .descendant(of: body, matching: find.byType(DPageSurface))
          .first;
      _expectPageRadius(tester.widget<DPageSurface>(surface).borderRadius);
      expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    if (const bool.fromEnvironment('captureMobileChrome')) {
      final menu = find.byKey(const ValueKey('mobile-menu-button'));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await _captureChrome(tester, 'navigation-open');
      await tester.tap(menu);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(1, 350));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      final navigation = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('mobile-navigation-page')),
      );
      final panel = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('mobile-navigation-panel')),
      );
      final panelBottom = panel
          .localToGlobal(
            panel.size.bottomLeft(Offset.zero),
            ancestor: navigation,
          )
          .dy;
      expect(navigation.size.height - panelBottom, 6 + 34 / 2);
      expect(tester.getRect(find.byType(DScrollChrome)).bottom, 810);
      await _captureChrome(tester, 'navigation-preview');
      await gesture.cancel();
      await tester.pumpAndSettle();
    }
  });

  _mobileTest(
    'reader compacts and reveals its header without changing topic or viewport',
    (tester) async {
      await _loadChromeCaptureFonts(tester);

      final shell = await pumpMobileShellFixture(
        tester,
        topics: const bool.fromEnvironment('captureMobileChrome')
            ? [
                const Topic(
                  id: 7,
                  title: 'A long community discussion',
                  slug: 'shared',
                ),
                for (var id = 8; id < 30; id++)
                  Topic(
                    id: id,
                    title: 'Community discussion $id',
                    slug: 'discussion-$id',
                  ),
              ]
            : null,
        topic: topicPayload(
          id: 7,
          title: 'A long community discussion',
          canCreatePost: true,
          tags: const [
            TopicTag(id: 1, name: 'support'),
            TopicTag(id: 2, name: 'design'),
            TopicTag(id: 3, name: 'mobile'),
          ],
          posts: [
            for (var id = 1; id <= 50; id++)
              Post(
                id: id,
                postNumber: id,
                username: 'reader',
                createdAt: DateTime.utc(2026, 9, 1, 0, id),
                cooked:
                    '<p>Post $id discusses mobile navigation, reading and the community.</p>',
              ),
          ],
        ),
      );
      if (const bool.fromEnvironment('captureMobileChrome')) {
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await shell.forumSettings.setShared(
          shell.forumSettings.shared.copyWith(
            font: ForumFont.lato,
            interfaceFont: ForumFont.lato,
          ),
        );
        await tester.pumpAndSettle();
      }
      Future<void> capture(String name) => _captureChrome(tester, name);

      await capture('root');
      final controls = tester.getRect(
        find.byKey(const ValueKey('topic-list-feed-row')),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('topic-card-7'))).top,
        closeTo(controls.bottom + 14, 1),
      );
      final mobileSurface = find
          .descendant(
            of: find.byKey(const ValueKey('mobile-content-panel')),
            matching: find.byType(DPageSurface),
          )
          .first;
      expect(tester.widget<DPageSurface>(mobileSurface).framed, isTrue);
      _expectPageRadius(
        tester.widget<DPageSurface>(mobileSurface).borderRadius,
      );
      await tester.tap(find.byKey(const ValueKey('topic-card-7')));
      await tester.pumpAndSettle();
      expect(tester.widget<DPageSurface>(mobileSurface).framed, isTrue);
      expect(
        tester.widget<DPageSurface>(mobileSurface).backgroundColor,
        Colors.transparent,
      );
      final sheetSurface = find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(DPageSurface),
          )
          .first;
      _expectPageRadius(tester.widget<DPageSurface>(sheetSurface).borderRadius);
      final reader = find.byType(TopicView);
      final element = tester.element(reader);
      final viewport = tester.getRect(reader);
      final expandedPageRadius = tester
          .widget<DPageSurface>(sheetSurface)
          .borderRadius;
      await capture('reader-full');
      final list = find
          .descendant(of: reader, matching: find.byType(CustomScrollView))
          .first;
      await tester.drag(list, const Offset(0, -850));
      if (const bool.fromEnvironment('captureMobileChrome')) {
        for (var frame = 0; frame < 24; frame++) {
          await tester.pump(const Duration(milliseconds: 33));
          await capture('fold-${frame.toString().padLeft(2, '0')}');
        }
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-header-compact-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-dock-reveal')).hitTestable(),
        findsOneWidget,
      );
      final controller = tester.widget<CustomScrollView>(list).controller!;
      final offset = controller.offset;
      expect(
        tester.widget<DPageSurface>(sheetSurface).borderRadius,
        expandedPageRadius,
      );
      await capture('reader-folded');
      await tester.tap(find.byKey(const ValueKey('mobile-dock-reveal')));
      if (const bool.fromEnvironment('captureMobileChrome')) {
        for (var frame = 0; frame < 24; frame++) {
          await tester.pump(const Duration(milliseconds: 33));
          await capture('unfold-${frame.toString().padLeft(2, '0')}');
        }
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-header-compact-layout')),
        findsOneWidget,
      );
      expect(controller.offset, offset);
      expect(tester.getRect(reader), viewport);
      expect(tester.element(reader), same(element));
      expect(shell.currentContent?.topicId, 7);
      expect(
        find.byKey(const ValueKey('topic-more-actions')).hitTestable(),
        findsOneWidget,
      );
      await capture('reader-compact');
      await tester.tap(find.byKey(const ValueKey('topic-more-actions')));
      await tester.pumpAndSettle();
      final menuSheet = find
          .ancestor(
            of: find.byType(DDropdownMenuContent),
            matching: find.byType(DSheetContent),
          )
          .first;
      expect(
        tester.widget<DSheetContent>(menuSheet).variant,
        DSheetVariant.adaptiveMenu,
      );
      final menuBounds = tester.getRect(menuSheet);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      // A sheet at its end keeps to the screen's sides.
      expect(menuBounds.left, 0);
      expect(menuBounds.right, screen.width);
      expect(menuBounds.top, greaterThan(screen.height / 2));
      expect(menuBounds.bottom, lessThanOrEqualTo(screen.height - 6));
      expect(
        find.descendant(of: menuSheet, matching: find.byType(DSheetHeader)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('topic-close-reader')), findsNothing);
      expect(find.text('Share topic').hitTestable(), findsOneWidget);
      expect(find.text('Mark unread').hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-header-taxonomy')), findsNothing);
      expect(controller.offset, offset);
      expect(shell.currentContent?.topicId, 7);
      await capture('reader-compact-menu-sheet');
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(controller.offset, offset);
      await tester.tap(find.byKey(const ValueKey('topic-more-actions')));
      await tester.pumpAndSettle();
      final menuHandle = find.descendant(
        of: menuSheet,
        matching: find.byKey(const ValueKey('sheet-drag-handle')),
      );
      expect(tester.getSize(menuHandle), const Size(36, 5));
      await tester.drag(menuHandle, const Offset(0, 220));
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(controller.offset, offset);
      expect(shell.currentContent?.topicId, 7);
      // Dismissal restores focus to More. Leave the header before restoring the
      // full layout, so a keyboard user's focused control is not replaced.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-header-compact-layout')),
        findsNothing,
      );
      expect(tester.getRect(reader), viewport);
      expect(tester.takeException(), isNull);
    },
  );

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
      for (final tab in ['topics', 'panel/chat', 'more']) {
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
        const iconHeight = 22.36;
        expect(tester.getSize(icon).height, closeTo(iconHeight, .01));
        final glyph = find.descendant(
          of: icon,
          matching: find.byType(TintedIconGlyph),
        );
        expect(tester.getSize(glyph).height, closeTo(iconHeight, .01));
      }
      expect(find.text('Topics'), findsWidgets);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('More'), findsNothing);
      expect(
        find.descendant(of: _bar, matching: find.byType(DTabList<String>)),
        findsNothing,
      );
      for (final key in [
        UserMenuButton.bellKey,
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
      expect(menu.center.dx, 53 / 2);
      expect(identity.left, 53 + 10);
      expect(bell.left - search.right, closeTo(10, .001));
      expect(find.byKey(UserMenuButton.avatarKey), findsNothing);
      final menuIcon = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile-menu-button')),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon.name == 'bars',
          ),
        ),
      );
      expect(menuIcon.center.dx, menu.center.dx);
      expect(
        tester.getSize(find.byKey(const ValueKey('forum-identity-logo'))),
        const Size.square(28),
      );
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'ordinary chat activity uses a dot beside the label within one tap target',
    (tester) async {
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
      expect(tester.widget(badge), isA<DNotificationDot>());
      expect(find.text('32'), findsNothing);
      await tester.tapAt(tester.getCenter(badge));
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.tab, const MobileTab.panel('chat'));
      expectPosition();
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'whole dock destination selects and clears without changing bounds',
    (tester) async {
      await pumpMobileShellFixture(tester);
      final button = find.byKey(const ValueKey('mobile-mode-panel/chat'));
      final bounds = tester.getRect(button);
      expect(tester.widget<DMobileDockItem>(button).selected, isFalse);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.widget<DMobileDockItem>(button).selected, isTrue);
      expect(tester.getRect(button), bounds);
      expect(tester.getSize(button).height, closeTo(52.36, .01));

      await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
      await tester.pumpAndSettle();
      expect(tester.widget<DMobileDockItem>(button).selected, isFalse);
      expect(tester.getRect(button), bounds);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('the current place is marked on the bar\'s top edge', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester);
    final surface = find.byKey(const ValueKey('mobile-dock-surface'));
    List<Rect> marks() => [
      for (final element
          in find
              .descendant(
                of: _bar,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is AnimatedContainer &&
                      widget.key is ValueKey<String> &&
                      (widget.key! as ValueKey<String>).value.startsWith(
                        'mobile-dock-mark-',
                      ),
                ),
              )
              .evaluate())
        tester.getRect(find.byElementPredicate((e) => e == element)),
    ].where((rect) => rect.width > 0).toList();
    void expectMarkOver(String tab) {
      final shown = marks();
      expect(shown, hasLength(1), reason: tab);
      expect(shown.single.width, closeTo(28, .01), reason: tab);
      expect(shown.single.height, closeTo(4, .01), reason: tab);
      expect(
        shown.single.top,
        closeTo(tester.getRect(surface).top, .01),
        reason: tab,
      );
      expect(
        shown.single.center.dx,
        closeTo(
          tester.getCenter(find.byKey(ValueKey('mobile-mode-$tab'))).dx,
          .01,
        ),
        reason: tab,
      );
    }

    expectMarkOver('topics');
    await _tapDockTab(tester, 'panel/chat');
    expectMarkOver('panel/chat');
    await _tapDockTab(tester, 'users');
    expectMarkOver('users');
    expect(tester.takeException(), isNull);
  });

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    _mobileTest('mobile sidebar mockup parity ${mode.name} flat', (
      tester,
    ) async {
      if (const bool.fromEnvironment('captureMobileSidebar')) {
        await tester.runAsync(() async {
          final manifest =
              jsonDecode(await rootBundle.loadString('FontManifest.json'))
                  as List;
          for (final entry in manifest.cast<Map<String, dynamic>>()) {
            final loader = FontLoader(entry['family'] as String);
            for (final face
                in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
              loader.addFont(rootBundle.load(face['asset'] as String));
            }
            await loader.load();
          }
        });
      }
      final shell = await pumpMobileShellFixture(tester, voice: true);
      await shell.forumSettings.setThemeMode(_site, mode);
      await shell.forumSettings.setThemes(
        _site,
        ForumThemePreferences.preset('dracula'),
      );
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(
          font: const bool.fromEnvironment('captureMobileSidebar')
              ? ForumFont.lato
              : null,
          interfaceFont: const bool.fromEnvironment('captureMobileSidebar')
              ? ForumFont.lato
              : null,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
      await tester.pumpAndSettle();
      final route = shell.currentContent;
      final tab = shell.mobileNavigation.tab;
      final switcher = find.byKey(const ValueKey('sidebar-panel-tabs'));
      final list = find.descendant(
        of: switcher,
        matching: find.byType(DTabList<String>),
      );
      expect(tester.widget<DTabList<String>>(list).expandSelected, isTrue);
      final panel = tester.getRect(
        find.byKey(const ValueKey('mobile-navigation-panel')),
      );
      final frame = find
          .descendant(
            of: find.byKey(const ValueKey('mobile-navigation-panel')),
            matching: find.byType(DPageSurface),
          )
          .first;
      expect(
        (tester.widget<DPageSurface>(frame).borderRadius!
                as BorderRadiusDirectional)
            .topStart,
        const Radius.circular(DRadius.panel),
      );
      expect(tester.widget<DPageSurface>(frame).border, isFalse);
      expect(tester.getRect(list).left, panel.left + 8);
      expect(tester.getRect(list).right, panel.right - 8);
      expect(tester.getRect(list).top, greaterThan(panel.center.dy));
      expect(find.text('Watercooler'), findsNothing);

      Future<void> capture(String state) async {
        if (!const bool.fromEnvironment('captureMobileSidebar')) return;
        await tester.runAsync(() async {
          final builder = ui.SceneBuilder();
          tester.binding.renderViews.first.debugLayer!.addToScene(builder);
          final scene = builder.build();
          final image = await scene.toImage(390, 844);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final platform = Theme.of(tester.element(_header)).platform.name;
          await File(
            '/private/tmp/mobile-sidebar-$platform-${mode.name}-flat-$state.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          scene.dispose();
        });
      }

      await capture('forum');
      await tester.tap(find.byKey(const ValueKey('sidebar-panel-switch-chat')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-inbox-activity-filter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat-inbox-channel-9')),
        findsOneWidget,
      );
      expect(find.text('Voice rooms'), findsOneWidget);
      expect(find.text('Watercooler'), findsOneWidget);
      expect(find.byType(ChatMobileSidebar), findsNothing);
      for (final label in ['Chats', 'Channels', 'Threads']) {
        expect(sidebarDestination(label), findsNothing);
      }
      expect(shell.currentContent, same(route));
      expect(shell.mobileNavigation.tab, tab);
      expect(shell.mobileNavigation.sidebarOpen, isTrue);
      await capture('chat');
      await tester.tap(
        find.byKey(const ValueKey('sidebar-panel-switch-shortcuts')),
      );
      await tester.pumpAndSettle();
      expect(sidebarDestination('Handbook'), findsOneWidget);
      expect(find.text('Watercooler'), findsNothing);
      expect(find.byKey(const ValueKey('chat-inbox-channel-9')), findsNothing);
      await capture('shortcuts');
      await tester.tap(find.byKey(const ValueKey('sidebar-panel-switch-main')));
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsOneWidget);
      expect(sidebarDestination('Handbook'), findsNothing);
      expect(shell.currentContent, same(route));
      expect(tester.takeException(), isNull);
    });
  }

  for (final conversation in ['channel', 'direct message', 'thread']) {
    _mobileTest('opening navigation from a $conversation selects Chat', (
      tester,
    ) async {
      final direct = conversation == 'direct message';
      final channel = ChatChannel(
        id: 10,
        title: 'Support',
        kind: direct ? ChatChannelKind.directMessage : ChatChannelKind.category,
        membership: const ChatMembership(following: true),
        threadingEnabled: true,
      );
      final shell = await pumpMobileShellFixture(
        tester,
        conversations: ChatChannels(
          public: [if (!direct) channel],
          direct: [if (direct) channel],
        ),
        chatThread: conversation == 'thread'
            ? const ChatThread(
                id: 3,
                channelId: 10,
                title: 'Support thread',
                status: 'open',
                replyCount: 0,
              )
            : null,
      );
      final menu = find.byKey(const ValueKey('mobile-menu-button'));
      final tabs = find.byKey(const ValueKey('sidebar-panel-tabs'));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(tester.widget<DTabs<String>>(tabs).value, 'forum');
      await tester.tap(menu);
      await tester.pumpAndSettle();

      if (conversation == 'thread') {
        shell.openChatThread(siteUrl: _site, channelId: 10, threadId: 3);
      } else {
        shell.openChatChannel(10);
      }
      await tester.pumpAndSettle();
      final route = shell.currentContent;
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(tester.widget<DTabs<String>>(tabs).value, 'chat');
      expect(
        find.byKey(const ValueKey('chat-inbox-channel-10')),
        findsOneWidget,
      );
      expect(shell.currentContent, route);

      await tester.tap(find.byKey(const ValueKey('sidebar-panel-switch-main')));
      await tester.pumpAndSettle();
      expect(tester.widget<DTabs<String>>(tabs).value, 'forum');
      expect(shell.currentContent, route);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(tester.widget<DTabs<String>>(tabs).value, 'chat');
      expect(shell.currentContent, route);
      expect(tester.takeException(), isNull);
    });
  }

  _mobileTest('mobile sidebar hides unavailable Chat and opens conversations', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, chat: false);
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sidebar-panel-switch-chat')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sidebar-panel-switch-main')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sidebar-panel-switch-shortcuts')),
      findsOneWidget,
    );
    // Replace the account fixture, then open Chat from the navigation switch.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final shell = await pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-panel-switch-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-inbox-channel-10')));
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(shell.currentContent?.id, 'chat-c-10');
    expect(find.byType(InstanceRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'navigation page exposes forum identity, destinations and custom Shortcuts',
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
        Colors.transparent,
      );
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byType(ForumIdentityHeader),
        ),
        findsOneWidget,
      );
      for (final label in ['Topics', 'Messages', 'Users']) {
        expect(sidebarDestination(label), findsOneWidget);
      }
      expect(sidebarDestination('Handbook'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile-navigation-page')),
          matching: find.text('Categories'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('sidebar-panel-switch-shortcuts')),
      );
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
        expect(navigation.top + 6, content.top);
        expect(navigation.bottom, content.bottom);
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

  for (final (bottom, keyboard) in [(0.0, 0.0), (34.0, 0.0), (0.0, 280.0)]) {
    _mobileTest(
      'navigation panel consumes bottom safe area once ($bottom, $keyboard)',
      (tester) async {
        tester.view.padding = FakeViewPadding(top: 44, bottom: bottom);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        final shell = await pumpMobileShellFixture(tester);
        final menu = find.byKey(const ValueKey('mobile-menu-button'));
        await tester.tap(menu);
        await tester.pumpAndSettle();
        final page = tester.getRect(
          find.byKey(const ValueKey('mobile-navigation-page')),
        );
        final panel = tester.getRect(
          find.byKey(const ValueKey('mobile-navigation-panel')),
        );
        final frame = find
            .descendant(
              of: find.byKey(const ValueKey('mobile-navigation-panel')),
              matching: find.byType(DPageSurface),
            )
            .first;
        // As low as a sheet at its end: 6 past half the foot, the outer
        // foot corner following the screen's 55 curve, 32 at a foot of 34.
        final lift = 6 + bottom / 2;
        expect(
          tester.widget<DPageSurface>(frame).borderRadius,
          BorderRadiusDirectional.only(
            topStart: const Radius.circular(DRadius.panel),
            topEnd: const Radius.circular(DRadius.panel),
            bottomStart: const Radius.circular(DRadius.panel),
            bottomEnd: Radius.circular(bottom > 0 ? 55 - lift : DRadius.panel),
          ),
        );
        expect(tester.widget<DPageSurface>(frame).border, isFalse);
        expect(page.bottom - panel.bottom, lift);
        expect(page.bottom, phone.height - keyboard - (keyboard > 0 ? 2 : 0));
        expect(panel.top - page.top, 6);
        final rail = tester.getRect(find.byType(InstanceRail));
        expect(rail.bottom, page.bottom, reason: 'the rail runs to the foot');
        final railColumn = tester.getRect(
          find
              .descendant(
                of: find.byType(InstanceRail),
                matching: find.byType(Column),
              )
              .first,
        );
        expect(rail.bottom - railColumn.bottom, bottom / 2 + 10);
        expect(panel.left - rail.right, 6);
        expect(page.right - panel.right, 6);
        final menuBounds = tester.getRect(menu);
        expect(menuBounds.center.dx, closeTo(rail.center.dx, .001));
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(shell.mobileNavigation.sidebarOpen, isFalse);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('mobile-navigation-panel'))),
          panel,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 430.0, 600.0]) {
    _mobileTest('navigation uses the full $width viewport with large text', (
      tester,
    ) async {
      await pumpMobileShellFixture(tester, size: Size(width, 844));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('mobile-content-panel')),
      );
      final content = tester.getRect(find.byType(MainContent));
      expect(panel.left, 0);
      expect(panel.right, width);
      expect(panel.width, width);
      expect(content.left, greaterThanOrEqualTo(0));
      expect(content.right, lessThanOrEqualTo(width));
      await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
      await tester.pumpAndSettle();
      final navigation = tester.getRect(
        find.byKey(const ValueKey('mobile-navigation-page')),
      );
      expect(navigation.left, 0);
      expect(navigation.width, width);
      final rail = tester.getRect(find.byType(InstanceRail));
      expect(rail.left, 0);
      expect(rail.width, 53);
      final menu = tester.getRect(
        find.byKey(const ValueKey('mobile-menu-button')),
      );
      expect(menu.center.dx, closeTo(rail.center.dx, .001));
      final navigationPanel = tester.getRect(
        find.byKey(const ValueKey('mobile-navigation-panel')),
      );
      expect(navigationPanel.left, rail.right + 6);
      expect(navigationPanel.right, width - 6);
      expect(navigationPanel.top, navigation.top + 6);
      expect(navigationPanel.bottom, navigation.bottom - 6);
      final addButton = tester.getRect(
        find.byKey(const ValueKey('add-instance-rail-button')),
      );
      expect(addButton.left, greaterThanOrEqualTo(rail.left));
      expect(addButton.right, lessThanOrEqualTo(rail.right));
      expect(_bar, findsNothing);
      expect(find.text('Shortcuts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  _mobileTest('Forum destinations return from Chat to the Topics tab', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    await _tapDockTab(tester, 'panel/chat');
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
    expect(
      tester
          .widget<DIcon>(
            find.descendant(of: topic, matching: find.byType(DIcon)),
          )
          .icon,
      DIcons.penToSquare,
    );
    expect(tester.getRect(topic).right, lessThan(tester.getRect(_bar).right));
    expect(tester.getCenter(topic).dy, tester.getCenter(_bar).dy);
    expect(tester.widget<DButton>(topic).tooltip, 'New topic');
    await tester.tap(topic);
    await tester.pumpAndSettle();
    expect(shell.visibleComposer, isNotNull);
    shell.closeComposer();
    await tester.pumpAndSettle();
    await _tapDockTab(tester, 'panel/chat');
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

  _mobileTest('rapid root switches keep each incoming action and its target', (
    tester,
  ) async {
    // Keep destinations visible while inspecting each transition frame.
    await pumpMobileShellFixture(tester, size: const Size(700, 844));

    await _tapDockTab(tester, 'panel/chat');
    for (final (tab, key) in [
      ('messages', 'new-message-button'),
      ('panel/chat', 'mobile-panel-action'),
      ('topics', 'mobile-new-topic'),
      ('panel/chat', 'mobile-panel-action'),
      ('messages', 'new-message-button'),
    ]) {
      await _tapDockTab(tester, tab, settle: false);
      await tester.pump();
      final actions = find.byKey(ValueKey(key));
      expect(actions, findsAtLeastNWidgets(1));

      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Switch roots again before the incoming action has fully settled.
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-message-button')));
    await tester.pumpAndSettle();
    final shell = ShellScope.read(tester.element(find.byType(MobileForumRoot)));
    expect(shell.visibleComposer!.target.isPrivateMessage, isTrue);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('minimized composer and dock consume the bottom safe area once', (
    tester,
  ) async {
    await pumpMobileShellFixture(
      tester,
      topics: [
        for (var id = 7; id < 30; id++)
          Topic(id: id, title: 'Discussion $id', slug: 'discussion-$id'),
      ],
    );
    final bottom = 34.0 * tester.view.devicePixelRatio;
    tester.view.padding = FakeViewPadding(bottom: bottom);
    tester.view.viewPadding = FakeViewPadding(bottom: bottom);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpAndSettle();
    final listElement = tester.element(find.byType(TopicListView));
    expect(
      tester.getRect(find.byType(TopicListView)).bottom,
      closeTo(phone.height, .01),
    );
    await tester.tap(find.byKey(const ValueKey('mobile-new-topic')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('composer-topic-title')),
      'Keep this draft above the dock',
    );
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    final restore = find.byKey(const ValueKey('composer-restore'));
    expect(restore.hitTestable(), findsOneWidget);
    final dock = tester.getRect(
      find.byKey(const ValueKey('mobile-dock-surface')),
    );
    // The bar stays at the screen's foot, and the parked draft waits 8 over
    // it, 6 in from the screen's sides, a pill of the bar's own stock.
    expect(dock.bottom, closeTo(phone.height, .01));
    expect(dock.left, 0);
    expect(dock.right, phone.width);
    expect(tester.getRect(restore).bottom, closeTo(dock.top - 8, .01));
    expect(tester.getRect(restore).left, closeTo(6, .01));
    expect(tester.getRect(restore).right, closeTo(phone.width - 6, .01));
    final pill = tester.widget<DButton>(restore);
    expect(pill.variant, DButtonVariant.resume);
    expect(
      buttonSurface(tester, of: restore).color,
      DTokens.of(tester.element(restore)).wellFill,
    );
    expect(
      tester.getRect(find.byType(TopicListView)).bottom,
      closeTo(phone.height, .01),
    );
    expect(tester.element(find.byType(TopicListView)), same(listElement));
    final list = find
        .descendant(
          of: find.byType(TopicListView),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(tester.getRect(list).bottom, closeTo(phone.height, .01));
    await tester.drag(list, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('topic-card-29'))).bottom,
      lessThanOrEqualTo(tester.getRect(restore).top),
    );
    expect(
      find.byKey(const ValueKey('topic-card-29')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'a parked draft keeps out of a chat, whose composer stands there',
    (tester) async {
      await pumpMobileShellFixture(tester);
      await tester.tap(find.byKey(const ValueKey('mobile-new-topic')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('composer-topic-title')),
        'Parked while chatting',
      );
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      final restore = find.byKey(const ValueKey('composer-restore'));
      expect(restore.hitTestable(), findsOneWidget);
      await _tapDockTab(tester, 'panel/chat');
      await _selectChatKind(tester, 'Direct messages');
      expect(restore.hitTestable(), findsOneWidget);
      await tester.tap(find.text('sam').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-composer-send')).hitTestable(),
        findsOneWidget,
      );
      expect(restore.hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey('composer-restore'), skipOffstage: false),
        findsOneWidget,
        reason: 'the parked editor is kept while it is out of the way',
      );
      await _tapDockTab(tester, 'topics');
      expect(restore.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('every dock action takes the send button colours', (
    tester,
  ) async {
    await pumpMobileShellFixture(
      tester,
      topic: topicPayload(id: 7, canCreatePost: true),
    );
    final primary = DTokens.of(tester.element(_bar)).buttonTheme.primary;
    void expectTinted(String key) {
      final button = tester.widget<DButton>(find.byKey(ValueKey(key)));
      expect(
        (button.foregroundColor, button.backgroundColor),
        (primary.foreground, primary.background),
        reason: key,
      );
    }

    expectTinted('mobile-new-topic');
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    expectTinted('mobile-topic-reply');
    await _tapDockTab(tester, 'panel/chat');
    expectTinted('mobile-panel-action');
    await _tapDockTab(tester, 'messages');
    expectTinted('new-message-button');
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

  _mobileTest(
    'matching compose glyphs stay still and changed glyphs transition',
    (tester) async {
      final shell = await pumpMobileShellFixture(
        tester,
        size: const Size(700, 844),
      );
      final scales = find.descendant(
        of: find.byType(DActionTransition),
        matching: find.byType(ScaleTransition),
      );
      final originalTransition = tester.element(scales);
      for (final (tab, key) in [
        ('messages', 'new-message-button'),
        ('topics', 'mobile-new-topic'),
        ('messages', 'new-message-button'),
        ('topics', 'mobile-new-topic'),
      ]) {
        await _tapDockTab(tester, tab, settle: false);
        await tester.pump();
        expect(scales, findsOneWidget, reason: tab);
        final animation = tester.widget<ScaleTransition>(scales).scale;
        expect(tester.element(scales), same(originalTransition), reason: tab);
        expect(animation.value, 1, reason: tab);
        expect(find.byKey(ValueKey(key)), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 60));
        expect(animation.value, 1, reason: tab);
      }
      await _tapDockTab(tester, 'messages');
      await tester.tap(find.byKey(const ValueKey('new-message-button')));
      await tester.pumpAndSettle();
      expect(shell.visibleComposer!.target.isPrivateMessage, isTrue);
      shell.closeComposer();
      await tester.pumpAndSettle();
      // Chat creates a conversation with a plus, so it now has distinct artwork.
      await _tapDockTab(tester, 'panel/chat', settle: false);
      await tester.pump();
      expect(scales, findsNWidgets(2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-panel-action')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-new-direct-message-sheet')),
        findsOneWidget,
      );
      expect(shell.visibleComposer, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('the dock action is an icon-only circle even on a wide phone', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, size: const Size(800, 1000));
    final topic = find.byKey(const ValueKey('mobile-new-topic'));
    expect(
      find.descendant(of: topic, matching: find.text('New topic')),
      findsNothing,
    );
    expect(tester.widget<DButton>(topic).tooltip, 'New topic');
    expect(tester.getSize(topic).width, tester.getSize(topic).height);
    expect(tester.getRect(topic).right, tester.getRect(_bar).right - 6);
    await _tapDockTab(tester, 'messages', settle: false);
    await tester.pump();
    final message = find.byKey(const ValueKey('new-message-button'));
    expect(
      find.descendant(of: message, matching: find.text('New message')),
      findsNothing,
    );
    expect(tester.widget<DButton>(message).tooltip, 'New message');
    expect(tester.getSize(message).width, tester.getSize(message).height);
    await tester.pump(const Duration(milliseconds: 60));
    expect(topic, findsNothing);
    expect(
      tester
          .widget<ScaleTransition>(
            find
                .ancestor(of: message, matching: find.byType(ScaleTransition))
                .first,
          )
          .scale
          .value,
      1,
    );
    await tester.pumpAndSettle();
    expect(topic, findsNothing);
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'fallback creation stays reachable on Bookmarks and dock slots stay put',
    (tester) async {
      await pumpMobileShellFixture(tester);
      final topic = find.byKey(const ValueKey('mobile-new-topic'));
      final topics = find.byKey(const ValueKey('mobile-mode-topics'));
      final topicsRect = tester.getRect(topics);
      await _tapDockTab(tester, 'destination/user-bookmarks');
      expect(topic.hitTestable(), findsOneWidget);
      expect(tester.getRect(topics), topicsRect);
      await _tapDockTab(tester, 'topics');
      expect(topic.hitTestable(), findsOneWidget);
      // Replace an action before its entrance has finished.
      await _tapDockTab(tester, 'panel/chat', settle: false);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(topic, findsNothing);
      expect(find.byKey(const ValueKey('mobile-panel-action')), findsOneWidget);
      expect(tester.getRect(topics), topicsRect);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('Topics to topic and back animates the contextual action', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      topic: topicPayload(id: 7, canCreatePost: true),
    );
    final transition = find.descendant(
      of: _bar,
      matching: find.byType(DActionTransition),
    );
    final element = tester.element(transition);
    final dockRect = tester.getRect(
      find.byKey(const ValueKey('mobile-mode-topics')),
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
          .widget<ScaleTransition>(
            find
                .ancestor(of: reply, matching: find.byType(ScaleTransition))
                .first,
          )
          .scale
          .value,
      allOf(greaterThanOrEqualTo(0), lessThan(1)),
    );
    await tester.pumpAndSettle();
    final settled = paintedReply();
    expect(entering.width, lessThan(settled.width * .92));
    expect(entering.center.dx, closeTo(settled.center.dx, .001));
    expect(entering.center.dy, closeTo(settled.center.dy, .001));
    expect(
      tester.getRect(find.byKey(const ValueKey('mobile-mode-topics'))),
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
          .widget<ScaleTransition>(
            find
                .ancestor(of: reply, matching: find.byType(ScaleTransition))
                .first,
          )
          .scale
          .value,
      allOf(greaterThanOrEqualTo(0), lessThan(1)),
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
      Map<Key?, Rect> slots() => {
        for (final item
            in find
                .descendant(of: _bar, matching: find.byType(DMobileDockItem))
                .evaluate())
          item.widget.key: tester.getRect(
            find.byElementPredicate((e) => e == item),
          ),
      };
      // Topics has its own trailing action, Chat carries its panel action,
      // and Bookmarks the fallback one: none may move a slot.
      for (final tab in [
        'destination/user-bookmarks',
        'topics',
        'panel/chat',
        'destination/user-bookmarks',
      ]) {
        await _tapDockTab(tester, tab);
        expect(slots(), expected ?? slots(), reason: '$tab at $width');
        expected ??= slots();
      }
      // Messages has no column: it stands where the ⋮ was and the three
      // places move over for it, then take their slots back.
      await _tapDockTab(tester, 'messages');
      final shared = slots();
      expect(shared.keys, isNot(contains(const ValueKey('mobile-mode-more'))));
      final messages = shared[const ValueKey('mobile-mode-messages')]!;
      for (final key in expected!.keys) {
        if (key == const ValueKey('mobile-mode-more')) continue;
        expect(
          shared[key]!.width,
          closeTo(messages.width, .01),
          reason: '$key',
        );
        expect(
          shared[key]!.width,
          lessThan(expected[key]!.width),
          reason: '$key',
        );
      }
      await _tapDockTab(tester, 'destination/user-bookmarks');
      expect(slots(), expected, reason: 'back from messages at $width');
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

  _mobileTest(
    'Topics is titled by its feed and Filters flows with the other filters',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      final title = find.byKey(const ValueKey('topic-list-title'));
      final row = find.byKey(const ValueKey('topic-list-feed-row'));
      final tags = find.byKey(const ValueKey('topic-list-tag-filter'));
      final filters = find.byWidgetPredicate(
        (widget) => widget is TopicListFilterMenu && widget.filterKey == null,
      );
      void expectFiltersFollowTags() {
        final tag = tester.getRect(tags);
        final filter = tester.getRect(filters);
        expect(
          filter.top > tag.top ||
              (filter.top == tag.top && filter.left > tag.right),
          isTrue,
          reason: 'Filters at $filter must follow Tags at $tag',
        );
      }

      expect(tester.widget<Text>(title).data, 'Latest topics');
      expectFiltersFollowTags();

      await shell.selectTopicListMode(TopicListMode.newActivity);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(title).data, 'New topics');

      shell.openCategory(
        const TopicCategory(
          id: 42,
          name: 'Support',
          slug: 'support',
          color: '3188CC',
        ),
      );
      await tester.pumpAndSettle();
      final bell = tester.getRect(find.byType(CategoryNotificationLevelButton));
      expect(bell.right, tester.getRect(row).right);
      expect(
        bell.top,
        tester.getRect(find.byKey(const ValueKey('topic-list-feed-menu'))).top,
      );
      expectFiltersFollowTags();
      expect(tester.getRect(filters).right, lessThan(bell.left));
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'creation actions adapt their labels and remain inside the dock at every width',
    (tester) async {
      await pumpMobileShellFixture(tester, events: true);
      for (final tab in ['topics', 'messages']) {
        await _tapDockTab(tester, tab);
        final action = find.byKey(
          ValueKey(tab == 'topics' ? 'mobile-new-topic' : 'new-message-button'),
        );
        for (final width in [800.0, 600.0, 390.0, 320.0]) {
          tester.view.physicalSize = Size(width, 844);
          await tester.pumpAndSettle();
          expect(tester.widget<DButton>(action).onPressed, isNotNull);
          expect(tester.getCenter(action).dy, tester.getCenter(_bar).dy);
          expect(
            tester.getRect(action).right,
            lessThan(tester.getRect(_bar).right),
          );
          expect(tester.getSize(action).height, closeTo(52.36, .01));
          expect(
            tester.getRect(action).width,
            greaterThanOrEqualTo(tester.getRect(action).height - .001),
          );
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
        // At narrow widths More, or the page standing in for it, keeps the
        // spilled destinations and creation stays pinned on the right, the
        // two touching on the narrowest bar.
        expect(
          tester.getRect(_moreTrigger).right,
          lessThanOrEqualTo(tester.getRect(action).left + .01),
        );
        expect(find.byKey(const ValueKey('mobile-mode-users')), findsNothing);
        tester.view.physicalSize = phone;
        await tester.pumpAndSettle();
      }
    },
  );

  _mobileTest(
    'dock destinations and actions stay within their own visible bounds',
    (tester) async {
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
          final icon = find.descendant(
            of: action,
            matching: find.byType(DIcon),
          );
          final dockIcon = find.descendant(
            of: find.byKey(const ValueKey('mobile-mode-topics')),
            matching: find.byType(DIcon),
          );
          expect(tester.widget<DButton>(action).onPressed, isNotNull);
          expect(tester.getSize(action).height, closeTo(52.36, .01));
          expect(
            tester.getRect(action).width,
            greaterThanOrEqualTo(tester.getRect(action).height - .001),
          );

          const iconDifference = 0;
          expect(
            tester.getSize(icon).height,
            tester.getSize(dockIcon).height - iconDifference,
          );
          final actionLabel = tester.widget<DButton>(action).label;
          if (actionLabel is! Text) {
            expect(
              tester.getCenter(icon).dx,
              closeTo(tester.getCenter(action).dx, .5),
            );
          } else {
            final label = find.byWidget(actionLabel);
            expect(
              tester.getRect(action).contains(tester.getCenter(icon)),
              isTrue,
            );
            expect(
              tester.getRect(icon).right,
              lessThanOrEqualTo(tester.getRect(label).left),
            );
          }
          final bar = tester.getRect(_bar);
          final visibleDestinations = find.descendant(
            of: _bar,
            matching: find.byType(DMobileDockItem),
          );
          for (final item in visibleDestinations.evaluate()) {
            final rect = tester.getRect(
              find.byElementPredicate((e) => e == item),
            );
            expect(rect.left, greaterThanOrEqualTo(bar.left));
            expect(rect.right, lessThanOrEqualTo(bar.right));
            expect(rect.right, lessThanOrEqualTo(tester.getRect(action).left));
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
    },
  );

  _mobileTest('the ⋮ grows the bar into a panel of places over the whole '
      'app', (tester) async {
    final shell = await pumpMobileShellFixture(tester);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpAndSettle();
    final more = find.byKey(DMobileDock.moreKey);
    final content = shell.currentContent;
    final tab = shell.mobileNavigation.tab;
    final rest = tester.getRect(_bar);
    expect(rest.bottom, phone.height);
    expect(_panel, findsNothing);
    await tester.tap(more);
    await tester.pumpAndSettle();

    // The panel rises from the foot the height its rows need, the bar risen
    // to be its head, and the dim lies over everything else, header and all.
    final tiles = _panelLabels(tester).length + 1;
    final geometry = DMobileDockGeometry.of(
      tester.element(_bar),
    ).panel(tiles: tiles);
    expect(geometry.bar.foot, 34);
    expect(geometry.rows, 3);
    final panel = tester.getRect(_panel);
    expect(panel.left, 0);
    expect(panel.right, phone.width);
    expect(panel.bottom, phone.height);
    expect(panel.height, geometry.height);
    expect(
      tester.getRect(find.byKey(const ValueKey('mobile-dock-surface'))).top,
      closeTo(rest.top - geometry.travel, .01),
    );
    expect(tester.getRect(_dim), Offset.zero & phone);
    expect(tester.getRect(_dim).contains(tester.getCenter(_header)), isTrue);
    expect(tester.widget<DMobileDockItem>(more).expanded, isTrue);
    expect(shell.currentContent, same(content));
    expect(shell.mobileNavigation.tab, tab);
    for (final label in ['Inbox', 'Users', 'Groups', 'Badges']) {
      expect(_panelTile(label).hitTestable(), findsOneWidget, reason: label);
    }
    expect(
      tester.getSize(find.byKey(DMobileDock.grabberKey)),
      const Size(36, 5),
    );
    // You are its last tile, named as the account menu names you, with your
    // presence said as the header's account button says it.
    final you = find.byKey(
      DMobileDock.tileKey(const ValueKey('mobile-mode-profile')),
    );
    expect(you.hitTestable(), findsOneWidget);
    expect(tester.widget<DMobileDockItem>(you).label, 'reader');
    expect(
      tester.widget<DMobileDockItem>(you).semanticLabel,
      'Your account, Online',
    );
    expect(_panelLabels(tester).last, isNot('reader'));

    // A press on the dim over the header closes the panel; the header under
    // it takes nothing.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('mobile-menu-button'))),
    );
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(shell.mobileNavigation.sidebarOpen, isFalse);
    expect(tester.widget<DMobileDockItem>(more).expanded, isFalse);
    expect(tester.getRect(_bar), rest);
    expect(shell.currentContent, same(content));
    expect(shell.mobileNavigation.tab, tab);

    // The profile tile opens the account menu.
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(you);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(find.byKey(const ValueKey('user-menu-own-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'the panel opens groups, badges and bookmarks using shared pages',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      // Bookmarks is the bar's third place, so the panel does not hold it.
      for (final (label, id) in [
        ('Groups', 'groups'),
        ('Badges', 'badges'),
        ('Bookmarks', 'user-bookmarks'),
      ]) {
        if (label == 'Bookmarks') {
          await _tapDockTab(tester, 'destination/user-bookmarks');
        } else {
          await tester.tap(_moreTrigger);
          await tester.pumpAndSettle();
          for (final (item, listed) in [
            ('Groups', true),
            ('Badges', true),
            ('Bookmarks', false),
          ]) {
            expect(_panelTile(item), listed ? findsOneWidget : findsNothing);
          }
          await tester.tap(_panelTile(label));
          await tester.pumpAndSettle();
        }
        expect(_panel, findsNothing);
        expect(shell.currentContent?.id, id);
        expect(shell.mobileNavigation.tab, MobileTab.destination(id));
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
    },
  );

  for (final (label, id) in [
    ('Categories', 'all-categories'),
    ('Badges', 'badges'),
    ('Interface', 'appearance'),
  ]) {
    _mobileTest('a relaunch on $label marks $label as the current place', (
      tester,
    ) async {
      final forumTabs = FakeForumTabStore();
      final shell = await pumpMobileShellFixture(tester, forumTabs: forumTabs);
      await _chooseFromPanel(tester, label);
      expect(shell.currentContent?.id, id);
      expect(_markedPlace(tester), label);

      final relaunched = await pumpMobileShellFixture(
        tester,
        forumTabs: forumTabs,
        key: UniqueKey(),
      );
      expect(relaunched, isNot(same(shell)));
      expect(relaunched.currentContent?.id, id);
      expect(relaunched.mobileNavigation.tab, MobileTab.destination(id));
      expect(_markedPlace(tester), label);
      expect(relaunched.mobileNavigation.canGoBack, isFalse);

      // The restored page is that place's root, so Topics starts its own.
      await _tapDockTab(tester, 'topics');
      expect(relaunched.currentContent?.id, 'latest');
      expect(_markedPlace(tester), 'Topics');
      expect(relaunched.mobileNavigation.canGoBack, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  _mobileTest('a relaunch in a chat channel keeps Chat and its list behind', (
    tester,
  ) async {
    final forumTabs = FakeForumTabStore();
    await pumpMobileShellFixture(tester, forumTabs: forumTabs);
    await _tapDockTab(tester, 'panel/chat');
    await tester.tap(find.byKey(const ValueKey('chat-inbox-channel-10')));
    await tester.pumpAndSettle();

    final relaunched = await pumpMobileShellFixture(
      tester,
      forumTabs: FakeForumTabStore([
        for (final workspace in forumTabs.workspaces)
          ForumWorkspace.tryFromJson(jsonDecode(jsonEncode(workspace)))!,
      ]),
      key: UniqueKey(),
    );
    expect(relaunched.currentContent?.id, 'chat-c-10');
    expect(relaunched.mobileNavigation.tab, const MobileTab.panel('chat'));
    expect(_markedPlace(tester), 'Chat');

    expect(relaunched.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ChatMobileSidebar), findsOneWidget);
    expect(relaunched.mobileNavigation.panelOwner, 'chat');
    expect(tester.takeException(), isNull);
  });

  _mobileTest('a saved page without its place starts on the default page', (
    tester,
  ) async {
    final forumTabs = FakeForumTabStore();
    final shell = await pumpMobileShellFixture(tester, forumTabs: forumTabs);
    await _chooseFromPanel(tester, 'Categories');
    expect(shell.currentContent?.id, 'all-categories');

    final olderBuild = FakeForumTabStore([
      for (final workspace in forumTabs.workspaces)
        ForumWorkspace.tryFromJson(
          jsonDecode(jsonEncode(workspace)) as Map<String, Object?>
            ..remove('mobile'),
        )!,
    ]);
    final relaunched = await pumpMobileShellFixture(
      tester,
      forumTabs: olderBuild,
      key: UniqueKey(),
    );
    expect(relaunched.currentContent?.id, 'latest');
    expect(_markedPlace(tester), 'Topics');
    expect(tester.takeException(), isNull);
  });

  _mobileTest('a relaunch in a topic keeps its list behind it', (tester) async {
    final forumTabs = FakeForumTabStore();
    final shell = await pumpMobileShellFixture(tester, forumTabs: forumTabs);
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.isTopic, isTrue);

    final relaunched = await pumpMobileShellFixture(
      tester,
      forumTabs: forumTabs,
      key: UniqueKey(),
    );
    expect(relaunched.currentContent?.isTopic, isTrue);
    expect(_markedPlace(tester), 'Topics');
    expect(relaunched.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(relaunched.currentContent?.id, 'latest');
    expect(tester.takeException(), isNull);
  });

  _mobileTest('Start is not a place: the bar and its panel are Start', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-mode-start')), findsNothing);
    expect(await _placesInOrder(tester), isNot(contains('Start')));
    expect(tester.takeException(), isNull);
  });

  _mobileTest('a phone left on the Start page lands on Topics', (tester) async {
    final shell = await pumpMobileShellFixture(tester);
    await _tapDockTab(tester, 'panel/chat');
    shell.selectMobileDestination(
      const MobileTab.destination('new-tab'),
      const SidebarDestination(
        id: 'new-tab',
        label: 'Start page',
        icon: DIcons.house,
      ),
    );
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(shell.currentContent?.id, 'latest');
    expect(find.byKey(const ValueKey('start-page-content')), findsNothing);
    expect(find.byKey(const ValueKey('topic-card-7')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('the dock and More offer what the Start page offered, in order', (
    tester,
  ) async {
    await pumpMobileShellFixture(tester, events: true);
    expect(await _placesInOrder(tester), [
      'Topics',
      'Chat',
      'Bookmarks',
      'Inbox',
      'Users',
      'Events',
      'Categories',
      'Groups',
      'Badges',
      'Interface',
      'Preferences',
      'Summary',
      'Activity',
      'Channels',
      'Threads',
    ]);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('the places a person has placed come first, in the bar and the '
      'panel, and a name the forum no longer offers is dropped', (
    tester,
  ) async {
    final placed = MobilePlaceOrderController(_site, 'user:reader');
    await placed.set(['destination/appearance', 'destination/gone', 'users']);
    placed.dispose();
    await pumpMobileShellFixture(tester);
    expect(await _placesInOrder(tester), [
      'Interface',
      'Users',
      'Topics',
      'Chat',
      'Bookmarks',
      'Inbox',
      'Categories',
      'Groups',
      'Badges',
      'Preferences',
      'Summary',
      'Activity',
      'Channels',
      'Threads',
    ]);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('a place dropped across the current one moves it over without '
      'the page changing tabs', (tester) async {
    final shell = await pumpMobileShellFixture(tester);
    await tester.tap(_moreTrigger);
    await tester.pumpAndSettle();
    final topics = tester.getCenter(
      find.byKey(const ValueKey('mobile-mode-topics')),
    );
    final gesture = await tester.createGesture();
    await gesture.down(
      tester.getCenter(find.byKey(const ValueKey('mobile-mode-panel/chat'))),
      timeStamp: Duration.zero,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await gesture.moveTo(topics, timeStamp: const Duration(milliseconds: 340));
    await tester.pump();
    await gesture.up(timeStamp: const Duration(milliseconds: 400));
    // The frame that brings the places in their new order, and the next.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(_dockLabels(tester).take(2), ['Chat', 'Topics']);
    // Topics is the page still, in another column: nothing slides, and the
    // page takes input.
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(find.byKey(const ValueKey('history-outgoing-tab')), findsNothing);
    expect(find.byKey(const ValueKey('history-incoming-tab')), findsNothing);
    final live = find.byKey(const ValueKey('history-live-page'));
    expect(live, findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .descendant(of: live, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isFalse,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  _mobileTest('staff reach Dashboard right after Bookmarks', (tester) async {
    await pumpMobileShellFixture(tester, user: _reader(staff: true));
    final places = await _placesInOrder(tester);
    expect(places.take(5), [
      'Topics',
      'Chat',
      'Bookmarks',
      'Dashboard',
      'Inbox',
    ]);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('a signed-out phone offers no account pages', (tester) async {
    await pumpShell(
      tester,
      phone,
      instances: [instance('meta.discourse.org')],
      api: FakeDiscourseApi(),
    );
    final places = await _placesInOrder(tester);
    expect(places.first, 'Topics');
    expect(places, containsAll(['Users', 'Categories', 'Groups', 'Badges']));
    for (final label in [
      'Bookmarks',
      'Preferences',
      'Summary',
      'Activity',
      'Drafts',
    ]) {
      expect(places, isNot(contains(label)));
    }
    expect(tester.takeException(), isNull);
  });

  for (final (label, id, page) in [
    ('Summary', 'summary', find.byType(UserSummaryView)),
    ('Activity', 'activity', find.byType(UserActivityView)),
    ('Channels', 'chat-browse', find.byType(ChatBrowseChannelsView)),
    ('Threads', 'chat-my-threads', find.byType(ChatMyThreadsView)),
  ]) {
    _mobileTest(
      '$label opens its page from the panel and becomes the current place',
      (tester) async {
        final shell = await pumpMobileShellFixture(tester);
        await _chooseFromPanel(tester, label);
        expect(page, findsOneWidget);
        expect(shell.currentContent?.id, id);
        expect(shell.mobileNavigation.tab, MobileTab.destination(id));
        // The page stands where the ⋮ was, marked current.
        final place = find.byKey(ValueKey('mobile-mode-destination/$id'));
        expect(place.hitTestable(), findsOneWidget);
        expect(tester.widget<DMobileDockItem>(place).selected, isTrue);
        expect(tester.widget<DMobileDockItem>(place).hasPopup, isTrue);
        expect(find.byKey(const ValueKey('mobile-mode-more')), findsNothing);
        _expectPage();
        expect(tester.takeException(), isNull);
      },
    );
  }

  _mobileTest('Drafts comes last and only while a draft can be resumed', (
    tester,
  ) async {
    late FakeDiscourseApi api;
    final shell = await pumpMobileShellFixture(
      tester,
      events: true,
      onApi: (fake) => api = fake,
    );
    // An edit draft cannot be resumed from a list.
    api.userDraftList = const [
      UserDraft(
        key: 'edit_topic_7',
        sequence: 1,
        topicId: 7,
        data: ComposerDraft(reply: 'An edit', action: 'edit'),
      ),
    ];
    await shell.draftList.load(shell.currentInstance!);
    await tester.pumpAndSettle();
    expect(await _placesInOrder(tester), isNot(contains('Drafts')));
    await tester.tapAt(const Offset(195, 100));
    await tester.pumpAndSettle();

    api.userDraftList = [...api.userDraftList, _topicDraft];
    await shell.draftList.load(shell.currentInstance!, refresh: true);
    await tester.pumpAndSettle();
    final places = await _placesInOrder(tester);
    expect(places.last, 'Drafts');
    expect(places.where((label) => label == 'Drafts'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  _mobileTest('a move keeps the slot of a place hidden for now, as Drafts is '
      'between drafts', (tester) async {
    final placed = MobilePlaceOrderController(_site, 'user:reader');
    await placed.set(['destination/drafts']);
    placed.dispose();
    late FakeDiscourseApi api;
    final shell = await pumpMobileShellFixture(
      tester,
      onApi: (fake) => api = fake..userDraftList = const [_topicDraft],
    );
    await shell.draftList.load(shell.currentInstance!);
    await tester.pumpAndSettle();
    expect(_dockLabels(tester).first, 'Drafts');
    // The draft finished, Drafts goes, and Chat is moved before Topics.
    shell.draftList.recordDeleted(_site, 'new_topic', knownToExist: true);
    await tester.pumpAndSettle();
    expect(_dockLabels(tester), ['Topics', 'Chat', 'Bookmarks']);
    final semantics = tester.ensureSemantics();
    await tester.tap(_moreTrigger);
    await tester.pumpAndSettle();
    final chat = tester.getSemantics(
      find.byKey(const ValueKey('mobile-mode-panel/chat')),
    );
    chat.owner!.performAction(
      chat.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Move earlier'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_dockLabels(tester), ['Chat', 'Topics', 'Bookmarks']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    semantics.dispose();
    // A new draft brings Drafts back where the person had put it.
    api.userDraftList = const [_topicDraft];
    await shell.draftList.load(shell.currentInstance!, refresh: true);
    await tester.pumpAndSettle();
    expect((await _placesInOrder(tester)).take(3), [
      'Drafts',
      'Chat',
      'Topics',
    ]);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('Drafts opens the drafts page and stays while it is open', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(
      tester,
      onApi: (api) => api.userDraftList = const [_topicDraft],
    );
    await shell.draftList.load(shell.currentInstance!);
    await tester.pumpAndSettle();
    await _chooseFromPanel(tester, 'Drafts');
    expect(find.byType(DraftListView), findsOneWidget);
    expect(shell.currentContent?.id, 'drafts');
    expect(shell.mobileNavigation.tab, const MobileTab.destination('drafts'));

    // Deleting the last draft empties the page, which stays on screen.
    shell.draftList.recordDeleted(_site, 'new_topic', knownToExist: true);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'drafts');
    expect(shell.mobileNavigation.tab, const MobileTab.destination('drafts'));
    expect(find.byType(DraftListView), findsOneWidget);

    await _tapDockTab(tester, 'topics');
    expect(await _placesInOrder(tester), isNot(contains('Drafts')));
    expect(tester.takeException(), isNull);
  });

  _mobileTest('no two places on the bar share a glyph', (tester) async {
    await pumpMobileShellFixture(tester);
    await _chooseFromPanel(tester, 'Categories');
    final glyphs = [
      for (final item in tester.widgetList<DMobileDockItem>(
        find.descendant(
          of: find.byType(DMobileDock),
          matching: find.byType(DMobileDockItem),
        ),
      ))
        if (item.label != 'More') (item.icon as DIcon).icon,
    ];
    expect(glyphs, hasLength(4));
    expect(glyphs.toSet(), hasLength(glyphs.length));
    expect(tester.takeException(), isNull);
  });

  _mobileTest('a page past the bar\'s columns stands where the ⋮ was', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester, events: true);
    final users = find.byKey(const ValueKey('mobile-mode-users'));
    final more = find.byKey(const ValueKey('mobile-mode-more'));
    expect(users, findsNothing);
    final chat = tester.getRect(
      find.byKey(const ValueKey('mobile-mode-panel/chat')),
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    for (final label in ['Inbox', 'Users', 'Events']) {
      expect(_panelTile(label), findsOneWidget);
    }
    await tester.tap(_panelTile('Users'));
    await tester.pumpAndSettle();
    expect(shell.mobileNavigation.tab, MobileTab.users);
    // Users takes the ⋮'s slot as a fourth place, the four sharing the room
    // the three and the ⋮ had; the circle would show its glyph.
    expect(more, findsNothing);
    expect(users.hitTestable(), findsOneWidget);
    expect(tester.widget<DMobileDockItem>(users).selected, isTrue);
    for (final tab in ['topics', 'panel/chat', 'destination/user-bookmarks']) {
      expect(
        tester.getSize(find.byKey(ValueKey('mobile-mode-$tab'))).width,
        closeTo(tester.getSize(users).width, .01),
        reason: tab,
      );
    }
    expect(tester.getSize(users).width, lessThan(chat.width));
    expect(
      tester.getRect(users).right,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('mobile-new-topic'))).left,
      ),
    );
    final reveal =
        tester
                .widget<DMobileDock>(find.byType(DMobileDock))
                .collapsedDestination
            as DMobileDockItem;
    expect((reveal.icon as DIcon).icon, DIcons.users);
    // Pressing it grows the bar into the panel, as the ⋮ does, Users still
    // among them and lit as the current place.
    await tester.tap(users);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(_panelTile('Users'), findsOneWidget);
    expect(
      tester.widget<DMobileDockItem>(_panelTile('Users')).selected,
      isTrue,
    );
    expect(shell.mobileNavigation.tab, MobileTab.users);
    await tester.tap(_panelTile('Events'));
    await tester.pumpAndSettle();
    final events = find.byKey(
      const ValueKey('mobile-mode-destination/events-upcoming'),
    );
    expect(events.hitTestable(), findsOneWidget);
    expect(users, findsNothing);
    expect(more, findsNothing);

    tester.view.physicalSize = const Size(800, 844);
    await tester.pumpAndSettle();
    expect(events, findsOneWidget);
    expect(more, findsNothing);
    await _tapDockTab(tester, 'topics');
    expect(more.hitTestable(), findsOneWidget);
    expect(tester.widget<DMobileDockItem>(more).selected, isFalse);
    expect(tester.takeException(), isNull);
  });

  _mobileTest('large text keeps three places, the ⋮ and the action on a '
      'narrow bar', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMobileShellFixture(tester, size: const Size(320, 720));
    final more = find.byKey(const ValueKey('mobile-mode-more'));
    final action = find.byKey(const ValueKey('mobile-new-topic'));
    expect(more, findsOneWidget);
    for (final tab in ['topics', 'panel/chat', 'destination/user-bookmarks']) {
      expect(
        find.byKey(ValueKey('mobile-mode-$tab')).hitTestable(),
        findsOneWidget,
      );
    }
    // On a bar this narrow the ⋮ and the action touch, and neither overlaps.
    expect(
      tester.getRect(more).right,
      lessThanOrEqualTo(tester.getRect(action).left + .01),
    );
    expect(tester.getSize(action).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(action).width, tester.getSize(action).height);
    await tester.tap(more);
    await tester.pumpAndSettle();
    for (final (label, listed) in [('Chat', false), ('Inbox', true)]) {
      expect(_panelTile(label), listed ? findsOneWidget : findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  _mobileTest('users and events keep their own page headings', (tester) async {
    await pumpMobileShellFixture(tester, events: true);
    for (final (tab, heading) in [
      ('users', 'Users'),
      ('destination/events-upcoming', 'Events'),
    ]) {
      await _tapDockTab(tester, tab);
      expect(
        find.descendant(
          of: find.byType(MainContent),
          matching: find.text(heading),
        ),
        findsOneWidget,
      );
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
      await pumpMobileShellFixture(
        tester,
        events: true,
        size: const Size(1024, 844),
      );
      final header = tester.getRect(_header);
      final bar = tester.getRect(_bar);
      final panel = find.byKey(const ValueKey('mobile-content-panel'));
      // Each move ends on a place the bar shows: a place chosen from the panel
      // moves only once its sheet has closed, after the frames read here.
      for (final (from, to, direction) in [
        ('messages', 'panel/chat', -1),
        ('panel/chat', 'destination/user-bookmarks', 1),
        ('destination/events-upcoming', 'topics', -1),
        ('destination/summary', 'topics', -1),
        ('destination/activity', 'destination/user-bookmarks', -1),
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
        final boundary = find.byWidgetPredicate(
          (widget) =>
              widget is ClipRRect &&
              widget.clipper != null &&
              widget.clipBehavior != Clip.none,
        );
        expect(boundary, findsOneWidget);
        final clip = tester
            .widget<ClipRRect>(boundary)
            .clipper!
            .getClip(tester.getSize(boundary));
        final box = tester.renderObject<RenderBox>(boundary);
        expect(
          clip.outerRect.shift(box.localToGlobal(Offset.zero)),
          restingPanel,
        );
        expect(clip.tlRadius, const Radius.circular(31));
        expect(clip.trRadius, const Radius.circular(31));
        expect(clip.blRadius, const Radius.circular(22));
        expect(clip.brRadius, const Radius.circular(22));
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
    'voice rooms belong to the navigation Chat tab and the Chat inbox',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester, voice: true);
      final voice = shell.pluginSession.require(voiceControllerService);
      expect(find.byKey(const ValueKey('mobile-mode-voice')), findsNothing);
      await _tapDockTab(tester, 'panel/chat');
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
      expect(find.text('Voice rooms'), findsNothing);
      expect(find.text('Watercooler'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar-panel-switch-chat')));
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
    'header retains notifications and drawer profile; search is a dedicated page',
    (tester) async {
      await pumpMobileShellFixture(tester);
      expect(_bar, findsOneWidget);
      expect(_header, findsOneWidget);
      expect(find.byType(InstanceRail), findsNothing);
      expect(find.byKey(UserMenuButton.bellKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.avatarKey), findsNothing);
      expect(find.byKey(ForumSearch.inputKey), findsNothing);
      expect(find.text('Filter'), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-panel-tabs')), findsNothing);
      await tester.tap(find.byKey(UserMenuButton.bellKey));
      await tester.pumpAndSettle();
      final notificationsSheet = find.ancestor(
        of: find.byType(UserMenuPanel),
        matching: find.byType(DSheetContent),
      );
      expect(notificationsSheet, findsOneWidget);
      expect(
        tester.widget<DSheetContent>(notificationsSheet).variant,
        DSheetVariant.adaptiveMenu,
      );
      expect(find.byType(UserMenuPanel), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      final profileSheet = find.ancestor(
        of: find.byKey(const ValueKey('user-menu-own-card')),
        matching: find.byType(DSheetContent),
      );
      expect(profileSheet, findsOneWidget);
      expect(
        tester.widget<DSheetContent>(profileSheet).variant,
        DSheetVariant.adaptiveMenu,
      );
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Preferences'), findsOneWidget);
      await tester.drag(
        find.descendant(
          of: profileSheet,
          matching: find.byKey(const ValueKey('sheet-drag-handle')),
        ),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      expect(profileSheet, findsNothing);
      expect(find.byType(InstanceRail), findsOneWidget);
      await tester.tap(find.byTooltip('Close navigation'));
      await tester.pumpAndSettle();
      expect(find.byType(InstanceRail), findsNothing);
      await tester.tap(find.byKey(const ValueKey('forum-identity-logo')));
      await tester.pumpAndSettle();
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

  _mobileTest('header icons stay on one line with enlarged text', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMobileShellFixture(tester);

    final controls = [
      find.byKey(const ValueKey('mobile-menu-button')),
      find.byKey(const ValueKey('mobile-search-button')),
      find.byKey(UserMenuButton.bellKey),
    ];
    for (final width in [320.0, 390.0, 430.0, 600.0, 1024.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final scale in [1.0, 1.15, 1.3, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();

        final header = tester.getRect(_header);
        final centerY = tester.getCenter(controls.first).dy;
        for (final control in controls) {
          final rect = tester.getRect(control);
          if (scale < 2) expect(rect.center.dy, closeTo(centerY, .01));
          expect(rect.top, greaterThanOrEqualTo(header.top));
          expect(rect.bottom, lessThanOrEqualTo(header.bottom));
          expect(rect.left, greaterThanOrEqualTo(header.left));
          expect(rect.right, lessThanOrEqualTo(header.right));
          expect(control.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

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
        expect(tester.getSize(logo), const Size.square(28));
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

  _mobileTest(
    'chat focus hides navigation and keeps Send inside the composer',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      await _tapDockTab(tester, 'panel/chat');
      await tester.pumpAndSettle();
      await _selectChatKind(tester, 'Direct messages');
      await tester.tap(find.text('sam').first);
      await tester.pumpAndSettle();
      final composer = tester
          .widget<ComposerEditor>(find.byType(ComposerEditor))
          .composer;
      composer.focus.unfocus();
      await tester.pumpAndSettle();
      expect(_bar.hitTestable(), findsOneWidget);
      final panel = find.byKey(const ValueKey('mobile-content-panel'));
      final initialHeight = tester.getSize(panel).height;
      composer.focus.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).height, initialHeight);
      expect(_bar.hitTestable(), findsNothing);
      final send = find.byKey(const ValueKey('chat-composer-send'));
      expect(find.descendant(of: _bar, matching: send), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chat-composer')),
          matching: send,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-new-topic')).hitTestable(),
        findsNothing,
      );
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
      expect(_bar.hitTestable(), findsNothing);
      composer.focus.unfocus();
      await tester.pumpAndSettle();
      expect(_bar.hitTestable(), findsOneWidget);
      expect(tester.getSize(panel).height, initialHeight);
      composer.focus.requestFocus();
      await tester.pumpAndSettle();
      shell.handleBack();
      await tester.pumpAndSettle();
      expect(_bar.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'chat mixes conversations and restores the selected type filter',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      await _tapDockTab(tester, 'panel/chat');
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
          of: find.byKey(const ValueKey('chat-composer')),
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
          of: find.byKey(const ValueKey('chat-composer')),
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
    await _tapDockTab(tester, 'panel/chat');
    await tester.pumpAndSettle();
    final navigation = find.byKey(const ValueKey('chat-browse-navigation'));
    Finder peer(String label) =>
        find.descendant(of: navigation, matching: find.text(label));
    expect(find.byKey(const ValueKey('chat-inbox-title')), findsOneWidget);
    expect(peer('Channels'), findsOneWidget);
    expect(peer('Threads'), findsOneWidget);
    await tester.ensureVisible(peer('Channels'));
    await tester.tap(peer('Channels'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-browse');
    shell.handleBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(peer('Threads'));
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
      const ContentRoute(
        destination: PageDestination(CorePage.users),
        title: 'Users',
        icon: DIcons.user,
      ),
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

  _mobileTest('edge swipes cover the full mobile navigation surface', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    final shell = await pumpMobileShellFixture(tester);
    shell.pushContent(
      const ContentRoute(
        destination: PageDestination(CorePage.users),
        title: 'Users',
        icon: DIcons.user,
      ),
    );
    await tester.pumpAndSettle();
    final surface = tester.getRect(find.byKey(const ValueKey('mobile-root')));
    final header = tester.getRect(_header);
    final bar = tester.getRect(_bar);
    final page = tester.getRect(
      find.byKey(const ValueKey('mobile-content-panel')),
    );
    for (final y in [
      page.center.dy,
      surface.top + 1,
      header.center.dy,
      page.top + 1,
      page.bottom - 1,
      bar.center.dy,
      surface.bottom - 1,
    ]) {
      for (final back in [true, false]) {
        final live = find.byKey(const ValueKey('mobile-content-panel'));
        final origin = tester.getTopLeft(live);
        final gesture = await tester.startGesture(
          Offset(
            back
                ? surface.left + (y < surface.top + 56 ? 80 : 1)
                : surface.right - 1,
            y,
          ),
        );
        await gesture.moveBy(
          Offset(back ? 120 : -120, 0),
          timeStamp: const Duration(milliseconds: 200),
        );
        await tester.pump();
        final left = tester.getTopLeft(live).dx;
        if (back) {
          expect(left - origin.dx, closeTo(120, .001), reason: 'Back at $y');
        } else {
          // The inset shrinks with the background page while its outer
          // viewport stays fixed, keeping a visible gutter at every edge.
          expect(left, closeTo(surface.left, .001), reason: 'Forward at $y');
        }
        expect(tester.getRect(_header), header);
        expect(tester.getRect(_bar), bar);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, back ? 'latest' : 'users');
      }
    }
    shell.handleBack();
    await tester.pumpAndSettle();
    for (final y in [surface.top + 1, surface.top + 55]) {
      await tester.dragFrom(Offset(surface.left + 1, y), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.sidebarOpen, isTrue);
      expect(tester.getRect(_header), header);
      await tester.dragFrom(
        Offset(surface.right - 1, y),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.sidebarOpen, isFalse);
      expect(tester.getRect(_header), header);
      expect(tester.getRect(_bar), bar);
    }
    expect(tester.takeException(), isNull);
  });

  _mobileTest(
    'sidebar swipe moves the tab bar with the finger in both directions',
    (tester) async {
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      final shell = await pumpMobileShellFixture(tester);
      final header = tester.getRect(_header);
      final bar = tester.getRect(_bar);
      final page = tester.getSize(
        find.byKey(const ValueKey('mobile-content-panel')),
      );
      final travel = DMobileDockGeometry.of(tester.element(_bar)).footerExtent;

      for (final opening in [true, false]) {
        for (final cancel in [true, false]) {
          final start = Offset(
            opening ? 1 : phone.width - 1,
            opening ? header.top + 12 : 400,
          );
          final gesture = await tester.startGesture(start);
          var step = 0;
          for (final fraction in [.2, .6, .35]) {
            await gesture.moveTo(
              start + Offset(phone.width * fraction * (opening ? 1 : -1), 0),
              timeStamp: Duration(milliseconds: ++step * 200),
            );
            await tester.pump();
            final hidden = opening ? fraction : 1 - fraction;
            expect(
              tester.getTopLeft(_bar).dy,
              closeTo(bar.top + travel * hidden, .01),
            );
            expect(tester.getRect(_header), header);
            if (opening) {
              expect(
                tester.getSize(
                  find.byKey(const ValueKey('mobile-content-panel')),
                ),
                page,
              );
            }
            // Holding the finger still must hold the bar at the same position.
            final held = tester.getRect(_bar);
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.getRect(_bar), held);
          }
          if (cancel) {
            await gesture.cancel();
          } else {
            await gesture.up();
          }
          final open = cancel ? !opening : opening;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 32));
          final settlingTop = tester.getTopLeft(_bar).dy;
          final releaseTop = bar.top + travel * (opening ? .35 : .65);
          if (open) {
            expect(settlingTop, greaterThan(releaseTop));
            expect(settlingTop, lessThan(bar.top + travel));
          } else {
            expect(settlingTop, lessThan(releaseTop));
            expect(settlingTop, greaterThan(bar.top));
          }
          await tester.pumpAndSettle();
          expect(shell.mobileNavigation.sidebarOpen, open);
          if (open) {
            expect(_bar, findsNothing);
          } else {
            expect(tester.getRect(_bar), bar);
          }
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('corner swipes open navigation across mobile tabs', (
    tester,
  ) async {
    final shell = await pumpMobileShellFixture(tester);
    final header = tester.getRect(_header);
    for (final tab in [
      'topics',
      'destination/user-bookmarks',
      'panel/chat',
      'messages',
      'users',
    ]) {
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

      final open = await tester.startGesture(Offset(8, header.top + 12));
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

  for (final width in [320.0, 430.0, 600.0]) {
    _mobileTest('rail stays inside the $width viewport during swipes', (
      tester,
    ) async {
      final shell = await pumpMobileShellFixture(
        tester,
        size: Size(width, 844),
      );
      final header = tester.getRect(_header);

      void expectRailInsideViewport() {
        for (final finder in [
          find.byType(InstanceRail),
          find.byKey(const ValueKey('add-instance-rail-button')),
        ]) {
          final box = tester.renderObject<RenderBox>(finder);
          final left = box.localToGlobal(Offset.zero).dx;
          final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
          expect(left, greaterThanOrEqualTo(-.001));
          expect(right, lessThan(width));
        }
        expect(tester.getRect(_header), header);
      }

      for (final open in [true, false]) {
        for (final cancel in [true, false]) {
          final gesture = await tester.startGesture(
            Offset(open ? 1 : width - 1, open ? header.top + 12 : 400),
          );
          for (final fraction in [.1, .45, .8]) {
            await gesture.moveTo(
              Offset(
                open ? 1 + width * fraction : width - 1 - width * fraction,
                open ? header.top + 12 : 400,
              ),
            );
            await tester.pump();
            expectRailInsideViewport();
          }
          if (cancel) {
            await gesture.cancel();
          } else {
            await gesture.up();
          }
          await tester.pumpAndSettle();
          expect(shell.mobileNavigation.sidebarOpen, cancel ? !open : open);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  _mobileTest('rail swipes preserve Back and Forward visits', (tester) async {
    final shell = await pumpMobileShellFixture(tester);
    final root = shell.mobileNavigation.entryId;
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    final topic = shell.mobileNavigation.entryId;
    final page = tester.getRect(
      find.byKey(const ValueKey('mobile-content-panel')),
    );
    Future<void> swipe(bool right, {bool sidebar = false}) async {
      final gesture = await tester.startGesture(
        Offset(
          right ? page.right - 4 : page.left + 4,
          sidebar ? tester.getRect(_header).top + 12 : 400,
        ),
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
    await swipe(false, sidebar: true);
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
          Offset(
            open ? page.right - 4 : page.left + 4,
            open ? 400 : tester.getRect(_header).top + 12,
          ),
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
    expect(dockItems, isNotEmpty);
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
    expect(find.byKey(const ValueKey('mobile-new-topic')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('forum-identity-logo')));
    await tester.pumpAndSettle();
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
