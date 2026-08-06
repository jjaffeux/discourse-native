import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../data/authenticator.dart';
import '../data/discourse_api.dart';
import '../data/draft_store.dart';
import '../data/instance_store.dart';
import '../data/site_tracker.dart';
import '../data/store.dart';
import '../data/user_api_key.dart';
import '../models/bookmark_feed.dart';
import '../models/composer_draft.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/notification.dart';
import '../models/notification_feed.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/post_likers.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../models/topic_link.dart';
import '../models/sidebar.dart';
import '../models/user_card.dart';
import 'composer_controller.dart';

/// Which pane occupies the space next to the rail when the shell is compact.
///
/// Only one of them can be on screen at a time on a phone; the rail itself is
/// always visible alongside whichever one is showing.
enum MobilePane { sidebar, content }

/// Everything the shell needs to decide what to draw.
///
/// Deliberately a plain [ChangeNotifier] so the skeleton carries no state
/// management dependency. Swapping in Riverpod or Bloc later only touches
/// [ShellScope] and this class.
class ShellController extends ChangeNotifier {
  ShellController({
    required this.instanceStore,
    required this.api,
    required this.authenticator,
    required this.drafts,
    Store? store,
    this.trackers = SiteTracker.new,
  }) : store = store ?? Store();

  final InstanceStore instanceStore;

  /// The identity map. Every topic, post, category and user card the app holds
  /// lives here once, and the maps in this class hold ids into it — so a list,
  /// a topic being read and a card popup are all drawing the same records
  /// rather than copies that have to be kept in step by hand.
  final Store store;

  final DiscourseApi api;
  final Authenticator authenticator;
  final DraftStore drafts;

  /// Opens a site's live connection. See [SiteTrackerFactory].
  final SiteTrackerFactory trackers;

  bool _connecting = false;

  /// True while the authorize flow is open, so the UI can show progress.
  bool get connecting => _connecting;

  String? _connectError;
  String? get connectError => _connectError;

  final List<DiscourseInstance> _instances = [];
  List<DiscourseInstance> get instances => List.unmodifiable(_instances);
  bool get hasInstances => _instances.isNotEmpty;

  bool _loaded = false;

  /// False until the stored sites have been read, so the shell can avoid
  /// flashing the empty state on launch.
  bool get loaded => _loaded;

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

  Future<void> load() async {
    final stored = await instanceStore.load();
    _instances
      ..clear()
      ..addAll(stored);
    _instanceIndex = 0;
    _resetToInstanceDefault();
    _loaded = true;
    _notify();

    // Counters are stale from the moment they were stored, so pull fresh ones
    // for every connected site. Deliberately not awaited by callers.
    unawaited(refreshTotals());
  }

  bool contains(String url) => _instances.any((i) => i.url == url);

  /// Appends a connected site and selects it.
  Future<void> addInstance(DiscourseInstance instance) async {
    if (contains(instance.url)) return;

    _instances.add(instance);
    _instanceIndex = _instances.length - 1;
    _resetToInstanceDefault();
    _mobilePane = MobilePane.sidebar;
    _notify();

    await instanceStore.save(_instances);
  }

