import 'dart:async';
// Only for the category badge colour a list route carries; the shell otherwise
// has no opinion about how anything is painted.
import 'dart:ui' show Color;

import 'package:flutter/scheduler.dart';

import '../data/aggregate_preferences_store.dart';
import '../data/authenticator.dart';
import '../data/discourse_api.dart';
import '../data/draft_store.dart';
import '../data/emoji_picker_store.dart';
import '../data/forum_tab_store.dart';
import '../data/http_transport.dart';
import '../data/instance_store.dart';
import '../data/site_image_repository.dart';
import '../data/site_lifecycle.dart';
import '../data/site_tracker.dart';
import '../data/store.dart';
import '../data/update_store.dart';
import '../data/updater.dart';
import '../data/user_api_key.dart';
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
import '../models/forum_workspace.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/list_link.dart';
import '../models/notification.dart';
import '../models/notification_feed.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/post_flag.dart';
import '../models/post_likers.dart';
import '../models/search_results.dart';
import '../models/sidebar.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../models/topic_filter.dart';
import '../models/topic_link.dart';
import '../models/user_card.dart';
import '../models/user_draft.dart';
import '../models/user_preferences.dart';
import '../models/user_status.dart';
import '../models/user_summary.dart';
import '../plugin_api/core_plugin_host.dart';
import '../plugin_api/core_plugin_manifest.dart';
import '../plugin_api/plugin_data.dart';
import '../plugin_api/plugin_runtime.dart';
import '../plugin_api/shell_extensions.dart';
import '../theme/d_icons.dart';
import 'account_activity_controller.dart';
import 'aggregate_feed_controller.dart';
import 'composer_autocomplete.dart';
import 'composer_controller.dart';
import 'composer_pills.dart';
import 'composer_quotes.dart';
import 'composer_triggers.dart';
import 'draft_list_controller.dart';
import 'post_quote.dart';
import 'preferences_controller.dart';
import 'shell_search_controller.dart';
import 'site_presentation_controller.dart';
import 'site_url.dart';
import 'topic_feed_controller.dart';
import 'topic_read_controller.dart';
import 'update_controller.dart';
import 'user_summary_controller.dart';

/// Which pane occupies the space next to the rail when the shell is compact.
///
/// Only one of them can be on screen at a time on a phone; the rail itself is
/// always visible alongside whichever one is showing.
enum MobilePane { sidebar, content }

/// Which app-wide surface owns the space to the right of the forum rail.
enum ShellRootMode { forum, aggregate }

enum InstanceLoadStatus { loading, ready, failed }

enum AggregateTopicOpenResult { opened, tabLimitReached, unavailable }

typedef TopicMoveDestination = ({int id, String title, String slug});
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

/// The confirmed result of a bookmark mutation, or why it was not applied.
final class BookmarkWriteResult {
  const BookmarkWriteResult.saved([this.bookmark])
    : message = null,
      reconciled = false;

  const BookmarkWriteResult.refused(this.message)
    : bookmark = null,
      reconciled = false;

  const BookmarkWriteResult.reconciled(this.message)
    : bookmark = null,
      reconciled = true;

  final Bookmark? bookmark;
  final String? message;
  final bool reconciled;

  bool get saved => message == null;
}

