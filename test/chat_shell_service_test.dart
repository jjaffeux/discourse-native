import 'dart:async';
import 'dart:ui' show Rect;

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer_preferences_store.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'in-app links wait for and honor the restored full-page preference',
    () async {
      final persistence = _PreferencesPersistence.gated();
      final fixture = await _fixture(
        channels: ChatChannels(public: [_channel(9)]),
        persistence: persistence,
      );
      addTearDown(fixture.dispose);
      fixture.shell.updateDrawerAvailability(true);

      final opened = fixture.shell.openPluginUrl(
        '$_site/chat/c/-/9',
        origin: PluginLinkOrigin.inApp,
      );
      await Future<void>.delayed(Duration.zero);

      expect(fixture.shell.drawerActive, isFalse);
      expect(fixture.host.contentStack.map((route) => route.id), ['latest']);

      persistence.completeDisplayModeRead('FULL_PAGE_CHAT');

      expect(await opened, isTrue);
      expect(
        fixture.shell.preferredDisplayMode,
        ChatPreferredDisplayMode.fullPage,
      );
      expect(fixture.shell.drawerActive, isFalse);
      expect(fixture.host.currentContent?.id, ChatRoute.channel(9).routeId);
    },
  );

  test(
    'a late preference restore cannot overwrite a newer explicit choice',
    () async {
      final persistence = _PreferencesPersistence.gated();
      final fixture = await _fixture(
        channels: ChatChannels(public: [_channel(9)]),
        persistence: persistence,
      );
      addTearDown(fixture.dispose);
      fixture.shell.updateDrawerAvailability(true);
      expect(fixture.shell.openChannel(9), isTrue);

      final openedFullPage = fixture.shell.openFullPageFromDrawer();
      expect(
        fixture.shell.preferredDisplayMode,
        ChatPreferredDisplayMode.fullPage,
      );

      persistence.completeDisplayModeRead('DRAWER_CHAT');
      await openedFullPage;

      expect(
        fixture.shell.preferredDisplayMode,
        ChatPreferredDisplayMode.fullPage,
      );
      expect(persistence.displayModeWrites, ['FULL_PAGE_CHAT']);
    },
  );

  test('widening restores a drawer that a compact layout promoted', () async {
    final fixture = await _fixture(
      channels: ChatChannels(public: [_channel(9)]),
      persistence: _PreferencesPersistence(displayMode: 'DRAWER_CHAT'),
    );
    addTearDown(fixture.dispose);
    await fixture.shell.openShortcut(drawerAvailable: true);
    expect(fixture.shell.openChannel(9), isTrue);
    final forumRouteId = fixture.host.currentContent?.id;

    fixture.shell.updateDrawerAvailability(false);
    await Future<void>.delayed(Duration.zero);

    expect(fixture.shell.drawerActive, isFalse);
    expect(fixture.shell.fullPageChatActive, isTrue);
    expect(fixture.host.currentContent?.id, ChatRoute.channel(9).routeId);
    expect(fixture.shell.preferredDisplayMode, ChatPreferredDisplayMode.drawer);

    fixture.shell.updateDrawerAvailability(true);
    await Future<void>.delayed(Duration.zero);

    expect(fixture.shell.drawerActive, isTrue);
    expect(
      fixture.shell.drawerCurrentContent?.id,
      ChatRoute.channel(9).routeId,
    );
    expect(fixture.shell.fullPageChatActive, isFalse);
    expect(fixture.host.currentContent?.id, forumRouteId);
    expect(fixture.persistence.displayModeWrites, isEmpty);
  });

  test(
    'a deep drawer route gains its channel parent in full-page Chat',
    () async {
      final fixture = await _fixture(
        channels: ChatChannels(public: [_channel(9)]),
        persistence: _PreferencesPersistence(displayMode: 'DRAWER_CHAT'),
      );
      addTearDown(fixture.dispose);
      await fixture.shell.openShortcut(drawerAvailable: true);
      fixture.shell.forget(_site);

      fixture.shell.openThread(siteUrl: _site, channelId: 9, threadId: 44);
      expect(fixture.shell.drawerContentStack.map((route) => route.id), [
        ChatRoute.thread(channelId: 9, threadId: 44).routeId,
      ]);

      await fixture.shell.openFullPageFromDrawer();

      expect(fixture.host.contentStack.map((route) => route.id), [
        ChatRoute.channel(9).routeId,
        ChatRoute.thread(channelId: 9, threadId: 44).routeId,
      ]);
    },
  );

  test(
    'channel cycling follows sidebar order rather than drawer activity order',
    () async {
      final fixture = await _fixture(
        channels: ChatChannels(
          public: [
            _channel(4, title: 'Alpha'),
            _channel(
              2,
              title: 'Beta',
              tracking: const ChatTracking(unreadCount: 1),
            ),
            _channel(
              1,
              title: 'Zulu',
              tracking: const ChatTracking(mentionCount: 1),
            ),
            _channel(3, title: 'Starred', starred: true),
          ],
        ),
        persistence: _PreferencesPersistence(displayMode: 'DRAWER_CHAT'),
      );
      addTearDown(fixture.dispose);
      await fixture.shell.openShortcut(drawerAvailable: true);
      expect(fixture.shell.openChannel(3), isTrue);

      for (final expectedChannelId in [4, 2, 1, 3]) {
        expect(fixture.shell.cycleDrawerChannel(forward: true), isTrue);
        expect(
          fixture.shell.drawerCurrentContent?.id,
          ChatRoute.channel(expectedChannelId).routeId,
        );
      }
    },
  );

  test(
    'channel cycling limits unstarred direct messages after removing starred',
    () async {
      final fixture = await _fixture(
        channels: ChatChannels(
          direct: [
            _directChannel(90, activityRank: -1, starred: true),
            for (var index = 0; index <= 50; index++)
              _directChannel(100 + index, activityRank: index),
          ],
        ),
        persistence: _PreferencesPersistence(displayMode: 'DRAWER_CHAT'),
      );
      addTearDown(fixture.dispose);
      await fixture.shell.openShortcut(drawerAvailable: true);
      expect(fixture.shell.openChannel(149), isTrue);

      expect(fixture.shell.cycleDrawerChannel(forward: true), isTrue);
      expect(
        fixture.shell.drawerCurrentContent?.id,
        ChatRoute.channel(90).routeId,
      );
      expect(fixture.shell.cycleDrawerChannel(forward: true), isTrue);
      expect(
        fixture.shell.drawerCurrentContent?.id,
        ChatRoute.channel(100).routeId,
      );
    },
  );

  test('unread-only cycling includes muted unread channels', () async {
    final fixture = await _fixture(
      channels: ChatChannels(
        public: [
          _channel(1, title: 'Alpha'),
          _channel(
            2,
            title: 'Beta',
            muted: true,
            tracking: const ChatTracking(unreadCount: 1),
          ),
          _channel(
            3,
            title: 'Gamma',
            tracking: const ChatTracking(unreadCount: 1),
          ),
        ],
      ),
      persistence: _PreferencesPersistence(displayMode: 'DRAWER_CHAT'),
    );
    addTearDown(fixture.dispose);
    await fixture.shell.openShortcut(drawerAvailable: true);
    expect(fixture.shell.openChannel(1), isTrue);

    expect(
      fixture.shell.cycleDrawerChannel(forward: true, unreadOnly: true),
      isTrue,
    );
    expect(
      fixture.shell.drawerCurrentContent?.id,
      ChatRoute.channel(2).routeId,
    );
  });

  test(
    'a shortcut that resolves after a site switch leaves the drawer closed',
    () async {
      final persistence = _PreferencesPersistence.gated();
      final fixture = await _fixture(
        channels: ChatChannels(public: [_channel(9)]),
        persistence: persistence,
      );
      addTearDown(fixture.dispose);

      final opened = fixture.shell.openShortcut(drawerAvailable: true);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.shell.drawerActive, isFalse);

      fixture.host.switchTo(
        const DiscourseInstance(url: 'https://other.example', title: 'Other'),
      );
      persistence.completeDisplayModeRead('DRAWER_CHAT');
      await opened;

      expect(fixture.shell.drawerActive, isFalse);
      expect(fixture.shell.drawerContentStack, isEmpty);
    },
  );

  test('channel cycling works full page but not from an index route', () async {
    final fixture = await _fixture(
      channels: ChatChannels(
        public: [
          _channel(1, title: 'Alpha'),
          _channel(2, title: 'Beta'),
        ],
      ),
      persistence: _PreferencesPersistence(displayMode: 'FULL_PAGE_CHAT'),
    );
    addTearDown(fixture.dispose);
    fixture.shell.updateDrawerAvailability(false);
    expect(fixture.shell.openChannel(1), isTrue);

    expect(fixture.shell.cycleDrawerChannel(forward: true), isTrue);
    expect(fixture.host.currentContent?.id, ChatRoute.channel(2).routeId);

    fixture.shell.openBrowseChannels();
    expect(fixture.host.currentContent?.id, ChatPlugin.browseRouteId);
    expect(fixture.shell.cycleDrawerChannel(forward: true), isFalse);
    expect(fixture.host.currentContent?.id, ChatPlugin.browseRouteId);
  });
}

