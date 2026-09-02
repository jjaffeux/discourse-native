import 'dart:async';
import 'dart:ui' show Color, Rect;

import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, ValueListenable;
import 'package:flutter/scheduler.dart';

import '../data/account_session_coordinator.dart';
import '../data/aggregate_preferences_store.dart';
import '../data/app_settings_store.dart';
import '../data/authenticator.dart';
import '../data/discourse_api_contracts.dart';
import '../data/draft_store.dart';
import '../data/emoji_picker_store.dart';
import '../data/forum_tab_store.dart';
import '../data/groups_api.dart';
import '../data/http_transport.dart';
import '../data/instance_store.dart';
import '../data/shell_api_ports.dart';
import '../data/site_image_repository.dart';
import '../data/site_lifecycle.dart';
import '../data/site_tracker.dart';
import '../data/store.dart';
import '../data/update_store.dart';
import '../data/updater.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/bounded_lru_cache.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/bookmark.dart';
import '../models/bookmark_feed.dart';
import '../models/category_feed.dart';
import '../models/category_sidebar.dart';
import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/forum_workspace.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/group_route.dart';
import '../models/json.dart';
import '../models/list_link.dart';
import '../models/notification_totals.dart';
import '../models/notification_type_counts.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/post_flag.dart';
import '../models/post_likers.dart';
import '../models/post_revision.dart';
import '../models/search_results.dart';
import '../models/sidebar.dart';
import '../models/sidebar_tag.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/tag_directory_feed.dart';
import '../models/tag_sidebar.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../models/topic_filter.dart';
import '../models/topic_link.dart';
import '../models/topic_tracking_state.dart';
import '../models/user_activity.dart';
import '../models/user_card.dart';
import '../models/user_draft.dart';
import '../models/user_preferences.dart';
import '../models/user_status.dart';
import '../models/user_summary.dart';
import '../plugin_api/bookmark_host.dart';
import '../plugin_api/core_plugin_host.dart';
import '../plugin_api/core_plugin_manifest.dart';
import '../plugin_api/emoji_preferences.dart';
import '../plugin_api/plugin_runtime.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/d_icons.dart';
import 'account_activity_controller.dart';
import 'aggregate_feed_controller.dart';
import 'app_settings_controller.dart';
import 'composer_autocomplete.dart';
import 'composer_controller.dart';
import 'composer_draft_coordinator.dart';
import 'composer_pills.dart';
import 'composer_quotes.dart';
import 'composer_triggers.dart';
import 'do_not_disturb_controller.dart';
import 'draft_list_controller.dart';
import 'groups_controller.dart';
import 'hashtag.dart';
import 'plugin_background_retention.dart';
import 'post_quote.dart';
import 'preferences_controller.dart';
import 'shell_search_controller.dart';
import 'site_presentation_controller.dart';
import 'site_url.dart';
import 'topic_category_path.dart' as category_path;
import 'topic_feed_controller.dart';
import 'topic_read_controller.dart';
import 'update_controller.dart';
import 'user_summary_controller.dart';

enum MobilePane { sidebar, content }

enum ShellRootMode { forum, aggregate, settings }

enum InstanceLoadStatus { loading, ready, failed }

enum AggregateTopicOpenResult { opened, tabLimitReached, unavailable }

typedef TopicMoveDestination = ({int id, String title, String slug});

// A site can retain a substantial topic, post, and taxonomy working set, while
// per-site/type shares stop one long browsing session from displacing every
// other connected forum.
const _shellEntityStorePolicy = StorePolicy(
  maxEntries: 4096,
  maxEntriesPerSite: 2048,
  maxEntriesPerSiteAndType: 1024,
);

typedef TopicMoveDestinationSearchResult = ({
  List<TopicMoveDestination> destinations,
  String? error,
});
typedef TopicPostMoveResult = ({String? destinationUrl, String? error});
typedef _SessionValue<T> = ({T value});
typedef _CategorySidebarCache = ({
  List<TopicCategory> categories,
  DiscourseUser? user,
  SiteConfig config,
  SidebarSection section,
});
typedef _TagSidebarCache = ({
  List<SidebarTag> tags,
  bool display,
  String? username,
  SidebarSection section,
});
typedef _SettingsReturnTarget = ({
  ShellRootMode rootMode,
  MobilePane mobilePane,
});
typedef _PluginPaneKey = ({String siteUrl, String tabId, PluginId owner});
typedef _PluginPaneStateKey = ({String siteUrl, String tabId});

int? _destinationNumericId(String destinationId, String prefix) {
  if (!destinationId.startsWith(prefix)) return null;
  final id = int.tryParse(destinationId.substring(prefix.length));
  return id != null && id > 0 ? id : null;
}

sealed class _BookmarkWriteContext {
  const _BookmarkWriteContext();
}

final class _TopicBookmarkWriteContext extends _BookmarkWriteContext {
  const _TopicBookmarkWriteContext(this.topicId);

  final int topicId;
}

final class _PluginBookmarkWriteContext extends _BookmarkWriteContext {
  const _PluginBookmarkWriteContext();
}

const _pluginBookmarkWriteContext = _PluginBookmarkWriteContext();

class ShellController extends FrameSafeNotifier
    implements
        PluginNavigationHost,
        BookmarkHost,
        PluginNotificationFeedHost,
        AccountSessionHost {
  ShellController({
    required this.instanceStore,
    required ShellApiCapabilities api,
    required this.authenticator,
    required this.drafts,
    EmojiPickerStore? emojiPickerStore,
    AggregatePreferencesStore? aggregatePreferences,
    AppSettingsStore? appSettingsStore,
    ForumTabStore? forumTabs,
    this.forumTabsEnabled = true,
    Store? store,
    SiteLifecycle? lifecycle,
    SiteImageRepository? siteImages,
    this.trackers = SiteTracker.new,
    Updater updater = const UnsupportedUpdater(),
    UpdateStore? updateStore,
    this.ownsApi = true,
    this.topicLoadTimeout = const Duration(seconds: 30),
    this.anchorPersistDebounce = const Duration(milliseconds: 500),
    this.pluginNotificationFeedRefreshDebounce = const Duration(
      milliseconds: 500,
    ),
    ShellRootMode initialRootMode = ShellRootMode.forum,
    InstalledPlugins? plugins,
    PluginDiagnosticsReporter? pluginDiagnosticsReporter,
  }) : api = ShellApiPorts.fromCapabilities(api),
       forumTabs = forumTabs ?? ForumTabStore.memory(),
       aggregatePreferences =
           aggregatePreferences ?? AggregatePreferencesStore(),
       appSettings = AppSettingsController(
         store:
             appSettingsStore ??
             AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
       ),
       emojiPickerStore = emojiPickerStore ?? EmojiPickerStore(),
       assert(topicLoadTimeout > Duration.zero),
       assert(anchorPersistDebounce >= Duration.zero),
       assert(pluginNotificationFeedRefreshDebounce >= Duration.zero),
       store = store ?? Store(policy: _shellEntityStorePolicy),
       lifecycle = lifecycle ?? SiteLifecycle(),
       _providedSiteImages = siteImages,
       _rootMode = initialRootMode,
       _ownsPlugins = plugins == null,
       _pluginDiagnosticsReporter =
           pluginDiagnosticsReporter ??
           const PluginDiagnosticsReporter.ambient(),
       plugins = plugins ?? PluginInstaller.install(corePluginManifest),
       updates = UpdateController(
         updater: updater,
         store: updateStore ?? UpdateStore(),
       );

  final InstanceStore instanceStore;
  final ForumTabStore forumTabs;
  final AggregatePreferencesStore aggregatePreferences;
  final AppSettingsController appSettings;

  final bool forumTabsEnabled;

  @override
  final Store store;

  final ShellApiPorts api;

  final bool ownsApi;

  final Duration topicLoadTimeout;

  final Duration anchorPersistDebounce;

  final Duration pluginNotificationFeedRefreshDebounce;

  final Authenticator authenticator;
  final DraftStore drafts;
  final EmojiPickerStore emojiPickerStore;
  final SiteLifecycle lifecycle;
  late final AccountSessionCoordinator _accountSessions =
      AccountSessionCoordinator(
        authenticator: authenticator,
        instances: instanceStore,
        drafts: drafts,
        lifecycle: lifecycle,
        api: api.site,
        host: this,
        reportError: (error, stackTrace, operation, {required bool warning}) {
          _reportOperationalError(
            error,
            stackTrace,
            operation,
            severity: warning
                ? DiagnosticSeverity.warning
                : DiagnosticSeverity.error,
          );
        },
      );
  final SiteImageRepository? _providedSiteImages;
  final InstalledPlugins plugins;
  final bool _ownsPlugins;
  final PluginDiagnosticsReporter _pluginDiagnosticsReporter;
  Future<void>? _pluginTeardownFuture;

  Future<void> get pluginTeardown =>
      _pluginTeardownFuture ?? Future<void>.value();

  late final PluginBackgroundRetentionRegistry _backgroundRetention =
      PluginBackgroundRetentionRegistry(
        canRetain: (siteUrl) => _instanceAt(siteUrl) != null,
        onChanged: _syncTracking,
      );

  late final SiteImageRepository siteImages =
      _providedSiteImages ??
      SiteImageRepository(credentials: authenticator, lifecycle: lifecycle);

  late final PluginSession _pluginSession = plugins.openSession(
    PluginHostBindings(<PluginHostPort<Object>>[
      PluginHostPort<Object>(corePluginTransportPort, api.pluginTransport),
      PluginHostPort<Object>(corePluginModelCodecPort, api.models),
      PluginHostPort<Object>(
        corePluginRequestPort,
        _ShellPluginRequestHost(this),
      ),
      _pluginPostHostPort(),
      PluginHostPort<Object>(
        corePluginAccountConnectionPort,
        _ShellPluginAccountConnectionHost(this),
      ),
      PluginHostPort<Object>(
        pluginDiagnosticsReporterPort,
        _pluginDiagnosticsReporter,
      ),
      PluginHostPort<Object>(
        corePluginSiteStatePort,
        PluginSiteStateHost(
          currentUserFor: (siteUrl) => _instanceAt(siteUrl)?.user,
          siteConfigFor: siteConfigFor,
        ),
      ),
      PluginHostPort<Object>(
        corePluginStaticContributionsPort,
        plugins.staticContributionsFor(const PluginId('core')),
        scopeToConsumer: plugins.staticContributionsFor,
      ),
      PluginHostPort<Object>(
        corePluginCurrentSitePort,
        () => currentInstance?.url,
      ),
      PluginHostPort<Object>(corePluginPostFlagCatalogPort, postFlagTypesFor),
      _pluginAccountEventsHostPort(),
      _pluginTargetHostPort(),
      _pluginFreshAccountHostPort(),
      PluginHostPort<Object>(
        corePluginTopicRefreshPort,
        PluginTopicRefreshHost(
          reloadTopic: (siteUrl, topicId) =>
              _refetchTopic(siteUrl, topicId, ''),
        ),
      ),
      _pluginTrackerHostPort(),
      _pluginBackgroundRetentionHostPort(),
      PluginHostPort<Object>(
        corePluginUserPort,
        (String siteUrl) => _instanceAt(siteUrl)?.user?.id,
      ),
      PluginHostPort<Object>(
        corePluginPresentationPort,
        (String siteUrl) => _presentation.resolveConfig(siteUrl),
      ),
      PluginHostPort<Object>(
        corePluginNavigationPort,
        _ShellPluginNavigationHost(this, () => isDisposed),
      ),
      PluginHostPort<Object>(
        corePluginRouteNavigationPort,
        _ShellPluginRouteNavigationHost(this),
      ),
      PluginHostPort<Object>(
        corePluginTopicListNavigationPort,
        _ShellPluginTopicListNavigationHost(this),
      ),
      _pluginBookmarkHostPort(),
      _pluginComposerHostPort(),
      _pluginEmojiHostPort(),
      _pluginNotificationFeedHostPort(),
    ]),
  );

  PluginSession get pluginSession => _pluginSession;

  PluginHostPort<Object> _pluginBookmarkHostPort() {
    final factory = _ShellPluginBookmarkHostFactory(this);
    return PluginHostPort<Object>(
      corePluginBookmarkPort,
      factory,
      scopeToConsumer: factory.scopedTo,
    );
  }

  PluginHostPort<Object> _pluginAccountEventsHostPort() {
    final host = PluginAccountEventsHost(
      updateNotificationCounter: (siteUrl, id, reduce) {
        final counter = plugins.registry.notificationCounter(id);
        if (counter == null) {
          throw PluginInstallationException(
            'Notification counter ${id.id} is not registered.',
          );
        }
        accountActivity.applyPluginCounter(siteUrl, counter, reduce);
      },
      markSiteUnreachable: _markForumUnavailable,
    );
    return PluginHostPort<Object>(
      corePluginAccountEventsPort,
      host,
      scopeToConsumer: (consumer) => PluginAccountEventsHost(
        updateNotificationCounter: (siteUrl, id, reduce) {
          if (id.owner != consumer) {
            throw PluginInstallationException(
              'Plugin $consumer cannot update notification counter ${id.id}.',
            );
          }
          host.updateNotificationCounter(siteUrl, id, reduce);
        },
        markSiteUnreachable: host.markSiteUnreachable,
      ),
    );
  }

  PluginHostPort<Object> _pluginPostHostPort() => PluginHostPort<Object>(
    corePluginPostPort,
    _ShellPluginPostHost(this, const PluginId('core')),
    scopeToConsumer: (consumer) => _ShellPluginPostHost(this, consumer),
  );

  PluginHostPort<Object> _pluginTargetHostPort() => PluginHostPort<Object>(
    corePluginTargetPort,
    _ShellPluginTargetHost(this, const PluginId('core')),
    scopeToConsumer: (consumer) => _ShellPluginTargetHost(this, consumer),
  );

  PluginHostPort<Object> _pluginFreshAccountHostPort() =>
      PluginHostPort<Object>(
        corePluginFreshAccountPort,
        _ShellPluginFreshAccountHost(this, const PluginId('core')),
        scopeToConsumer: (consumer) =>
            _ShellPluginFreshAccountHost(this, consumer),
      );

  PluginHostPort<Object> _pluginComposerHostPort() {
    final host = PluginComposerHost(
      buildComposer: buildPluginComposer,
      openNewTopic: openNewTopicFromPlugin,
      isActive: (composer) =>
          !isDisposed && identical(visibleComposer, composer),
      siteConfigFor: siteConfigFor,
      siteConfigListenableFor: _pluginSiteConfigListenableFor,
    );
    return PluginHostPort<Object>(
      corePluginComposerPort,
      host,
      scopeToConsumer: (consumer) => PluginComposerHost(
        buildComposer: (request) {
          if (request.kind.owner != consumer) {
            throw PluginInstallationException(
              'Plugin $consumer cannot build composer target '
              '${request.kind.id}.',
            );
          }
          return host.buildComposer(request);
        },
        openNewTopic: host.openNewTopic,
        isActive: host.isActive,
        siteConfigFor: host.siteConfigFor,
        siteConfigListenableFor: host.siteConfigListenableFor,
      ),
    );
  }

  PluginHostPort<Object> _pluginEmojiHostPort() {
    final host = PluginEmojiHost(
      preferences: emojiPickerStore,
      siteConfigFor: siteConfigFor,
      loadCatalog: (siteUrl, {refresh = false}) =>
          refresh ? refreshEmojiCatalog(siteUrl) : ensureEmojiCatalog(siteUrl),
      loadSearchAliases: (siteUrl, {refresh = false}) => refresh
          ? refreshEmojiSearchAliases(siteUrl)
          : ensureEmojiSearchAliases(siteUrl),
      resolveUrl: emojiUrlFor,
    );
    return PluginHostPort<Object>(
      corePluginEmojiPort,
      host,
      scopeToConsumer: (consumer) => PluginEmojiHost(
        preferences: _ScopedEmojiPreferenceStore(emojiPickerStore, consumer),
        siteConfigFor: host.siteConfigFor,
        loadCatalog: host.loadCatalog,
        loadSearchAliases: host.loadSearchAliases,
        resolveUrl: host.resolveUrl,
      ),
    );
  }

  PluginHostPort<Object> _pluginNotificationFeedHostPort() {
    final host = _ShellPluginNotificationFeedHost(this);
    return PluginHostPort<Object>(
      corePluginNotificationFeedPort,
      host,
      scopeToConsumer: (consumer) =>
          _ShellScopedPluginNotificationFeedHost(host, consumer, {
            for (final source in plugins.registry.notificationFeeds)
              if (source.id.owner == consumer) source.id: source,
          }),
    );
  }

  PluginHostPort<Object> _pluginTrackerHostPort() {
    PluginTrackerReader scopedReader(PluginId consumer) => (siteUrl) {
      final tracker = _trackers[siteUrl];
      if (tracker == null) return null;
      return tracker.pluginLiveChannels(plugins.liveChannelScopesFor(consumer));
    };

    return PluginHostPort<Object>(
      corePluginTrackerPort,
      scopedReader(const PluginId('core')),
      scopeToConsumer: scopedReader,
    );
  }

  PluginHostPort<Object> _pluginBackgroundRetentionHostPort() =>
      PluginHostPort<Object>(
        corePluginBackgroundRetentionPort,
        _backgroundRetention.scopedTo(const PluginId('core')),
        scopeToConsumer: _backgroundRetention.scopedTo,
        revokeConsumer: _backgroundRetention.releaseOwner,
      );

  Set<String> get _pluginBackgroundSiteUrls => _backgroundRetention.siteUrls;

  Future<PluginWriteCredential> pluginWriteCredential(String siteUrl) =>
      _credentialForWrite(siteUrl);

  bool beginPluginPostWrite(String siteUrl, int postId) =>
      _beginPostWrite(_postKey(siteUrl, postId));

  void endPluginPostWrite(String siteUrl, int postId) =>
      _endPostWrite(siteUrl, postId);

  bool pluginPostWriteInFlight(String siteUrl, int postId) =>
      _postWritesInFlight.contains(_postKey(siteUrl, postId));

  Future<void> refreshPluginPost(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    SiteLease lease,
  ) => _refreshPost(siteUrl, topicId, postId, apiKey, lease);

  void notifyPluginStateChanged() => _notify();

  void reportPluginError(
    Object error,
    StackTrace stackTrace,
    String operation,
  ) => _reportOperationalError(error, stackTrace, operation);

  void _reportOperationalError(
    Object error,
    StackTrace stackTrace,
    String operation, {
    bool degraded = true,
    DiagnosticSeverity severity = DiagnosticSeverity.error,
  }) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'shell',
      severity: severity,
      handled: true,
      degraded: degraded,
    );
  }

  void _observePluginLifecycle(Future<void> task, String operation) {
    unawaited(
      task.onError((Object error, StackTrace stackTrace) {
        _reportOperationalError(
          error,
          stackTrace,
          operation,
          severity: DiagnosticSeverity.warning,
        );
      }),
    );
  }

  Future<PluginWriteCredential> _credentialForWrite(String siteUrl) async {
    try {
      final apiKey = await authenticator.apiKeyFor(siteUrl);
      return apiKey == null
          ? (
              apiKey: null,
              failure: const WriteException(WriteFailure.forbidden),
            )
          : (apiKey: apiKey, failure: null);
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'authentication.readWriteCredential',
      );
      return (
        apiKey: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }

  Future<_SessionValue<T>?> _readSessionValue<T>(
    SiteLease lease,
    Future<T> Function() read,
  ) async {
    final value = await read();
    if (isDisposed || !lease.isCurrent) return null;
    return (value: value);
  }

  Future<T> _awaitTopicLoadStage<T>(
    Future<T> stage,
    Stopwatch elapsed,
    String description,
  ) {
    final remaining = topicLoadTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      return Future<T>.error(
        TimeoutException('Timed out $description.', topicLoadTimeout),
      );
    }
    return stage.timeout(
      remaining,
      onTimeout: () =>
          throw TimeoutException('Timed out $description.', topicLoadTimeout),
    );
  }

  final SiteTrackerFactory trackers;

  final UpdateController updates;

  late final AccountActivityController accountActivity =
      AccountActivityController(
        api: api.accountActivity,
        credentials: authenticator,
        lifecycle: lifecycle,
        onTotalsLoaded: _onTotalsLoaded,
        onTotalsChanged: _onTotalsChanged,
        onGroupedUnreadAuthorityAdvanced:
            _advanceGroupedUnreadNotificationVersion,
      );

  late final DoNotDisturbController doNotDisturb = DoNotDisturbController(
    api: api.doNotDisturb,
    credentials: authenticator,
    lifecycle: lifecycle,
    onCommitted: _commitDoNotDisturb,
  );

  late final DraftListController draftList = DraftListController(
    api: api.drafts,
    credentials: authenticator,
    lifecycle: lifecycle,
  );

  late final UserSummaryController userSummary = UserSummaryController(
    api: api.userSummaries,
    credentials: authenticator,
    lifecycle: lifecycle,
  );

  late final GroupsController groups = GroupsController(
    api: GroupsApi(api.pluginTransport, api.models),
    credentials: authenticator,
    lifecycle: lifecycle,
  );

  late final PreferencesController preferences = PreferencesController(
    api: api.userPreferences,
    credentials: authenticator,
    lifecycle: lifecycle,
    onSaved: _onPreferencesSaved,
  );

  late final TopicFeedController topicFeeds = _createTopicFeedController();

  late final AggregateFeedController aggregate = AggregateFeedController(
    api: api.topicFeeds,
    credentials: authenticator,
    lifecycle: lifecycle,
    store: store,
    preferences: aggregatePreferences,
    readPersonalizationVersion: _siteBookmarkVersion,
    prepareTopic: (siteUrl, topic, version) =>
        _prepareTopicForStore(siteUrl, topic, version),
  );

  TopicFeedController _createTopicFeedController() {
    return TopicFeedController(
      api: api.topicFeeds,
      credentials: authenticator,
      lifecycle: lifecycle,
      store: store,
      onFeedLoaded: (instance, apiKey, categories, categoryIds) {
        if (categories.isNotEmpty) {
          _mergeCategories(instance.url, categories);
          _notify();
        }
        unawaited(_ensureCategoriesFor(instance));
        unawaited(_ensureCategoryIds(instance, apiKey, categoryIds));
      },
      readPersonalizationVersion: _siteBookmarkVersion,
      prepareTopicForStore: _prepareTopicForStore,
    );
  }

  late final TopicReadController _topicReads = TopicReadController(
    api: api.topicReads,
    credentials: authenticator,
    lifecycle: lifecycle,
    store: store,
    reportError: (error, stackTrace, operation) {
      _reportOperationalError(
        error,
        stackTrace,
        operation,
        severity: DiagnosticSeverity.warning,
      );
    },
  );

  late final ShellSearchController search = ShellSearchController(
    api: api.search,
    credentials: authenticator,
    lifecycle: lifecycle,
  );

  SitePresentationController? _sitePresentation;
  final Map<String, _PluginSiteConfigListenable> _pluginSiteConfigListenables =
      {};

  ValueListenable<SiteConfig> _pluginSiteConfigListenableFor(String siteUrl) =>
      _pluginSiteConfigListenables.putIfAbsent(
        siteUrl,
        () => _PluginSiteConfigListenable(
          _presentation,
          () => siteConfigFor(siteUrl),
        ),
      );

  SitePresentationController get _presentation =>
      _sitePresentation ??= _createSitePresentationController();

  SitePresentationController _createSitePresentationController() {
    final controller = SitePresentationController(
      loadAppearance: _loadSiteAppearance,
      loadConfig: _loadSiteConfig,
      loadCustomEmojis: _loadCustomEmojis,
      loadEmojiCatalog: _loadEmojiCatalog,
      loadEmojiSearchAliases: _loadEmojiSearchAliases,
      credentials: authenticator,
      lifecycle: lifecycle,
      readPersistedAppearance: (siteUrl) => _instanceAt(siteUrl)?.appearance,
      readPersistedConfig: (siteUrl) => _instanceAt(siteUrl)?.config,
      onAppearanceLoaded: _persistSiteAppearance,
      onConfigLoaded: _persistSiteConfig,
    );
    controller.addListener(_notify);
    return controller;
  }

  Future<SiteAppearance?> _loadSiteAppearance({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    // A failed credential deletion can leave an orphaned key behind. The stored
    // instance identity is the account boundary: signed-out sites may refresh
    // their public colors, but must never forward that leftover credential.
    final instance = _instanceAt(siteUrl);
    final authenticate = apiKey != null && instance?.isConnected == true;
    return api.site.siteAppearance(
      siteUrl: siteUrl,
      username: authenticate ? instance!.user!.username : null,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  Future<SiteConfig> _loadSiteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    // As with appearance, key presence is not account identity: secure storage
    // can retain a key after a failed deletion. A signed-out instance must ask
    // only for the site's public client settings.
    final authenticate =
        apiKey != null && _instanceAt(siteUrl)?.isConnected == true;
    return api.site.siteConfig(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  Future<Map<String, String>> _loadCustomEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final authenticate =
        apiKey != null && _instanceAt(siteUrl)?.isConnected == true;
    return api.site.customEmojis(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  Future<SiteEmojiCatalog> _loadEmojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final authenticate =
        apiKey != null && _instanceAt(siteUrl)?.isConnected == true;
    return api.site.emojiCatalog(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  Future<Map<String, List<String>>> _loadEmojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final authenticate =
        apiKey != null && _instanceAt(siteUrl)?.isConnected == true;
    return api.site.emojiSearchAliases(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  String? _connectingSiteUrl;

  bool get connecting => _connectingSiteUrl == currentInstance?.url;

  final Map<String, String> _connectErrors = {};

  String? get connectError {
    final siteUrl = currentInstance?.url;
    return siteUrl == null ? null : _connectErrors[siteUrl];
  }

  final Set<String> _unavailableForums = {};
  final Set<String> _retryingUnavailableForums = {};

  bool get currentForumUnavailable {
    final siteUrl = currentInstance?.url;
    return siteUrl != null && _unavailableForums.contains(siteUrl);
  }

  bool get retryingCurrentForum {
    final siteUrl = currentInstance?.url;
    return siteUrl != null && _retryingUnavailableForums.contains(siteUrl);
  }

  void _markForumUnavailable(String siteUrl) {
    if (_instanceAt(siteUrl) == null || !_unavailableForums.add(siteUrl)) {
      return;
    }
    _notify();
  }

  Future<void> retryCurrentForum() async {
    final instance = currentInstance;
    final route = currentContent;
    if (instance == null ||
        route == null ||
        !_unavailableForums.contains(instance.url) ||
        !_retryingUnavailableForums.add(instance.url)) {
      return;
    }

    _notify();
    try {
      for (final retry in _pluginSession.capabilities<PluginRouteRetry>()) {
        final result = await retry.retryPluginRoute(instance.url, route.id);
        if (result == PluginRouteRetryResult.notHandled) continue;
        if (!isDisposed && result == PluginRouteRetryResult.succeeded) {
          _unavailableForums.remove(instance.url);
        }
        break;
      }
    } finally {
      if (!isDisposed) {
        _retryingUnavailableForums.remove(instance.url);
        _notify();
      }
    }
  }

  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  }) async {
    for (final handler in _pluginSession.capabilities<PluginLinkHandler>()) {
      if (await handler.openPluginUrl(url, origin: origin)) return true;
    }
    return false;
  }

  Future<bool> openNotificationUrl(String url) async {
    if (!loaded || url.isEmpty || url.length > TopicLink.maximumUrlLength) {
      return false;
    }

    final Uri target;
    try {
      target = requireSafeHttpUrl(Uri.parse(url));
    } on FormatException {
      return false;
    } on UnsafeHttpTransportException {
      return false;
    }

    final owned = _instances.any(
      (instance) => instance.isConnected && instance.serves(target),
    );
    if (!owned) return false;

    final absolute = target.toString();
    if (await openPluginUrl(absolute, origin: PluginLinkOrigin.inApp)) {
      return _revealNotificationTarget();
    }
    if (openGroupUrl(absolute)) return _revealNotificationTarget();
    if (_openTopicUrl(absolute, refresh: true)) {
      return _revealNotificationTarget();
    }
    if (openListUrl(absolute)) return _revealNotificationTarget();
    return false;
  }

  bool _revealNotificationTarget() {
    final changed = _setForumContentRoot();
    if (changed) _notify();
    return true;
  }

  bool _setForumContentRoot() {
    final changed =
        _rootMode != ShellRootMode.forum || _mobilePane != MobilePane.content;
    _settingsReturnTarget = null;
    _rootMode = ShellRootMode.forum;
    _mobilePane = MobilePane.content;
    return changed;
  }

  final List<DiscourseInstance> _instances = [];
  @override
  List<DiscourseInstance> get instances => List.unmodifiable(_instances);
  bool get hasInstances => _instances.isNotEmpty;

  // Reorders are optimistic, just like adding and removing a site. This small
  // drain owns their writes because InstanceStore coalesces queued snapshots:
  // one failed older write must not roll a newer drag out of the rail.
  int _instanceReorderRevision = 0;
  bool _savingInstanceOrder = false;
  List<String> _durableInstanceOrder = const [];
  final List<({int revision, Completer<bool> result})>
  _pendingInstanceReorders = [];

  InstanceLoadStatus _loadStatus = InstanceLoadStatus.loading;

  InstanceLoadStatus get loadStatus => _loadStatus;

  bool get loaded => _loadStatus == InstanceLoadStatus.ready;

  int _instanceIndex = 0;
  int get instanceIndex => _instanceIndex;
  @override
  DiscourseInstance? get currentInstance =>
      hasInstances ? _instances[_instanceIndex] : null;

  String? get currentAccountIdentity {
    final instance = currentInstance;
    return instance == null ? null : _workspaceAccountIdentity(instance);
  }

  final Map<String, ForumWorkspace> _forumWorkspaces = {};
  final Map<_PluginPaneKey, ForumTab> _mainPaneTabs = {};
  final Map<_PluginPaneKey, ForumTab> _pluginPaneTabs = {};
  final Map<_PluginPaneStateKey, PluginId> _activePluginPanes = {};
  final Set<_PluginPaneStateKey> _coldPluginPanes = {};
  int _tabSequence = 0;
  ({String siteUrl, String tabId})? _pendingTabSelection;
  bool _tabSelectionSettlementScheduled = false;
  bool _tabSelectionPersistencePending = false;
  Timer? _anchorPersistTimer;
  bool _anchorPersistencePending = false;

  ForumWorkspace? get currentWorkspace {
    final siteUrl = currentInstance?.url;
    return siteUrl == null ? null : _forumWorkspaces[siteUrl];
  }

  ForumWorkspace? workspaceFor(String siteUrl) => _forumWorkspaces[siteUrl];

  ForumTab? get activeTab => currentWorkspace?.activeTab;
  String? get activeTabId => currentWorkspace?.activeTabId;
  List<ForumTab> get tabsForCurrentForum => currentWorkspace?.tabs ?? const [];
  bool get canCreateTab =>
      forumTabsEnabled &&
      (currentWorkspace?.tabs.length ?? 0) < ForumWorkspace.maximumTabs;

  String? get destinationId => activeTab?.rootDestinationId;

  @override
  List<ContentRoute> get contentStack => activeTab?.contentStack ?? const [];
  @override
  ContentRoute? get currentContent => activeTab?.currentContent;
  bool get canPopContent => (activeTab?.contentStack.length ?? 0) > 1;
  bool get canForwardContent => activeTab?.canGoForward ?? false;

  MobilePane _mobilePane = MobilePane.sidebar;
  MobilePane get mobilePane => _mobilePane;

  ShellRootMode _rootMode;
  ShellRootMode get rootMode => _rootMode;

  _SettingsReturnTarget? _settingsReturnTarget;

  ShellRootMode get settingsUnderlayRootMode =>
      _rootMode == ShellRootMode.settings
      ? _settingsReturnTarget?.rootMode ?? ShellRootMode.forum
      : _rootMode;

  MobilePane get settingsUnderlayMobilePane =>
      _rootMode == ShellRootMode.settings
      ? _settingsReturnTarget?.mobilePane ?? MobilePane.sidebar
      : _mobilePane;

  @override
  Listenable get changes => this;

  @override
  bool get forumActive => _rootMode == ShellRootMode.forum;

  ({Object owner, PluginVisibleTopicContext context})? _visibleTopicContext;

  @override
  PluginVisibleTopicContext? get visibleTopicContext {
    final held = _visibleTopicContext?.context;
    if (held == null ||
        currentInstance?.url != held.siteUrl ||
        currentContent?.topicId != held.topicId) {
      return null;
    }
    return held;
  }

  /// Publishes the narrow topic viewport snapshot exposed to plugin writes.
  ///
  /// [owner] makes teardown race-safe when one topic view replaces another:
  /// the retiring view cannot clear a newer view's snapshot.
  void updateVisibleTopicContext({
    required Object owner,
    required String siteUrl,
    required int topicId,
    required Iterable<int> postIds,
  }) {
    if (currentInstance?.url != siteUrl || currentContent?.topicId != topicId) {
      clearVisibleTopicContext(owner);
      return;
    }
    final normalizedPostIds = <int>[];
    final seen = <int>{};
    for (final postId in postIds) {
      if (postId > 0 && seen.add(postId)) normalizedPostIds.add(postId);
    }
    _visibleTopicContext = (
      owner: owner,
      context: PluginVisibleTopicContext(
        siteUrl: siteUrl,
        topicId: topicId,
        postIds: normalizedPostIds,
      ),
    );
  }

  void clearVisibleTopicContext(Object owner) {
    if (identical(_visibleTopicContext?.owner, owner)) {
      _visibleTopicContext = null;
    }
  }

  DiscourseInstance? instanceFor(String siteUrl) => _instanceAt(siteUrl);

  static String _workspaceAccountIdentity(DiscourseInstance instance) =>
      instance.user == null
      ? 'anonymous'
      : 'user:${instance.user!.username.toLowerCase()}';

  String _nextTabId() {
    final held = <String>{
      for (final workspace in _forumWorkspaces.values)
        for (final tab in workspace.tabs) tab.id,
    };
    late String id;
    do {
      _tabSequence++;
      id =
          'tab-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
          '${_tabSequence.toRadixString(36)}';
    } while (held.contains(id));
    return id;
  }

  ForumTab _newDefaultTab(DiscourseInstance instance) {
    final destination = instance.defaultDestination;
    return ForumTab(
      id: _nextTabId(),
      rootDestinationId: destination.id,
      contentStack: [ContentRoute.fromDestination(destination)],
    );
  }

  ForumWorkspace _newWorkspace(DiscourseInstance instance) {
    final tab = _newDefaultTab(instance);
    return ForumWorkspace(
      siteUrl: instance.url,
      accountIdentity: _workspaceAccountIdentity(instance),
      tabs: [tab],
      activeTabId: tab.id,
    );
  }

  ForumWorkspace _normalizeWorkspace(ForumWorkspace workspace) {
    if (forumTabsEnabled || workspace.tabs.length == 1) return workspace;
    return workspace.copyWith(tabs: [workspace.activeTab]);
  }

  ForumWorkspace _ensureWorkspace(
    DiscourseInstance instance, {
    bool persist = true,
  }) {
    final existing = _forumWorkspaces[instance.url];
    if (existing != null &&
        existing.accountIdentity == _workspaceAccountIdentity(instance)) {
      return existing;
    }
    _forgetPluginPaneTabs(instance.url);
    final workspace = _newWorkspace(instance);
    _forumWorkspaces[instance.url] = workspace;
    if (persist) _persistWorkspaces();
    return workspace;
  }

  void _putWorkspace(ForumWorkspace workspace, {bool persist = true}) {
    final normalized = _normalizeWorkspace(workspace);
    _forumWorkspaces[normalized.siteUrl] = normalized;
    final liveTabIds = {for (final tab in normalized.tabs) tab.id};
    _mainPaneTabs.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _pluginPaneTabs.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _activePluginPanes.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _coldPluginPanes.removeWhere(
      (key) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    if (persist) _persistWorkspaces();
  }

  void _removeWorkspace(String siteUrl, {bool persist = true}) {
    _forgetPluginPaneTabs(siteUrl);
    if (_forumWorkspaces.remove(siteUrl) != null && persist) {
      _persistWorkspaces();
    }
  }

  void _forgetPluginPaneTabs(String siteUrl) {
    _mainPaneTabs.removeWhere((key, _) => key.siteUrl == siteUrl);
    _pluginPaneTabs.removeWhere((key, _) => key.siteUrl == siteUrl);
    _activePluginPanes.removeWhere((key, _) => key.siteUrl == siteUrl);
    _coldPluginPanes.removeWhere((key) => key.siteUrl == siteUrl);
  }

  void _persistWorkspaces() {
    _tabSelectionPersistencePending = false;
    // Any full write already carries the in-memory anchors, so a waiting
    // anchor window has nothing left to add.
    _anchorPersistencePending = false;
    unawaited(forumTabs.save(_forumWorkspaces.values));
  }

  void _schedulePersistAnchors() {
    _anchorPersistencePending = true;
    if (_anchorPersistTimer != null) return;
    _anchorPersistTimer = Timer(anchorPersistDebounce, () {
      _anchorPersistTimer = null;
      if (isDisposed || !_anchorPersistencePending) return;
      _persistWorkspaces();
    });
  }

  void _flushPendingAnchorPersist() {
    _anchorPersistTimer?.cancel();
    _anchorPersistTimer = null;
    if (_anchorPersistencePending) _persistWorkspaces();
  }

  void flushAnchorPersist() {
    if (isDisposed) return;
    _flushPendingAnchorPersist();
  }

  void _replaceTab(
    String siteUrl,
    ForumTab replacement, {
    bool persist = true,
  }) {
    final workspace = _forumWorkspaces[siteUrl];
    if (workspace == null || workspace.tabById(replacement.id) == null) return;
    _putWorkspace(
      workspace.copyWith(
        tabs: [
          for (final tab in workspace.tabs)
            if (tab.id == replacement.id) replacement else tab,
        ],
      ),
      persist: persist,
    );
  }

  void _replaceActiveTab(ForumTab replacement, {bool persist = true}) {
    final siteUrl = currentInstance?.url;
    if (siteUrl != null) {
      _replaceTab(siteUrl, replacement, persist: persist);
    }
  }

  Future<void>? _loadTask;

  Future<void> load() {
    if (loaded || isDisposed) return Future.value();

    final active = _loadTask;
    if (active != null) return active;

    final shouldNotify = _loadStatus != InstanceLoadStatus.loading;
    if (shouldNotify) {
      _loadStatus = InstanceLoadStatus.loading;
    }

    late final Future<void> task;
    task = _load().whenComplete(() {
      if (identical(_loadTask, task)) _loadTask = null;
    });
    _loadTask = task;
    if (shouldNotify) _notify();
    return task;
  }

  Future<void> _load() async {
    final settingsLoad = appSettings.load();
    final storedWorkspaces = forumTabs.load();
    final List<DiscourseInstance> stored;
    try {
      stored = await instanceStore.load();
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'instances.load',
        degraded: false,
      );
      if (!isDisposed) {
        _loadStatus = InstanceLoadStatus.failed;
        _notify();
      }
      await settingsLoad;
      return;
    }

    await settingsLoad;
    if (isDisposed) return;
    _instances
      ..clear()
      ..addAll(stored);
    for (final instance in stored) {
      var totals = instance.notificationTotals;
      final storedGroupedCounts = instance.user?.groupedUnreadNotifications;
      if (totals?.groupedUnreadNotifications.isAvailable != true &&
          storedGroupedCounts?.isAvailable == true) {
        // Older snapshots kept grouped counts only on the current user. Seed
        // AccountActivity before local read/dismiss writes so their zero is an
        // available authoritative value, rather than falling back to stale
        // user counts in plugin menu contexts.
        totals = (totals ?? const NotificationTotals())
            .withGroupedUnreadNotifications(storedGroupedCounts!);
      }
      if (totals != null) {
        accountActivity.restoreTotals(instance.url, totals);
      }
      doNotDisturb.restoreSnapshot(
        instance.url,
        instance.user?.doNotDisturbUntil,
      );
    }
    await aggregate.loadPreferences(stored);
    if (isDisposed) return;
    _durableInstanceOrder = [for (final instance in stored) instance.url];
    _instanceIndex = 0;
    _forumWorkspaces.clear();
    var workspacesNormalized = false;
    for (final workspace in await storedWorkspaces) {
      final normalized = _normalizeWorkspace(workspace);
      workspacesNormalized =
          workspacesNormalized || !identical(normalized, workspace);
      final instance = _instanceAt(workspace.siteUrl);
      if (instance != null &&
          workspace.accountIdentity == _workspaceAccountIdentity(instance)) {
        _forumWorkspaces[workspace.siteUrl] = normalized;
      }
    }
    if (workspacesNormalized) _persistWorkspaces();
    final initialInstance = currentInstance;
    // A persisted palette is already good enough for the first frame. Its
    // expensive stylesheet refresh follows the selected account's small JSON
    // reads instead of competing with the feed during the cold-start burst.
    _restoreInstanceWorkspace(
      refreshAppearance: initialInstance?.appearance == null,
    );
    final aggregateBehindSettings =
        _rootMode == ShellRootMode.settings &&
        _settingsReturnTarget?.rootMode == ShellRootMode.aggregate;
    if ((_rootMode == ShellRootMode.aggregate || aggregateBehindSettings) &&
        _instances.isNotEmpty) {
      unawaited(aggregate.open(_instances));
    }
    _loadStatus = InstanceLoadStatus.ready;
    _notify();

    unawaited(updates.load());

    // Refresh only the selected account; persisted metadata can draw inactive
    // sites until their first selection.
    unawaited(_refreshAccountState(initialInstance));
  }

  bool contains(String url) => _instances.any((i) => i.url == url);

  Future<bool> addInstance(DiscourseInstance instance) async {
    await load();
    if (isDisposed || !loaded) return false;
    if (contains(instance.url)) return true;

    final previousSiteUrl = currentInstance?.url;
    final previousPane = _mobilePane;
    final previousRootMode = _rootMode;

    _instances.add(instance);
    _rootMode = ShellRootMode.forum;
    _instanceIndex = _instances.length - 1;
    _resetToInstanceDefault();
    _mobilePane = MobilePane.sidebar;
    _notify();

    try {
      await instanceStore.save(List.of(_instances));
      _settingsReturnTarget = null;
      unawaited(aggregate.pruneForums(_instances));
      return true;
    } catch (_) {
      if (isDisposed) return false;

      // A failed first save must not leave an in-memory-only site that the add
      // sheet can neither persist nor retry because it now looks duplicated.
      // Only undo the exact object added here; if it was replaced meanwhile,
      // a newer operation owns its state and gets one repair save instead.
      final held = _instanceAt(instance.url);
      if (!identical(held, instance)) {
        try {
          await instanceStore.save(List.of(_instances));
          unawaited(aggregate.pruneForums(_instances));
          return true;
        } catch (_) {
          return false;
        }
      }

      final selectedSiteUrl = currentInstance?.url;
      _forgetSiteState(instance.url);
      _instances.remove(instance);
      _rootMode = previousRootMode;

      if (selectedSiteUrl == instance.url) {
        final previousIndex = previousSiteUrl == null
            ? -1
            : _instances.indexWhere((item) => item.url == previousSiteUrl);
        if (previousIndex >= 0) {
          _instanceIndex = previousIndex;
          _restoreInstanceWorkspace();
          _mobilePane = previousPane;
        } else {
          _instanceIndex = _instances.isEmpty ? 0 : _instances.length - 1;
          _restoreInstanceWorkspace();
        }
      } else {
        final selectedIndex = selectedSiteUrl == null
            ? -1
            : _instances.indexWhere((item) => item.url == selectedSiteUrl);
        _instanceIndex = selectedIndex >= 0 ? selectedIndex : 0;
      }
      _notify();

      // A newer save may have been queued while the failed write was active.
      // Make this rollback the newest snapshot before reporting the failure.
      try {
        await instanceStore.save(List.of(_instances));
      } catch (_) {}
      return false;
    }
  }

  Future<bool> moveInstance(DiscourseInstance instance, int newIndex) {
    if (isDisposed || !loaded || _instances.length < 2) {
      return Future.value(false);
    }

    final oldIndex = _instances.indexWhere((item) => item.url == instance.url);
    if (oldIndex < 0) return Future.value(false);
    final destination = newIndex.clamp(0, _instances.length - 1);
    if (oldIndex == destination) return Future.value(true);

    // When no reorder is outstanding, the live membership/order came from a
    // completed load, add or removal and is the rollback boundary for this
    // batch of drags.
    if (!_savingInstanceOrder && _pendingInstanceReorders.isEmpty) {
      _durableInstanceOrder = [for (final item in _instances) item.url];
    }
    final revision = ++_instanceReorderRevision;

    final selectedSiteUrl = currentInstance?.url;
    final moved = _instances.removeAt(oldIndex);
    _instances.insert(destination, moved);
    _followSelectedInstance(selectedSiteUrl);
    _notify();

    final result = Completer<bool>();
    _pendingInstanceReorders.add((revision: revision, result: result));
    if (!_savingInstanceOrder) {
      _savingInstanceOrder = true;
      unawaited(_drainInstanceOrderSaves());
    }
    return result.future;
  }

  Future<void> _drainInstanceOrderSaves() async {
    try {
      while (_pendingInstanceReorders.isNotEmpty) {
        final savedRevision = _instanceReorderRevision;
        final snapshot = List.of(_instances);
        final savedOrder = [for (final item in snapshot) item.url];

        try {
          await instanceStore.save(snapshot);
        } catch (_) {
          if (isDisposed) {
            _completeInstanceReordersThrough(savedRevision, false);
            continue;
          }

          // A drag landed behind the write that failed. Its newest snapshot
          // still contains the whole intended ordering, so let the next loop
          // persist it rather than allowing the older failure to roll it back.
          if (savedRevision != _instanceReorderRevision) continue;

          final restored = _restoreDurableInstanceOrder();
          _completeInstanceReordersThrough(savedRevision, false);

          // Put the rollback (or, if membership changed concurrently, the
          // untouched newest rail) behind the failed snapshot before accepting
          // another batch. New drags can still update the live list while this
          // repair is in flight; the next loop persists them afterward.
          final repairSnapshot = List.of(_instances);
          final repairOrder = [for (final item in repairSnapshot) item.url];
          var repairPersisted = false;
          try {
            await instanceStore.save(repairSnapshot);
            repairPersisted = true;
          } catch (_) {}
          if (restored && repairPersisted) {
            _durableInstanceOrder = repairOrder;
          }
          continue;
        }

        _durableInstanceOrder = savedOrder;
        _completeInstanceReordersThrough(savedRevision, true);
      }
    } finally {
      _savingInstanceOrder = false;
      if (_pendingInstanceReorders.isNotEmpty) {
        _savingInstanceOrder = true;
        unawaited(_drainInstanceOrderSaves());
      }
    }
  }

  void _completeInstanceReordersThrough(int revision, bool persisted) {
    final completed = _pendingInstanceReorders
        .where((request) => request.revision <= revision)
        .toList();
    _pendingInstanceReorders.removeWhere(
      (request) => request.revision <= revision,
    );
    for (final request in completed) {
      if (!request.result.isCompleted) request.result.complete(persisted);
    }
  }

  void _followSelectedInstance(String? selectedSiteUrl) {
    if (selectedSiteUrl == null) {
      _instanceIndex = _instances.isEmpty ? 0 : _instanceIndex;
      return;
    }
    final selectedIndex = _instances.indexWhere(
      (item) => item.url == selectedSiteUrl,
    );
    if (selectedIndex >= 0) _instanceIndex = selectedIndex;
  }

  bool _restoreDurableInstanceOrder() {
    if (_instances.length != _durableInstanceOrder.length) return false;
    final byUrl = {for (final instance in _instances) instance.url: instance};
    if (byUrl.length != _durableInstanceOrder.length ||
        _durableInstanceOrder.any((url) => !byUrl.containsKey(url))) {
      return false;
    }

    final selectedSiteUrl = currentInstance?.url;
    _instances
      ..clear()
      ..addAll(_durableInstanceOrder.map((url) => byUrl[url]!));
    _followSelectedInstance(selectedSiteUrl);
    _notify();
    return true;
  }

  Future<bool> removeInstance(DiscourseInstance instance) async {
    if (!_instances.contains(instance)) return false;

    final disconnected = await _accountSessions.disconnect(instance.url);
    final lease = disconnected.lease;
    if (disconnected.outcome != AccountDisconnectionOutcome.disconnected ||
        lease == null ||
        !lease.isCurrent) {
      return false;
    }

    // Presentation metadata may have replaced the immutable instance object
    // while revocation was in flight. URL is the rail identity; resolve the
    // object owned by the new lifecycle generation before mutating the list.
    final held = _instanceAt(instance.url);
    if (held == null) return false;
    final index = _instances.indexOf(held);
    if (index < 0) return false;
    final selected = currentInstance;
    final removingSelected = selected?.url == held.url;
    final signedOut = held.copyWith(
      clearUser: true,
      clearConfig: true,
      clearAppearance: true,
    );
    final previousSettingsReturnTarget = _settingsReturnTarget;
    _instances.removeAt(index);
    if (_instances.isEmpty) {
      if (_rootMode != ShellRootMode.settings) {
        _rootMode = ShellRootMode.forum;
      }
    }

    if (removingSelected) {
      _instanceIndex = _instances.isEmpty
          ? 0
          : index.clamp(0, _instances.length - 1);
      _restoreInstanceWorkspace();
    } else {
      _instanceIndex = _instances.indexOf(selected!);
    }
    _notify();

    try {
      await instanceStore.save(List.of(_instances));
      unawaited(aggregate.pruneForums(_instances));
      return true;
    } catch (_) {
      if (isDisposed || !lease.isCurrent || _instanceAt(instance.url) != null) {
        return false;
      }

      final restoredIndex = index.clamp(0, _instances.length);
      _instances.insert(restoredIndex, signedOut);
      _settingsReturnTarget = previousSettingsReturnTarget;
      if (removingSelected) {
        _instanceIndex = restoredIndex;
        _mobilePane = MobilePane.sidebar;
        _resetToInstanceDefault();
      } else {
        final selectedIndex = selected == null
            ? -1
            : _instances.indexWhere((item) => item.url == selected.url);
        _instanceIndex = selectedIndex >= 0 ? selectedIndex : 0;
      }
      _notify();

      // The failed write may have raced a newer queued snapshot. Make the
      // signed-out rollback the latest value before handing control back.
      try {
        await instanceStore.save(List.of(_instances));
      } catch (_) {}
      return false;
    }
  }

  NotificationTotals? totalsFor(DiscourseInstance instance) =>
      accountActivity.totalsFor(instance.url);

  @override
  NotificationTotals? get currentTotals {
    final instance = currentInstance;
    return instance == null ? null : accountActivity.totalsFor(instance.url);
  }

  @override
  Rect? get floatingComposerBounds {
    final composer = visibleComposer;
    return identical(composer, _floatingComposerBoundsOwner)
        ? _floatingComposerBounds
        : null;
  }

  int railBadgeFor(DiscourseInstance instance) =>
      accountActivity.totalsFor(instance.url)?.badge ?? 0;

  SidebarBadge sidebarBadgeFor(String destinationId) {
    if (destinationId == 'drafts') {
      return SidebarBadge.count(draftCountFor(currentInstance?.url));
    }
    final totals = currentTotals;
    if (destinationId == 'latest') {
      final count = currentInstance?.user?.unifiedNewEnabled == true
          ? newActivityCount
          : totals?.topicTrackingSidebarCount ?? 0;
      return SidebarBadge.count(count);
    }
    if (destinationId == 'messages') {
      return SidebarBadge.count(totals?.unreadPersonalMessages ?? 0);
    }

    final instance = currentInstance;
    final user = instance?.user;
    final tracking = instance == null
        ? null
        : _topicTrackingBySite[instance.url];
    if (instance == null || user == null || tracking == null) {
      return SidebarBadge.none;
    }
    final showCount = user.sidebarShowCountOfNewItems;
    final unifiedNew = user.unifiedNewEnabled;

    if (_destinationNumericId(destinationId, 'category-') case final id?) {
      return tracking.categoryBadge(
        categoryId: id,
        categories: _categoriesBySite[instance.url] ?? const [],
        unifiedNew: unifiedNew,
        showCount: showCount,
      );
    }
    if (_destinationNumericId(destinationId, 'tag-') case final id?) {
      final tags = <SidebarTag>[
        ...user.sidebarTags,
        ...?_siteTopTagsBySite[instance.url],
        ...?_anonymousDefaultTagsBySite[instance.url],
      ];
      if (tags.any((tag) => tag.id == id && tag.pmOnly)) {
        return SidebarBadge.none;
      }
      return tracking.tagBadge(
        tagId: id,
        unifiedNew: unifiedNew,
        showCount: showCount,
      );
    }
    return SidebarBadge.none;
  }

  int topicTrackingRevisionFor(String siteUrl) =>
      _topicTrackingRevisions[siteUrl] ?? 0;

  int draftCountFor(String? siteUrl) {
    if (siteUrl == null) return 0;
    final feed = draftList.feedFor(siteUrl);
    if (feed.totalCount case final count?) return count;
    return _instanceAt(siteUrl)?.user?.draftCount ?? 0;
  }

  void _recordDraftDestroyed(
    String siteUrl,
    String draftKey, {
    required bool knownToExist,
  }) {
    final wasListed = draftList
        .feedFor(siteUrl)
        .drafts
        .any((draft) => draft.key == draftKey);
    draftList.recordDeleted(siteUrl, draftKey);
    if (!knownToExist || wasListed) return;
    final instance = _instanceAt(siteUrl);
    if (instance?.isConnected == true) {
      // A cached count may predate a newly-created draft, so subtracting can
      // under-count. Refresh the authoritative account count instead.
      draftList.invalidateTotalCount(siteUrl);
      unawaited(_refreshSessionUserFor(instance!, force: true));
    }
  }

  Future<void> _refreshOne(DiscourseInstance instance) async {
    await accountActivity.refresh(instance);
  }

  Future<void> _refreshAccountState(DiscourseInstance? initialInstance) async {
    if (initialInstance case final instance? when instance.isConnected) {
      await Future.wait([
        _refreshOne(instance),
        _refreshSessionUserFor(instance),
      ]);
      if (isDisposed || !contains(instance.url)) return;
      await _presentation.ensureAppearance(instance.url);
    } else if (initialInstance case final instance?
        when !instance.loginRequired) {
      if (isDisposed || !contains(instance.url)) return;
      // Anonymous appearance is public and may have been populated by lookup
      // moments ago. Refresh it normally; the warm-start suppression is for a
      // persisted connected account whose many authenticated appearance reads
      // otherwise join the cold-start burst.
      await _presentation.refreshAppearance(instance.url);
    }
  }

  Future<void> _refreshSessionUserFor(
    DiscourseInstance instance, {
    bool force = false,
  }) async {
    final lease = lifecycle.capture(instance.url);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      if (credential.value case final apiKey?) {
        await _sessionUser(instance.url, apiKey, lease: lease, force: force);
        if (!lease.isCurrent || currentInstance?.url != instance.url) return;
        await _refreshCustomSidebarSections(instance.url, apiKey, lease: lease);
      }
    } catch (_) {
      // Freshness-sensitive plugin capabilities remain unknown. Persisted
      // extension state must not authorize them in their place.
    }
  }

  final Map<String, List<SidebarSection>> _customSidebarSections = {};
  final Set<String> _customSidebarSectionsLoaded = {};
  final Map<String, Future<void>> _customSidebarSectionRequests = {};
  final Map<String, DateTime> _customSidebarSectionAttemptedAt = {};

  static const _customSidebarRetryInterval = Duration(minutes: 5);

  List<SidebarSection> customSidebarSectionsFor(String siteUrl) =>
      _customSidebarSections[siteUrl] ?? const [];

  Future<void> _refreshCustomSidebarSections(
    String siteUrl,
    String apiKey, {
    SiteLease? lease,
  }) {
    // Custom sections belong only to the site on screen. A session lookup can
    // finish after the reader has switched away, and must not turn that stale
    // completion into another inactive-site request.
    if (isDisposed || currentInstance?.url != siteUrl) return Future.value();
    if (_customSidebarSectionsLoaded.contains(siteUrl)) return Future.value();

    final active = _customSidebarSectionRequests[siteUrl];
    if (active != null) return active;
    final attemptedAt = _customSidebarSectionAttemptedAt[siteUrl];
    if (attemptedAt != null &&
        DateTime.now().difference(attemptedAt) < _customSidebarRetryInterval) {
      return Future.value();
    }

    late final Future<void> request;
    request = _loadCustomSidebarSections(siteUrl, apiKey, lease: lease)
        .whenComplete(() {
          if (identical(_customSidebarSectionRequests[siteUrl], request)) {
            final removed = _customSidebarSectionRequests.remove(siteUrl);
            assert(identical(removed, request));
          }
        });
    _customSidebarSectionRequests[siteUrl] = request;
    return request;
  }

  Future<void> _loadCustomSidebarSections(
    String siteUrl,
    String apiKey, {
    SiteLease? lease,
  }) async {
    final session = lease ?? lifecycle.capture(siteUrl);
    try {
      final identity = await _readSessionValue(session, authenticator.clientId);
      if (identity == null ||
          !session.isCurrent ||
          currentInstance?.url != siteUrl) {
        return;
      }
      _customSidebarSectionAttemptedAt[siteUrl] = DateTime.now();
      final sections = await api.site.customSidebarSections(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: identity.value,
      );
      session.commit(() {
        _customSidebarSections[siteUrl] = sections;
        _customSidebarSectionsLoaded.add(siteUrl);
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !session.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'sidebar.loadCustomSections',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  void _onTotalsLoaded(DiscourseInstance instance, NotificationTotals totals) {
    _notifyPluginTotals(instance, totals);
  }

  void _onTotalsChanged(String siteUrl, NotificationTotals totals) {
    if (isDisposed) return;
    final instance = _instanceAt(siteUrl);
    if (instance == null || !instance.isConnected) return;
    if (instance.notificationTotals == totals) return;
    _replaceInstance(instance, instance.copyWith(notificationTotals: totals));
    instanceStore.save(List.of(_instances)).ignore();
  }

  void _advanceGroupedUnreadNotificationVersion(String siteUrl) {
    _groupedUnreadNotificationVersions.update(
      siteUrl,
      (version) => version + 1,
      ifAbsent: () => 1,
    );
  }

  void _onPreferencesSaved(
    String siteUrl,
    PreferenceSection section,
    UserPreferences preferences,
  ) {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user == null ||
        user.username.toLowerCase() != preferences.username.toLowerCase()) {
      return;
    }
    var updated = switch (section) {
      PreferenceSection.profile => user.withPreferences(
        timezone: preferences.timezone,
      ),
      PreferenceSection.interface => user.withPreferences(
        bookmarkAutoDeletePreference: preferences.bookmarkAutoDeletePreference,
      ),
      _ => user,
    };
    for (final mirror
        in _pluginSession.capabilities<PluginUserPreferenceMirror>()) {
      try {
        updated = mirror.mirrorUserPreference(updated, section, preferences);
      } catch (error, stackTrace) {
        _reportOperationalError(
          error,
          stackTrace,
          'preferences.pluginMirror',
          severity: DiagnosticSeverity.warning,
        );
      }
    }
    if (updated == user) return;
    _replaceInstance(instance, instance.copyWith(user: updated));
    _notify();
    unawaited(_persistPreferencesMirror(List.of(_instances)));
  }

  Future<void> _persistPreferencesMirror(
    List<DiscourseInstance> instances,
  ) async {
    try {
      await instanceStore.save(instances);
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'preferences.persistMirror',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  void _notifyPluginTotals(
    DiscourseInstance instance, [
    NotificationTotals? loadedTotals,
  ]) {
    final totals = loadedTotals ?? accountActivity.totalsFor(instance.url);
    if (totals == null) return;
    for (final observer
        in _pluginSession.capabilities<PluginTotalsObserver>()) {
      _observePluginLifecycle(
        Future.sync(
          () => observer.pluginTotalsLoaded(
            instance.url,
            totals,
            selected: currentInstance?.url == instance.url,
          ),
        ),
        'plugins.session.totalsLoaded',
      );
    }
  }

  NotificationFeed notificationsFor(String siteUrl) =>
      accountActivity.notificationsFor(siteUrl);

  Future<void> loadNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadNotifications(instance);
  }

  NotificationFeed replyNotificationsFor(String siteUrl) =>
      accountActivity.replyNotificationsFor(siteUrl);

  Future<void> loadReplyNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadReplyNotifications(instance);
    }
  }

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) =>
      accountActivity.pluginNotificationsListenable(id);

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) => accountActivity.pluginNotificationsFor(id, siteUrl);

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {
    final registered = plugins.registry.notificationFeed(source.id);
    if (registered != source) {
      throw StateError(
        'Notification feed ${source.id.id} is not installed in this build.',
      );
    }
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadPluginNotifications(instance, registered!);
    }
  }

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {
    final registered = plugins.registry.notificationFeed(source.id);
    if (registered != source) {
      throw StateError(
        'Notification feed ${source.id.id} is not installed in this build.',
      );
    }
    if (registered!.dismissal == null) {
      throw StateError(
        'Notification feed ${source.id.id} does not support dismissal.',
      );
    }
    final instance = _instanceAt(siteUrl);
    if (instance == null) {
      throw StateError('No forum is registered for $siteUrl.');
    }
    await accountActivity.dismissPluginNotifications(instance, registered);
  }

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => readNotification(siteUrl, notification);

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      absoluteUrl(path, siteUrl: siteUrl);

  @override
  Future<bool> openPluginNotificationUrl(String url) =>
      openNotificationUrl(url);

  void readNotification(String siteUrl, DiscourseNotification notification) {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      accountActivity.readNotification(instance, notification);
    }
  }

  BookmarkFeed bookmarksFor(String siteUrl) =>
      accountActivity.bookmarksFor(siteUrl);

  Future<void> loadBookmarks(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadBookmarks(instance);
  }

  Future<void> loadUserActivity(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadUserActivity(instance);
  }

  final Set<String> _categorised = {};
  final Map<String, List<TopicCategory>> _categoriesBySite = {};
  final Map<String, TopicTrackingState> _topicTrackingBySite = {};
  final Set<String> _topicTrackingSnapshotsLoaded = {};
  final Map<String, int> _topicTrackingRevisions = {};
  final Set<String> _topicTrackingLoads = {};
  final Map<String, List<Object?>> _topicTrackingPendingEvents = {};
  final Map<String, CategoryFeed> _categoryFeeds = {};
  final Set<(String, int)> _categoryIdsLoading = {};
  final Map<String, _CategorySidebarCache> _categorySidebarCache = {};
  final Map<String, List<SidebarTag>> _siteTopTagsBySite = {};
  final Map<String, List<SidebarTag>> _anonymousDefaultTagsBySite = {};
  final Map<String, _TagSidebarCache> _tagSidebarCache = {};
  final Map<String, TagDirectoryFeed> _tagDirectoryFeeds = {};
  final Map<String, Object> _tagDirectoryRequests = {};
  final Map<String, TopicComposerCapabilities> _topicComposerCapabilities = {};
  final Map<String, SitePostActionCatalog> _postActionCatalogs = {};

  List<PostFlagType> postFlagTypesFor(String siteUrl) =>
      _postActionCatalogs[siteUrl]?.postFlags ?? const [];

  List<PostFlagType> availablePostFlagTypes(String siteUrl, Post post) {
    if (post.hidden || post.isDeleted || post.actedFlagSummaries.isNotEmpty) {
      return const [];
    }
    final available = [
      for (final type in postFlagTypesFor(siteUrl))
        if (type.enabled && type.appliesToPost && post.canFlagWith(type.id))
          type,
    ];
    final notifyUser = available.indexWhere(
      (type) => type.nameKey == 'notify_user',
    );
    if (notifyUser > 0) {
      final type = available.removeAt(notifyUser);
      available.insert(0, type);
    }
    return List.unmodifiable(available);
  }

  List<PostFlagType> availableTopicFlagTypes(
    String siteUrl,
    TopicDetail topic,
  ) {
    final catalog =
        _postActionCatalogs[siteUrl]?.topicFlags ?? const <PostFlagType>[];
    return List.unmodifiable([
      for (final type in catalog)
        if (type.enabled && type.appliesToTopic && topic.canFlagWith(type.id))
          type,
    ]);
  }

  String? get currentFeedId {
    final route = currentContent;
    if (route?.isMessages == true) return route!.id;
    if (route != null && route.feedPath != null) return route.id;
    return destinationId;
  }

  TopicFeed? get currentFeed {
    final instance = currentInstance;
    final feedId = currentFeedId;
    if (instance == null || feedId == null) return null;
    return topicFeeds.feedFor(instance.url, feedId);
  }

  TopicListMode? get currentTopicListMode {
    final tab = activeTab;
    if (tab == null ||
        tab.rootDestinationId != 'latest' ||
        tab.contentStack.length != 1) {
      return null;
    }
    return TopicListMode.fromRoute(tab.currentContent);
  }

  ({int all, int topics, int replies}) get topicListNewCounts {
    final instance = currentInstance;
    final totals = currentTotals;
    if (instance?.user?.unifiedNewEnabled == true) {
      final tracking = _topicTrackingBySite[instance!.url];
      if (tracking == null ||
          !_topicTrackingSnapshotsLoaded.contains(instance.url)) {
        return (all: totals?.topicTrackingNew ?? 0, topics: 0, replies: 0);
      }
      final counts = tracking.newActivityCounts;
      final trackedTotal = counts.newTopics + counts.newReplies;
      return (
        all: trackedTotal,
        topics: counts.newTopics,
        replies: counts.newReplies,
      );
    }

    final topics = totals?.topicTrackingNew ?? 0;
    return (
      all: topics,
      topics: topics,
      replies: totals?.topicTrackingUnread ?? 0,
    );
  }

  int get newTopicCount => topicListNewCounts.topics;

  int get newReplyCount => topicListNewCounts.replies;

  int get newActivityCount => topicListNewCounts.all;

  TopicListMode get defaultTopTopicListMode {
    final siteUrl = currentInstance?.url;
    final period = siteUrl == null
        ? TopPeriod.yearly
        : TopPeriod.fromQueryValue(siteConfigFor(siteUrl).topPageDefaultPeriod);
    return TopicListMode.top(period);
  }

  bool get canCreateTopicHere {
    if (currentContent?.isTopic != false ||
        currentContent?.isPreferences == true ||
        currentContent?.isMessages == true) {
      return false;
    }
    final instance = currentInstance;
    if (currentContent?.id == 'all-categories' && instance != null) {
      return categoryFeedFor(instance.url).canCreateTopic;
    }
    return currentFeed?.canCreateTopic ?? false;
  }

  bool get canCreateTopicFromSidebar =>
      currentInstance?.user?.canCreateTopic == true;

  CategoryFeed categoryFeedFor(String siteUrl) =>
      _categoryFeeds[siteUrl] ?? const CategoryFeed();

  List<TopicCategory> topicComposerCategories(String siteUrl) =>
      _categoriesBySite[siteUrl] ?? const [];

  SidebarSection? categorySidebarSectionFor(String siteUrl) {
    if (!_categoriesBySite.containsKey(siteUrl)) return null;
    final categories = _categoriesBySite[siteUrl]!;
    final user = _instanceAt(siteUrl)?.user;
    final config = siteConfigFor(siteUrl);
    final held = _categorySidebarCache[siteUrl];
    if (held != null &&
        identical(held.categories, categories) &&
        identical(held.user, user) &&
        held.config == config) {
      return held.section;
    }

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: user != null,
      preferredCategoryIds: user?.sidebarCategoryIds ?? const [],
      defaultCategoryIds: config.defaultNavigationMenuCategoryIds,
      fixedCategoryPositions: config.fixedCategoryPositions,
      allowUncategorizedTopics: config.allowUncategorizedTopics,
    );
    _categorySidebarCache[siteUrl] = (
      categories: categories,
      user: user,
      config: config,
      section: section,
    );
    return section;
  }

  SidebarSection? tagSidebarSectionFor(String siteUrl) {
    final instance = _instanceAt(siteUrl);
    if (instance == null || !siteConfigFor(siteUrl).taggingEnabled) return null;

    final user = instance.user;
    final siteTop = _siteTopTagsBySite[siteUrl] ?? const <SidebarTag>[];
    final anonymousDefaults =
        _anonymousDefaultTagsBySite[siteUrl] ?? const <SidebarTag>[];
    final tags = user == null
        ? (anonymousDefaults.isNotEmpty ? anonymousDefaults : siteTop)
        : (user.sidebarTags.isNotEmpty ? user.sidebarTags : siteTop);
    final display = user == null ? tags.isNotEmpty : user.displaySidebarTags;

    final held = _tagSidebarCache[siteUrl];
    if (held != null &&
        identical(held.tags, tags) &&
        held.display == display &&
        held.username == user?.username) {
      return held.section;
    }

    final section = buildTagSidebarSection(
      tags: tags,
      display: display,
      username: user?.username,
    );
    if (section == null) {
      _tagSidebarCache.remove(siteUrl);
      return null;
    }
    _tagSidebarCache[siteUrl] = (
      tags: tags,
      display: display,
      username: user?.username,
      section: section,
    );
    return section;
  }

  TagDirectoryFeed tagDirectoryFeedFor(String siteUrl) =>
      _tagDirectoryFeeds[siteUrl] ?? const TagDirectoryFeed();

  TopicComposerCapabilities topicComposerCapabilities(String siteUrl) =>
      _topicComposerCapabilities[siteUrl] ?? const TopicComposerCapabilities();

  Future<TopicComposerCapabilities> prepareTopicTagEditor(
    String siteUrl,
  ) async {
    await _ensureTopicComposerCapabilities(siteUrl);
    return topicComposerCapabilities(siteUrl);
  }

  TopicCategory? categoryFor(int? categoryId, {String? siteUrl}) {
    final sourceSite = siteUrl ?? currentInstance?.url;
    if (sourceSite == null || categoryId == null) return null;
    return store.read<TopicCategory>(sourceSite, categoryId);
  }

  String topicCategoryPathLabel(TopicCategory category, {String? siteUrl}) {
    final parent = categoryFor(category.parentCategoryId, siteUrl: siteUrl);
    return category_path.topicCategoryPathLabel(category, parent: parent);
  }

  Ref<Topic> topicRef(String siteUrl, int topicId) =>
      store.ref<Topic>(siteUrl, topicId);

  Ref<TopicCategory> categoryRef(String siteUrl, int categoryId) =>
      store.ref<TopicCategory>(siteUrl, categoryId);

  Ref<Post> postRef(String siteUrl, int postId) =>
      store.ref<Post>(siteUrl, postId);

  String? _feedPath(String feedId, DiscourseInstance instance) {
    for (final route in contentStack.reversed) {
      if (route.id != feedId) continue;
      if (route.feedPath != null) return route.feedPath;
      if (route.messageGroupName case final groupName?) {
        final username = instance.user?.username;
        if (username == null) return null;
        return '/topics/private-messages-group/'
            '${Uri.encodeComponent(username)}/'
            '${Uri.encodeComponent(groupName)}.json';
      }
    }

    final username = instance.user?.username;
    return switch (feedId) {
      'latest' => '/latest.json',
      'filter' => Uri(
        path: '/filter.json',
        queryParameters: switch (topicFeeds.filterQueryFor(instance.url)) {
          final query when query.isNotEmpty => {'q': query},
          _ => null,
        },
      ).toString(),
      'messages' when username != null =>
        '/topics/private-messages/${Uri.encodeComponent(username)}.json',
      _ => null,
    };
  }

  void selectMessageInbox(String? groupName) {
    final instance = currentInstance;
    final route = currentContent;
    final user = instance?.user;
    if (instance == null || user == null || route?.isMessages != true) return;

    final group = groupName?.trim();
    if (group != null && !user.messageGroupNames.contains(group)) return;

    final replacement = ContentRoute.messages(groupName: group);
    if (route!.id == replacement.id) return;
    replaceCurrentContent(replacement);
    unawaited(loadFeed(replacement.id));
  }

  Future<void> loadFeed(String destinationId, {bool force = false}) async {
    final instance = currentInstance;
    if (instance == null) return;

    // Lookup has already established that an anonymous request cannot read
    // this forum. The shell shows its sign-in action until connecting gives
    // this request a user API key.
    if (instance.loginRequired && !instance.isConnected) return;

    final path = _feedPath(destinationId, instance);
    if (path == null) return;
    await topicFeeds.load(
      instance: instance,
      destinationId: destinationId,
      path: path,
      incoming: _trackers[instance.url]?.incoming,
      force: force,
    );
  }

  String filterQueryFor(String siteUrl) => topicFeeds.filterQueryFor(siteUrl);

  Future<void> submitTopicFilter(String query) async {
    final instance = currentInstance;
    if (instance == null || destinationId != 'filter') return;
    topicFeeds.setFilterQuery(instance.url, query);
    await loadFeed('filter', force: true);
  }

  List<TopicCategory> filterCategoriesFor(String siteUrl) =>
      _categoriesBySite[siteUrl] ?? const [];

  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.tags',
    (apiKey, clientId) => api.lookups.searchFilterTags(
      siteUrl: siteUrl,
      term: term,
      apiKey: apiKey,
      clientId: clientId,
    ),
  );

  Future<List<TopicFilterLookupValue>> searchFilterTagGroups({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.tagGroups',
    (apiKey, clientId) => api.lookups.searchFilterTagGroups(
      siteUrl: siteUrl,
      term: term,
      apiKey: apiKey,
      clientId: clientId,
    ),
  );

  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.groups',
    (apiKey, clientId) => apiKey == null
        ? Future.value(const [])
        : api.lookups.searchFilterGroups(
            siteUrl: siteUrl,
            term: term,
            apiKey: apiKey,
            clientId: clientId,
          ),
  );

  Future<List<TopicFilterLookupValue>> searchFilterUsers({
    required String siteUrl,
    required String term,
  }) => _filterLookup(
    siteUrl,
    'topics.filter.users',
    (apiKey, clientId) async => [
      for (final user in await api.lookups.searchUsers(
        siteUrl: siteUrl,
        term: term,
        apiKey: apiKey,
        clientId: clientId,
      ))
        TopicFilterLookupValue(name: user.username, description: user.name),
    ],
  );

  Future<List<T>> _filterLookup<T>(
    String siteUrl,
    String operation,
    Future<List<T>> Function(String? apiKey, String clientId) lookup,
  ) async {
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null) return const [];
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !lease.isCurrent) return const [];
      final found = await lookup(credential.value, identity.value);
      return !isDisposed && lease.isCurrent ? found : const [];
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          operation,
          degraded: false,
          severity: DiagnosticSeverity.warning,
        );
      }
      return const [];
    }
  }

  int feedScrollRow(String destinationId) {
    final instance = currentInstance;
    if (instance == null) return 0;
    final anchor = activeTab?.anchors[destinationId];
    if (anchor?.kind == 'feed') return anchor!.itemId;
    return 0;
  }

  void saveFeedScrollRow(String destinationId, int row) {
    final instance = currentInstance;
    final tab = activeTab;
    if (instance == null || tab == null) return;
    topicFeeds.saveScrollRow(instance.url, destinationId, row);
    final previous = tab.anchors[destinationId];
    if (previous?.kind == 'feed' && previous?.itemId == row) return;
    _replaceActiveTab(
      tab.copyWith(
        anchors: {
          ...tab.anchors,
          destinationId: ForumTabAnchor(kind: 'feed', itemId: row),
        },
      ),
      persist: false,
    );
    _schedulePersistAnchors();
  }

  int? topicScrollPostNumber(int topicId) {
    final tab = activeTab;
    final route = currentContent;
    if (tab == null || route?.topicId != topicId) return null;
    final anchor = tab.anchors[route!.id];
    if (anchor?.kind == 'topic') return anchor!.itemId;
    return route.postNumber;
  }

  double topicScrollPostOffset(int topicId) {
    final tab = activeTab;
    final route = currentContent;
    if (tab == null || route?.topicId != topicId) return 0;
    final anchor = tab.anchors[route!.id];
    return anchor?.kind == 'topic' ? anchor!.offset : 0;
  }

  void saveTopicScrollPost(
    int topicId,
    int postNumber, {
    double viewportOffset = 0,
  }) {
    final tab = activeTab;
    final route = currentContent;
    if (tab == null || route?.topicId != topicId) return;
    final previous = tab.anchors[route!.id];
    if (previous?.kind == 'topic' &&
        previous?.itemId == postNumber &&
        previous?.offset == viewportOffset) {
      return;
    }
    _replaceActiveTab(
      tab.copyWith(
        anchors: {
          ...tab.anchors,
          route.id: ForumTabAnchor(
            kind: 'topic',
            itemId: postNumber,
            offset: viewportOffset,
          ),
        },
      ),
      persist: false,
    );
    _schedulePersistAnchors();
  }

  final Map<String, SiteTracker> _trackers = {};
  final Set<String> _trackersStarting = {};
  final Map<String, Map<int, UserStatus?>> _userStatusOverrides = {};
  final Set<String> _userStatusWrites = {};
  final Map<String, bool> _optimisticHidePresence = {};
  final Map<String, Object> _hidePresenceWrites = {};
  final Map<String, String> _hidePresenceErrors = {};
  final Map<String, int> _hidePresenceVersions = {};
  final Map<String, int> _groupedUnreadNotificationVersions = {};
  final Map<String, int> _draftCountVersions = {};
  final Map<String, Timer> _pluginNotificationFeedRefreshTimers = {};

  final Set<String> _sessionUsersRefreshed = {};

  final Map<String, Future<DiscourseUser?>> _sessionUserRequests = {};

  bool _foreground = true;

  int incomingCount(String destinationId) {
    final instance = currentInstance;
    if (instance == null) return 0;
    return _trackers[instance.url]?.incoming.count(destinationId) ?? 0;
  }

  Future<void> showIncoming(String destinationId) async {
    final instance = currentInstance;
    if (instance == null) return;

    final tracker = _trackers[instance.url];
    final path = _feedPath(destinationId, instance);
    if (tracker == null || path == null) return;
    await topicFeeds.showIncoming(
      instance: instance,
      destinationId: destinationId,
      path: path,
      incoming: tracker.incoming,
    );
  }

  void _syncTracking() {
    final instance = currentInstance;
    final retainedSiteUrls = _pluginBackgroundSiteUrls;

    for (final entry in _trackers.entries) {
      if (entry.key != instance?.url) entry.value.unwatchTopic();
      final selectedAndVisible = _foreground && entry.key == instance?.url;
      final connectedAndVisible =
          _foreground && (_instanceAt(entry.key)?.isConnected ?? false);
      if (selectedAndVisible ||
          connectedAndVisible ||
          retainedSiteUrls.contains(entry.key)) {
        entry.value.start();
      } else {
        entry.value.stop();
      }
    }

    for (final candidate in _instances) {
      final selected = candidate.url == instance?.url;
      final retained = retainedSiteUrls.contains(candidate.url);
      if (!_foreground && !retained) continue;
      if (!selected && !candidate.isConnected && !retained) continue;

      // Core never starts MessageBus for an anonymous reader on a private site.
      // Such a poll can only be refused, and retrying that refusal adds traffic
      // without a channel the reader is allowed to consume.
      if (candidate.loginRequired && !candidate.isConnected) continue;

      final tracker = _trackers[candidate.url];
      if (tracker == null) {
        unawaited(_startTracking(candidate));
      } else {
        tracker.start();
      }
    }

    if (_foreground && instance != null) {
      final selected = instance;
      final tracker = _trackers[selected.url];
      if (tracker != null) _syncTopicWatch(selected.url, tracker);
    }
  }

  void _syncTopicChannels() {
    final instance = currentInstance;
    if (instance == null) return;
    final tracker = _trackers[instance.url];
    if (tracker == null) return;
    _syncTopicWatch(instance.url, tracker);
  }

  void _syncTopicWatch(String siteUrl, SiteTracker tracker) {
    final topicId = currentContent?.topicId;
    if (topicId == null) {
      tracker.unwatchTopic();
      return;
    }

    // Core publishes every post-stream mutation here. In particular, changing
    // a topic status creates a small-action post and publishes `type: created`;
    // that is how the web client makes "closed this topic" appear without a
    // manual reload. Plugin channels are additional topic-scoped hints.
    final coreChannel = '/topic/$topicId';
    final channels = [coreChannel, ...plugins.registry.topicChannels(topicId)];

    tracker.watchTopic(topicId, channels, (channel, data) {
      if (channel == coreChannel && _coreTopicMessageRefreshesStream(data)) {
        final route = currentContent;
        if (route?.topicId == topicId) {
          unawaited(_refetchTopic(siteUrl, topicId, route?.slug ?? ''));
        }
      }
      if (plugins.registry.staleTopic(topicId, channel, data)) {
        final route = currentContent;
        if (route?.topicId == topicId) {
          unawaited(_refetchTopic(siteUrl, topicId, route?.slug ?? ''));
        }
      }
      final stale = plugins.registry.stalePosts(channel, data);
      if (stale.isNotEmpty) {
        unawaited(_refreshPosts(siteUrl, topicId, stale));
      }
    });
  }

  static bool _coreTopicMessageRefreshesStream(Object? data) {
    if (data is! Map) return false;
    return data['type'] == 'created' || data['reload_topic'] == true;
  }

  Future<void> _refreshPosts(
    String siteUrl,
    int topicId,
    Set<int> postIds,
  ) async {
    final eligible = <int>[];
    for (final id in postIds) {
      final key = _postKey(siteUrl, id);
      if (store.read<Post>(siteUrl, id) == null) continue;
      if (_postWritesInFlight.contains(key)) {
        // A poll/reaction echo received during a write is useful, but not yet:
        // the pre-write personalized post could land over the write response.
        // Remember it and re-read as soon as the post lease is released.
        _postRefreshPending.add(key);
        _postRefreshTopics[key] = topicId;
      } else {
        eligible.add(id);
      }
    }
    final wanted = <int>[];
    for (final id in eligible.take(TopicDetail.maximumInitialPosts)) {
      final key = _postKey(siteUrl, id);
      if (_postRefreshRequests.containsKey(key)) {
        _postRefreshPending.add(key);
      } else {
        wanted.add(id);
      }
    }
    if (wanted.isEmpty) return;
    final lease = lifecycle.capture(siteUrl);
    final request = Object();
    for (final id in wanted) {
      final key = _postKey(siteUrl, id);
      _postRefreshRequests[key] = request;
      // Keep the topic beside every active read as well as beside reads that
      // arrive during a write. If a write starts now, it invalidates this
      // pre-write response and needs enough context to replay it afterward.
      _postRefreshTopics[key] = topicId;
    }

    bool requestOwns(int postId) =>
        identical(_postRefreshRequests[_postKey(siteUrl, postId)], request);

    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return;
      final posts = await api.topicContent.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: wanted,
        apiKey: credential.value,
      );
      lease.commit(() {
        final current = [
          for (final post in posts)
            if (requestOwns(post.id) &&
                !_postRefreshPending.contains(_postKey(siteUrl, post.id)))
              post,
        ];
        if (current.isEmpty) return;
        store.putAll(siteUrl, current);
        _notify();
      });
    } catch (error, stackTrace) {
      final stillRelevant = wanted.any((id) {
        final key = _postKey(siteUrl, id);
        return requestOwns(id) && !_postRefreshPending.contains(key);
      });
      if (!isDisposed && lease.isCurrent && stillRelevant) {
        _reportOperationalError(
          error,
          stackTrace,
          'post.refreshFromMessageBus',
          severity: DiagnosticSeverity.warning,
        );
      }
    } finally {
      final retry = <int>{};
      lease.commit(() {
        for (final id in wanted) {
          final key = _postKey(siteUrl, id);
          if (identical(_postRefreshRequests[key], request)) {
            _postRefreshRequests.remove(key);
            if (_postRefreshPending.remove(key)) {
              retry.add(id);
            } else {
              _postRefreshTopics.remove(key);
            }
          }
        }
      });
      if (retry.isNotEmpty) {
        unawaited(_refreshPosts(siteUrl, topicId, retry));
      }
    }
  }

  void _acceptLiveNotificationState(
    String siteUrl,
    Object? data,
    SiteLease lease,
  ) {
    // This is called only from the tracker's lifecycle-bound commit closure.
    // Advancing here, rather than in the raw MessageBus callback, prevents a
    // retired account generation from invalidating current feeds or counts.
    final groupedCounts = data is Map
        ? NotificationTypeCounts.fromWire(data['grouped_unread_notifications'])
        : NotificationTypeCounts.unavailable;
    if (groupedCounts.isAvailable) {
      _advanceGroupedUnreadNotificationVersion(siteUrl);
    }
    accountActivity.applyLiveNotificationState(siteUrl, data);
    if (!accountActivity.hasTrackedPluginNotifications(siteUrl)) return;

    _pluginNotificationFeedRefreshTimers.remove(siteUrl)?.cancel();
    late final Timer timer;
    timer = Timer(pluginNotificationFeedRefreshDebounce, () {
      if (!identical(_pluginNotificationFeedRefreshTimers[siteUrl], timer)) {
        return;
      }
      _pluginNotificationFeedRefreshTimers.remove(siteUrl);
      if (isDisposed || !lease.isCurrent) return;
      final instance = _instanceAt(siteUrl);
      if (instance?.isConnected != true) return;
      accountActivity.refreshLoadedPluginNotifications(instance!).ignore();
    });
    _pluginNotificationFeedRefreshTimers[siteUrl] = timer;
  }

  Future<void> _startTracking(DiscourseInstance instance) async {
    final siteUrl = instance.url;
    if (instance.loginRequired && !instance.isConnected) return;
    if (_trackers.containsKey(siteUrl) || !_trackersStarting.add(siteUrl)) {
      return;
    }
    final lease = lifecycle.capture(siteUrl);

    final String? apiKey;
    final String clientId;
    try {
      // The persisted account state, not a credential that may have failed
      // to delete, decides whether this session may open private channels.
      apiKey = instance.isConnected
          ? await authenticator.apiKeyFor(siteUrl)
          : null;
      clientId = await authenticator.clientId();
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(error, stackTrace, 'messageBus.readCredentials');
      lease.commit(() => _trackersStarting.remove(siteUrl));
      return;
    }

    final userId = apiKey == null
        ? null
        : await _accountId(siteUrl, apiKey: apiKey, lease: lease);

    lease.commit(() {
      _trackersStarting.remove(siteUrl);
      final current = _instanceAt(siteUrl);
      if (isDisposed || current == null) return;

      // Validate visibility before constructing SiteTracker, whose constructor
      // immediately opens MessageBus. Plugin leases explicitly retain it.
      final selectedAndVisible = _foreground && currentInstance?.url == siteUrl;
      final connectedAndVisible =
          _foreground && (_instanceAt(siteUrl)?.isConnected ?? false);
      if (!selectedAndVisible &&
          !connectedAndVisible &&
          !_backgroundRetention.retains(siteUrl)) {
        return;
      }

      void commit(SiteMutation mutation) {
        if (!isDisposed) lease.commit(mutation);
      }

      final trackingUsername = apiKey == null ? null : current.user?.username;
      final shouldLoadTopicTracking =
          trackingUsername != null &&
          !_topicTrackingBySite.containsKey(siteUrl) &&
          _topicTrackingLoads.add(siteUrl);
      if (shouldLoadTopicTracking) {
        _topicTrackingPendingEvents[siteUrl] = <Object?>[];
      }

      final SiteTracker tracker;
      try {
        tracker = trackers(
          siteUrl: siteUrl,
          userId: userId,
          apiKey: apiKey,
          clientId: clientId,
          shouldLongPoll: () =>
              _foreground || _backgroundRetention.retains(siteUrl),
          onIncomingTopics: () => commit(() {
            if (currentInstance?.url == siteUrl) _notify();
          }),
          onNotifications: (data) =>
              commit(() => _acceptLiveNotificationState(siteUrl, data, lease)),
          onReviewableCounts: (data) => commit(
            () => _applyCounts(
              siteUrl,
              (held) => held.withReviewableCounts(data),
            ),
          ),
        );
      } catch (error, stackTrace) {
        if (shouldLoadTopicTracking) {
          _topicTrackingLoads.remove(siteUrl);
          _topicTrackingPendingEvents.remove(siteUrl);
        }
        _reportOperationalError(error, stackTrace, 'messageBus.start');
        return;
      }
      _trackers[siteUrl] = tracker;
      if (apiKey != null) {
        if (userId != null) {
          try {
            tracker.watchTopicTrackingState(
              userId,
              (data) => commit(() => _applyTopicTrackingMessage(siteUrl, data)),
            );
          } catch (error, stackTrace) {
            _reportOperationalError(
              error,
              stackTrace,
              'messageBus.subscribeTopicTracking',
              severity: DiagnosticSeverity.warning,
            );
          }
        }
        if (shouldLoadTopicTracking) {
          unawaited(
            _loadTopicTrackingState(
              siteUrl: siteUrl,
              username: trackingUsername,
              apiKey: apiKey,
              clientId: clientId,
              lease: lease,
            ),
          );
        }
        try {
          tracker.watchPluginChannel(
            '/user-status',
            (data) => commit(() => _applyUserStatusMessage(siteUrl, data)),
            lastId: _instanceAt(siteUrl)?.user?.status?.messageBusLastId,
          );
        } catch (error, stackTrace) {
          _reportOperationalError(
            error,
            stackTrace,
            'messageBus.subscribeUserStatus',
            severity: DiagnosticSeverity.warning,
          );
        }
        if (userId != null) {
          try {
            tracker.watchPluginChannel(
              '/user-drafts/$userId',
              (data) => commit(() => _applyUserDraftsMessage(siteUrl, data)),
            );
          } catch (error, stackTrace) {
            _reportOperationalError(
              error,
              stackTrace,
              'messageBus.subscribeUserDrafts',
              severity: DiagnosticSeverity.warning,
            );
          }
          try {
            final user = _instanceAt(siteUrl)?.user;
            tracker.watchPluginChannel(
              '/do-not-disturb/$userId',
              (data) => commit(() => doNotDisturb.applyMessage(siteUrl, data)),
              lastId: user?.doNotDisturbChannelPosition,
            );
          } catch (error, stackTrace) {
            _reportOperationalError(
              error,
              stackTrace,
              'messageBus.subscribeDoNotDisturb',
              severity: DiagnosticSeverity.warning,
            );
          }
        }
      }
      for (final owned
          in _pluginSession.ownedCapabilities<PluginTrackerAttachment>()) {
        try {
          owned.capability.attachPluginTracker(
            siteUrl,
            tracker.pluginLiveChannels(
              plugins.liveChannelScopesFor(owned.owner),
            ),
          );
        } catch (error, stackTrace) {
          _reportOperationalError(
            error,
            stackTrace,
            'plugins.attachTracker.${owned.owner.value}',
            severity: DiagnosticSeverity.warning,
          );
        }
      }
      final stillSelectedAndVisible =
          _foreground && currentInstance?.url == siteUrl;
      final stillConnectedAndVisible =
          _foreground && (_instanceAt(siteUrl)?.isConnected ?? false);
      if (!stillSelectedAndVisible &&
          !stillConnectedAndVisible &&
          !_backgroundRetention.retains(siteUrl)) {
        tracker.stop();
      } else if (stillSelectedAndVisible) {
        _syncTopicWatch(siteUrl, tracker);
      }
    });
  }

  Future<void> _loadTopicTrackingState({
    required String siteUrl,
    required String username,
    required String apiKey,
    required String clientId,
    required SiteLease lease,
  }) async {
    try {
      final snapshot = await api.site.topicTrackingState(
        siteUrl: siteUrl,
        apiKey: apiKey,
        username: username,
        clientId: clientId,
      );
      if (!lease.isCurrent || isDisposed) return;
      final currentUsername = _instanceAt(siteUrl)?.user?.username;
      if (currentUsername?.toLowerCase() != username.toLowerCase()) return;

      // The bus is attached before the HTTP request starts. Replaying anything
      // received while it was in flight closes the snapshot/message race; the
      // operations are idempotent when the response already included one.
      for (final event
          in _topicTrackingPendingEvents[siteUrl] ?? const <Object?>[]) {
        snapshot.applyMessage(event);
      }
      lease.commit(() {
        _topicTrackingBySite[siteUrl] = snapshot;
        _topicTrackingSnapshotsLoaded.add(siteUrl);
        _topicTrackingRevisions.update(
          siteUrl,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        if (currentInstance?.url == siteUrl) _notify();
      });
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'topicTracking.load',
          severity: DiagnosticSeverity.warning,
        );
      }
    } finally {
      lease.commit(() {
        _topicTrackingLoads.remove(siteUrl);
        _topicTrackingPendingEvents.remove(siteUrl);
      });
    }
  }

  void _applyTopicTrackingMessage(String siteUrl, Object? data) {
    _topicTrackingPendingEvents[siteUrl]?.add(data);
    final tracking = _topicTrackingBySite.putIfAbsent(
      siteUrl,
      TopicTrackingState.new,
    );
    if (tracking.applyMessage(data) && currentInstance?.url == siteUrl) {
      _topicTrackingRevisions.update(
        siteUrl,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      _notify();
    }
  }

  Future<int?> _accountId(
    String siteUrl, {
    required String apiKey,
    required SiteLease lease,
  }) async {
    if (!lease.isCurrent) return null;
    final held = _instanceAt(siteUrl);
    if (held == null) return null;
    final storedId = held.user?.id;
    if (storedId != null) return storedId;

    final user = await _sessionUser(siteUrl, apiKey, lease: lease);
    if (!lease.isCurrent) return null;
    // A stored id is stable enough to keep this account's private counters
    // connected after a failed refresh, but its capabilities remain unknown.
    return user?.id ?? _instanceAt(siteUrl)?.user?.id;
  }

  Future<DiscourseUser?> _sessionUser(
    String siteUrl,
    String apiKey, {
    SiteLease? lease,
    bool force = false,
  }) {
    final held = _instanceAt(siteUrl);
    if (held == null) return Future.value();
    if (!force && _sessionUsersRefreshed.contains(siteUrl)) {
      return Future.value(held.user);
    }

    final active = _sessionUserRequests[siteUrl];
    final session = lease ?? lifecycle.capture(siteUrl);
    if (active != null) {
      if (!force) return active;
      return () async {
        await active;
        if (!session.isCurrent) return null;
        return _sessionUser(siteUrl, apiKey, lease: session, force: true);
      }();
    }

    final hidePresenceVersion = _hidePresenceVersions[siteUrl] ?? 0;
    final groupedUnreadNotificationVersion =
        _groupedUnreadNotificationVersions[siteUrl] ?? 0;
    final draftCountVersion = _draftCountVersions[siteUrl] ?? 0;
    late final Future<DiscourseUser?> request;
    request =
        _readSessionUser(
          siteUrl,
          apiKey,
          session,
          hidePresenceVersion,
          groupedUnreadNotificationVersion,
          draftCountVersion,
        ).whenComplete(() {
          if (identical(_sessionUserRequests[siteUrl], request)) {
            final removed = _sessionUserRequests.remove(siteUrl);
            assert(identical(removed, request));
          }
        });
    _sessionUserRequests[siteUrl] = request;
    return request;
  }

  Future<DiscourseUser?> _readSessionUser(
    String siteUrl,
    String apiKey,
    SiteLease lease,
    int hidePresenceVersion,
    int groupedUnreadNotificationVersion,
    int draftCountVersion,
  ) async {
    if (!lease.isCurrent || _connectingSiteUrl == siteUrl) return null;

    final DiscourseUser responseUser;
    try {
      responseUser = await api.site.currentUser(
        siteUrl: siteUrl,
        apiKey: apiKey,
      );
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return null;
      _reportOperationalError(
        error,
        stackTrace,
        'messageBus.resolveAccount',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        if (_instanceAt(siteUrl)?.user?.hidePresence == null &&
            !_hidePresenceWrites.containsKey(siteUrl)) {
          _hidePresenceErrors[siteUrl] =
              "Couldn't load the presence setting. Try again.";
          _notify();
        }
      });
      return null;
    }
    if (isDisposed || !lease.isCurrent) return null;
    final user = _acceptDoNotDisturbSnapshot(siteUrl, responseUser);

    var changed = false;
    DiscourseUser? committedUser;
    final accepted = lease.commit(() {
      final fresh = _instanceAt(siteUrl);
      if (fresh == null) return;
      final previousUser = fresh.user;
      final accountChanged =
          previousUser != null &&
          !plugins.models.sameCurrentUserAccount(previousUser, user);
      final withPreservedPlugins = plugins.models.preserveUnknownCurrentUser(
        previousUser,
        user,
      );
      final preserveConfirmedPresence =
          !accountChanged &&
          (_hidePresenceWrites.containsKey(siteUrl) ||
              (_hidePresenceVersions[siteUrl] ?? 0) != hidePresenceVersion);
      final groupedCountsAreCurrent =
          (_groupedUnreadNotificationVersions[siteUrl] ?? 0) ==
          groupedUnreadNotificationVersion;
      final draftCountIsCurrent =
          (_draftCountVersions[siteUrl] ?? 0) == draftCountVersion;
      var reconciledUser = preserveConfirmedPresence
          ? withPreservedPlugins.withHidePresence(previousUser?.hidePresence)
          : withPreservedPlugins;
      if (!accountChanged && !groupedCountsAreCurrent && previousUser != null) {
        // The response predates a live snapshot or a local read/dismiss write.
        // Keep accepting its unrelated current-user fields, but do not expose
        // its stale grouped map through the menu's user fallback.
        reconciledUser = reconciledUser.withGroupedUnreadNotifications(
          previousUser.groupedUnreadNotifications,
        );
      }
      if (!accountChanged && !draftCountIsCurrent && previousUser != null) {
        reconciledUser = reconciledUser.withDraftCount(previousUser.draftCount);
      }
      committedUser = reconciledUser;
      _sessionUsersRefreshed.add(siteUrl);
      _hidePresenceErrors.remove(siteUrl);
      if (previousUser != committedUser || accountChanged) {
        changed = true;
        if (accountChanged) {
          accountActivity.forget(siteUrl);
          groups.forget(siteUrl);
          _topicTrackingBySite.remove(siteUrl);
          _topicTrackingSnapshotsLoaded.remove(siteUrl);
          _topicTrackingRevisions.remove(siteUrl);
          _topicTrackingLoads.remove(siteUrl);
          _topicTrackingPendingEvents.remove(siteUrl);
        }
        _replaceInstance(
          fresh,
          fresh.copyWith(
            user: committedUser,
            clearNotificationTotals: accountChanged,
          ),
        );
      }
      if (accountChanged || groupedCountsAreCurrent) {
        _seedGroupedUnreadNotifications(siteUrl, committedUser!);
      }
      _notify();
    });
    if (accepted && changed && lease.isCurrent) {
      instanceStore.save(List.of(_instances)).ignore();
    }
    if (accepted && lease.isCurrent) {
      for (final observer
          in _pluginSession.capabilities<PluginCurrentUserObserver>()) {
        _observePluginLifecycle(
          Future.sync(() => observer.pluginCurrentUserRefreshed(siteUrl)),
          'plugins.session.currentUserRefreshed',
        );
      }
    }
    return accepted ? committedUser : null;
  }

  void _applyCounts(
    String siteUrl,
    NotificationTotals Function(NotificationTotals held) fold,
  ) => accountActivity.applyCounts(siteUrl, fold);

  void _applyUserDraftsMessage(String siteUrl, Object? data) {
    if (data is! Map<Object?, Object?>) return;
    final count = jsonIntOrNull(data['draft_count']);
    if (count == null || count < 0) return;

    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null || user == null) return;

    _draftCountVersions.update(
      siteUrl,
      (version) => version + 1,
      ifAbsent: () => 1,
    );

    var current = instance;
    if (user.draftCount != count) {
      current = instance.copyWith(user: user.withDraftCount(count));
      _replaceInstance(instance, current);
      _notify();
      instanceStore.save(List.of(_instances)).ignore();
    }

    final feed = draftList.feedFor(siteUrl);
    if (!feed.loaded && !feed.loading) return;
    draftList.invalidateTotalCount(siteUrl);
    unawaited(draftList.load(current, refresh: true));
  }

  void _seedGroupedUnreadNotifications(String siteUrl, DiscourseUser user) {
    final counts = user.groupedUnreadNotifications;
    if (!counts.isAvailable) return;
    accountActivity.applyGroupedUnreadSnapshot(siteUrl, counts);
  }

  UserStatus? userStatusFor(String siteUrl, int? userId, UserStatus? snapshot) {
    final overrides = _userStatusOverrides[siteUrl];
    final status = userId != null && (overrides?.containsKey(userId) ?? false)
        ? overrides![userId]
        : snapshot;
    return status?.isActiveAt(DateTime.now()) == true ? status : null;
  }

  void _applyUserStatusMessage(String siteUrl, Object? data) {
    if (data is! Map<Object?, Object?>) return;
    var changed = false;
    var ownStatusChanged = false;
    for (final entry in data.entries) {
      final userId = switch (entry.key) {
        final int value => value,
        final String value => int.tryParse(value),
        _ => null,
      };
      if (userId == null || userId <= 0) continue;

      final UserStatus? status;
      if (entry.value == null) {
        status = null;
      } else if (entry.value case final Map<Object?, Object?> value) {
        status = UserStatus.fromJson(Map<String, dynamic>.from(value));
        if (status == null) continue;
      } else {
        continue;
      }
      _userStatusOverrides.putIfAbsent(siteUrl, () => {})[userId] = status;
      ownStatusChanged =
          _applyOwnUserStatus(siteUrl, userId, status) || ownStatusChanged;
      changed = true;
    }
    if (changed) {
      _notify();
      if (ownStatusChanged) {
        instanceStore.save(List.of(_instances)).ignore();
      }
    }
  }

  bool _applyOwnUserStatus(String siteUrl, int userId, UserStatus? status) {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user == null ||
        user.id != userId ||
        user.status == status) {
      return false;
    }
    _replaceInstance(
      instance,
      instance.copyWith(user: user.withStatus(status)),
    );
    return true;
  }

  DiscourseUser _acceptDoNotDisturbSnapshot(
    String siteUrl,
    DiscourseUser user,
  ) {
    final until = doNotDisturb.acceptSnapshot(siteUrl, user.doNotDisturbUntil);
    return until == user.doNotDisturbUntil
        ? user
        : user.withDoNotDisturbUntil(until);
  }

  void _commitDoNotDisturb(String siteUrl, DateTime? until) {
    if (isDisposed) return;
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null || user == null || user.doNotDisturbUntil == until) {
      return;
    }
    _replaceInstance(
      instance,
      instance.copyWith(user: user.withDoNotDisturbUntil(until)),
    );
    _notify();
    instanceStore.save(List.of(_instances)).ignore();
  }

  bool? hidePresenceFor(String siteUrl) =>
      _optimisticHidePresence.containsKey(siteUrl)
      ? _optimisticHidePresence[siteUrl]
      : _instanceAt(siteUrl)?.user?.hidePresence;

  bool hidePresenceWriteInFlight(String siteUrl) =>
      _hidePresenceWrites.containsKey(siteUrl);

  String? hidePresenceErrorFor(String siteUrl) => _hidePresenceErrors[siteUrl];

  Future<void> retryHidePresence(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance?.user == null || hidePresenceFor(siteUrl) != null) return;
    final lease = lifecycle.capture(siteUrl);
    _hidePresenceErrors.remove(siteUrl);
    _notify();

    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null) return;
      final apiKey = credential.value;
      if (apiKey == null) {
        lease.commit(() {
          _hidePresenceErrors[siteUrl] =
              'Reconnect this account to load its presence setting.';
          _notify();
        });
        return;
      }
      await _sessionUser(siteUrl, apiKey, lease: lease);
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'presence.read',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        _hidePresenceErrors[siteUrl] =
            "Couldn't load the presence setting. Try again.";
        _notify();
      });
    }
  }

  Future<void> toggleHidePresence(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    final held = hidePresenceFor(siteUrl);
    if (instance == null || user == null || held == null) return;
    if (_hidePresenceWrites.containsKey(siteUrl)) return;

    final desired = !held;
    final request = Object();
    final lease = lifecycle.capture(siteUrl);
    _hidePresenceWrites[siteUrl] = request;
    _optimisticHidePresence[siteUrl] = desired;
    _hidePresenceErrors.remove(siteUrl);
    _bumpHidePresenceVersion(siteUrl);
    _notify();

    bool isCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_hidePresenceWrites[siteUrl], request);

    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!isCurrent()) return;
      if (credential.failure case final failure?) {
        _finishHidePresenceWrite(
          siteUrl,
          request,
          lease,
          error: _hidePresenceError(failure),
        );
        return;
      }
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !isCurrent()) return;
      await api.site.updateHidePresence(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        username: user.username,
        hidePresence: desired,
        clientId: identity.value,
      );
      if (!isCurrent()) return;
      _finishHidePresenceWrite(siteUrl, request, lease, confirmed: desired);
    } on WriteException catch (error) {
      _finishHidePresenceWrite(
        siteUrl,
        request,
        lease,
        error: _hidePresenceError(error),
      );
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _reportOperationalError(error, stackTrace, 'presence.update');
      }
      _finishHidePresenceWrite(
        siteUrl,
        request,
        lease,
        error: "Couldn't update presence. Check the connection and try again.",
      );
    }
  }

  void _finishHidePresenceWrite(
    String siteUrl,
    Object request,
    SiteLease lease, {
    bool? confirmed,
    String? error,
  }) {
    if (isDisposed ||
        !lease.isCurrent ||
        !identical(_hidePresenceWrites[siteUrl], request)) {
      return;
    }
    lease.commit(() {
      _hidePresenceWrites.remove(siteUrl);
      _optimisticHidePresence.remove(siteUrl);
      _bumpHidePresenceVersion(siteUrl);

      if (error != null) {
        _hidePresenceErrors[siteUrl] = error;
      } else {
        _hidePresenceErrors.remove(siteUrl);
        final instance = _instanceAt(siteUrl);
        final user = instance?.user;
        if (instance != null && user != null && confirmed != null) {
          _replaceInstance(
            instance,
            instance.copyWith(user: user.withHidePresence(confirmed)),
          );
          instanceStore.save(List.of(_instances)).ignore();
        }
      }
      _notify();
    });
  }

  void _bumpHidePresenceVersion(String siteUrl) {
    _hidePresenceVersions[siteUrl] = (_hidePresenceVersions[siteUrl] ?? 0) + 1;
  }

  String _hidePresenceError(WriteException error) {
    if (error.errors.isNotEmpty) return error.errors.join('\n');
    return switch (error.failure) {
      WriteFailure.validation =>
        "The site didn't accept that presence setting.",
      WriteFailure.rateLimited => switch (error.retryAfter) {
        final wait? =>
          'Too fast — try changing presence again in ${wait.inSeconds}s.',
        null => 'Too fast — try changing presence again in a moment.',
      },
      WriteFailure.forbidden =>
        'Presence could not be changed. Reconnect this account and try again.',
      WriteFailure.conflict =>
        'Presence changed somewhere else. Try again to use this setting.',
      WriteFailure.unreachable =>
        "Couldn't update presence. Check the connection and try again.",
    };
  }

  bool userStatusWriteInFlight(String siteUrl) =>
      _userStatusWrites.contains(siteUrl);

  Future<String?> setUserStatus(
    String siteUrl, {
    required String description,
    required String emoji,
    DateTime? endsAt,
    bool? pauseNotifications,
  }) async {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user?.id == null ||
        !instance.config.userStatusEnabled) {
      return 'Custom status is not available for this account.';
    }
    if (!_userStatusWrites.add(siteUrl)) {
      return 'Another status change is still finishing.';
    }
    final lease = lifecycle.capture(siteUrl);
    _notify();
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      await api.site.setUserStatus(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        description: description,
        emoji: emoji,
        endsAt: endsAt,
        clientId: clientId,
      );
      if (!lease.isCurrent || isDisposed) return null;
      final status = UserStatus(
        description: description.trim(),
        emoji: emoji
            .trim()
            .replaceFirst(RegExp(r'^:'), '')
            .replaceFirst(RegExp(r':$'), ''),
        endsAt: endsAt?.toUtc(),
      );
      lease.commit(() {
        _userStatusOverrides.putIfAbsent(siteUrl, () => {})[user!.id!] = status;
        _applyOwnUserStatus(siteUrl, user.id!, status);
        _notify();
        instanceStore.save(List.of(_instances)).ignore();
      });
      if (!lease.isCurrent || isDisposed) return null;
      if (pauseNotifications case final pause?) {
        final error = pause
            ? await doNotDisturb.pause(
                siteUrl,
                endsAt == null
                    ? doNotDisturbDurationUntil(eternalDoNotDisturbUntil)
                    : doNotDisturbDurationUntil(endsAt),
              )
            : await doNotDisturb.resume(siteUrl);
        if (!lease.isCurrent || isDisposed) return null;
        if (error != null) return error;
      }
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'userStatus.set');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _userStatusWrites.remove(siteUrl);
      if (!isDisposed) _notify();
    }
  }

  Future<String?> clearUserStatus(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user?.id == null ||
        !instance.config.userStatusEnabled) {
      return 'Custom status is not available for this account.';
    }
    if (!_userStatusWrites.add(siteUrl)) {
      return 'Another status change is still finishing.';
    }
    final lease = lifecycle.capture(siteUrl);
    _notify();
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      await api.site.clearUserStatus(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        clientId: clientId,
      );
      if (!lease.isCurrent || isDisposed) return null;
      lease.commit(() {
        _userStatusOverrides.putIfAbsent(siteUrl, () => {})[user!.id!] = null;
        _applyOwnUserStatus(siteUrl, user.id!, null);
        _notify();
        instanceStore.save(List.of(_instances)).ignore();
      });
      if (!lease.isCurrent || isDisposed) return null;
      final doNotDisturbError = await doNotDisturb.resume(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (doNotDisturbError != null) return doNotDisturbError;
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'userStatus.clear');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _userStatusWrites.remove(siteUrl);
      if (!isDisposed) _notify();
    }
  }

  void _disposeTracking(String siteUrl) {
    final tracker = _trackers.remove(siteUrl);
    tracker?.dispose().ignore();
  }

  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    // The OS may suspend or kill a backgrounded process before any timer
    // fires again, so an anchor waiting out its window must be durable now.
    if (!foreground) _flushPendingAnchorPersist();
    _observePluginLifecycle(
      _pluginSession.setForeground(foreground),
      'plugins.session.setForeground',
    );
    _syncTracking();
    if (!foreground) return;
    doNotDisturb.checkExpirations();

    final instance = currentInstance;
    final retainedSiteUrls = _pluginBackgroundSiteUrls;
    for (final entry in _trackers.entries) {
      final selected = entry.key == instance?.url;
      final connected = _instanceAt(entry.key)?.isConnected ?? false;
      if (selected || connected || retainedSiteUrls.contains(entry.key)) {
        entry.value.pollNow();
      }
    }
  }

  final Set<String> _topicsLoading = {};
  final Set<String> _topicRefreshPending = {};
  final Map<String, int> _topicRefreshPostNumbers = {};
  // A failed forced reconciliation must not turn the held topic into a
  // permanent cache hit. The next ordinary open retries it automatically.
  final Set<String> _topicsStale = {};
  final Set<String> _postsLoading = {};
  final Set<String> _earlierPostsLoading = {};
  final Map<String, List<int>> _topicSummaryStreams = {};
  final Set<String> _topicSummariesLoading = {};
  final Set<(String, int, int, bool)> _postGapsLoading = {};
  final Map<String, int> _topicNotificationRevisions = {};
  final Map<String, Future<void>> _topicNotificationTails = {};
  final Map<String, TopicNotificationLevel> _topicNotificationConfirmed = {};
  final Set<String> _topicPinWrites = {};
  final Set<String> _topicStatusWrites = {};
  final Set<String> _topicDeletionWrites = {};
  final Map<String, Object> _topicJumpRuns = {};
  int _topicNavigationRevision = 0;

  static String _topicKey(String siteUrl, int topicId) => '$siteUrl#$topicId';

  TopicDetail? get currentTopic {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;
    return store.read<TopicDetail>(instance.url, topicId);
  }

  bool get currentTopicSummary {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _topicSummaryStreams.containsKey(_topicKey(instance.url, topicId));
  }

  bool get currentTopicSummaryLoading {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _topicSummariesLoading.contains(_topicKey(instance.url, topicId));
  }

  List<int> _topicStream(String siteUrl, TopicDetail detail) =>
      _topicSummaryStreams[_topicKey(siteUrl, detail.id)] ?? detail.stream;

  List<int> get currentTopicStreamIds {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return const [];
    return _topicStream(instance.url, detail);
  }

  List<int> get currentPostIds {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return const [];
    final stream = _topicStream(instance.url, detail);
    final key = (
      instance.url,
      detail,
      stream,
      currentContent?.postNumber,
      store.generationOf<Post>(instance.url),
    );
    final cachedKey = _postIdsCacheKey;
    if (cachedKey != null &&
        cachedKey.$1 == key.$1 &&
        identical(cachedKey.$2, key.$2) &&
        identical(cachedKey.$3, key.$3) &&
        cachedKey.$4 == key.$4 &&
        cachedKey.$5 == key.$5) {
      return _postIdsCache;
    }
    final range = _loadedPostRange(instance.url, detail, stream: stream);
    _postIdsCacheKey = key;
    return _postIdsCache = range == null
        ? const []
        : [for (final id in stream.sublist(range.$1, range.$2 + 1)) id];
  }

  List<int> _postIdsCache = const [];
  (String, TopicDetail, List<int>, int?, int)? _postIdsCacheKey;

  (int, int)? _loadedPostRange(
    String siteUrl,
    TopicDetail detail, {
    List<int>? stream,
  }) {
    final effectiveStream = stream ?? _topicStream(siteUrl, detail);
    if (effectiveStream.isEmpty) return null;

    final target = currentContent?.postNumber;
    var anchor = -1;
    if (target != null) {
      for (var i = 0; i < effectiveStream.length; i++) {
        final post = store.read<Post>(siteUrl, effectiveStream[i]);
        if (post != null && post.postNumber >= target) {
          anchor = i;
          break;
        }
      }
    } else {
      anchor = effectiveStream.indexWhere(
        (id) => store.read<Post>(siteUrl, id) != null,
      );
    }
    // A stale cache or a deliberately minimal test payload may not contain
    // the requested post yet. Keep showing the contiguous data in hand until
    // the around-post request lands instead of flashing an empty topic.
    if (anchor < 0 && target != null) {
      anchor = effectiveStream.indexWhere(
        (id) => store.read<Post>(siteUrl, id) != null,
      );
    }
    if (anchor < 0) return null;

    var first = anchor;
    while (first > 0 &&
        store.read<Post>(siteUrl, effectiveStream[first - 1]) != null) {
      first--;
    }
    var last = anchor;
    while (last + 1 < effectiveStream.length &&
        store.read<Post>(siteUrl, effectiveStream[last + 1]) != null) {
      last++;
    }
    return (first, last);
  }

  List<int> _pendingPostIds(String siteUrl, TopicDetail detail) {
    final stream = _topicStream(siteUrl, detail);
    final range = _loadedPostRange(siteUrl, detail, stream: stream);
    final start = range == null ? 0 : range.$2 + 1;
    return [
      for (final id in stream.skip(start))
        if (store.read<Post>(siteUrl, id) == null) id,
    ];
  }

  List<int> _pendingEarlierPostIds(
    String siteUrl,
    TopicDetail detail,
    int batchSize,
  ) {
    final stream = _topicStream(siteUrl, detail);
    final range = _loadedPostRange(siteUrl, detail, stream: stream);
    if (range == null || range.$1 == 0) return const [];
    final start = range.$1 > batchSize ? range.$1 - batchSize : 0;
    return [
      for (final id in stream.sublist(start, range.$1))
        if (store.read<Post>(siteUrl, id) == null) id,
    ];
  }

  bool get currentTopicHasMore {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return false;
    return _pendingPostIds(instance.url, detail).isNotEmpty;
  }

  bool get currentTopicHasEarlier {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return false;
    return _pendingEarlierPostIds(instance.url, detail, 1).isNotEmpty;
  }

  bool get currentTopicLoading {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _topicsLoading.contains(_topicKey(instance.url, topicId));
  }

  void openTopic(Topic topic) => _openTopic(
    topic.id,
    topic.slug,
    topic.title,
    postNumber: topic.lastUnreadPostNumber,
  );

  void openSummaryTopic(UserSummaryTopic topic, {int? postNumber}) =>
      _openTopic(
        topic.id,
        topic.slug,
        topic.title,
        postNumber: postNumber != null && postNumber > 0 ? postNumber : null,
      );

  void openFeaturedTopic(CategoryFeaturedTopic topic) => _openTopic(
    topic.id,
    topic.slug,
    topic.title,
    postNumber: topic.firstUnreadPostNumber,
  );

  void openCategory(TopicCategory category, {String? siteUrl}) {
    final targetSiteUrl = siteUrl ?? currentInstance?.url;
    if (targetSiteUrl == null) return;
    final index = _instances.indexWhere(
      (instance) => instance.url == targetSiteUrl,
    );
    if (index < 0) return;
    if (index != _instanceIndex || _rootMode != ShellRootMode.forum) {
      selectInstance(index);
    }
    if (currentInstance?.url != targetSiteUrl) return;

    final categories = _categoriesBySite[targetSiteUrl] ?? const [];
    final byId = <int, TopicCategory>{
      for (final item in categories) item.id: item,
      category.id: category,
    };
    final route = ContentRoute.fromDestination(
      buildCategoryDestination(category, categoriesById: byId),
    );
    if (currentContent?.id == route.id) {
      showPluginContent();
      return;
    }
    pushContent(route);
    unawaited(loadFeed(route.id));
  }

  void openTag(SidebarTag tag) {
    final instance = currentInstance;
    if (instance == null) return;
    final destination = buildTagDestination(
      tag,
      username: instance.user?.username,
    );
    if (destination == null) return;
    final route = ContentRoute.fromDestination(destination);
    if (currentContent?.id == route.id) return;
    pushContent(route);
    unawaited(loadFeed(route.id));
  }

  Future<bool> openTopicTag(
    TopicTag tag, {
    required String siteUrl,
    bool privateMessage = false,
  }) async {
    var resolvedTag = _topicTagWithKnownIdentity(siteUrl, tag);
    final isPrivateMessage =
        privateMessage ||
        resolvedTag.pmOnly ||
        _isKnownPrivateMessageOnlyTag(siteUrl, resolvedTag);
    if (!isPrivateMessage &&
        resolvedTag.id == null &&
        int.tryParse(resolvedTag.name.trim()) != null) {
      final source = (
        rootMode: _rootMode,
        instanceUrl: currentInstance?.url,
        tabId: activeTabId,
        contentId: currentContent?.id,
        stackDepth: contentStack.length,
        mobilePane: _mobilePane,
        aggregateTabId: activeAggregateTabId,
      );
      final lease = lifecycle.capture(siteUrl);
      final found = await searchHashtags(
        siteUrl: siteUrl,
        term: resolvedTag.name,
      );
      if (!lease.isCurrent ||
          isDisposed ||
          _rootMode != source.rootMode ||
          currentInstance?.url != source.instanceUrl ||
          activeTabId != source.tabId ||
          currentContent?.id != source.contentId ||
          contentStack.length != source.stackDepth ||
          _mobilePane != source.mobilePane ||
          activeAggregateTabId != source.aggregateTabId) {
        return false;
      }
      final normalizedName = resolvedTag.name.trim().toLowerCase();
      final match = found.where((candidate) {
        if (candidate.type != 'tag' || candidate.id <= 0) return false;
        return candidate.slug.trim().toLowerCase() == normalizedName ||
            candidate.text.trim().toLowerCase() == normalizedName;
      }).firstOrNull;
      if (match == null) return false;
      resolvedTag = _topicTagWithIdentity(
        resolvedTag,
        id: match.id,
        slug: match.slug,
      );
    }

    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return false;

    final instance = _instances[index];
    final destination = buildTopicTagDestination(
      resolvedTag,
      username: instance.user?.username,
      privateMessage: isPrivateMessage,
    );
    if (destination == null) return false;

    if (index != _instanceIndex || _rootMode != ShellRootMode.forum) {
      selectInstance(index);
    }
    if (currentInstance?.url != siteUrl) return false;

    final route = ContentRoute.fromDestination(destination);
    if (currentContent?.id == route.id) {
      showPluginContent();
      return true;
    }
    pushContent(route);
    unawaited(loadFeed(route.id));
    return true;
  }

  TopicTag _topicTagWithKnownIdentity(String siteUrl, TopicTag topicTag) {
    if (topicTag.id case final id? when id > 0) return topicTag;
    final known = _knownTopicTag(siteUrl, topicTag);
    if (known == null) return topicTag;
    return _topicTagWithIdentity(
      topicTag,
      id: known.id,
      slug: known.slug,
      pmOnly: topicTag.pmOnly || known.pmOnly,
    );
  }

  TopicTag _topicTagWithIdentity(
    TopicTag tag, {
    required int id,
    required String slug,
    bool? pmOnly,
  }) => TopicTag(
    id: id,
    name: tag.name,
    slug: slug,
    pmOnly: pmOnly ?? tag.pmOnly,
    count: tag.count,
    disabled: tag.disabled,
    disabledReason: tag.disabledReason,
  );

  SidebarTag? _knownTopicTag(String siteUrl, TopicTag topicTag) {
    final topicTagId = topicTag.id;
    final topicTagName = topicTag.name.trim().toLowerCase();
    for (final tag in _knownTagsFor(siteUrl)) {
      if ((topicTagId != null && topicTagId > 0 && tag.id == topicTagId) ||
          tag.name.trim().toLowerCase() == topicTagName) {
        return tag;
      }
    }
    return null;
  }

  Iterable<SidebarTag> _knownTagsFor(String siteUrl) sync* {
    yield* _instanceAt(siteUrl)?.user?.sidebarTags ?? const [];
    yield* _siteTopTagsBySite[siteUrl] ?? const [];
    yield* _anonymousDefaultTagsBySite[siteUrl] ?? const [];
    yield* tagDirectoryFeedFor(siteUrl).tags;
  }

  bool _isKnownPrivateMessageOnlyTag(String siteUrl, TopicTag topicTag) {
    return _knownTopicTag(siteUrl, topicTag)?.pmOnly == true;
  }

  void openSearchResult(SearchPostHit hit) {
    search.clear();
    if (currentContent?.topicId == hit.topicId) {
      openCurrentTopicPost(hit.postNumber, loadAroundPost: true);
      return;
    }
    _openTopic(
      hit.topicId,
      hit.topicSlug,
      hit.topicTitle,
      postNumber: hit.postNumber,
    );
  }

  void openUserActivityItem(UserActivityItem item) => _openTopic(
    item.topicId,
    item.slug,
    item.title,
    postNumber: item.postNumber,
  );

  void _openTopic(
    int topicId,
    String slug,
    String title, {
    int? postNumber,
    bool force = false,
  }) {
    // A fast double tap on a row pushes the same topic twice — the fetch is
    // deduped below, but the second route still costs a back tap.
    if (currentContent?.topicId == topicId) return;
    if (currentInstance case final instance?) {
      _topicSummaryStreams.remove(_topicKey(instance.url, topicId));
    }
    pushContent(
      ContentRoute.topic(
        topicId: topicId,
        slug: slug,
        title: title,
        postNumber: postNumber,
      ),
    );
    unawaited(loadTopic(topicId, slug, force: force, postNumber: postNumber));
  }

  String absoluteUrl(String url, {String? siteUrl}) =>
      resolveSiteUrl(url, siteUrl ?? currentInstance?.url);

  bool openTopicUrl(String url) => _openTopicUrl(url);

  bool openGroupUrl(String url) {
    final absolute = absoluteUrl(url);
    final route = GroupRoute.parse(absolute);
    if (route == null) return false;
    final target = Uri.tryParse(absolute);
    if (target == null) return false;
    final index = _instances.indexWhere((instance) => instance.serves(target));
    if (index < 0) return false;
    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();
    if (currentContent?.groupRoute == route) {
      if (rootChanged) _notify();
      return true;
    }

    final instance = _instances[index];
    final content = ContentRoute.group(
      route,
      feedPath: route.topicFeedPath(instance.user?.username),
    );
    pushContent(content);
    if (content.feedPath != null) unawaited(loadFeed(content.id));
    return true;
  }

  bool _openTopicUrl(String url, {bool refresh = false}) {
    final link = TopicLink.parse(absoluteUrl(url));
    if (link == null) return false;

    final index = _instances.indexWhere((i) => i.serves(link.uri));
    if (index < 0) return false;

    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();

    // Posts link to the topic they are already in — every cross-post quote
    // does — and stacking a second copy of it only costs the user a back tap.
    // A notification is different: it reports a change that happened after
    // the post may have entered the store, so its target has to be read again.
    if (currentContent?.topicId == link.topicId) {
      if (refresh) {
        openCurrentTopicPost(link.postNumber ?? 1, loadAroundPost: true);
      } else if (rootChanged) {
        _notify();
      }
      return true;
    }

    _openTopic(
      link.topicId,
      link.slug,
      link.placeholderTitle,
      postNumber: link.postNumber,
      force: refresh,
    );
    return true;
  }

  void openCurrentTopicPost(int postNumber, {bool loadAroundPost = false}) {
    final route = currentContent;
    final tab = activeTab;
    if (route?.topicId case final topicId? when tab != null && postNumber > 0) {
      final anchors = Map<String, ForumTabAnchor>.of(tab.anchors)
        ..remove(route!.id);
      final targeted = ContentRoute.topic(
        topicId: topicId,
        slug: route.slug ?? '',
        title: route.title,
        subtitle: route.subtitle,
        color: route.color,
        postNumber: postNumber,
      );
      _topicNavigationRevision++;
      _replaceActiveTab(
        tab.copyWith(
          contentStack: [
            ...tab.contentStack.take(tab.contentStack.length - 1),
            targeted,
          ],
          anchors: anchors,
        ),
      );
      _notify();
      unawaited(
        loadTopic(
          topicId,
          route.slug ?? '',
          force: loadAroundPost,
          postNumber: postNumber,
        ),
      );
    }
  }

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
  }) {
    if (postNumber <= 0) return;
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);
    _setForumContentRoot();
    if (currentContent?.topicId == topicId) {
      openCurrentTopicPost(postNumber, loadAroundPost: true);
      return;
    }
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    final row = store.read<Topic>(siteUrl, topicId);
    _openTopic(
      topicId,
      row?.slug ?? '',
      detail?.title ?? row?.title ?? 'Topic',
      postNumber: postNumber,
    );
  }

  int get topicNavigationRevision => _topicNavigationRevision;

  Future<bool> jumpToCurrentTopicIndex(int index) async {
    final instance = currentInstance;
    final route = currentContent;
    final topic = currentTopic;
    final tabId = activeTabId;
    if (instance == null ||
        route?.topicId == null ||
        topic == null ||
        tabId == null ||
        currentTopicStreamIds.isEmpty) {
      return false;
    }

    final stream = currentTopicStreamIds;
    final boundedIndex = index.clamp(1, stream.length);
    final targetId = stream[boundedIndex - 1];
    final key = _topicKey(instance.url, topic.id);
    final token = Object();
    final lease = lifecycle.capture(instance.url);
    _topicJumpRuns[key] = token;

    bool isCurrent() =>
        identical(_topicJumpRuns[key], token) &&
        lease.isCurrent &&
        !isDisposed &&
        activeTabId == tabId &&
        currentInstance?.url == instance.url &&
        currentContent?.topicId == topic.id;

    try {
      var target = store.read<Post>(instance.url, targetId);
      final loadAroundPost = target == null;
      if (target == null) {
        final credential = await _readSessionValue(
          lease,
          () => authenticator.apiKeyFor(instance.url),
        );
        if (credential == null || !isCurrent()) return false;
        final bookmarkVersion = _bookmarkVersion(instance.url, topic.id);
        final fetched = await api.topicContent.posts(
          siteUrl: instance.url,
          topicId: topic.id,
          ids: [targetId],
          apiKey: credential.value,
        );
        if (!isCurrent()) return false;
        target = fetched.where((post) => post.id == targetId).firstOrNull;
        if (target == null) return false;
        lease.commit(
          () => _putTopicPosts(instance.url, topic.id, [
            target!,
          ], bookmarkVersionAtDispatch: bookmarkVersion),
        );
      }
      if (!isCurrent()) return false;
      openCurrentTopicPost(target.postNumber, loadAroundPost: loadAroundPost);
      return true;
    } catch (error, stackTrace) {
      if (isCurrent()) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.jumpToIndex',
          severity: DiagnosticSeverity.warning,
        );
      }
      return false;
    } finally {
      if (identical(_topicJumpRuns[key], token)) {
        final _ = _topicJumpRuns.remove(key);
      }
    }
  }

  bool openListUrl(String url, {String? title}) {
    final link = ListLink.parse(absoluteUrl(url));
    if (link == null) return false;

    final index = _instances.indexWhere((i) => i.serves(link.uri));
    if (index < 0) return false;

    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();

    final category = link.kind == ListKind.category
        ? categoryFor(link.id)
        : null;

    final route = ContentRoute.list(
      link,
      title: title,
      color: category == null ? null : Color(category.colorValue),
    );

    if (currentContent?.id == route.id) {
      if (rootChanged) _notify();
      return true;
    }

    pushContent(route);
    // In the same turn as the push, so the main region never draws a route
    // whose feed does not exist yet — that is the placeholder screen, and it
    // would flash in before the list arrived.
    unawaited(loadFeed(route.id));
    return true;
  }

  Future<void> loadTopic(
    int topicId,
    String slug, {
    bool force = false,
    int? postNumber,
  }) => DiagnosticsSink.runOperation(
    'topic.load',
    () => _loadTopic(topicId, slug, force: force, postNumber: postNumber),
  );

  Future<void> _loadTopic(
    int topicId,
    String slug, {
    required bool force,
    int? postNumber,
  }) async {
    final instance = currentInstance;
    if (instance == null) return;
    if (instance.loginRequired && !instance.isConnected) return;

    // Start presentation fetches before cache/in-flight guards so failures stay
    // retryable even for topics already in the store.
    unawaited(_presentation.ensureConfig(instance.url));
    unawaited(_presentation.ensureCustomEmojis(instance.url));
    // Hashtags need category colors even when a notification or link opened
    // the topic without first loading a feed.
    unawaited(_ensureCategoriesFor(instance));

    final key = _topicKey(instance.url, topicId);
    if (_topicsLoading.contains(key)) {
      if (force || postNumber != null) {
        _topicRefreshPending.add(key);
        if (postNumber != null) {
          _topicRefreshPostNumbers[key] = postNumber;
        }
      }
      return;
    }
    final held = store.read<TopicDetail>(instance.url, topicId);
    if (held != null && !force && !_topicsStale.contains(key)) {
      final targetHeld = postNumber == null
          ? true
          : held.stream.any((id) {
              final post = store.read<Post>(instance.url, id);
              return post?.postNumber == postNumber;
            });
      if (targetHeld) return;
    }
    final lease = lifecycle.capture(instance.url);
    final elapsed = Stopwatch()..start();
    final bookmarkVersion = _bookmarkVersion(instance.url, topicId);

    _topicsLoading.add(key);
    _notify();

    try {
      final credential = await _awaitTopicLoadStage(
        _readSessionValue(lease, () => authenticator.apiKeyFor(instance.url)),
        elapsed,
        'reading credentials for topic $topicId',
      );
      if (credential == null || !lease.isCurrent) return;
      final fetched = await _awaitTopicLoadStage(
        api.topicContent.topic(
          siteUrl: instance.url,
          slug: slug,
          id: topicId,
          postNumber: postNumber,
          apiKey: credential.value,
        ),
        elapsed,
        'loading topic $topicId',
      );
      lease.commit(() {
        _absorb(
          instance.url,
          fetched,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        if (currentInstance?.url == instance.url) {
          _retitle(topicId, fetched.detail.title);
        }
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(error, stackTrace, 'topic.load', degraded: false);
    } finally {
      var replayRefresh = false;
      int? replayPostNumber;
      lease.commit(() {
        _topicsLoading.remove(key);
        replayRefresh = _topicRefreshPending.remove(key);
        if (replayRefresh) {
          replayPostNumber = _topicRefreshPostNumbers.remove(key);
        }
        _notify();
      });
      if (replayRefresh && lease.isCurrent) {
        unawaited(
          _refetchTopic(
            instance.url,
            topicId,
            '',
            postNumber: replayPostNumber,
          ),
        );
      }
    }
  }

  void _retitle(int topicId, String title) {
    if (title.isEmpty) return;
    final siteUrl = currentInstance?.url;
    if (siteUrl == null) return;
    _rewriteTopicRoutes(siteUrl, topicId, (route) {
      if (route.title == title) return route;
      return ContentRoute.topic(
        topicId: topicId,
        slug: route.slug ?? '',
        title: title,
        subtitle: route.subtitle,
        color: route.color,
        postNumber: route.postNumber,
      );
    });
  }

  void _updateTopicRouteMetadata(
    String siteUrl,
    int topicId,
    String title,
    int? categoryId,
  ) {
    final category = categoryFor(categoryId, siteUrl: siteUrl);
    _rewriteTopicRoutes(siteUrl, topicId, (route) {
      return ContentRoute.topic(
        topicId: topicId,
        slug: route.slug ?? '',
        title: title,
        subtitle: route.subtitle,
        color: category == null ? null : Color(category.colorValue),
        postNumber: route.postNumber,
      );
    });
  }

  void _rewriteTopicRoutes(
    String siteUrl,
    int topicId,
    ContentRoute Function(ContentRoute route) rewrite,
  ) {
    final workspace = _forumWorkspaces[siteUrl];
    if (workspace == null) return;
    var changed = false;
    final tabs = <ForumTab>[];
    for (final tab in workspace.tabs) {
      var tabChanged = false;
      List<ContentRoute> rewriteRoutes(List<ContentRoute> source) {
        final routes = <ContentRoute>[];
        for (final route in source) {
          if (route.topicId != topicId) {
            routes.add(route);
            continue;
          }
          final updated = rewrite(route);
          routes.add(updated);
          tabChanged = tabChanged || !identical(updated, route);
        }
        return routes;
      }

      final routes = rewriteRoutes(tab.contentStack);
      final forwardRoutes = rewriteRoutes(tab.forwardStack);
      changed = changed || tabChanged;
      tabs.add(
        tabChanged
            ? tab.copyWith(contentStack: routes, forwardStack: forwardRoutes)
            : tab,
      );
    }
    if (changed) _putWorkspace(workspace.copyWith(tabs: tabs));
  }

  TopicDetail _absorb(
    String siteUrl,
    TopicPayload payload, {
    int? bookmarkVersionAtDispatch,
  }) {
    final preserveBookmarks =
        bookmarkVersionAtDispatch != null &&
        bookmarkVersionAtDispatch !=
            _bookmarkVersion(siteUrl, payload.detail.id);
    final heldDetail = store.read<TopicDetail>(siteUrl, payload.detail.id);
    final posts = preserveBookmarks
        ? [
            for (final incoming in payload.posts)
              switch (store.read<Post>(siteUrl, incoming.id)) {
                final held? => incoming.withBookmarkOf(held),
                null => incoming,
              },
          ]
        : payload.posts;
    store.putAll(siteUrl, posts);
    final incomingDetail = preserveBookmarks && heldDetail != null
        ? payload.detail.withBookmarksOf(heldDetail)
        : payload.detail;
    final detail = store.put(siteUrl, incomingDetail);
    _topicsStale.remove(_topicKey(siteUrl, detail.id));
    store.update<Topic>(
      siteUrl,
      detail.id,
      (row) => row
          .copyWith(
            title: detail.title,
            postsCount: detail.postsCount,
            bookmarked: detail.hasBookmarks,
          )
          .withPlugins(detail.plugins),
    );
    return detail;
  }

  Future<void> expandPostGap({
    required int anchorPostId,
    required bool before,
  }) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return;

    final detail = store.read<TopicDetail>(instance.url, topicId);
    if (detail == null) return;
    final gap = (before ? detail.gapsBefore : detail.gapsAfter)[anchorPostId];
    if (gap == null || gap.isEmpty) return;

    final requestIds = gap.take(TopicDetail.maximumInitialPosts).toList();
    final key = (instance.url, topicId, anchorPostId, before);
    if (!_postGapsLoading.add(key)) return;
    final lease = lifecycle.capture(instance.url);
    final bookmarkVersion = _bookmarkVersion(instance.url, topicId);

    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      final fetched = await api.topicContent.posts(
        siteUrl: instance.url,
        topicId: topicId,
        ids: requestIds,
        apiKey: credential.value,
      );
      if (!lease.isCurrent) return;

      final requested = requestIds.toSet();
      final byId = <int, Post>{
        for (final post in fetched)
          if (requested.contains(post.id)) post.id: post,
      };
      final revealed = [
        for (final id in requestIds)
          if (byId.containsKey(id)) id,
      ];
      lease.commit(() {
        _putTopicPosts(instance.url, topicId, [
          for (final id in revealed) byId[id]!,
        ], bookmarkVersionAtDispatch: bookmarkVersion);
        store.update<TopicDetail>(
          instance.url,
          topicId,
          (held) => held.withExpandedGap(
            anchorPostId: anchorPostId,
            before: before,
            consumedIds: requestIds,
            revealedIds: revealed,
          ),
        );
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topic.expandPostGap',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      lease.commit(() => _postGapsLoading.remove(key));
    }
  }

  Future<bool> updateTopicNotificationLevel(
    String siteUrl,
    int topicId,
    TopicNotificationLevel level,
  ) {
    if (isDisposed || topicId <= 0) return Future.value(false);
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null) return Future.value(false);

    final key = _topicKey(siteUrl, topicId);
    if (held.notificationLevel == level &&
        !_topicNotificationTails.containsKey(key)) {
      return Future.value(true);
    }
    _topicNotificationConfirmed.putIfAbsent(key, () => held.notificationLevel);
    final revision = (_topicNotificationRevisions[key] ?? 0) + 1;
    _topicNotificationRevisions[key] = revision;
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (topic) => topic.withNotificationLevel(level),
    );
    _notify();

    final write = _QueuedTopicNotification(
      siteUrl: siteUrl,
      topicId: topicId,
      level: level,
      revision: revision,
      lease: lifecycle.capture(siteUrl),
    );
    final previousTail = _topicNotificationTails[key] ?? Future.value();
    late final Future<void> tail;
    tail = previousTail
        .catchError((_) {
          // Every write settles internally. Keep one unexpected failure from
          // stranding later selections in the queue.
        })
        .then((_) => _performTopicNotificationWrite(key, write))
        .whenComplete(() {
          if (!identical(_topicNotificationTails[key], tail)) return;
          final _ = _topicNotificationTails.remove(key);
          _topicNotificationRevisions.remove(key);
          _topicNotificationConfirmed.remove(key);
        });
    _topicNotificationTails[key] = tail;
    unawaited(tail);
    return write.result.future;
  }

  Future<void> _performTopicNotificationWrite(
    String key,
    _QueuedTopicNotification write,
  ) async {
    bool isLatest() =>
        _topicNotificationRevisions[key] == write.revision &&
        write.lease.isCurrent &&
        !isDisposed;

    if (!isLatest()) {
      write.complete(false);
      return;
    }

    try {
      final credential = await _credentialForWrite(write.siteUrl);
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      if (credential.failure != null) {
        _rollbackTopicNotification(key, write);
        write.complete(false);
        return;
      }
      final clientId = await authenticator.clientId();
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      await api.topicMutations.updateTopicNotificationLevel(
        siteUrl: write.siteUrl,
        apiKey: credential.apiKey!,
        topicId: write.topicId,
        notificationLevel: write.level,
        clientId: clientId,
      );
      if (!write.lease.isCurrent || isDisposed) {
        write.complete(false);
        return;
      }
      _topicNotificationConfirmed[key] = write.level;
      if (isLatest()) {
        write.lease.commit(() {
          store.update<TopicDetail>(
            write.siteUrl,
            write.topicId,
            (topic) => topic.withNotificationLevel(write.level),
          );
          _notify();
        });
      }
      write.complete(true);
    } catch (error, stackTrace) {
      if (write.lease.isCurrent && !isDisposed) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.updateNotificationLevel',
          severity: DiagnosticSeverity.warning,
        );
        if (isLatest()) _rollbackTopicNotification(key, write);
      }
      write.complete(false);
    }
  }

  void _rollbackTopicNotification(String key, _QueuedTopicNotification write) {
    if (!write.lease.isCurrent || isDisposed) return;
    final confirmed = _topicNotificationConfirmed[key];
    if (confirmed == null) return;
    write.lease.commit(() {
      store.update<TopicDetail>(
        write.siteUrl,
        write.topicId,
        (topic) => topic.withNotificationLevel(confirmed),
      );
      _notify();
    });
  }

  bool topicPinWriteInFlight(String siteUrl, int topicId) =>
      _topicPinWrites.contains(_topicKey(siteUrl, topicId));

  Future<String?> updateTopicPinPreference(
    String siteUrl,
    int topicId,
    bool pinned,
  ) async {
    if (isDisposed || topicId <= 0) {
      return 'This topic can no longer be changed.';
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null || !held.hasPinPreference) {
      return 'This topic does not offer a pin preference.';
    }
    if (held.pinned == pinned) return null;

    final key = _topicKey(siteUrl, topicId);
    if (!_topicPinWrites.add(key)) {
      return 'Another pin change is still finishing.';
    }
    final heldRow = store.read<Topic>(siteUrl, topicId);
    final lease = lifecycle.capture(siteUrl);

    void project(bool nextPinned, bool nextUnpinned) {
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.copyWith(pinned: nextPinned, unpinned: nextUnpinned),
        );
        store.update<Topic>(
          siteUrl,
          topicId,
          (topic) => topic.copyWith(pinned: nextPinned),
        );
        _notify();
      });
    }

    void rollback() {
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) =>
              topic.copyWith(pinned: held.pinned, unpinned: held.unpinned),
        );
        if (heldRow != null) store.put(siteUrl, heldRow);
        _notify();
      });
    }

    project(pinned, !pinned);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) {
        rollback();
        return failure.message;
      }
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      await api.topicMutations.updateTopicPinForUser(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        pinned: pinned,
        clientId: clientId,
      );
      return null;
    } on WriteException catch (error) {
      if (lease.isCurrent && !isDisposed) rollback();
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'topic.updatePinPreference');
        rollback();
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _topicPinWrites.remove(key);
      if (!isDisposed) _notify();
    }
  }

  bool topicStatusWriteInFlight(String siteUrl, int topicId) =>
      _topicStatusWrites.contains(_topicKey(siteUrl, topicId));

  Future<String?> updateTopicStatus(
    String siteUrl,
    int topicId,
    TopicStatusProperty status,
    bool enabled,
  ) async {
    if (isDisposed || topicId <= 0) {
      return 'This topic can no longer be changed.';
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null || !held.canChangeStatus(status)) {
      return 'This topic can no longer be changed that way.';
    }
    if (held.statusValue(status) == enabled) return null;

    final key = _topicKey(siteUrl, topicId);
    if (!_topicStatusWrites.add(key)) {
      return 'Another topic action is still finishing.';
    }
    final lease = lifecycle.capture(siteUrl);
    _notify();
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      await api.topicMutations.updateTopicStatus(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        status: status,
        enabled: enabled,
        clientId: clientId,
      );
      if (!lease.isCurrent || isDisposed) return null;
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.withStatus(status, enabled),
        );
        if (status == TopicStatusProperty.closed) {
          store.update<Topic>(
            siteUrl,
            topicId,
            (topic) => topic.copyWith(closed: enabled),
          );
        }
        _notify();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'topic.updateStatus');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _topicStatusWrites.remove(key);
      if (!isDisposed) _notify();
    }
  }

  bool topicDeletionWriteInFlight(String siteUrl, int topicId) =>
      _topicDeletionWrites.contains(_topicKey(siteUrl, topicId));

  Future<String?> setTopicDeleted(
    String siteUrl,
    int topicId,
    bool deleted,
  ) async {
    if (isDisposed || topicId <= 0) {
      return 'This topic can no longer be changed.';
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    final allowed = deleted
        ? held?.canDeleteTopic == true
        : held?.canRecoverTopic == true;
    if (held == null || !allowed) {
      return deleted
          ? 'This topic cannot be deleted.'
          : 'This topic cannot be recovered.';
    }
    final key = _topicKey(siteUrl, topicId);
    if (!_topicDeletionWrites.add(key)) {
      return 'Another topic action is still finishing.';
    }
    final lease = lifecycle.capture(siteUrl);
    _notify();
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      if (deleted) {
        await api.topicMutations.deleteTopic(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          clientId: clientId,
        );
      } else {
        await api.topicMutations.recoverTopic(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          clientId: clientId,
        );
      }
      if (!lease.isCurrent || isDisposed) return null;
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.withDeletion(deleted, DateTime.now().toUtc()),
        );
        _notify();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'topic.setDeleted');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _topicDeletionWrites.remove(key);
      if (!isDisposed) _notify();
    }
  }

  void _putTopicPosts(
    String siteUrl,
    int topicId,
    Iterable<Post> incoming, {
    required int bookmarkVersionAtDispatch,
  }) {
    final preserveBookmarks =
        bookmarkVersionAtDispatch != _bookmarkVersion(siteUrl, topicId);
    store.putAll(
      siteUrl,
      preserveBookmarks
          ? [
              for (final post in incoming)
                switch (store.read<Post>(siteUrl, post.id)) {
                  final held? => post.withBookmarkOf(held),
                  null => post,
                },
            ]
          : incoming,
    );
  }

  Future<void> markTopicRead(
    String siteUrl,
    int topicId,
    int postNumber, {
    required bool caughtUp,
  }) {
    final receipt = _topicReads.mark(
      siteUrl,
      topicId,
      postNumber,
      caughtUp: caughtUp,
    );
    return receipt;
  }

  Future<void> loadMorePosts({int batchSize = 20}) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return;

    final key = _topicKey(instance.url, topicId);
    final detail = store.read<TopicDetail>(instance.url, topicId);
    if (detail == null) return;
    if (_postsLoading.contains(key)) return;

    final boundedBatch = batchSize.clamp(1, TopicDetail.maximumInitialPosts);
    final pending = _pendingPostIds(instance.url, detail);
    if (pending.isEmpty) return;
    final requestIds = pending.take(boundedBatch).toList();
    // Recommendations are dynamic: resolve them only at the final window and
    // never replace an existing snapshot with a later empty response.
    final resolveRecommendations =
        detail.recommendations == null && requestIds.length == pending.length;
    final lease = lifecycle.capture(instance.url);
    final bookmarkVersion = _bookmarkVersion(instance.url, topicId);

    _postsLoading.add(key);
    _notify();

    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      final page = resolveRecommendations
          ? await api.topicContent.topicPosts(
              siteUrl: instance.url,
              topicId: topicId,
              ids: requestIds,
              apiKey: credential.value,
            )
          : (
              posts: await api.topicContent.posts(
                siteUrl: instance.url,
                topicId: topicId,
                ids: requestIds,
                apiKey: credential.value,
              ),
              recommendations: null,
            );
      lease.commit(() {
        _putTopicPosts(
          instance.url,
          topicId,
          page.posts,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        if (page.recommendations case final recommendations?) {
          store.update<TopicDetail>(
            instance.url,
            topicId,
            // A topic refetch may have supplied a snapshot while this post
            // page was in flight. Paging only fills an unresolved value; it
            // never replaces a recommendation set that arrived later.
            (detail) => detail.recommendations == null
                ? detail.withRecommendations(recommendations)
                : detail,
          );
        }
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topic.loadMorePosts',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      lease.commit(() {
        _postsLoading.remove(key);
        _notify();
      });
    }
  }

  Future<void> loadEarlierPosts({int batchSize = 20}) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return;

    final key = _topicKey(instance.url, topicId);
    final detail = store.read<TopicDetail>(instance.url, topicId);
    if (detail == null) return;
    if (_earlierPostsLoading.contains(key)) return;

    final boundedBatch = batchSize.clamp(1, TopicDetail.maximumInitialPosts);
    final pending = _pendingEarlierPostIds(instance.url, detail, boundedBatch);
    if (pending.isEmpty) return;
    final lease = lifecycle.capture(instance.url);
    final bookmarkVersion = _bookmarkVersion(instance.url, topicId);

    _earlierPostsLoading.add(key);
    _notify();

    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      final posts = await api.topicContent.posts(
        siteUrl: instance.url,
        topicId: topicId,
        ids: pending,
        apiKey: credential.value,
      );
      lease.commit(
        () => _putTopicPosts(
          instance.url,
          topicId,
          posts,
          bookmarkVersionAtDispatch: bookmarkVersion,
        ),
      );
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topic.loadEarlierPosts',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      lease.commit(() {
        _earlierPostsLoading.remove(key);
        _notify();
      });
    }
  }

  bool get loadingMorePosts {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _postsLoading.contains(_topicKey(instance.url, topicId));
  }

  bool get loadingEarlierPosts {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _earlierPostsLoading.contains(_topicKey(instance.url, topicId));
  }

  Future<String?> toggleTopicSummary() async {
    final instance = currentInstance;
    final topic = currentTopic;
    if (instance == null || topic == null || !topic.hasSummary) return null;

    final key = _topicKey(instance.url, topic.id);
    if (_topicSummaryStreams.remove(key) != null) {
      _notify();
      return null;
    }
    if (!_topicSummariesLoading.add(key)) return null;
    final lease = lifecycle.capture(instance.url);
    _notify();

    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return null;
      final payload = await api.topicContent.topic(
        siteUrl: instance.url,
        slug: currentContent?.slug ?? '',
        id: topic.id,
        summary: true,
        apiKey: credential.value,
      );
      lease.commit(() {
        store.putAll(instance.url, payload.posts);
        _topicSummaryStreams[key] = List.unmodifiable(payload.detail.stream);
      });
      return null;
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.loadSummary',
          severity: DiagnosticSeverity.warning,
        );
      }
      return "Couldn't load this topic's summary.";
    } finally {
      lease.commit(() {
        _topicSummariesLoading.remove(key);
        _notify();
      });
    }
  }

  ComposerController? _composer;
  ComposerController? _floatingComposerBoundsOwner;
  Rect? _floatingComposerBounds;

  late final ComposerDraftCoordinator _composerDrafts =
      ComposerDraftCoordinator(
        localStore: drafts,
        persistence: api.composerPersistence,
        draftsApi: api.drafts,
        lifecycle: lifecycle,
        readCredential: _credentialForWrite,
        readClientId: authenticator.clientId,
        isDisposed: () => isDisposed,
        isCurrentComposer: (composer) => identical(_composer, composer),
        readCachedDraft: (target) => target.createsTopic
            ? null
            : store.read<TopicDetail>(target.siteUrl, target.topicId)?.draft,
        readCachedSequence: (target) => target.createsTopic
            ? 0
            : store
                      .read<TopicDetail>(target.siteUrl, target.topicId)
                      ?.draftSequence ??
                  0,
        writeCachedDraft: (target, draft, sequence) {
          store.update<TopicDetail>(
            target.siteUrl,
            target.topicId,
            (detail) => detail.withDraft(draft, sequence),
          );
        },
        minimumRequiredTagsFor: (siteUrl, categoryId) =>
            topicComposerCategories(siteUrl)
                .where((category) => category.id == categoryId)
                .firstOrNull
                ?.minimumRequiredTags ??
            0,
        isServerDraftKnown: (target) =>
            draftList
                .feedFor(target.siteUrl)
                .drafts
                .any((draft) => draft.key == target.draftKey) ||
            (!target.createsTopic &&
                store
                        .read<TopicDetail>(target.siteUrl, target.topicId)
                        ?.draft !=
                    null),
        recordDraftDestroyed: _recordDraftDestroyed,
        onComposerClosed: (composer) {
          if (!identical(_composer, composer)) return;
          _composer = null;
          _notify();
        },
        reportError: _reportOperationalError,
      );

  ComposerController? get visibleComposer {
    final composer = _composer;
    final instance = currentInstance;
    if (_rootMode != ShellRootMode.forum ||
        composer == null ||
        instance == null) {
      return null;
    }
    if (composer.target.siteUrl != instance.url) return null;
    if (composer.target.tabId case final tabId?) {
      if (tabId != activeTabId) return null;
    }
    return composer;
  }

  /// Receives the actual painted composer rectangle without making its
  /// movable presentation geometry part of the composer domain model.
  void reportFloatingComposerBounds(ComposerController composer, Rect? bounds) {
    if (isDisposed) return;
    if (bounds == null) {
      if (!identical(_floatingComposerBoundsOwner, composer)) return;
      _floatingComposerBoundsOwner = null;
      _floatingComposerBounds = null;
      _notify();
      return;
    }
    if (!identical(visibleComposer, composer) ||
        identical(_floatingComposerBoundsOwner, composer) &&
            _floatingComposerBounds == bounds) {
      return;
    }
    _floatingComposerBoundsOwner = composer;
    _floatingComposerBounds = bounds;
    _notify();
  }

  bool get canReplyHere => currentTopic?.canCreatePost ?? false;

  ComposerController _buildTextComposer(
    ComposerTarget target, {
    bool persistsDraft = false,
    int minimumRequiredTags = 0,
  }) {
    final config = siteConfigFor(target.siteUrl);
    final draftSession = persistsDraft
        ? _composerDrafts.openSession(target)
        : null;
    ComposerPluginState readPluginState() {
      final currentUser = currentUserFor(target.siteUrl);
      final freshCurrentUser = freshCurrentUserFor(target.siteUrl);
      final editingPostId = target.editingPostId;
      final editingPost = editingPostId == null
          ? null
          : store.read<Post>(target.siteUrl, editingPostId);
      return ComposerPluginState(
        siteSettings: siteConfigFor(target.siteUrl).plugins,
        currentUser: currentUser?.plugins ?? PluginData.none,
        freshCurrentUser: freshCurrentUser?.plugins ?? PluginData.none,
        editingPost: editingPost?.plugins ?? PluginData.none,
        accountTimezone: currentUser?.timezone,
        freshCurrentUserIsStaff: freshCurrentUser?.staff == true,
      );
    }

    final initialPluginState = readPluginState();
    late final ComposerController composer;
    composer = ComposerController(
      target,
      onSaveDraft: draftSession?.save,
      onStageDraft: draftSession?.stage,
      search: _composerSearch(target),
      onEmojiAccepted: (code) => unawaited(
        emojiPickerStore.trackEmoji(
          siteUrl: target.siteUrl,
          context:
              target.policy?.emojiUsageContext ?? CoreEmojiUsageContexts.topic,
          emoji: code,
        ),
      ),
      resolveEmoji: (name) => emojiUrlFor(target.siteUrl, name),
      pills: _composerPills(target),
      pluginHashtagPresentation: plugins.registry.pluginHashtagPresentation,
      formatQuoteContents: (block) =>
          quoteContentsFor(target, block) ?? block.contents,
      syntaxPolicies: plugins.registry.composerSyntaxPolicies(
        ComposerSyntaxPolicyContext(
          siteUrl: target.siteUrl,
          isPluginTarget: target.isPlugin,
          isEdit: target.isEdit,
          initialState: initialPluginState,
          readState: readPluginState,
        ),
      ),
      pluginStateReader: readPluginState,
      isCurrentComposer: () => identical(_composer, composer),
      imageUploader: !(target.policy?.uploadsEnabled ?? true)
          ? null
          : (file, {required onProgress, required abortTrigger}) =>
                _uploadComposerImage(
                  target,
                  file,
                  onProgress: onProgress,
                  abortTrigger: abortTrigger,
                ),
      resolveUploadUrls: (urls) => _resolveComposerUploadUrls(target, urls),
      canUploadImage: (filename) => config.canUploadImage(
        filename,
        staff: currentUserFor(target.siteUrl)?.staff == true,
      ),
      simultaneousUploads: config.simultaneousUploads,
      enableAutoGridImages: config.enableAutoGridImages,
      enableMarkdownLinkify: config.enableMarkdownLinkify,
      markdownLinkifyTlds: config.markdownLinkifyTlds,
      maxImageWidth: config.maxImageWidth,
      maxImageHeight: config.maxImageHeight,
      minimumRequiredTags: minimumRequiredTags,
    );
    if (draftSession != null) _composerDrafts.attach(draftSession, composer);
    return composer;
  }

  String? quoteContentsFor(ComposerTarget target, ComposerQuoteBlock block) {
    final topicId = block.topicId;
    final postNumber = block.postNumber;
    if (topicId == null || postNumber == null) return null;
    final topic = store.read<TopicDetail>(target.siteUrl, topicId);
    if (topic == null) return null;

    for (final id in topic.stream) {
      final post = store.read<Post>(target.siteUrl, id);
      if (post?.postNumber != postNumber) continue;
      return postQuoteContentsFromSelection(post!.cooked, block.contents);
    }
    return null;
  }

  ComposerController? buildPluginComposer(ComposerTargetRequest request) {
    final policy = plugins.registry.composerTarget(
      request,
      ComposerTargetContext(
        siteSettings: siteConfigFor(request.siteUrl).plugins,
        currentUser:
            currentUserFor(request.siteUrl)?.plugins ?? PluginData.none,
      ),
    );
    if (policy == null) return null;
    return _buildTextComposer(
      ComposerTarget.plugin(
        siteUrl: request.siteUrl,
        topicTitle: request.title,
        policy: policy,
        data: Map.unmodifiable(request.data),
      ),
    );
  }

  void openPrivateMessage({
    required String siteUrl,
    required String targetRecipients,
  }) {
    final instance = currentInstance;
    final route = currentContent;
    final tabId = activeTabId;
    final feedId = currentFeedId;
    final recipients = targetRecipients
        .split(',')
        .map((recipient) => recipient.trim())
        .where((recipient) => recipient.isNotEmpty)
        .join(',');
    if (instance?.url != siteUrl ||
        instance?.user?.canSendPrivateMessages != true ||
        route?.isTopic != false ||
        tabId == null ||
        feedId == null ||
        recipients.isEmpty) {
      return;
    }

    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: siteUrl,
      tabId: tabId,
      topicId: 0,
      slug: '',
      topicTitle: 'New message',
      mode: ComposerMode.privateMessage,
      originFeedId: feedId,
      targetRecipients: recipients,
    );
    final composer = _buildTextComposer(target, persistsDraft: true);
    _composer = composer;
    _notify();
    _composerDrafts.startRestore(composer);
    composer.requestFocus();
  }

  Future<void> openNewTopic() =>
      _openNewTopic(permitted: canCreateTopicHere, revealContent: false);

  Future<void> openNewTopicFromSidebar() =>
      _openNewTopic(permitted: canCreateTopicFromSidebar, revealContent: true);

  Future<void> _openNewTopic({
    required bool permitted,
    required bool revealContent,
  }) async {
    final instance = currentInstance;
    final route = currentContent;
    final feedId = currentFeedId;
    final tabId = activeTabId;
    if (instance == null ||
        route == null ||
        feedId == null ||
        tabId == null ||
        !permitted) {
      return;
    }
    final originFeedId = revealContent && !canCreateTopicHere
        ? instance.defaultDestination.id
        : feedId;

    final lease = lifecycle.capture(instance.url);
    var capabilities = _topicComposerCapabilities[instance.url];
    var categories = _categoriesBySite[instance.url];
    String? apiKey;
    if (capabilities == null || categories == null) {
      final credential = await _credentialForWrite(instance.url);
      if (!lease.isCurrent || currentFeedId != feedId || activeTabId != tabId) {
        return;
      }
      if (credential.failure != null) return;
      apiKey = credential.apiKey!;
      try {
        final results = await Future.wait<Object>([
          api.topicComposerQueries.topicComposerCapabilities(
            siteUrl: instance.url,
            apiKey: apiKey,
          ),
          api.categories.categories(siteUrl: instance.url, apiKey: apiKey),
        ]);
        capabilities = results[0] as TopicComposerCapabilities;
        categories = results[1] as List<TopicCategory>;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(
            error,
            stackTrace,
            'composer.topicCapabilities',
            severity: DiagnosticSeverity.warning,
          );
        }
        return;
      }
    }
    if (!lease.isCurrent || currentFeedId != feedId || activeTabId != tabId) {
      return;
    }

    int? categoryId;
    var tags = const <TopicTag>[];
    final path = route.feedPath;
    final link = path == null
        ? null
        : ListLink.parse(path.replaceFirst(RegExp(r'\.json$'), ''));
    if (link?.kind == ListKind.category) {
      final category = categories
          .where((item) => item.id == link?.id)
          .firstOrNull;
      if (category?.canCreateTopic == true) categoryId = category!.id;
    } else if (link?.kind == ListKind.tag && capabilities.canTagTopics) {
      try {
        if (apiKey == null) {
          final credential = await _credentialForWrite(instance.url);
          apiKey = credential.apiKey;
        }
        if (apiKey == null) return;
        final result = await api.topicComposerQueries.searchTopicTags(
          siteUrl: instance.url,
          apiKey: apiKey,
          term: link!.slug,
          categoryId: categoryId,
        );
        final exact = result.results.where(
          (tag) =>
              tag.id == link.id ||
              tag.name.toLowerCase() == link.slug.toLowerCase() ||
              tag.slug?.toLowerCase() == link.slug.toLowerCase(),
        );
        if (exact.isNotEmpty && !exact.first.disabled) tags = [exact.first];
      } catch (_) {}
    }
    if (!lease.isCurrent || currentFeedId != feedId || activeTabId != tabId) {
      return;
    }

    _categoriesBySite[instance.url] = List.unmodifiable(categories);
    _topicComposerCapabilities[instance.url] = capabilities;
    store.putAll(instance.url, categories);
    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: tabId,
      topicId: 0,
      slug: '',
      topicTitle: 'New topic',
      mode: ComposerMode.newTopic,
      originFeedId: originFeedId,
      initialCategoryId: categoryId,
      initialTags: tags,
    );
    final composer = _buildTextComposer(
      target,
      persistsDraft: true,
      minimumRequiredTags:
          categories
              .where((category) => category.id == categoryId)
              .firstOrNull
              ?.minimumRequiredTags ??
          0,
    );
    _composer = composer;
    if (revealContent) _mobilePane = MobilePane.content;
    _notify();
    _composerDrafts.startRestore(composer);
  }

  Future<void> openReplyAsNewTopic(String continuation) async {
    final instance = currentInstance;
    final route = currentContent;
    final detail = currentTopic;
    final tabId = activeTabId;
    if (instance == null ||
        route?.topicId == null ||
        detail?.canReplyAsNewTopic != true ||
        tabId == null ||
        continuation.trim().isEmpty) {
      return;
    }

    final siteUrl = instance.url;
    final sourceTopicId = detail!.id;
    final lease = lifecycle.capture(siteUrl);
    await Future.wait<void>([
      loadCategories(siteUrl),
      _ensureTopicComposerCapabilities(siteUrl),
    ]);
    if (!lease.isCurrent ||
        activeTabId != tabId ||
        currentInstance?.url != siteUrl ||
        currentContent?.topicId != sourceTopicId ||
        currentTopic?.canReplyAsNewTopic != true) {
      return;
    }

    final category = topicComposerCategories(siteUrl)
        .where((item) => item.id == detail.categoryId && item.canCreateTopic)
        .firstOrNull;
    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: siteUrl,
      tabId: tabId,
      topicId: 0,
      slug: '',
      topicTitle: 'New topic',
      mode: ComposerMode.newTopic,
      originTopicId: sourceTopicId,
      initialCategoryId: category?.id,
    );
    final composer = _buildTextComposer(
      target,
      persistsDraft: true,
      minimumRequiredTags: category?.minimumRequiredTags ?? 0,
    );
    _composer = composer;
    _notify();
    _composerDrafts.startRestore(composer);

    try {
      await _composerDrafts.restoreTaskFor(composer);
    } catch (_) {}
    if (!lease.isCurrent ||
        !identical(_composer, composer) ||
        activeTabId != tabId ||
        currentContent?.topicId != sourceTopicId) {
      return;
    }
    if (!composer.text.text.contains(continuation.trim())) {
      composer.prependBlock(continuation);
    }
    composer.focus.requestFocus();
  }

  Future<OpenComposerResult> openNewTopicFromPlugin(
    OpenNewTopicComposerRequest request,
  ) async {
    final siteUrl = request.siteUrl;
    final sourceRouteId = request.sourceRouteId;
    final route = currentContent;
    final tabId = activeTabId;
    final feedId = currentFeedId;
    bool sourceIsCurrent() => request.sourceStillCurrent?.call() ?? true;

    if (!forumActive || route?.id != sourceRouteId || !sourceIsCurrent()) {
      return OpenComposerResult.sourceChanged;
    }
    if (request.seed.raw.trim().isEmpty ||
        currentInstance?.url != siteUrl ||
        currentInstance?.user == null ||
        tabId == null ||
        feedId == null) {
      return OpenComposerResult.unavailable;
    }

    final lease = lifecycle.capture(siteUrl);
    await Future.wait<void>([
      loadCategories(siteUrl),
      _ensureTopicComposerCapabilities(siteUrl),
    ]);
    if (!forumActive ||
        !lease.isCurrent ||
        currentInstance?.url != siteUrl ||
        currentContent?.id != sourceRouteId ||
        !sourceIsCurrent() ||
        activeTabId != tabId ||
        currentFeedId != feedId) {
      return OpenComposerResult.sourceChanged;
    }

    final category = request.initialCategoryId == null
        ? null
        : topicComposerCategories(siteUrl)
              .where(
                (item) =>
                    item.id == request.initialCategoryId && item.canCreateTopic,
              )
              .firstOrNull;
    var composer = visibleComposer;
    final reusable =
        composer != null &&
        composer.target.isNewTopic &&
        composer.target.siteUrl == siteUrl &&
        composer.target.tabId == tabId &&
        composer.target.originFeedId == feedId;
    if (!reusable) {
      if (!_replaceComposer()) return OpenComposerResult.unavailable;
      final target = ComposerTarget(
        siteUrl: siteUrl,
        tabId: tabId,
        topicId: 0,
        slug: '',
        topicTitle: 'New topic',
        mode: ComposerMode.newTopic,
        originFeedId: feedId,
        initialCategoryId: category?.id,
      );
      composer = _buildTextComposer(
        target,
        persistsDraft: true,
        minimumRequiredTags: category?.minimumRequiredTags ?? 0,
      );
      _composer = composer;
      _notify();
      _composerDrafts.startRestore(composer);
    }

    try {
      await _composerDrafts.restoreTaskFor(composer);
    } catch (_) {}
    if (!forumActive ||
        !lease.isCurrent ||
        !identical(_composer, composer) ||
        currentContent?.id != sourceRouteId ||
        !sourceIsCurrent() ||
        activeTabId != tabId) {
      return OpenComposerResult.sourceChanged;
    }
    switch (request.seed.placement) {
      case ComposerSeedPlacement.block:
        if (!composer.insertBlock(
          expectedValue: composer.value,
          markdown: request.seed.raw,
        )) {
          return OpenComposerResult.sourceChanged;
        }
    }
    composer.requestFocus();
    return OpenComposerResult.opened;
  }

  Future<TopicTagSearch> searchComposerTags(
    ComposerController composer,
    String term,
  ) async {
    final target = composer.target;
    final lease = lifecycle.capture(target.siteUrl);
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(target.siteUrl),
    );
    if (held == null || !lease.isCurrent || !identical(_composer, composer)) {
      return const TopicTagSearch();
    }
    if (held.value.failure case final failure?) {
      throw failure;
    }
    return api.topicComposerQueries.searchTopicTags(
      siteUrl: target.siteUrl,
      apiKey: held.value.apiKey!,
      term: term,
      categoryId: composer.categoryId,
      selectedTagIds: composer.tags.map((tag) => tag.id).whereType<int>(),
      // Core rejects a page larger than the site's own setting outright, so
      // the site sets this and the client only caps what it will render.
      limit: siteConfigFor(
        target.siteUrl,
      ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
    );
  }

  Future<TopicTagSearch> searchTopicTagsForEditor({
    required String siteUrl,
    required int? categoryId,
    required Iterable<TopicTag> selectedTags,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(siteUrl),
    );
    if (held == null || !lease.isCurrent) return const TopicTagSearch();
    if (held.value.failure case final failure?) throw failure;
    return api.topicComposerQueries.searchTopicTags(
      siteUrl: siteUrl,
      apiKey: held.value.apiKey!,
      term: term,
      categoryId: categoryId,
      selectedTagIds: selectedTags.map((tag) => tag.id).whereType<int>(),
      limit: siteConfigFor(
        siteUrl,
      ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
    );
  }

  Future<List<TopicCategory>> searchTopicCategoriesForEditor({
    required String siteUrl,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(siteUrl),
    );
    if (held == null || !lease.isCurrent) return const [];
    if (held.value.failure case final failure?) throw failure;

    final categories = await api.categories.searchCategories(
      siteUrl: siteUrl,
      apiKey: held.value.apiKey!,
      term: term,
      includeUncategorized: siteConfigFor(siteUrl).allowUncategorizedTopics,
    );
    if (!lease.isCurrent) return const [];
    lease.commit(() {
      _mergeCategories(siteUrl, categories);
      _notify();
    });
    return categories;
  }

  Future<void> changeComposerCategory(
    ComposerController composer,
    int? categoryId,
  ) async {
    final minimumRequiredTags = topicComposerCategories(composer.target.siteUrl)
        .where((category) => category.id == categoryId)
        .firstOrNull
        ?.minimumRequiredTags;
    composer.setCategory(
      categoryId,
      minimumRequiredTags: minimumRequiredTags ?? 0,
    );
    if (composer.tags.isEmpty) return;
    final kept = <TopicTag>[];
    for (final selected in composer.tags) {
      try {
        final result = await searchComposerTags(composer, selected.name);
        if (!identical(_composer, composer) ||
            composer.categoryId != categoryId) {
          return;
        }
        final match = result.results
            .where(
              (tag) =>
                  tag.id == selected.id ||
                  tag.name.toLowerCase() == selected.name.toLowerCase(),
            )
            .firstOrNull;
        if (!result.isForbidden && match != null && !match.disabled) {
          kept.add(match);
        }
      } catch (_) {
        return;
      }
    }
    if (!identical(_composer, composer) || composer.categoryId != categoryId) {
      return;
    }
    if (kept.length != composer.tags.length) {
      composer.setTags(kept);
      composer.showNotice(
        'Some tags were removed because they are not allowed in that category.',
      );
    }
  }

  void openReply({
    int? replyToPostNumber,
    String? replyToUsername,
    bool? replyingToWhisper,
  }) {
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !canReplyHere) return;
    final targetsWhisper =
        replyingToWhisper ?? _replyTargetsWhisper(replyToPostNumber);

    final existing = _composer;
    if (existing?.discarding == true) return;
    if (existing != null &&
        !existing.target.isEdit &&
        existing.target.topicId == topicId &&
        existing.target.siteUrl == instance.url &&
        existing.target.tabId == activeTabId) {
      existing.retarget(
        replyToPostNumber: replyToPostNumber,
        replyToUsername: replyToUsername,
        replyingToWhisper: targetsWhisper,
      );
      existing.focus.requestFocus();
      return;
    }

    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: activeTabId,
      topicId: topicId,
      slug: route?.slug ?? '',
      topicTitle: route?.title ?? '',
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
      replyingToWhisper: targetsWhisper,
    );
    final composer = _buildTextComposer(target, persistsDraft: true);
    _composer = composer;
    _notify();

    _composerDrafts.startRestore(composer);
  }

  bool _replyTargetsWhisper(int? postNumber) {
    if (postNumber == null) return false;
    final instance = currentInstance;
    final topic = currentTopic;
    if (instance == null || topic == null) return false;
    for (final postId in topic.stream) {
      final post = store.read<Post>(instance.url, postId);
      if (post?.postNumber == postNumber) return post!.isWhisper;
    }
    return false;
  }

  Future<void> openQuote(Post post, String quote) async {
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null ||
        topicId == null ||
        !canReplyHere ||
        quote.trim().isEmpty) {
      return;
    }

    var composer = _composer;
    final reusesOpenReply =
        composer != null &&
        !composer.target.isEdit &&
        !composer.target.createsTopic &&
        !composer.target.isPlugin &&
        composer.target.topicId == topicId &&
        composer.target.siteUrl == instance.url &&
        composer.target.tabId == activeTabId;

    if (!reusesOpenReply) {
      openReply(
        replyToPostNumber: post.postNumber == 1 ? null : post.postNumber,
        replyToUsername: post.postNumber == 1 ? null : post.username,
        replyingToWhisper: post.postNumber != 1 && post.isWhisper,
      );
      composer = _composer;
    }
    if (composer == null) return;

    final restore = identical(_composer, composer)
        ? _composerDrafts.restoreTaskFor(composer)
        : null;
    if (restore != null) {
      try {
        await restore;
      } catch (_) {}
    }

    if (isDisposed ||
        !identical(_composer, composer) ||
        currentInstance?.url != instance.url ||
        currentContent?.topicId != topicId ||
        activeTabId != composer.target.tabId) {
      return;
    }
    if (!composer.insertBlock(expectedValue: composer.value, markdown: quote)) {
      return;
    }
    composer.focus.requestFocus();
  }

  void openEdit(Post post) {
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !post.canEdit) return;
    unawaited(_ensureTopicComposerCapabilities(instance.url));

    if (!_replaceComposer()) return;
    final detail = currentTopic;
    final editsTopic = post.postNumber == 1 && detail?.canEdit == true;
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: activeTabId,
      topicId: topicId,
      slug: route?.slug ?? '',
      topicTitle: route?.title ?? '',
      editingPostId: post.id,
      editingPostNumber: post.postNumber,
      mode: editsTopic ? ComposerMode.topicEdit : ComposerMode.postEdit,
      initialCategoryId: editsTopic ? detail?.categoryId : null,
      initialTags: editsTopic ? detail?.tags ?? const [] : const [],
    );
    // No `onSaveDraft`: Discourse files a topic's drafts under one key, so
    // saving here would overwrite an unfinished reply with the text of a post
    // that is already published.
    final composer = _buildTextComposer(
      target,
      minimumRequiredTags: editsTopic
          ? categoryFor(
                  detail?.categoryId,
                  siteUrl: instance.url,
                )?.minimumRequiredTags ??
                0
          : 0,
    );
    _composer = composer;
    _notify();

    unawaited(_loadEditBody(composer, post));
  }

  void openCategoryEdit() {
    final instance = currentInstance;
    final route = currentContent;
    final detail = currentTopic;
    if (instance == null || route?.topicId == null || detail?.canEdit != true) {
      return;
    }
    unawaited(_ensureTopicComposerCapabilities(instance.url));
    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: activeTabId,
      topicId: route!.topicId!,
      slug: route.slug ?? '',
      topicTitle: detail!.title,
      editingPostId: detail.stream.firstOrNull,
      editingPostNumber: 1,
      mode: ComposerMode.categoryEdit,
      initialCategoryId: detail.categoryId,
      initialTags: detail.tags,
    );
    _composer = ComposerController(
      target,
      minimumRequiredTags:
          categoryFor(
            detail.categoryId,
            siteUrl: instance.url,
          )?.minimumRequiredTags ??
          0,
    );
    _notify();
  }

  Future<String?> saveTopicTitle({
    required String siteUrl,
    required int topicId,
    required String title,
  }) async {
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    if (detail?.canEdit != true) {
      return 'This topic can no longer be edited.';
    }
    final nextTitle = title.trim();
    if (nextTitle.isEmpty) return 'A topic title is required.';
    if (nextTitle == detail!.title.trim()) return null;

    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return 'The forum changed before the title saved.';
    if (credential.failure case final failure?) return failure.message;

    try {
      await api.topicMutations.updateTopic(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        title: nextTitle,
        originalTitle: detail.title,
        categoryId: detail.categoryId,
        tags: detail.tags,
        originalTags: detail.tags,
      );
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'topic.editTitle');
      }
      return const WriteException(WriteFailure.unreachable).message;
    }
    if (!lease.isCurrent) return 'The forum changed before the title saved.';

    lease.commit(() {
      store.update<TopicDetail>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(title: nextTitle),
      );
      store.update<Topic>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(title: nextTitle),
      );
      _updateTopicRouteMetadata(siteUrl, topicId, nextTitle, detail.categoryId);
      _notify();
    });
    return null;
  }

  Future<String?> saveTopicCategory({
    required String siteUrl,
    required int topicId,
    required int categoryId,
  }) async {
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    if (detail?.canEdit != true) {
      return 'This topic can no longer be edited.';
    }
    if (detail!.categoryId == categoryId) return null;
    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return 'The forum changed before the category saved.';
    if (credential.failure case final failure?) return failure.message;

    final tags = await _tagsAllowedInCategory(
      siteUrl: siteUrl,
      apiKey: credential.apiKey!,
      categoryId: categoryId,
      selected: detail.tags,
    );
    if (!lease.isCurrent) return 'The forum changed before the category saved.';

    try {
      await api.topicMutations.updateTopic(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        title: detail.title,
        originalTitle: detail.title,
        categoryId: categoryId,
        tags: tags,
        originalTags: detail.tags,
      );
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'topic.editCategory');
      }
      return const WriteException(WriteFailure.unreachable).message;
    }
    if (!lease.isCurrent) return 'The forum changed before the category saved.';

    lease.commit(() {
      store.update<TopicDetail>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(categoryId: categoryId, tags: tags),
      );
      store.update<Topic>(
        siteUrl,
        topicId,
        (topic) => topic.copyWith(categoryId: categoryId, tags: tags),
      );
      _updateTopicRouteMetadata(siteUrl, topicId, detail.title, categoryId);
      _notify();
    });
    return null;
  }

  Future<List<TopicTag>> _tagsAllowedInCategory({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required List<TopicTag> selected,
  }) async {
    if (selected.isEmpty) return selected;
    final kept = <TopicTag>[];
    for (final tag in selected) {
      try {
        final result = await api.topicComposerQueries.searchTopicTags(
          siteUrl: siteUrl,
          apiKey: apiKey,
          term: tag.name,
          categoryId: categoryId,
          selectedTagIds: selected.map((item) => item.id).whereType<int>(),
          limit: siteConfigFor(
            siteUrl,
          ).maxTagSearchResults.clamp(1, TopicTagSearch.maximumResults),
        );
        final match = result.results
            .where(
              (item) =>
                  item.id == tag.id ||
                  item.name.toLowerCase() == tag.name.toLowerCase(),
            )
            .firstOrNull;
        if (!result.isForbidden && match != null && !match.disabled) {
          kept.add(match);
        }
      } catch (_) {
        // A failed validation lookup must not silently remove existing tags.
        return selected;
      }
    }
    return List.unmodifiable(kept);
  }

  void openTagsEdit() {
    final instance = currentInstance;
    final route = currentContent;
    final detail = currentTopic;
    if (instance == null ||
        route?.topicId == null ||
        detail?.canEditTags != true) {
      return;
    }
    unawaited(_ensureTopicComposerCapabilities(instance.url));
    if (!_replaceComposer()) return;
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: activeTabId,
      topicId: route!.topicId!,
      slug: route.slug ?? '',
      topicTitle: detail!.title,
      editingPostId: detail.stream.firstOrNull,
      editingPostNumber: 1,
      mode: ComposerMode.tagsEdit,
      initialCategoryId: detail.categoryId,
      initialTags: detail.tags,
    );
    _composer = ComposerController(
      target,
      minimumRequiredTags:
          categoryFor(
            detail.categoryId,
            siteUrl: instance.url,
          )?.minimumRequiredTags ??
          0,
    );
    _notify();
  }

  Future<String?> updateTopicTagsFromSidebar({
    required String siteUrl,
    required int topicId,
    required Iterable<TopicTag> tags,
  }) async {
    if (currentInstance?.url != siteUrl ||
        currentContent?.topicId != topicId ||
        currentTopic?.canEditTags != true) {
      return 'Topic tags can no longer be edited.';
    }
    final next = List<TopicTag>.unmodifiable(tags);
    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return 'The site changed before tags were saved.';
    if (credential.failure case final failure?) return failure.message;
    try {
      await api.topicMutations.updateTopicTags(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topicId,
        tags: next,
      );
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'topicSidebar.editTopicTags',
        );
      }
      return const WriteException(WriteFailure.unreachable).message;
    }
    if (!lease.isCurrent) return 'The site changed before tags were saved.';
    lease.commit(() {
      _applyTopicTags(siteUrl, topicId, next);
      _notify();
    });
    return null;
  }

  Future<void> _ensureTopicComposerCapabilities(String siteUrl) async {
    if (_topicComposerCapabilities.containsKey(siteUrl)) return;
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || credential.failure != null) return;
      final capabilities = await api.topicComposerQueries
          .topicComposerCapabilities(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
          );
      lease.commit(() {
        _topicComposerCapabilities[siteUrl] = capabilities;
        _notify();
      });
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.topicCapabilities',
          severity: DiagnosticSeverity.warning,
        );
      }
    }
  }

  ComposerSearch _composerSearch(ComposerTarget target) {
    if (siteConfigFor(target.siteUrl).emojiEnabled) {
      unawaited(ensureEmojiCatalog(target.siteUrl));
    }

    return (
      users: (term) async {
        final found = await searchUsers(
          siteUrl: target.siteUrl,
          topicId: target.isPlugin
              ? target.policy!.mentionTopicId
              : target.topicId,
          term: term,
        );
        return [
          for (final user in found)
            ComposerSuggestion(
              kind: ComposerTriggerKind.mention,
              value: user.username,
              label: user.username,
              detail: user.name,
              art: ArtAvatar(user.avatarUrl),
              siteUrl: target.siteUrl,
              userId: user.id,
              userStatus: user.status,
            ),
        ];
      },
      hashtags: (term) async {
        final found = await searchHashtags(siteUrl: target.siteUrl, term: term);
        return [
          for (final hashtag in found)
            ComposerSuggestion(
              kind: ComposerTriggerKind.hashtag,
              // The ref, not the slug: it is what the site cooks against, and
              // the only form that finds a subcategory or tells two things
              // that share a name apart.
              value: hashtag.ref,
              label: hashtag.text,
              detail: hashtag.secondaryText,
              art: _hashtagArt(target.siteUrl, hashtag),
            ),
        ];
      },
      emojis: (query) async {
        if (!siteConfigFor(target.siteUrl).emojiEnabled) return const [];
        final catalog = await ensureEmojiCatalog(target.siteUrl);
        if (catalog == null ||
            catalog.isEmpty ||
            !siteConfigFor(target.siteUrl).emojiEnabled) {
          return const [];
        }

        // Aliases are optional. Waiting for them gives the first query the
        // forum's active-locale vocabulary; a failed request leaves the
        // catalog's canonical-name search fully usable.
        await ensureEmojiSearchAliases(target.siteUrl);
        await emojiPickerStore.ensureLoaded(siteUrl: target.siteUrl);
        if (!siteConfigFor(target.siteUrl).emojiEnabled) return const [];
        final tone = emojiPickerStore.skinToneFor(siteUrl: target.siteUrl);
        final found = searchEmojis(target.siteUrl, query, limit: 5);
        return [
          for (final emoji in found)
            ComposerSuggestion(
              kind: ComposerTriggerKind.emoji,
              value: emoji.codeFor(tone),
              label: emoji.codeFor(tone),
              art: ArtImage(emoji.urlFor(tone)),
            ),
          ComposerSuggestion(
            kind: ComposerTriggerKind.emoji,
            value: query,
            label: 'More emoji',
            art: const ArtIcon('discourse-emojis'),
            action: ComposerSuggestionAction.openEmojiPicker,
          ),
        ];
      },
    );
  }

  Future<void> _loadEditBody(ComposerController composer, Post post) async {
    if (post.raw case final raw?) {
      composer.loadedBody(raw);
      return;
    }

    composer.beginLoadingBody();
    final target = composer.target;
    final lease = lifecycle.capture(target.siteUrl);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(target.siteUrl),
      );
      if (credential == null ||
          !lease.isCurrent ||
          !identical(_composer, composer)) {
        return;
      }
      final fetched = await api.topicContent.posts(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        ids: [post.id],
        includeRaw: true,
        apiKey: credential.value,
      );
      final raw = fetched.firstWhere((p) => p.id == post.id).raw;
      lease.commit(() {
        if (raw == null) {
          composer.bodyLoadFailed();
        } else {
          composer.loadedBody(raw);
        }
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(error, stackTrace, 'post.loadEditBody');
      lease.commit(composer.bodyLoadFailed);
    }
  }

  bool topicPostSelectionEnabled(String siteUrl, int topicId) =>
      _topicPostSelections.containsKey(_topicKey(siteUrl, topicId));

  Set<int> selectedTopicPostIds(String siteUrl, int topicId) =>
      Set.unmodifiable(
        _topicPostSelections[_topicKey(siteUrl, topicId)] ?? const <int>{},
      );

  List<Post> selectedTopicPosts(String siteUrl, int topicId) {
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    final selected = _topicPostSelections[_topicKey(siteUrl, topicId)];
    if (detail == null || selected == null || selected.isEmpty) return const [];
    return List.unmodifiable([
      for (final id in detail.stream)
        if (selected.contains(id)) ?store.read<Post>(siteUrl, id),
    ]);
  }

  bool topicPostSelectionWriteInFlight(String siteUrl, int topicId) =>
      _topicPostSelectionWrites.contains(_topicKey(siteUrl, topicId));

  void setTopicPostSelectionEnabled(String siteUrl, int topicId, bool enabled) {
    final key = _topicKey(siteUrl, topicId);
    if (enabled) {
      final topic = store.read<TopicDetail>(siteUrl, topicId);
      if (topic == null || !topic.canSelectPosts) return;
      if (_topicPostSelections.containsKey(key)) return;
      _topicPostSelections[key] = <int>{};
    } else {
      if (_topicPostSelectionWrites.contains(key) ||
          _topicPostSelections.remove(key) == null) {
        return;
      }
    }
    _notify();
  }

  void toggleTopicPostSelected(String siteUrl, int topicId, int postId) {
    final key = _topicKey(siteUrl, topicId);
    final selected = _topicPostSelections[key];
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (selected == null ||
        topic == null ||
        !topic.canSelectPosts ||
        _topicPostSelectionWrites.contains(key) ||
        !topic.stream.contains(postId) ||
        store.read<Post>(siteUrl, postId) == null) {
      return;
    }
    if (!selected.remove(postId)) selected.add(postId);
    _notify();
  }

  void selectAllLoadedTopicPosts(String siteUrl, int topicId) {
    final key = _topicKey(siteUrl, topicId);
    final selected = _topicPostSelections[key];
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (selected == null ||
        topic == null ||
        !topic.canSelectPosts ||
        _topicPostSelectionWrites.contains(key)) {
      return;
    }
    selected
      ..clear()
      ..addAll(
        topic.stream.where((id) => store.read<Post>(siteUrl, id) != null),
      );
    _notify();
  }

  void clearSelectedTopicPosts(String siteUrl, int topicId) {
    final key = _topicKey(siteUrl, topicId);
    final selected = _topicPostSelections[key];
    if (selected == null ||
        selected.isEmpty ||
        _topicPostSelectionWrites.contains(key)) {
      return;
    }
    selected.clear();
    _notify();
  }

  Future<String?> deleteSelectedTopicPosts(String siteUrl, int topicId) {
    final posts = selectedTopicPosts(siteUrl, topicId);
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (topic == null ||
        !topic.canSelectPosts ||
        posts.isEmpty ||
        posts.any((post) => !post.canDelete)) {
      return Future.value();
    }
    return _mutateSelectedTopicPosts(
      siteUrl,
      topicId,
      posts,
      (apiKey, ids) => api.postMutations.deletePosts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postIds: ids,
      ),
    );
  }

  Future<String?> mergeSelectedTopicPosts(String siteUrl, int topicId) {
    final posts = selectedTopicPosts(siteUrl, topicId);
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (topic == null ||
        !topic.canSelectPosts ||
        posts.length < 2 ||
        posts.any((post) => !post.canDelete) ||
        posts.map((post) => post.username).toSet().length != 1) {
      return Future.value();
    }
    return _mutateSelectedTopicPosts(
      siteUrl,
      topicId,
      posts,
      (apiKey, ids) => api.postMutations.mergePosts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postIds: ids,
      ),
    );
  }

  Future<TopicMoveDestinationSearchResult> searchTopicMoveDestinations(
    String siteUrl,
    int topicId,
    String term,
  ) async {
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    final trimmed = term.trim();
    if (topic == null || !topic.canMovePosts || trimmed.isEmpty) {
      return (destinations: const <TopicMoveDestination>[], error: null);
    }
    final lease = lifecycle.capture(siteUrl);
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) {
      return (destinations: const <TopicMoveDestination>[], error: null);
    }
    if (credential.failure case final failure?) {
      return (
        destinations: const <TopicMoveDestination>[],
        error: failure.message,
      );
    }
    try {
      final results = await api.search.searchPosts(
        siteUrl: siteUrl,
        term: trimmed,
        typeFilter: 'topic',
        searchForId: true,
        restrictToArchetype: 'regular',
        apiKey: credential.apiKey,
      );
      if (!lease.isCurrent) {
        return (destinations: const <TopicMoveDestination>[], error: null);
      }
      final seen = <int>{};
      return (
        destinations: List<TopicMoveDestination>.unmodifiable([
          for (final hit in results.hits)
            if (hit.topicId != topicId &&
                !hit.privateMessage &&
                seen.add(hit.topicId))
              (id: hit.topicId, title: hit.topicTitle, slug: hit.topicSlug),
        ]),
        error: results.error,
      );
    } on WriteException catch (error) {
      return (
        destinations: const <TopicMoveDestination>[],
        error: error.message,
      );
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.selectedPosts.searchDestination',
          severity: DiagnosticSeverity.warning,
        );
      }
      return (
        destinations: const <TopicMoveDestination>[],
        error: const WriteException(WriteFailure.unreachable).message,
      );
    }
  }

  Future<TopicPostMoveResult> moveSelectedTopicPostsToExisting(
    String siteUrl,
    int topicId,
    int destinationTopicId, {
    bool chronologicalOrder = false,
  }) async {
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    final posts = selectedTopicPosts(siteUrl, topicId);
    if (topic == null ||
        !topic.canMovePosts ||
        posts.isEmpty ||
        destinationTopicId <= 0 ||
        destinationTopicId == topicId) {
      return (
        destinationUrl: null,
        error: const WriteException(WriteFailure.forbidden).message,
      );
    }
    String? destinationUrl;
    final error = await _mutateSelectedTopicPosts(siteUrl, topicId, posts, (
      apiKey,
      ids,
    ) async {
      destinationUrl = await api.postMutations.movePosts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postIds: ids,
        destinationTopicId: destinationTopicId,
        chronologicalOrder: chronologicalOrder,
      );
    });
    return (
      destinationUrl: error == null ? destinationUrl : null,
      error: error,
    );
  }

  Future<TopicPostMoveResult> moveSelectedTopicPostsToNew(
    String siteUrl,
    int topicId, {
    required String title,
    int? categoryId,
    List<int> tagIds = const [],
  }) async {
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    final posts = selectedTopicPosts(siteUrl, topicId);
    final allSelected = topic != null && posts.length == topic.stream.length;
    if (topic == null ||
        !topic.canMovePosts ||
        posts.isEmpty ||
        allSelected ||
        posts.first.postType != Post.regularPostType ||
        title.trim().isEmpty) {
      return (
        destinationUrl: null,
        error: const WriteException(WriteFailure.forbidden).message,
      );
    }
    String? destinationUrl;
    final error = await _mutateSelectedTopicPosts(siteUrl, topicId, posts, (
      apiKey,
      ids,
    ) async {
      destinationUrl = await api.postMutations.movePosts(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postIds: ids,
        title: title,
        categoryId: categoryId,
        tagIds: tagIds,
      );
    });
    return (
      destinationUrl: error == null ? destinationUrl : null,
      error: error,
    );
  }

  bool canChangeSelectedTopicPostOwner(String siteUrl, int topicId) {
    if (currentInstance?.url != siteUrl ||
        currentInstance?.user?.canChangePostOwner != true) {
      return false;
    }
    final posts = selectedTopicPosts(siteUrl, topicId);
    return posts.isNotEmpty &&
        posts.map((post) => post.username).toSet().length == 1;
  }

  Future<String?> changeSelectedTopicPostOwner(
    String siteUrl,
    int topicId,
    String username,
  ) {
    final posts = selectedTopicPosts(siteUrl, topicId);
    final trimmedUsername = username.trim();
    if (!canChangeSelectedTopicPostOwner(siteUrl, topicId) ||
        trimmedUsername.isEmpty ||
        posts.first.username == trimmedUsername) {
      return Future.value(const WriteException(WriteFailure.forbidden).message);
    }
    return _mutateSelectedTopicPosts(
      siteUrl,
      topicId,
      posts,
      (apiKey, ids) => api.postMutations.changePostOwners(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postIds: ids,
        username: trimmedUsername,
      ),
    );
  }

  bool canChangeTopicPostOwner(Post post) {
    final topic = currentTopic;
    return currentInstance?.user?.canChangePostOwner == true &&
        topic != null &&
        topic.stream.contains(post.id);
  }

  Future<String?> changeTopicPostOwner(Post post, String username) {
    final topic = currentTopic;
    final trimmedUsername = username.trim();
    if (!canChangeTopicPostOwner(post) ||
        topic == null ||
        trimmedUsername.isEmpty ||
        trimmedUsername == post.username) {
      return Future.value(const WriteException(WriteFailure.forbidden).message);
    }
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.changePostOwners(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topic.id,
        postIds: [post.id],
        username: trimmedUsername,
      ),
    );
  }

  Future<String?> deletePost(Post post) async {
    if (!post.canDelete) return null;
    final siteUrl = currentInstance?.url;
    if (siteUrl != null &&
        _postWritesInFlight.contains(_postKey(siteUrl, post.id))) {
      return null;
    }
    final editing = _composer?.target.editingPostId == post.id
        ? _composer
        : null;

    final error = await _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.deletePost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
      ),
    );

    if (error == null && identical(_composer, editing)) {
      closeComposer();
    }
    return error;
  }

  bool canPermanentlyDeletePost(Post post) {
    final topic = currentTopic;
    return post.isDeleted &&
        topic != null &&
        topic.stream.contains(post.id) &&
        (post.postNumber == 1
            ? topic.deletedAt != null && topic.canPermanentlyDelete
            : post.canPermanentlyDelete);
  }

  Future<String?> checkPermanentPostDeletion(Post post) async {
    if (!canPermanentlyDeletePost(post)) {
      return 'This post cannot be permanently deleted.';
    }
    final instance = currentInstance;
    if (instance == null) return 'This post can no longer be changed.';
    final lease = lifecycle.capture(instance.url);
    final credential = await _credentialForWrite(instance.url);
    if (!lease.isCurrent || isDisposed) {
      return 'Your connection changed. Reopen the action and try again.';
    }
    if (credential.failure case final failure?) return failure.message;
    try {
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) {
        return 'Your connection changed. Reopen the action and try again.';
      }
      final result = await api.postMutations.checkPermanentPostDeletion(
        siteUrl: instance.url,
        apiKey: credential.apiKey!,
        postId: post.id,
        clientId: clientId,
      );
      if (!lease.isCurrent || isDisposed) {
        return 'Your connection changed. Reopen the action and try again.';
      }
      return result.allowed
          ? null
          : result.reason ?? 'This post cannot be permanently deleted yet.';
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(
          error,
          stackTrace,
          'post.permanentDeletionCheck',
          severity: DiagnosticSeverity.warning,
        );
      }
      return const WriteException(WriteFailure.unreachable).message;
    }
  }

  Future<String?> permanentlyDeletePost(Post post) async {
    final topic = currentTopic;
    if (!canPermanentlyDeletePost(post) || topic == null) {
      return 'This post cannot be permanently deleted.';
    }
    if (post.postNumber != 1) {
      return _mutatePost(
        post,
        (siteUrl, apiKey) => api.postMutations.permanentlyDeletePost(
          siteUrl: siteUrl,
          apiKey: apiKey,
          topicId: topic.id,
          postId: post.id,
        ),
      );
    }

    final instance = currentInstance;
    if (instance == null) return 'This topic can no longer be changed.';
    final siteUrl = instance.url;
    final key = _topicKey(siteUrl, topic.id);
    if (!_topicDeletionWrites.add(key)) {
      return 'Another topic action is still finishing.';
    }
    final lease = lifecycle.capture(siteUrl);
    _notify();
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || isDisposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = await authenticator.clientId();
      if (!lease.isCurrent || isDisposed) return null;
      await api.topicMutations.permanentlyDeleteTopic(
        siteUrl: siteUrl,
        apiKey: credential.apiKey!,
        topicId: topic.id,
        clientId: clientId,
      );
      if (!lease.isCurrent || isDisposed) return null;
      lease.commit(() {
        for (final postId in topic.stream) {
          store.remove<Post>(siteUrl, postId);
        }
        store.remove<TopicDetail>(siteUrl, topic.id);
        store.remove<Topic>(siteUrl, topic.id);
        _notify();
      });
      if (currentContent?.topicId == topic.id) {
        handleBack(canReturnToSidebar: false);
      }
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent && !isDisposed) {
        _reportOperationalError(error, stackTrace, 'topic.permanentlyDelete');
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _topicDeletionWrites.remove(key);
      if (!isDisposed) _notify();
    }
  }

  Future<String?> recoverPost(Post post) async {
    if (!post.canRecover) return null;
    final siteUrl = currentInstance?.url;
    if (siteUrl != null &&
        _postWritesInFlight.contains(_postKey(siteUrl, post.id))) {
      return null;
    }
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.recoverPost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
      ),
    );
  }

  Future<String?> setPostWiki(Post post, bool wiki) {
    if (!post.canWiki || post.wiki == wiki) return Future.value();
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.updatePostWiki(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        wiki: wiki,
      ),
    );
  }

  bool canLockPost(Post post) =>
      currentInstance?.user?.staff == true && post.userId != null;

  Future<String?> setPostLocked(Post post, bool locked) {
    if (!canLockPost(post) || post.locked == locked) return Future.value();
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.updatePostLocked(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        locked: locked,
      ),
    );
  }

  bool canUnhidePost(Post post) =>
      currentInstance?.user?.staff == true && post.hidden;

  Future<String?> unhidePost(Post post) {
    if (!canUnhidePost(post)) return Future.value();
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.unhidePost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
      ),
    );
  }

  bool canTogglePostType(Post post) =>
      currentInstance?.user?.staff == true && !post.isWhisper;

  Future<String?> togglePostType(Post post) {
    if (!canTogglePostType(post)) return Future.value();
    final nextType = post.isModeratorAction
        ? Post.regularPostType
        : Post.moderatorPostType;
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.updatePostType(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        postType: nextType,
      ),
    );
  }

  bool canEditPostNotice(Post post) {
    final instance = currentInstance;
    final topic = currentTopic;
    return instance != null &&
        topic?.canEditStaffNotes == true &&
        topic!.stream.contains(post.id);
  }

  Future<String?> setPostNotice(Post post, String? notice) {
    if (!canEditPostNotice(post)) return Future.value();
    final trimmed = notice?.trim();
    final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
    if (next == post.notice?.raw) return Future.value();
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.postMutations.updatePostNotice(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        notice: next,
      ),
    );
  }

  Future<String?> createPostFlag(
    String siteUrl,
    Post post,
    PostFlagType flagType, {
    String? message,
  }) async {
    final instance = _instanceAt(siteUrl);
    final held = store.read<Post>(siteUrl, post.id);
    PostFlagType? currentType;
    for (final type in postFlagTypesFor(siteUrl)) {
      if (type.id == flagType.id) {
        currentType = type;
        break;
      }
    }
    if (instance?.isConnected != true) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    if (held == null ||
        held.hidden ||
        held.isDeleted ||
        held.actedFlagSummaries.isNotEmpty ||
        currentType == null ||
        !currentType.enabled ||
        !currentType.appliesToPost ||
        !held.canFlagWith(currentType.id)) {
      return 'This post can no longer be flagged.';
    }

    final submittedMessage = currentType.requireMessage ? message ?? '' : null;
    final length = submittedMessage?.length ?? 0;
    final minimum = siteConfigFor(siteUrl).minPersonalMessagePostLength;
    if (currentType.requireMessage &&
        (length < minimum || length > PostFlagType.maximumMessageLength)) {
      return 'Your message must be between $minimum and '
          '${PostFlagType.maximumMessageLength} characters.';
    }

    final key = _postKey(siteUrl, held.id);
    if (!_beginPostWrite(key)) {
      return 'Another action on this post is still being saved.';
    }
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return 'Your connection changed. Reopen the flag form and try again.';
      }
      if (credential.failure case final failure?) return failure.message;

      try {
        final fresh = await api.postMutations.createPostFlag(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          postId: held.id,
          postActionTypeId: currentType.id,
          message: submittedMessage,
        );
        if (!lease.isCurrent) {
          return 'Your connection changed. Reopen the flag form and try again.';
        }
        lease.commit(() {
          final current = store.read<Post>(siteUrl, fresh.id);
          store.put(
            siteUrl,
            current == null ? fresh : fresh.withBookmarkOf(current),
          );
          _notify();
        });
        return null;
      } on WriteException catch (error) {
        return error.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'post.flag');
        }
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      lease.commit(() => _endPostWrite(siteUrl, held.id));
    }
  }

  bool topicFlagWriteInFlight(String siteUrl, int topicId) =>
      _topicFlagWrites.contains(_topicKey(siteUrl, topicId));

  Future<String?> createTopicFlag(
    String siteUrl,
    TopicDetail topic,
    PostFlagType flagType, {
    String? message,
  }) async {
    final instance = _instanceAt(siteUrl);
    final held = store.read<TopicDetail>(siteUrl, topic.id);
    final currentType = _postActionCatalogs[siteUrl]?.topicFlags
        .where((type) => type.id == flagType.id)
        .firstOrNull;
    if (instance?.isConnected != true) {
      return const WriteException(WriteFailure.forbidden).message;
    }
    if (held == null ||
        currentType == null ||
        !currentType.enabled ||
        !currentType.appliesToTopic ||
        !held.canFlagWith(currentType.id)) {
      return 'This topic can no longer be flagged.';
    }

    final submittedMessage = currentType.requireMessage ? message ?? '' : null;
    final length = submittedMessage?.length ?? 0;
    final minimum = siteConfigFor(siteUrl).minPersonalMessagePostLength;
    if (currentType.requireMessage &&
        (length < minimum || length > PostFlagType.maximumMessageLength)) {
      return 'Your message must be between $minimum and '
          '${PostFlagType.maximumMessageLength} characters.';
    }

    final key = _topicKey(siteUrl, held.id);
    if (!_topicFlagWrites.add(key)) {
      return 'Another flag on this topic is still being saved.';
    }
    _notify();
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return 'Your connection changed. Reopen the flag form and try again.';
      }
      if (credential.failure case final failure?) return failure.message;

      try {
        await api.postMutations.createTopicFlag(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: held.id,
          postActionTypeId: currentType.id,
          message: submittedMessage,
        );
        if (!lease.isCurrent) {
          return 'Your connection changed. Reopen the flag form and try again.';
        }
        lease.commit(() {
          store.update<TopicDetail>(
            siteUrl,
            held.id,
            (current) => current.withTopicFlag(currentType.id),
          );
          _notify();
        });
        return null;
      } on WriteException catch (error) {
        return error.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'topic.flag');
        }
        return const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      lease.commit(() {
        _topicFlagWrites.remove(key);
        _notify();
      });
    }
  }

  Future<String?> toggleLike(Post post, {String? siteUrl}) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null || !post.canToggleLike) return null;

    final key = _postKey(targetSite, post.id);
    // One at a time per post. Without this a double tap sends a like and an
    // undo at once — the second reads the guess the first just wrote — and
    // whichever answer lands last decides what is drawn, which is not
    // necessarily the one the site ended up believing.
    if (!_beginPostWrite(key)) return null;
    final lease = lifecycle.capture(targetSite);

    try {
      return await _writeLike(targetSite, post, lease);
    } finally {
      lease.commit(() => _endPostWrite(targetSite, post.id));
    }
  }

  Future<String?> _writeLike(String siteUrl, Post post, SiteLease lease) async {
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return null;
    if (credential.failure case final failure?) return failure.message;
    final apiKey = credential.apiKey!;

    final liked = !post.liked;
    // Apply the guess to the current store value: a re-read can land during
    // credential lookup, and a 204 response will not correct a stale put.
    final applied = lease.commit(() {
      store.update<Post>(siteUrl, post.id, (held) => held.withLike(liked));
      _notify();
    });
    if (!applied) return null;

    void revert() {
      lease.commit(() {
        store.update<Post>(siteUrl, post.id, (held) => held.withLikesOf(post));
        _notify();
      });
    }

    try {
      final fresh = liked
          ? await api.postMutations.likePost(
              siteUrl: siteUrl,
              apiKey: apiKey,
              postId: post.id,
            )
          : await api.postMutations.unlikePost(
              siteUrl: siteUrl,
              apiKey: apiKey,
              postId: post.id,
            );
      // A route that answered with nothing still did the thing it was asked to
      // — the guess above stands until the post is read again.
      if (fresh != null) {
        lease.commit(() {
          final held = store.read<Post>(siteUrl, fresh.id);
          store.put(siteUrl, held == null ? fresh : fresh.withBookmarkOf(held));
          _notify();
        });
      }
    } on WriteException catch (e) {
      revert();
      return e.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'post.toggleLike');
      }
      revert();
      return const WriteException(WriteFailure.unreachable).message;
    }
    return null;
  }

  bool postWriteInFlight(int postId, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    return targetSite != null &&
        _postWritesInFlight.contains(_postKey(targetSite, postId));
  }

  final Set<String> _postWritesInFlight = {};
  final Map<String, Set<int>> _topicPostSelections = {};
  final Set<String> _topicPostSelectionWrites = {};
  final Set<String> _topicFlagWrites = {};

  final Set<String> _topicBookmarkWritesInFlight = {};
  final Set<String> _pluginBookmarkWritesInFlight = {};
  final Map<BookmarkTargetType, _ShellCoreBookmarkTargetHost>
  _coreBookmarkTargetHosts = {};
  final Map<BookmarkTargetType, _ShellPluginBookmarkTargetHost>
  _pluginBookmarkTargetHosts = {};
  final Map<String, int> _bookmarkVersions = {};
  final Map<String, int> _siteBookmarkVersions = {};

  @override
  BookmarkTargetHost bookmarkTarget(BookmarkTargetType targetType) {
    if (targetType != BookmarkTargetType.post &&
        targetType != BookmarkTargetType.topic) {
      throw ArgumentError.value(
        targetType,
        'targetType',
        'Plugin bookmark targets require a plugin-scoped host.',
      );
    }
    return _coreBookmarkTargetHosts.putIfAbsent(
      targetType,
      () => _ShellCoreBookmarkTargetHost(this, targetType),
    );
  }

  _ShellPluginBookmarkTargetHost _pluginBookmarkTargetHost(
    BookmarkTargetType targetType,
  ) => _pluginBookmarkTargetHosts.putIfAbsent(
    targetType,
    () => _ShellPluginBookmarkTargetHost(this, targetType),
  );

  int _bookmarkVersion(String siteUrl, int topicId) =>
      _bookmarkVersions[_topicKey(siteUrl, topicId)] ?? 0;

  int _siteBookmarkVersion(String siteUrl) =>
      _siteBookmarkVersions[siteUrl] ?? 0;

  void _advanceBookmarkVersion(String siteUrl, int topicId) {
    final key = _topicKey(siteUrl, topicId);
    _bookmarkVersions[key] = _bookmarkVersion(siteUrl, topicId) + 1;
    _siteBookmarkVersions[siteUrl] = _siteBookmarkVersion(siteUrl) + 1;
  }

  Topic _prepareTopicForStore(
    String siteUrl,
    Topic incoming,
    int? versionAtDispatch,
  ) {
    if (versionAtDispatch == null ||
        versionAtDispatch == _siteBookmarkVersion(siteUrl)) {
      return incoming;
    }
    final held = store.read<Topic>(siteUrl, incoming.id);
    final heldDetail = store.read<TopicDetail>(siteUrl, incoming.id);
    if (held == null && heldDetail == null) return incoming;
    return incoming.copyWith(
      bookmarked: held?.bookmarked ?? heldDetail?.hasBookmarks ?? false,
    );
  }

  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
  }) => _bookmarkWriteInFlight(
    siteUrl: siteUrl,
    context: _TopicBookmarkWriteContext(topicId),
    targetType: targetType,
    targetId: targetId,
  );

  bool _pluginBookmarkWriteInFlight({
    required String siteUrl,
    required BookmarkTargetType targetType,
    required int targetId,
  }) => _bookmarkWriteInFlight(
    siteUrl: siteUrl,
    context: _pluginBookmarkWriteContext,
    targetType: targetType,
    targetId: targetId,
  );

  bool _bookmarkWriteInFlight({
    required String siteUrl,
    required _BookmarkWriteContext context,
    required BookmarkTargetType targetType,
    required int targetId,
  }) {
    if (targetType == BookmarkTargetType.post) {
      return _postWritesInFlight.contains(_postKey(siteUrl, targetId));
    }
    if (targetType == BookmarkTargetType.topic) {
      if (context case _TopicBookmarkWriteContext(:final topicId)) {
        return _topicBookmarkWritesInFlight.contains(
          _topicKey(siteUrl, topicId),
        );
      }
      return false;
    }
    return _pluginBookmarkWritesInFlight.contains(
      _pluginBookmarkKey(siteUrl, targetType, targetId),
    );
  }

  PluginBookmarkTargetStrategy? _pluginBookmarkStrategy(
    BookmarkTargetType targetType,
  ) {
    PluginBookmarkTargetStrategy? owner;
    for (final candidate
        in _pluginSession.capabilities<PluginBookmarkTargetStrategy>()) {
      if (candidate.pluginBookmarkTarget != targetType) continue;
      if (owner != null) {
        throw StateError('Duplicate bookmark target ${targetType.id}.');
      }
      owner = candidate;
    }
    return owner;
  }

  BookmarkTargetType? _bookmarkTargetFor(Bookmark bookmark) {
    final core = bookmark.coreTargetType;
    if (core != null) return core;
    PluginBookmarkTargetStrategy? owner;
    for (final candidate
        in _pluginSession.capabilities<PluginBookmarkTargetStrategy>()) {
      if (candidate.pluginBookmarkTarget.wireName !=
          bookmark.bookmarkableType) {
        continue;
      }
      if (owner != null) {
        throw StateError(
          'Duplicate bookmark wire type ${bookmark.bookmarkableType}.',
        );
      }
      owner = candidate;
    }
    return owner?.pluginBookmarkTarget;
  }

  bool _bookmarkContextMatches(
    BookmarkTargetType targetType,
    _BookmarkWriteContext context,
  ) {
    final coreTarget =
        targetType == BookmarkTargetType.post ||
        targetType == BookmarkTargetType.topic;
    return switch (context) {
      _TopicBookmarkWriteContext(:final topicId) => coreTarget && topicId > 0,
      _PluginBookmarkWriteContext() => !coreTarget,
    };
  }

  final Map<String, Object> _postRefreshRequests = {};

  final Set<String> _postRefreshPending = {};

  final Map<String, int> _postRefreshTopics = {};

  bool _beginPostWrite(String key) {
    if (!_postWritesInFlight.add(key)) return false;
    // A live invalidation may already be reading the pre-write snapshot. It
    // must not land over the optimistic write or the write's own re-read.
    if (_postRefreshRequests.remove(key) != null) {
      _postRefreshPending.add(key);
    }
    _notify();
    return true;
  }

  void _endPostWrite(String siteUrl, int postId) {
    final key = _postKey(siteUrl, postId);
    _postWritesInFlight.remove(key);
    _notify();
    if (!_postRefreshPending.remove(key)) return;
    final topicId = _postRefreshTopics.remove(key);
    if (topicId != null) {
      unawaited(_refreshPosts(siteUrl, topicId, {postId}));
    }
  }

  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _createBookmark(
    siteUrl: siteUrl,
    context: _TopicBookmarkWriteContext(topicId),
    targetType: targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  Future<BookmarkWriteResult> _createBookmark({
    required String siteUrl,
    required _BookmarkWriteContext context,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) async {
    final instance = _instanceAt(siteUrl);
    final refreshTarget = targetType.refreshLabel;
    if (instance == null || !instance.isConnected) {
      return const BookmarkWriteResult.refused(
        'Reconnect to this forum to bookmark it.',
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return const BookmarkWriteResult.refused(
        'This bookmark target requires its owning context.',
      );
    }
    if (targetType != BookmarkTargetType.post &&
        targetType != BookmarkTargetType.topic &&
        _pluginBookmarkStrategy(targetType) == null) {
      return const BookmarkWriteResult.refused(
        'This bookmark target is not available in this build.',
      );
    }
    if (!_beginBookmarkWrite(siteUrl, context, targetType, targetId)) {
      return const BookmarkWriteResult.refused(
        'Another action on this bookmark is still finishing.',
      );
    }
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return const BookmarkWriteResult.reconciled(
          'The forum changed before the bookmark finished.',
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      final preference =
          autoDeletePreference ??
          instance.user?.bookmarkAutoDeletePreference ??
          BookmarkAutoDeletePreference.clearReminder;
      final int id;
      try {
        id = await api.bookmarks.createBookmark(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          targetType: targetType,
          targetId: targetId,
          name: name,
          reminderAt: reminderAt,
          autoDeletePreference: preference,
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            "Couldn't confirm whether the bookmark was created. The $refreshTarget is being refreshed.",
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.create');
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          "Couldn't confirm whether the bookmark was created. The $refreshTarget is being refreshed.",
        );
      }
      final postNumber = targetType == BookmarkTargetType.post
          ? store.read<Post>(siteUrl, targetId)?.postNumber
          : null;
      final bookmark = Bookmark(
        id: id,
        bookmarkableId: targetId,
        bookmarkableType: targetType.wireName,
        postNumber: postNumber,
        name: name,
        reminderAt: reminderAt?.toUtc(),
        autoDeletePreference: preference,
      );
      final applied = lease.commit(() {
        _applyBookmark(siteUrl, context, bookmark);
      });
      if (!applied) {
        return const BookmarkWriteResult.reconciled(
          'The bookmark was saved on the forum.',
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        targetType: targetType,
        targetId: targetId,
      );
      return BookmarkWriteResult.saved(bookmark);
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, context, targetType, targetId),
      );
    }
  }

  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) => _updateBookmark(
    siteUrl: siteUrl,
    context: _TopicBookmarkWriteContext(topicId),
    bookmark: bookmark,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  Future<BookmarkWriteResult> _updateBookmark({
    required String siteUrl,
    required _BookmarkWriteContext context,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) async {
    final instance = _instanceAt(siteUrl);
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    if (instance == null ||
        !instance.isConnected ||
        targetType == null ||
        targetId == null) {
      return const BookmarkWriteResult.refused(
        'This bookmark cannot be edited here.',
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return const BookmarkWriteResult.refused(
        'This bookmark target requires its owning context.',
      );
    }
    final refreshTarget = targetType.refreshLabel;
    if (!_beginBookmarkWrite(siteUrl, context, targetType, targetId)) {
      return const BookmarkWriteResult.refused(
        'Another action on this bookmark is still finishing.',
      );
    }
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return const BookmarkWriteResult.reconciled(
          'The forum changed before the bookmark finished.',
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      try {
        await api.bookmarks.updateBookmark(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          bookmarkId: bookmark.id,
          name: name,
          reminderAt: reminderAt,
          autoDeletePreference: autoDeletePreference,
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            "Couldn't confirm the bookmark changes. The $refreshTarget is being refreshed.",
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.update');
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          "Couldn't confirm the bookmark changes. The $refreshTarget is being refreshed.",
        );
      }
      final updated = bookmark.copyWith(
        name: name,
        clearName: name == null,
        reminderAt: reminderAt?.toUtc(),
        clearReminder: reminderAt == null,
        autoDeletePreference: autoDeletePreference,
      );
      final applied = lease.commit(() {
        _applyBookmark(siteUrl, context, updated);
      });
      if (!applied) {
        return const BookmarkWriteResult.reconciled(
          'The bookmark was updated on the forum.',
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        targetType: targetType,
        targetId: targetId,
      );
      return BookmarkWriteResult.saved(updated);
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, context, targetType, targetId),
      );
    }
  }

  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) => updateBookmark(
    siteUrl: siteUrl,
    topicId: topicId,
    bookmark: bookmark,
    name: bookmark.name,
    autoDeletePreference: bookmark.autoDeletePreference,
  );

  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) => _deleteBookmark(
    siteUrl: siteUrl,
    context: _TopicBookmarkWriteContext(topicId),
    bookmark: bookmark,
  );

  Future<BookmarkWriteResult> _deleteBookmark({
    required String siteUrl,
    required _BookmarkWriteContext context,
    required Bookmark bookmark,
  }) async {
    final instance = _instanceAt(siteUrl);
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    if (instance == null ||
        !instance.isConnected ||
        targetType == null ||
        targetId == null) {
      return const BookmarkWriteResult.refused(
        'This bookmark cannot be deleted here.',
      );
    }
    if (!_bookmarkContextMatches(targetType, context)) {
      return const BookmarkWriteResult.refused(
        'This bookmark target requires its owning context.',
      );
    }
    final refreshTarget = targetType.refreshLabel;
    if (!_beginBookmarkWrite(siteUrl, context, targetType, targetId)) {
      return const BookmarkWriteResult.refused(
        'Another action on this bookmark is still finishing.',
      );
    }
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return const BookmarkWriteResult.reconciled(
          'The forum changed before the bookmark finished.',
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      final bool? topicBookmarked;
      try {
        topicBookmarked = await api.bookmarks.deleteBookmark(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          bookmarkId: bookmark.id,
          targetType: targetType,
        );
        if (targetType.updatesTopicBookmarkState && topicBookmarked == null) {
          throw const WriteException(WriteFailure.unreachable);
        }
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
          return BookmarkWriteResult.reconciled(
            "Couldn't confirm the deletion. The $refreshTarget is being refreshed.",
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.delete');
          _reconcileBookmarks(
            instance,
            context,
            targetType: targetType,
            targetId: targetId,
          );
        }
        return BookmarkWriteResult.reconciled(
          "Couldn't confirm the deletion. The $refreshTarget is being refreshed.",
        );
      }
      final applied = lease.commit(() {
        _removeBookmark(
          siteUrl,
          context,
          bookmark,
          topicBookmarked: topicBookmarked,
        );
      });
      if (!applied) {
        return const BookmarkWriteResult.reconciled(
          'The bookmark was deleted on the forum.',
        );
      }
      _reconcileBookmarks(
        instance,
        context,
        targetType: targetType,
        targetId: targetId,
      );
      return const BookmarkWriteResult.saved();
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, context, targetType, targetId),
      );
    }
  }

  @override
  Future<BookmarkWriteResult> deleteAllTopicBookmarks({
    required String siteUrl,
    required int topicId,
  }) async {
    final context = _TopicBookmarkWriteContext(topicId);
    final instance = _instanceAt(siteUrl);
    if (instance == null || !instance.isConnected) {
      return const BookmarkWriteResult.refused(
        'Reconnect to this forum to delete its bookmarks.',
      );
    }
    final key = _topicKey(siteUrl, topicId);
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    final postIds =
        detail?.postBookmarks
            .map((bookmark) => bookmark.bookmarkableId)
            .whereType<int>()
            .toSet() ??
        const <int>{};
    final postKeys = {for (final postId in postIds) _postKey(siteUrl, postId)};
    if (_topicBookmarkWritesInFlight.contains(key) ||
        postKeys.any(_postWritesInFlight.contains)) {
      return const BookmarkWriteResult.refused(
        'Another bookmark action is still finishing.',
      );
    }
    _topicBookmarkWritesInFlight.add(key);
    _postWritesInFlight.addAll(postKeys);
    _notify();
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) {
        return const BookmarkWriteResult.reconciled(
          'The forum changed before the bookmarks were deleted.',
        );
      }
      if (credential.failure case final failure?) {
        return BookmarkWriteResult.refused(failure.message);
      }
      try {
        await api.bookmarks.deleteTopicBookmarks(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(instance, context);
          return const BookmarkWriteResult.reconciled(
            "Couldn't confirm the deletion. The topic is being refreshed.",
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.deleteAll');
          _reconcileBookmarks(instance, context);
        }
        return const BookmarkWriteResult.reconciled(
          "Couldn't confirm the deletion. The topic is being refreshed.",
        );
      }
      lease.commit(() => _removeAllBookmarks(siteUrl, topicId));
      _reconcileBookmarks(instance, context);
      return const BookmarkWriteResult.saved();
    } finally {
      lease.commit(() {
        _topicBookmarkWritesInFlight.remove(key);
        for (final postId in postIds) {
          _endPostWrite(siteUrl, postId);
        }
        _notify();
      });
    }
  }

  bool _beginBookmarkWrite(
    String siteUrl,
    _BookmarkWriteContext context,
    BookmarkTargetType targetType,
    int targetId,
  ) {
    if (targetType == BookmarkTargetType.post) {
      return _beginPostWrite(_postKey(siteUrl, targetId));
    }
    if (targetType == BookmarkTargetType.topic) {
      final topicId = (context as _TopicBookmarkWriteContext).topicId;
      return _beginTopicBookmarkWrite(_topicKey(siteUrl, topicId));
    }
    final key = _pluginBookmarkKey(siteUrl, targetType, targetId);
    if (!_pluginBookmarkWritesInFlight.add(key)) return false;
    _notify();
    return true;
  }

  bool _beginTopicBookmarkWrite(String key) {
    if (!_topicBookmarkWritesInFlight.add(key)) return false;
    _notify();
    return true;
  }

  void _endBookmarkWrite(
    String siteUrl,
    _BookmarkWriteContext context,
    BookmarkTargetType targetType,
    int targetId,
  ) {
    if (targetType == BookmarkTargetType.post) {
      _endPostWrite(siteUrl, targetId);
      return;
    }
    if (targetType == BookmarkTargetType.topic) {
      final topicId = (context as _TopicBookmarkWriteContext).topicId;
      _topicBookmarkWritesInFlight.remove(_topicKey(siteUrl, topicId));
      _notify();
      return;
    }
    _pluginBookmarkWritesInFlight.remove(
      _pluginBookmarkKey(siteUrl, targetType, targetId),
    );
    _notify();
  }

  void _applyBookmark(
    String siteUrl,
    _BookmarkWriteContext context,
    Bookmark bookmark,
  ) {
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    final plugin = targetType == null
        ? null
        : _pluginBookmarkStrategy(targetType);
    if (plugin != null) {
      if (targetId != null) {
        plugin.putPluginBookmark(siteUrl, targetId, bookmark);
      }
      _notify();
      return;
    }
    final topicId = (context as _TopicBookmarkWriteContext).topicId;
    _advanceBookmarkVersion(siteUrl, topicId);
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (detail) => detail.withBookmark(bookmark),
    );
    final postId = bookmark.bookmarkableId;
    if (targetType == BookmarkTargetType.post && postId != null) {
      store.update<Post>(
        siteUrl,
        postId,
        (post) => post.withBookmark(bookmark),
      );
    }
    store.update<Topic>(
      siteUrl,
      topicId,
      (topic) => topic.copyWith(bookmarked: true),
    );
    _notify();
  }

  void _removeBookmark(
    String siteUrl,
    _BookmarkWriteContext context,
    Bookmark bookmark, {
    required bool? topicBookmarked,
  }) {
    final targetType = _bookmarkTargetFor(bookmark);
    final targetId = bookmark.bookmarkableId;
    final plugin = targetType == null
        ? null
        : _pluginBookmarkStrategy(targetType);
    if (plugin != null) {
      if (targetId != null) plugin.removePluginBookmark(siteUrl, targetId);
      _notify();
      return;
    }
    final topicId = (context as _TopicBookmarkWriteContext).topicId;
    _advanceBookmarkVersion(siteUrl, topicId);
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (detail) => detail.withoutBookmark(bookmark.id),
    );
    final postId = bookmark.bookmarkableId;
    if (targetType == BookmarkTargetType.post && postId != null) {
      store.update<Post>(siteUrl, postId, (post) => post.withBookmark(null));
    }
    store.update<Topic>(
      siteUrl,
      topicId,
      (topic) => topic.copyWith(bookmarked: topicBookmarked == true),
    );
    _notify();
  }

  void _removeAllBookmarks(String siteUrl, int topicId) {
    _advanceBookmarkVersion(siteUrl, topicId);
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    if (detail != null) {
      for (final postId in detail.stream) {
        store.update<Post>(siteUrl, postId, (post) => post.withBookmark(null));
      }
      store.put(siteUrl, detail.withoutBookmarks());
    }
    store.update<Topic>(
      siteUrl,
      topicId,
      (topic) => topic.copyWith(bookmarked: false),
    );
    _notify();
  }

  void _reconcileBookmarks(
    DiscourseInstance instance,
    _BookmarkWriteContext context, {
    BookmarkTargetType targetType = BookmarkTargetType.topic,
    int? targetId,
  }) {
    final plugin = _pluginBookmarkStrategy(targetType);
    if (plugin != null && targetId != null) {
      _observePluginLifecycle(
        Future.sync(
          () => plugin.reconcilePluginBookmark(instance.url, targetId),
        ),
        'plugins.session.reconcileBookmark',
      );
    } else {
      final topicId = (context as _TopicBookmarkWriteContext).topicId;
      final route = currentContent;
      final row = store.read<Topic>(instance.url, topicId);
      unawaited(
        _refetchTopic(
          instance.url,
          topicId,
          route?.topicId == topicId ? route?.slug ?? '' : row?.slug ?? '',
        ),
      );
    }
    unawaited(accountActivity.loadBookmarks(instance, force: true));
  }

  static String _postKey(String siteUrl, int postId) => '$siteUrl~$postId';

  static String _pluginBookmarkKey(
    String siteUrl,
    BookmarkTargetType targetType,
    int targetId,
  ) => '$siteUrl~${targetType.id}~$targetId';

  final Set<String> _likersLoading = {};
  final Map<String, String> _likersErrors = {};

  PostLikers? likers(int postId, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return null;
    return store.read<PostLikers>(targetSite, postId);
  }

  String? likersError(int postId, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return null;
    return _likersErrors[_postKey(targetSite, postId)];
  }

  Future<void> loadLikers(int postId, {String? siteUrl}) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return;
    final instance = _instanceAt(targetSite);
    if (instance == null) return;

    final key = _postKey(targetSite, postId);
    if (!_likersLoading.add(key)) return;
    _likersErrors.remove(key);
    _notify();

    final lease = lifecycle.capture(targetSite);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(targetSite),
      );
      if (credential == null || !lease.isCurrent) return;
      final fetched = await api.topicContent.postLikers(
        siteUrl: targetSite,
        postId: postId,
        // Keep credential reads inside the guarded try: macOS entitlement
        // failures must not strand the key in [_likersLoading].
        apiKey: credential.value,
      );
      lease.commit(() => store.put(targetSite, fetched));
    } on SiteLookupException catch (e, stackTrace) {
      if (isDisposed || !lease.isCurrent || !_likersLoading.contains(key)) {
        return;
      }
      _reportOperationalError(
        e,
        stackTrace,
        'post.loadLikers',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        _likersErrors[key] = e.failure == SiteLookupFailure.notDiscourse
            ? "Couldn't see who liked this."
            : "Couldn't reach ${instance.host}.";
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent || !_likersLoading.contains(key)) {
        return;
      }
      _reportOperationalError(
        error,
        stackTrace,
        'post.loadLikers',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        _likersErrors[key] = "Couldn't load who liked this.";
      });
    } finally {
      lease.commit(() {
        _likersLoading.remove(key);
        _notify();
      });
    }
  }

  Future<PostRevision?> loadPostRevision({
    required String siteUrl,
    required int postId,
    int? revision,
  }) async {
    if (_instanceAt(siteUrl) == null) return null;
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return null;
      final fetched = await api.topicContent.postRevision(
        siteUrl: siteUrl,
        postId: postId,
        revision: revision,
        apiKey: credential.value,
      );
      return lease.isCurrent ? fetched : null;
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'post.loadRevision',
          severity: DiagnosticSeverity.warning,
        );
      }
      rethrow;
    }
  }

  Future<String?> _mutatePost(
    Post post,
    Future<void> Function(String siteUrl, String apiKey) write,
  ) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;

    final siteUrl = instance.url;
    final lease = lifecycle.capture(siteUrl);
    final key = _postKey(siteUrl, post.id);
    if (!_beginPostWrite(key)) return null;

    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      final apiKey = credential.apiKey!;

      try {
        await write(siteUrl, apiKey);
      } on WriteException catch (e) {
        return e.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'post.mutate');
        }
        return const WriteException(WriteFailure.unreachable).message;
      }

      if (!lease.isCurrent) return null;
      await _refreshPost(siteUrl, topicId, post.id, apiKey, lease);
      return null;
    } finally {
      lease.commit(() => _endPostWrite(siteUrl, post.id));
    }
  }

  Future<String?> _mutateSelectedTopicPosts(
    String siteUrl,
    int topicId,
    List<Post> posts,
    Future<void> Function(String apiKey, List<int> ids) write,
  ) async {
    final topicKey = _topicKey(siteUrl, topicId);
    final postKeys = [for (final post in posts) _postKey(siteUrl, post.id)];
    if (_topicPostSelectionWrites.contains(topicKey) ||
        postKeys.any(_postWritesInFlight.contains)) {
      return null;
    }
    final lease = lifecycle.capture(siteUrl);
    _topicPostSelectionWrites.add(topicKey);
    for (final key in postKeys) {
      _postWritesInFlight.add(key);
      if (_postRefreshRequests.remove(key) != null) {
        _postRefreshPending.add(key);
      }
    }
    _notify();

    var succeeded = false;
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent) return null;
      if (credential.failure case final failure?) return failure.message;
      final ids = List<int>.unmodifiable(posts.map((post) => post.id));
      try {
        await write(credential.apiKey!, ids);
      } on WriteException catch (error) {
        return error.message;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(
            error,
            stackTrace,
            'topic.selectedPosts.mutate',
          );
        }
        return const WriteException(WriteFailure.unreachable).message;
      }
      if (!lease.isCurrent) return null;
      await _refreshSelectedTopicPosts(
        siteUrl,
        topicId,
        ids,
        credential.apiKey,
        lease,
      );
      succeeded = true;
      return null;
    } finally {
      lease.commit(() {
        _topicPostSelectionWrites.remove(topicKey);
        if (succeeded) _topicPostSelections.remove(topicKey);
        for (final post in posts) {
          _endPostWrite(siteUrl, post.id);
        }
        _notify();
      });
    }
  }

  Future<void> _refreshSelectedTopicPosts(
    String siteUrl,
    int topicId,
    List<int> postIds,
    String? apiKey,
    SiteLease lease,
  ) async {
    final freshById = <int, Post>{};
    try {
      for (var start = 0; start < postIds.length; start += 20) {
        final end = start + 20 < postIds.length ? start + 20 : postIds.length;
        final fetched = await api.topicContent.posts(
          siteUrl: siteUrl,
          topicId: topicId,
          ids: postIds.sublist(start, end),
          apiKey: apiKey,
        );
        for (final post in fetched) {
          if (postIds.contains(post.id)) freshById[post.id] = post;
        }
      }
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'topic.selectedPosts.refreshAfterWrite',
          severity: DiagnosticSeverity.warning,
        );
      }
      return;
    }

    lease.commit(() {
      for (final postId in postIds) {
        final fresh = freshById[postId];
        if (fresh == null) {
          store.remove<Post>(siteUrl, postId);
          store.update<TopicDetail>(
            siteUrl,
            topicId,
            (detail) => detail.withoutPostId(postId),
          );
        } else {
          store.put(siteUrl, fresh);
          store.update<TopicDetail>(
            siteUrl,
            topicId,
            (detail) => detail.withPostId(postId),
          );
        }
      }
      _notify();
    });
  }

  Future<void> _refreshPost(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    SiteLease lease,
  ) async {
    List<Post> fetched;
    try {
      fetched = await api.topicContent.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: [postId],
        apiKey: apiKey,
      );
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'post.refreshAfterWrite',
          severity: DiagnosticSeverity.warning,
        );
      }
      return;
    }

    lease.commit(() {
      final fresh = fetched.where((p) => p.id == postId).firstOrNull;
      if (fresh == null) {
        store.remove<Post>(siteUrl, postId);
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (detail) => detail.withoutPostId(postId),
        );
      } else {
        store.put(siteUrl, fresh);
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (detail) => detail.withPostId(postId),
        );
      }
      _notify();
    });
  }

  bool _replaceComposer() {
    final existing = _composer;
    if (existing == null) return true;
    if (existing.discarding) return false;
    _composerDrafts.retire(existing);
    existing.dispose();
    _composer = null;
    _composerDrafts.detach(existing);
    return true;
  }

  void closeComposer() {
    final composer = _composer;
    if (composer == null || composer.discarding) return;
    _composerDrafts.retire(composer);
    composer.dispose();
    _composer = null;
    _composerDrafts.detach(composer);
    _notify();
  }

  Future<bool> finishComposerDraftRestore(ComposerController composer) =>
      _composerDrafts.finishRestore(composer);

  Future<String?> discardComposer(ComposerController composer) =>
      _composerDrafts.discard(composer);

  Future<ComposerUploadResult> _uploadComposerImage(
    ComposerTarget target,
    ComposerUploadFile file, {
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
  }) async {
    final credential = await _credentialForWrite(target.siteUrl);
    if (credential.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    return api.composerPersistence.uploadComposerImage(
      siteUrl: target.siteUrl,
      apiKey: credential.apiKey!,
      clientId: await authenticator.clientId(),
      file: file,
      onProgress: onProgress,
      abortTrigger: abortTrigger,
      uploadType: target.policy?.uploadType ?? ComposerUploadType.composer,
    );
  }

  Future<Map<String, String>> _resolveComposerUploadUrls(
    ComposerTarget target,
    Iterable<String> urls,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    final held = await _readSessionValue(
      lease,
      () => _credentialForWrite(target.siteUrl),
    );
    if (held == null) return const {};
    if (held.value.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    final identity = await _readSessionValue(lease, authenticator.clientId);
    if (identity == null || !lease.isCurrent) return const {};
    return api.composerPersistence.lookupUploadUrls(
      siteUrl: target.siteUrl,
      apiKey: held.value.apiKey!,
      clientId: identity.value,
      shortUrls: urls,
    );
  }

  Future<void> submitComposer() async {
    final composer = _composer;
    if (composer == null ||
        composer.discarding ||
        composer.submitting ||
        !composer.canSubmit) {
      return;
    }

    final target = composer.target;
    final raw = composer.raw;
    final lease = lifecycle.capture(target.siteUrl);

    if (target.isEdit) return _submitEdit(composer, target, raw);

    // Before any await: the credential round trip below is a gap a second tap
    // can pass through, and a create sent twice posts twice — unlike an edit,
    // nothing undoes that.
    composer.beginSubmit();
    await composer.finishDraftSaves();
    if (!lease.isCurrent) return;

    final credential = await _credentialForWrite(target.siteUrl);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    final apiKey = credential.apiKey!;
    final PostCreation creation;
    try {
      creation = target.createsTopic
          ? await api.composerPersistence.createTopic(
              siteUrl: target.siteUrl,
              apiKey: apiKey,
              title: composer.title.text.trim(),
              raw: raw,
              categoryId: composer.categoryId,
              tags: composer.tags,
              typingDuration: composer.typingDuration,
              composerOpenDuration: composer.openDuration,
              targetRecipients: target.targetRecipients,
              draftKey: target.draftKey,
            )
          : await api.composerPersistence.createPost(
              siteUrl: target.siteUrl,
              apiKey: apiKey,
              topicId: target.topicId,
              raw: raw,
              replyToPostNumber: target.replyToPostNumber,
              whisper: composer.whisper,
              typingDuration: composer.typingDuration,
              composerOpenDuration: composer.openDuration,
              draftKey: target.draftKey,
            );
    } on WriteException catch (e) {
      // A refusal is certain — the site answered and said no. Not reaching it
      // is not: the post may well have been created and only the answer lost.
      if (e.failure == WriteFailure.unreachable) {
        if (target.createsTopic) {
          await _reconcileNewTopic(target, composer, e, lease: lease);
        } else {
          await _reconcile(target, raw, composer, e, lease: lease);
        }
      } else {
        lease.commit(() => composer.failed(e));
      }
      return;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'composer.submit');
      }
      if (target.createsTopic) {
        await _reconcileNewTopic(
          target,
          composer,
          const WriteException(WriteFailure.unreachable),
          lease: lease,
        );
      } else {
        await _reconcile(
          target,
          raw,
          composer,
          const WriteException(WriteFailure.unreachable),
          lease: lease,
        );
      }
      return;
    }

    if (target.createsTopic) {
      lease.commit(
        () => _applyTopicCreation(target, creation, composer, lease),
      );
    } else {
      lease.commit(() => _applyCreation(target, creation, composer, lease));
    }
  }

  Future<void> _submitEdit(
    ComposerController composer,
    ComposerTarget target,
    String raw,
  ) async {
    if (target.isCategoryEdit) {
      return _submitCategoryEdit(composer, target);
    }
    if (target.isTagsEdit) {
      return _submitTagsEdit(composer, target);
    }
    final key = _postKey(target.siteUrl, target.editingPostId!);
    if (!_beginPostWrite(key)) {
      composer.failed(
        const WriteException(
          WriteFailure.conflict,
          errors: ['Another action on this post is still being saved.'],
        ),
      );
      return;
    }
    try {
      await _submitEditNow(composer, target, raw);
    } finally {
      _endPostWrite(target.siteUrl, target.editingPostId!);
    }
  }

  Future<void> _submitEditNow(
    ComposerController composer,
    ComposerTarget target,
    String raw,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    composer.beginSubmit();
    // A missing baseline means the body fetch failed. Never build a destructive
    // edit without the original text used for conflict detection.
    if (composer.originalRaw == null) {
      composer.failed(const WriteException(WriteFailure.unreachable));
      return;
    }
    final credential = await _credentialForWrite(target.siteUrl);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    final apiKey = credential.apiKey!;

    if (target.editsTopicMetadata && composer.metadataChanged) {
      try {
        await api.topicMutations.updateTopic(
          siteUrl: target.siteUrl,
          apiKey: apiKey,
          topicId: target.topicId,
          title: composer.title.text.trim(),
          originalTitle: composer.originalTitle,
          categoryId: composer.categoryId,
          tags: composer.tags,
          originalTags: composer.originalTags,
        );
      } on WriteException catch (e) {
        lease.commit(() => composer.failed(e));
        return;
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'composer.editTopic');
        }
        lease.commit(
          () => composer.failed(const WriteException(WriteFailure.unreachable)),
        );
        return;
      }
      lease.commit(() {
        final title = composer.title.text.trim();
        store.update<TopicDetail>(
          target.siteUrl,
          target.topicId,
          (detail) => detail.copyWith(
            title: title,
            categoryId: composer.categoryId,
            clearCategory: composer.categoryId == null,
            tags: composer.tags,
          ),
        );
        store.update<Topic>(
          target.siteUrl,
          target.topicId,
          (topic) => topic.copyWith(
            title: title,
            categoryId: composer.categoryId,
            clearCategory: composer.categoryId == null,
            tags: composer.tags,
          ),
        );
        _updateTopicRouteMetadata(
          target.siteUrl,
          target.topicId,
          title,
          composer.categoryId,
        );
        composer.metadataSettled();
      });
      if (raw == composer.originalRaw) {
        lease.commit(() => _closeSubmittedComposer(composer));
        return;
      }
    }

    final Post updated;
    try {
      updated = await api.composerPersistence.updatePost(
        siteUrl: target.siteUrl,
        apiKey: apiKey,
        postId: target.editingPostId!,
        raw: raw,
        originalText: composer.originalRaw,
      );
    } on WriteException catch (e) {
      lease.commit(() => composer.failed(e));
      return;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'composer.edit');
      }
      lease.commit(
        () => composer.failed(const WriteException(WriteFailure.unreachable)),
      );
      return;
    }

    // Edit responses omit reader-specific actions and plugin state; preserve
    // those values from the held post.
    lease.commit(() {
      final held = store.read<Post>(target.siteUrl, updated.id);
      store.put(
        target.siteUrl,
        held == null
            ? updated
            : updated
                  .withLikesOf(held)
                  .withPostActionsOf(held)
                  .withBookmarkOf(held)
                  .withPlugins(
                    api.models.mergeAfterPostEdit(
                      held: held.plugins,
                      incoming: updated.plugins,
                    ),
                  ),
      );

      _closeSubmittedComposer(composer);
    });
  }

  Future<void> _submitTagsEdit(
    ComposerController composer,
    ComposerTarget target,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    composer.beginSubmit();
    final credential = await _credentialForWrite(target.siteUrl);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    try {
      await api.topicMutations.updateTopicTags(
        siteUrl: target.siteUrl,
        apiKey: credential.apiKey!,
        topicId: target.topicId,
        tags: composer.tags,
      );
    } on WriteException catch (error) {
      lease.commit(() => composer.failed(error));
      return;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'composer.editTopicTags');
      }
      lease.commit(
        () => composer.failed(const WriteException(WriteFailure.unreachable)),
      );
      return;
    }
    lease.commit(() {
      _applyTopicTags(target.siteUrl, target.topicId, composer.tags);
      _closeSubmittedComposer(composer);
    });
  }

  void _applyTopicTags(String siteUrl, int topicId, List<TopicTag> tags) {
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (detail) => detail.copyWith(tags: tags),
    );
    store.update<Topic>(
      siteUrl,
      topicId,
      (topic) => topic.copyWith(tags: tags),
    );
  }

  Future<void> _submitCategoryEdit(
    ComposerController composer,
    ComposerTarget target,
  ) async {
    final lease = lifecycle.capture(target.siteUrl);
    composer.beginSubmit();
    final credential = await _credentialForWrite(target.siteUrl);
    if (!lease.isCurrent) return;
    if (credential.failure case final failure?) {
      lease.commit(() => composer.failed(failure));
      return;
    }
    try {
      await api.topicMutations.updateTopic(
        siteUrl: target.siteUrl,
        apiKey: credential.apiKey!,
        topicId: target.topicId,
        title: target.topicTitle,
        originalTitle: target.topicTitle,
        categoryId: composer.categoryId,
        tags: composer.tags,
        originalTags: composer.originalTags,
      );
    } on WriteException catch (error) {
      lease.commit(() => composer.failed(error));
      return;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.editTopicCategory',
        );
      }
      lease.commit(
        () => composer.failed(const WriteException(WriteFailure.unreachable)),
      );
      return;
    }
    lease.commit(() {
      store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) => detail.copyWith(
          categoryId: composer.categoryId,
          clearCategory: composer.categoryId == null,
          tags: composer.tags,
        ),
      );
      store.update<Topic>(
        target.siteUrl,
        target.topicId,
        (topic) => topic.copyWith(
          categoryId: composer.categoryId,
          clearCategory: composer.categoryId == null,
          tags: composer.tags,
        ),
      );
      _updateTopicRouteMetadata(
        target.siteUrl,
        target.topicId,
        target.topicTitle,
        composer.categoryId,
      );
      _closeSubmittedComposer(composer);
    });
  }

  void _closeSubmittedComposer(ComposerController composer) {
    if (identical(_composer, composer)) {
      composer.dispose();
      _composer = null;
    }
    _notify();
  }

  Future<void> recheckComposer() async {
    final composer = _composer;
    if (composer == null || !composer.canRecheck) return;
    if (composer.target.createsTopic) {
      await _reconcileNewTopic(
        composer.target,
        composer,
        const WriteException(WriteFailure.unreachable),
      );
    } else {
      await _reconcile(
        composer.target,
        composer.raw,
        composer,
        const WriteException(WriteFailure.unreachable),
      );
    }
  }

  static const int _reconcileWindow = 5;

  Future<void> _reconcileNewTopic(
    ComposerTarget target,
    ComposerController composer,
    WriteException failure, {
    SiteLease? lease,
  }) async {
    final session = lease ?? lifecycle.capture(target.siteUrl);
    if (!session.commit(composer.checking)) return;
    final credential = await _credentialForWrite(target.siteUrl);
    if (!session.isCurrent || credential.failure != null) {
      session.commit(composer.unresolved);
      return;
    }
    final apiKey = credential.apiKey!;

    try {
      final retained = await api.composerPersistence.draft(
        siteUrl: target.siteUrl,
        apiKey: apiKey,
        draftKey: target.draftKey,
      );
      if (!session.isCurrent) return;
      final draft = retained.draft;
      if (draft != null &&
          draft.title?.trim() == composer.title.text.trim() &&
          draft.reply.trim() == composer.raw) {
        session.commit(() => composer.checkedNotPosted(failure));
        return;
      }

      final username = _instanceAt(target.siteUrl)?.user?.username;
      if (username == null) {
        session.commit(composer.unresolved);
        return;
      }
      final recentPath = target.isPrivateMessage
          ? '/topics/private-messages-sent/${Uri.encodeComponent(username)}.json'
          : '/topics/created-by/${Uri.encodeComponent(username)}.json';
      final recent = await api.topicFeeds.topicList(
        siteUrl: target.siteUrl,
        path: recentPath,
        apiKey: apiKey,
      );
      final matches = <TopicPayload>[];
      for (final row
          in recent.topics
              .where((topic) => topic.title == composer.title.text.trim())
              .take(_reconcileWindow)) {
        final payload = await api.topicContent.topic(
          siteUrl: target.siteUrl,
          slug: row.slug,
          id: row.id,
          apiKey: apiKey,
        );
        final firstId = payload.detail.stream.firstOrNull;
        if (firstId == null) continue;
        final posts = await api.topicContent.posts(
          siteUrl: target.siteUrl,
          topicId: row.id,
          ids: [firstId],
          includeRaw: true,
          apiKey: apiKey,
        );
        if (posts.firstOrNull?.raw?.trim() == composer.raw) {
          matches.add(payload);
        }
      }
      if (!session.isCurrent) return;
      if (matches.length == 1) {
        final payload = matches.single;
        session.commit(() {
          _absorb(target.siteUrl, payload);
          _finishCreatedTopic(
            target,
            composer,
            session,
            payload.detail.id,
            recent.topics
                    .where((topic) => topic.id == payload.detail.id)
                    .firstOrNull
                    ?.slug ??
                '',
            payload.detail.title,
          );
        });
      } else {
        session.commit(composer.unresolved);
      }
    } catch (error, stackTrace) {
      if (session.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.reconcileTopic',
          severity: DiagnosticSeverity.warning,
        );
      }
      session.commit(composer.unresolved);
    }
  }

  Future<void> _reconcile(
    ComposerTarget target,
    String raw,
    ComposerController composer,
    WriteException failure, {
    SiteLease? lease,
  }) async {
    final session = lease ?? lifecycle.capture(target.siteUrl);
    if (!session.commit(composer.checking)) return;

    final username = _instanceAt(target.siteUrl)?.user?.username;
    final credential = await _credentialForWrite(target.siteUrl);
    if (!session.isCurrent) return;
    if (credential.failure != null) {
      session.commit(() {
        composer.unresolved();
        _notify();
      });
      return;
    }
    final apiKey = credential.apiKey;

    late TopicPayload topic;
    late List<Post> posts;
    Post? landed;
    try {
      topic = await api.topicContent.topic(
        siteUrl: target.siteUrl,
        slug: target.slug,
        id: target.topicId,
        apiKey: apiKey,
      );

      // Ours would be at the end, and a topic answers with its first chunk of
      // posts — so the tail has to be asked for by id.
      final stream = topic.detail.stream;
      final tail = stream.length <= _reconcileWindow
          ? stream
          : stream.sublist(stream.length - _reconcileWindow);

      posts = await api.topicContent.posts(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        ids: tail,
        includeRaw: true,
        apiKey: apiKey,
      );
      for (final post in posts) {
        if (post.username == username && post.raw?.trim() == raw) {
          landed = post;
          break;
        }
      }
    } catch (error, stackTrace) {
      if (session.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'composer.reconcile',
          severity: DiagnosticSeverity.warning,
        );
      }
      // Still unknown, and saying "it failed" would invite the second post
      // this whole path exists to prevent.
      session.commit(() {
        composer.unresolved();
        _notify();
      });
      return;
    }

    session.commit(() {
      _absorb(target.siteUrl, topic);
      store.putAll(target.siteUrl, posts);
      if (landed == null) {
        composer.checkedNotPosted(failure);
        _notify();
        return;
      }

      store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) => detail.withPostId(landed!.id),
      );
      if (identical(_composer, composer)) {
        composer.dispose();
        _composer = null;
      }
      _notify();
    });
  }

  DiscourseInstance? _instanceAt(String url) {
    for (final instance in _instances) {
      if (instance.url == url) return instance;
    }
    return null;
  }

  void _applyCreation(
    ComposerTarget target,
    PostCreation creation,
    ComposerController composer,
    SiteLease lease,
  ) {
    final post = creation.post;
    if (post != null) {
      store.put(target.siteUrl, post);
      store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) => detail.withPostId(post.id),
      );
    }

    // Accepting a post deletes its draft and advances the sequence server side,
    // so the local copy goes too and the next save uses the number it sent back
    // — keeping the old one earns a conflict on the very next keystroke.
    _composerDrafts.settleAfterSubmission(
      composer,
      lease,
      sequence: creation.draftSequence,
    );
    store.update<TopicDetail>(
      target.siteUrl,
      target.topicId,
      (detail) => detail.withDraft(null, _composerDrafts.sequenceFor(target)),
    );

    if (creation.isEnqueued) {
      composer.enqueued(creation.message);
      _notify();
      return;
    }

    if (identical(_composer, composer)) {
      composer.dispose();
      _composer = null;
    }
    _notify();

    // The appended post is what the author sees immediately; this repairs the
    // stream and the count, and picks up whatever landed while they typed.
    unawaited(_refetchTopic(target.siteUrl, target.topicId, target.slug));
  }

  void _applyTopicCreation(
    ComposerTarget target,
    PostCreation creation,
    ComposerController composer,
    SiteLease lease,
  ) {
    _composerDrafts.settleAfterSubmission(
      composer,
      lease,
      sequence: creation.draftSequence,
    );
    if (creation.isEnqueued) {
      composer.enqueued(creation.message);
      _notify();
      return;
    }
    final topicId = creation.topicId;
    if (topicId == null) {
      composer.failed(const WriteException(WriteFailure.unreachable));
      return;
    }
    if (creation.post case final post?) store.put(target.siteUrl, post);
    _finishCreatedTopic(
      target,
      composer,
      lease,
      topicId,
      creation.topicSlug ?? '',
      creation.topicTitle ?? composer.title.text.trim(),
    );
  }

  void _finishCreatedTopic(
    ComposerTarget target,
    ComposerController composer,
    SiteLease lease,
    int topicId,
    String slug,
    String title,
  ) {
    _composerDrafts.settleAfterSubmission(composer, lease);
    _closeSubmittedComposer(composer);
    final origin = target.originFeedId;
    if (currentInstance?.url == target.siteUrl) {
      _openTopic(topicId, slug, title);
      if (origin != null && target.isNewTopic) {
        unawaited(loadFeed(origin, force: true));
      }
    }
  }

  Future<void> _refetchTopic(
    String siteUrl,
    int topicId,
    String slug, {
    int? postNumber,
  }) async {
    final key = _topicKey(siteUrl, topicId);
    if (_topicsLoading.contains(key)) {
      // A live echo can start a read while an Assign write is still landing.
      // Remember the later invalidation so the pre-write snapshot cannot be
      // the last answer stored.
      _topicRefreshPending.add(key);
      if (postNumber != null) {
        _topicRefreshPostNumbers[key] = postNumber;
      }
      return;
    }
    final lease = lifecycle.capture(siteUrl);
    final bookmarkVersion = _bookmarkVersion(siteUrl, topicId);
    _topicsLoading.add(key);

    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return;
      final topic = await api.topicContent.topic(
        siteUrl: siteUrl,
        slug: slug,
        id: topicId,
        postNumber: postNumber,
        apiKey: credential.value,
      );
      lease.commit(
        () =>
            _absorb(siteUrl, topic, bookmarkVersionAtDispatch: bookmarkVersion),
      );
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      lease.commit(() => _topicsStale.add(key));
      _reportOperationalError(
        error,
        stackTrace,
        'topic.refetchAfterWrite',
        severity: DiagnosticSeverity.warning,
      );
    } finally {
      var replayRefresh = false;
      int? replayPostNumber;
      lease.commit(() {
        _topicsLoading.remove(key);
        replayRefresh = _topicRefreshPending.remove(key);
        if (replayRefresh) {
          replayPostNumber = _topicRefreshPostNumbers.remove(key);
        }
        _notify();
      });
      if (replayRefresh && lease.isCurrent) {
        unawaited(
          _refetchTopic(siteUrl, topicId, '', postNumber: replayPostNumber),
        );
      }
    }
  }

  final Set<String> _userCardsLoading = {};
  final Map<String, String> _userCardErrors = {};

  static String _userKey(String siteUrl, String username) =>
      '$siteUrl@${username.toLowerCase()}';

  UserCard? userCard(String username, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return null;
    return store.read<UserCard>(targetSite, username.toLowerCase());
  }

  String? userCardError(String username, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return null;
    return _userCardErrors[_userKey(targetSite, username)];
  }

  Future<void> loadUserCard(
    String username, {
    bool force = false,
    String? siteUrl,
  }) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null || username.isEmpty) return;
    final instance = _instanceAt(targetSite);
    if (instance == null) return;

    final key = _userKey(targetSite, username);
    if (_userCardsLoading.contains(key)) return;
    if (!force) {
      if (_userCardErrors.containsKey(key)) return;
      if (store.read<UserCard>(targetSite, username.toLowerCase()) != null) {
        return;
      }
    }

    _userCardsLoading.add(key);
    _userCardErrors.remove(key);
    _notify();

    final lease = lifecycle.capture(targetSite);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(targetSite),
      );
      if (credential == null || !lease.isCurrent) return;
      final card = await api.site.userCard(
        siteUrl: targetSite,
        username: username,
        // Read inside the guard, the way `loadLikers` does: storage that
        // throws would otherwise strand the key in [_userCardsLoading].
        apiKey: credential.value,
      );
      lease.commit(() => store.put(targetSite, card));
    } on SiteLookupException catch (e, stackTrace) {
      if (isDisposed || !lease.isCurrent || !_userCardsLoading.contains(key)) {
        return;
      }
      _reportOperationalError(
        e,
        stackTrace,
        'userCard.load',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        _userCardErrors[key] = e.failure == SiteLookupFailure.notDiscourse
            ? "Couldn't see that profile."
            : "Couldn't reach ${instance.host}.";
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent || !_userCardsLoading.contains(key)) {
        return;
      }
      _reportOperationalError(
        error,
        stackTrace,
        'userCard.load',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        _userCardErrors[key] = "Couldn't load @$username.";
      });
    } finally {
      lease.commit(() {
        _userCardsLoading.remove(key);
        _notify();
      });
    }
  }

  Future<void> loadMoreFeed(String destinationId) async {
    final instance = currentInstance;
    if (instance == null) return;
    await topicFeeds.loadMore(instance: instance, destinationId: destinationId);
  }

  SiteEmojiCatalog? emojiCatalogFor(String siteUrl) =>
      _presentation.emojiCatalogFor(siteUrl);

  Future<SiteEmojiCatalog?> ensureEmojiCatalog(String siteUrl) =>
      _presentation.ensureEmojiCatalog(siteUrl);

  Future<SiteEmojiCatalog?> refreshEmojiCatalog(String siteUrl) =>
      _presentation.refreshEmojiCatalog(siteUrl);

  Future<Map<String, List<String>>?> ensureEmojiSearchAliases(String siteUrl) =>
      _presentation.ensureEmojiSearchAliases(siteUrl);

  Future<Map<String, List<String>>?> refreshEmojiSearchAliases(
    String siteUrl,
  ) => _presentation.refreshEmojiSearchAliases(siteUrl);

  List<SiteEmoji> searchEmojis(String siteUrl, String query, {int limit = 7}) =>
      _presentation.searchEmojis(siteUrl, query, limit: limit);

  SuggestionArt _hashtagArt(String siteUrl, FoundHashtag hashtag) {
    final presentation = resolveHashtagPresentation(
      HashtagPresentationRequest(
        type: hashtag.type,
        style: HashtagStyle.parse(hashtag.styleType),
        icon: hashtag.icon,
        emoji: hashtag.emoji,
        colorValues: hashtag.colorValues,
      ),
      pluginPresentation: plugins.registry.pluginHashtagPresentation,
    );
    return hashtagSuggestionArt(
      presentation,
      resolveEmoji: (emoji) => emojiUrlFor(siteUrl, emoji),
    );
  }

  static const int composerIdentityCacheCapacity = 2048;

  final Map<String, BoundedLruCache<String, FoundHashtag?>> _hashtags = {};
  final Map<String, Set<String>> _hashtagsInFlight = {};

  final Map<String, BoundedLruCache<String, bool>> _mentioned = {};
  final Map<String, Set<String>> _mentionsInFlight = {};

  List<String> _composerHashtagTypes() {
    final types = <String>{
      ...defaultDiscourseHashtagOrder,
      ...plugins.registry.pluginHashtagWireTypes,
    };
    // The endpoint rejects the entire request above its fixed bound. Core
    // kinds stay first; installed registrations retain manifest order after
    // them. Servers without one of those data sources simply filter it out.
    return types
        .take(maximumDiscourseHashtagsPerRequest)
        .toList(growable: false);
  }

  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final List<FoundHashtag> found;
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null) return const [];
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !lease.isCurrent) return const [];
      found = await api.search.searchHashtags(
        siteUrl: siteUrl,
        term: term,
        order: _composerHashtagTypes(),
        apiKey: credential.value,
        clientId: identity.value,
      );
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'hashtags.search',
          severity: DiagnosticSeverity.warning,
        );
      }
      return const [];
    }

    // Everything offered is now known, so accepting a suggestion draws its
    // pill without a second round trip. This is the path almost every hashtag
    // in a post takes.
    final accepted = lease.commit(() {
      final known = _hashtags.putIfAbsent(
        siteUrl,
        () => BoundedLruCache(composerIdentityCacheCapacity),
      );
      for (final hashtag in found) {
        known.put(hashtag.ref, hashtag);
      }
    });
    return accepted ? found : const [];
  }

  ComposerPills _composerPills(ComposerTarget target) {
    final siteUrl = target.siteUrl;
    return (
      hashtag: (ref) => _hashtags[siteUrl]?.read(ref),
      mention: (username) => _mentioned[siteUrl]?.read(username),
      resolve: (refs, usernames) {
        unawaited(_resolveHashtags(siteUrl, refs));
        unawaited(
          _resolveMentions(
            siteUrl,
            target.isPlugin ? target.policy!.mentionTopicId : target.topicId,
            usernames,
          ),
        );
      },
    );
  }

  Future<void> _resolveHashtags(String siteUrl, Set<String> refs) async {
    final known = _hashtags.putIfAbsent(
      siteUrl,
      () => BoundedLruCache(composerIdentityCacheCapacity),
    );
    final inFlight = _hashtagsInFlight.putIfAbsent(siteUrl, () => {});

    final ask = [
      for (final ref in refs)
        if (!known.containsKey(ref) && inFlight.add(ref)) ref,
    ];
    if (ask.isEmpty) return;

    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null) return;
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !lease.isCurrent) return;
      final found = await api.lookups.lookupHashtags(
        siteUrl: siteUrl,
        refs: ask,
        order: _composerHashtagTypes(),
        apiKey: credential.value,
        clientId: identity.value,
      );
      if (isDisposed) return;
      lease.commit(() {
        for (final ref in ask) {
          known.put(ref, null);
        }
        for (final hashtag in found) {
          known.put(hashtag.ref, hashtag);
        }
        _composer?.text.artworkArrived();
      });
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent && ask.any(inFlight.contains)) {
        _reportOperationalError(
          error,
          stackTrace,
          'hashtags.resolve',
          severity: DiagnosticSeverity.warning,
        );
      }
    } finally {
      if (!isDisposed) lease.commit(() => inFlight.removeAll(ask));
    }
  }

  Future<void> _resolveMentions(
    String siteUrl,
    int? topicId,
    Set<String> usernames,
  ) async {
    final known = _mentioned.putIfAbsent(
      siteUrl,
      () => BoundedLruCache(composerIdentityCacheCapacity),
    );
    final inFlight = _mentionsInFlight.putIfAbsent(siteUrl, () => {});

    final ask = [
      for (final name in usernames)
        if (!known.containsKey(name) && inFlight.add(name)) name,
    ];
    if (ask.isEmpty) return;

    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null) return;
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !lease.isCurrent) return;
      final real = await api.lookups.checkMentions(
        siteUrl: siteUrl,
        names: ask,
        topicId: topicId,
        apiKey: credential.value,
        clientId: identity.value,
      );
      if (isDisposed) return;
      lease.commit(() {
        for (final name in ask) {
          known.put(name, real.contains(name));
        }
        _composer?.text.artworkArrived();
      });
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent && ask.any(inFlight.contains)) {
        _reportOperationalError(
          error,
          stackTrace,
          'mentions.resolve',
          severity: DiagnosticSeverity.warning,
        );
      }
    } finally {
      if (!isDisposed) lease.commit(() => inFlight.removeAll(ask));
    }
  }

  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required int? topicId,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final List<FoundUser> found;
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null) return const [];
      final identity = await _readSessionValue(lease, authenticator.clientId);
      if (identity == null || !lease.isCurrent) return const [];
      found = await api.lookups.searchUsers(
        siteUrl: siteUrl,
        term: term,
        topicId: topicId,
        apiKey: credential.value,
        clientId: identity.value,
      );
    } catch (error, stackTrace) {
      if (!isDisposed && lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'users.search',
          severity: DiagnosticSeverity.warning,
        );
      }
      return const [];
    }

    // The site just named these, so they exist — accepting one draws its pill
    // without asking again.
    final accepted = lease.commit(() {
      final known = _mentioned.putIfAbsent(
        siteUrl,
        () => BoundedLruCache(composerIdentityCacheCapacity),
      );
      for (final user in found) {
        known.put(user.username, true);
      }
    });
    return accepted ? found : const [];
  }

  String emojiUrlFor(String siteUrl, String name) =>
      _presentation.emojiUrlFor(siteUrl, name);

  bool knowsEmoji(String siteUrl, String name) =>
      _presentation.knowsEmoji(siteUrl, name);

  String? emojiNameFor(String siteUrl, String name) =>
      _presentation.emojiNameFor(siteUrl, name);

  Object presentationTokenFor(String siteUrl) =>
      _presentation.presentationTokenFor(siteUrl);

  SiteConfig siteConfigFor(String siteUrl) => _presentation.configFor(siteUrl);

  Future<SiteConfig?> resolveSiteConfig(String siteUrl) =>
      _presentation.resolveConfig(siteUrl);

  SiteConfig get currentSiteConfig {
    final instance = currentInstance;
    return instance == null
        ? const SiteConfig.unknown()
        : siteConfigFor(instance.url);
  }

  SiteAppearance? siteAppearanceFor(String siteUrl) =>
      _presentation.appearanceFor(siteUrl);

  SiteAppearance? get currentSiteAppearance {
    final instance = currentInstance;
    return instance == null ? null : siteAppearanceFor(instance.url);
  }

  Future<void> _persistSiteAppearance(
    String siteUrl,
    SiteAppearance appearance,
  ) async {
    final held = _instanceAt(siteUrl);
    if (held == null || held.appearance == appearance) return;
    _replaceInstance(held, held.copyWith(appearance: appearance));
    await instanceStore.save(List.of(_instances));
  }

  DiscourseUser? currentUserFor(String siteUrl) => _instanceAt(siteUrl)?.user;

  DiscourseUser? freshCurrentUserFor(String siteUrl) =>
      _sessionUsersRefreshed.contains(siteUrl)
      ? _instanceAt(siteUrl)?.user
      : null;

  ({bool valid, PluginData data}) _pluginDataForTarget(
    String siteUrl,
    PluginTarget target,
  ) {
    switch (target.kind) {
      case 'topic':
        if (target.id != target.topicId) {
          return (valid: false, data: PluginData.none);
        }
        final topic = store.read<TopicDetail>(siteUrl, target.id);
        return (valid: topic != null, data: topic?.plugins ?? PluginData.none);
      case 'post':
        final topic = store.read<TopicDetail>(siteUrl, target.topicId);
        if (topic == null || !topic.stream.contains(target.id)) {
          return (valid: false, data: PluginData.none);
        }
        final post = store.read<Post>(siteUrl, target.id);
        // Post #1 is represented by the topic target in Discourse write APIs.
        if (post == null || post.postNumber == 1) {
          return (valid: false, data: PluginData.none);
        }
        return (valid: true, data: post.plugins);
      default:
        return (valid: false, data: PluginData.none);
    }
  }

  Future<void> _persistSiteConfig(String siteUrl, SiteConfig config) async {
    if (currentInstance?.url == siteUrl) {
      search.selectSite(
        siteUrl,
        minimumLength: config.minSearchTermLength,
        logSearchQueries: config.logSearchQueries,
        taggingEnabled: config.taggingEnabled,
        usePgHeadlinesForExcerpt: config.usePgHeadlinesForExcerpt,
      );
    }
    if (!config.emojiEnabled && _composer?.target.siteUrl == siteUrl) {
      _composer?.closeEmojiAutocomplete();
    }
    if (_composer?.target.siteUrl == siteUrl) {
      _composer?.updateEnableAutoGridImages(config.enableAutoGridImages);
      _composer?.updateMarkdownLinkify(
        enabled: config.enableMarkdownLinkify,
        tlds: config.markdownLinkifyTlds,
      );
    }
    final held = _instanceAt(siteUrl);
    if (held == null) return;
    final persisted = plugins.models.preserveUnknownSiteSettings(
      held.config,
      config,
    );
    if (held.config == persisted) return;
    _replaceInstance(held, held.copyWith(config: persisted));
    await instanceStore.save(List.of(_instances));
  }

  Future<void> loadCategories(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await _ensureCategoriesFor(instance);
  }

  Future<void> loadTags(String siteUrl, {bool force = false}) async {
    final instance = _instanceAt(siteUrl);
    if (instance == null || (instance.loginRequired && !instance.isConnected)) {
      return;
    }
    if (!siteConfigFor(siteUrl).taggingEnabled) {
      final held = tagDirectoryFeedFor(siteUrl);
      if (!held.loaded || held.tags.isNotEmpty || held.error != null) {
        _tagDirectoryFeeds[siteUrl] = const TagDirectoryFeed(loaded: true);
        _notify();
      }
      return;
    }
    final held = tagDirectoryFeedFor(siteUrl);
    if (!force && held.loaded) return;
    if (_tagDirectoryRequests.containsKey(siteUrl)) return;
    final request = Object();
    _tagDirectoryRequests[siteUrl] = request;

    final lease = lifecycle.capture(siteUrl);
    _tagDirectoryFeeds[siteUrl] = held.refreshing();
    _notify();
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null || !lease.isCurrent) return;
      final identity = credential.value == null
          ? null
          : await _readSessionValue(lease, authenticator.clientId);
      if (credential.value != null && (identity == null || !lease.isCurrent)) {
        return;
      }
      final tags = await api.tags.tags(
        siteUrl: siteUrl,
        apiKey: credential.value,
        clientId: identity?.value,
      );
      final visibleTags = instance.user == null
          ? tags.where((tag) => !tag.pmOnly)
          : tags;
      lease.commit(() {
        _tagDirectoryFeeds[siteUrl] = held.withTags(visibleTags);
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'tags.load',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        _tagDirectoryFeeds[siteUrl] = held.withError(
          "Couldn't load tags from ${instance.host}.",
        );
        _notify();
      });
    } finally {
      if (identical(_tagDirectoryRequests[siteUrl], request)) {
        _tagDirectoryRequests.remove(siteUrl);
      }
    }
  }

  Future<void> _ensureCategoryIds(
    DiscourseInstance instance,
    String? apiKey,
    Iterable<int> categoryIds,
  ) async {
    if (instance.loginRequired && !instance.isConnected) return;
    final lease = lifecycle.capture(instance.url);
    String? clientId;
    try {
      if (apiKey != null) clientId = await authenticator.clientId();
      if (!lease.isCurrent) return;

      var pending = categoryIds.toSet();
      while (pending.isNotEmpty) {
        pending.removeWhere(
          (id) => store.read<TopicCategory>(instance.url, id) != null,
        );
        final batch = <int>[];
        for (final id in pending) {
          if (batch.length == 100) break;
          if (_categoryIdsLoading.add((instance.url, id))) batch.add(id);
        }
        if (batch.isEmpty) return;

        List<TopicCategory> found;
        try {
          found = await api.categories.findCategories(
            siteUrl: instance.url,
            ids: batch,
            apiKey: apiKey,
            clientId: clientId,
          );
        } finally {
          for (final id in batch) {
            _categoryIdsLoading.remove((instance.url, id));
          }
        }
        if (!lease.isCurrent) return;

        lease.commit(() {
          _mergeCategories(instance.url, found);
          _notify();
        });
        pending.removeAll(batch);
        pending.addAll([
          for (final category in found) ?category.parentCategoryId,
        ]);
      }
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.find',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  Future<void> _ensureCategoriesFor(DiscourseInstance instance) async {
    if (instance.loginRequired && !instance.isConnected) return;

    final lease = lifecycle.capture(instance.url);
    try {
      final apiKey = instance.isConnected
          ? await authenticator.apiKeyFor(instance.url)
          : null;
      if (!lease.isCurrent) return;
      final clientId = apiKey == null ? null : await authenticator.clientId();
      if (!lease.isCurrent) return;
      await _ensureCategories(
        instance,
        apiKey,
        clientId: clientId,
        lease: lease,
      );
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.readCredentials',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        final held = categoryFeedFor(instance.url);
        _categoryFeeds[instance.url] = held.withError(
          "Couldn't load categories from ${instance.host}.",
        );
        _notify();
      });
    }
  }

  Future<void> _ensureCategories(
    DiscourseInstance instance,
    String? apiKey, {
    String? clientId,
    SiteLease? lease,
  }) async {
    if (!_categorised.add(instance.url)) return;
    final session = lease ?? lifecycle.capture(instance.url);
    final existingFeed = categoryFeedFor(instance.url);
    _categoryFeeds[instance.url] = existingFeed.refreshing();
    _notify();

    try {
      final result = await api.categories.loadCategories(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
      );
      session.commit(() {
        _mergeCategories(instance.url, result.categories);

        final held = categoryFeedFor(instance.url);
        final roots = <int>{...result.rootCategoryIds, ...held.categoryIds};
        final nextPage = existingFeed.loaded && existingFeed.error == null
            ? held.nextPage
            : result.rootCategoryIds.isNotEmpty
            ? 2
            : null;
        _categoryFeeds[instance.url] = CategoryFeed(
          categoryIds: List.unmodifiable(roots),
          loaded: true,
          nextPage: nextPage,
          canCreateTopic: result.canCreateTopic,
        );
        if (result.postActionCatalog case final catalog?) {
          _postActionCatalogs[instance.url] = catalog;
        }
        if (result.siteTopTags case final tags?) {
          _siteTopTagsBySite[instance.url] = tags;
          _tagSidebarCache.remove(instance.url);
        }
        if (result.anonymousDefaultTags case final tags?) {
          _anonymousDefaultTagsBySite[instance.url] = tags;
          _tagSidebarCache.remove(instance.url);
        }
        if (!result.complete) _categorised.remove(instance.url);
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !session.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.load',
        severity: DiagnosticSeverity.warning,
      );
      session.commit(() {
        _categorised.remove(instance.url);
        final held = categoryFeedFor(instance.url);
        _categoryFeeds[instance.url] = held.withError(
          "Couldn't load categories from ${instance.host}.",
        );
        _notify();
      });
    }
  }

  void _mergeCategories(String siteUrl, Iterable<TopicCategory> incoming) {
    final stored = store.putAll(siteUrl, incoming);
    final byId = <int, TopicCategory>{
      for (final category
          in _categoriesBySite[siteUrl] ?? const <TopicCategory>[])
        category.id: category,
      for (final category in stored) category.id: category,
    };
    _categoriesBySite[siteUrl] = List.unmodifiable(byId.values);
    _categorySidebarCache.remove(siteUrl);
  }

  final Map<String, Object> _categoryPageRequests = {};

  Future<void> loadMoreCategories(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    final feed = categoryFeedFor(siteUrl);
    final page = feed.nextPage;
    if (instance == null || page == null || feed.loadingMore) return;
    if (_categoryPageRequests.containsKey(siteUrl)) return;

    final lease = lifecycle.capture(siteUrl);
    final request = Object();
    _categoryPageRequests[siteUrl] = request;
    _categoryFeeds[siteUrl] = feed.loadingNextPage();
    _notify();

    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_categoryPageRequests[siteUrl], request);

    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(siteUrl),
      );
      if (credential == null || !requestIsCurrent()) return;
      final identity = credential.value == null
          ? null
          : await _readSessionValue(lease, authenticator.clientId);
      if (credential.value != null &&
          (identity == null || !requestIsCurrent())) {
        return;
      }

      final result = await api.categories.loadCategories(
        siteUrl: siteUrl,
        apiKey: credential.value,
        clientId: identity?.value,
        page: page,
      );
      if (!requestIsCurrent()) return;

      lease.commit(() {
        if (!identical(_categoryPageRequests[siteUrl], request)) return;
        _categoryPageRequests.remove(siteUrl);
        _mergeCategories(siteUrl, result.categories);
        final held = categoryFeedFor(siteUrl);
        _categoryFeeds[siteUrl] = held.withPage(
          result.rootCategoryIds,
          hasMore: result.rootCategoryIds.isNotEmpty,
        );
        _notify();
      });
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.loadMore',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        if (!identical(_categoryPageRequests[siteUrl], request)) return;
        _categoryPageRequests.remove(siteUrl);
        final held = categoryFeedFor(siteUrl);
        _categoryFeeds[siteUrl] = held.withError(
          "Couldn't load more categories from ${instance.host}.",
          page: true,
        );
        _notify();
      });
    }
  }

  Future<void> connectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null || _connectingSiteUrl != null) return;

    _connectingSiteUrl = instance.url;
    _connectErrors.remove(instance.url);
    _notify();

    try {
      final result = await _accountSessions.connect(instance.url);
      switch (result.outcome) {
        case AccountConnectionOutcome.connected:
          _connectErrors.remove(instance.url);
          final connected = result.instance!;
          unawaited(_refreshOne(connected));
          unawaited(
            _refreshCustomSidebarSections(instance.url, result.apiKey!),
          );
        case AccountConnectionOutcome.cancelled:
          _connectErrors.remove(instance.url);
        case AccountConnectionOutcome.failed:
          _connectErrors[instance.url] = result.message!;
          if (result.refreshSignedOutPresentation &&
              currentInstance?.url == instance.url) {
            unawaited(_presentation.ensureAppearance(instance.url));
          }
        case AccountConnectionOutcome.stale || AccountConnectionOutcome.missing:
          break;
      }
    } finally {
      if (_connectingSiteUrl == instance.url) _connectingSiteUrl = null;
      final held = _instanceAt(instance.url);
      if (held?.isConnected == true &&
          !_sessionUsersRefreshed.contains(instance.url)) {
        // A cancelled/failed handshake leaves the previous account in place.
        // Retry a background refresh that deliberately stood aside above.
        unawaited(_refreshSessionUserFor(held!));
      }
      _notify();
    }
  }

  Future<void> disconnectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null) return;

    await disconnectInstance(instance.url);
  }

  Future<bool> disconnectInstance(String siteUrl) async {
    final result = await _accountSessions.disconnect(siteUrl);
    return result.outcome == AccountDisconnectionOutcome.disconnected;
  }

  @override
  bool get accountSessionDisposed => isDisposed;

  @override
  List<DiscourseInstance> get accountSessionInstances =>
      List.unmodifiable(_instances);

  @override
  DiscourseInstance? accountSessionInstance(String siteUrl) =>
      _instanceAt(siteUrl);

  @override
  void clearAccountSessionState(String siteUrl) {
    _forgetSiteState(siteUrl, invalidateLifecycle: false);
  }

  @override
  DiscourseInstance? applyAccountSessionInstance(
    DiscourseInstance replacement,
    AccountSessionPhase phase,
  ) {
    final held = _instanceAt(replacement.url);
    if (held == null) return null;

    var applied = replacement;
    if (phase == AccountSessionPhase.connected && replacement.user != null) {
      final user = _acceptDoNotDisturbSnapshot(
        replacement.url,
        replacement.user!,
      );
      applied = replacement.copyWith(user: user);
      _seedGroupedUnreadNotifications(replacement.url, user);
      _sessionUsersRefreshed.add(replacement.url);
    } else if (phase == AccountSessionPhase.restored &&
        replacement.user != null) {
      if (replacement.notificationTotals case final totals?) {
        accountActivity.restoreTotals(replacement.url, totals);
      }
      doNotDisturb.restoreSnapshot(
        replacement.url,
        replacement.user?.doNotDisturbUntil,
      );
      _seedGroupedUnreadNotifications(replacement.url, replacement.user!);
    }

    _replaceInstance(held, applied);
    if (currentInstance?.url == replacement.url) {
      switch (phase) {
        case AccountSessionPhase.connecting:
          break;
        case AccountSessionPhase.connected:
          _resetToInstanceDefault(refreshAppearance: false);
          unawaited(_presentation.refreshAppearance(replacement.url));
        case AccountSessionPhase.disconnecting:
          // The coordinator has published the durable signed-out boundary but
          // still owns credential revocation and deletion. Starting anonymous
          // presentation work here would race that teardown and read the same
          // credential again. The final disconnected phase rebuilds and
          // hydrates the public workspace once secret storage has settled.
          break;
        case AccountSessionPhase.rolledBack:
          _resetToInstanceDefault(refreshAppearance: false);
        case AccountSessionPhase.disconnected || AccountSessionPhase.restored:
          _resetToInstanceDefault();
      }
    }
    _notify();
    return applied;
  }

  void _forgetSiteState(String siteUrl, {bool invalidateLifecycle = true}) {
    if (invalidateLifecycle) lifecycle.invalidate(siteUrl);
    siteImages.forget(siteUrl);
    _removeWorkspace(siteUrl);
    if (currentInstance?.url == siteUrl) search.clear();
    _composerDrafts.forgetSite(siteUrl);

    final composer = _composer;
    if (composer?.target.siteUrl == siteUrl) {
      composer!.draftSettled();
      composer.dispose();
      _composer = null;
      _composerDrafts.detach(composer);
    }

    accountActivity.forget(siteUrl);
    draftList.forget(siteUrl);
    userSummary.forget(siteUrl);
    groups.forget(siteUrl);
    preferences.forget(siteUrl);
    store.forget(siteUrl);

    _likersLoading.removeWhere((key) => key.startsWith('$siteUrl~'));
    _likersErrors.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _userCardsLoading.removeWhere((key) => key.startsWith('$siteUrl@'));
    _userCardErrors.removeWhere((key, _) => key.startsWith('$siteUrl@'));
    _postWritesInFlight.removeWhere((key) => key.startsWith('$siteUrl~'));
    _topicPostSelections.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicPostSelectionWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicFlagWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicBookmarkWritesInFlight.removeWhere(
      (key) => key.startsWith('$siteUrl#'),
    );
    _pluginBookmarkWritesInFlight.removeWhere(
      (key) => key.startsWith('$siteUrl~'),
    );
    _bookmarkVersions.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _siteBookmarkVersions.remove(siteUrl);
    _postRefreshRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _postRefreshPending.removeWhere((key) => key.startsWith('$siteUrl~'));
    _postRefreshTopics.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _topicsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicRefreshPending.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicRefreshPostNumbers.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicsStale.removeWhere((key) => key.startsWith('$siteUrl#'));
    _postsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _earlierPostsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicSummaryStreams.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicSummariesLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicNotificationRevisions.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicNotificationTails.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicNotificationConfirmed.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicPinWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicStatusWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicDeletionWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicJumpRuns.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicReads.forget(siteUrl);

    _categorised.remove(siteUrl);
    _categoriesBySite.remove(siteUrl);
    _topicTrackingBySite.remove(siteUrl);
    _topicTrackingSnapshotsLoaded.remove(siteUrl);
    _topicTrackingRevisions.remove(siteUrl);
    _topicTrackingLoads.remove(siteUrl);
    _topicTrackingPendingEvents.remove(siteUrl);
    _categoryFeeds.remove(siteUrl);
    _categoryIdsLoading.removeWhere((entry) => entry.$1 == siteUrl);
    _categoryPageRequests.remove(siteUrl);
    _categorySidebarCache.remove(siteUrl);
    _siteTopTagsBySite.remove(siteUrl);
    _anonymousDefaultTagsBySite.remove(siteUrl);
    _tagSidebarCache.remove(siteUrl);
    _tagDirectoryFeeds.remove(siteUrl);
    _tagDirectoryRequests.remove(siteUrl);
    _topicComposerCapabilities.remove(siteUrl);
    _postActionCatalogs.remove(siteUrl);
    _customSidebarSections.remove(siteUrl);
    _customSidebarSectionsLoaded.remove(siteUrl);
    _customSidebarSectionAttemptedAt.remove(siteUrl);
    _customSidebarSectionRequests.remove(siteUrl)?.ignore();
    _sitePresentation?.forget(siteUrl);
    _hashtags.remove(siteUrl);
    _hashtagsInFlight.remove(siteUrl);
    _mentioned.remove(siteUrl);
    _mentionsInFlight.remove(siteUrl);
    _connectErrors.remove(siteUrl);
    _unavailableForums.remove(siteUrl);
    _retryingUnavailableForums.remove(siteUrl);

    _backgroundRetention.releaseSite(siteUrl);
    final forgetPlugins = _pluginSession
        .forget(siteUrl)
        .whenComplete(() => _backgroundRetention.releaseSite(siteUrl));
    _observePluginLifecycle(forgetPlugins, 'plugins.session.forget');
    topicFeeds.forget(siteUrl);
    _trackersStarting.remove(siteUrl);
    _sessionUsersRefreshed.remove(siteUrl);
    _sessionUserRequests.remove(siteUrl)?.ignore();
    doNotDisturb.forget(siteUrl);
    _userStatusOverrides.remove(siteUrl);
    _userStatusWrites.remove(siteUrl);
    _optimisticHidePresence.remove(siteUrl);
    _hidePresenceWrites.remove(siteUrl);
    _hidePresenceErrors.remove(siteUrl);
    _hidePresenceVersions.remove(siteUrl);
    _groupedUnreadNotificationVersions.remove(siteUrl);
    _draftCountVersions.remove(siteUrl);
    _pluginNotificationFeedRefreshTimers.remove(siteUrl)?.cancel();
    _disposeTracking(siteUrl);
    _notify();
  }

  void _replaceInstance(DiscourseInstance old, DiscourseInstance updated) {
    final index = _instances.indexOf(old);
    if (index >= 0) _instances[index] = updated;
  }

  void _restoreInstanceWorkspace({
    bool refreshAppearance = true,
    bool hydrateActiveTab = true,
  }) {
    final instance = currentInstance;
    if (instance == null) {
      search.selectSite(null);
      _syncTracking();
      return;
    }

    _ensureWorkspace(instance);
    _activateInstanceWorkspace(
      instance,
      refreshAppearance: refreshAppearance,
      hydrateActiveTab: hydrateActiveTab,
    );
  }

  void _resetToInstanceDefault({bool refreshAppearance = true}) {
    final instance = currentInstance;
    if (instance == null) {
      search.selectSite(null);
      _syncTracking();
      return;
    }

    _putWorkspace(_newWorkspace(instance));
    _activateInstanceWorkspace(instance, refreshAppearance: refreshAppearance);
  }

  void _activateInstanceWorkspace(
    DiscourseInstance instance, {
    required bool refreshAppearance,
    bool hydrateActiveTab = true,
  }) {
    assert(currentInstance?.url == instance.url);

    final canRead = !instance.loginRequired || instance.isConnected;
    search.selectSite(
      canRead ? instance.url : null,
      minimumLength: instance.config.minSearchTermLength,
      logSearchQueries: instance.config.logSearchQueries,
      taggingEnabled: instance.config.taggingEnabled,
      usePgHeadlinesForExcerpt: instance.config.usePgHeadlinesForExcerpt,
    );
    if (refreshAppearance && canRead) {
      unawaited(_presentation.ensureAppearance(instance.url));
    }
    // Category navigation is first-class shell state. It cannot depend on the
    // default topic feed succeeding, and its ordering/defaults live in the
    // client settings payload.
    if (canRead) {
      unawaited(_presentation.ensureConfig(instance.url));
      unawaited(_presentation.ensureCustomEmojis(instance.url));
      // Warm the emoji catalog with the first feed to avoid a second title frame.
      unawaited(_presentation.warmEmojiCatalog(instance.url));
      unawaited(_ensureCategoriesFor(instance));
    }
    for (final activator
        in _pluginSession.capabilities<PluginSiteActivator>()) {
      _observePluginLifecycle(
        Future.sync(
          () => activator.activatePluginSite(
            instance.url,
            connected: instance.isConnected,
          ),
        ),
        'plugins.session.activateSite',
      );
    }
    _syncTracking();
    _syncTopicChannels();
    // Totals may have landed while this site was inactive. The ordinary
    // refresh on reselection can legitimately reuse that five-minute snapshot,
    // so activation itself must notify totals observers instead of relying on
    // a callback which only runs after network responses.
    _notifyPluginTotals(instance);
    if (canRead && hydrateActiveTab) _hydrateActiveTab(instance);
  }

  void _hydrateActiveTab(DiscourseInstance instance) {
    final tab = activeTab;
    if (tab == null || currentInstance?.url != instance.url) return;

    final root = tab.contentStack.first;
    unawaited(
      loadFeed(
        root.feedPath == null && !root.isMessages
            ? tab.rootDestinationId
            : root.id,
      ),
    );
    final route = tab.currentContent;
    final hydrator = _pluginSession
        .capabilities<PluginRouteHydrator>()
        .where((candidate) => candidate.handlesPluginRoute(route.id))
        .firstOrNull;
    if (hydrator != null) {
      _observePluginLifecycle(
        Future.sync(() => hydrator.hydratePluginRoute(instance.url, route.id)),
        'plugins.session.hydrateRoute',
      );
    } else if (route.topicId case final topicId?) {
      final anchor = tab.anchors[route.id];
      unawaited(
        loadTopic(
          topicId,
          route.slug ?? '',
          postNumber: anchor?.kind == 'topic'
              ? anchor!.itemId
              : route.postNumber,
        ),
      );
    } else if (route.feedPath != null && route.id != root.id) {
      unawaited(loadFeed(route.id));
    }
  }

  @override
  void selectInstance(int index) {
    assert(index >= 0 && index < _instances.length);
    _settingsReturnTarget = null;
    _rootMode = ShellRootMode.forum;
    if (index != _instanceIndex) {
      _instanceIndex = index;
      _restoreInstanceWorkspace();
      final selected = currentInstance;
      if (selected != null && selected.isConnected) {
        unawaited(
          Future.wait([
            _refreshOne(selected),
            _refreshSessionUserFor(selected),
          ]),
        );
      }
    }
    _mobilePane = MobilePane.sidebar;
    _notify();
  }

  void selectAggregate() {
    if (!loaded || !hasInstances) return;
    _settingsReturnTarget = null;
    _rootMode = ShellRootMode.aggregate;
    _mobilePane = MobilePane.content;
    _notify();
    unawaited(aggregate.open(_instances));
  }

  void selectSettings() {
    if (_rootMode == ShellRootMode.settings) return;
    _settingsReturnTarget = (rootMode: _rootMode, mobilePane: _mobilePane);
    _rootMode = ShellRootMode.settings;
    _mobilePane = MobilePane.content;
    _notify();
  }

  Future<void> refreshAggregate() => aggregate.refresh(_instances, force: true);

  List<AggregateFeedTab> get aggregateTabs => aggregate.tabs;
  String get activeAggregateTabId => aggregate.activeTabId;
  bool get canCreateAggregateTab => forumTabsEnabled && aggregate.canCreateTab;

  void createAggregateTab() {
    if (!forumTabsEnabled || aggregate.createTab() == null) return;
    unawaited(aggregate.open(_instances));
  }

  void selectAggregateTab(String id) {
    if (!forumTabsEnabled || !aggregate.selectTab(id)) return;
    unawaited(aggregate.open(_instances));
  }

  void renameAggregateTab(String id, String name) {
    if (!forumTabsEnabled) return;
    aggregate.renameTab(id, name);
  }

  void closeAggregateTab(String id) {
    if (!forumTabsEnabled) return;
    final openedAnotherTab = aggregate.closeTab(id);
    if (openedAnotherTab) unawaited(aggregate.open(_instances));
  }

  void moveAggregateTab(String id, int newIndex) {
    if (!forumTabsEnabled) return;
    aggregate.moveTab(id, newIndex);
  }

  void closeOtherAggregateTabs(String id) {
    if (!forumTabsEnabled || !aggregate.closeOtherTabs(id)) return;
    unawaited(aggregate.open(_instances));
  }

  Future<void> setAggregateForumFilters({
    required Set<String> includedForums,
    required Map<String, String> queries,
  }) async {
    final persisted = aggregate.setForumFilters(
      allForums: _instances,
      includedConnectedForums: includedForums,
      queries: queries,
    );
    await aggregate.refresh(_instances, force: true);
    await persisted;
  }

  AggregateTopicOpenResult openAggregateTopic(String siteUrl, int topicId) {
    final topic = store.read<Topic>(siteUrl, topicId);
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (topic == null || index < 0) {
      return AggregateTopicOpenResult.unavailable;
    }

    final instance = _instances[index];
    _settingsReturnTarget = null;

    if (!forumTabsEnabled) {
      _rootMode = ShellRootMode.forum;
      if (index != _instanceIndex) {
        _instanceIndex = index;
        _restoreInstanceWorkspace(hydrateActiveTab: false);
      }
      _mobilePane = MobilePane.content;
      if (currentContent?.topicId == topic.id) {
        _notify();
      } else {
        _openTopic(
          topic.id,
          topic.slug,
          topic.title,
          postNumber: topic.lastUnreadPostNumber,
        );
      }
      return AggregateTopicOpenResult.opened;
    }

    final workspace = _ensureWorkspace(instance);
    ForumTab? existingTopicTab;
    for (final candidate in workspace.tabs) {
      if (candidate.currentContent.topicId == topic.id) {
        existingTopicTab = candidate;
        break;
      }
    }
    if (existingTopicTab == null &&
        workspace.tabs.length >= ForumWorkspace.maximumTabs) {
      return AggregateTopicOpenResult.tabLimitReached;
    }

    _rootMode = ShellRootMode.forum;
    if (index != _instanceIndex) {
      _instanceIndex = index;
      _restoreInstanceWorkspace(hydrateActiveTab: false);
    }

    if (existingTopicTab case final tab?) {
      _putWorkspace(workspace.copyWith(activeTabId: tab.id));
      _mobilePane = MobilePane.content;
      _syncTopicChannels();
      _notify();
      _hydrateActiveTab(instance);
      return AggregateTopicOpenResult.opened;
    }

    final tab = _newDefaultTab(instance).push(
      ContentRoute.topic(
        topicId: topic.id,
        slug: topic.slug,
        title: topic.title,
        postNumber: topic.lastUnreadPostNumber,
      ),
    );
    _putWorkspace(
      workspace.copyWith(tabs: [...workspace.tabs, tab], activeTabId: tab.id),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    _hydrateActiveTab(instance);
    return AggregateTopicOpenResult.opened;
  }

  @override
  void selectDestination(SidebarDestination destination) {
    _preparePluginPaneForRoute(destination.id);
    final instance = currentInstance;
    if (instance == null) return;
    final tab = _ensureWorkspace(instance).activeTab;
    // Tapping what you are already looking at asks for it again — the cache
    // otherwise holds a list for the life of the session, and a mouse cannot
    // pull to refresh. Only at the destination's root: a tap that is busy
    // returning from a topic stays a return.
    final refresh =
        destination.id == tab.rootDestinationId && tab.contentStack.length <= 1;

    final content = destination.id == 'groups'
        ? ContentRoute.group(const GroupRoute.directory())
        : ContentRoute.fromDestination(destination);
    _replaceActiveTab(
      tab.copyWith(
        rootDestinationId: destination.id,
        contentStack: [content],
        forwardStack: const [],
      ),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();

    if (destination.id == 'all-tags') {
      if (refresh) unawaited(loadTags(instance.url, force: true));
    } else {
      unawaited(loadFeed(destination.id, force: refresh));
    }
  }

  void selectGroupRoute(GroupRoute route, {String? feedPath}) {
    final instance = currentInstance;
    final current = currentContent?.groupRoute;
    if (instance == null ||
        current?.isDetail != true ||
        route.groupName != current!.groupName ||
        route == current) {
      return;
    }
    final content = ContentRoute.group(
      route,
      title: currentContent?.title,
      feedPath: feedPath ?? route.topicFeedPath(instance.user?.username),
    );
    replaceCurrentContent(content);
    if (content.feedPath != null) unawaited(loadFeed(content.id));
  }

  Future<void> selectTopicListMode(TopicListMode mode) async {
    final instance = currentInstance;
    final user = instance?.user;
    final tab = activeTab;
    final currentMode = currentTopicListMode;
    if (user == null || tab == null || currentMode == null) return;
    if (mode.isSubset && !user.unifiedNewEnabled) return;
    if (mode == currentMode) return;

    final route = ContentRoute.topicList(mode);
    _replaceActiveTab(
      tab.copyWith(contentStack: [route], forwardStack: const []),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    await loadFeed(route.id);
  }

  void createTab() {
    if (!canCreateTab) return;
    final instance = currentInstance;
    if (instance == null) return;
    final workspace = _ensureWorkspace(instance);
    final tab = _newDefaultTab(instance);
    _putWorkspace(
      workspace.copyWith(tabs: [...workspace.tabs, tab], activeTabId: tab.id),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    _hydrateActiveTab(instance);
  }

  void selectTab(String id) {
    if (!forumTabsEnabled) return;
    final instance = currentInstance;
    final workspace = currentWorkspace;
    if (instance == null || workspace?.tabById(id) == null) return;

    if (workspace!.activeTabId != id) {
      // A desktop tab click is local navigation. Paint that state before
      // serialising every workspace or starting any cache/network hydration;
      // both otherwise share the pointer event's UI-isolate turn and can make
      // a synchronous selection feel as though it is waiting on the server.
      _putWorkspace(workspace.copyWith(activeTabId: id), persist: false);
      _tabSelectionPersistencePending = true;
      _mobilePane = MobilePane.content;
      _notify();
      _scheduleTabSelectionSettlement(instance.url, id);
      return;
    }
    _mobilePane = MobilePane.content;
    _notify();
  }

  void moveTab(String id, int newIndex) {
    if (!forumTabsEnabled) return;
    final workspace = currentWorkspace;
    if (workspace == null || workspace.tabs.length < 2) return;
    final oldIndex = workspace.tabs.indexWhere((tab) => tab.id == id);
    if (oldIndex < 0) return;
    final destination = newIndex.clamp(0, workspace.tabs.length - 1);
    if (oldIndex == destination) return;

    final reordered = List<ForumTab>.of(workspace.tabs);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(destination, moved);
    _putWorkspace(workspace.copyWith(tabs: reordered));
    _notify();
  }

  void _scheduleTabSelectionSettlement(String siteUrl, String tabId) {
    _pendingTabSelection = (siteUrl: siteUrl, tabId: tabId);

    // Controller-only consumers have nothing to paint. Preserve their
    // synchronous hydration/persistence semantics rather than leaving a task
    // waiting for a test or headless binding to produce a frame.
    if (!hasListeners) {
      _settlePendingTabSelection();
      return;
    }
    if (_tabSelectionSettlementScheduled) return;
    _tabSelectionSettlementScheduled = true;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final needsAnotherFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.postFrameCallbacks;
    unawaited(() async {
      // endOfFrame schedules a frame when called while idle. Unlike a zero
      // duration timer, it guarantees the selected indicator, header and
      // cached viewport have had an opportunity to paint first.
      await SchedulerBinding.instance.endOfFrame;
      // A selection raised while layout/paint or another post-frame callback
      // is running cannot notify its widgets until the following frame.
      if (needsAnotherFrame) await SchedulerBinding.instance.endOfFrame;
      if (!isDisposed) _settlePendingTabSelection();
    }());
  }

  void _settlePendingTabSelection() {
    final target = _pendingTabSelection;
    _pendingTabSelection = null;
    _tabSelectionSettlementScheduled = false;
    if (_tabSelectionPersistencePending) _persistWorkspaces();
    if (target == null ||
        currentInstance?.url != target.siteUrl ||
        activeTabId != target.tabId) {
      return;
    }

    final instance = _instanceAt(target.siteUrl);
    if (instance == null) return;
    _syncTopicChannels();
    _hydrateActiveTab(instance);
  }

  void closeTab(String id) {
    if (!forumTabsEnabled) return;
    final instance = currentInstance;
    final workspace = currentWorkspace;
    if (instance == null || workspace == null) return;
    final index = workspace.tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;

    if (_composer case final composer? when composer.target.tabId == id) {
      if (composer.discarding) return;
      closeComposer();
    }

    final closedActive = workspace.activeTabId == id;
    late ForumWorkspace replacement;
    if (workspace.tabs.length == 1) {
      final fresh = _newDefaultTab(instance);
      replacement = workspace.copyWith(tabs: [fresh], activeTabId: fresh.id);
    } else {
      final remaining = [
        for (final tab in workspace.tabs)
          if (tab.id != id) tab,
      ];
      final activeId = closedActive
          ? remaining[index < remaining.length ? index : remaining.length - 1]
                .id
          : workspace.activeTabId;
      replacement = workspace.copyWith(tabs: remaining, activeTabId: activeId);
    }

    _putWorkspace(replacement);
    if (closedActive) {
      _syncTopicChannels();
      _hydrateActiveTab(instance);
    }
    _notify();
  }

  void closeOtherTabs(String id) {
    if (!forumTabsEnabled) return;
    final instance = currentInstance;
    final workspace = currentWorkspace;
    if (instance == null || workspace == null || workspace.tabs.length == 1) {
      return;
    }
    final kept = workspace.tabById(id);
    if (kept == null) return;

    if (_composer case final composer? when composer.target.tabId != id) {
      if (composer.discarding) return;
      closeComposer();
    }

    final activeChanged = workspace.activeTabId != id;
    _putWorkspace(workspace.copyWith(tabs: [kept], activeTabId: id));
    if (activeChanged) {
      _syncTopicChannels();
      _hydrateActiveTab(instance);
    }
    _notify();
  }

  void openDrafts(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);

    final instance = _instances[index];
    for (final section in instance.sections) {
      for (final destination in section.destinations) {
        if (destination.id == 'drafts') {
          selectDestination(destination);
          return;
        }
      }
    }
  }

  void openUserSummary(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || _instances[index].user == null) return;
    if (index != _instanceIndex) selectInstance(index);
    if (currentContent?.id == 'summary') return;
    pushContent(
      const ContentRoute(id: 'summary', title: 'Summary', icon: DIcons.user),
    );
  }

  void openPreferences(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || !_instances[index].isConnected) return;
    if (index != _instanceIndex) selectInstance(index);
    if (currentContent?.isPreferences == true) {
      _mobilePane = MobilePane.content;
      _notify();
      return;
    }
    pushContent(ContentRoute.preferences());
  }

  void openUserActivity(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);
    if (_instances[index].isConnected != true ||
        currentContent?.id == 'activity') {
      return;
    }
    pushContent(ContentRoute.userActivity());
  }

  Future<void> resumeDraft(String siteUrl, UserDraft draft) async {
    if (!draft.canResume) return;
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    if (index != _instanceIndex) selectInstance(index);
    final instance = currentInstance;
    if (instance == null || instance.url != siteUrl) return;

    if (draft.key == ComposerDraft.newTopicDraftKey) {
      final destination = instance.defaultDestination;
      // Selecting the destination already on screen means "refresh" to the
      // shell. Do not start that second, unawaited request when a header-menu
      // draft is resumed from the default list; openNewTopic needs the
      // creatable feed that is already in hand.
      if (destinationId != destination.id || contentStack.length != 1) {
        selectDestination(destination);
      }
      await loadFeed(destination.id);
      if (currentInstance?.url != siteUrl || destinationId != destination.id) {
        return;
      }
      await openNewTopic();
      final composer = _composer;
      if (composer == null || composer.target.draftKey != draft.key) return;
      _composerDrafts.restoreListedDraft(composer, draft);
      return;
    }

    final topicId = draft.topicId;
    if (topicId == null) return;
    pushContent(
      ContentRoute.topic(
        topicId: topicId,
        slug: draft.slug ?? '',
        title: draft.title ?? draft.displayTitle,
      ),
    );
    await loadTopic(topicId, draft.slug ?? '');
    if (currentInstance?.url != siteUrl || currentContent?.topicId != topicId) {
      return;
    }
    openReply(
      replyToPostNumber: draft.data?.replyToPostNumber,
      replyToUsername: draft.data?.replyToUsername,
    );
    final composer = _composer;
    if (composer == null || composer.target.draftKey != draft.key) return;
    _composerDrafts.restoreListedDraft(composer, draft);
  }

  @override
  void pushContent(ContentRoute route) {
    final startsPluginPane = _preparePluginPaneForRoute(route.id);
    final tab = activeTab;
    if (tab == null) return;
    _setForumContentRoot();
    _replaceActiveTab(
      startsPluginPane
          ? tab.copyWith(
              rootDestinationId: route.id,
              contentStack: [route],
              forwardStack: const [],
            )
          : tab.push(route),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
  }

  @override
  void replaceCurrentContent(ContentRoute route) {
    final startsPluginPane = _preparePluginPaneForRoute(route.id);
    final tab = activeTab;
    if (tab == null) return;
    _setForumContentRoot();
    _replaceActiveTab(
      startsPluginPane
          ? tab.copyWith(
              rootDestinationId: route.id,
              contentStack: [route],
              forwardStack: const [],
            )
          : tab.copyWith(
              contentStack: [
                ...tab.contentStack.take(tab.contentStack.length - 1),
                route,
              ],
            ),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
  }

  @override
  void showPluginContent() {
    if (!_setForumContentRoot()) return;
    _notify();
  }

  @override
  bool activatePluginPane(PluginId owner) {
    final instance = currentInstance;
    var tab = activeTab;
    if (instance == null || tab == null) return false;

    var stateKey = (siteUrl: instance.url, tabId: tab.id);
    var activeOwner = _activePluginPanes[stateKey];
    if (activeOwner == null) {
      final currentRouteId = tab.currentContent.id;
      final restoredPolicy = _pluginSession
          .capabilities<PluginPaneRoutePolicy>()
          .where(
            (policy) =>
                policy.ownsPluginPaneRoute(currentRouteId) &&
                policy.separatesPluginPane(currentRouteId),
          )
          .firstOrNull;
      if (restoredPolicy != null) {
        activeOwner = restoredPolicy.pluginPaneOwner;
        _activePluginPanes[stateKey] = activeOwner;
      }
    }
    if (activeOwner == owner) {
      return !_coldPluginPanes.contains(stateKey);
    }
    if (activeOwner != null) {
      _deactivatePluginPane(activeOwner, notifyAndHydrate: false);
      tab = activeTab;
      if (tab == null) return false;
      stateKey = (siteUrl: instance.url, tabId: tab.id);
    }
    final key = (siteUrl: instance.url, tabId: tab.id, owner: owner);
    _activePluginPanes[stateKey] = owner;
    _mainPaneTabs[key] = tab;
    final pluginTab = _pluginPaneTabs[key];
    if (pluginTab == null) {
      _coldPluginPanes.add(stateKey);
      return false;
    }

    _coldPluginPanes.remove(stateKey);
    _restorePluginPaneTab(instance, pluginTab);
    return true;
  }

  @override
  void deactivatePluginPane(PluginId owner) {
    _deactivatePluginPane(owner, notifyAndHydrate: true);
  }

  void _deactivatePluginPane(PluginId owner, {required bool notifyAndHydrate}) {
    final instance = currentInstance;
    final tab = activeTab;
    if (instance == null || tab == null) return;

    final stateKey = (siteUrl: instance.url, tabId: tab.id);
    final activeOwner = _activePluginPanes[stateKey];
    if (activeOwner != null && activeOwner != owner) return;
    _activePluginPanes.remove(stateKey);
    final wasCold = _coldPluginPanes.remove(stateKey);
    final key = (siteUrl: instance.url, tabId: tab.id, owner: owner);
    if (!wasCold) _pluginPaneTabs[key] = tab;
    final mainTab =
        _mainPaneTabs.remove(key) ??
        ForumTab(
          id: tab.id,
          rootDestinationId: instance.defaultDestination.id,
          contentStack: [
            ContentRoute.fromDestination(instance.defaultDestination),
          ],
        );
    _restorePluginPaneTab(
      instance,
      mainTab,
      notifyAndHydrate: notifyAndHydrate,
    );
  }

  bool _preparePluginPaneForRoute(String routeId) {
    final instance = currentInstance;
    final tab = activeTab;
    if (instance == null || tab == null) return false;

    final stateKey = (siteUrl: instance.url, tabId: tab.id);
    final policies = _pluginSession
        .capabilities<PluginPaneRoutePolicy>()
        .toList(growable: false);
    var owner = _activePluginPanes[stateKey];
    if (owner == null) {
      final currentRouteId = tab.currentContent.id;
      final currentPolicy = policies
          .where(
            (policy) =>
                policy.ownsPluginPaneRoute(currentRouteId) &&
                policy.separatesPluginPane(currentRouteId),
          )
          .firstOrNull;
      if (currentPolicy != null) {
        owner = currentPolicy.pluginPaneOwner;
        _activePluginPanes[stateKey] = owner;
      }
    }

    if (owner != null) {
      final staysInPane = policies.any(
        (policy) =>
            policy.pluginPaneOwner == owner &&
            policy.ownsPluginPaneRoute(routeId) &&
            policy.separatesPluginPane(routeId),
      );
      if (staysInPane) return _coldPluginPanes.remove(stateKey);
      _deactivatePluginPane(owner, notifyAndHydrate: false);
    }

    final targetPolicy = policies
        .where(
          (policy) =>
              policy.ownsPluginPaneRoute(routeId) &&
              policy.separatesPluginPane(routeId),
        )
        .firstOrNull;
    if (targetPolicy != null) {
      activatePluginPane(targetPolicy.pluginPaneOwner);
      return _coldPluginPanes.remove(stateKey);
    }
    return false;
  }

  void _restorePluginPaneTab(
    DiscourseInstance instance,
    ForumTab tab, {
    bool notifyAndHydrate = true,
  }) {
    _setForumContentRoot();
    _replaceActiveTab(tab);
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    if (notifyAndHydrate) {
      _notify();
      _hydrateActiveTab(instance);
    }
  }

  bool handleBack({bool canReturnToSidebar = true}) {
    if (_rootMode == ShellRootMode.settings) {
      final target = _settingsReturnTarget;
      _settingsReturnTarget = null;
      final restoreAggregate = target?.rootMode == ShellRootMode.aggregate;
      _rootMode = restoreAggregate
          ? ShellRootMode.aggregate
          : ShellRootMode.forum;
      _mobilePane = restoreAggregate
          ? MobilePane.content
          : target?.rootMode == ShellRootMode.forum
          ? target!.mobilePane
          : MobilePane.sidebar;
      _notify();
      return true;
    }
    if (_rootMode == ShellRootMode.aggregate) {
      _rootMode = ShellRootMode.forum;
      _mobilePane = MobilePane.sidebar;
      _notify();
      return true;
    }
    if (canPopContent) {
      final tab = activeTab!;
      _replaceActiveTab(tab.goBack());
      _syncTopicChannels();
      _notify();
      if (currentInstance case final instance?) _hydrateActiveTab(instance);
      return true;
    }
    if (canReturnToSidebar && _mobilePane == MobilePane.content) {
      _mobilePane = MobilePane.sidebar;
      _notify();
      return true;
    }
    return false;
  }

  bool handleForward() {
    final tab = activeTab;
    if (_rootMode != ShellRootMode.forum || tab?.canGoForward != true) {
      return false;
    }
    _replaceActiveTab(tab!.goForward());
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
    if (currentInstance case final instance?) _hydrateActiveTab(instance);
    return true;
  }

  void _notify() => notifySafely();

  @override
  void dispose() {
    final composer = _composer;
    // Queue the final local draft before lifecycle invalidation without
    // entering the normal remote-sync callback.
    _composerDrafts.preservePendingLocally(composer);

    // A window can close in the frame immediately after a selection or a
    // scroll. Keep the latest local choice and anchor durable, but never start
    // hydration while tearing the controller down.
    _pendingTabSelection = null;
    _tabSelectionSettlementScheduled = false;
    _anchorPersistTimer?.cancel();
    _anchorPersistTimer = null;
    if (_tabSelectionPersistencePending || _anchorPersistencePending) {
      _persistWorkspaces();
    }
    _topicNotificationRevisions.clear();
    _topicNotificationTails.clear();
    _topicNotificationConfirmed.clear();
    _topicPinWrites.clear();
    _topicStatusWrites.clear();
    _userStatusOverrides.clear();
    _userStatusWrites.clear();
    _optimisticHidePresence.clear();
    _hidePresenceWrites.clear();
    _hidePresenceErrors.clear();
    _hidePresenceVersions.clear();
    _groupedUnreadNotificationVersions.clear();
    _draftCountVersions.clear();
    for (final timer in _pluginNotificationFeedRefreshTimers.values) {
      timer.cancel();
    }
    _pluginNotificationFeedRefreshTimers.clear();
    _topicDeletionWrites.clear();
    _topicPostSelections.clear();
    _topicPostSelectionWrites.clear();
    _topicFlagWrites.clear();
    _topicJumpRuns.clear();
    _topicReads.dispose();
    for (final instance in _instances) {
      lifecycle.invalidate(instance.url);
    }
    updates.dispose();
    accountActivity.dispose();
    doNotDisturb.dispose();
    draftList.dispose();
    userSummary.dispose();
    groups.dispose();
    preferences.dispose();
    topicFeeds.dispose();
    aggregate.dispose();
    appSettings.dispose();
    siteImages.dispose();
    final closePluginSession = _pluginSession.close();
    _backgroundRetention.close();
    _observePluginLifecycle(closePluginSession, 'plugins.session.close');
    if (_ownsPlugins) {
      final closeOwnedPlugins = closePluginSession
          .onError((_, _) {})
          .then((_) => plugins.close());
      _pluginTeardownFuture = closeOwnedPlugins;
      _observePluginLifecycle(closeOwnedPlugins, 'plugins.close');
    } else {
      _pluginTeardownFuture = closePluginSession;
    }
    search.dispose();
    for (final host in _coreBookmarkTargetHosts.values) {
      host.dispose();
    }
    _coreBookmarkTargetHosts.clear();
    for (final host in _pluginBookmarkTargetHosts.values) {
      host.dispose();
    }
    _pluginBookmarkTargetHosts.clear();
    for (final listenable in _pluginSiteConfigListenables.values) {
      listenable.dispose();
    }
    _pluginSiteConfigListenables.clear();
    final presentation = _sitePresentation;
    if (presentation != null) {
      presentation.removeListener(_notify);
      presentation.dispose();
    }
    composer?.dispose();
    _composer = null;
    for (final tracker in _trackers.values) {
      tracker.dispose().ignore();
    }
    _trackers.clear();
    if (ownsApi) api.close();
    super.dispose();
  }
}

final class _PluginSiteConfigListenable extends ChangeNotifier
    implements ValueListenable<SiteConfig> {
  _PluginSiteConfigListenable(Listenable source, SiteConfig Function() read)
    : _source = source,
      _read = read,
      _value = read() {
    _source.addListener(_refresh);
  }

  final Listenable _source;
  final SiteConfig Function() _read;
  SiteConfig _value;

  @override
  SiteConfig get value => _value;

  void _refresh() {
    final next = _read();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _source.removeListener(_refresh);
    super.dispose();
  }
}

final class _ScopedEmojiPreferenceStore implements EmojiPreferenceStore {
  const _ScopedEmojiPreferenceStore(this._delegate, this._consumer);

  final EmojiPreferenceStore _delegate;
  final PluginId _consumer;

  void _requireOwned(EmojiUsageContext context) {
    if (context.isValidFor(_consumer)) return;
    throw PluginInstallationException(
      'Plugin $_consumer cannot use emoji context ${context.id}.',
    );
  }

  @override
  Future<EmojiSkinTone> readSkinTone({required String siteUrl}) =>
      _delegate.readSkinTone(siteUrl: siteUrl);

  @override
  Future<List<String>> favoriteEmojiCodes({
    required String siteUrl,
    required EmojiUsageContext context,
    required SiteEmojiCatalog catalog,
  }) {
    _requireOwned(context);
    return _delegate.favoriteEmojiCodes(
      siteUrl: siteUrl,
      context: context,
      catalog: catalog,
    );
  }

  @override
  Future<void> writeSkinTone({
    required String siteUrl,
    required EmojiSkinTone tone,
  }) => _delegate.writeSkinTone(siteUrl: siteUrl, tone: tone);

  @override
  Future<void> trackEmoji({
    required String siteUrl,
    required EmojiUsageContext context,
    required String emoji,
  }) {
    _requireOwned(context);
    return _delegate.trackEmoji(
      siteUrl: siteUrl,
      context: context,
      emoji: emoji,
    );
  }

  @override
  Future<void> clearHistory({
    required String siteUrl,
    required EmojiUsageContext context,
  }) {
    _requireOwned(context);
    return _delegate.clearHistory(siteUrl: siteUrl, context: context);
  }
}

final class _ShellPluginSiteLease implements PluginSiteLease {
  const _ShellPluginSiteLease(this.value);

  final SiteLease value;

  @override
  bool get isCurrent => value.isCurrent;

  @override
  bool commit(VoidCallback mutation) => value.commit(mutation);
}

final class _ShellPluginRequestHost implements PluginRequestHost {
  const _ShellPluginRequestHost(this._shell);

  final ShellController _shell;

  @override
  PluginSiteLease capture(String siteUrl) =>
      _ShellPluginSiteLease(_shell.lifecycle.capture(siteUrl));

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      PluginRequestCredentials(
        apiKey: await _shell.authenticator.apiKeyFor(siteUrl),
        clientId: await _shell.authenticator.clientId(),
      );

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) =>
      _shell.pluginWriteCredential(siteUrl);
}

final class _ShellPluginAccountConnectionHost
    implements PluginAccountConnectionHost {
  const _ShellPluginAccountConnectionHost(this._shell);

  final ShellController _shell;

  @override
  bool isConnected(String siteUrl) =>
      _shell._instanceAt(siteUrl)?.isConnected == true;

  @override
  Future<String?> connect(String siteUrl) async {
    if (_shell.currentInstance?.url != siteUrl) return null;
    await _shell.connectCurrentInstance();
    return _shell._connectErrors[siteUrl];
  }
}

final class _ShellPluginTargetHost implements PluginTargetHost {
  const _ShellPluginTargetHost(this._shell, this._consumer);

  final ShellController _shell;
  final PluginId _consumer;

  @override
  PluginTargetSnapshot<T> recordFor<T extends Object>(
    String siteUrl,
    PluginTarget target,
    PluginDataKey<T> key,
  ) {
    if (key.owner != _consumer.value) {
      throw PluginInstallationException(
        'Plugin $_consumer cannot inspect plugin data owned by ${key.owner}.',
      );
    }
    final snapshot = _shell._pluginDataForTarget(siteUrl, target);
    return (valid: snapshot.valid, value: snapshot.data.get(key));
  }
}

final class _ShellPluginFreshAccountHost implements PluginFreshAccountHost {
  const _ShellPluginFreshAccountHost(this._shell, this._consumer);

  final ShellController _shell;
  final PluginId _consumer;

  DiscourseUser? _user(String siteUrl) => _shell.freshCurrentUserFor(siteUrl);

  @override
  PluginFreshAccountProfile? profileFor(String siteUrl) {
    final user = _user(siteUrl);
    return user == null
        ? null
        : PluginFreshAccountProfile(staff: user.staff, groups: user.groups);
  }

  @override
  T? recordFor<T extends Object>(String siteUrl, PluginDataKey<T> key) {
    if (key.owner != _consumer.value) {
      throw PluginInstallationException(
        'Plugin $_consumer cannot inspect current-user data owned by '
        '${key.owner}.',
      );
    }
    return _user(siteUrl)?.plugins.get(key);
  }
}

final class _ShellPluginPostHost implements PluginPostHost {
  const _ShellPluginPostHost(this._shell, this._consumer);

  final ShellController _shell;
  final PluginId _consumer;

  @override
  Post? readPost(String siteUrl, int postId) =>
      _shell.store.read<Post>(siteUrl, postId);

  @override
  bool topicArchived(String siteUrl, int topicId) =>
      _shell.store.read<TopicDetail>(siteUrl, topicId)?.archived == true;

  @override
  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int postId,
    PluginDataKey<T> key,
    T? Function(T? held) update,
  ) {
    if (key.owner != _consumer.value) {
      throw PluginInstallationException(
        'Plugin $_consumer cannot update plugin data owned by ${key.owner}.',
      );
    }
    _shell.store.update<Post>(siteUrl, postId, (held) {
      final next = update(held.plugins.get(key));
      return held.withPlugins(held.plugins.withValue(key, next));
    });
    _shell.notifyPluginStateChanged();
  }

  @override
  bool beginWrite(String siteUrl, int postId) =>
      _shell.beginPluginPostWrite(siteUrl, postId);

  @override
  void endWrite(String siteUrl, int postId) =>
      _shell.endPluginPostWrite(siteUrl, postId);

  @override
  bool writeInFlight(String siteUrl, int postId) =>
      _shell.pluginPostWriteInFlight(siteUrl, postId);

  @override
  Future<void> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  }) {
    if (lease is! _ShellPluginSiteLease) {
      throw ArgumentError.value(
        lease,
        'lease',
        'Lease belongs to another host.',
      );
    }
    return _shell.refreshPluginPost(
      siteUrl,
      topicId,
      postId,
      apiKey,
      lease.value,
    );
  }
}

final class _ShellPluginNavigationHost implements PluginNavigationHost {
  const _ShellPluginNavigationHost(this._shell, this._isDisposed);

  final ShellController _shell;
  final bool Function() _isDisposed;

  @override
  Listenable get changes => _shell;

  @override
  List<DiscourseInstance> get instances => _shell.instances;

  @override
  DiscourseInstance? get currentInstance => _shell.currentInstance;

  @override
  bool get forumActive => _shell.rootMode == ShellRootMode.forum;

  @override
  bool get isDisposed => _isDisposed();

  @override
  ContentRoute? get currentContent => _shell.currentContent;

  @override
  List<ContentRoute> get contentStack => _shell.contentStack;

  @override
  NotificationTotals? get currentTotals => _shell.currentTotals;

  @override
  PluginVisibleTopicContext? get visibleTopicContext =>
      _shell.visibleTopicContext;

  @override
  Rect? get floatingComposerBounds => _shell.floatingComposerBounds;

  @override
  void selectInstance(int index) => _shell.selectInstance(index);

  @override
  void selectDestination(SidebarDestination destination) =>
      _shell.selectDestination(destination);

  @override
  void pushContent(ContentRoute route) => _shell.pushContent(route);

  @override
  void replaceCurrentContent(ContentRoute route) =>
      _shell.replaceCurrentContent(route);

  @override
  void showPluginContent() => _shell.showPluginContent();

  @override
  bool activatePluginPane(PluginId owner) => _shell.activatePluginPane(owner);

  @override
  void deactivatePluginPane(PluginId owner) =>
      _shell.deactivatePluginPane(owner);
}

final class _ShellPluginRouteNavigationHost
    implements PluginRouteNavigationHost {
  const _ShellPluginRouteNavigationHost(this._shell);

  final ShellController _shell;

  @override
  List<PluginRouteSite> get sites => List.unmodifiable([
    for (final instance in _shell.instances)
      PluginRouteSite(
        url: instance.url,
        title: instance.title,
        isConnected: instance.isConnected,
      ),
  ]);

  @override
  PluginRouteSite? get currentSite {
    final instance = _shell.currentInstance;
    return instance == null
        ? null
        : PluginRouteSite(
            url: instance.url,
            title: instance.title,
            isConnected: instance.isConnected,
          );
  }

  @override
  ContentRoute? get currentContent => _shell.currentContent;

  @override
  void selectInstance(int index) => _shell.selectInstance(index);

  @override
  void pushContent(ContentRoute route) => _shell.pushContent(route);

  @override
  void replaceCurrentContent(ContentRoute route) =>
      _shell.replaceCurrentContent(route);

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
  }) => _shell.openTopicPost(
    siteUrl: siteUrl,
    topicId: topicId,
    postNumber: postNumber,
  );
}

final class _ShellPluginTopicListNavigationHost
    implements PluginTopicListNavigationHost {
  const _ShellPluginTopicListNavigationHost(this._shell);

  final ShellController _shell;

  @override
  void openTopicList(ContentRoute route) {
    if (route.feedPath == null || _shell.currentContent?.id == route.id) return;
    _shell.pushContent(route);
    unawaited(_shell.loadFeed(route.id));
  }
}

final class _ShellPluginBookmarkHostFactory
    implements PluginBookmarkHostFactory {
  const _ShellPluginBookmarkHostFactory(this._shell);

  final ShellController _shell;

  PluginBookmarkHostFactory scopedTo(PluginId consumer) =>
      _ShellScopedPluginBookmarkHostFactory(_shell, consumer);

  @override
  PluginBookmarkHost forTarget(BookmarkTargetType targetType) =>
      throw StateError(
        'The bookmark host factory must be scoped to a plugin session.',
      );
}

final class _ShellScopedPluginBookmarkHostFactory
    implements PluginBookmarkHostFactory {
  const _ShellScopedPluginBookmarkHostFactory(this._shell, this._consumer);

  final ShellController _shell;
  final PluginId _consumer;

  @override
  PluginBookmarkHost forTarget(BookmarkTargetType targetType) {
    if (targetType.owner != _consumer) {
      throw PluginInstallationException(
        'Plugin $_consumer cannot request bookmark target ${targetType.id}.',
      );
    }
    return _shell._pluginBookmarkTargetHost(targetType);
  }
}

final class _ShellCoreBookmarkTargetHost implements BookmarkTargetHost {
  _ShellCoreBookmarkTargetHost(this._shell, this._targetType);

  final ShellController _shell;
  final BookmarkTargetType _targetType;
  final Map<
    ({String siteUrl, int topicId, int targetId}),
    _BookmarkWriteListenable
  >
  _writeListenables = {};

  bool _owns(Bookmark bookmark) =>
      _shell._bookmarkTargetFor(bookmark) == _targetType;

  BookmarkWriteResult _foreignBookmark() => BookmarkWriteResult.refused(
    'This bookmark does not belong to ${_targetType.refreshLabel}.',
  );

  @override
  BookmarkSiteContext siteContextFor(String siteUrl) {
    final user = _shell.currentUserFor(siteUrl);
    final config = _shell.siteConfigFor(siteUrl);
    return BookmarkSiteContext(
      username: user?.username,
      timezone: user?.timezone,
      suggestWeekendsInDatePickers: config.suggestWeekendsInDatePickers,
    );
  }

  @override
  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int topicId,
    required int targetId,
  }) => _shell.bookmarkWriteInFlight(
    siteUrl: siteUrl,
    topicId: topicId,
    targetType: _targetType,
    targetId: targetId,
  );

  @override
  ValueListenable<bool> bookmarkWriteInFlightListenable({
    required String siteUrl,
    required int topicId,
    required int targetId,
  }) {
    final key = (siteUrl: siteUrl, topicId: topicId, targetId: targetId);
    return _writeListenables.putIfAbsent(
      key,
      () => _BookmarkWriteListenable(
        _shell,
        () => bookmarkWriteInFlight(
          siteUrl: siteUrl,
          topicId: topicId,
          targetId: targetId,
        ),
      ),
    );
  }

  @override
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int topicId,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _shell.createBookmark(
    siteUrl: siteUrl,
    topicId: topicId,
    targetType: _targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  @override
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell.updateBookmark(
      siteUrl: siteUrl,
      topicId: topicId,
      bookmark: bookmark,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell.clearBookmarkReminder(
      siteUrl: siteUrl,
      topicId: topicId,
      bookmark: bookmark,
    );
  }

  @override
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell.deleteBookmark(
      siteUrl: siteUrl,
      topicId: topicId,
      bookmark: bookmark,
    );
  }

  void dispose() {
    for (final listenable in _writeListenables.values) {
      listenable.dispose();
    }
    _writeListenables.clear();
  }
}

final class _ShellPluginBookmarkTargetHost implements PluginBookmarkHost {
  _ShellPluginBookmarkTargetHost(this._shell, this._targetType);

  final ShellController _shell;
  final BookmarkTargetType _targetType;
  final Map<({String siteUrl, int targetId}), _BookmarkWriteListenable>
  _writeListenables = {};

  bool _owns(Bookmark bookmark) =>
      _shell._bookmarkTargetFor(bookmark) == _targetType;

  BookmarkWriteResult _foreignBookmark() => BookmarkWriteResult.refused(
    'This bookmark does not belong to ${_targetType.refreshLabel}.',
  );

  @override
  BookmarkSiteContext siteContextFor(String siteUrl) {
    final user = _shell.currentUserFor(siteUrl);
    final config = _shell.siteConfigFor(siteUrl);
    return BookmarkSiteContext(
      username: user?.username,
      timezone: user?.timezone,
      suggestWeekendsInDatePickers: config.suggestWeekendsInDatePickers,
    );
  }

  @override
  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int targetId,
  }) => _shell._pluginBookmarkWriteInFlight(
    siteUrl: siteUrl,
    targetType: _targetType,
    targetId: targetId,
  );

  @override
  ValueListenable<bool> bookmarkWriteInFlightListenable({
    required String siteUrl,
    required int targetId,
  }) {
    final key = (siteUrl: siteUrl, targetId: targetId);
    return _writeListenables.putIfAbsent(
      key,
      () => _BookmarkWriteListenable(
        _shell,
        () => bookmarkWriteInFlight(siteUrl: siteUrl, targetId: targetId),
      ),
    );
  }

  @override
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => _shell._createBookmark(
    siteUrl: siteUrl,
    context: _pluginBookmarkWriteContext,
    targetType: _targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  @override
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell._updateBookmark(
      siteUrl: siteUrl,
      context: _pluginBookmarkWriteContext,
      bookmark: bookmark,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell._updateBookmark(
      siteUrl: siteUrl,
      context: _pluginBookmarkWriteContext,
      bookmark: bookmark,
      name: bookmark.name,
      autoDeletePreference: bookmark.autoDeletePreference,
    );
  }

  @override
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required Bookmark bookmark,
  }) {
    if (!_owns(bookmark)) return Future.value(_foreignBookmark());
    return _shell._deleteBookmark(
      siteUrl: siteUrl,
      context: _pluginBookmarkWriteContext,
      bookmark: bookmark,
    );
  }

  void dispose() {
    for (final listenable in _writeListenables.values) {
      listenable.dispose();
    }
    _writeListenables.clear();
  }
}

final class _BookmarkWriteListenable extends ChangeNotifier
    implements ValueListenable<bool> {
  _BookmarkWriteListenable(Listenable source, bool Function() read)
    : _source = source,
      _read = read,
      _value = read() {
    _source.addListener(_refresh);
  }

  final Listenable _source;
  final bool Function() _read;
  bool _value;

  @override
  bool get value => _value;

  void _refresh() {
    final next = _read();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _source.removeListener(_refresh);
    super.dispose();
  }
}

final class _ShellPluginNotificationFeedHost
    implements PluginNotificationFeedHost {
  const _ShellPluginNotificationFeedHost(this._shell);

  final ShellController _shell;

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) =>
      _shell.notificationFeedListenable(id);

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) => _shell.notificationFeedFor(id, siteUrl);

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) => _shell.loadPluginNotificationFeed(siteUrl, source);

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) => _shell.dismissPluginNotifications(siteUrl, source);

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => _shell.readPluginNotification(siteUrl, notification);

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      _shell.pluginAbsoluteUrl(path, siteUrl: siteUrl);

  @override
  Future<bool> openPluginNotificationUrl(String url) =>
      _shell.openPluginNotificationUrl(url);
}

final class _ShellScopedPluginNotificationFeedHost
    implements PluginNotificationFeedHost {
  const _ShellScopedPluginNotificationFeedHost(
    this._host,
    this._consumer,
    this._sources,
  );

  final PluginNotificationFeedHost _host;
  final PluginId _consumer;
  final Map<PluginNotificationFeedId, PluginNotificationFeedSource> _sources;

  PluginNotificationFeedSource _requireDeclared(PluginNotificationFeedId id) {
    final source = _sources[id];
    if (source != null) return source;
    final reason = id.owner == _consumer
        ? 'did not register notification feed'
        : 'cannot access notification feed';
    throw PluginInstallationException('Plugin $_consumer $reason ${id.id}.');
  }

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) {
    _requireDeclared(id);
    return _host.notificationFeedListenable(id);
  }

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) {
    _requireDeclared(id);
    return _host.notificationFeedFor(id, siteUrl);
  }

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) {
    final registered = _requireDeclared(source.id);
    if (registered != source) {
      throw PluginInstallationException(
        'Plugin $_consumer must use its registered notification feed '
        '${source.id.id}.',
      );
    }
    return _host.loadPluginNotificationFeed(siteUrl, registered);
  }

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) {
    final registered = _requireDeclared(source.id);
    if (registered != source) {
      throw PluginInstallationException(
        'Plugin $_consumer must use its registered notification feed '
        '${source.id.id}.',
      );
    }
    if (registered.dismissal == null) {
      throw PluginInstallationException(
        'Plugin $_consumer did not register dismissal for notification feed '
        '${source.id.id}.',
      );
    }
    return _host.dismissPluginNotifications(siteUrl, registered);
  }

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => _host.readPluginNotification(siteUrl, notification);

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      _host.pluginAbsoluteUrl(path, siteUrl: siteUrl);

  @override
  Future<bool> openPluginNotificationUrl(String url) =>
      _host.openPluginNotificationUrl(url);
}

final class _QueuedTopicNotification {
  _QueuedTopicNotification({
    required this.siteUrl,
    required this.topicId,
    required this.level,
    required this.revision,
    required this.lease,
  });

  final String siteUrl;
  final int topicId;
  final TopicNotificationLevel level;
  final int revision;
  final SiteLease lease;
  final Completer<bool> result = Completer<bool>();

  void complete(bool succeeded) {
    if (!result.isCompleted) result.complete(succeeded);
  }
}
