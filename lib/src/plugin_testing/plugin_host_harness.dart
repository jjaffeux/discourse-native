import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app.dart';
import '../data/authenticator.dart';
import '../data/discourse_api.dart';
import '../data/draft_store.dart';
import '../data/forum_tab_store.dart';
import '../data/instance_store.dart';
import '../data/private_storage.dart';
import '../data/secure_store.dart';
import '../data/site_message_bus_bootstrap.dart';
import '../data/site_tracker.dart';
import '../data/update_store.dart';
import '../data/updater.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/notification_totals.dart';
import '../models/sidebar.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/topic.dart';
import '../models/topic_tracking_state.dart';
import '../plugin_api/core_plugin_manifest.dart';
import '../plugin_api/discourse_model_codec.dart';
import '../plugin_api/plugin_runtime.dart';
import '../shell/shell_controller.dart';
import '../shell/shell_scope.dart';

@immutable
final class PluginHostUser {
  const PluginHostUser({required this.username, this.id, this.name});

  final String username;
  final int? id;
  final String? name;

  DiscourseUser _toCore() =>
      DiscourseUser(username: username, id: id, name: name);
}

@immutable
final class PluginHostSite {
  const PluginHostSite({
    required this.url,
    this.title,
    this.apiKey,
    this.user,
    this.config = const SiteConfig.unknown(),
    this.loginRequired = false,
  });

  final String url;
  final String? title;
  final String? apiKey;
  final PluginHostUser? user;
  final SiteConfig config;
  final bool loginRequired;

  DiscourseInstance _toCore() {
    final uri = Uri.parse(url);
    return DiscourseInstance(
      url: uri.origin,
      title: title ?? uri.host,
      apiVersion: 4,
      loginRequired: loginRequired,
      user: user?._toCore(),
      config: config,
    );
  }
}

final class PluginHostHarness {
  PluginHostHarness._({
    required this._dependencies,
    required this._controller,
    required this._plugins,
  });

  static Future<PluginHostHarness> open({
    required PluginApiTransport transport,
    PluginManifest manifest = corePluginManifest,
    Iterable<PluginHostSite> sites = const [],
    Iterable<String> emptyFeedPaths = const ['/latest.json'],
  }) async {
    final installed = PluginInstaller.install(manifest);
    final dependencies = await _PluginHostDependencies.create(
      transport: transport,
      sites: sites,
      emptyFeedPaths: emptyFeedPaths,
      models: installed.models,
    );
    final controller = ShellController(
      instanceStore: dependencies.instances,
      api: dependencies.api,
      authenticator: dependencies.authenticator,
      drafts: dependencies.drafts,
      forumTabs: dependencies.forumTabs,
      trackers: dependencies.trackers,
      updater: const UnsupportedUpdater(),
      updateStore: dependencies.updateStore,
      plugins: installed,
      initialRootMode: ShellRootMode.forum,
    );
    try {
      await controller.load();
    } catch (_) {
      controller.dispose();
      await controller.pluginTeardown;
      await installed.close();
      rethrow;
    }
    return PluginHostHarness._(
      dependencies: dependencies,
      controller: controller,
      plugins: installed,
    );
  }

  static Future<PluginHostHarness> forApp({
    required PluginApiTransport transport,
    Iterable<PluginHostSite> sites = const [],
    Iterable<String> emptyFeedPaths = const ['/latest.json'],
  }) async => PluginHostHarness._(
    dependencies: await _PluginHostDependencies.create(
      transport: transport,
      sites: sites,
      emptyFeedPaths: emptyFeedPaths,
      models: const DiscourseModelCodec.core(),
    ),
    controller: null,
    plugins: null,
  );

  final _PluginHostDependencies _dependencies;
  final ShellController? _controller;
  final InstalledPlugins? _plugins;
  bool _closed = false;

  ShellController get _shell {
    final controller = _controller;
    if (controller == null) {
      throw StateError('This PluginHostHarness was created for an app test.');
    }
    return controller;
  }

  ContentRoute? get currentContent => _shell.currentContent;

  List<ContentRoute> get contentStack => _shell.contentStack;

  T require<T extends Object>(PluginServiceKey<T> key) =>
      _shell.pluginSession.require(key);