ChatChannel _channel(
  int id, {
  String title = 'Support',
  bool starred = false,
  bool muted = false,
  ChatTracking tracking = const ChatTracking(),
}) => ChatChannel(
  id: id,
  title: title,
  slug: title.toLowerCase(),
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true, starred: starred, muted: muted),
  tracking: tracking,
  threadingEnabled: true,
);

ChatChannel _directChannel(
  int id, {
  required int activityRank,
  bool starred = false,
}) => ChatChannel(
  id: id,
  title: 'Direct $id',
  kind: ChatChannelKind.directMessage,
  membership: ChatMembership(following: true, starred: starred),
  lastMessageId: 1000 - activityRank,
  lastMessageAt: DateTime.utc(
    2026,
    8,
    1,
  ).subtract(Duration(minutes: activityRank)),
);

Future<_Fixture> _fixture({
  required ChatChannels channels,
  required _PreferencesPersistence persistence,
}) async {
  final settings = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(),
    ),
  );
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
    ),
  );
  final totals = chatNotificationTotals();
  final instance = DiscourseInstance(
    url: _site,
    title: 'Meta',
    user: user,
    notificationTotals: totals,
    config: settings,
  );
  final api = FakeDiscourseApi(chatChannelsBySite: {_site: channels});
  final credentials = FakeApiCredentialReader()..keys[_site] = 'api-key';
  final store = Store();
  final chat = ChatController(
    api: api,
    requests: FakePluginRequestHost(credentials: credentials),
    store: store,
    currentUserFor: (_) => user,
    siteConfigFor: (_) => settings,
  );
  await chat.loadChannels(_site);

  final host = _NavigationHost(instance: instance, totals: totals);
  final settingsListenable = ValueNotifier(settings);
  final shell = ChatShellService(
    chat: chat,
    host: host,
    composerHost: PluginComposerHost(
      buildComposer: (_) => null,
      openNewTopic: (_) async => OpenComposerResult.unavailable,
      isActive: (_) => false,
      siteConfigFor: (_) => settings,
      siteConfigListenableFor: (_) => settingsListenable,
    ),
    store: store,
    postFlagCatalog: (_) => const [],
    drawerPreferences: ChatDrawerPreferencesStore(persistence: persistence),
  );
  return _Fixture(
    chat: chat,
    host: host,
    shell: shell,
    settingsListenable: settingsListenable,
    persistence: persistence,
  );
}

