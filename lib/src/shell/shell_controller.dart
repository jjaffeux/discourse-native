import 'dart:async';
// Only for the category badge colour a list route carries; the shell otherwise
// has no opinion about how anything is painted.
import 'dart:ui' show Color;

import '../data/authenticator.dart';
import '../data/discourse_api.dart';
import '../data/draft_store.dart';
import '../data/instance_store.dart';
import '../data/site_lifecycle.dart';
import '../data/site_tracker.dart';
import '../data/store.dart';
import '../data/update_store.dart';
import '../data/updater.dart';
import '../data/user_api_key.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/bookmark_feed.dart';
import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/list_link.dart';
import '../models/notification.dart';
import '../models/notification_feed.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
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
import '../plugins/chat/chat_controller.dart';
import '../plugins/chat/chat_plugin.dart';
import '../plugins/poll/poll.dart';
import '../plugins/reactions/reaction.dart';
import '../plugins/reactions/reactions_controller.dart';
import '../plugins/resenha/resenha_api.dart';
import '../plugins/resenha/resenha_controller.dart';
import '../plugins/site_plugin.dart';
import '../theme/d_icons.dart';
import 'account_activity_controller.dart';
import 'composer_autocomplete.dart';
import 'composer_controller.dart';
import 'composer_pills.dart';
import 'composer_triggers.dart';
import 'draft_list_controller.dart';
import 'shell_search_controller.dart';
import 'site_presentation_controller.dart';
import 'site_url.dart';
import 'update_controller.dart';

/// Which pane occupies the space next to the rail when the shell is compact.
///
/// Only one of them can be on screen at a time on a phone; the rail itself is
/// always visible alongside whichever one is showing.
enum MobilePane { sidebar, content }

enum InstanceLoadStatus { loading, ready, failed }

typedef _WriteCredential = ({String? apiKey, WriteException? failure});

typedef _TopicReadReceipt = ({
  String siteUrl,
  int topicId,
  int postNumber,
  SiteLease lease,
});

/// What a native poll write learned.
///
/// [reconciled] means the write response was unreachable and the owning post
/// was read again. Presentation must discard its optimistic local selection,
/// even when the refetched saved selection happens to equal the old one.
final class PollVoteWriteResult {
  const PollVoteWriteResult.saved() : message = null, reconciled = false;

  const PollVoteWriteResult.reconciled() : message = null, reconciled = true;

  const PollVoteWriteResult.refused(this.message) : reconciled = false;

  final String? message;
  final bool reconciled;
}

/// Everything the shell needs to decide what to draw.
///
/// Uses Flutter's notifier contract directly, without a state-management
/// dependency. [FrameSafeNotifier] only centralizes disposal and frame timing.
class ShellController extends FrameSafeNotifier {
  ShellController({
    required this.instanceStore,
    required this.api,
    required this.authenticator,
    required this.drafts,
    Store? store,
    SiteLifecycle? lifecycle,
    this.trackers = SiteTracker.new,
    Updater updater = const UnsupportedUpdater(),
    UpdateStore? updateStore,
    this.ownsApi = true,
  }) : store = store ?? Store(),
       lifecycle = lifecycle ?? SiteLifecycle(),
       updates = UpdateController(
         updater: updater,
         store: updateStore ?? UpdateStore(),
       );

  final InstanceStore instanceStore;

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

  final Authenticator authenticator;
  final DraftStore drafts;
  final SiteLifecycle lifecycle;

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