  bool popContent() => _shell.handleBack(canReturnToSidebar: false);

  Widget scope({required Widget child}) =>
      ShellScope(controller: _shell, child: child);

  Widget buildApp({Key? key, PluginManifest manifest = corePluginManifest}) =>
      DiscourseApp(
        key: key,
        store: _dependencies.instances,
        api: _dependencies.api,
        authenticator: _dependencies.authenticator,
        drafts: _dependencies.drafts,
        forumTabs: _dependencies.forumTabs,
        trackers: _dependencies.trackers,
        updater: const UnsupportedUpdater(),
        updateStore: _dependencies.updateStore,
        initialRootMode: ShellRootMode.forum,
        pluginManifest: manifest,
      );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final controller = _controller;
    if (controller != null) {
      controller.dispose();
      await controller.pluginTeardown;
      await _plugins?.close();
    } else {
      _dependencies.api.close();
    }
  }
}

final class _PluginHostDependencies {
  const _PluginHostDependencies({
    required this.instances,
    required this.api,
    required this.authenticator,
    required this.drafts,
    required this.forumTabs,
    required this.trackers,
    required this.updateStore,
  });

  static Future<_PluginHostDependencies> create({
    required PluginApiTransport transport,
    required Iterable<PluginHostSite> sites,
    required Iterable<String> emptyFeedPaths,
    required DiscourseModelCodec models,
  }) async {
    final scenarioSites = List<PluginHostSite>.unmodifiable(sites);
    final coreSites = List<DiscourseInstance>.unmodifiable(
      scenarioSites.map((site) => site._toCore()),
    );
    final secureStorage = _MemoryPrivateStorage();
    final secureStore = SecureStore(
      storage: secureStorage,
      legacyClientIds: secureStorage,
      clientIds: _MemoryClientIdPersistence(),
      tokenGenerator: () => 'test-client',
    );
    for (final site in scenarioSites) {
      if (site.apiKey case final apiKey?) {
        await secureStore.writeApiKey(Uri.parse(site.url).origin, apiKey);
      }
    }
    final authenticator = Authenticator(store: secureStore);
    final api = _PluginHostApi(
      transport: transport,
      sites: coreSites,
      emptyFeedPaths: emptyFeedPaths,
      models: models,
    );
    return _PluginHostDependencies(
      instances: _MemoryInstanceStore(coreSites),
      api: api,
      authenticator: authenticator,
      drafts: _MemoryDraftStore(),
      forumTabs: ForumTabStore.memory(),
      trackers: _memoryTracker,
      updateStore: UpdateStore(persistence: _MemoryUpdatePersistence()),
    );
  }

  final _MemoryInstanceStore instances;
  final _PluginHostApi api;
  final Authenticator authenticator;
  final _MemoryDraftStore drafts;
  final ForumTabStore forumTabs;
  final SiteTrackerFactory trackers;
  final UpdateStore updateStore;
}

final class _PluginHostApi extends DiscourseApi {
  _PluginHostApi({
    required PluginApiTransport transport,
    required Iterable<DiscourseInstance> sites,
    required Iterable<String> emptyFeedPaths,
    required super.models,
  }) : _pluginTransport = transport,
       _sites = {for (final site in sites) site.url: site},
       _emptyFeedPaths = Set.unmodifiable(emptyFeedPaths),
       super(client: _NoNetworkClient());