final class _Fixture {
  const _Fixture({
    required this.chat,
    required this.host,
    required this.shell,
    required this.settingsListenable,
    required this.persistence,
  });

  final ChatController chat;
  final _NavigationHost host;
  final ChatShellService shell;
  final ValueNotifier<SiteConfig> settingsListenable;
  final _PreferencesPersistence persistence;

  void dispose() {
    shell.dispose();
    chat.dispose();
    settingsListenable.dispose();
    host.dispose();
  }
}

final class _NavigationHost implements PluginNavigationHost {
  _NavigationHost({required this.instance, required this.totals})
    : _contentStack = [
        ContentRoute.fromDestination(instance.defaultDestination),
      ];

  DiscourseInstance instance;
  final NotificationTotals totals;
  final ChangeNotifier _changes = ChangeNotifier();
  List<ContentRoute> _contentStack;
  List<ContentRoute>? _mainPaneStack;
  List<ContentRoute>? _pluginPaneStack;
  bool _pluginPaneActive = false;
  bool _disposed = false;

  @override
  Listenable get changes => _changes;

  @override
  List<DiscourseInstance> get instances => [instance];

  @override
  DiscourseInstance get currentInstance => instance;

  @override
  bool get forumActive => true;

  @override
  bool get isDisposed => _disposed;

