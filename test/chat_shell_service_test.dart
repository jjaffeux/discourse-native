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
    'unrelated host updates do not notify chat presentation listeners',
    () async {
      final fixture = await _fixture(
        channels: ChatChannels(public: [_channel(9)]),
      );
      addTearDown(fixture.dispose);
      var changes = 0;
      fixture.shell.addListener(() => changes++);

      fixture.host._changes.notifyListeners();
      fixture.host._changes.notifyListeners();
      expect(changes, 0);

      fixture.host.pushContent(
        ContentRoute.topic(topicId: 42, slug: 'topic', title: 'Topic'),
      );
      expect(changes, 1);
      fixture.host._changes.notifyListeners();
      expect(changes, 1);

      fixture.host.bounds = const Rect.fromLTWH(0, 0, 600, 800);
      fixture.host._changes.notifyListeners();
      expect(changes, 2);

      fixture.host.instance = fixture.host.instance.copyWith(
        title: 'Renamed forum',
      );
      fixture.host._changes.notifyListeners();
      expect(changes, 3);
    },
  );

  for (final origin in PluginLinkOrigin.values) {
    test('$origin chat links open the full-page channel', () async {
      final fixture = await _fixture(
        channels: ChatChannels(public: [_channel(9)]),
      );
      addTearDown(fixture.dispose);
      expect(
        await fixture.shell.openPluginUrl('$_site/chat/c/-/9', origin: origin),
        isTrue,
      );
      expect(fixture.shell.fullPageChatActive, isTrue);
      expect(fixture.host.currentContent?.id, ChatRoute.channel(9).routeId);
    });
  }

  test('the Chat shortcut opens a channel in the main content', () async {
    final fixture = await _fixture(
      channels: ChatChannels(public: [_channel(9)]),
    );
    addTearDown(fixture.dispose);
    await fixture.shell.openShortcut();
    expect(fixture.shell.fullPageChatActive, isTrue);
    expect(fixture.host.currentContent?.id, ChatRoute.channel(9).routeId);
  });

  test('the Chat shortcut opens browse when there are no channels', () async {
    final fixture = await _fixture(channels: const ChatChannels());
    addTearDown(fixture.dispose);
    await fixture.shell.openShortcut();
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

Future<_Fixture> _fixture({required ChatChannels channels}) async {
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
  );
  return _Fixture(
    chat: chat,
    host: host,
    shell: shell,
    settingsListenable: settingsListenable,
  );
}

final class _Fixture {
  const _Fixture({
    required this.chat,
    required this.host,
    required this.shell,
    required this.settingsListenable,
  });

  final ChatController chat;
  final _NavigationHost host;
  final ChatShellService shell;
  final ValueNotifier<SiteConfig> settingsListenable;

  void dispose() {
    shell.dispose();
    chat.dispose();
    settingsListenable.dispose();
    host.dispose();
  }
}

final class _NavigationHost implements PluginNavigationHost {
  @override
  bool get desktopPanelsEnabled => false;
  _NavigationHost({required this.instance, required this.totals})
    : _contentStack = [
        ContentRoute.fromDestination(instance.defaultDestination),
      ];

  DiscourseInstance instance;
  final NotificationTotals totals;
  Rect? bounds;
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
  Rect? get readerContentBounds => bounds;

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
  void pushContent(ContentRoute route, {bool newTab = false}) {
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