  /// Signs [instance] out and takes it out of the rail.
  Future<void> removeInstance(DiscourseInstance instance) async {
    final index = _instances.indexOf(instance);
    if (index < 0) return;

    final selected = currentInstance;
    await _revokeAndForget(instance);
    _instances.removeAt(index);

    if (selected == instance) {
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

    await instanceStore.save(_instances);
  }

  final Map<String, NotificationTotals> _totals = {};

  NotificationTotals? totalsFor(DiscourseInstance instance) =>
      _totals[instance.url];

  /// Counters for the site on screen — what the user menu's tabs show, and
  /// what puts the dot on the avatar that opens it.
  NotificationTotals? get currentTotals {
    final instance = currentInstance;
    return instance == null ? null : _totals[instance.url];
  }

  /// Number on the rail for [instance]: things addressed to the user.
  int railBadgeFor(DiscourseInstance instance) =>
      _totals[instance.url]?.badge ?? 0;

  /// Number beside a sidebar entry, or 0 when there is nothing to show.
  ///
  /// It comes from the one totals call rather than a request per section.
  int sidebarBadgeFor(String destinationId) {
    final totals = currentInstance == null
        ? null
        : _totals[currentInstance!.url];
    if (totals == null) return 0;

    return switch (destinationId) {
      'messages' => totals.unreadPersonalMessages,
      _ => 0,
    };
  }

  /// Refreshes counters for every connected site, in parallel.
  Future<void> refreshTotals() async {
    await Future.wait(_instances.where((i) => i.isConnected).map(_refreshOne));
  }

  Future<void> _refreshOne(DiscourseInstance instance) async {
    final apiKey = await authenticator.apiKeyFor(instance.url);
    if (apiKey == null) return;

    try {
      final totals = await api.notificationTotals(
        siteUrl: instance.url,
        apiKey: apiKey,
      );
      _totals[instance.url] = totals;
      _notify();
    } catch (_) {
      // Counters are decoration. A site being down must not break the shell.
    }
  }

  final Map<String, NotificationFeed> _notifications = {};

  /// The current site's notifications, as far as they have been fetched.
  NotificationFeed get notifications {
    final instance = currentInstance;
    if (instance == null) return const NotificationFeed();
    return _notifications[instance.url] ?? const NotificationFeed();
  }

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
  Future<void> loadNotifications() async {
    final instance = currentInstance;
    if (instance == null || !instance.isConnected) return;

    final held = _notifications[instance.url];
    if (held != null && held.loading) return;

    if (held == null || held.error != null) {
      _notifications[instance.url] = const NotificationFeed.loading();
      _notify();
    }

    void fail(String message) {
      // Rows already on screen are better than an error where they were: they
      // were true a moment ago, and the next open tries again.
      if (held != null && held.notifications.isNotEmpty) return;
      _notifications[instance.url] = NotificationFeed.failed(message);
    }

    final apiKey = await authenticator.apiKeyFor(instance.url);
    if (apiKey == null) {
      fail('Reconnect to ${instance.host} to see notifications.');
      _notify();
      return;
    }

    try {
      _notifications[instance.url] = NotificationFeed.of(
        await api.notifications(siteUrl: instance.url, apiKey: apiKey),
      );
    } on SiteLookupException catch (e) {
      fail(
        e.failure == SiteLookupFailure.notDiscourse
            ? 'Not allowed — try reconnecting to ${instance.host}.'
            : "Couldn't reach ${instance.host}.",
      );
    } catch (_) {
      fail("Couldn't load notifications from ${instance.host}.");
    }
    _notify();
  }

  /// Marks [notification] read, which is what opening it amounts to here.
  ///
  /// Where it then leads is [DiscourseNotification.path], handled the same way
  /// as any other link — see `NotificationSection`. Called from the bookmarks
  /// tab too, whose reminders are notifications like any other.
  void readNotification(DiscourseNotification notification) {
    final instance = currentInstance;
    if (instance == null || notification.read) return;
    unawaited(_markNotificationRead(instance, notification));
  }

  /// Marks one notification read, here and on the site.
  ///
  /// The row stops being unread immediately rather than when the request
  /// lands: the user has just opened the thing it points at, and anything else
  /// reads as lag. A failure leaves the site's copy unread, which the next
  /// fetch restores.
  ///
  /// Both tabs holding it are corrected, not just the one it was tapped in: a
  /// bookmark reminder sits in the notifications list and the bookmarks list at
  /// once, and reading it in one place does not leave it unread in the other.
  Future<void> _markNotificationRead(
    DiscourseInstance instance,
    DiscourseNotification notification,
  ) async {
    if (_notifications[instance.url] case final feed?) {
      _notifications[instance.url] = feed.withRead(notification.id);
    }
    if (_bookmarks[instance.url] case final feed?) {
      _bookmarks[instance.url] = feed.withRead(notification.id);
    }
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    if (apiKey == null) return;

    try {
      await api.markNotificationRead(
        siteUrl: instance.url,
        apiKey: apiKey,
        id: notification.id,
      );
    } catch (_) {
      return;
    }

    // Every badge in the shell counts unread notifications, so they are all one
    // out until the site is asked again.
    await _refreshOne(instance);
  }

  final Map<String, BookmarkFeed> _bookmarks = {};

  /// The current site's bookmarks, as far as they have been fetched.
  BookmarkFeed get bookmarks {
    final instance = currentInstance;
    if (instance == null) return const BookmarkFeed();
    return _bookmarks[instance.url] ?? const BookmarkFeed();
  }

  /// Fetches what the user menu's bookmarks tab lists.
  ///
  /// Refetched every time the tab appears, for the same reason as
  /// [loadNotifications]: a reminder that came due while the menu was shut is
  /// the whole point of opening it, and bookmarks are cheap to ask for.
  ///
  /// Signed out there is nothing to ask — the route is the account's own, and
  /// names it — so the tab is left empty rather than showing a failure the
  /// reader can do nothing about from here.
  Future<void> loadBookmarks() async {
    final instance = currentInstance;
    final username = instance?.user?.username;
    if (instance == null || username == null) return;

    final held = _bookmarks[instance.url];
    if (held != null && held.loading) return;

    if (held == null || held.error != null) {
      _bookmarks[instance.url] = const BookmarkFeed.loading();
      _notify();
    }

    void fail(String message) {
      // Rows already on screen are better than an error where they were: they
      // were true a moment ago, and the next open tries again.
      if (held != null && held.hasRows) return;
      _bookmarks[instance.url] = BookmarkFeed.failed(message);
    }

    final apiKey = await authenticator.apiKeyFor(instance.url);
    if (apiKey == null) {
      fail('Reconnect to ${instance.host} to see your bookmarks.');
      _notify();
      return;
    }

    try {
      _bookmarks[instance.url] = BookmarkFeed.of(
        await api.bookmarks(
          siteUrl: instance.url,
          apiKey: apiKey,
          username: username,
        ),
      );
    } on SiteLookupException catch (e) {
      fail(
        e.failure == SiteLookupFailure.notDiscourse
            ? 'Not allowed — try reconnecting to ${instance.host}.'
            : "Couldn't reach ${instance.host}.",
      );
    } catch (_) {
      fail("Couldn't load bookmarks from ${instance.host}.");
    }
    _notify();
  }

  final Map<String, TopicFeed> _feeds = {};

  /// Sites whose category list has been fetched. The categories themselves are
  /// in the store; this only remembers not to ask again.
  final Set<String> _categorised = {};

  static String _feedKey(String siteUrl, String destinationId) =>
      '$siteUrl|$destinationId';

  /// The list currently filling the main region, if the destination has one.
  TopicFeed? get currentFeed {
    final instance = currentInstance;
    final destination = _destinationId;
    if (instance == null || destination == null) return null;
    return _feeds[_feedKey(instance.url, destination)];
  }

  /// Category badge for a topic, once categories have been fetched.
  TopicCategory? categoryFor(int? categoryId) {
    final instance = currentInstance;
    if (instance == null || categoryId == null) return null;
    return store.read<TopicCategory>(instance.url, categoryId);
  }

  /// The topic behind a row, watched rather than read.
  ///
  /// The list holds ids, so this is how a row gets its topic — and why editing
  /// a topic anywhere redraws that row and nothing else.
  Ref<Topic> topicRef(String siteUrl, int topicId) =>
      store.ref<Topic>(siteUrl, topicId);

  Ref<Post> postRef(String siteUrl, int postId) =>
      store.ref<Post>(siteUrl, postId);

  /// The list route behind a sidebar entry, or null when there is none to
  /// fetch (messages needs a signed-in user to name the inbox).
  static String? feedPath(String destinationId, DiscourseInstance instance) {
    final username = instance.user?.username;
    return switch (destinationId) {
      'latest' => '/latest.json',
      'messages' when username != null =>
        '/topics/private-messages/$username.json',
      _ => null,
    };
  }

  /// Fetches the list for [destinationId] unless it is already in hand.
  Future<void> loadFeed(String destinationId, {bool force = false}) async {
    final instance = currentInstance;
    if (instance == null) return;

    final path = feedPath(destinationId, instance);
    if (path == null) return;

    final key = _feedKey(instance.url, destinationId);
    final existing = _feeds[key];
    if (existing != null && !force && (existing.loading || existing.loaded)) {
      return;
    }

    // The list is about to be replaced wholesale, so the old position means
    // nothing — a refresh should leave the user at the top.
    _feedRows.remove(key);
    // And whatever was announced as incoming is about to arrive in the response
    // rather than needing a banner to fetch it. Cleared before the request, not
    // after, so a topic created while it is in flight still counts.
    _trackers[instance.url]?.incoming.reset(destinationId);
    _feeds[key] = const TopicFeed.loading();
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      final list = await api.topicList(
        siteUrl: instance.url,
        path: path,
        apiKey: apiKey,
      );
      store.putAll(instance.url, list.topics);
      _feeds[key] = TopicFeed.of(list);
    } on SiteLookupException catch (e) {
      _feeds[key] = TopicFeed.failed(
        e.failure == SiteLookupFailure.notDiscourse
            ? 'Not allowed — try reconnecting to ${instance.host}.'
            : "Couldn't reach ${instance.host}.",
      );
    } catch (_) {
      _feeds[key] = TopicFeed.failed("Couldn't load ${instance.host}.");
    }
    _notify();

    unawaited(_ensureCategories(instance, apiKey));
  }