  @override
  ContentRoute? get currentContent => _contentStack.lastOrNull;

  @override
  List<ContentRoute> get contentStack => List.unmodifiable(_contentStack);

  @override
  NotificationTotals get currentTotals => totals;

  @override
  PluginVisibleTopicContext? get visibleTopicContext => null;

  @override
  Rect? get floatingComposerBounds => null;

  @override
  void selectInstance(int index) {}

  void switchTo(DiscourseInstance next) {
    instance = next;
    _contentStack = [ContentRoute.fromDestination(next.defaultDestination)];
    _changes.notifyListeners();
  }

  @override
  void selectDestination(SidebarDestination destination) {
    _contentStack = [ContentRoute.fromDestination(destination)];
    _changes.notifyListeners();
  }

  @override
  void pushContent(ContentRoute route) {
    _contentStack = [..._contentStack, route];
    _changes.notifyListeners();
  }

  @override
  void replaceCurrentContent(ContentRoute route) {
    _contentStack = [..._contentStack.take(_contentStack.length - 1), route];
    _changes.notifyListeners();
  }

  @override
  void showPluginContent() {}

  @override
  bool activatePluginPane(PluginId owner) {
    if (_pluginPaneActive) return _pluginPaneStack != null;
    _pluginPaneActive = true;
    _mainPaneStack = [..._contentStack];
    final pluginStack = _pluginPaneStack;
    if (pluginStack == null) return false;
    _contentStack = [...pluginStack];
    _changes.notifyListeners();
    return true;
  }

  @override
  void deactivatePluginPane(PluginId owner) {
    if (!_pluginPaneActive) return;
    _pluginPaneStack = [..._contentStack];
    _contentStack = [...?_mainPaneStack];
    _mainPaneStack = null;
    _pluginPaneActive = false;
    _changes.notifyListeners();
  }

  void dispose() {
    _disposed = true;
    _changes.dispose();
  }
}

final class _PreferencesPersistence
    implements ChatDrawerPreferencesPersistence {
  _PreferencesPersistence({this.displayMode}) : _displayModeRead = null;

  _PreferencesPersistence.gated() : _displayModeRead = Completer<String?>();

  String? displayMode;
  final Completer<String?>? _displayModeRead;
  final List<String> displayModeWrites = [];

  void completeDisplayModeRead(String? value) =>
      _displayModeRead!.complete(value);

  @override
  Future<String?> readPreferredDisplayMode() async {
    final pending = _displayModeRead;
    return pending == null ? displayMode : await pending.future;
  }

  @override
  Future<({double? width, double? height})> readDrawerSize() async =>
      (width: null, height: null);

  @override
  Future<bool> writePreferredDisplayMode(String value) async {
    displayMode = value;
    displayModeWrites.add(value);
    return true;
  }

  @override
  Future<bool> writeDrawerSize({
    required double width,
    required double height,
  }) async => true;
}