  Future<_WriteCredential> _credentialForWrite(String siteUrl) async {
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

  /// The one global, transient search interaction. Its notifier is consumed by
  /// the field and result panel alone, so typing never redraws the shell.
  late final ShellSearchController search = ShellSearchController(
    api: api,
    credentials: authenticator,
    lifecycle: lifecycle,
  );

  /// Who reacted to what, on a site that has the reactions plugin.
  ///
  /// The same escape valve, for the same reason: opening one reactor list
  /// should redraw that list rather than every post in the topic. `late final`
  /// so it can be handed the [store] this constructor resolved.
  late final ReactionsController reactions = ReactionsController(
    api: api,
    credentials: authenticator,
    store: store,
    lifecycle: lifecycle,
  );

  /// The chat channels a site has, and the messages in the one on screen.
  ///
  /// Its notifications are consumed by the chat navigation and channel view,
  /// so paging a channel does not rebuild unrelated shell regions.
  late final ChatController chat = ChatController(
    api: api,
    credentials: authenticator,
    store: store,
    lifecycle: lifecycle,
  );

  /// Voice/video rooms across every connected site. Unlike topic and chat
  /// state this owns one app-global media session, so it deliberately survives
  /// switching the selected site.
  late final ResenhaController resenha = ResenhaController(
    api: ResenhaApi(api),
    chatApi: api,
    credentials: authenticator,
    trackerFor: (siteUrl) => _trackers[siteUrl],
    userIdFor: (siteUrl) => _instanceAt(siteUrl)?.user?.id,
    onCallSiteChanged: _syncTracking,
  );

  SitePresentationController? _sitePresentation;

  SitePresentationController get _presentation =>
      _sitePresentation ??= _createSitePresentationController();

  SitePresentationController _createSitePresentationController() {
    final controller = SitePresentationController(
      loadAppearance: _loadSiteAppearance,
      loadConfig: api.siteConfig,
      loadCustomEmojis: api.customEmojis,
      loadEmojis: api.emojis,
      credentials: authenticator,
      lifecycle: lifecycle,
      readPersistedAppearance: (siteUrl) => _instanceAt(siteUrl)?.appearance,
      readPersistedConfig: (siteUrl) => _instanceAt(siteUrl)?.config,
      onAppearanceLoaded: _persistSiteAppearance,
      onConfigLoaded: _persistSiteConfig,
      onEmojiIndexChanged: () => _composer?.autocomplete.refresh(),
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

  String? _connectingSiteUrl;

  /// True while the authorize flow is open, so the UI can show progress.
  bool get connecting => _connectingSiteUrl == currentInstance?.url;

  final Map<String, String> _connectErrors = {};

  String? get connectError {
    final siteUrl = currentInstance?.url;
    return siteUrl == null ? null : _connectErrors[siteUrl];
  }

  final List<DiscourseInstance> _instances = [];
  List<DiscourseInstance> get instances => List.unmodifiable(_instances);
  bool get hasInstances => _instances.isNotEmpty;

  InstanceLoadStatus _loadStatus = InstanceLoadStatus.loading;

  InstanceLoadStatus get loadStatus => _loadStatus;

  /// False until the stored sites have been read, so the shell can avoid
  /// flashing the empty state on launch.
  bool get loaded => _loadStatus == InstanceLoadStatus.ready;

  int _instanceIndex = 0;
  int get instanceIndex => _instanceIndex;
  DiscourseInstance? get currentInstance =>
      hasInstances ? _instances[_instanceIndex] : null;

  String? _destinationId;

  /// Id of the highlighted sidebar entry, or null once the user has navigated
  /// deeper than the entry the stack started from.
  String? get destinationId => _destinationId;

  final List<ContentRoute> _contentStack = [];
  List<ContentRoute> get contentStack => List.unmodifiable(_contentStack);
  ContentRoute? get currentContent =>
      _contentStack.isEmpty ? null : _contentStack.last;
  bool get canPopContent => _contentStack.length > 1;

  MobilePane _mobilePane = MobilePane.sidebar;
  MobilePane get mobilePane => _mobilePane;

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
    _instanceIndex = 0;
    _resetToInstanceDefault();
    _loadStatus = InstanceLoadStatus.ready;
    _notify();

    // Whether a newer build exists is not something anyone is waiting on, and
    // a failure here has to stay quiet. See UpdateController.check.
    unawaited(updates.load());

    // Counters are stale from the moment they were stored, so pull fresh ones
    // for every connected site. Deliberately not awaited by callers.
    unawaited(_refreshTotals());
    // Poll creation, staff status, and group eligibility are authorization
    // inputs. Refresh them for every connected site once this app session,
    // not only when that site happens to become the selected one.
    unawaited(_refreshSessionUsers());
  }

  bool contains(String url) => _instances.any((i) => i.url == url);

  /// Appends a connected site and selects it.
  Future<bool> addInstance(DiscourseInstance instance) async {
    await load();
    if (isDisposed || !loaded) return false;
    if (contains(instance.url)) return true;

    final previousSiteUrl = currentInstance?.url;
    final previousDestinationId = _destinationId;
    final previousContent = List.of(_contentStack);
    final previousPane = _mobilePane;

    _instances.add(instance);
    _instanceIndex = _instances.length - 1;
    _resetToInstanceDefault();
    _mobilePane = MobilePane.sidebar;
    _notify();

    try {
      await instanceStore.save(List.of(_instances));
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
          return true;
        } catch (_) {
          return false;
        }
      }

      final selectedSiteUrl = currentInstance?.url;
      _forgetSiteState(instance.url);
      _instances.remove(instance);

      if (selectedSiteUrl == instance.url) {
        final previousIndex = previousSiteUrl == null
            ? -1
            : _instances.indexWhere((item) => item.url == previousSiteUrl);
        if (previousIndex >= 0) {
          _instanceIndex = previousIndex;
          _destinationId = previousDestinationId;
          _contentStack
            ..clear()
            ..addAll(previousContent);
          _mobilePane = previousPane;
          _syncTracking();
          _syncTopicChannels();
        } else {
          _instanceIndex = _instances.isEmpty ? 0 : _instances.length - 1;
          _resetToInstanceDefault();
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

  /// Signs [instance] out and takes it out of the rail.
  ///
  /// Returns false when the local rail could not be persisted. The key is
  /// still forgotten, and the site is restored as signed out so memory and the
  /// repaired on-disk snapshot agree and the removal remains retryable.
  Future<bool> removeInstance(DiscourseInstance instance) async {
    if (!_instances.contains(instance)) return false;

    final lease = await _revokeAndForget(instance);
    if (!lease.isCurrent) return false;

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

    if (removingSelected) {
      // The site being read is the one going away, so there is somewhere new
      // to land: whatever took its place, or the end of a shortened rail.
      _instanceIndex = _instances.isEmpty
          ? 0
          : index.clamp(0, _instances.length - 1);
      _resetToInstanceDefault();
    } else {
      // Removing a site the user is not looking at must not cost them their
      // place, so follow the selected one to wherever the removal left it
      // rather than resetting to its default destination.
      _instanceIndex = _instances.indexOf(selected!);
    }
    _notify();

    try {
      await instanceStore.save(List.of(_instances));
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

  /// Refreshes counters for every connected site, in parallel.
  Future<void> _refreshTotals() async {
    await accountActivity.refreshAll(_instances);
  }

  Future<void> _refreshOne(DiscourseInstance instance) async {
    await accountActivity.refresh(instance);
  }

  Future<void> _refreshSessionUsers() async {
    await Future.wait([
      for (final instance in List<DiscourseInstance>.of(_instances))
        if (instance.isConnected) _refreshSessionUserFor(instance),
    ]);
  }

  Future<void> _refreshSessionUserFor(DiscourseInstance instance) async {
    try {
      final apiKey = await authenticator.apiKeyFor(instance.url);
      if (apiKey != null) await _sessionUser(instance.url, apiKey);
    } catch (_) {
      // Capabilities remain unknown. Persisted values never authorize a poll
      // creation or a group-restricted vote in their place.
    }
  }

  void _onTotalsLoaded(DiscourseInstance instance, NotificationTotals totals) {
    // A post arrives whether or not you care about reactions, so its payload
    // can be the gate. A channel list arrives only if you ask, so its absence
    // proves nothing.
    if (totals.hasChatEnabled) {
      unawaited(_presentation.ensureConfig(instance.url));
      unawaited(_presentation.ensureCustomEmojis(instance.url));
      unawaited(chat.loadChannels(instance.url));
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

  final Map<String, TopicFeed> _feeds = {};
  final Map<String, String> _filterQueries = {};

  /// Identity of the newest whole-list request for each feed.
  ///
  /// A site lease separates account sessions, but two refreshes in the same
  /// session share that lease. This token gives those requests an ordering:
  /// only the newest one may replace the feed or write its topics to the
  /// identity store.
  final Map<String, Object> _feedRevisions = {};

  /// Sites whose category list has been fetched. The categories themselves are
  /// in the store; this only remembers not to ask again.
  final Set<String> _categorised = {};
  final Map<String, List<TopicCategory>> _categoriesBySite = {};
  final Map<String, TopicComposerCapabilities> _topicComposerCapabilities = {};

  static String _feedKey(String siteUrl, String destinationId) =>
      '$siteUrl|$destinationId';

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
    return _destinationId;
  }

  TopicFeed? get currentFeed {
    final instance = currentInstance;
    final feedId = currentFeedId;
    if (instance == null || feedId == null) return null;
    return _feeds[_feedKey(instance.url, feedId)];
  }

  bool get canCreateTopicHere =>
      currentContent?.isTopic == false &&
      currentFeedId != 'messages' &&
      (currentFeed?.canCreateTopic ?? false);

  List<TopicCategory> topicComposerCategories(String siteUrl) =>
      _categoriesBySite[siteUrl] ?? const [];

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
    for (final route in _contentStack.reversed) {
      if (route.id == feedId && route.feedPath != null) return route.feedPath;
    }

    final username = instance.user?.username;
    return switch (feedId) {
      'latest' => '/latest.json',
      'filter' => Uri(
        path: '/filter.json',
        queryParameters: switch (_filterQueries[instance.url]) {
          final query? when query.isNotEmpty => {'q': query},
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

    final path = _feedPath(destinationId, instance);
    if (path == null) return;

    final key = _feedKey(instance.url, destinationId);
    final existing = _feeds[key];
    if (existing != null && !force && (existing.loading || existing.loaded)) {
      return;
    }
    final lease = lifecycle.capture(instance.url);
    final revision = Object();
    _feedRevisions[key] = revision;

    // A whole-list response supersedes every page based on the old snapshot.
    // Removing its ownership token also lets the refreshed list page without
    // waiting for an obsolete request to finish.
    _feedPageRequests.remove(key);

    // The list is about to be replaced wholesale, so the old position means
    // nothing — a refresh should leave the user at the top.
    _feedRows.remove(key);
    // And whatever was announced as incoming is about to arrive in the response
    // rather than needing a banner to fetch it. Cleared before the request, not
    // after, so a topic created while it is in flight still counts — and put
    // back if the request fails, since the announcement is still owed then.
    final tracker = _trackers[instance.url];
    final announced = tracker?.incoming.topicIds(destinationId) ?? const [];
    tracker?.incoming.reset(destinationId);
    _feeds[key] = TopicFeed(
      loading: true,
      filterOptions: existing?.filterOptions ?? const [],
    );
    _notify();

    try {
      final apiKey = await authenticator.apiKeyFor(instance.url);
      final list = await api.topicList(
        siteUrl: instance.url,
        path: path,
        apiKey: apiKey,
      );
      lease.commit(() {
        if (!identical(_feedRevisions[key], revision)) return;
        store.putAll(instance.url, list.topics);
        _feeds[key] = TopicFeed.of(list);
        _notify();
        unawaited(_ensureCategories(instance, apiKey));
      });
    } on SiteLookupException catch (e, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_feedRevisions[key], revision)) {
        return;
      }
      _reportOperationalError(e, stackTrace, 'topics.loadFeed');
      lease.commit(() {
        if (!identical(_feedRevisions[key], revision)) return;
        tracker?.incoming.restore(destinationId, announced);
        _feeds[key] = TopicFeed(
          error: e.failure == SiteLookupFailure.notDiscourse
              ? 'Not allowed — try reconnecting to ${instance.host}.'
              : "Couldn't reach ${instance.host}.",
          loaded: true,
          filterOptions: existing?.filterOptions ?? const [],
        );
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_feedRevisions[key], revision)) {
        return;
      }
      _reportOperationalError(error, stackTrace, 'topics.loadFeed');
      lease.commit(() {
        if (!identical(_feedRevisions[key], revision)) return;
        tracker?.incoming.restore(destinationId, announced);
        _feeds[key] = TopicFeed(
          error: "Couldn't load ${instance.host}.",
          loaded: true,
          filterOptions: existing?.filterOptions ?? const [],
        );
        _notify();
      });
    }
  }

  final Map<String, int> _feedRows = {};

  String filterQueryFor(String siteUrl) => _filterQueries[siteUrl] ?? '';

  /// Submits the text on the Filter destination. Editing the field alone does
  /// not call this; core only refreshes its list on Enter or clear.
  Future<void> submitTopicFilter(String query) async {
    final instance = currentInstance;
    if (instance == null || _destinationId != 'filter') return;
    _filterQueries[instance.url] = query;
    _feedRows.remove(_feedKey(instance.url, 'filter'));
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
      final found = await lookup(
        await authenticator.apiKeyFor(siteUrl),
        await authenticator.clientId(),
      );
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
    return _feedRows[_feedKey(instance.url, destinationId)] ?? 0;
  }

  /// Records the list position. Deliberately silent: nothing on screen depends
  /// on it, and it is written as the list scrolls.
  void saveFeedScrollRow(String destinationId, int row) {
    final instance = currentInstance;
    if (instance == null) return;
    _feedRows[_feedKey(instance.url, destinationId)] = row;
  }

  final Map<String, SiteTracker> _trackers = {};
  final Set<String> _trackersStarting = {};

  /// Sites whose account was read from `/session/current.json` during this
  /// process. Persisted capabilities are intentionally never put in this set.
  final Set<String> _sessionUsersRefreshed = {};

  /// Deduplicates the selected site's tracker startup with the all-sites
  /// session refresh kicked off during load.
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

    final key = _feedKey(instance.url, destinationId);
    final feed = _feeds[key];
    final tracker = _trackers[instance.url];
    final path = _feedPath(destinationId, instance);
    if (feed == null || tracker == null || path == null) return;
    if (feed.loadingIncoming) return;

    final ids = tracker.incoming.topicIds(destinationId);
    if (ids.isEmpty) return;
    final lease = lifecycle.capture(instance.url);
    final feedRevision = _feedRevisions[key];

    bool requestIsCurrent() => identical(_feedRevisions[key], feedRevision);

    _feeds[key] = feed.copyWith(loadingIncoming: true);
    _notify();

    try {
      final apiKey = await authenticator.apiKeyFor(instance.url);
      final list = await api.topicList(
        siteUrl: instance.url,
        path: '$path?topic_ids=${ids.join(',')}',
        apiKey: apiKey,
      );

      lease.commit(() {
        if (!requestIsCurrent()) return;
        store.putAll(instance.url, list.topics);
        final held = _feeds[key] ?? feed;
        final arrived = [for (final topic in list.topics) topic.id];
        final prepended = arrived.toSet();
        _feeds[key] = held.copyWith(
          topicIds: [
            ...arrived,
            ...held.topicIds.where((id) => !prepended.contains(id)),
          ],
          loadingIncoming: false,
        );
        tracker.incoming.clear(destinationId, ids);
        _feedRows[key] = 0;
        _notify();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent || !requestIsCurrent()) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topics.loadIncoming',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        if (!requestIsCurrent()) return;
        _feeds[key] = (_feeds[key] ?? feed).copyWith(loadingIncoming: false);
        _notify();
      });
    }
  }

  /// Points the one live connection at the site on screen.
  ///
  /// Trackers are kept for every site the user has visited but only the current
  /// one polls, so there is a single long poll open at any moment — the same as
  /// the web, which only ever has one site. Their cursors survive being
  /// stopped, so coming back to a site asks for what it published while it was
  /// off screen instead of starting over.
  void _syncTracking() {
    final instance = currentInstance;
    final callSiteUrl = resenha.activeSiteUrl;

    for (final entry in _trackers.entries) {
      if (entry.key != instance?.url && entry.key != callSiteUrl) {
        entry.value.stop();
      }
    }
    if (callSiteUrl != null && callSiteUrl != instance?.url) {
      _trackers[callSiteUrl]?.start();
    }
    if (instance == null) return;

    final tracker = _trackers[instance.url];
    if (tracker == null) {
      unawaited(_startTracking(instance));
      return;
    }
    tracker.start();
    _syncTopicWatch(instance.url, tracker);
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

    final channels = [
      for (final plugin in sitePlugins) ...plugin.topicChannels(topicId),
    ];
    if (channels.isEmpty) {
      tracker.unwatchTopic();
      return;
    }

    tracker.watchTopic(topicId, channels, (channel, data) {
      final stale = <int>{
        for (final plugin in sitePlugins) ...plugin.stalePosts(channel, data),
      };
      unawaited(_refreshPosts(siteUrl, topicId, stale));
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
    for (final id in eligible) {
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
      final posts = await api.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: wanted,
        apiKey: await authenticator.apiKeyFor(siteUrl),
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
          onIncomingTopics: () => commit(_notify),
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
      resenha.attachTracker(siteUrl);
      if (currentInstance?.url != siteUrl && resenha.activeSiteUrl != siteUrl) {
        tracker.stop();
      } else {
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
    final user = await _sessionUser(siteUrl, apiKey);
    if (!lease.isCurrent) return null;
    // A stored id is stable enough to keep this account's private counters
    // connected after a failed refresh, but its capabilities remain unknown.
    return user?.id ?? _instanceAt(siteUrl)?.user?.id;
  }

  Future<DiscourseUser?> _sessionUser(String siteUrl, String apiKey) {
    final held = _instanceAt(siteUrl);
    if (held == null) return Future.value();
    if (_sessionUsersRefreshed.contains(siteUrl)) {
      return Future.value(held.user);
    }

    final active = _sessionUserRequests[siteUrl];
    if (active != null) return active;

    final lease = lifecycle.capture(siteUrl);
    late final Future<DiscourseUser?> request;
    request = _readSessionUser(siteUrl, apiKey, lease).whenComplete(() {
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

  void _disposeTracking(String siteUrl) {
    final tracker = _trackers.remove(siteUrl);
    tracker?.dispose().ignore();
  }

  /// Tells the shell whether it is the app in front.
  ///
  /// A backgrounded app must not hold a long poll open — the connection is
  /// usually dead by the time it comes back and the OS has been waiting on it
  /// the whole while — so polling drops to the message_bus client's background
  /// pacing and a returning app reconnects at once rather than waiting out a
  /// backoff.
  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    resenha.setForeground(foreground);
    if (!foreground) return;

    final instance = currentInstance;
    if (instance != null) _trackers[instance.url]?.pollNow();
    final callSite = resenha.activeSiteUrl;
    if (callSite != null && callSite != instance?.url) {
      _trackers[callSite]?.pollNow();
    }
  }

  final Set<String> _topicsLoading = {};
  final Set<String> _postsLoading = {};
  final Set<String> _earlierPostsLoading = {};
  final Map<String, int> _topicReadPositions = {};
  final Map<String, _TopicReadReceipt> _queuedTopicReadReceipts = {};
  final Map<String, Future<void>> _topicReadReceiptTasks = {};
  final Map<String, Object> _topicReadReceiptRuns = {};

  static String _topicKey(String siteUrl, int topicId) => '$siteUrl#$topicId';

  /// The topic filling the main region, once it has arrived.
  TopicDetail? get currentTopic {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;
    return store.read<TopicDetail>(instance.url, topicId);
  }

  /// The contiguous ids of the posts on screen, in reading order.
  ///
  /// The topic knows every post id it has; the store knows which of them have
  /// actually been fetched. An ordinary load draws the fetched prefix, while
  /// a numbered load draws the fetched window around its target.
  List<int> get currentPostIds {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return const [];
    final range = _loadedPostRange(instance.url, detail);
    if (range == null) return const [];
    return [for (final id in detail.stream.sublist(range.$1, range.$2 + 1)) id];
  }

  /// The loaded window to draw.
  ///
  /// Ordinary topic loads are a prefix. Numbered loads are a middle window;
  /// when older posts from a previous visit are also cached, drawing every
  /// loaded id would collapse the unfetched gap between them. Instead, grow
  /// outward only while adjacent posts are present around the requested one.
  (int, int)? _loadedPostRange(String siteUrl, TopicDetail detail) {
    if (detail.stream.isEmpty) return null;

    final target = currentContent?.postNumber;
    var anchor = -1;
    if (target != null) {
      for (var i = 0; i < detail.stream.length; i++) {
        final post = store.read<Post>(siteUrl, detail.stream[i]);
        if (post != null && post.postNumber >= target) {
          anchor = i;
          break;
        }
      }
    } else {
      anchor = detail.stream.indexWhere(
        (id) => store.read<Post>(siteUrl, id) != null,
      );
    }
    // A stale cache or a deliberately minimal test payload may not contain
    // the requested post yet. Keep showing the contiguous data in hand until
    // the around-post request lands instead of flashing an empty topic.
    if (anchor < 0 && target != null) {
      anchor = detail.stream.indexWhere(
        (id) => store.read<Post>(siteUrl, id) != null,
      );
    }
    if (anchor < 0) return null;

    var first = anchor;
    while (first > 0 &&
        store.read<Post>(siteUrl, detail.stream[first - 1]) != null) {
      first--;
    }
    var last = anchor;
    while (last + 1 < detail.stream.length &&
        store.read<Post>(siteUrl, detail.stream[last + 1]) != null) {
      last++;
    }
    return (first, last);
  }

  /// Post ids after the loaded window, oldest first.
  List<int> _pendingPostIds(String siteUrl, TopicDetail detail) {
    final range = _loadedPostRange(siteUrl, detail);
    final start = range == null ? 0 : range.$2 + 1;
    return [
      for (final id in detail.stream.skip(start))
        if (store.read<Post>(siteUrl, id) == null) id,
    ];
  }

  /// Post ids immediately before the loaded window, newest batch first.
  List<int> _pendingEarlierPostIds(
    String siteUrl,
    TopicDetail detail,
    int batchSize,
  ) {
    final range = _loadedPostRange(siteUrl, detail);
    if (range == null || range.$1 == 0) return const [];
    final start = range.$1 > batchSize ? range.$1 - batchSize : 0;
    return [
      for (final id in detail.stream.sublist(start, range.$1))
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

  void openSearchResult(SearchPostHit hit) {
    search.clear();
    _openTopic(
      hit.topicId,
      hit.topicSlug,
      hit.topicTitle,
      postNumber: hit.postNumber,
    );
  }

  void _openTopic(int topicId, String slug, String title, {int? postNumber}) {
    // A fast double tap on a row pushes the same topic twice — the fetch is
    // deduped below, but the second route still costs a back tap.
    if (currentContent?.topicId == topicId) return;
    pushContent(
      ContentRoute.topic(
        topicId: topicId,
        slug: slug,
        title: title,
        postNumber: postNumber,
      ),
    );
    unawaited(loadTopic(topicId, slug, postNumber: postNumber));
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
  bool openTopicUrl(String url) {
    final link = TopicLink.parse(absoluteUrl(url));
    if (link == null) return false;

    final index = _instances.indexWhere((i) => i.serves(link.uri));
    if (index < 0) return false;

    if (index != _instanceIndex) selectInstance(index);

    // Posts link to the topic they are already in — every cross-post quote
    // does — and stacking a second copy of it only costs the user a back tap.
    if (currentContent?.topicId == link.topicId) return true;

    _openTopic(
      link.topicId,
      link.slug,
      link.placeholderTitle,
      postNumber: link.postNumber,
    );
    return true;
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

  /// Opens a Resenha room link on a connected, signed-in site.
  Future<bool> openResenhaUrl(String url) async {
    if (!resenha.supportedPlatform) return false;
    final uri = Uri.tryParse(absoluteUrl(url));
    if (uri == null) return false;
    final match = RegExp(r'^/resenha/r/([^/]+)/?$').firstMatch(uri.path);
    if (match == null) return false;
    final index = _instances.indexWhere((instance) => instance.serves(uri));
    if (index < 0 || !_instances[index].isConnected) return false;
    if (index != _instanceIndex) selectInstance(index);
    final instance = _instances[index];
    await resenha.ensureLoaded(instance.url);
    final room = await resenha.resolveRoom(
      instance.url,
      Uri.decodeComponent(match.group(1)!),
    );
    if (room == null) return false;
    pushContent(
      ContentRoute(
        id: 'resenha-room-${room.id}',
        title: room.name,
        icon: DIcons.microphoneLines,
      ),
    );
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
    if (_topicsLoading.contains(key)) return;
    final held = store.read<TopicDetail>(instance.url, topicId);
    if (held != null && !force) {
      final targetHeld = postNumber == null
          ? true
          : held.stream.any((id) {
              final post = store.read<Post>(instance.url, id);
              return post?.postNumber == postNumber;
            });
      if (targetHeld) return;
    }
    final lease = lifecycle.capture(instance.url);

    _topicsLoading.add(key);
    _notify();

    try {
      final apiKey = await authenticator.apiKeyFor(instance.url);
      final fetched = await api.topic(
        siteUrl: instance.url,
        slug: slug,
        id: topicId,
        postNumber: postNumber,
        apiKey: apiKey,
      );
      lease.commit(() {
        _absorb(instance.url, fetched);
        if (currentInstance?.url == instance.url) {
          _retitle(topicId, fetched.detail.title);
        }
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(error, stackTrace, 'topic.load', degraded: false);
      // Left absent; the view shows its own failure state.
    } finally {
      lease.commit(() {
        _topicsLoading.remove(key);
        _notify();
      });
    }
  }

  /// Corrects the header of a topic opened from a link, which could only guess
  /// at the title from the slug in the URL.
  void _retitle(int topicId, String title) {
    if (title.isEmpty) return;

    for (var i = 0; i < _contentStack.length; i++) {
      final route = _contentStack[i];
      if (route.topicId != topicId || route.title == title) continue;
      _contentStack[i] = ContentRoute.topic(
        topicId: topicId,
        slug: route.slug ?? '',
        title: title,
        subtitle: route.subtitle,
        color: route.color,
        postNumber: route.postNumber,
      );
    }
  }

  void _updateTopicRouteMetadata(
    String siteUrl,
    int topicId,
    String title,
    int? categoryId,
  ) {
    final category = categoryFor(categoryId, siteUrl: siteUrl);
    for (var i = 0; i < _contentStack.length; i++) {
      final route = _contentStack[i];
      if (route.topicId != topicId) continue;
      _contentStack[i] = ContentRoute.topic(
        topicId: topicId,
        slug: route.slug ?? '',
        title: title,
        subtitle: route.subtitle,
        color: category == null ? null : Color(category.colorValue),
      );
    }
  }

  /// Files a topic payload: the posts under their own ids, the topic under
  /// its own, and the list row's durable details corrected to match.
  ///
  /// Fetching is deliberately not treated as reading. Discourse advances a
  /// topic's reading position from `/topics/timings`; [markTopicRead] sends
  /// that only after the viewport has actually shown a post.
  TopicDetail _absorb(String siteUrl, TopicPayload payload) {
    store.putAll(siteUrl, payload.posts);
    final detail = store.put(siteUrl, payload.detail);
    store.update<Topic>(
      siteUrl,
      detail.id,
      (row) => row.copyWith(title: detail.title, postsCount: detail.postsCount),
    );
    return detail;
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
    if (isDisposed || postNumber <= 0) return Future.value();

    final key = _topicKey(siteUrl, topicId);
    final held = store.read<Topic>(siteUrl, topicId);
    final local = _topicReadPositions[key] ?? 0;
    final server = held?.lastReadPostNumber ?? 0;
    final recorded = local > server ? local : server;
    if (recorded >= postNumber) return Future.value();

    final lease = lifecycle.capture(siteUrl);
    _topicReadPositions[key] = postNumber;
    store.update<Topic>(
      siteUrl,
      topicId,
      (row) => row.copyWith(
        lastReadPostNumber: postNumber,
        // A live list update may already know about a newer post than the
        // detail stream on screen. Reaching that stream's end must not clear
        // unread state for the newer post the reader has not received yet.
        markRead:
            caughtUp &&
            (row.highestPostNumber <= 0 || postNumber >= row.highestPostNumber),
      ),
    );

    _queuedTopicReadReceipts[key] = (
      siteUrl: siteUrl,
      topicId: topicId,
      postNumber: postNumber,
      lease: lease,
    );
    final running = _topicReadReceiptTasks[key];
    if (running != null) return running;

    final run = Object();
    _topicReadReceiptRuns[key] = run;
    final task = _drainTopicReadReceipts(key, run);
    _topicReadReceiptTasks[key] = task;
    return task;
  }

  /// Sends one receipt at a time and collapses any waiting positions to the
  /// newest one. Read positions only move forwards, so intermediate writes
  /// carry no information once a later viewport observation exists.
  Future<void> _drainTopicReadReceipts(String key, Object run) async {
    while (true) {
      if (!identical(_topicReadReceiptRuns[key], run)) return;
      final receipt = _queuedTopicReadReceipts.remove(key);
      if (receipt == null) {
        if (identical(_topicReadReceiptRuns[key], run)) {
          _topicReadReceiptRuns.remove(key);
          final _ = _topicReadReceiptTasks.remove(key);
        }
        return;
      }

      try {
        final apiKey = await authenticator.apiKeyFor(receipt.siteUrl);
        if (isDisposed || !receipt.lease.isCurrent || apiKey == null) continue;
        final clientId = await authenticator.clientId();
        if (isDisposed || !receipt.lease.isCurrent) continue;
        await api.recordTopicRead(
          siteUrl: receipt.siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          topicId: receipt.topicId,
          postNumber: receipt.postNumber,
        );
      } catch (error, stackTrace) {
        if (!isDisposed &&
            receipt.lease.isCurrent &&
            identical(_topicReadReceiptRuns[key], run)) {
          _reportOperationalError(
            error,
            stackTrace,
            'topic.markRead',
            severity: DiagnosticSeverity.warning,
          );
        }
        // A newer queued position must still be attempted after this failure.
      }
    }
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

    final pending = _pendingPostIds(instance.url, detail);
    if (pending.isEmpty) return;
    final lease = lifecycle.capture(instance.url);

    _postsLoading.add(key);
    _notify();

    try {
      final posts = await api.posts(
        siteUrl: instance.url,
        topicId: topicId,
        ids: pending.take(batchSize).toList(),
        apiKey: await authenticator.apiKeyFor(instance.url),
      );
      lease.commit(() => store.putAll(instance.url, posts));
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

    final pending = _pendingEarlierPostIds(instance.url, detail, batchSize);
    if (pending.isEmpty) return;
    final lease = lifecycle.capture(instance.url);

    _earlierPostsLoading.add(key);
    _notify();

    try {
      final posts = await api.posts(
        siteUrl: instance.url,
        topicId: topicId,
        ids: pending,
        apiKey: await authenticator.apiKeyFor(instance.url),
      );
      lease.commit(() => store.putAll(instance.url, posts));
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

  ComposerController? _composer;

  /// The open composer, but only when it belongs to what is on screen.
  ///
  /// Navigating away leaves it open and out of sight rather than throwing away
  /// what was written, and it stays bound to the site it was opened on.
  ComposerController? get visibleComposer {
    final composer = _composer;
    final instance = currentInstance;
    if (composer == null || instance == null) return null;
    if (composer.target.siteUrl != instance.url) return null;
    if (composer.target.isNewTopic) {
      return currentContent?.isTopic == false &&
              currentFeedId == composer.target.originFeedId
          ? composer
          : null;
    }
    return currentContent?.topicId == composer.target.topicId ? composer : null;
  }

  /// Whether a reply affordance should be offered for the topic on screen.
  bool get canReplyHere => currentTopic?.canCreatePost ?? false;

  /// Opens a new-topic composer while leaving the originating list in place.
  Future<void> openNewTopic() async {
    final instance = currentInstance;
    final route = currentContent;
    final feedId = currentFeedId;
    if (instance == null ||
        route == null ||
        feedId == null ||
        !canCreateTopicHere) {
      return;
    }

    final lease = lifecycle.capture(instance.url);
    final credential = await _credentialForWrite(instance.url);
    if (!lease.isCurrent || currentFeedId != feedId) return;
    if (credential.failure != null) return;
    final apiKey = credential.apiKey!;

    TopicComposerCapabilities capabilities;
    List<TopicCategory> categories;
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
    if (!lease.isCurrent || currentFeedId != feedId) return;

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
    if (!lease.isCurrent || currentFeedId != feedId) return;

    _categoriesBySite[instance.url] = List.unmodifiable(categories);
    _topicComposerCapabilities[instance.url] = capabilities;
    store.putAll(instance.url, categories);
    _replaceComposer();
    final target = ComposerTarget(
      siteUrl: instance.url,
      topicId: 0,
      slug: '',
      topicTitle: 'New topic',
      mode: ComposerMode.newTopic,
      originFeedId: feedId,
      initialCategoryId: categoryId,
      initialTags: tags,
    );
    final config = siteConfigFor(target.siteUrl);
    final composer = ComposerController(
      target,
      onSaveDraft: _saveDraft,
      search: _composerSearch(target),
      resolveEmoji: (name) => emojiUrlFor(target.siteUrl, name),
      pills: _composerPills(target),
      pollMaximumOptions: config.pollMaximumOptions,
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
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
      minimumRequiredTags:
          categories
              .where((category) => category.id == categoryId)
              .firstOrNull
              ?.minimumRequiredTags ??
          0,
    )..draftSequence = _draftSequence(target);
    _composer = composer;
    _notify();
    unawaited(_restoreDraft(composer));
  }

  Future<TopicTagSearch> searchComposerTags(
    ComposerController composer,
    String term,
  ) async {
    final target = composer.target;
    final credential = await _credentialForWrite(target.siteUrl);
    if (credential.failure != null) {
      throw credential.failure!;
    }
    return api.searchTopicTags(
      siteUrl: target.siteUrl,
      apiKey: credential.apiKey!,
      term: term,
      categoryId: composer.categoryId,
      selectedTagIds: composer.tags.map((tag) => tag.id).whereType<int>(),
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
        existing.target.siteUrl == instance.url) {
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
      topicId: topicId,
      slug: route?.slug ?? '',
      topicTitle: route?.title ?? '',
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
    );
    final config = siteConfigFor(target.siteUrl);
    final composer = ComposerController(
      target,
      onSaveDraft: _saveDraft,
      search: _composerSearch(target),
      resolveEmoji: (name) => emojiUrlFor(target.siteUrl, name),
      pills: _composerPills(target),
      pollMaximumOptions: config.pollMaximumOptions,
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
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
    )..draftSequence = _draftSequence(target);
    _composer = composer;
    _notify();

    unawaited(_restoreDraft(composer));
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
    final config = siteConfigFor(target.siteUrl);
    final composer = ComposerController(
      target,
      search: _composerSearch(target),
      resolveEmoji: (name) => emojiUrlFor(target.siteUrl, name),
      pills: _composerPills(target),
      pollMaximumOptions: config.pollMaximumOptions,
      imageUploader: (file, {required onProgress, required abortTrigger}) =>
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
    unawaited(ensureEmojis(target.siteUrl));

    return (
      users: (term) async {
        final found = await searchUsers(
          siteUrl: target.siteUrl,
          topicId: target.topicId,
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
      emojis: (query) => [
        for (final emoji in searchEmojis(target.siteUrl, query))
          ComposerSuggestion(
            kind: ComposerTriggerKind.emoji,
            value: emoji.name,
            label: emoji.name,
            art: ArtImage(emoji.url),
          ),
      ],
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
      final fetched = await api.posts(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        ids: [post.id],
        includeRaw: true,
        apiKey: await authenticator.apiKeyFor(target.siteUrl),
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
          store.put(siteUrl, fresh);
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

  /// Gives, moves or takes back this reader's reaction. null means it went
  /// through.
  ///
  /// The same bargain [toggleLike] makes and for the same reason — a reaction
  /// is a tap made while reading, and a row that waits for a round trip reads
  /// as broken rather than slow.
  ///
  /// Nothing here ever writes `/post_actions` on a post that has reactions.
  /// Reacting with a non-excluded emoji leaves a shadow like behind it, so an
  /// unliking `DELETE` would destroy that and orphan the reaction — a desync
  /// only a scheduled server job repairs.
  Future<String?> toggleReaction(
    Post post,
    String reaction, {
    String? siteUrl,
  }) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    if (targetSite == null || !post.canReact) return null;

    // Per post rather than per reaction, and shared with the like: two
    // reactions toggled at once on one post contradict each other server side,
    // because giving one *replaces* whatever was there. Serialising them is the
    // correct granularity, not a simplification.
    final key = _postKey(targetSite, post.id);
    if (!_beginPostWrite(key)) return null;
    final lease = lifecycle.capture(targetSite);

    try {
      return await _writeReaction(targetSite, post, reaction, lease);
    } finally {
      lease.commit(() => _endPostWrite(targetSite, post.id));
    }
  }

  bool postWriteInFlight(int postId, {String? siteUrl}) {
    final targetSite = siteUrl ?? currentInstance?.url;
    return targetSite != null &&
        _postWritesInFlight.contains(_postKey(targetSite, postId));
  }

  /// Casts or changes a vote in one named poll. The card owns the responsive
  /// pending selection; only the personalized server answer is committed to
  /// the post, so counts and confidential results are never guessed.
  Future<PollVoteWriteResult> castPollVote(
    Post post,
    Poll poll,
    List<String> optionIds, {
    String? siteUrl,
  }) => _writePollVote(
    post,
    poll,
    options: List.unmodifiable(optionIds),
    siteUrl: siteUrl,
  );

  Future<PollVoteWriteResult> removePollVote(
    Post post,
    Poll poll, {
    String? siteUrl,
  }) => _writePollVote(post, poll, options: null, siteUrl: siteUrl);

  Future<PollVoteWriteResult> _writePollVote(
    Post post,
    Poll poll, {
    required List<String>? options,
    String? siteUrl,
  }) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    final topicId = currentContent?.topicId;
    if (targetSite == null || topicId == null || !poll.isOpen) {
      return const PollVoteWriteResult.saved();
    }
    final detail = store.read<TopicDetail>(targetSite, topicId);
    if (detail?.archived == true) {
      return const PollVoteWriteResult.refused(
        'Voting is unavailable in archived topics.',
      );
    }

    final key = _postKey(targetSite, post.id);
    if (!_beginPostWrite(key)) {
      // Another card on this post won the same-frame race before the shell
      // could rebuild both as disabled. Tell this card to discard the local
      // selection it already painted, without presenting an error.
      return const PollVoteWriteResult.reconciled();
    }
    final lease = lifecycle.capture(targetSite);
    try {
      final credential = await _credentialForWrite(targetSite);
      if (!lease.isCurrent) return const PollVoteWriteResult.saved();
      if (credential.failure case final failure?) {
        return PollVoteWriteResult.refused(failure.message);
      }
      final apiKey = credential.apiKey!;

      final PollVoteResponse answer;
      try {
        answer = options == null
            ? await api.removePollVote(
                siteUrl: targetSite,
                apiKey: apiKey,
                postId: post.id,
                pollName: poll.name,
              )
            : await api.votePoll(
                siteUrl: targetSite,
                apiKey: apiKey,
                postId: post.id,
                pollName: poll.name,
                options: options,
              );
      } on WriteException catch (error) {
        if (error.failure != WriteFailure.unreachable) {
          return PollVoteWriteResult.refused(error.message);
        }
        // The vote route is idempotent for a concrete selection. If its answer
        // was lost, a personalized post read is the only safe reconciliation.
        await _refreshPost(targetSite, topicId, post.id, apiKey, lease);
        return const PollVoteWriteResult.reconciled();
      } catch (_) {
        await _refreshPost(targetSite, topicId, post.id, apiKey, lease);
        return const PollVoteWriteResult.reconciled();
      }

      lease.commit(() {
        store.update<Post>(targetSite, post.id, (held) {
          final polls = held.polls ?? const Polls();
          return held.withPlugins(
            held.plugins.withValue<Polls>(polls.withPoll(answer.poll)),
          );
        });
        _notify();
      });
      return const PollVoteWriteResult.saved();
    } finally {
      lease.commit(() => _endPostWrite(targetSite, post.id));
    }
  }

  Future<String?> _writeReaction(
    String siteUrl,
    Post post,
    String reaction,
    SiteLease lease,
  ) async {
    final credential = await _credentialForWrite(siteUrl);
    if (!lease.isCurrent) return null;
    if (credential.failure case final failure?) return failure.message;
    final apiKey = credential.apiKey!;

    final held = post.reactions;
    if (held == null) return null;

    // A transform of whatever is held now, not a put of the tapped copy: the
    // credential await above is a window an edit or a re-read can land in, and
    // putting the whole stale snapshot back would undo it — and unlike a
    // like, whose success path puts the site's full answer over the guess, a
    // reaction's answer is merged selectively and could never heal that.
    final applied = lease.commit(() {
      store.update<Post>(siteUrl, post.id, (current) {
        final reactions = current.reactions;
        if (reactions == null) return current;
        return current.withPlugins(
          current.plugins.withValue<Reactions>(
            reactions
                .withToggled(reaction)
                .withMainReaction(siteConfigFor(siteUrl).mainReaction),
          ),
        );
      });
      _notify();
    });
    if (!applied) return null;

    /// Puts the reactions back the way they were, and nothing else — the twin
    /// of `_writeLike`'s revert, for the same reason.
    void revert() {
      lease.commit(() {
        store.update<Post>(
          siteUrl,
          post.id,
          (h) => h.withPlugins(h.plugins.withValue<Reactions>(held)),
        );
        _notify();
      });
    }

    try {
      final fresh = await api.toggleReaction(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: post.id,
        reaction: reaction,
      );
      // Only what the answer says about *this reader*, never its counts. The
      // plugin builds `reactions` one way for a topic read and another for a
      // write, and the second drops reactions whose emoji no longer exists — so
      // taking its counts would bump a pill and leave it wrong until the topic
      // was read again. The guess above is corrected by the next real read, the
      // way a like's count is when the route answers with nothing.
      if (fresh?.reactions case final answered?) {
        lease.commit(() {
          store.update<Post>(
            siteUrl,
            post.id,
            (h) => h.withPlugins(
              h.plugins.withValue<Reactions>(h.reactions?.withMineOf(answered)),
            ),
          );
          _notify();
        });
      }
    } on WriteException catch (e) {
      if (e.statusCode == 404) {
        // Either the plugin went away or the post did — the route answers the
        // same bytes for both, and the next read of the topic settles which.
        // Deliberately scoped to this one post: dropping the site's reactions
        // because a moderator deleted a post while it was being read would
        // empty every footer in the topic.
        lease.commit(() {
          store.update<Post>(
            siteUrl,
            post.id,
            (h) => h.withPlugins(h.plugins.withValue<Reactions>(null)),
          );
          _notify();
        });
        // The row disappearing is the honest report; there is nothing a reader
        // could do about either cause.
        return null;
      }
      revert();
      return e.message;
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _reportOperationalError(error, stackTrace, 'post.toggleReaction');
      }
      revert();
      return const WriteException(WriteFailure.unreachable).message;
    }
    return null;
  }

  /// One write at a time per post, whichever kind it is. Keyed by site and post
  /// because topic 7's post 3 on two sites are two different posts.
  final Set<String> _postWritesInFlight = {};

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
      final fetched = await api.postLikers(
        siteUrl: targetSite,
        postId: postId,
        // Read inside the guard, not before it: storage that refuses —
        // an unsigned macOS build answers `errSecMissingEntitlement` —
        // would otherwise leave the key in [_likersLoading] for the rest of
        // the session, and every later hover would find a fetch in flight
        // that is not.
        apiKey: await authenticator.apiKeyFor(targetSite),
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
    if (existing == null) return;
    if (existing.draftPending) {
      unawaited(existing.flushDraft());
    }
    existing.dispose();
    _composer = null;
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
    );
  }

  Future<Map<String, String>> _resolveComposerUploadUrls(
    ComposerTarget target,
    Iterable<String> urls,
  ) async {
    final credential = await _credentialForWrite(target.siteUrl);
    if (credential.failure case final failure?) {
      throw ComposerUploadException(failure.message);
    }
    return api.lookupUploadUrls(
      siteUrl: target.siteUrl,
      apiKey: credential.apiKey!,
      clientId: await authenticator.clientId(),
      shortUrls: urls,
    );
  }

  /// Puts an unfinished reply back in the composer.
  Future<void> _restoreDraft(ComposerController composer) async {
    final target = composer.target;
    final lease = lifecycle.capture(target.siteUrl);

    // The local copy exists only while the site does not have the text, so if
    // there is one it is the newer of the two by construction — no timestamps
    // to compare, and no chance of restoring over something newer.
    final local = ComposerDraft.decode(
      await drafts.read(target.siteUrl, target.draftKey),
    );
    ComposerDraft? remote;
    var remoteSequence = 0;
    if (local == null && target.isNewTopic) {
      try {
        final credential = await _credentialForWrite(target.siteUrl);
        if (credential.failure == null) {
          final found = await api.draft(
            siteUrl: target.siteUrl,
            apiKey: credential.apiKey!,
            draftKey: target.draftKey,
          );
          remote = found.draft;
          remoteSequence = found.sequence;
        }
      } catch (_) {
        // A draft restore is best effort; opening the composer must still work.
      }
    }
    lease.commit(() {
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
                  .withPlugins(
                    PluginData.afterPostEdit(
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
  Future<void> _refetchTopic(String siteUrl, int topicId, String slug) async {
    final key = _topicKey(siteUrl, topicId);
    if (_topicsLoading.contains(key)) return;
    final lease = lifecycle.capture(siteUrl);
    _topicsLoading.add(key);

    try {
      final topic = await api.topic(
        siteUrl: siteUrl,
        slug: slug,
        id: topicId,
        apiKey: await authenticator.apiKeyFor(siteUrl),
      );
      lease.commit(() => _absorb(siteUrl, topic));
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topic.refetchAfterWrite',
        severity: DiagnosticSeverity.warning,
      );
      // The post is already on screen; the stream is repaired next time.
    } finally {
      lease.commit(() {
        _topicsLoading.remove(key);
        _notify();
      });
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
      final card = await api.userCard(
        siteUrl: targetSite,
        username: username,
        // Read inside the guard, the way `loadLikers` does: storage that
        // throws would otherwise strand the key in [_userCardsLoading].
        apiKey: await authenticator.apiKeyFor(targetSite),
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

  /// The request that owns each feed's pagination state.
  ///
  /// Identity matters here: a refresh can invalidate an old page and a new
  /// page can start before that request unwinds. The old request's `finally`
  /// must not clear the new request's loading state.
  final Map<String, Object> _feedPageRequests = {};

  /// Appends the next page, if there is one and nothing is already in flight.
  Future<void> loadMoreFeed(String destinationId) async {
    final instance = currentInstance;
    if (instance == null) return;

    final key = _feedKey(instance.url, destinationId);
    final feed = _feeds[key];
    if (feed == null || feed.loadingMore || !feed.hasMore) return;
    if (_feedPageRequests.containsKey(key)) return;
    final lease = lifecycle.capture(instance.url);
    final feedRevision = _feedRevisions[key];
    final pageRequest = Object();
    _feedPageRequests[key] = pageRequest;

    bool requestIsCurrent() =>
        identical(_feedRevisions[key], feedRevision) &&
        identical(_feedPageRequests[key], pageRequest);

    _feeds[key] = feed.copyWith(loadingMore: true);
    _notify();

    try {
      final next = await api.topicList(
        siteUrl: instance.url,
        path: feed.nextPagePath!,
        apiKey: await authenticator.apiKeyFor(instance.url),
      );

      lease.commit(() {
        if (!requestIsCurrent()) return;
        store.putAll(instance.url, next.topics);
        final held = _feeds[key];
        if (held == null) return;
        final seen = held.topicIds.toSet();
        final fresh = [
          for (final topic in next.topics)
            if (!seen.contains(topic.id)) topic.id,
        ];

        _feeds[key] = held.copyWith(
          topicIds: [...held.topicIds, ...fresh],
          loadingMore: false,
          nextPagePath: next.nextPagePath,
          clearNextPage: next.nextPagePath == null || fresh.isEmpty,
        );
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent || !requestIsCurrent()) return;
      _reportOperationalError(
        error,
        stackTrace,
        'topics.loadMore',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        if (!requestIsCurrent()) return;
        final held = _feeds[key];
        if (held != null) _feeds[key] = held.copyWith(loadingMore: false);
      });
    } finally {
      lease.commit(() {
        if (!identical(_feedPageRequests[key], pageRequest)) return;
        _feedPageRequests.remove(key);
        _notify();
      });
    }
  }

  Future<void> ensureEmojis(String siteUrl) =>
      _presentation.ensureEmojis(siteUrl);

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
  final Map<String, Map<String, FoundHashtag?>> _hashtags = {};
  final Map<String, Set<String>> _hashtagsInFlight = {};

  /// The same, for usernames: true is somebody, false is nobody.
  final Map<String, Map<String, bool>> _mentioned = {};
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
      found = await api.searchHashtags(
        siteUrl: siteUrl,
        term: term,
        order: [
          ...DiscourseApi.hashtagOrder,
          if (resenha.directory(siteUrl) != null) 'room',
        ],
        apiKey: await authenticator.apiKeyFor(siteUrl),
        clientId: await authenticator.clientId(),
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
      final known = _hashtags.putIfAbsent(siteUrl, () => {});
      for (final hashtag in found) {
        known[hashtag.ref] = hashtag;
      }
    });
    return accepted ? found : const [];
  }

  /// What the composer needs before it may draw a pill over what is typed.
  ComposerPills _composerPills(ComposerTarget target) {
    final siteUrl = target.siteUrl;
    return (
      hashtag: (ref) => _hashtags[siteUrl]?[ref],
      mention: (username) => _mentioned[siteUrl]?[username],
      resolve: (refs, usernames) {
        unawaited(_resolveHashtags(siteUrl, refs));
        unawaited(_resolveMentions(siteUrl, target.topicId, usernames));
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
    final known = _hashtags.putIfAbsent(siteUrl, () => {});
    final inFlight = _hashtagsInFlight.putIfAbsent(siteUrl, () => {});

    final ask = [
      for (final ref in refs)
        if (!known.containsKey(ref) && inFlight.add(ref)) ref,
    ];
    if (ask.isEmpty) return;

    final lease = lifecycle.capture(siteUrl);
    try {
      final found = await api.lookupHashtags(
        siteUrl: siteUrl,
        refs: ask,
        apiKey: await authenticator.apiKeyFor(siteUrl),
        clientId: await authenticator.clientId(),
      );
      if (isDisposed) return;
      lease.commit(() {
        for (final ref in ask) {
          known[ref] = null;
        }
        for (final hashtag in found) {
          known[hashtag.ref] = hashtag;
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
    int topicId,
    Set<String> usernames,
  ) async {
    final known = _mentioned.putIfAbsent(siteUrl, () => {});
    final inFlight = _mentionsInFlight.putIfAbsent(siteUrl, () => {});

    final ask = [
      for (final name in usernames)
        if (!known.containsKey(name) && inFlight.add(name)) name,
    ];
    if (ask.isEmpty) return;

    final lease = lifecycle.capture(siteUrl);
    try {
      final real = await api.checkMentions(
        siteUrl: siteUrl,
        names: ask,
        topicId: topicId,
        apiKey: await authenticator.apiKeyFor(siteUrl),
        clientId: await authenticator.clientId(),
      );
      if (isDisposed) return;
      lease.commit(() {
        for (final name in ask) {
          known[name] = real.contains(name);
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
    required int topicId,
    required String term,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final List<FoundUser> found;
    try {
      found = await api.searchUsers(
        siteUrl: siteUrl,
        term: term,
        topicId: topicId,
        apiKey: await authenticator.apiKeyFor(siteUrl),
        clientId: await authenticator.clientId(),
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
      final known = _mentioned.putIfAbsent(siteUrl, () => {});
      for (final user in found) {
        known[user.username] = true;
      }
    });
    return accepted ? found : const [];
  }

  String emojiUrlFor(String siteUrl, String name) =>
      _presentation.emojiUrlFor(siteUrl, name);

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

  Future<void> _persistSiteConfig(String siteUrl, SiteConfig config) async {
    if (currentInstance?.url == siteUrl) {
      search.selectSite(siteUrl, minimumLength: config.minSearchTermLength);
    }
    final held = _instanceAt(siteUrl);
    if (held == null || held.config == config) return;
    _replaceInstance(held, held.copyWith(config: config));
    await instanceStore.save(List.of(_instances));
  }

  /// Categories are fetched once per site; the topic rows need them to draw
  /// their badges, and they change rarely.
  Future<void> _ensureCategoriesFor(DiscourseInstance instance) async {
    final lease = lifecycle.capture(instance.url);
    try {
      final apiKey = await authenticator.apiKeyFor(instance.url);
      if (!lease.isCurrent) return;
      await _ensureCategories(instance, apiKey, lease: lease);
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _reportOperationalError(
        error,
        stackTrace,
        'categories.readCredentials',
        severity: DiagnosticSeverity.warning,
      );
      // Categories are optional decoration and can retry on the next read.
    }
  }

  Future<void> _ensureCategories(
    DiscourseInstance instance,
    String? apiKey, {
    SiteLease? lease,
  }) async {
    if (!_categorised.add(instance.url)) return;
    final session = lease ?? lifecycle.capture(instance.url);

    try {
      final categories = await api.categories(
        siteUrl: instance.url,
        apiKey: apiKey,
      );
      session.commit(() {
        store.putAll(instance.url, categories);
        _categoriesBySite[instance.url] = List.unmodifiable(categories);
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
      session.commit(() => _categorised.remove(instance.url));
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
          _resetToInstanceDefault();
        }
        _notify();
      });
      if (!accepted || connected == null) return;

      await instanceStore.save(List.of(_instances));
      if (lease.isCurrent) unawaited(_refreshOne(connected!));
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
        currentInstance?.url == instance.url) {
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
  /// Returns whether the signed-out rail snapshot was persisted. The key and
  /// private in-memory state are forgotten regardless.
  Future<bool> disconnectInstance(String siteUrl) async {
    final instance = _instanceAt(siteUrl);
    if (instance == null) return false;

    final lease = await _revokeAndForget(instance);
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
  Future<SiteLease> _revokeAndForget(DiscourseInstance instance) async {
    _forgetSiteState(instance.url);
    final lease = lifecycle.capture(instance.url);

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
    await drafts.clearSite(instance.url, ifCurrent: () => lease.isCurrent);
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
    store.forget(siteUrl);

    _likersLoading.removeWhere((key) => key.startsWith('$siteUrl~'));
    _likersErrors.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _userCardsLoading.removeWhere((key) => key.startsWith('$siteUrl@'));
    _userCardErrors.removeWhere((key, _) => key.startsWith('$siteUrl@'));
    _postWritesInFlight.removeWhere((key) => key.startsWith('$siteUrl~'));
    _postRefreshRequests.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _postRefreshPending.removeWhere((key) => key.startsWith('$siteUrl~'));
    _postRefreshTopics.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _topicsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _postsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _earlierPostsLoading.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicReadPositions.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _queuedTopicReadReceipts.removeWhere(
      (key, _) => key.startsWith('$siteUrl#'),
    );
    _topicReadReceiptTasks.removeWhere((key, _) => key.startsWith('$siteUrl#'));
    _topicReadReceiptRuns.removeWhere((key, _) => key.startsWith('$siteUrl#'));

    _categorised.remove(siteUrl);
    _categoriesBySite.remove(siteUrl);
    _topicComposerCapabilities.remove(siteUrl);
    _sitePresentation?.forget(siteUrl);
    _hashtags.remove(siteUrl);
    _hashtagsInFlight.remove(siteUrl);
    _mentioned.remove(siteUrl);
    _mentionsInFlight.remove(siteUrl);
    _connectErrors.remove(siteUrl);

    reactions.forget(siteUrl);
    chat.forget(siteUrl);
    resenha.forget(siteUrl);
    _feeds.removeWhere((key, _) => key.startsWith('$siteUrl|'));
    _filterQueries.remove(siteUrl);
    _feedRevisions.removeWhere((key, _) => key.startsWith('$siteUrl|'));
    _feedRows.removeWhere((key, _) => key.startsWith('$siteUrl|'));
    _feedPageRequests.removeWhere((key, _) => key.startsWith('$siteUrl|'));
    _trackersStarting.remove(siteUrl);
    _sessionUsersRefreshed.remove(siteUrl);
    _sessionUserRequests.remove(siteUrl)?.ignore();
    _disposeTracking(siteUrl);
    _notify();
  }

  void _replaceInstance(DiscourseInstance old, DiscourseInstance updated) {
    final index = _instances.indexOf(old);
    if (index >= 0) _instances[index] = updated;
  }

  void _resetToInstanceDefault({bool refreshAppearance = true}) {
    final instance = currentInstance;
    _contentStack.clear();
    _syncTracking();

    if (instance == null) {
      _destinationId = null;
      search.selectSite(null);
      return;
    }

    search.selectSite(
      instance.url,
      minimumLength: instance.config.minSearchTermLength,
    );

    final destination = instance.defaultDestination;
    _destinationId = destination.id;
    _contentStack.add(ContentRoute.fromDestination(destination));
    if (refreshAppearance) {
      unawaited(_presentation.ensureAppearance(instance.url));
    }
    if (instance.isConnected) unawaited(resenha.ensureLoaded(instance.url));
    unawaited(loadFeed(destination.id));
  }

  /// Tapping the already-selected instance is how you get back to its sidebar
  /// on a phone, where the sidebar and the content cannot both be visible.
  void selectInstance(int index) {
    assert(index >= 0 && index < _instances.length);
    if (index != _instanceIndex) {
      _instanceIndex = index;
      _resetToInstanceDefault();
      final selected = currentInstance;
      if (selected != null && selected.isConnected) {
        unawaited(_refreshOne(selected));
      }
    }
    _mobilePane = MobilePane.sidebar;
    _notify();
  }

  void selectDestination(SidebarDestination destination) {
    // Tapping what you are already looking at asks for it again — the cache
    // otherwise holds a list for the life of the session, and a mouse cannot
    // pull to refresh. Only at the destination's root: a tap that is busy
    // returning from a topic stays a return.
    final refresh =
        destination.id == _destinationId && _contentStack.length <= 1;

    _destinationId = destination.id;
    _contentStack
      ..clear()
      ..add(ContentRoute.fromDestination(destination));
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
    _notify();

    unawaited(loadFeed(destination.id, force: refresh));
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

  /// Opens the channel core would choose when its header chat icon is clicked.
  ///
  /// The channel list may still be arriving when the icon first appears, so
  /// this waits on that shared request and then verifies that the reader has
  /// not switched sites in the meantime.
  Future<void> openChat() async {
    final instance = currentInstance;
    if (instance == null || !instance.isConnected) return;
    final totals = currentTotals;
    if (totals?.hasChatEnabled != true ||
        instance.user?.hasChatEnabled == false) {
      return;
    }

    final siteUrl = instance.url;
    await chat.loadChannels(siteUrl);
    if (currentInstance?.url != siteUrl) return;

    final channel = chat.shortcutChannel(
      siteUrl,
      lastChannelId: currentInstance?.user?.lastChatChannelId,
    );
    if (channel != null) selectDestination(ChatPlugin.destination(channel));
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
      selectDestination(destination);
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
  void pushContent(ContentRoute route) {
    _contentStack.add(route);
    _mobilePane = MobilePane.content;
    _syncTopicChannels();
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
      _resetToInstanceDefault();
    }
    if (sameInstance && currentContent?.id == route.id) {
      // The sidebar secondary action and the persistent call card can both
      // open the room already on screen. Replacing its metadata keeps the
      // route fresh without adding an indistinguishable stack entry that
      // would make the first Back press appear to do nothing.
      _contentStack[_contentStack.length - 1] = route;
      _mobilePane = MobilePane.content;
      _syncTopicChannels();
      _notify();
      return;
    }
    if (replaceCurrent && sameInstance && _contentStack.isNotEmpty) {
      _contentStack[_contentStack.length - 1] = route;
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
    if (canPopContent) {
      _contentStack.removeLast();
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
    _queuedTopicReadReceipts.clear();
    _topicReadReceiptTasks.clear();
    _topicReadReceiptRuns.clear();
    for (final instance in _instances) {
      lifecycle.invalidate(instance.url);
    }
    updates.dispose();
    accountActivity.dispose();
    draftList.dispose();
    reactions.dispose();
    chat.dispose();
    resenha.dispose();
    search.dispose();
    final presentation = _sitePresentation;
    if (presentation != null) {
      presentation.removeListener(_notify);
      presentation.dispose();
    }
    _composer?.dispose();
    _composer = null;
    for (final tracker in _trackers.values) {
      tracker.dispose().ignore();
    }
    _trackers.clear();
    if (ownsApi) api.close();
    super.dispose();
  }
}