/// Everything the shell needs to decide what to draw.
///
/// Uses Flutter's notifier contract directly, without a state-management
/// dependency. [FrameSafeNotifier] only centralizes disposal and frame timing.
class ShellController extends FrameSafeNotifier
    implements PluginNavigationHost {
  ShellController({
    required this.instanceStore,
    required this.api,
    required this.authenticator,
    required this.drafts,
    EmojiPickerStore? emojiPickerStore,
    AggregatePreferencesStore? aggregatePreferences,
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
    ShellRootMode initialRootMode = ShellRootMode.forum,
    InstalledPlugins? plugins,
  }) : forumTabs = forumTabs ?? ForumTabStore.memory(),
       aggregatePreferences =
           aggregatePreferences ?? AggregatePreferencesStore(),
       emojiPickerStore = emojiPickerStore ?? EmojiPickerStore(),
       assert(topicLoadTimeout > Duration.zero),
       assert(anchorPersistDebounce >= Duration.zero),
       store = store ?? Store(),
       lifecycle = lifecycle ?? SiteLifecycle(),
       _providedSiteImages = siteImages,
       _rootMode = initialRootMode,
       _ownsPlugins = plugins == null,
       plugins = plugins ?? PluginInstaller.install(corePluginManifest),
       updates = UpdateController(
         updater: updater,
         store: updateStore ?? UpdateStore(),
       );

  final InstanceStore instanceStore;
  final ForumTabStore forumTabs;
  final AggregatePreferencesStore aggregatePreferences;

  /// Whether the platform exposes the forum tab lifecycle.
  ///
  /// Mobile still uses one internal navigation context so the rest of the
  /// shell can share the same routing code, but it can never accumulate tabs.
  final bool forumTabsEnabled;

  /// The identity map. Every topic, post, category and user card the app holds
  /// lives here once, and the maps in this class hold ids into it — so a list,
  /// a topic being read and a card popup are all drawing the same records
  /// rather than copies that have to be kept in step by hand.
  final Store store;

  final DiscourseApi api;

  /// Whether disposing this controller also closes [api].
  ///
  /// The app state keeps this false because it may move one API between
  /// controller generations when another injected dependency changes.
  final bool ownsApi;

  /// Maximum wall-clock time spent getting a topic onto the screen.
  ///
  /// The HTTP transport has its own deadline, but a topic can wait before it
  /// reaches that boundary: credential storage crosses a platform channel and
  /// the request coordinator may queue work behind an origin cooldown. Bound
  /// both waits so neither can leave the topic loading state alive
  /// indefinitely.
  final Duration topicLoadTimeout;

  /// How long scroll-anchor churn may remain memory-only before it is written.
  ///
  /// Scrolling emits one anchor change per top row or top post, and each
  /// persisted write serialises every workspace synchronously on the UI
  /// isolate. Zero still coalesces a synchronous burst into one write.
  final Duration anchorPersistDebounce;

  final Authenticator authenticator;
  final DraftStore drafts;
  final EmojiPickerStore emojiPickerStore;
  final SiteLifecycle lifecycle;
  final SiteImageRepository? _providedSiteImages;
  final InstalledPlugins plugins;
  final bool _ownsPlugins;

  late final SiteImageRepository siteImages =
      _providedSiteImages ??
      SiteImageRepository(credentials: authenticator, lifecycle: lifecycle);

  late final PluginSession _pluginSession = plugins.openSession(
    PluginHostBindings(<PluginHostPort<Object>>[
      PluginHostPort<Object>(
        corePluginHostPort,
        CorePluginHost(
          api: api,
          credentials: authenticator,
          store: store,
          siteLifecycle: lifecycle,
          currentUserFor: (siteUrl) => _instanceAt(siteUrl)?.user,
          siteConfigFor: siteConfigFor,
          previewEngine: plugins.registry.chatPreviewEngine,
          applyNotificationDelta: (siteUrl, delta) {
            accountActivity.applyCounts(
              siteUrl,
              (held) => held.withChatNotificationsDelta(delta),
            );
          },
          markSiteUnreachable: _markForumUnavailable,
          canPerform: (siteUrl, capability, recordPermission) =>
              switch (capability) {
                'assign' => canAssignForTarget(siteUrl, recordPermission),
                _ => false,
              },
          dataForTarget: _pluginDataForTarget,
          reloadTopic: (siteUrl, topicId) =>
              _refetchTopic(siteUrl, topicId, ''),
          invalidateFallback: (siteUrl, capability) {
            if (capability == 'assign') {
              _assignLegacyFallbackUnavailable.add(siteUrl);
              _notify();
            }
          },
          trackerFor: (siteUrl) => _trackers[siteUrl],
          userIdFor: (siteUrl) => _instanceAt(siteUrl)?.user?.id,
          capabilityEnabledFor: (siteUrl, capability) async =>
              switch (capability) {
                'resenha' => (await _presentation.resolveConfig(
                  siteUrl,
                ))?.resenha.enabled,
                _ => null,
              },
          onCallSiteChanged: _syncTracking,
          navigation: this,
        ),
      ),
    ]),
  );

  /// The installed feature services for this shell lifetime.
  ///
  /// Exposed as one typed lookup boundary for [PluginScope], not as a second
  /// shell controller API.
  PluginSession get pluginSession => _pluginSession;

  String? get _pluginBackgroundSiteUrl => _pluginSession
      .capabilities<PluginBackgroundSite>()
      .map((capability) => capability.pluginBackgroundSiteUrl)
      .whereType<String>()
      .firstOrNull;

  /// Neutral write coordination available to plugin-owned interaction APIs.
  ///
  /// Core owns serialization with its own post writes and session invalidation;
  /// plugins own their payload types, endpoints, optimistic transforms, and
  /// typed results.
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

  /// Reads one asynchronous session input without letting its stale answer
  /// reach a later network dispatch.
  ///
  /// A credential store can suspend on a platform channel. In that gap the
  /// account may be forgotten and a new lifecycle generation may start for
  /// the same URL, so checking only when the eventual response is committed is
  /// too late: the obsolete credential has already been sent. The record
  /// wrapper distinguishes a current nullable value (a signed-out API key)
  /// from an invalidated read.
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

  /// Opens a site's live connection. See [SiteTrackerFactory].
  final SiteTrackerFactory trackers;

  /// Updating the app itself.
  ///
  /// Its own notifier rather than state on this class, so that download
  /// progress does not rebuild the whole shell, and so that it stays meaningful
  /// with no sites connected. Reached through a `ListenableBuilder`, the way
  /// [ComposerController] is. See [UpdateController].
  final UpdateController updates;

  /// Notifications, bookmarks, and account counters for every connected site.
  ///
  /// This state changes independently from navigation, so widgets that show it
  /// listen here instead of invalidating every [ShellScope] dependent.
  late final AccountActivityController accountActivity =
      AccountActivityController(
        api: api,
        credentials: authenticator,
        lifecycle: lifecycle,
        onTotalsLoaded: _onTotalsLoaded,
      );

  /// The connected account's server-side drafts for the full-page destination.
  late final DraftListController draftList = DraftListController(
    api: api,
    credentials: authenticator,
    lifecycle: lifecycle,
  );

  /// The connected account's profile summary, independent from shell-wide
  /// navigation so refreshes do not rebuild the rail or inactive tabs.
  late final UserSummaryController userSummary = UserSummaryController(
    api: api,
    credentials: authenticator,
    lifecycle: lifecycle,
  );

  /// The connected account's server-owned preferences.
  ///
  /// Form edits and network progress remain on this independent notifier so
  /// typing in Preferences cannot rebuild the rail, sidebar, or topic view.
  late final PreferencesController preferences = PreferencesController(
    api: api,
    credentials: authenticator,
    lifecycle: lifecycle,
    onSaved: _onPreferencesSaved,
  );

  /// Topic-list snapshots and their competing refresh/page requests.
  ///
  /// Feed state has its own notification boundary. Widgets that render it
  /// listen here directly; shell listeners remain about navigation and other
  /// shell-owned state.
  late final TopicFeedController topicFeeds = _createTopicFeedController();

  /// Topics returned by each selected forum's saved Discourse filter query.
  ///
  /// Its notifier is intentionally independent: paging this global list
  /// should not rebuild the rail, sidebar, forum tabs, or inactive topics.
  late final AggregateFeedController aggregate = AggregateFeedController(
    api: api,
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
      api: api,
      credentials: authenticator,
      lifecycle: lifecycle,
      store: store,
      onFeedLoaded: (instance, _) {
        unawaited(_ensureCategoriesFor(instance));
      },
      readPersonalizationVersion: _siteBookmarkVersion,
      prepareTopicForStore: _prepareTopicForStore,
    );
  }

  /// Optimistic topic read positions and their serialized server receipts.
  late final TopicReadController _topicReads = TopicReadController(
    api: api,
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

  /// The one global, transient search interaction. Its notifier is consumed by
  /// the field and result panel alone, so typing never redraws the shell.
  late final ShellSearchController search = ShellSearchController(
    api: api,
    credentials: authenticator,
    lifecycle: lifecycle,
  );

  SitePresentationController? _sitePresentation;

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
    return api.siteAppearance(
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
    return api.siteConfig(
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
    return api.customEmojis(
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
    return api.emojiCatalog(
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
    return api.emojiSearchAliases(
      siteUrl: siteUrl,
      apiKey: authenticate ? apiKey : null,
      clientId: authenticate ? clientId : null,
    );
  }

  String? _connectingSiteUrl;

  /// True while the authorize flow is open, so the UI can show progress.
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

  /// Retries the plugin-owned route whose failure replaced this workspace.
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

  /// Offers [url] to installed session features in manifest order.
  Future<bool> openPluginUrl(String url) async {
    for (final handler in _pluginSession.capabilities<PluginLinkHandler>()) {
      if (await handler.openPluginUrl(url)) return true;
    }
    return false;
  }

  /// Opens a trusted notification target only when it is a safe URL owned by a
  /// connected forum and the app has an internal route for it.
  ///
  /// Notification taps never fall back to the external browser: an unknown
  /// route or forum is ignored instead of letting server-supplied data launch
  /// another application.
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
    if (await openPluginUrl(absolute)) return true;
    if (_openTopicUrl(absolute, refresh: true)) return true;
    return openListUrl(absolute);
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

  /// False until the stored sites have been read, so the shell can avoid
  /// flashing the empty state on launch.
  bool get loaded => _loadStatus == InstanceLoadStatus.ready;

  int _instanceIndex = 0;
  int get instanceIndex => _instanceIndex;
  @override
  DiscourseInstance? get currentInstance =>
      hasInstances ? _instances[_instanceIndex] : null;

  final Map<String, ForumWorkspace> _forumWorkspaces = {};
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

  /// Id of the sidebar destination at the root of the active tab.
  String? get destinationId => activeTab?.rootDestinationId;

  /// Navigation within the active tab. Inactive tabs retain their own stack.
  @override
  List<ContentRoute> get contentStack => activeTab?.contentStack ?? const [];
  @override
  ContentRoute? get currentContent => activeTab?.currentContent;
  bool get canPopContent => (activeTab?.contentStack.length ?? 0) > 1;

  MobilePane _mobilePane = MobilePane.sidebar;
  MobilePane get mobilePane => _mobilePane;

  ShellRootMode _rootMode;
  ShellRootMode get rootMode => _rootMode;

  /// A connected forum looked up by the same canonical origin used in a
  /// cross-forum topic reference.
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
    final workspace = _newWorkspace(instance);
    _forumWorkspaces[instance.url] = workspace;
    if (persist) _persistWorkspaces();
    return workspace;
  }

  void _putWorkspace(ForumWorkspace workspace, {bool persist = true}) {
    final normalized = _normalizeWorkspace(workspace);
    _forumWorkspaces[normalized.siteUrl] = normalized;
    if (persist) _persistWorkspaces();
  }

  void _removeWorkspace(String siteUrl, {bool persist = true}) {
    if (_forumWorkspaces.remove(siteUrl) != null && persist) {
      _persistWorkspaces();
    }
  }

  void _persistWorkspaces() {
    _tabSelectionPersistencePending = false;
    // Any full write already carries the in-memory anchors, so a waiting
    // anchor window has nothing left to add.
    _anchorPersistencePending = false;
    unawaited(forumTabs.save(_forumWorkspaces.values));
  }

  /// Persists scroll anchors once per window instead of once per change.
  ///
  /// A fixed window, deliberately, not a window each change restarts: an
  /// uninterrupted scroll emits anchors continuously, and a restarting window
  /// would defer every write to whenever it happened to stop. What
  /// [anchorPersistDebounce] promises is a bound on how stale the persisted
  /// anchor may be, which only a fixed window gives.
  ///
  /// The active tab is updated before this runs — widgets read anchors from
  /// memory synchronously — and the eventual write serialises that live state,
  /// so the last anchor in a window always wins regardless of how many changes
  /// the window absorbed. Backgrounding and disposal flush the window, so a
  /// pending anchor cannot outlive the process.
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

  /// Writes an anchor still waiting out its debounce window.
  ///
  /// Views call this as their scrolled viewport unmounts: nothing can move
  /// the anchor once the viewport is gone, so the window buys no further
  /// coalescing and holding the write only defers durability.
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
      return;
    }

    if (isDisposed) return;
    _instances
      ..clear()
      ..addAll(stored);
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
    if (_rootMode == ShellRootMode.aggregate && _instances.isNotEmpty) {
      unawaited(aggregate.open(_instances));
    }
    _loadStatus = InstanceLoadStatus.ready;
    _notify();

    // Whether a newer build exists is not something anyone is waiting on, and
    // a failure here has to stay quiet. See UpdateController.check.
    unawaited(updates.load());

    // Refresh only the selected account. The web client asks about the one site
    // being viewed; eagerly hydrating every saved native site multiplied a cold
    // start into six authenticated reads per inactive account. The others are
    // refreshed lazily when selected, while their persisted rail metadata is
    // already enough to draw them.
    unawaited(_refreshAccountState(initialInstance));
  }

  bool contains(String url) => _instances.any((i) => i.url == url);

  /// Appends a connected site and selects it.
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

  /// Moves [instance] to [newIndex] and persists the resulting rail order.
  ///
  /// Reordering is presentation-only: the forum being read, its workspace,
  /// current route and compact-layout pane all stay exactly where they were.
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

  /// Signs [instance] out and takes it out of the rail.
  ///
  /// Returns false when the private-draft boundary or local rail could not be
  /// persisted. A boundary failure leaves the account/key intact; a later rail
  /// failure restores the already-forgotten site as signed out and retryable.
  Future<bool> removeInstance(DiscourseInstance instance) async {
    if (!_instances.contains(instance)) return false;

    final lease = await _revokeAndForget(instance);
    if (lease == null || !lease.isCurrent) return false;

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
    _instances.removeAt(index);
    if (_instances.isEmpty) _rootMode = ShellRootMode.forum;

    if (removingSelected) {
      // The site being read is the one going away, so there is somewhere new
      // to land: whatever took its place, or the end of a shortened rail.
      _instanceIndex = _instances.isEmpty
          ? 0
          : index.clamp(0, _instances.length - 1);
      _restoreInstanceWorkspace();
    } else {
      // Removing a site the user is not looking at must not cost them their
      // place, so follow the selected one to wherever the removal left it
      // rather than resetting to its default destination.
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

  /// Counters for the site on screen — what the user menu's tabs show, and
  /// what puts the dot on the avatar that opens it.
  @override
  NotificationTotals? get currentTotals {
    final instance = currentInstance;
    return instance == null ? null : accountActivity.totalsFor(instance.url);
  }

  /// Number on the rail for [instance]: things addressed to the user.
  int railBadgeFor(DiscourseInstance instance) =>
      accountActivity.totalsFor(instance.url)?.badge ?? 0;

  /// Number beside a sidebar entry, or 0 when there is nothing to show.
  ///
  /// It comes from the one totals call rather than a request per section.
  int sidebarBadgeFor(String destinationId) {
    if (destinationId == 'drafts') {
      return draftCountFor(currentInstance?.url);
    }
    final totals = currentTotals;
    if (totals == null) return 0;

    return switch (destinationId) {
      'messages' => totals.unreadPersonalMessages,
      _ => 0,
    };
  }

  int draftCountFor(String? siteUrl) {
    if (siteUrl == null) return 0;
    final feed = draftList.feedFor(siteUrl);
    if (feed.totalCount case final count?) return count;
    return _instanceAt(siteUrl)?.user?.draftCount ?? 0;
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

  Future<void> _refreshSessionUserFor(DiscourseInstance instance) async {
    final lease = lifecycle.capture(instance.url);
    try {
      final credential = await _readSessionValue(
        lease,
        () => authenticator.apiKeyFor(instance.url),
      );
      if (credential == null || !lease.isCurrent) return;
      if (credential.value case final apiKey?) {
        await _sessionUser(instance.url, apiKey, lease: lease);
        if (!lease.isCurrent || currentInstance?.url != instance.url) return;
        await _refreshCustomSidebarSections(instance.url, apiKey, lease: lease);
      }
    } catch (_) {
      // Capabilities remain unknown. Persisted values never authorize a poll
      // creation or a group-restricted vote in their place.
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
      final sections = await api.customSidebarSections(
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
      // Custom navigation is optional. Keep the last successful answer, if
      // there was one, and leave the native sidebar usable.
    }
  }

  void _onTotalsLoaded(DiscourseInstance instance, NotificationTotals totals) {
    _notifyPluginTotals(instance, totals);
  }

  void _onPreferencesSaved(
    String siteUrl,
    PreferenceSection section,
    UserPreferences preferences,
  ) {
    if (section != PreferenceSection.datesAndReminders) return;
    final instance = _instanceAt(siteUrl);
    final user = instance?.user;
    if (instance == null ||
        user == null ||
        user.username.toLowerCase() != preferences.username.toLowerCase()) {
      return;
    }
    final updated = user.withPreferences(
      timezone: preferences.timezone,
      bookmarkAutoDeletePreference: preferences.bookmarkAutoDeletePreference,
    );
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

  /// The notifications fetched for [siteUrl].
  NotificationFeed notificationsFor(String siteUrl) =>
      accountActivity.notificationsFor(siteUrl);

  /// Fetches what the user menu's notifications tab lists.
  ///
  /// Called every time the tab appears rather than once per session: a list of
  /// what other people have just done is stale within minutes, and the point of
  /// opening the menu is to see what is new. Only for the site being looked at,
  /// and only when something asks — unlike the counters, which every site in
  /// the rail keeps up to date.
  ///
  /// A refresh happens underneath whatever is already on screen. Only the first
  /// fetch, and one after a failure, gets to replace the tab with a spinner.
  Future<void> loadNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadNotifications(instance);
  }

  /// The filtered reply notifications fetched for [siteUrl].
  NotificationFeed replyNotificationsFor(String siteUrl) =>
      accountActivity.replyNotificationsFor(siteUrl);

  /// Fetches what the user menu's Replies tab lists.
  ///
  /// Kept apart from [loadNotifications] because both endpoints have their own
  /// thirty-row budget, cache and request lifetime even though they return the
  /// same kind of row.
  Future<void> loadReplyNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadReplyNotifications(instance);
    }
  }

  /// The filtered chat notifications fetched for [siteUrl].
  NotificationFeed chatNotificationsFor(String siteUrl) =>
      accountActivity.chatNotificationsFor(siteUrl);

  /// Fetches what the user menu's Chat tab lists.
  ///
  /// This is separate from both the general and Replies feeds so opening any
  /// one tab cannot replace another tab's cache or consume its row budget.
  Future<void> loadChatNotifications(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      await accountActivity.loadChatNotifications(instance);
    }
  }

  /// Marks [notification] read, which is what opening it amounts to here.
  ///
  /// Where it then leads is [DiscourseNotification.path], handled the same way
  /// as any other link — see `NotificationSection`. Called from the bookmarks
  /// tab too, whose reminders are notifications like any other.
  void readNotification(String siteUrl, DiscourseNotification notification) {
    final instance = _instanceAt(siteUrl);
    if (instance != null) {
      accountActivity.readNotification(instance, notification);
    }
  }

  /// The bookmarks fetched for [siteUrl].
  BookmarkFeed bookmarksFor(String siteUrl) =>
      accountActivity.bookmarksFor(siteUrl);

  /// Fetches what the user menu's bookmarks tab lists.
  ///
  /// Refetched every time the tab appears, for the same reason as
  /// [loadNotifications]: a reminder that came due while the menu was shut is
  /// the whole point of opening it, and bookmarks are cheap to ask for.
  ///
  /// Signed out there is nothing to ask — the route is the account's own, and
  /// names it — so the tab is left empty rather than showing a failure the
  /// reader can do nothing about from here.
  Future<void> loadBookmarks(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await accountActivity.loadBookmarks(instance);
  }

  /// Sites whose category list has been fetched. The categories themselves are
  /// in the store; this only remembers not to ask again.
  final Set<String> _categorised = {};
  final Map<String, List<TopicCategory>> _categoriesBySite = {};
  final Map<String, CategoryFeed> _categoryFeeds = {};
  final Map<String, _CategorySidebarCache> _categorySidebarCache = {};
  final Map<String, TopicComposerCapabilities> _topicComposerCapabilities = {};
  final Map<String, SitePostActionCatalog> _postActionCatalogs = {};

  /// Flag metadata in the order supplied by this site's `/site.json`.
  List<PostFlagType> postFlagTypesFor(String siteUrl) =>
      _postActionCatalogs[siteUrl]?.postFlags ?? const [];

  /// The flag reasons both the site catalog and this personalized post allow.
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

  /// Topic-specific reasons both the catalog and this topic summary permit.
  ///
  /// Core localizes these separately from post reasons and the topic's
  /// top-level `actions_summary` is the personalized authority for each id.
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

  /// The list currently filling the main region, if the destination has one.
  /// Which feed the main region is showing.
  ///
  /// A route that brought its own list — a category or tag opened from a
  /// hashtag — answers for itself; everything else is the sidebar destination
  /// that is selected. Deliberately not [destinationId] alone: a hashtag is
  /// pushed *over* whatever list it was read from, and that list stays
  /// selected in the sidebar so back still means something.
  String? get currentFeedId {
    final route = currentContent;
    if (route != null && route.feedPath != null) return route.id;
    return destinationId;
  }

  TopicFeed? get currentFeed {
    final instance = currentInstance;
    final feedId = currentFeedId;
    if (instance == null || feedId == null) return null;
    return topicFeeds.feedFor(instance.url, feedId);
  }

  bool get canCreateTopicHere {
    if (currentContent?.isTopic != false || currentFeedId == 'messages') {
      return false;
    }
    final instance = currentInstance;
    if (currentContent?.id == 'all-categories' && instance != null) {
      return categoryFeedFor(instance.url).canCreateTopic;
    }
    return currentFeed?.canCreateTopic ?? false;
  }

  CategoryFeed categoryFeedFor(String siteUrl) =>
      _categoryFeeds[siteUrl] ?? const CategoryFeed();

  List<TopicCategory> topicComposerCategories(String siteUrl) =>
      _categoriesBySite[siteUrl] ?? const [];

  /// The built-in Categories section once this site's category list arrives.
  ///
  /// The cache is presentation identity as well as saved work: the sidebar
  /// selector compares sections by identity so unrelated shell notifications
  /// do not rebuild the whole navigation column.
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

  TopicComposerCapabilities topicComposerCapabilities(String siteUrl) =>
      _topicComposerCapabilities[siteUrl] ?? const TopicComposerCapabilities();

  /// Category badge for a topic, once categories have been fetched.
  TopicCategory? categoryFor(int? categoryId, {String? siteUrl}) {
    final sourceSite = siteUrl ?? currentInstance?.url;
    if (sourceSite == null || categoryId == null) return null;
    return store.read<TopicCategory>(sourceSite, categoryId);
  }

  /// The topic behind a row, watched rather than read.
  ///
  /// The list holds ids, so this is how a row gets its topic — and why editing
  /// a topic anywhere redraws that row and nothing else.
  Ref<Topic> topicRef(String siteUrl, int topicId) =>
      store.ref<Topic>(siteUrl, topicId);

  Ref<TopicCategory> categoryRef(String siteUrl, int categoryId) =>
      store.ref<TopicCategory>(siteUrl, categoryId);

  Ref<Post> postRef(String siteUrl, int postId) =>
      store.ref<Post>(siteUrl, postId);

  /// Where [feedId]'s list lives, or null when there is none to fetch
  /// (messages needs a signed-in user to name the inbox).
  ///
  /// Routes that carry their own path are looked up first, and from the *stack*
  /// rather than from a map of their own: a category route exists exactly as
  /// long as it is open, and giving it a second home to be evicted from would
  /// be one more thing to keep in step with the back button.
  String? _feedPath(String feedId, DiscourseInstance instance) {
    for (final route in contentStack.reversed) {
      if (route.id == feedId && route.feedPath != null) return route.feedPath;
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
        '/topics/private-messages/$username.json',
      _ => null,
    };
  }

  /// Fetches the list for [destinationId] unless it is already in hand.
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

  /// Submits the text on the Filter destination. Editing the field alone does
  /// not call this; core only refreshes its list on Enter or clear.
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
    (apiKey, clientId) => api.searchFilterTags(
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
    (apiKey, clientId) => api.searchFilterTagGroups(
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
        : api.searchFilterGroups(
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
      for (final user in await api.searchUsers(
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

  /// The row at the top of [destinationId]'s list when the user last saw it.
  ///
  /// Opening a topic replaces the list rather than covering it, so the list
  /// widget — and its scroll position with it — is torn down. Remembering the
  /// row here is what lets going back land where they left off.
  ///
  /// A row rather than an offset: a remounted list has measured none of the
  /// rows above the viewport, so a saved pixel offset is restored against a
  /// guess at their heights and lands short. Rows survive that, and landing at
  /// the top of the row you were halfway through is what the reader wanted
  /// anyway.
  int feedScrollRow(String destinationId) {
    final instance = currentInstance;
    if (instance == null) return 0;
    final anchor = activeTab?.anchors[destinationId];
    if (anchor?.kind == 'feed') return anchor!.itemId;
    return 0;
  }

  /// Records the list position. Deliberately silent: nothing on screen depends
  /// on it, and it is written as the list scrolls.
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

  /// The post a remounted topic tab should reveal.
  ///
  /// A viewport anchor supersedes the route's original deep-link target after
  /// the reader has moved through the topic.
  int? topicScrollPostNumber(int topicId) {
    final tab = activeTab;
    final route = currentContent;
    if (tab == null || route?.topicId != topicId) return null;
    final anchor = tab.anchors[route!.id];
    if (anchor?.kind == 'topic') return anchor!.itemId;
    return route.postNumber;
  }

  /// Where the remembered post's leading edge sat relative to the viewport.
  ///
  /// This is usually zero or negative. Keeping it separately from the post
  /// number matters for posts taller than the viewport: revealing only their
  /// number would always reopen them at the beginning.
  double topicScrollPostOffset(int topicId) {
    final tab = activeTab;
    final route = currentContent;
    if (tab == null || route?.topicId != topicId) return 0;
    final anchor = tab.anchors[route!.id];
    return anchor?.kind == 'topic' ? anchor!.offset : 0;
  }

  /// Records the first visible post for the active topic tab.
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

  /// Sites whose account was read from `/session/current.json` during this
  /// process. Persisted capabilities are intentionally never put in this set.
  final Set<String> _sessionUsersRefreshed = {};
  final Set<String> _assignLegacyFallbackUnavailable = {};

  /// Deduplicates tracker startup with account refreshes and rapid lifecycle
  /// changes.
  final Map<String, Future<DiscourseUser?>> _sessionUserRequests = {};

  bool _foreground = true;

  /// How many topics have appeared at the top of [destinationId] since it was
  /// fetched. Zero for the lists nothing is tracked for — see `IncomingTopics`.
  int incomingCount(String destinationId) {
    final instance = currentInstance;
    if (instance == null) return 0;
    return _trackers[instance.url]?.incoming.count(destinationId) ?? 0;
  }

  /// Fetches the topics the banner is counting and puts them at the top of the
  /// list, which is what tapping it does.
  ///
  /// The same shape as core's `TopicList.loadBefore`: ask the *list* route for
  /// those ids specifically, so each topic arrives in the form that list draws
  /// — with its posters, its unread counts and the list's own ordering — then
  /// drop any copy already held before prepending, since a topic that was
  /// bumped rather than created is already somewhere further down.
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

  /// Keeps every connected site's account counters live while the app is in
  /// front, plus the selected public site for topic-list updates.
  ///
  /// Each forum is a different MessageBus origin, so its rail badge needs its
  /// own poll. Signed-out forums stay lazy unless selected because they have no
  /// private counters to update. All ordinary polls stop with the app lifecycle;
  /// their cursors survive, so foregrounding asks for what was missed.
  void _syncTracking() {
    final instance = currentInstance;
    final callSiteUrl = _pluginBackgroundSiteUrl;

    for (final entry in _trackers.entries) {
      if (entry.key != instance?.url) entry.value.unwatchTopic();
      final selectedAndVisible = _foreground && entry.key == instance?.url;
      final connectedAndVisible =
          _foreground && (_instanceAt(entry.key)?.isConnected ?? false);
      if (selectedAndVisible ||
          connectedAndVisible ||
          entry.key == callSiteUrl) {
        entry.value.start();
      } else {
        entry.value.stop();
      }
    }
    if (callSiteUrl != null && callSiteUrl != instance?.url) {
      _trackers[callSiteUrl]?.start();
    }
    if (!_foreground) return;

    for (final candidate in _instances) {
      final selected = candidate.url == instance?.url;
      if (!selected && !candidate.isConnected) continue;

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

    if (instance case final selected?) {
      final tracker = _trackers[selected.url];
      if (tracker != null) _syncTopicWatch(selected.url, tracker);
    }
  }

  /// Points the topic-scoped channels at whatever is on screen now.
  ///
  /// Called wherever the content stack moves. A site with no tracker open yet
  /// is left alone — [_syncTracking] does this once the connection is up, and
  /// there is nothing to subscribe on before then.
  void _syncTopicChannels() {
    final instance = currentInstance;
    if (instance == null) return;
    final tracker = _trackers[instance.url];
    if (tracker == null) return;
    _syncTopicWatch(instance.url, tracker);
  }

  /// Points the topic-scoped channels at the topic being read.
  ///
  /// Only what is on screen, and only one at a time: a topic's own updates are
  /// of no use once the reader has left it, and a site's topics cannot all be
  /// subscribed to at once.
  void _syncTopicWatch(String siteUrl, SiteTracker tracker) {
    final topicId = currentContent?.topicId;
    if (topicId == null) {
      tracker.unwatchTopic();
      return;
    }

    final channels = plugins.registry.topicChannels(topicId);
    if (channels.isEmpty) {
      tracker.unwatchTopic();
      return;
    }

    tracker.watchTopic(topicId, channels, (channel, data) {
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

  /// Reads posts a live message said have changed.
  ///
  /// Through `/t/:id/posts.json`, which is the preloaded path — the one whose
  /// counts agree with what the topic was drawn from. A write of this reader's
  /// own is skipped: it has already drawn its guess, and the answer to its own
  /// request is on the way.
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
      final posts = await api.posts(
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
      // Somebody else's reaction not arriving is not worth saying anything
      // about; the next read of the topic settles it.
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

  /// Opens a site's connection, once credential storage has said who we are.
  ///
  /// Signed out this still runs: `/latest` is public, so a reader with no
  /// account still gets the banner.
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
      if (isDisposed || _instanceAt(siteUrl) == null) return;

      // Credential lookup can outlive the lifecycle state that asked for this
      // tracker. SiteTracker starts its message bus in the constructor, so
      // checking only after construction still spends one poll for a hidden
      // app. A voice call remains eligible because its signalling deliberately
      // survives app backgrounding.
      final selectedAndVisible = _foreground && currentInstance?.url == siteUrl;
      final connectedAndVisible =
          _foreground && (_instanceAt(siteUrl)?.isConnected ?? false);
      if (!selectedAndVisible &&
          !connectedAndVisible &&
          _pluginBackgroundSiteUrl != siteUrl) {
        return;
      }

      void commit(SiteMutation mutation) {
        if (!isDisposed) lease.commit(mutation);
      }

      final SiteTracker tracker;
      try {
        tracker = trackers(
          siteUrl: siteUrl,
          userId: userId,
          apiKey: apiKey,
          clientId: clientId,
          shouldLongPoll: () => _foreground,
          onIncomingTopics: () => commit(() {
            if (currentInstance?.url == siteUrl) _notify();
          }),
          onNotifications: (data) => commit(
            () => _applyCounts(siteUrl, (held) => held.withNotification(data)),
          ),
          onReviewableCounts: (data) => commit(
            () => _applyCounts(
              siteUrl,
              (held) => held.withReviewableCounts(data),
            ),
          ),
        );
      } catch (error, stackTrace) {
        _reportOperationalError(error, stackTrace, 'messageBus.start');
        return;
      }
      _trackers[siteUrl] = tracker;
      if (apiKey != null) {
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
      }
      for (final attachment
          in _pluginSession.capabilities<PluginTrackerAttachment>()) {
        attachment.attachPluginTracker(siteUrl, tracker);
      }
      final stillSelectedAndVisible =
          _foreground && currentInstance?.url == siteUrl;
      final stillConnectedAndVisible =
          _foreground && (_instanceAt(siteUrl)?.isConnected ?? false);
      if (!stillSelectedAndVisible &&
          !stillConnectedAndVisible &&
          _pluginBackgroundSiteUrl != siteUrl) {
        tracker.stop();
      } else if (stillSelectedAndVisible) {
        _syncTopicWatch(siteUrl, tracker);
      }
    });
  }

  /// The account id for a connected site, asking the site for it if what was
  /// stored predates our needing it.
  ///
  /// Discourse names a user's counter channels after their id, so without it
  /// there is nothing to subscribe to. Sites connected before this existed have
  /// a user with no id in preferences; one `/session/current.json` heals that
  /// for good, since what comes back is written straight back out.
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
  }) {
    final held = _instanceAt(siteUrl);
    if (held == null) return Future.value();
    if (_sessionUsersRefreshed.contains(siteUrl)) {
      return Future.value(held.user);
    }

    final active = _sessionUserRequests[siteUrl];
    if (active != null) return active;

    final session = lease ?? lifecycle.capture(siteUrl);
    late final Future<DiscourseUser?> request;
    request = _readSessionUser(siteUrl, apiKey, session).whenComplete(() {
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
  ) async {
    if (!lease.isCurrent || _connectingSiteUrl == siteUrl) return null;

    final DiscourseUser user;
    try {
      user = await api.currentUser(siteUrl: siteUrl, apiKey: apiKey);
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return null;
      _reportOperationalError(
        error,
        stackTrace,
        'messageBus.resolveAccount',
        severity: DiagnosticSeverity.warning,
      );
      // The connection is still worth opening for `/latest`.
      return null;
    }

    var changed = false;
    final accepted = lease.commit(() {
      final fresh = _instanceAt(siteUrl);
      if (fresh == null) return;
      _sessionUsersRefreshed.add(siteUrl);
      _assignLegacyFallbackUnavailable.remove(siteUrl);
      if (fresh.user != user) {
        changed = true;
        _replaceInstance(fresh, fresh.copyWith(user: user));
      }
      _notify();
    });
    if (accepted && changed && lease.isCurrent) {
      instanceStore.save(List.of(_instances)).ignore();
    }
    return accepted ? user : null;
  }

  /// Folds a counters message onto what is held for a site.
  ///
  /// Nothing is redrawn when the message changes nothing we show, which is the
  /// common case: `/notification/` is published on every read as well as every
  /// arrival, and a read the user made here has already been applied.
  void _applyCounts(
    String siteUrl,
    NotificationTotals Function(NotificationTotals held) fold,
  ) => accountActivity.applyCounts(siteUrl, fold);

  /// The freshest status known for an account, including live MessageBus
  /// changes which arrived after the model carrying [snapshot] was fetched.
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

  bool userStatusWriteInFlight(String siteUrl) =>
      _userStatusWrites.contains(siteUrl);

  Future<String?> setUserStatus(
    String siteUrl, {
    required String description,
    required String emoji,
    DateTime? endsAt,
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
      await api.setUserStatus(
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
      await api.clearUserStatus(
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

  /// Tells the shell whether it is the app in front.
  ///
  /// A backgrounded native app stops ordinary polling altogether. The browser
  /// client's one-minute hidden-tab pacing assumes a tab that remains runnable;
  /// on desktop that made this hidden app wake forever, and on mobile the OS can
  /// suspend the socket at any point. Cursors survive [SiteTracker.stop], so a
  /// returning app still asks for exactly what it missed. A tracker carrying an
  /// active voice call is the sole exception because call signalling must stay
  /// live in the background.
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

    final instance = currentInstance;
    final callSite = _pluginBackgroundSiteUrl;
    for (final entry in _trackers.entries) {
      final selected = entry.key == instance?.url;
      final connected = _instanceAt(entry.key)?.isConnected ?? false;
      if (selected || connected || entry.key == callSite) {
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

  /// The topic filling the main region, once it has arrived.
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

  /// Every id in the active topic projection, including unloaded posts.
  ///
  /// Core's progress control counts its filtered stream. A top-replies
  /// summary therefore has its own positions rather than borrowing the full
  /// topic's count.
  List<int> get currentTopicStreamIds {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return const [];
    return _topicStream(instance.url, detail);
  }

  /// The contiguous ids of the posts on screen, in reading order.
  ///
  /// The topic knows every post id it has; the store knows which of them have
  /// actually been fetched. An ordinary load draws the fetched prefix, while
  /// a numbered load draws the fetched window around its target.
  ///
  /// Memoized: every shell notification re-selects a snapshot, and each
  /// post-frame viewport look asks again, so an uncached answer costs a store
  /// read per loaded post per frame. The key is exactly what the derivation
  /// reads — the site, the detail record, the route's target post, and the
  /// site's post-change generation.
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

  /// The loaded window to draw.
  ///
  /// Ordinary topic loads are a prefix. Numbered loads are a middle window;
  /// when older posts from a previous visit are also cached, drawing every
  /// loaded id would collapse the unfetched gap between them. Instead, grow
  /// outward only while adjacent posts are present around the requested one.
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

  /// Post ids after the loaded window, oldest first.
  List<int> _pendingPostIds(String siteUrl, TopicDetail detail) {
    final stream = _topicStream(siteUrl, detail);
    final range = _loadedPostRange(siteUrl, detail, stream: stream);
    final start = range == null ? 0 : range.$2 + 1;
    return [
      for (final id in stream.skip(start))
        if (store.read<Post>(siteUrl, id) == null) id,
    ];
  }

  /// Post ids immediately before the loaded window, newest batch first.
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

  /// Whether the topic on screen has posts left to fetch.
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

  /// Replaces the main region with [topic] and fetches it.
  void openTopic(Topic topic) => _openTopic(
    topic.id,
    topic.slug,
    topic.title,
    postNumber: topic.lastUnreadPostNumber,
  );

  /// Opens one of the partial topic records side-loaded with a user summary.
  void openSummaryTopic(UserSummaryTopic topic, {int? postNumber}) =>
      _openTopic(
        topic.id,
        topic.slug,
        topic.title,
        postNumber: postNumber != null && postNumber > 0 ? postNumber : null,
      );

  /// Opens a featured topic from the categories page.
  ///
  /// Category-list topics use a deliberately smaller serializer than an
  /// ordinary [Topic]. Keeping this entry point separate prevents absent list
  /// fields from being mistaken for real zeroes in the identity store.
  void openFeaturedTopic(CategoryFeaturedTopic topic) => _openTopic(
    topic.id,
    topic.slug,
    topic.title,
    postNumber: topic.firstUnreadPostNumber,
  );

  /// Pushes one category's native topic list over the full categories page.
  void openCategory(TopicCategory category) {
    final instance = currentInstance;
    if (instance == null) return;
    final categories = _categoriesBySite[instance.url] ?? const [];
    final byId = <int, TopicCategory>{
      for (final item in categories) item.id: item,
      category.id: category,
    };
    final route = ContentRoute.fromDestination(
      buildCategoryDestination(category, categoriesById: byId),
    );
    if (currentContent?.id == route.id) return;
    pushContent(route);
    unawaited(loadFeed(route.id));
  }

  void openSearchResult(SearchPostHit hit) {
    search.clear();
    _openTopic(
      hit.topicId,
      hit.topicSlug,
      hit.topicTitle,
      postNumber: hit.postNumber,
    );
  }

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

  /// Absolute form of [url].
  ///
  /// Discourse writes its own links site-relative — `/t/slug/1`, `/u/someone`
  /// — so they only mean anything once resolved against the site they were
  /// written on. Anything already absolute is returned untouched, including
  /// the schemes that are not ours to resolve, such as `mailto:`.
  String absoluteUrl(String url, {String? siteUrl}) =>
      resolveSiteUrl(url, siteUrl ?? currentInstance?.url);

  /// Opens [url] here when it points at a topic on a site in the rail,
  /// switching to that site first when the topic is on another one.
  ///
  /// Returns false for everything else — a topic on a site the user has not
  /// connected is a page this app has no view for — which is the caller's
  /// signal to hand the link to the browser.
  bool openTopicUrl(String url) => _openTopicUrl(url);

  bool _openTopicUrl(String url, {bool refresh = false}) {
    final link = TopicLink.parse(absoluteUrl(url));
    if (link == null) return false;

    final index = _instances.indexWhere((i) => i.serves(link.uri));
    if (index < 0) return false;

    if (index != _instanceIndex) selectInstance(index);

    // Posts link to the topic they are already in — every cross-post quote
    // does — and stacking a second copy of it only costs the user a back tap.
    // A notification is different: it reports a change that happened after
    // the post may have entered the store, so its target has to be read again.
    if (currentContent?.topicId == link.topicId) {
      if (refresh) {
        openCurrentTopicPost(link.postNumber ?? 1, loadAroundPost: true);
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

  /// Changes whenever an explicit same-topic navigation replaces the reader's
  /// viewport. Topic views use this to reject positioning callbacks from the
  /// route that was on screen before the navigation.
  int get topicNavigationRevision => _topicNavigationRevision;

  /// Jumps to one one-based position in the current topic's visible stream.
  ///
  /// Core's timeline addresses the stream by post id, not by assuming its
  /// index is also a post number: deleted and hidden posts make those diverge.
  /// Resolve an unloaded id through the same bounded post endpoint as the web
  /// client, then reuse the numbered topic route for the around-post window.
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
        final fetched = await api.posts(
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

  /// Opens the category or tag list [url] points at, if this is one and a site
  /// in the rail serves it.
  ///
  /// The sibling of [openTopicUrl], and the same shape: a hashtag in a post is
  /// a link like any other, and where it belongs is decided the same way.
  ///
  /// [title] is what the site called the list, where the caller knows — a
  /// cooked hashtag carries the real name, which beats un-slugging the URL.
  bool openListUrl(String url, {String? title}) {
    final link = ListLink.parse(absoluteUrl(url));
    if (link == null) return false;

    final index = _instances.indexWhere((i) => i.serves(link.uri));
    if (index < 0) return false;

    if (index != _instanceIndex) selectInstance(index);

    // The badge colour, where the categories have landed. Null is not a
    // failure — the header draws its icon plain, as it does for every sidebar
    // destination.
    final category = link.kind == ListKind.category
        ? categoryFor(link.id)
        : null;

    final route = ContentRoute.list(
      link,
      title: title,
      color: category == null ? null : Color(category.colorValue),
    );

    // Already looking at it. Pushing a second copy would only cost a back tap,
    // the way `openTopicUrl` says of a topic linking to itself.
    if (currentContent?.id == route.id) return true;

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

    // Before the guards below, not after: both of them return early on the
    // ordinary path — a topic already in the store, or one already being
    // fetched — and a fetch that only ever runs on a cache miss would get one
    // attempt per session and no way back if it failed. Reading a topic is also
    // the first thing that needs any of this, so a site whose topics are never
    // opened is never asked.
    unawaited(_presentation.ensureConfig(instance.url));
    unawaited(_presentation.ensureCustomEmojis(instance.url));
    // A hashtag in a post needs its category to know what colour to draw, and
    // a topic opened from a notification or a link has never loaded a feed —
    // which until now was the only thing that asked for them.
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
        api.topic(
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
      // Left absent; the view shows its own failure state.
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

  /// Corrects the header of a topic opened from a link, which could only guess
  /// at the title from the slug in the URL.
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
      final routes = <ContentRoute>[];
      for (final route in tab.contentStack) {
        if (route.topicId != topicId) {
          routes.add(route);
          continue;
        }
        final updated = rewrite(route);
        routes.add(updated);
        tabChanged = tabChanged || !identical(updated, route);
      }
      changed = changed || tabChanged;
      tabs.add(tabChanged ? tab.copyWith(contentStack: routes) : tab);
    }
    if (changed) _putWorkspace(workspace.copyWith(tabs: tabs));
  }

  /// Files a topic payload: the posts under their own ids, the topic under
  /// its own, and the list row's durable details corrected to match.
  ///
  /// Fetching is deliberately not treated as reading. Discourse advances a
  /// topic's reading position from `/topics/timings`; [markTopicRead] sends
  /// that only after the viewport has actually shown a post.
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

  /// Reveals one bounded chunk of posts the topic stream deliberately hid.
  ///
  /// The ids come from core's `post_stream.gaps`, so the site has already
  /// decided that this reader may request them. They remain outside ordinary
  /// paging until this explicit action, matching the web client's gap flow.
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
      final fetched = await api.posts(
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

  /// Changes how closely the current account follows one topic.
  ///
  /// The selected level is painted immediately. Writes for one topic are
  /// serialized, and a newer selection supersedes an older one that has not
  /// reached the server yet. If the latest write fails, the last confirmed
  /// level is restored.
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
      await api.updateTopicNotificationLevel(
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

  /// Dismisses or restores a personalized topic pin, as core's footer does.
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
      await api.updateTopicPinForUser(
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

  /// Applies one status offered by the topic serializer's guardian gates.
  ///
  /// Statuses share one per-topic lock. Core's admin menu does not need two
  /// overlapping mutations, and serializing them prevents a slower close from
  /// painting over a later archive when the responses arrive out of order.
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
      await api.updateTopicStatus(
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

  /// Deletes or recovers a topic only when its personalized guardian allows it.
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
        await api.deleteTopic(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          clientId: clientId,
        );
      } else {
        await api.recoverTopic(
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

  /// Credits the reader through the farthest post the viewport has shown.
  ///
  /// The local list row moves first so leaving and reopening in this session
  /// uses the new position even while the network write is in flight. Failed
  /// receipts are not rolled back: the next personalized list refresh is the
  /// site's authoritative reconciliation, and putting unread state back under
  /// a reader who just saw the post would be misleading.
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

  /// Fetches the next batch of posts in the open topic.
  ///
  /// A topic arrives with its first twenty posts plus the ids of all the rest,
  /// so paging is by id rather than by page number.
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
      final page = await api.topicPosts(
        siteUrl: instance.url,
        topicId: topicId,
        ids: pending.take(boundedBatch).toList(),
        apiKey: credential.value,
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
            (detail) => detail.withRecommendations(recommendations),
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
      // Keep what is already shown.
    } finally {
      lease.commit(() {
        _postsLoading.remove(key);
        _notify();
      });
    }
  }

  /// Fetches the batch immediately before an around-post topic window.
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
      final posts = await api.posts(
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

  /// Switches the open topic between its complete stream and core's
  /// top-replies summary filter.
  ///
  /// The filtered stream stays controller-owned rather than replacing the
  /// stored [TopicDetail]: cancelling must reveal the complete id list without
  /// a second request, and the filtered serializer is only a projection of the
  /// same topic, not a newer copy of it.
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
      final payload = await api.topic(
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
  Future<void>? _composerDraftRestore;

  /// The open composer, but only when it belongs to what is on screen.
  ///
  /// Navigating away leaves it open and out of sight rather than throwing away
  /// what was written, and it stays bound to the site it was opened on.
  ComposerController? get visibleComposer {
    final composer = _composer;
    final instance = currentInstance;
    if (composer == null || instance == null) return null;
    if (composer.target.siteUrl != instance.url) return null;
    if (composer.target.tabId case final tabId?) {
      if (tabId != activeTabId) return null;
    }
    if (composer.target.isNewTopic) {
      if (composer.target.originTopicId case final topicId?) {
        return currentContent?.topicId == topicId ? composer : null;
      }
      return currentContent?.isTopic == false &&
              currentFeedId == composer.target.originFeedId
          ? composer
          : null;
    }
    return currentContent?.topicId == composer.target.topicId ? composer : null;
  }

  /// Whether a reply affordance should be offered for the topic on screen.
  bool get canReplyHere => currentTopic?.canCreatePost ?? false;

  /// Builds a text composer with the site-owned services every writing mode
  /// shares.
  ///
  /// Tags-only editing deliberately does not use this factory: it never opens
  /// the text editor, so search, artwork, uploads, and draft persistence would
  /// all be unused dependencies there.
  ComposerController _buildTextComposer(
    ComposerTarget target, {
    bool persistsDraft = false,
    int minimumRequiredTags = 0,
  }) {
    final config = siteConfigFor(target.siteUrl);
    final composer = ComposerController(
      target,
      onSaveDraft: persistsDraft ? _saveDraft : null,
      search: _composerSearch(target),
      onEmojiAccepted: (code) => unawaited(
        emojiPickerStore.trackEmoji(
          siteUrl: target.siteUrl,
          context: target.isChat
              ? EmojiPickerContext.chat
              : EmojiPickerContext.topic,
          emoji: code,
        ),
      ),
      resolveEmoji: (name) => emojiUrlFor(target.siteUrl, name),
      pills: _composerPills(target),
      formatQuoteContents: (block) =>
          quoteContentsFor(target, block) ?? block.contents,
      syntaxPlugins: plugins.registry.composerSyntaxPlugins,
      pollMaximumOptions: config.pollMaximumOptions,
      localDateAccountTimezone: currentUserFor(target.siteUrl)?.timezone,
      imageUploader: target.isChat && !config.chatUploadsEnabled
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
      maxImageWidth: config.maxImageWidth,
      maxImageHeight: config.maxImageHeight,
      minimumRequiredTags: minimumRequiredTags,
    );
    if (persistsDraft) composer.draftSequence = _draftSequence(target);
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

  /// Builds the inline composer for one chat channel with the same markdown,
  /// completion, artwork, and upload services as the topic composer.
  ///
  /// Chat owns where this controller lives and how it is submitted; the shell
  /// owns the site-scoped services needed while text is being written.
  ComposerController buildChatComposer({
    required String siteUrl,
    required int channelId,
    required String channelTitle,
    int? threadId,
  }) => _buildTextComposer(
    ComposerTarget(
      siteUrl: siteUrl,
      topicId: 0,
      slug: '',
      topicTitle: channelTitle,
      chatChannelId: channelId,
      chatThreadId: threadId,
      mode: ComposerMode.chat,
    ),
  );

  /// Opens a new-topic composer while leaving the originating list in place.
  Future<void> openNewTopic() async {
    final instance = currentInstance;
    final route = currentContent;
    final feedId = currentFeedId;
    final tabId = activeTabId;
    if (instance == null ||
        route == null ||
        feedId == null ||
        tabId == null ||
        !canCreateTopicHere) {
      return;
    }

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
          api.topicComposerCapabilities(siteUrl: instance.url, apiKey: apiKey),
          api.categories(siteUrl: instance.url, apiKey: apiKey),
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
        final result = await api.searchTopicTags(
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
      } catch (_) {
        // Context prefill is optional; the composer remains usable without it.
      }
    }
    if (!lease.isCurrent || currentFeedId != feedId || activeTabId != tabId) {
      return;
    }

    _categoriesBySite[instance.url] = List.unmodifiable(categories);
    _topicComposerCapabilities[instance.url] = capabilities;
    store.putAll(instance.url, categories);
    _replaceComposer();
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: tabId,
      topicId: 0,
      slug: '',
      topicTitle: 'New topic',
      mode: ComposerMode.newTopic,
      originFeedId: feedId,
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
    _notify();
    _startComposerDraftRestore(composer);
  }

  /// Starts a new topic from the topic on screen and preserves the backlink
  /// core inserts at the top of that composer.
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
    _replaceComposer();
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
    _startComposerDraftRestore(composer);

    try {
      await _composerDraftRestore;
    } catch (_) {
      // Draft restoration is best effort; the continuation action remains
      // useful even when local persistence is unavailable.
    }
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

  @override
  Future<String?> insertPluginTranscriptIntoNewTopic({
    required String siteUrl,
    required String sourceRouteId,
    required String markdown,
    int? initialCategoryId,
  }) async {
    final route = currentContent;
    final tabId = activeTabId;
    final feedId = currentFeedId;
    if (markdown.trim().isEmpty ||
        currentInstance?.url != siteUrl ||
        currentInstance?.user == null ||
        route?.id != sourceRouteId ||
        tabId == null ||
        feedId == null) {
      return 'The topic composer is no longer available here.';
    }

    final lease = lifecycle.capture(siteUrl);
    await Future.wait<void>([
      loadCategories(siteUrl),
      _ensureTopicComposerCapabilities(siteUrl),
    ]);
    if (!lease.isCurrent ||
        currentInstance?.url != siteUrl ||
        currentContent?.id != sourceRouteId ||
        activeTabId != tabId ||
        currentFeedId != feedId) {
      return 'The topic composer is no longer available here.';
    }

    final category = initialCategoryId == null
        ? null
        : topicComposerCategories(siteUrl)
              .where(
                (item) => item.id == initialCategoryId && item.canCreateTopic,
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
      _replaceComposer();
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
      _startComposerDraftRestore(composer);
    }

    try {
      await _composerDraftRestore;
    } catch (_) {
      // A local draft failure must not turn a canonical transcript into a
      // dead action.
    }
    if (!lease.isCurrent ||
        !identical(_composer, composer) ||
        currentContent?.id != sourceRouteId ||
        activeTabId != tabId) {
      return 'The topic composer is no longer available here.';
    }
    composer.insertBlock(markdown);
    composer.focus.requestFocus();
    return null;
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
    return api.searchTopicTags(
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

  /// Opens the composer against the topic on screen.
  ///
  /// [replyToPostNumber] addresses one post; leaving it out replies to the
  /// topic. Reopening while something is already written points the existing
  /// composer at the new post rather than discarding it — unless that composer
  /// is editing a post, which is a different piece of writing altogether and
  /// cannot be retargeted into a reply.
  void openReply({int? replyToPostNumber, String? replyToUsername}) {
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !canReplyHere) return;

    final existing = _composer;
    if (existing != null &&
        !existing.target.isEdit &&
        existing.target.topicId == topicId &&
        existing.target.siteUrl == instance.url &&
        existing.target.tabId == activeTabId) {
      existing.retarget(
        replyToPostNumber: replyToPostNumber,
        replyToUsername: replyToUsername,
      );
      existing.focus.requestFocus();
      return;
    }

    _replaceComposer();
    final target = ComposerTarget(
      siteUrl: instance.url,
      tabId: activeTabId,
      topicId: topicId,
      slug: route?.slug ?? '',
      topicTitle: route?.title ?? '',
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
    );
    final composer = _buildTextComposer(target, persistsDraft: true);
    _composer = composer;
    _notify();

    _startComposerDraftRestore(composer);
  }

  /// Opens a reply composer and inserts a selected post quote into it.
  ///
  /// Draft restoration finishes first, so quoting into a closed composer adds
  /// to the unfinished reply Discourse already knows about instead of hiding
  /// it behind the newly inserted block. An already-open reply keeps its own
  /// target, matching core: selecting another post should not silently retarget
  /// text that is already being written.
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
        !composer.target.isNewTopic &&
        !composer.target.isChat &&
        composer.target.topicId == topicId &&
        composer.target.siteUrl == instance.url &&
        composer.target.tabId == activeTabId;

    if (!reusesOpenReply) {
      openReply(
        replyToPostNumber: post.postNumber == 1 ? null : post.postNumber,
        replyToUsername: post.postNumber == 1 ? null : post.username,
      );
      composer = _composer;
    }
    if (composer == null) return;

    final restore = identical(_composer, composer)
        ? _composerDraftRestore
        : null;
    if (restore != null) {
      try {
        await restore;
      } catch (_) {
        // Draft restoration is best effort. A local-storage failure must not
        // turn a selected quote into a dead action.
      }
    }

    if (isDisposed ||
        !identical(_composer, composer) ||
        currentInstance?.url != instance.url ||
        currentContent?.topicId != topicId ||
        activeTabId != composer.target.tabId) {
      return;
    }
    composer.insertBlock(quote);
    composer.focus.requestFocus();
  }

  /// Opens the composer over an existing post, to rewrite it.
  ///
  /// Whether that is allowed is the site's answer, not ours: [Post.canEdit]
  /// comes from the guardian that already weighed ownership, staff, the edit
  /// window and the state of the topic. It is checked again here because the
  /// affordance and the action are reached separately — a keyboard shortcut or
  /// a stale row must not get past the button being hidden.
  void openEdit(Post post) {
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !post.canEdit) return;
    unawaited(_ensureTopicComposerCapabilities(instance.url));

    _replaceComposer();
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
    // Rewriting a post wants mentions and emoji as much as writing one does.
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
    _replaceComposer();
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

  Future<void> _ensureTopicComposerCapabilities(String siteUrl) async {
    if (_topicComposerCapabilities.containsKey(siteUrl)) return;
    final lease = lifecycle.capture(siteUrl);
    try {
      final credential = await _credentialForWrite(siteUrl);
      if (!lease.isCurrent || credential.failure != null) return;
      final capabilities = await api.topicComposerCapabilities(
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

  /// How a composer for [target] finds people and emoji.
  ///
  /// Closed over the target's own site and topic rather than reading the
  /// current instance when a key is pressed, for the reason [ComposerTarget]
  /// carries a siteUrl at all: switching sites while a reply is half written
  /// must not send the search — or the name it completes — to the site the
  /// user switched to.
  ComposerSearch _composerSearch(ComposerTarget target) {
    if (siteConfigFor(target.siteUrl).emojiEnabled) {
      unawaited(ensureEmojiCatalog(target.siteUrl));
    }

    return (
      users: (term) async {
        final found = await searchUsers(
          siteUrl: target.siteUrl,
          topicId: target.isChat ? null : target.topicId,
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
              art: _hashtagArt(hashtag),
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

  /// Fills an edit composer with the post's markdown.
  ///
  /// The stream carries cooked HTML, which is Discourse's rendering of the
  /// post rather than the post — reproducing the markdown from it is exactly
  /// the transformation this client does not do. So the raw is fetched.
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
      final fetched = await api.posts(
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

  /// Deletes [post], then reads it back to see what that did.
  ///
  /// Returns the site's refusal when there was one, so the caller can say so;
  /// null means it went through.
  ///
  /// Guarded on the site's own answer for the same reason as [openEdit]: the
  /// button being hidden is not a permission check.
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
      (apiKey, ids) =>
          api.deletePosts(siteUrl: siteUrl, apiKey: apiKey, postIds: ids),
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
      (apiKey, ids) =>
          api.mergePosts(siteUrl: siteUrl, apiKey: apiKey, postIds: ids),
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
      final results = await api.searchPosts(
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
      destinationUrl = await api.movePosts(
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
      destinationUrl = await api.movePosts(
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
      (apiKey, ids) => api.changePostOwners(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postIds: ids,
        username: trimmedUsername,
      ),
    );
  }

  /// Reassigns one post directly from its admin menu.
  ///
  /// The account-level serializer flag is the same gate web uses here. The
  /// topic route still accepts a post-id array, so the direct action sends a
  /// one-element selection and authoritatively re-reads that post afterwards.
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
      (siteUrl, apiKey) => api.changePostOwners(
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
      (siteUrl, apiKey) =>
          api.deletePost(siteUrl: siteUrl, apiKey: apiKey, postId: post.id),
    );

    // Editing something that has just been deleted is writing into a hole, and
    // saving would fail anyway.
    if (error == null && identical(_composer, editing)) {
      closeComposer();
    }
    return error;
  }

  /// Whether core advertised permanent deletion for this already-deleted
  /// target. The opening post takes its permission from topic details; replies
  /// carry it on their own serializer, exactly as the web model does.
  bool canPermanentlyDeletePost(Post post) {
    final topic = currentTopic;
    return post.isDeleted &&
        topic != null &&
        topic.stream.contains(post.id) &&
        (post.postNumber == 1
            ? topic.deletedAt != null && topic.canPermanentlyDelete
            : post.canPermanentlyDelete);
  }

  /// Runs core's just-in-time cooldown/different-admin preflight.
  ///
  /// Null means the confirmation may be shown; a non-null string is either the
  /// server's localized refusal reason or a transport/account failure.
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
      final result = await api.checkPermanentPostDeletion(
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
        (siteUrl, apiKey) => api.permanentlyDeletePost(
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
      await api.permanentlyDeleteTopic(
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

  /// Puts a deleted post back.
  Future<String?> recoverPost(Post post) async {
    if (!post.canRecover) return null;
    final siteUrl = currentInstance?.url;
    if (siteUrl != null &&
        _postWritesInFlight.contains(_postKey(siteUrl, post.id))) {
      return null;
    }
    return _mutatePost(
      post,
      (siteUrl, apiKey) =>
          api.recoverPost(siteUrl: siteUrl, apiKey: apiKey, postId: post.id),
    );
  }

  /// Changes whether the site treats this as a collaboratively editable post.
  Future<String?> setPostWiki(Post post, bool wiki) {
    if (!post.canWiki || post.wiki == wiki) return Future.value();
    return _mutatePost(
      post,
      (siteUrl, apiKey) => api.updatePostWiki(
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
      (siteUrl, apiKey) => api.updatePostLocked(
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
      (siteUrl, apiKey) =>
          api.unhidePost(siteUrl: siteUrl, apiKey: apiKey, postId: post.id),
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
      (siteUrl, apiKey) => api.updatePostType(
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
      (siteUrl, apiKey) => api.updatePostNotice(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        notice: next,
      ),
    );
  }

  /// Privately flags [post] with one server-advertised reason.
  ///
  /// Unlike a like, this is not guessed locally. The editor stays open until
  /// the personalized post response proves both that the action succeeded and
  /// what the post looks like after any moderation rules ran.
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
        final fresh = await api.createPostFlag(
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

  /// Privately flags a topic using core's topic-id post-action bridge.
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
        await api.createTopicFlag(
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

  /// Adds this reader's like to [post], or takes it back if it is already
  /// there.
  ///
  /// Returns the site's refusal when there was one, so the caller can say so;
  /// null means it went through.
  ///
  /// The post changes before the request leaves, and changes back if the site
  /// refuses. A like is the one write here worth doing that for: it is a
  /// single tap people make while reading, often several in a row, and a heart
  /// that waits for a round trip before filling in reads as a broken button
  /// rather than a slow one. Nothing is lost if it fails, which is what makes
  /// the guess safe to make — unlike a post, where guessing wrong would mean
  /// showing a reply that was never made.
  ///
  /// Whichever way it goes the site's own answer lands on top: `post_actions`
  /// replies with the post, so the count includes whatever else happened to it
  /// while the request was in flight.
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
    // A transform of whatever is held now rather than a put of the tapped
    // copy, for the reason `_writeReaction` gives: the credential await above
    // is a gap a re-read can land in. The guess is usually corrected by the
    // site's full answer, but an answer of 204 brings nothing, so a stale
    // snapshot put here would stand.
    final applied = lease.commit(() {
      store.update<Post>(siteUrl, post.id, (held) => held.withLike(liked));
      _notify();
    });
    if (!applied) return null;

    /// Puts the like back the way it was, and nothing else.
    ///
    /// A whole copy of the post would do it too, and would also undo anything
    /// that landed while the request was in flight — an edit, a deletion, a
    /// re-read. Only the four fields this touched are its to put back.
    void revert() {
      lease.commit(() {
        store.update<Post>(siteUrl, post.id, (held) => held.withLikesOf(post));
        _notify();
      });
    }

    try {
      final fresh = liked
          ? await api.likePost(
              siteUrl: siteUrl,
              apiKey: apiKey,
              postId: post.id,
            )
          : await api.unlikePost(
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

  /// One write at a time per post, whichever kind it is. Keyed by site and post
  /// because topic 7's post 3 on two sites are two different posts.
  final Set<String> _postWritesInFlight = {};
  final Map<String, Set<int>> _topicPostSelections = {};
  final Set<String> _topicPostSelectionWrites = {};
  final Set<String> _topicFlagWrites = {};

  final Set<String> _topicBookmarkWritesInFlight = {};
  final Set<String> _chatBookmarkWritesInFlight = {};
  final Map<String, int> _bookmarkVersions = {};
  final Map<String, int> _siteBookmarkVersions = {};

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
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    String? siteUrl,
  }) {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null) return false;
    return switch (targetType) {
      BookmarkTargetType.post => _postWritesInFlight.contains(
        _postKey(targetSite, targetId),
      ),
      BookmarkTargetType.topic => _topicBookmarkWritesInFlight.contains(
        _topicKey(targetSite, topicId),
      ),
      BookmarkTargetType.chatMessage => _chatBookmarkWritesInFlight.contains(
        _postKey(targetSite, targetId),
      ),
    };
  }

  /// The live read currently allowed to update each post.
  final Map<String, Object> _postRefreshRequests = {};

  /// Another invalidation arrived while that read was in flight.
  final Set<String> _postRefreshPending = {};

  /// Topic needed to replay an invalidation held behind a post write.
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
    required int topicId,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) async {
    final instance = currentInstance;
    final refreshTarget = targetType == BookmarkTargetType.chatMessage
        ? 'chat message'
        : 'topic';
    if (instance == null || !instance.isConnected) {
      return const BookmarkWriteResult.refused(
        'Reconnect to this forum to bookmark it.',
      );
    }
    final siteUrl = instance.url;
    if (!_beginBookmarkWrite(siteUrl, topicId, targetType, targetId)) {
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
        id = await api.createBookmark(
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
            topicId,
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
            topicId,
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
        _applyBookmark(siteUrl, topicId, bookmark);
      });
      if (!applied) {
        return const BookmarkWriteResult.reconciled(
          'The bookmark was saved on the forum.',
        );
      }
      _reconcileBookmarks(
        instance,
        topicId,
        targetType: targetType,
        targetId: targetId,
      );
      return BookmarkWriteResult.saved(bookmark);
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, topicId, targetType, targetId),
      );
    }
  }

  Future<BookmarkWriteResult> updateBookmark({
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) async {
    final instance = currentInstance;
    final targetType = bookmark.coreTargetType;
    final targetId = bookmark.bookmarkableId;
    if (instance == null ||
        !instance.isConnected ||
        targetType == null ||
        targetId == null) {
      return const BookmarkWriteResult.refused(
        'This bookmark cannot be edited here.',
      );
    }
    final refreshTarget = targetType == BookmarkTargetType.chatMessage
        ? 'chat message'
        : 'topic';
    final siteUrl = instance.url;
    if (!_beginBookmarkWrite(siteUrl, topicId, targetType, targetId)) {
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
        await api.updateBookmark(
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
            topicId,
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
            topicId,
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
        _applyBookmark(siteUrl, topicId, updated);
      });
      if (!applied) {
        return const BookmarkWriteResult.reconciled(
          'The bookmark was updated on the forum.',
        );
      }
      _reconcileBookmarks(
        instance,
        topicId,
        targetType: targetType,
        targetId: targetId,
      );
      return BookmarkWriteResult.saved(updated);
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, topicId, targetType, targetId),
      );
    }
  }

  Future<BookmarkWriteResult> clearBookmarkReminder({
    required int topicId,
    required Bookmark bookmark,
  }) => updateBookmark(
    topicId: topicId,
    bookmark: bookmark,
    name: bookmark.name,
    autoDeletePreference: bookmark.autoDeletePreference,
  );

  Future<BookmarkWriteResult> deleteBookmark({
    required int topicId,
    required Bookmark bookmark,
  }) async {
    final instance = currentInstance;
    final targetType = bookmark.coreTargetType;
    final targetId = bookmark.bookmarkableId;
    if (instance == null ||
        !instance.isConnected ||
        targetType == null ||
        targetId == null) {
      return const BookmarkWriteResult.refused(
        'This bookmark cannot be deleted here.',
      );
    }
    final refreshTarget = targetType == BookmarkTargetType.chatMessage
        ? 'chat message'
        : 'topic';
    final siteUrl = instance.url;
    if (!_beginBookmarkWrite(siteUrl, topicId, targetType, targetId)) {
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
        topicBookmarked = await api.deleteBookmark(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          bookmarkId: bookmark.id,
          targetType: targetType,
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(
            instance,
            topicId,
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
            topicId,
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
          topicId,
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
        topicId,
        targetType: targetType,
        targetId: targetId,
      );
      return const BookmarkWriteResult.saved();
    } finally {
      lease.commit(
        () => _endBookmarkWrite(siteUrl, topicId, targetType, targetId),
      );
    }
  }

  Future<BookmarkWriteResult> deleteAllTopicBookmarks(int topicId) async {
    final instance = currentInstance;
    if (instance == null || !instance.isConnected) {
      return const BookmarkWriteResult.refused(
        'Reconnect to this forum to delete its bookmarks.',
      );
    }
    final siteUrl = instance.url;
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
        await api.deleteTopicBookmarks(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
        );
      } on WriteException catch (error) {
        if (error.failure == WriteFailure.unreachable) {
          _reconcileBookmarks(instance, topicId);
          return const BookmarkWriteResult.reconciled(
            "Couldn't confirm the deletion. The topic is being refreshed.",
          );
        }
        return BookmarkWriteResult.refused(error.message);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(error, stackTrace, 'bookmark.deleteAll');
          _reconcileBookmarks(instance, topicId);
        }
        return const BookmarkWriteResult.reconciled(
          "Couldn't confirm the deletion. The topic is being refreshed.",
        );
      }
      lease.commit(() => _removeAllBookmarks(siteUrl, topicId));
      _reconcileBookmarks(instance, topicId);
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
    int topicId,
    BookmarkTargetType targetType,
    int targetId,
  ) => switch (targetType) {
    BookmarkTargetType.post => _beginPostWrite(_postKey(siteUrl, targetId)),
    BookmarkTargetType.topic => _beginTopicBookmarkWrite(
      _topicKey(siteUrl, topicId),
    ),
    BookmarkTargetType.chatMessage => _beginChatBookmarkWrite(
      _postKey(siteUrl, targetId),
    ),
  };

  bool _beginTopicBookmarkWrite(String key) {
    if (!_topicBookmarkWritesInFlight.add(key)) return false;
    _notify();
    return true;
  }

  bool _beginChatBookmarkWrite(String key) {
    if (!_chatBookmarkWritesInFlight.add(key)) return false;
    _notify();
    return true;
  }

  void _endBookmarkWrite(
    String siteUrl,
    int topicId,
    BookmarkTargetType targetType,
    int targetId,
  ) {
    switch (targetType) {
      case BookmarkTargetType.post:
        _endPostWrite(siteUrl, targetId);
      case BookmarkTargetType.topic:
        _topicBookmarkWritesInFlight.remove(_topicKey(siteUrl, topicId));
        _notify();
      case BookmarkTargetType.chatMessage:
        _chatBookmarkWritesInFlight.remove(_postKey(siteUrl, targetId));
        _notify();
    }
  }

  void _applyBookmark(String siteUrl, int topicId, Bookmark bookmark) {
    final targetType = bookmark.coreTargetType;
    final targetId = bookmark.bookmarkableId;
    if (targetType == BookmarkTargetType.chatMessage) {
      if (targetId != null) {
        for (final observer
            in _pluginSession.capabilities<PluginBookmarkObserver>()) {
          if (!observer.handlesPluginBookmark(
            BookmarkTargetType.chatMessage.name,
          )) {
            continue;
          }
          observer.putPluginBookmark(siteUrl, targetId, bookmark);
          break;
        }
      }
      _notify();
      return;
    }
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
    int topicId,
    Bookmark bookmark, {
    required bool? topicBookmarked,
  }) {
    final targetType = bookmark.coreTargetType;
    final targetId = bookmark.bookmarkableId;
    if (targetType == BookmarkTargetType.chatMessage) {
      if (targetId != null) {
        for (final observer
            in _pluginSession.capabilities<PluginBookmarkObserver>()) {
          if (!observer.handlesPluginBookmark(
            BookmarkTargetType.chatMessage.name,
          )) {
            continue;
          }
          observer.removePluginBookmark(siteUrl, targetId);
          break;
        }
      }
      _notify();
      return;
    }
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
    int topicId, {
    BookmarkTargetType targetType = BookmarkTargetType.topic,
    int? targetId,
  }) {
    if (targetType == BookmarkTargetType.chatMessage && targetId != null) {
      for (final observer
          in _pluginSession.capabilities<PluginBookmarkObserver>()) {
        if (!observer.handlesPluginBookmark(targetType.name)) continue;
        _observePluginLifecycle(
          Future.sync(
            () => observer.reconcilePluginBookmark(instance.url, targetId),
          ),
          'plugins.session.reconcileBookmark',
        );
        break;
      }
    } else {
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

  /// Names a post in the per-site maps and sets here: site and post together,
  /// because topic 7's post 3 on two sites are two different posts.
  static String _postKey(String siteUrl, int postId) => '$siteUrl~$postId';

  final Set<String> _likersLoading = {};
  final Map<String, String> _likersErrors = {};

  /// Who liked a post, once the list has been asked for and arrived.
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

  /// Fetches the accounts behind a post's like count.
  ///
  /// Asked for every time the list is opened rather than once, because it is a
  /// list of what other people have just done and the point of opening it is to
  /// see who. Names already on screen stay there while the fetch runs, so
  /// reopening a list is instant and merely gets corrected.
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
      final fetched = await api.postLikers(
        siteUrl: targetSite,
        postId: postId,
        // Read inside the guard, not before it: storage that refuses —
        // an unsigned macOS build answers `errSecMissingEntitlement` —
        // would otherwise leave the key in [_likersLoading] for the rest of
        // the session, and every later hover would find a fetch in flight
        // that is not.
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

  /// Runs a write against one post and then re-reads it.
  ///
  /// Re-reading rather than guessing, because deleting is not one operation:
  /// staff get a soft delete that stays in the stream and can be undone, an
  /// author gets a placeholder, and some posts go for good. Only the site knows
  /// which, and asking is one cheap request.
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
        final fetched = await api.posts(
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

  /// Re-reads one post and puts whatever came back into the topic on screen.
  ///
  /// Nothing coming back is itself the answer: the post is gone, or no longer
  /// visible to this reader, and either way it should stop being drawn.
  Future<void> _refreshPost(
    String siteUrl,
    int topicId,
    int postId,
    String? apiKey,
    SiteLease lease,
  ) async {
    List<Post> fetched;
    try {
      fetched = await api.posts(
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
      // The write landed; the stream is repaired the next time it is read.
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

  /// Makes way for a new composer without losing what is in the old one.
  ///
  /// A pending draft is flushed rather than dropped: the save is debounced, so
  /// disposing outright throws away up to a couple of seconds of typing that
  /// neither the site nor this device has yet. Edits have no draft to flush.
  void _replaceComposer() {
    final existing = _composer;
    if (existing == null) {
      _composerDraftRestore = null;
      return;
    }
    if (existing.draftPending) {
      unawaited(existing.flushDraft());
    }
    existing.dispose();
    _composer = null;
    _composerDraftRestore = null;
  }

  /// Closes the composer, keeping the draft.
  ///
  /// Closing is how you get the topic back, not how you throw a reply away —
  /// reopening restores what was written. A pending draft is flushed first,
  /// for the same reason [_replaceComposer] flushes: the save is debounced, so
  /// disposing outright throws away the last couple of seconds of typing.
  void closeComposer() {
    final composer = _composer;
    if (composer == null) return;
    if (composer.draftPending) {
      unawaited(composer.flushDraft());
    }
    composer.dispose();
    _composer = null;
    _composerDraftRestore = null;
    _notify();
  }

  final Map<String, int> _draftSequences = {};
  final Map<String, Object> _draftSaveRequests = {};

  static String _draftKey(String siteUrl, String draftKey) =>
      '$siteUrl#$draftKey';

  int _draftSequence(ComposerTarget target) =>
      _draftSequences[_draftKey(target.siteUrl, target.draftKey)] ??
      (target.isNewTopic
          ? null
          : store
                .read<TopicDetail>(target.siteUrl, target.topicId)
                ?.draftSequence) ??
      0;

  /// Writes the local copy first, then sends it.
  ///
  /// The local copy is only removed once the site has the same text. If local
  /// storage is unavailable, the server still gets a chance to preserve it;
  /// the local failure is surfaced only when neither copy was made safe.
  Future<int?> _saveDraft(ComposerDraftSave save) async {
    final target = save.target;
    final data = save.draft.encode();
    final key = _draftKey(target.siteUrl, target.draftKey);
    final request = Object();
    _draftSaveRequests[key] = request;
    final lease = lifecycle.capture(target.siteUrl);

    try {
      DraftWriteException? localFailure;
      try {
        await drafts.write(
          target.siteUrl,
          target.draftKey,
          data,
          ifCurrent: () =>
              save.isCurrent() &&
              identical(_draftSaveRequests[key], request) &&
              lease.commit(() {}),
        );
      } on DraftWriteException catch (error) {
        localFailure = error;
      } catch (error) {
        localFailure = DraftWriteException(error);
      }
      if (!lease.commit(() {})) return null;

      // After the sync has given up, the local copy above is the whole save:
      // the site is not asked again, and the copy is not cleared.
      if (save.localOnly) {
        if (localFailure != null) throw localFailure;
        return null;
      }

      try {
        final credential = await _credentialForWrite(target.siteUrl);
        if (!lease.isCurrent) return null;
        if (credential.failure case final failure?) throw failure;
        final apiKey = credential.apiKey!;
        final clientId = await authenticator.clientId();
        if (!lease.isCurrent) return null;

        final sequence = await api.saveDraft(
          siteUrl: target.siteUrl,
          apiKey: apiKey,
          draftKey: target.draftKey,
          sequence: save.sequence,
          data: data,
          // Discourse uses this to tell the same account writing from somewhere
          // else apart from this client coming back.
          owner: clientId,
        );

        var clearLocal = false;
        lease.commit(() {
          if (sequence != null) _draftSequences[key] = sequence;
          if (!save.isCurrent() ||
              !identical(_draftSaveRequests[key], request)) {
            return;
          }

          if (!target.isNewTopic) {
            store.update<TopicDetail>(
              target.siteUrl,
              target.topicId,
              (detail) =>
                  detail.withDraft(save.draft, sequence ?? save.sequence),
            );
          }
          clearLocal = true;
        });
        if (clearLocal) {
          await drafts.clear(
            target.siteUrl,
            target.draftKey,
            ifCurrent: () =>
                save.isCurrent() &&
                identical(_draftSaveRequests[key], request) &&
                lease.commit(() {}),
          );
        }

        return sequence;
      } catch (_) {
        if (localFailure != null) throw localFailure;
        rethrow;
      }
    } finally {
      if (identical(_draftSaveRequests[key], request)) {
        _draftSaveRequests.remove(key);
      }
    }
  }

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
    return api.uploadComposerImage(
      siteUrl: target.siteUrl,
      apiKey: credential.apiKey!,
      clientId: await authenticator.clientId(),
      file: file,
      onProgress: onProgress,
      abortTrigger: abortTrigger,
      uploadType: target.isChat
          ? ComposerUploadType.chatComposer
          : ComposerUploadType.composer,
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
    return api.lookupUploadUrls(
      siteUrl: target.siteUrl,
      apiKey: held.value.apiKey!,
      clientId: identity.value,
      shortUrls: urls,
    );
  }

  void _startComposerDraftRestore(ComposerController composer) {
    final restore = _restoreDraft(composer);
    _composerDraftRestore = restore;
    unawaited(restore);
  }

  /// Puts an unfinished reply back in the composer.
  Future<void> _restoreDraft(ComposerController composer) async {
    final target = composer.target;
    final lease = lifecycle.capture(target.siteUrl);

    bool isCurrent() =>
        !isDisposed && lease.isCurrent && identical(_composer, composer);

    // The local copy exists only while the site does not have the text, so if
    // there is one it is the newer of the two by construction — no timestamps
    // to compare, and no chance of restoring over something newer.
    final local = ComposerDraft.decode(
      await drafts.read(target.siteUrl, target.draftKey),
    );
    if (!isCurrent()) return;
    ComposerDraft? remote;
    var remoteSequence = 0;
    if (local == null && target.isNewTopic) {
      try {
        final held = await _readSessionValue(
          lease,
          () => _credentialForWrite(target.siteUrl),
        );
        if (held == null || !isCurrent()) return;
        if (held.value.failure == null) {
          final found = await api.draft(
            siteUrl: target.siteUrl,
            apiKey: held.value.apiKey!,
            draftKey: target.draftKey,
          );
          remote = found.draft;
          remoteSequence = found.sequence;
        }
      } catch (_) {
        // A draft restore is best effort; opening the composer must still work.
      }
    }
    if (!isCurrent()) return;
    lease.commit(() {
      if (!identical(_composer, composer)) return;
      final draft =
          local ??
          remote ??
          (target.isNewTopic
              ? null
              : store.read<TopicDetail>(target.siteUrl, target.topicId)?.draft);
      if (draft == null) return;

      composer.restore(draft);
      composer.setMinimumRequiredTags(
        topicComposerCategories(target.siteUrl)
                .where((category) => category.id == composer.categoryId)
                .firstOrNull
                ?.minimumRequiredTags ??
            0,
      );
      if (target.isNewTopic && remoteSequence > 0) {
        composer.draftSequence = remoteSequence;
        _draftSequences[_draftKey(target.siteUrl, target.draftKey)] =
            remoteSequence;
      }
      if (draft.replyToPostNumber != null &&
          target.replyToPostNumber == null &&
          identical(_composer, composer)) {
        composer.retarget(
          replyToPostNumber: draft.replyToPostNumber,
          replyToUsername: draft.replyToUsername,
        );
      }
    });
  }

  /// Sends the open composer.
  ///
  /// Everything is resolved from the composer's own target rather than from
  /// whatever is current, so switching sites or topics mid-flight cannot
  /// redirect the post.
  Future<void> submitComposer() async {
    final composer = _composer;
    if (composer == null || composer.submitting || !composer.canSubmit) return;

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
      creation = target.isNewTopic
          ? await api.createTopic(
              siteUrl: target.siteUrl,
              apiKey: apiKey,
              title: composer.title.text.trim(),
              raw: raw,
              categoryId: composer.categoryId,
              tags: composer.tags,
              typingDuration: composer.typingDuration,
              composerOpenDuration: composer.openDuration,
              draftKey: target.draftKey,
            )
          : await api.createPost(
              siteUrl: target.siteUrl,
              apiKey: apiKey,
              topicId: target.topicId,
              raw: raw,
              replyToPostNumber: target.replyToPostNumber,
              typingDuration: composer.typingDuration,
              composerOpenDuration: composer.openDuration,
              draftKey: target.draftKey,
            );
    } on WriteException catch (e) {
      // A refusal is certain — the site answered and said no. Not reaching it
      // is not: the post may well have been created and only the answer lost.
      if (e.failure == WriteFailure.unreachable) {
        if (target.isNewTopic) {
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
      if (target.isNewTopic) {
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

    if (target.isNewTopic) {
      lease.commit(
        () => _applyTopicCreation(target, creation, composer, lease),
      );
    } else {
      lease.commit(() => _applyCreation(target, creation, composer, lease));
    }
  }

  /// Sends an edit.
  ///
  /// Much shorter than creating a post, and the reason is worth stating: an
  /// edit is idempotent. Sending the same raw twice leaves the post saying the
  /// same thing, so a failure needs no reconciliation — it is just a failure,
  /// and pressing the button again is safe.
  Future<void> _submitEdit(
    ComposerController composer,
    ComposerTarget target,
    String raw,
  ) async {
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
    // Both modes that reach here opened on an existing post, so a null
    // baseline means the body fetch failed and `raw` is whatever was typed
    // into the empty field, not the post. Sending it would replace the whole
    // post, and with no originalText the site's edit-conflict check would
    // not run either. `canSubmit` already refuses this, but that gate is
    // UI-level; the request must be impossible to build, not just to press.
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
        await api.updateTopic(
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
      updated = await api.updatePost(
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

    // Everything the edit says about the post, except what it says about what
    // this reader did — which is nothing, however confidently it is phrased.
    // `PostsController#update` serializes without the reader's own post
    // actions, so `actions_summary` comes back with no `acted` and a
    // `can_act: true` that is simply wrong on a post they have already liked.
    // Taken literally it would empty the heart of anyone who fixes a typo. The
    // plugins' view of the reader is absent the same way, and on a reactions
    // site dropping it would swap the footer back to the like one — whose
    // heart then writes through a route that destroys the reaction.
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
      await api.updateTopicTags(
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
      store.update<TopicDetail>(
        target.siteUrl,
        target.topicId,
        (detail) => detail.copyWith(tags: composer.tags),
      );
      store.update<Topic>(
        target.siteUrl,
        target.topicId,
        (topic) => topic.copyWith(tags: composer.tags),
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

  /// Runs the check again after one could not be completed.
  Future<void> recheckComposer() async {
    final composer = _composer;
    if (composer == null || !composer.canRecheck) return;
    if (composer.target.isNewTopic) {
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

  /// How far back to look for a post that may or may not have been made.
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
      final retained = await api.draft(
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
      final recent = await api.topicList(
        siteUrl: target.siteUrl,
        path: '/topics/created-by/${Uri.encodeComponent(username)}.json',
        apiKey: apiKey,
      );
      final matches = <TopicPayload>[];
      for (final row
          in recent.topics
              .where((topic) => topic.title == composer.title.text.trim())
              .take(_reconcileWindow)) {
        final payload = await api.topic(
          siteUrl: target.siteUrl,
          slug: row.slug,
          id: row.id,
          apiKey: apiKey,
        );
        final firstId = payload.detail.stream.firstOrNull;
        if (firstId == null) continue;
        final posts = await api.posts(
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

  /// After a failure that might have posted anyway, look before sending again.
  ///
  /// A user API key gets no idempotency from Discourse — the request memoizer
  /// is gated on `is_api?`, which needs a different header than ours — so a
  /// resend after a timeout publishes the post twice, and nothing undoes that.
  /// The only safe recovery is to re-read the topic and see.
  ///
  /// The comparison is against `raw` rather than the cooked HTML, because raw
  /// is exactly the string that was sent; cooking is a transformation this
  /// client deliberately does not reproduce.
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
      topic = await api.topic(
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

      posts = await api.posts(
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
    composer.draftSettled();
    unawaited(
      drafts.clear(
        target.siteUrl,
        target.draftKey,
        ifCurrent: () => lease.commit(() {}),
      ),
    );
    if (creation.draftSequence case final sequence?) {
      _draftSequences[_draftKey(target.siteUrl, target.draftKey)] = sequence;
      composer.draftSequence = sequence;
    }
    store.update<TopicDetail>(
      target.siteUrl,
      target.topicId,
      (detail) => detail.withDraft(null, _draftSequence(target)),
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
    composer.draftSettled();
    unawaited(
      drafts.clear(
        target.siteUrl,
        target.draftKey,
        ifCurrent: () => lease.commit(() {}),
      ),
    );
    if (creation.draftSequence case final sequence?) {
      _draftSequences[_draftKey(target.siteUrl, target.draftKey)] = sequence;
      composer.draftSequence = sequence;
    }
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
    composer.draftSettled();
    unawaited(
      drafts.clear(
        target.siteUrl,
        target.draftKey,
        ifCurrent: () => lease.commit(() {}),
      ),
    );
    _closeSubmittedComposer(composer);
    final origin = target.originFeedId;
    if (currentInstance?.url == target.siteUrl) {
      _openTopic(topicId, slug, title);
      if (origin != null) unawaited(loadFeed(origin, force: true));
    }
  }

  /// Re-reads a topic on a named site, rather than on whatever is current.
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
      final topic = await api.topic(
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
      // The post is already on screen; the stream is repaired next time.
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

  /// The card for [username] on the current site, once it has arrived.
  ///
  /// Read under the lowercased name, the way [UserCard.storeId] files it —
  /// the requested casing and the payload's are not reliably the same.
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

  /// Fetches the card for [username] unless it is already in hand.
  ///
  /// Cards are cached for the life of the session: the same handful of people
  /// write most of a topic, and re-opening a card should be instant.
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
      final card = await api.userCard(
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

  /// Appends the next page, if there is one and nothing is already in flight.
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

  /// What a hashtag row draws on its left, from the style the site reported.
  ///
  /// The same three shapes the cooked pill has, and for the same reason: a row
  /// that looked different from what the post will look like would be
  /// offering something other than what it writes.
  static SuggestionArt _hashtagArt(FoundHashtag hashtag) =>
      switch (hashtag.styleType) {
        'emoji' when hashtag.emoji != null => ArtIcon(hashtag.icon),
        'icon' => ArtIcon(
          hashtag.icon,
          colorValue: hashtag.colorValues.isEmpty
              ? null
              : hashtag.colorValues.last,
        ),
        // A tag has no colour of its own, so it keeps its glyph rather than
        // drawing an empty swatch.
        _ when hashtag.type != 'category' => ArtIcon(hashtag.icon),
        _ => ArtSquare(hashtag.colorValues),
      };

  /// What each site has said a `#ref` is. A null value is a ref it was asked
  /// about and did not have — remembered, so it is not asked twice.
  ///
  /// The composer may encounter new refs for an entire long-running session.
  /// Keep the most recent answers rather than turning that stream into an
  /// unbounded per-site dictionary. Entries in flight are never evicted.
  static const int composerIdentityCacheCapacity = 2048;

  final Map<String, BoundedLruCache<String, FoundHashtag?>> _hashtags = {};
  final Map<String, Set<String>> _hashtagsInFlight = {};

  /// The same, for usernames: true is somebody, false is nobody.
  final Map<String, BoundedLruCache<String, bool>> _mentioned = {};
  final Map<String, Set<String>> _mentionsInFlight = {};

  /// Categories and tags matching [term].
  ///
  /// Never throws, for the reason [searchUsers] gives: a popup that says
  /// "could not reach the site" while somebody is mid-word is noise.
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
      found = await api.searchHashtags(
        siteUrl: siteUrl,
        term: term,
        order: [
          ...DiscourseApi.hashtagOrder,
          if (_pluginSession.capabilities<PluginComposerTargetProvider>().any(
            (provider) =>
                provider.supportsPluginComposerTarget(siteUrl, 'room'),
          ))
            'room',
        ],
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

  /// What the composer needs before it may draw a pill over what is typed.
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
            target.isChat ? null : target.topicId,
            usernames,
          ),
        );
      },
    );
  }

  /// Asks what [refs] are, once each.
  ///
  /// Anything already answered or already in flight is dropped here rather
  /// than by the caller, which repaints far more often than it learns anything
  /// new. A failure is left unanswered rather than remembered as one: the site
  /// being unreachable says nothing about whether a category exists, and the
  /// next repaint may as well ask again.
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
      final found = await api.lookupHashtags(
        siteUrl: siteUrl,
        refs: ask,
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
      // The ref stays text and remains eligible for a later retry.
    } finally {
      if (!isDisposed) lease.commit(() => inFlight.removeAll(ask));
    }
  }

  /// The same for usernames, through `/composer/mentions`.
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
      final real = await api.checkMentions(
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
      // As above.
    } finally {
      if (!isDisposed) lease.commit(() => inFlight.removeAll(ask));
    }
  }

  /// Accounts matching [term] in [topicId].
  ///
  /// Never throws. A popup that says "could not reach the site" while somebody
  /// is mid-word is noise; an empty list simply closes it, and the mention can
  /// still be typed out by hand.
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
      found = await api.searchUsers(
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

  /// Whether a shortcode names emoji this site is known to serve; see
  /// [SitePresentationController.knowsEmoji] for what false covers.
  bool knowsEmoji(String siteUrl, String name) =>
      _presentation.knowsEmoji(siteUrl, name);

  /// Opaque identity for widgets whose presentation depends on this site's
  /// settings or custom emoji artwork.
  Object presentationTokenFor(String siteUrl) =>
      _presentation.presentationTokenFor(siteUrl);

  /// What a site's client settings said, or core's defaults where it has not
  /// answered. Never null, and never a loading state — see [SiteConfig].
  ///
  /// What was stored last launch stands in until this session has asked, which
  /// is what keeps a site drawing its own emoji set through the first topic
  /// rather than drawing twitter's and correcting itself.
  SiteConfig siteConfigFor(String siteUrl) => _presentation.configFor(siteUrl);

  /// Waits for client settings the site actually supplied when a choice of
  /// route or interaction cannot safely be made from defaults alone.
  Future<SiteConfig?> resolveSiteConfig(String siteUrl) =>
      _presentation.resolveConfig(siteUrl);

  /// The same, for the site on screen.
  SiteConfig get currentSiteConfig {
    final instance = currentInstance;
    return instance == null
        ? const SiteConfig.unknown()
        : siteConfigFor(instance.url);
  }

  /// The resolved color appearance for [siteUrl], if this Discourse exposes
  /// modern color-definition stylesheets.
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

  /// A creation capability is useful only after this app session has asked
  /// the site. An old persisted `true` is deliberately treated as unknown.
  bool canCreatePollFor(String siteUrl) =>
      _sessionUsersRefreshed.contains(siteUrl) &&
      _instanceAt(siteUrl)?.user?.canCreatePoll == true;

  bool get canCreatePoll {
    final siteUrl = currentInstance?.url;
    return siteUrl != null && canCreatePollFor(siteUrl);
  }

  DiscourseUser? currentUserFor(String siteUrl) => _instanceAt(siteUrl)?.user;

  DiscourseUser? freshCurrentUserFor(String siteUrl) =>
      _sessionUsersRefreshed.contains(siteUrl)
      ? _instanceAt(siteUrl)?.user
      : null;

  /// Assign added per-target capabilities after its session-wide capability.
  /// An explicit target answer always wins; only an absent answer may use a
  /// freshly fetched session value. Persisted capabilities are never enough
  /// to authorize a write, and absent/disabled plugins serialize neither.
  bool canAssignForTarget(String siteUrl, bool? targetCanAssign) =>
      targetCanAssign ??
      (!_assignLegacyFallbackUnavailable.contains(siteUrl) &&
          freshCurrentUserFor(siteUrl)?.canAssign == true);

  PluginTargetSnapshot _pluginDataForTarget(
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
    final held = _instanceAt(siteUrl);
    if (held == null || held.config == config) return;
    _replaceInstance(held, held.copyWith(config: config));
    await instanceStore.save(List.of(_instances));
  }

  /// Categories are fetched once per site; the topic rows need them to draw
  /// their badges, and they change rarely.
  Future<void> loadCategories(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance != null) await _ensureCategoriesFor(instance);
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
      final result = await api.loadCategories(
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

  /// Appends the next server page to the full categories destination.
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

      final result = await api.loadCategories(
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

  /// Sends the user to the current site to authorize, then records who they
  /// turned out to be.
  Future<void> connectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null || _connectingSiteUrl != null) return;
    var lease = lifecycle.capture(instance.url);
    UserApiCredentials? credentials;

    _connectingSiteUrl = instance.url;
    _connectErrors.remove(instance.url);
    _notify();

    try {
      // Read before the handshake: connecting mints a fresh key and stores it
      // over whatever was there.
      final previousKey = await authenticator.apiKeyFor(instance.url);
      if (!lease.isCurrent || _instanceAt(instance.url) == null) return;

      final connectedCredentials = await authenticator.connect(instance.url);
      credentials = connectedCredentials;
      if (!lease.isCurrent || _instanceAt(instance.url) == null) {
        await _discardCredentials(instance.url, connectedCredentials.key);
        return;
      }

      _forgetSiteState(instance.url);
      lease = lifecycle.capture(instance.url);

      DiscourseInstance? pending;
      lease.commit(() {
        final held = _instanceAt(instance.url);
        if (held == null) return;
        pending = held.copyWith(
          apiVersion: connectedCredentials.apiVersion,
          clearUser: true,
          clearConfig: true,
          clearAppearance: true,
        );
        _replaceInstance(held, pending!);
        _notify();
      });
      if (pending == null) {
        await _discardCredentials(instance.url, connectedCredentials.key);
        return;
      }

      // The handshake has already replaced the key. Persist the matching
      // signed-out boundary before anything else can fail, so account A's
      // profile is never restored from disk beside account B's key.
      await instanceStore.save(List.of(_instances));
      if (!lease.isCurrent) return;
      await drafts.clearSite(instance.url);
      if (!lease.isCurrent) return;

      // Reconnecting over an existing key leaves the old one live in the
      // account's authorized-apps list with nothing tying it back to this
      // install, so revoke it the way a disconnect does. Best effort, for the
      // reason `_revokeAndForget` tolerates failure: being offline must not
      // stand in the way of connecting. The revocation cannot run before the
      // handshake — backing out of the browser must not cost the key still in
      // use.
      if (previousKey != null && previousKey != connectedCredentials.key) {
        try {
          await api.revokeApiKey(siteUrl: instance.url, apiKey: previousKey);
        } catch (error, stackTrace) {
          if (lease.isCurrent) {
            _reportOperationalError(
              error,
              stackTrace,
              'authentication.revokePreviousKey',
              severity: DiagnosticSeverity.warning,
            );
          }
        }
      }
      if (!lease.isCurrent) return;

      final user = await api.currentUser(
        siteUrl: instance.url,
        apiKey: connectedCredentials.key,
      );
      if (!lease.isCurrent) return;

      // The signed-out boundary above deliberately lasts while the replacement
      // account is being verified. Re-entering the site during that await can
      // start an anonymous appearance refresh in the same generation. Rotate
      // once more before publishing the connected identity so a completed
      // public palette is not cached as the account palette, and a late public
      // response cannot overwrite the authenticated refresh started below.
      _forgetSiteState(instance.url);
      lease = lifecycle.capture(instance.url);

      DiscourseInstance? connected;
      final accepted = lease.commit(() {
        final held = _instanceAt(instance.url);
        if (held == null) return;
        connected = held.copyWith(
          user: user,
          apiVersion: connectedCredentials.apiVersion,
        );
        _replaceInstance(held, connected!);
        _sessionUsersRefreshed.add(instance.url);
        if (currentInstance?.url == instance.url) {
          // The anonymous palette may have completed while the account lookup
          // was in flight. This identity boundary must bypass warm persisted
          // freshness and fetch the authenticated palette exactly once.
          _resetToInstanceDefault(refreshAppearance: false);
          unawaited(_presentation.refreshAppearance(instance.url));
        }
        _notify();
      });
      if (!accepted || connected == null) return;

      await instanceStore.save(List.of(_instances));
      if (lease.isCurrent) {
        unawaited(_refreshOne(connected!));
        unawaited(
          _refreshCustomSidebarSections(instance.url, connectedCredentials.key),
        );
      }
    } on UserApiAuthException catch (e, stackTrace) {
      if (credentials != null && lease.isCurrent) {
        lease = await _rollbackConnection(instance, credentials, lease);
      }
      if (!lease.isCurrent) return;
      // Backing out of the browser is a normal thing to do, not an error.
      // Everything else has to be said out loud, or the button simply stops
      // spinning and the user is left guessing. A switch rather than a
      // ternary so the analyzer flags the next value someone adds.
      final message = switch (e.failure) {
        UserApiAuthFailure.cancelled => null,
        UserApiAuthFailure.launchFailed ||
        UserApiAuthFailure.badReply => e.message,
      };
      if (e.failure != UserApiAuthFailure.cancelled) {
        _reportOperationalError(e, stackTrace, 'authentication.connect');
      }
      if (message == null) {
        _connectErrors.remove(instance.url);
      } else {
        _connectErrors[instance.url] = message;
      }
    } on SiteLookupException catch (e, stackTrace) {
      if (credentials != null && lease.isCurrent) {
        lease = await _rollbackConnection(instance, credentials, lease);
      }
      if (!lease.isCurrent) return;
      _reportOperationalError(e, stackTrace, 'authentication.loadAccount');
      _connectErrors[instance.url] = e.message;
    } catch (e, stackTrace) {
      if (credentials != null && lease.isCurrent) {
        lease = await _rollbackConnection(instance, credentials, lease);
      }
      if (!lease.isCurrent) return;
      _reportOperationalError(e, stackTrace, 'authentication.connect');
      _connectErrors[instance.url] = 'Could not connect to ${instance.host}.';
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

  Future<SiteLease> _rollbackConnection(
    DiscourseInstance instance,
    UserApiCredentials credentials,
    SiteLease lease,
  ) async {
    if (!lease.isCurrent) return lease;

    // A connected user becomes visible before the final persistence write so
    // the shell can reset their personalized navigation. If that write fails,
    // make the local identity boundary explicit before any async cleanup: no
    // view should keep presenting an account whose new key is being removed.
    _forgetSiteState(instance.url);
    final rollbackLease = lifecycle.capture(instance.url);
    rollbackLease.commit(() {
      final held = _instanceAt(instance.url);
      if (held == null) return;
      _replaceInstance(
        held,
        held.copyWith(
          clearUser: true,
          clearConfig: true,
          clearAppearance: true,
        ),
      );
      if (currentInstance?.url == instance.url) {
        // The replacement key still lives in the credential store until the
        // cleanup below finishes. Reset the signed-out navigation now, but do
        // not let its optional appearance refresh race that account boundary.
        _resetToInstanceDefault(refreshAppearance: false);
      }
      _notify();
    });

    final credentialsDiscarded = await _discardCredentials(
      instance.url,
      credentials.key,
    );
    if (!rollbackLease.isCurrent) return rollbackLease;

    // The failure may have been the signed-out boundary or the final connected
    // snapshot. Either way, leave the durable value matching the discarded key
    // when the platform store recovers. A second attempt covers the transient
    // failure mode without turning connection into an unbounded retry loop.
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!rollbackLease.isCurrent) break;
      try {
        await instanceStore.save(List.of(_instances));
        break;
      } catch (_) {}
    }
    if (credentialsDiscarded &&
        rollbackLease.isCurrent &&
        currentInstance?.url == instance.url &&
        !instance.loginRequired) {
      // This read is now necessarily anonymous. If deleting the local key
      // failed, retaining native colors is safer than presenting another
      // account-derived palette on a signed-out instance.
      unawaited(_presentation.ensureAppearance(instance.url));
    }
    return rollbackLease;
  }

  Future<bool> _discardCredentials(String siteUrl, String apiKey) async {
    try {
      await api.revokeApiKey(siteUrl: siteUrl, apiKey: apiKey);
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'authentication.revokeKey',
        severity: DiagnosticSeverity.warning,
      );
    }
    try {
      await authenticator.disconnect(siteUrl);
      return true;
    } catch (error, stackTrace) {
      _reportOperationalError(
        error,
        stackTrace,
        'authentication.deleteCredential',
        severity: DiagnosticSeverity.warning,
      );
      return false;
    }
  }

  /// Forgets the key and who we were, leaving the site in the rail.
  Future<void> disconnectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null) return;

    await disconnectInstance(instance.url);
  }

  /// Forgets the key and account belonging to [siteUrl].
  ///
  /// Returns whether the signed-out rail snapshot was persisted. A failure to
  /// make the private-draft boundary durable leaves the account and key intact.
  Future<bool> disconnectInstance(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance == null) return false;

    final lease = await _revokeAndForget(instance);
    if (lease == null) return false;
    final accepted = lease.commit(() {
      final held = _instanceAt(instance.url);
      if (held == null) return;
      // The settings go with the key. On a `login_required` site they were only
      // readable as that account, so keeping an answer that can no longer be
      // refreshed would leave the shell drawing something it cannot correct.
      _replaceInstance(
        held,
        held.copyWith(
          clearUser: true,
          clearConfig: true,
          clearAppearance: true,
        ),
      );
      if (currentInstance?.url == instance.url) _resetToInstanceDefault();
      _notify();
    });
    if (!accepted) return false;

    try {
      await instanceStore.save(List.of(_instances));
      return true;
    } catch (_) {
      if (isDisposed || !lease.isCurrent) return false;
      try {
        // Shared-preferences writes are idempotent. Retrying the latest
        // snapshot prevents a transient platform failure from restoring a
        // stale connected profile beside a key that has already been deleted.
        await instanceStore.save(List.of(_instances));
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Tells the site to drop the key before we drop our copy.
  ///
  /// Deleting locally is not enough: the key would stay live in the user's
  /// authorized-apps list with no way for them to connect it to us.
  Future<SiteLease?> _revokeAndForget(DiscourseInstance instance) async {
    _forgetSiteState(instance.url);
    final lease = lifecycle.capture(instance.url);

    // Persist the private-text boundary before revoking or deleting the key.
    // If storage cannot retain the blocker, abort while the account and its
    // credential still agree instead of leaving connected UI backed by no key.
    try {
      await drafts.clearSite(instance.url, ifCurrent: () => lease.isCurrent);
    } catch (_) {
      return null;
    }
    if (!lease.isCurrent) return lease;

    String? apiKey;
    try {
      apiKey = await authenticator.apiKeyFor(instance.url);
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'authentication.readCredentialForDisconnect',
          severity: DiagnosticSeverity.warning,
        );
      }
      // The local account boundary has already been cleared.
    }
    if (!lease.isCurrent) return lease;
    if (apiKey != null) {
      try {
        await api.revokeApiKey(siteUrl: instance.url, apiKey: apiKey);
      } catch (error, stackTrace) {
        if (lease.isCurrent) {
          _reportOperationalError(
            error,
            stackTrace,
            'authentication.revokeKey',
            severity: DiagnosticSeverity.warning,
          );
        }
        // Forget locally even when the site cannot be reached.
      }
    }
    if (!lease.isCurrent) return lease;
    try {
      await authenticator.disconnect(instance.url);
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(
          error,
          stackTrace,
          'authentication.deleteCredential',
          severity: DiagnosticSeverity.warning,
        );
      }
      // Connecting again overwrites a key local storage could not remove.
    }
    if (!lease.isCurrent) return lease;

    // Revocation is asynchronous, so switching away and back can start fresh
    // account-bound work in this generation. Forget once more before the
    // caller commits removal or sign-out: completed state is dropped and late
    // responses lose their lease. The caller receives the replacement lease
    // so its persistence work still belongs to the new boundary.
    _forgetSiteState(instance.url);
    return lifecycle.capture(instance.url);
  }

  void _forgetSiteState(String siteUrl) {
    lifecycle.invalidate(siteUrl);
    siteImages.forget(siteUrl);
    _removeWorkspace(siteUrl);
    if (currentInstance?.url == siteUrl) search.clear();
    _draftSaveRequests.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _draftSequences.removeWhere((key, _) => key.startsWith('$siteUrl#'));

    final composer = _composer;
    if (composer?.target.siteUrl == siteUrl) {
      composer!.draftSettled();
      composer.dispose();
      _composer = null;
    }

    accountActivity.forget(siteUrl);
    draftList.forget(siteUrl);
    userSummary.forget(siteUrl);
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
    _chatBookmarkWritesInFlight.removeWhere(
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
    _categoryFeeds.remove(siteUrl);
    _categoryPageRequests.remove(siteUrl);
    _categorySidebarCache.remove(siteUrl);
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

    _observePluginLifecycle(
      _pluginSession.forget(siteUrl),
      'plugins.session.forget',
    );
    topicFeeds.forget(siteUrl);
    _trackersStarting.remove(siteUrl);
    _sessionUsersRefreshed.remove(siteUrl);
    _assignLegacyFallbackUnavailable.remove(siteUrl);
    _sessionUserRequests.remove(siteUrl)?.ignore();
    _userStatusOverrides.remove(siteUrl);
    _userStatusWrites.remove(siteUrl);
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
      // Titles draw only the shortcodes the catalog vouches for, so it is a
      // dependency of the first topic list rather than of the composer that
      // used to be the only thing asking. Warmed alongside the feed, it lands
      // with the rows instead of turning every title into a second frame, and
      // warming retries a failure rather than inheriting the picker's
      // give-up-for-the-session verdict.
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
    // so activation itself must apply its chat capability instead of relying
    // on a callback which only runs after network responses.
    _notifyPluginTotals(instance);
    if (canRead && hydrateActiveTab) _hydrateActiveTab(instance);
  }

  void _hydrateActiveTab(DiscourseInstance instance) {
    final tab = activeTab;
    if (tab == null || currentInstance?.url != instance.url) return;

    final root = tab.contentStack.first;
    unawaited(
      loadFeed(root.feedPath == null ? tab.rootDestinationId : root.id),
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

  /// Tapping the already-selected instance is how you get back to its sidebar
  /// on a phone, where the sidebar and the content cannot both be visible.
  @override
  void selectInstance(int index) {
    assert(index >= 0 && index < _instances.length);
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

  /// Opens the app-wide topic stream and refreshes it when its snapshot is old.
  void selectAggregate() {
    if (!loaded || !hasInstances) return;
    _rootMode = ShellRootMode.aggregate;
    _mobilePane = MobilePane.content;
    _notify();
    unawaited(aggregate.open(_instances));
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

  /// Opens an Aggregate row in its owning forum.
  ///
  /// Desktop gives a topic its own forum tab and reuses an exact existing one.
  /// Mobile retains its single navigation context and replaces the current
  /// forum surface, matching every other topic-list tap there.
  AggregateTopicOpenResult openAggregateTopic(String siteUrl, int topicId) {
    final topic = store.read<Topic>(siteUrl, topicId);
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (topic == null || index < 0) {
      return AggregateTopicOpenResult.unavailable;
    }

    final instance = _instances[index];

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
      // Aggregate remains on screen, with the previously selected forum still
      // underneath it, so the failed click has no navigation side effect.
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
    final instance = currentInstance;
    if (instance == null) return;
    final tab = _ensureWorkspace(instance).activeTab;
    // Tapping what you are already looking at asks for it again — the cache
    // otherwise holds a list for the life of the session, and a mouse cannot
    // pull to refresh. Only at the destination's root: a tap that is busy
    // returning from a topic stays a return.
    final refresh =
        destination.id == tab.rootDestinationId && tab.contentStack.length <= 1;

    _replaceActiveTab(
      tab.copyWith(
        rootDestinationId: destination.id,
        contentStack: [ContentRoute.fromDestination(destination)],
      ),
    );
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();

    unawaited(loadFeed(destination.id, force: refresh));
  }

  /// Adds a fresh Topics work context to the selected forum and opens it.
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

  /// Activates one of the tabs owned by the selected forum.
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

  /// Moves one of the selected forum's tabs without changing its active tab.
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

  /// Closes a tab in the selected forum without affecting any other forum.
  ///
  /// When the active tab closes, its right neighbour wins, falling back to the
  /// left at the end of the list. The forum always keeps one fresh Topics tab.
  void closeTab(String id) {
    if (!forumTabsEnabled) return;
    final instance = currentInstance;
    final workspace = currentWorkspace;
    if (instance == null || workspace == null) return;
    final index = workspace.tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;

    if (_composer?.target.tabId == id) closeComposer();

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

  /// Keeps one tab in the selected forum and closes every sibling tab.
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

  /// Opens the Drafts destination for [siteUrl], including from a profile menu
  /// that stayed open while another site became selected.
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

  /// Opens the connected account's restorable native Summary destination.
  void openUserSummary(String siteUrl) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || _instances[index].user == null) return;
    if (index != _instanceIndex) selectInstance(index);
    if (currentContent?.id == 'summary') return;
    pushContent(
      const ContentRoute(id: 'summary', title: 'Summary', icon: DIcons.user),
    );
  }

  /// Opens the native Preferences page for the account which owned the menu.
  ///
  /// A touch sheet can remain alive while another forum becomes selected, so
  /// the source URL is resolved again instead of assuming the current forum.
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

  /// Restores a draft into the composer mode this client supports.
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
      composer
        ..draftSequence = draft.sequence
        ..restore(draft.data!);
      _draftSequences[_draftKey(siteUrl, draft.key)] = draft.sequence;
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
    composer
      ..draftSequence = draft.sequence
      ..restore(draft.data!);
    _draftSequences[_draftKey(siteUrl, draft.key)] = draft.sequence;
  }

  /// Replaces the main region with something deeper, keeping a way back.
  @override
  void pushContent(ContentRoute route) {
    final tab = activeTab;
    if (tab == null) return;
    _replaceActiveTab(tab.push(route));
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();
  }

  /// Replaces the top route without changing the content stack's Back target.
  @override
  void replaceCurrentContent(ContentRoute route) {
    final tab = activeTab;
    if (tab == null) return;
    _replaceActiveTab(
      tab.copyWith(
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
    if (_mobilePane == MobilePane.content) return;
    _mobilePane = MobilePane.content;
    _notify();
  }

  /// Opens the active call's room even when its site is not the one currently
  /// selected. The call itself stays untouched; only navigation moves.
  void openResenhaRoom({
    required String siteUrl,
    required ContentRoute route,
    bool replaceCurrent = false,
  }) {
    final index = _instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0) return;
    final sameInstance = index == _instanceIndex;
    if (index != _instanceIndex) {
      _instanceIndex = index;
      _restoreInstanceWorkspace();
    }
    if (sameInstance && currentContent?.id == route.id) {
      // The sidebar secondary action and the persistent call card can both
      // open the room already on screen. Replacing its metadata keeps the
      // route fresh without adding an indistinguishable stack entry that
      // would make the first Back press appear to do nothing.
      final tab = activeTab!;
      _replaceActiveTab(
        tab.copyWith(
          contentStack: [
            ...tab.contentStack.take(tab.contentStack.length - 1),
            route,
          ],
        ),
      );
      _mobilePane = MobilePane.content;
      _syncTopicChannels();
      _notify();
      return;
    }
    if (replaceCurrent && sameInstance && contentStack.isNotEmpty) {
      final tab = activeTab!;
      _replaceActiveTab(
        tab.copyWith(
          contentStack: [
            ...tab.contentStack.take(tab.contentStack.length - 1),
            route,
          ],
        ),
      );
      _mobilePane = MobilePane.content;
      _syncTopicChannels();
      _notify();
      return;
    }
    pushContent(route);
  }

  /// Unwinds one step: first through the content stack, then — on compact
  /// layouts only — back out to the sidebar.
  ///
  /// Returns false when there is nothing left to unwind, which is the signal
  /// to let the platform handle the back gesture.
  bool handleBack({bool canReturnToSidebar = true}) {
    if (_rootMode == ShellRootMode.aggregate) {
      _rootMode = ShellRootMode.forum;
      _mobilePane = MobilePane.sidebar;
      _notify();
      return true;
    }
    if (canPopContent) {
      final tab = activeTab!;
      _replaceActiveTab(
        tab.copyWith(
          contentStack: tab.contentStack
              .take(tab.contentStack.length - 1)
              .toList(),
        ),
      );
      _syncTopicChannels();
      _notify();
      return true;
    }
    if (canReturnToSidebar && _mobilePane == MobilePane.content) {
      _mobilePane = MobilePane.sidebar;
      _notify();
      return true;
    }
    return false;
  }

  void _notify() => notifySafely();

  @override
  void dispose() {
    final composer = _composer;
    if (composer != null && composer.draftPersistencePending) {
      final target = composer.target;
      final data = composer.draft.encode();
      // This is the last local safety boundary. It must enter DraftStore's
      // per-site queue before lifecycle invalidation below, and must not use
      // the normal callback because that can continue into remote sync.
      // DraftStore diagnoses the underlying persistence failure; disposal has
      // no live composer left to surface its wrapper error, so observe it here.
      Future<void>.sync(
        () => drafts.write(target.siteUrl, target.draftKey, data),
      ).ignore();
    }

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
    draftList.dispose();
    userSummary.dispose();
    preferences.dispose();
    topicFeeds.dispose();
    aggregate.dispose();
    siteImages.dispose();
    final closePluginSession = _pluginSession.close();
    _observePluginLifecycle(closePluginSession, 'plugins.session.close');
    if (_ownsPlugins) {
      _observePluginLifecycle(
        closePluginSession.then((_) => plugins.close()),
        'plugins.close',
      );
    }
    search.dispose();
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
