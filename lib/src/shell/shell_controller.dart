import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/authenticator.dart';
import '../data/discourse_api.dart';
import '../data/draft_store.dart';
import '../data/instance_store.dart';
import '../data/user_api_key.dart';
import '../models/composer_draft.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
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
    required this.store,
    required this.api,
    required this.authenticator,
    required this.drafts,
  });

  final InstanceStore store;
  final DiscourseApi api;
  final Authenticator authenticator;
  final DraftStore drafts;

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

  bool _rightSidebarVisible = true;
  bool get rightSidebarVisible => _rightSidebarVisible;

  Future<void> load() async {
    final stored = await store.load();
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

    await store.save(_instances);
  }

  Future<void> removeInstance(DiscourseInstance instance) async {
    final index = _instances.indexOf(instance);
    if (index < 0) return;

    await _revokeAndForget(instance);
    _instances.removeAt(index);
    _instanceIndex = _instanceIndex.clamp(
      0,
      _instances.isEmpty ? 0 : _instances.length - 1,
    );
    _resetToInstanceDefault();
    _notify();

    await store.save(_instances);
  }

  final Map<String, NotificationTotals> _totals = {};

  NotificationTotals? totalsFor(DiscourseInstance instance) =>
      _totals[instance.url];

  /// Number on the rail for [instance]: things addressed to the user.
  int railBadgeFor(DiscourseInstance instance) =>
      _totals[instance.url]?.badge ?? 0;

  /// Number beside a sidebar entry, or 0 when there is nothing to show.
  ///
  /// All of these come from the one totals call rather than a request per
  /// section.
  int sidebarBadgeFor(String destinationId) {
    final totals = currentInstance == null
        ? null
        : _totals[currentInstance!.url];
    if (totals == null) return 0;

    return switch (destinationId) {
      'unread' => totals.topicTrackingUnread,
      'new' => totals.topicTrackingNew,
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

  final Map<String, TopicFeed> _feeds = {};
  final Map<String, List<TopicCategory>> _categories = {};

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
    for (final category
        in _categories[instance.url] ?? const <TopicCategory>[]) {
      if (category.id == categoryId) return category;
    }
    return null;
  }

  /// The list route behind a sidebar entry, or null for one that is not a
  /// topic list (bookmarks has its own shape).
  static String? feedPath(String destinationId, DiscourseInstance instance) {
    final username = instance.user?.username;
    return switch (destinationId) {
      'latest' => '/latest.json',
      'new' => '/new.json',
      'unread' => '/unread.json',
      'top' => '/top.json',
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
    _feeds[key] = const TopicFeed.loading();
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      final list = await api.topicList(
        siteUrl: instance.url,
        path: path,
        apiKey: apiKey,
      );
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

  final Map<String, TopicDetail> _topics = {};
  final Set<String> _topicsLoading = {};
  final Set<String> _postsLoading = {};

  static String _topicKey(String siteUrl, int topicId) => '$siteUrl#$topicId';

  /// The topic filling the main region, once it has arrived.
  TopicDetail? get currentTopic {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;
    return _topics[_topicKey(instance.url, topicId)];
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
    if (_topics.containsKey(key) && !force) return;

    _topicsLoading.add(key);
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      final detail = await api.topic(
        siteUrl: instance.url,
        slug: slug,
        id: topicId,
        apiKey: apiKey,
      );
      _topics[key] = detail;
      _retitle(topicId, detail.title);
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

  /// Fetches the next batch of posts in the open topic.
  ///
  /// A topic arrives with its first twenty posts plus the ids of all the rest,
  /// so paging is by id rather than by page number.
  Future<void> loadMorePosts({int batchSize = 20}) async {
    final instance = currentInstance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return;

    final key = _topicKey(instance.url, topicId);
    final detail = _topics[key];
    if (detail == null || !detail.hasMore) return;
    if (_postsLoading.contains(key)) return;

    _postsLoading.add(key);
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      final more = await api.posts(
        siteUrl: instance.url,
        topicId: topicId,
        ids: detail.pendingIds.take(batchSize).toList(),
        apiKey: apiKey,
      );
      _topics[key] = detail.withMorePosts(more);
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
  /// composer at the new post rather than discarding it.
  void openReply({int? replyToPostNumber, String? replyToUsername}) {
    final instance = currentInstance;
    final route = currentContent;
    final topicId = route?.topicId;
    if (instance == null || topicId == null || !canReplyHere) return;

    final existing = _composer;
    if (existing != null &&
        existing.target.topicId == topicId &&
        existing.target.siteUrl == instance.url) {
      existing.retarget(
        replyToPostNumber: replyToPostNumber,
        replyToUsername: replyToUsername,
      );
      existing.focus.requestFocus();
      return;
    }

    existing?.dispose();
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
      _topics[_topicKey(target.siteUrl, target.topicId)]?.draftSequence ??
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
    final topicKey = _topicKey(target.siteUrl, target.topicId);
    if (_topics[topicKey] case final detail?) {
      _topics[topicKey] = detail.withDraft(
        composer.draft,
        sequence ?? composer.draftSequence,
      );
    }

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
        local ?? _topics[_topicKey(target.siteUrl, target.topicId)]?.draft;
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
    final key = _topicKey(target.siteUrl, target.topicId);

    Post? landed;
    try {
      final fresh = await api.topic(
        siteUrl: target.siteUrl,
        slug: target.slug,
        id: target.topicId,
        apiKey: apiKey,
      );
      final held = _topics[key];
      _topics[key] = held == null ? fresh : held.withRefreshed(fresh);

      // Ours would be at the end, and a topic answers with its first chunk of
      // posts — so the tail has to be asked for by id.
      final tail = fresh.stream.length <= _reconcileWindow
          ? fresh.stream
          : fresh.stream.sublist(fresh.stream.length - _reconcileWindow);

      for (final post in await api.posts(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        ids: tail,
        includeRaw: true,
        apiKey: apiKey,
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
    final detail = _topics[key];
    if (detail != null) _topics[key] = detail.withNewPost(landed);
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
    final key = _topicKey(target.siteUrl, target.topicId);
    final detail = _topics[key];
    final post = creation.post;
    if (detail != null && post != null) {
      _topics[key] = detail.withNewPost(post);
    }

    // Accepting a post deletes its draft and advances the sequence server side,
    // so the local copy goes too and the next save uses the number it sent back
    // — keeping the old one earns a conflict on the very next keystroke.
    composer.draftSettled();
    unawaited(drafts.clear(target.siteUrl, target.draftKey));
    if (creation.draftSequence case final sequence?) {
      _draftSequences[_draftKey(target.siteUrl, target.draftKey)] = sequence;
    }
    if (_topics[key] case final held?) {
      _topics[key] = held.withDraft(null, _draftSequence(target));
    }

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
      final fresh = await api.topic(
        siteUrl: siteUrl,
        slug: slug,
        id: topicId,
        apiKey: apiKey,
      );
      final held = _topics[key];
      _topics[key] = held == null ? fresh : held.withRefreshed(fresh);
    } catch (_) {
      // The post is already on screen; the stream is repaired next time.
    }
    _topicsLoading.remove(key);
    _notify();
  }

  final Map<String, UserCard> _userCards = {};
  final Set<String> _userCardsLoading = {};
  final Map<String, String> _userCardErrors = {};

  static String _userKey(String siteUrl, String username) =>
      '$siteUrl@$username';

  /// The card for [username] on the current site, once it has arrived.
  UserCard? userCard(String username) {
    final instance = currentInstance;
    if (instance == null) return null;
    return _userCards[_userKey(instance.url, username)];
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
    if (_userCards.containsKey(key) && !force) return;

    _userCardsLoading.add(key);
    _userCardErrors.remove(key);
    _notify();

    final apiKey = await authenticator.apiKeyFor(instance.url);
    try {
      _userCards[key] = await api.userCard(
        siteUrl: instance.url,
        username: username,
        apiKey: apiKey,
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

      // A topic bumped between page fetches shifts the window and comes back
      // on the next page too, so drop anything already held.
      final seen = feed.topics.map((t) => t.id).toSet();
      final fresh = next.topics.where((t) => !seen.contains(t.id)).toList();

      _feeds[key] = feed.copyWith(
        topics: [...feed.topics, ...fresh],
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
    if (_categories.containsKey(instance.url)) return;

    try {
      _categories[instance.url] = await api.categories(
        siteUrl: instance.url,
        apiKey: apiKey,
      );
      _notify();
    } catch (_) {
      // Badges are decoration; the list still reads without them.
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
      await store.save(_instances);
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
    _notify();
    await store.save(_instances);
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
    await authenticator.disconnect(instance.url);
    _totals.remove(instance.url);
  }

  void _replaceInstance(DiscourseInstance old, DiscourseInstance updated) {
    final index = _instances.indexOf(old);
    if (index >= 0) _instances[index] = updated;
  }

  void _resetToInstanceDefault() {
    final instance = currentInstance;
    _contentStack.clear();

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

  void toggleRightSidebar() {
    _rightSidebarVisible = !_rightSidebarVisible;
    _notify();
  }

  bool _disposed = false;

  /// Requests outlive the widget tree — a list or a counter can land after the
  /// shell is gone, and ChangeNotifier throws if notified once disposed.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _composer?.dispose();
    _composer = null;
    api.close();
    super.dispose();
  }
}