  final Map<String, int> _feedRows = {};

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
    final path = feedPath(destinationId, instance);
    if (feed == null || tracker == null || path == null) return;
    if (feed.loadingIncoming) return;

    final ids = tracker.incoming.topicIds(destinationId);
    if (ids.isEmpty) return;

    _feeds[key] = feed.copyWith(loadingIncoming: true);
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      final list = await api.topicList(
        siteUrl: instance.url,
        path: '$path?topic_ids=${ids.join(',')}',
        apiKey: apiKey,
      );

      store.putAll(instance.url, list.topics);

      // Read again rather than reusing `feed`: a page may have landed while
      // this was in flight.
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
      // The rows moved down by however many arrived, and the list is about to
      // jump back to the top to show them.
      _feedRows[key] = 0;
    } catch (_) {
      // Nothing is lost: the ids are still counted, so the banner stays and
      // tapping it again tries the same fetch.
      _feeds[key] = (_feeds[key] ?? feed).copyWith(loadingIncoming: false);
    }
    _notify();
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

    for (final entry in _trackers.entries) {
      if (entry.key != instance?.url) entry.value.stop();
    }
    if (instance == null) return;

    final tracker = _trackers[instance.url];
    if (tracker == null) {
      unawaited(_startTracking(instance));
      return;
    }
    tracker.start();
  }

  /// Opens a site's connection, once the keychain has said who we are.
  ///
  /// Signed out this still runs: `/latest` is public, so a reader with no
  /// account still gets the banner.
  Future<void> _startTracking(DiscourseInstance instance) async {
    final siteUrl = instance.url;
    if (_trackers.containsKey(siteUrl) || !_trackersStarting.add(siteUrl)) {
      return;
    }

    final String? apiKey;
    final String clientId;
    try {
      apiKey = await authenticator.apiKeyFor(siteUrl);
      clientId = await authenticator.clientId();
    } catch (_) {
      _trackersStarting.remove(siteUrl);
      return;
    }

    final userId = apiKey == null
        ? null
        : await _accountId(siteUrl, apiKey: apiKey);
    _trackersStarting.remove(siteUrl);

    // The site may have been removed, or the shell torn down, while the
    // keychain and the site were answering.
    if (_disposed || _instanceAt(siteUrl) == null) return;

    final tracker = trackers(
      siteUrl: siteUrl,
      userId: userId,
      apiKey: apiKey,
      clientId: clientId,
      shouldLongPoll: () => _foreground,
      onIncomingTopics: _notify,
      onNotifications: (data) =>
          _applyCounts(siteUrl, (held) => held.withNotification(data)),
      onReviewableCounts: (data) =>
          _applyCounts(siteUrl, (held) => held.withReviewableCounts(data)),
    );
    _trackers[siteUrl] = tracker;
    // Subscribing starts the client, so a site that stopped being the current
    // one in the meantime has to be put back to sleep.
    if (currentInstance?.url != siteUrl) tracker.stop();
  }

  /// The account id for a connected site, asking the site for it if what was
  /// stored predates our needing it.
  ///
  /// Discourse names a user's counter channels after their id, so without it
  /// there is nothing to subscribe to. Sites connected before this existed have
  /// a user with no id in preferences; one `/session/current.json` heals that
  /// for good, since what comes back is written straight back out.
  Future<int?> _accountId(String siteUrl, {required String apiKey}) async {
    final held = _instanceAt(siteUrl);
    if (held?.user?.id case final id?) return id;
    if (held == null) return null;

    final DiscourseUser user;
    try {
      user = await api.currentUser(siteUrl: siteUrl, apiKey: apiKey);
    } catch (_) {
      // The connection is still worth opening for `/latest`.
      return null;
    }

    final fresh = _instanceAt(siteUrl);
    if (fresh == null) return null;
    // Only when it told us something new. A site old enough not to report an
    // id at all would otherwise be rewritten to preferences every launch, for
    // an answer that never changes.
    if (fresh.user != user) {
      _replaceInstance(fresh, fresh.copyWith(user: user));
      _notify();
      unawaited(instanceStore.save(_instances));
    }
    return user.id;
  }

  /// Folds a counters message onto what is held for a site.
  ///
  /// Nothing is redrawn when the message changes nothing we show, which is the
  /// common case: `/notification/` is published on every read as well as every
  /// arrival, and a read the user made here has already been applied.
  void _applyCounts(
    String siteUrl,
    NotificationTotals Function(NotificationTotals held) fold,
  ) {
    final held = _totals[siteUrl] ?? const NotificationTotals();
    final updated = fold(held);
    if (updated == held) return;

    _totals[siteUrl] = updated;
    _notify();
  }

  void _disposeTracking(String siteUrl) {
    final tracker = _trackers.remove(siteUrl);
    if (tracker != null) unawaited(tracker.dispose());
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
    if (!foreground) return;

    final instance = currentInstance;
    if (instance != null) _trackers[instance.url]?.pollNow();
  }

  final Set<String> _topicsLoading = {};
  final Set<String> _postsLoading = {};

  static String _topicKey(String siteUrl, int topicId) => '$siteUrl#$topicId';

  /// The topic filling the main region, once it has arrived.
  TopicDetail? get currentTopic {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;
    return store.read<TopicDetail>(instance.url, topicId);
  }

  /// The ids of the posts on screen, in reading order.
  ///
  /// The topic knows every post id it has; the store knows which of them have
  /// actually been fetched. The list drawn is the intersection, which is what
  /// the topic used to keep a second copy of.
  List<int> get currentPostIds {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return const [];
    return [
      for (final id in detail.stream)
        if (store.read<Post>(instance.url, id) != null) id,
    ];
  }

  /// Post ids the stream names but nothing has fetched, oldest first.
  List<int> _pendingPostIds(String siteUrl, TopicDetail detail) => [
    for (final id in detail.stream)
      if (store.read<Post>(siteUrl, id) == null) id,
  ];

  /// Whether the topic on screen has posts left to fetch.
  bool get currentTopicHasMore {
    final instance = currentInstance;
    final detail = currentTopic;
    if (instance == null || detail == null) return false;
    return _pendingPostIds(instance.url, detail).isNotEmpty;
  }

  bool get currentTopicLoading {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _topicsLoading.contains(_topicKey(instance.url, topicId));
  }

  /// Replaces the main region with [topic] and fetches it.
  void openTopic(Topic topic) => _openTopic(topic.id, topic.slug, topic.title);

  void _openTopic(int topicId, String slug, String title) {
    pushContent(ContentRoute.topic(topicId: topicId, slug: slug, title: title));
    unawaited(loadTopic(topicId, slug));
  }

  /// Absolute form of [url].
  ///
  /// Discourse writes its own links site-relative — `/t/slug/1`, `/u/someone`
  /// — so they only mean anything once resolved against the site they were
  /// written on. Anything already absolute is returned untouched, including
  /// the schemes that are not ours to resolve, such as `mailto:`.
  String absoluteUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';

    final uri = Uri.tryParse(url);
    if (uri == null || uri.hasScheme) return url;

    final base = currentInstance?.url;
    if (base == null) return url;
    return '$base${url.startsWith('/') ? '' : '/'}$url';
  }

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

    _openTopic(link.topicId, link.slug, link.placeholderTitle);
    return true;
  }

  Future<void> loadTopic(int topicId, String slug, {bool force = false}) async {
    final instance = currentInstance;
    if (instance == null) return;

    final key = _topicKey(instance.url, topicId);
    if (_topicsLoading.contains(key)) return;
    if (store.read<TopicDetail>(instance.url, topicId) != null && !force) {
      return;
    }

    _topicsLoading.add(key);
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      final fetched = await api.topic(
        siteUrl: instance.url,
        slug: slug,
        id: topicId,
        apiKey: apiKey,
      );
      _absorb(instance.url, fetched);
      _retitle(topicId, fetched.detail.title);
    } catch (_) {
      // Left absent; the view shows its own failure state.
    }
    _topicsLoading.remove(key);
    _notify();
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
      );
    }
  }

  /// Files a topic payload: the posts under their own ids, the topic under
  /// its own, and the list row corrected to match.
  ///
  /// That last part is what having one copy is for. Reading a topic is what
  /// makes it read, and the row saying so is in however many lists happen to
  /// hold it — `/latest`, `/unread`, `/new` — none of which this knows or needs
  /// to. There is one row, so there is one thing to change.
  TopicDetail _absorb(String siteUrl, TopicPayload payload) {
    store.putAll(siteUrl, payload.posts);
    final detail = store.put(siteUrl, payload.detail);
    store.update<Topic>(
      siteUrl,
      detail.id,
      (row) => row.copyWith(
        title: detail.title,
        postsCount: detail.postsCount,
        markRead: true,
      ),
    );
    return detail;
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

    _postsLoading.add(key);
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      store.putAll(
        instance.url,
        await api.posts(
          siteUrl: instance.url,
          topicId: topicId,
          ids: pending.take(batchSize).toList(),
          apiKey: apiKey,
        ),
      );
    } catch (_) {
      // Keep what is already shown.
    }
    _postsLoading.remove(key);
    _notify();
  }

  bool get loadingMorePosts {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return _postsLoading.contains(_topicKey(instance.url, topicId));
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
    return currentContent?.topicId == composer.target.topicId ? composer : null;
  }

  /// Whether a reply affordance should be offered for the topic on screen.
  bool get canReplyHere => currentTopic?.canCreatePost ?? false;

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
    final composer = ComposerController(target, onSaveDraft: _saveDraft)
      ..draftSequence = _draftSequence(target);
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

    _replaceComposer();
    final target = ComposerTarget(
      siteUrl: instance.url,
      topicId: topicId,
      slug: route?.slug ?? '',
      topicTitle: route?.title ?? '',
      editingPostId: post.id,
      editingPostNumber: post.postNumber,
    );
    // No `onSaveDraft`: Discourse files a topic's drafts under one key, so
    // saving here would overwrite an unfinished reply with the text of a post
    // that is already published.
    final composer = ComposerController(target);
    _composer = composer;
    _notify();

    unawaited(_loadEditBody(composer, post));
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
    final apiKey = await authenticator.apiKeyFor(target.siteUrl);
    try {
      final fetched = await api.posts(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        ids: [post.id],
        includeRaw: true,
        apiKey: apiKey,
      );
      final raw = fetched.firstWhere((p) => p.id == post.id).raw;
      if (raw == null) {
        composer.bodyLoadFailed();
        return;
      }
      composer.loadedBody(raw);
    } catch (_) {
      composer.bodyLoadFailed();
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

    final error = await _mutatePost(
      post,
      (siteUrl, apiKey) =>
          api.deletePost(siteUrl: siteUrl, apiKey: apiKey, postId: post.id),
    );

    // Editing something that has just been deleted is writing into a hole, and
    // saving would fail anyway.
    if (error == null && _composer?.target.editingPostId == post.id) {
      closeComposer();
    }
    return error;
  }

  /// Puts a deleted post back.
  Future<String?> recoverPost(Post post) async {
    if (!post.canRecover) return null;
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
  Future<String?> toggleLike(Post post) async {
    final instance = currentInstance;
    if (instance == null || !post.canToggleLike) return null;

    final siteUrl = instance.url;
    final key = _likersKey(siteUrl, post.id);
    // One at a time per post. Without this a double tap sends a like and an
    // undo at once — the second reads the guess the first just wrote — and
    // whichever answer lands last decides what is drawn, which is not
    // necessarily the one the site ended up believing.
    if (!_likesInFlight.add(key)) return null;

    try {
      return await _writeLike(siteUrl, post);
    } finally {
      _likesInFlight.remove(key);
    }
  }

  Future<String?> _writeLike(String siteUrl, Post post) async {
    final apiKey = await authenticator.apiKeyFor(siteUrl);
    if (apiKey == null) {
      return const WriteException(WriteFailure.forbidden).message;
    }

    final liked = !post.liked;
    store.put(siteUrl, post.withLike(liked));
    _notify();

    /// Puts the like back the way it was, and nothing else.
    ///
    /// A whole copy of the post would do it too, and would also undo anything
    /// that landed while the request was in flight — an edit, a deletion, a
    /// re-read. Only the four fields this touched are its to put back.
    void revert() {
      store.update<Post>(siteUrl, post.id, (held) => held.withLikesOf(post));
      _notify();
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
      if (fresh != null) store.put(siteUrl, fresh);
    } on WriteException catch (e) {
      revert();
      return e.message;
    } catch (_) {
      revert();
      return const WriteException(WriteFailure.unreachable).message;
    }
    _notify();
    return null;
  }

  final Set<String> _likesInFlight = {};

  final Set<String> _likersLoading = {};
  final Map<String, String> _likersErrors = {};

  static String _likersKey(String siteUrl, int postId) => '$siteUrl~$postId';

  /// Who liked a post, once the list has been asked for and arrived.
  PostLikers? likers(int postId) {
    final instance = currentInstance;
    if (instance == null) return null;
    return store.read<PostLikers>(instance.url, postId);
  }

  bool likersLoading(int postId) {
    final instance = currentInstance;
    if (instance == null) return false;
    return _likersLoading.contains(_likersKey(instance.url, postId));
  }

  String? likersError(int postId) {
    final instance = currentInstance;
    if (instance == null) return null;
    return _likersErrors[_likersKey(instance.url, postId)];
  }

  /// Fetches the accounts behind a post's like count.
  ///
  /// Asked for every time the list is opened rather than once, because it is a
  /// list of what other people have just done and the point of opening it is to
  /// see who. Names already on screen stay there while the fetch runs, so
  /// reopening a list is instant and merely gets corrected.
  Future<void> loadLikers(int postId) async {
    final instance = currentInstance;
    if (instance == null) return;

    final key = _likersKey(instance.url, postId);
    if (!_likersLoading.add(key)) return;
    _likersErrors.remove(key);
    _notify();

    try {
      store.put(
        instance.url,
        await api.postLikers(
          siteUrl: instance.url,
          postId: postId,
          // Read inside the guard, not before it: a keychain that refuses —
          // an unsigned macOS build answers `errSecMissingEntitlement` —
          // would otherwise leave the key in [_likersLoading] for the rest of
          // the session, and every later hover would find a fetch in flight
          // that is not.
          apiKey: await authenticator.apiKeyFor(instance.url),
        ),
      );
    } on SiteLookupException catch (e) {
      _likersErrors[key] = e.failure == SiteLookupFailure.notDiscourse
          ? "Couldn't see who liked this."
          : "Couldn't reach ${instance.host}.";
    } catch (_) {
      _likersErrors[key] = "Couldn't load who liked this.";
    }
    _likersLoading.remove(key);
    _notify();
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
    final apiKey = await authenticator.apiKeyFor(siteUrl);
    if (apiKey == null) {
      return const WriteException(WriteFailure.forbidden).message;
    }

    try {
      await write(siteUrl, apiKey);
    } on WriteException catch (e) {
      return e.message;
    } catch (_) {
      return const WriteException(WriteFailure.unreachable).message;
    }

    await _refreshPost(siteUrl, topicId, post.id, apiKey);
    return null;
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
  ) async {
    List<Post> fetched;
    try {
      fetched = await api.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: [postId],
        apiKey: apiKey,
      );
    } catch (_) {
      // The write landed; the stream is repaired the next time it is read.
      return;
    }

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
      unawaited(_saveDraft(existing).catchError((_) {}));
    }
    existing.dispose();
    _composer = null;
  }

  /// Closes the composer, keeping the draft.
  ///
  /// Closing is how you get the topic back, not how you throw a reply away —
  /// reopening restores what was written.
  void closeComposer() {
    if (_composer == null) return;
    _composer!.dispose();
    _composer = null;
    _notify();
  }

  final Map<String, int> _draftSequences = {};

  static String _draftKey(String siteUrl, String draftKey) =>
      '$siteUrl#$draftKey';

  int _draftSequence(ComposerTarget target) =>
      _draftSequences[_draftKey(target.siteUrl, target.draftKey)] ??
      store.read<TopicDetail>(target.siteUrl, target.topicId)?.draftSequence ??
      0;

  /// Writes the local copy first, then sends it.
  ///
  /// In that order, and the local copy is only removed once the site has the
  /// same text — so at no point is the reply somewhere it can be lost.
  Future<void> _saveDraft(ComposerController composer) async {
    final target = composer.target;
    final data = composer.draft.encode();

    await drafts.write(target.siteUrl, target.draftKey, data);

    final apiKey = await authenticator.apiKeyFor(target.siteUrl);
    if (apiKey == null) throw const WriteException(WriteFailure.forbidden);

    final sequence = await api.saveDraft(
      siteUrl: target.siteUrl,
      apiKey: apiKey,
      draftKey: target.draftKey,
      sequence: composer.draftSequence,
      data: data,
      // Discourse uses this to tell the same account writing from somewhere
      // else apart from this client coming back.
      owner: await authenticator.clientId(),
    );

    if (sequence != null) {
      composer.draftSequence = sequence;
      _draftSequences[_draftKey(target.siteUrl, target.draftKey)] = sequence;
    }

    // Keep the cached topic saying what a fresh fetch would say, so reopening
    // the composer finds the draft the site now holds.
    store.update<TopicDetail>(
      target.siteUrl,
      target.topicId,
      (detail) =>
          detail.withDraft(composer.draft, sequence ?? composer.draftSequence),
    );

    await drafts.clear(target.siteUrl, target.draftKey);
  }

  /// Puts an unfinished reply back in the composer.
  Future<void> _restoreDraft(ComposerController composer) async {
    final target = composer.target;

    // The local copy exists only while the site does not have the text, so if
    // there is one it is the newer of the two by construction — no timestamps
    // to compare, and no chance of restoring over something newer.
    final local = ComposerDraft.decode(
      await drafts.read(target.siteUrl, target.draftKey),
    );
    final draft =
        local ?? store.read<TopicDetail>(target.siteUrl, target.topicId)?.draft;
    if (draft == null) return;

    composer.restore(draft);
    if (draft.replyToPostNumber != null &&
        target.replyToPostNumber == null &&
        identical(_composer, composer)) {
      composer.retarget(
        replyToPostNumber: draft.replyToPostNumber,
        replyToUsername: draft.replyToUsername,
      );
    }
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

    if (target.isEdit) return _submitEdit(composer, target, raw);

    final apiKey = await authenticator.apiKeyFor(target.siteUrl);
    if (apiKey == null) {
      composer.failed(const WriteException(WriteFailure.forbidden));
      return;
    }

    composer.beginSubmit();
    final PostCreation creation;
    try {
      creation = await api.createPost(
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
        await _reconcile(target, raw, composer, e);
      } else {
        composer.failed(e);
      }
      return;
    } catch (_) {
      await _reconcile(
        target,
        raw,
        composer,
        const WriteException(WriteFailure.unreachable),
      );
      return;
    }

    _applyCreation(target, creation, composer);
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
    final apiKey = await authenticator.apiKeyFor(target.siteUrl);
    if (apiKey == null) {
      composer.failed(const WriteException(WriteFailure.forbidden));
      return;
    }

    composer.beginSubmit();
    final Post updated;
    try {
      updated = await api.updatePost(
        siteUrl: target.siteUrl,
        apiKey: apiKey,
        postId: target.editingPostId!,
        raw: raw,
      );
    } on WriteException catch (e) {
      composer.failed(e);
      return;
    } catch (_) {
      composer.failed(const WriteException(WriteFailure.unreachable));
      return;
    }

    // Everything the edit says about the post, except what it says about
    // likes — which is nothing, however confidently it is phrased.
    // `PostsController#update` serializes without the reader's own post
    // actions, so `actions_summary` comes back with no `acted` and a
    // `can_act: true` that is simply wrong on a post they have already liked.
    // Taken literally it would empty the heart of anyone who fixes a typo.
    final held = store.read<Post>(target.siteUrl, updated.id);
    store.put(
      target.siteUrl,
      held == null ? updated : updated.withLikesOf(held),
    );

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
    await _reconcile(
      composer.target,
      composer.raw,
      composer,
      const WriteException(WriteFailure.unreachable),
    );
  }

  /// How far back to look for a post that may or may not have been made.
  static const int _reconcileWindow = 5;

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
    WriteException failure,
  ) async {
    composer.checking();

    final username = _instanceAt(target.siteUrl)?.user?.username;
    final apiKey = await authenticator.apiKeyFor(target.siteUrl);

    Post? landed;
    try {
      final fresh = _absorb(
        target.siteUrl,
        await api.topic(
          siteUrl: target.siteUrl,
          slug: target.slug,
          id: target.topicId,
          apiKey: apiKey,
        ),
      );

      // Ours would be at the end, and a topic answers with its first chunk of
      // posts — so the tail has to be asked for by id.
      final tail = fresh.stream.length <= _reconcileWindow
          ? fresh.stream
          : fresh.stream.sublist(fresh.stream.length - _reconcileWindow);

      for (final post in store.putAll(
        target.siteUrl,
        await api.posts(
          siteUrl: target.siteUrl,
          topicId: target.topicId,
          ids: tail,
          includeRaw: true,
          apiKey: apiKey,
        ),
      )) {
        if (post.username == username && post.raw?.trim() == raw) {
          landed = post;
          break;
        }
      }
    } catch (_) {
      // Still unknown, and saying "it failed" would invite the second post
      // this whole path exists to prevent.
      composer.unresolved();
      _notify();
      return;
    }

    if (landed == null) {
      composer.checkedNotPosted(failure);
      _notify();
      return;
    }

    // It posted after all. Show it, and let the composer go.
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
    unawaited(drafts.clear(target.siteUrl, target.draftKey));
    if (creation.draftSequence case final sequence?) {
      _draftSequences[_draftKey(target.siteUrl, target.draftKey)] = sequence;
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

  /// Re-reads a topic on a named site, rather than on whatever is current.
  Future<void> _refetchTopic(String siteUrl, int topicId, String slug) async {
    final key = _topicKey(siteUrl, topicId);
    if (_topicsLoading.contains(key)) return;
    _topicsLoading.add(key);

    final apiKey = await authenticator.apiKeyFor(siteUrl);
    try {
      _absorb(
        siteUrl,
        await api.topic(
          siteUrl: siteUrl,
          slug: slug,
          id: topicId,
          apiKey: apiKey,
        ),
      );
    } catch (_) {
      // The post is already on screen; the stream is repaired next time.
    }
    _topicsLoading.remove(key);
    _notify();
  }

  final Set<String> _userCardsLoading = {};
  final Map<String, String> _userCardErrors = {};

  static String _userKey(String siteUrl, String username) =>
      '$siteUrl@$username';

  /// The card for [username] on the current site, once it has arrived.
  UserCard? userCard(String username) {
    final instance = currentInstance;
    if (instance == null) return null;
    return store.read<UserCard>(instance.url, username);
  }

  bool userCardLoading(String username) {
    final instance = currentInstance;
    if (instance == null) return false;
    return _userCardsLoading.contains(_userKey(instance.url, username));
  }

  String? userCardError(String username) {
    final instance = currentInstance;
    if (instance == null) return null;
    return _userCardErrors[_userKey(instance.url, username)];
  }

  /// Fetches the card for [username] unless it is already in hand.
  ///
  /// Cards are cached for the life of the session: the same handful of people
  /// write most of a topic, and re-opening a card should be instant.
  Future<void> loadUserCard(String username, {bool force = false}) async {
    final instance = currentInstance;
    if (instance == null || username.isEmpty) return;

    final key = _userKey(instance.url, username);
    if (_userCardsLoading.contains(key)) return;
    if (store.read<UserCard>(instance.url, username) != null && !force) return;

    _userCardsLoading.add(key);
    _userCardErrors.remove(key);
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      store.put(
        instance.url,
        await api.userCard(
          siteUrl: instance.url,
          username: username,
          apiKey: apiKey,
        ),
      );
    } on SiteLookupException catch (e) {
      _userCardErrors[key] = e.failure == SiteLookupFailure.notDiscourse
          ? "Couldn't see that profile."
          : "Couldn't reach ${instance.host}.";
    } catch (_) {
      _userCardErrors[key] = "Couldn't load @$username.";
    }
    _userCardsLoading.remove(key);
    _notify();
  }

  /// Appends the next page, if there is one and nothing is already in flight.
  Future<void> loadMoreFeed(String destinationId) async {
    final instance = currentInstance;
    if (instance == null) return;

    final key = _feedKey(instance.url, destinationId);
    final feed = _feeds[key];
    if (feed == null || feed.loadingMore || !feed.hasMore) return;

    _feeds[key] = feed.copyWith(loadingMore: true);
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      final next = await api.topicList(
        siteUrl: instance.url,
        path: feed.nextPagePath!,
        apiKey: apiKey,
      );

      store.putAll(instance.url, next.topics);

      // A topic bumped between page fetches shifts the window and comes back
      // on the next page too, so drop anything already held.
      final seen = feed.topicIds.toSet();
      final fresh = [
        for (final topic in next.topics)
          if (!seen.contains(topic.id)) topic.id,
      ];

      _feeds[key] = feed.copyWith(
        topicIds: [...feed.topicIds, ...fresh],
        loadingMore: false,
        nextPagePath: next.nextPagePath,
        // No further page, or a page that added nothing: stop asking.
        clearNextPage: next.nextPagePath == null || fresh.isEmpty,
      );
    } catch (_) {
      // Keep what is already on screen; the footer just stops spinning.
      _feeds[key] = feed.copyWith(loadingMore: false);
    }
    _notify();
  }

  /// Categories are fetched once per site; the topic rows need them to draw
  /// their badges, and they change rarely.
  Future<void> _ensureCategories(
    DiscourseInstance instance,
    String? apiKey,
  ) async {
    if (!_categorised.add(instance.url)) return;

    try {
      store.putAll(
        instance.url,
        await api.categories(siteUrl: instance.url, apiKey: apiKey),
      );
      _notify();
    } catch (_) {
      // Badges are decoration; the list still reads without them. Asking again
      // on the next list is fine — it is one request per site per session.
      _categorised.remove(instance.url);
    }
  }

  /// Sends the user to the current site to authorize, then records who they
  /// turned out to be.
  Future<void> connectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null || _connecting) return;

    _connecting = true;
    _connectError = null;
    _notify();

    try {
      final credentials = await authenticator.connect(instance.url);
      final user = await api.currentUser(
        siteUrl: instance.url,
        apiKey: credentials.key,
      );
      final connected = instance.copyWith(
        user: user,
        apiVersion: credentials.apiVersion,
      );
      _replaceInstance(instance, connected);
      // Reopen the connection with the key in it, so `/new` is subscribed to.
      _disposeTracking(connected.url);
      _syncTracking();
      await instanceStore.save(_instances);
      unawaited(_refreshOne(connected));
    } on UserApiAuthException catch (e) {
      // Backing out of the browser is a normal thing to do, not an error.
      _connectError = e.failure == UserApiAuthFailure.cancelled
          ? null
          : e.message;
    } on SiteLookupException catch (e) {
      _connectError = e.message;
    } catch (e) {
      _connectError = 'Could not connect to ${instance.host}.';
    } finally {
      _connecting = false;
      _notify();
    }
  }

  /// Forgets the key and who we were, leaving the site in the rail.
  Future<void> disconnectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null) return;

    await _revokeAndForget(instance);
    _replaceInstance(instance, instance.copyWith(clearUser: true));
    _syncTracking();
    _notify();
    await instanceStore.save(_instances);
  }

  /// Tells the site to drop the key before we drop our copy.
  ///
  /// Deleting locally is not enough: the key would stay live in the user's
  /// authorized-apps list with no way for them to connect it to us.
  Future<void> _revokeAndForget(DiscourseInstance instance) async {
    final apiKey = await authenticator.apiKeyFor(instance.url);
    if (apiKey != null) {
      try {
        await api.revokeApiKey(siteUrl: instance.url, apiKey: apiKey);
      } catch (_) {
        // Offline, or a site too old for the route. Forget it locally anyway —
        // keeping a key we can no longer see is worse.
      }
    }
    try {
      await authenticator.disconnect(instance.url);
    } catch (_) {
      // A keychain that will not answer must not be able to strand a site in
      // the rail, which is what letting this through does — the removal is
      // abandoned half done and the site is still there. Revoking above is
      // what actually kills the key; dropping our copy is hygiene, and
      // connecting again overwrites whatever was left behind.
    }
    _totals.remove(instance.url);
    // Reconnecting can land on a different account, and what the last one was
    // notified about, kept, or could see at all is none of its business.
    _notifications.remove(instance.url);
    _bookmarks.remove(instance.url);
    store.forget(instance.url);
    _categorised.remove(instance.url);
    _feeds.removeWhere((key, _) => key.startsWith('${instance.url}|'));
    // The key is baked into the poll headers, so the connection cannot outlive
    // it. A signed-out one is opened in its place by whoever called this.
    _disposeTracking(instance.url);
  }

  void _replaceInstance(DiscourseInstance old, DiscourseInstance updated) {
    final index = _instances.indexOf(old);
    if (index >= 0) _instances[index] = updated;
  }

  void _resetToInstanceDefault() {
    final instance = currentInstance;
    _contentStack.clear();
    _syncTracking();

    if (instance == null) {
      _destinationId = null;
      return;
    }

    final destination = instance.defaultDestination;
    _destinationId = destination.id;
    _contentStack.add(ContentRoute.fromDestination(destination));
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
    _destinationId = destination.id;
    _contentStack
      ..clear()
      ..add(ContentRoute.fromDestination(destination));
    _mobilePane = MobilePane.content;
    _notify();

    unawaited(loadFeed(destination.id));
  }

  /// Replaces the main region with something deeper, keeping a way back.
  void pushContent(ContentRoute route) {
    _contentStack.add(route);
    _mobilePane = MobilePane.content;
    _notify();
  }

  /// Unwinds one step: first through the content stack, then — on compact
  /// layouts only — back out to the sidebar.
  ///
  /// Returns false when there is nothing left to unwind, which is the signal
  /// to let the platform handle the back gesture.
  bool handleBack({bool canReturnToSidebar = true}) {
    if (canPopContent) {
      _contentStack.removeLast();
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

  void showContentPane() {
    if (_mobilePane == MobilePane.content) return;
    _mobilePane = MobilePane.content;
    _notify();
  }

  bool _disposed = false;
  bool _notifyScheduled = false;

  /// Requests outlive the widget tree — a list or a counter can land after the
  /// shell is gone, and ChangeNotifier throws if notified once disposed.
  ///
  /// Some callers also arrive *inside* a frame, where marking the tree dirty
  /// is an error rather than a rebuild. A viewport whose position ends up past
  /// the end of its content — the window grew, the list shrank, a jump
  /// overshot — puts that right by starting a scroll from inside its own
  /// `performLayout`, and the notification dispatched there reaches the
  /// load-more handlers, which ask for the next page.
  ///
  /// So the phase is checked here rather than at each of the thirty-odd call
  /// sites, none of which can know which one they are running in: a
  /// notification raised mid-frame waits for the end of it instead. One
  /// deferred notification per frame is enough, since listeners read the state
  /// rather than the notification.
  void _notify() {
    if (_disposed) return;

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      });
      return;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _composer?.dispose();
    _composer = null;
    for (final tracker in _trackers.values) {
      unawaited(tracker.dispose());
    }
    _trackers.clear();
    api.close();
    super.dispose();
  }
}