  final PluginApiTransport _pluginTransport;
  final Map<String, DiscourseInstance> _sites;
  final Set<String> _emptyFeedPaths;
  bool _closed = false;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => _pluginTransport.pluginGetJson(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    final transport = _pluginTransport;
    if (transport case final PluginJsonListTransport listTransport) {
      return listTransport.pluginGetJsonList(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
    throw StateError('The supplied plugin transport has no JSON-list port.');
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => _pluginTransport.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (!_emptyFeedPaths.contains(path)) {
      throw StateError('No empty core feed configured for $path.');
    }
    return const TopicList(topics: []);
  }

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async => null;

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => _site(siteUrl).config;

  @override
  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => const {};

  @override
  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => SiteEmojiCatalog.empty;

  @override
  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => const {};

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => CategoryLoadResult(const []);

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => const NotificationTotals();

  @override
  Future<SiteMessageBusBootstrap?> messageBusBootstrap({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => null;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final user = _site(siteUrl).user;
    if (user == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    return user;
  }

  @override
  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async => TopicTrackingState();

  @override
  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => const [];

  DiscourseInstance _site(String siteUrl) {
    final site = _sites[siteUrl];
    if (site == null) throw StateError('No plugin host site for $siteUrl.');
    return site;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    super.close();
  }
}

final class _MemoryInstanceStore implements InstanceStore {
  _MemoryInstanceStore(Iterable<DiscourseInstance> instances)
    : _instances = List.of(instances);

  List<DiscourseInstance> _instances;

  @override
  Future<List<DiscourseInstance>> load() async => List.unmodifiable(_instances);

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    _instances = List.of(instances);
  }
}

final class _MemoryDraftStore implements DraftStore {
  final Map<String, String> _drafts = {};

  static String _key(String siteUrl, String draftKey) => '$siteUrl::$draftKey';

  @override
  Future<String?> read(String siteUrl, String draftKey) async =>
      _drafts[_key(siteUrl, draftKey)];

  @override
  Future<DraftStoreRead> readChecked(String siteUrl, String draftKey) async =>
      (value: await read(siteUrl, draftKey), succeeded: true);

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (ifCurrent?.call() == false) return;
    _drafts[_key(siteUrl, draftKey)] = data;
  }

  @override
  Future<void> clear(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    if (ifCurrent?.call() == false) return;
    _drafts.remove(_key(siteUrl, draftKey));
  }

  @override
  Future<bool> clearChecked(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    if (ifCurrent?.call() == false) return false;
    _drafts.remove(_key(siteUrl, draftKey));
    return true;
  }

  @override
  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    if (ifCurrent?.call() == false) return;
    _drafts.removeWhere((key, _) => key.startsWith('$siteUrl::'));
  }
}

final class _MemoryPrivateStorage implements PrivateStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

final class _MemoryClientIdPersistence implements ClientIdPersistence {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}

final class _MemoryUpdatePersistence implements UpdatePersistence {
  String? _channel;
  int? _lastChecked;

  @override
  Future<String?> readChannelName() async => _channel;

  @override
  Future<bool> writeChannelName(String value) async {
    _channel = value;
    return true;
  }

  @override
  Future<int?> readLastCheckedMillis() async => _lastChecked;

  @override
  Future<bool> writeLastCheckedMillis(int value) async {
    _lastChecked = value;
    return true;
  }
}

SiteTracker _memoryTracker({
  required String siteUrl,
  required void Function() onIncomingTopics,
  required void Function(Object? data) onNotifications,
  required void Function(Object? data) onReviewableCounts,
  int? userId,
  String? apiKey,
  String? clientId,
  bool Function()? shouldLongPoll,
  Map<String, int?> initialLastIds = const {},
}) => SiteTracker(
  siteUrl: siteUrl,
  onIncomingTopics: onIncomingTopics,
  onNotifications: onNotifications,
  onReviewableCounts: onReviewableCounts,
  userId: userId,
  apiKey: apiKey,
  clientId: clientId,
  shouldLongPoll: shouldLongPoll,
  initialLastIds: initialLastIds,
  httpClient: _NoNetworkClient(),
  messageBus: _MemoryMessageBus(),
);

final class _MemoryMessageBus implements SiteMessageBusSession {
  final List<_MemoryMessageBusSubscription> _subscriptions = [];

  @override
  SiteMessageBusSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    late final _MemoryMessageBusSubscription subscription;
    subscription = _MemoryMessageBusSubscription(
      () => _subscriptions.remove(subscription),
    );
    _subscriptions.add(subscription);
    return subscription;
  }

  @override
  void start() {}

  @override
  void stop() {}

  @override
  void pollNow() {}

  @override
  Future<void> close() async {
    final subscriptions = List.of(_subscriptions);
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  }
}

final class _MemoryMessageBusSubscription
    implements SiteMessageBusSubscription {
  _MemoryMessageBusSubscription(this._remove);

  final void Function() _remove;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _remove();
  }
}

final class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError(
      'Unexpected core network request: ${request.method} ${request.url.path}',
    );
  }
}
