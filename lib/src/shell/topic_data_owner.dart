import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';

import '../models/post.dart';
import '../models/post_mutation_outcome.dart';
import '../models/topic.dart';
import '../plugin_api/discourse_model_codec.dart';
import 'bookmark_transactions.dart';
import 'topic_prefetch_controller.dart';

typedef TopicDataPosition = ({String slug, int postNumber});

final class TopicOpening {
  const TopicOpening({
    required this.received,
    required this.resume,
    required this.canResume,
  });

  final void Function(TopicDetail detail) received;
  final TopicDataPosition? Function(int postNumber) resume;
  final bool Function() canResume;
}

final class TopicDataOwner {
  TopicDataOwner({
    required this.content,
    required this.feeds,
    required this.models,
    required this.store,
    required this.credentials,
    required this.lifecycle,
    required this.changed,
    required this.liveChanged,
    required this.published,
    required this.prepareCategories,

    required this.loadTimeout,
    required this.bookmarkReads,
  });

  final TopicContentApi content;
  final TopicFeedsApi feeds;
  final DiscourseModelCodec models;
  final Store store;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final void Function() changed;
  final void Function(String siteUrl) liveChanged;
  final bool Function(String siteUrl, TopicDetail detail) published;
  final Future<void> Function(String siteUrl, Iterable<int> ids)
  prepareCategories;

  final Duration loadTimeout;
  final BookmarkReadProjection Function(String, SiteLease) bookmarkReads;
  final _prefetch = TopicPrefetchController();
  final Map<String, TopicDataSession> _accounts = {};
  bool _disposed = false;

  TopicDataSession forSite(String siteUrl) {
    if (_disposed) throw StateError('Topic data owner is disposed.');
    final held = _accounts[siteUrl];
    if (held != null && held.isCurrent) return held;
    final account = TopicDataSession._(
      this,
      siteUrl,
      lifecycle.capture(siteUrl),
    );
    _accounts[siteUrl] = account;
    account._detach = account.lease.onRetire(() {
      account._retire();
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
      _prefetch.validate();
    });
    return account;
  }

  TopicDataSession? forLease(String siteUrl, SiteLease lease) {
    if (_disposed || !lease.isCurrent) return null;
    final account = forSite(siteUrl);
    return identical(account.lease.session, lease.session) ? account : null;
  }

  void validatePrefetch() => _prefetch.validate();
  void clearPrefetch() => _prefetch.clear();

  void forget(String siteUrl) {
    _prefetch.clear();
    _accounts.remove(siteUrl)?._retire();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _prefetch.clear();
    for (final account in _accounts.values.toList()) {
      account._retire();
    }
    _accounts.clear();
  }
}

final class _TopicState {
  Object? reading;
  bool refreshPending = false;
  int? refreshPostNumber;
  bool stale = false;
  Object? newerPage;
  Object? earlierPage;
  Object? summaryRead;
  List<int>? summary;
  final Map<(int, bool), Object> gaps = {};
  int archive = 0;
  int removals = 0;
  int streams = 0;
  int positions = 0;
  int matchingReads = 0;
  final Map<int, int> removedAt = {};
  _LiveBatch? queuedLive;
  int? deferredPostsCount;
}

final class _PostState {
  final Set<Object> holders = {};
  Object? refreshOwner;
  bool refreshPending = false;
  int? topicId;
  bool deletion = false;
}

typedef _ReadStamp = ({int bookmarks, int archive, int removals, int streams});

final class _LiveBatch {
  _LiveBatch(this.topicId);
  final int topicId;
  final Set<int> postIds = {};
}

final class _CapturedKey implements SiteApiKeyReader {
  const _CapturedKey(this.key);
  final String? key;

  @override
  Future<String?> apiKeyFor(String siteUrl) async => key;
}

final class TopicDataSession implements BookmarkTopicData {
  TopicDataSession._(this._owner, this.siteUrl, this.lease);

  final TopicDataOwner _owner;
  final String siteUrl;
  final SiteLease lease;
  final Map<int, _TopicState> _topics = {};
  final Map<int, _PostState> _posts = {};
  final Map<int, void Function()> _pluginWrites = {};
  final Set<_ModerationRecovery> _moderationRecoveries = {};
  void Function()? _detach;
  bool _retired = false;

  bool get isCurrent => !_retired && !_owner._disposed && lease.isCurrent;
  Store get _store => _owner.store;
  _TopicState _topic(int id) => _topics.putIfAbsent(id, _TopicState.new);
  _PostState _post(int id) => _posts.putIfAbsent(id, _PostState.new);
  AccountRequestSession get _requests => AccountRequestSession(siteUrl, lease);

  bool loading(int topicId) => isCurrent && _topic(topicId).reading != null;
  bool paging(int topicId, {required bool newer}) =>
      isCurrent &&
      (newer ? _topic(topicId).newerPage : _topic(topicId).earlierPage) != null;
  bool summaryLoading(int topicId) =>
      isCurrent && _topic(topicId).summaryRead != null;
  bool showingSummary(int topicId) =>
      isCurrent && _topic(topicId).summary != null;
  @override
  bool postWriting(int postId) => isCurrent && _post(postId).holders.isNotEmpty;
  late final BookmarkReadProjection _bookmarks = _owner.bookmarkReads(
    siteUrl,
    lease,
  );

  List<int> streamFor(TopicDetail detail) =>
      isCurrent ? _topic(detail.id).summary ?? detail.stream : detail.stream;

  void clearSummary(int topicId) {
    if (isCurrent) _topic(topicId).summary = null;
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    _topics.clear();
    _posts.clear();
    _pluginWrites.clear();
    _moderationRecoveries.clear();
  }

  void _changed() {
    if (isCurrent) _owner.changed();
  }

  void _update<T extends Storable<T>>(Object id, T Function(T) change) {
    if (isCurrent) _store.update<T>(siteUrl, id, change);
  }

  T? _put<T extends Storable<T>>(T record) =>
      isCurrent ? _store.put(siteUrl, record) : null;

  _ReadStamp _stamp(int topicId) {
    final state = _topic(topicId);
    return (
      bookmarks: _bookmarks.revision(topicId),
      archive: state.archive,
      removals: state.removals,
      streams: state.streams,
    );
  }

  Set<int> _removedSince(int topicId, int version) {
    final state = _topic(topicId);
    if (state.removals == version) return const {};
    return {
      for (final entry in state.removedAt.entries)
        if (entry.value > version) entry.key,
    };
  }

  bool _removedAfter(int topicId, int postId, int version) =>
      (_topic(topicId).removedAt[postId] ?? 0) > version;

  void removePost(int topicId, int postId) {
    if (!isCurrent) return;
    final state = _topic(topicId);
    state.removedAt[postId] = ++state.removals;
    _store.remove<Post>(siteUrl, postId);
    _update<TopicDetail>(topicId, (detail) => detail.withoutPostId(postId));
    final summary = state.summary;
    if (summary != null && summary.contains(postId)) {
      state.summary = List.unmodifiable([
        for (final id in summary)
          if (id != postId) id,
      ]);
    }
  }

  TopicPayload _withoutRemoved(TopicPayload payload, int removalVersion) {
    final removed = _removedSince(payload.detail.id, removalVersion);
    if (removed.isEmpty) return payload;
    return (
      detail: removed.fold(
        payload.detail,
        (detail, id) => detail.withoutPostId(id),
      ),
      posts: [
        for (final post in payload.posts)
          if (!removed.contains(post.id)) post,
      ],
    );
  }

  bool _publishPosts(
    int topicId,
    Iterable<Post> incoming,
    _ReadStamp stamp, {
    bool onlyUnloaded = false,
  }) {
    for (final post in incoming) {
      if (!isCurrent) return false;
      final state = _topic(topicId);
      if ((state.removedAt[post.id] ?? 0) > stamp.removals ||
          (onlyUnloaded && _store.containsRecord<Post>(siteUrl, post.id))) {
        continue;
      }
      _put(_bookmarks.postFromRead(topicId, stamp.bookmarks, post));
    }
    return isCurrent;
  }

  TopicDetail? _publishTopic(
    TopicPayload response,
    _ReadStamp stamp, {
    bool positioned = false,
  }) {
    if (!isCurrent) return null;
    final payload = _withoutRemoved(response, stamp.removals);
    final topicId = payload.detail.id;
    final state = _topic(topicId);
    state.streams++;
    if (!_publishPosts(topicId, payload.posts, stamp)) return null;
    final held = _store.read<TopicDetail>(siteUrl, topicId);
    final latest = _withoutRemoved(response, stamp.removals);
    var incoming = _bookmarks.detailFromRead(stamp.bookmarks, latest.detail);
    if (held != null && stamp.archive != state.archive) {
      incoming = incoming.copyWith(messageArchived: held.messageArchived);
    }
    final stored = _put(incoming);
    if (!isCurrent || stored == null) return null;
    var detail = _store.read<TopicDetail>(siteUrl, topicId) ?? stored;
    final positionedStream = _withoutRemoved(
      response,
      stamp.removals,
    ).detail.stream;
    if (positioned && detail.isMegaTopic && positionedStream.isNotEmpty) {
      final run = detail.stream.toSet();
      if (!positionedStream.any(run.contains)) {
        _update<TopicDetail>(
          topicId,
          (held) => held.copyWith(stream: positionedStream),
        );
        detail = _store.read<TopicDetail>(siteUrl, topicId) ?? detail;
      }
    }
    if (!isCurrent) return null;
    state.stale = false;
    final accepted = detail;
    _update<Topic>(
      topicId,
      (row) => _bookmarks.projectTopicRow(
        row
            .copyWith(title: accepted.title, postsCount: accepted.postsCount)
            .withPlugins(accepted.plugins),
      ),
    );
    if (!isCurrent) return null;
    detail = _store.read<TopicDetail>(siteUrl, topicId) ?? detail;
    _owner.published(siteUrl, detail);
    return isCurrent ? _store.read<TopicDetail>(siteUrl, topicId) : null;
  }

  void refreshWhenOpened(int topicId) {
    if (!isCurrent) return;
    final state = _topic(topicId);
    if (state.reading != null) {
      state.refreshPending = true;
    } else {
      state.stale = true;
    }
  }

  bool _hasPost(int topicId, int? postNumber) {
    final held = _store.read<TopicDetail>(siteUrl, topicId);
    return held != null &&
        (postNumber == null ||
            held.stream.any(
              (id) => _store.read<Post>(siteUrl, id)?.postNumber == postNumber,
            ));
  }

  Future<T> _stage<T>(Future<T> future, Stopwatch elapsed, String description) {
    final remaining = _owner.loadTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      return Future<T>.error(
        TimeoutException(appL10n.timedOut(description), _owner.loadTimeout),
      );
    }
    return future.timeout(
      remaining,
      onTimeout: () => throw TimeoutException(
        appL10n.timedOut(description),
        _owner.loadTimeout,
      ),
    );
  }

  void Function() prefetch(
    Topic topic, {
    required TopicPrefetchIntent intent,
    required bool Function() isInterested,
  }) {
    if (!isCurrent ||
        loading(topic.id) ||
        (!_topic(topic.id).stale &&
            _hasPost(topic.id, topic.lastUnreadPostNumber))) {
      return () {};
    }
    final postNumber = topic.lastUnreadPostNumber;
    return _owner._prefetch.hover(
      (
        siteUrl: siteUrl,
        session: lease.session,
        topicId: topic.id,
        postNumber: postNumber,
      ),
      intent: intent,
      isCurrent: () => isCurrent && isInterested(),
      load: (cancellation) async {
        final elapsed = Stopwatch()..start();
        final stamp = _stamp(topic.id);
        try {
          final credential = await _stage(
            Future.any<AccountRequestCredentials?>([
              _requests.credentials(_owner.credentials),
              cancellation.trigger.then((_) => null),
            ]),
            elapsed,
            'reading credentials for topic prefetch',
          );
          if (credential == null || !isCurrent || cancellation.isCancelled) {
            return null;
          }
          final payload = await _stage(
            credential.run(
              () => _owner.content.topic(
                siteUrl: siteUrl,
                slug: topic.slug,
                id: topic.id,
                postNumber: postNumber,
                apiKey: credential.apiKey,
                clientId: credential.clientId,
                abortTrigger: cancellation.trigger,
              ),
            ),
            elapsed,
            'prefetching topic ${topic.id}',
          );
          if (!isCurrent || cancellation.isCancelled) return null;
          return PrefetchedTopic(
            payload,
            stamp.bookmarks,
            stamp.archive,
            stamp.removals,
          );
        } catch (_) {
          cancellation.cancel();
          return null;
        }
      },
    );
  }

  Future<void> open(
    int topicId, {
    required String slug,
    int? postNumber,
    bool force = false,
    required TopicOpening opening,
  }) async {
    if (!isCurrent) return;
    final state = _topic(topicId);
    if (postNumber != null) {
      state.positions++;
    }
    if (state.reading != null) {
      if (force || postNumber != null) {
        state.refreshPending = true;
        if (postNumber != null) state.refreshPostNumber = postNumber;
      }
      return;
    }
    force = force || state.refreshPending;
    postNumber ??= state.refreshPostNumber;
    if (state.refreshPending && postNumber != null) {
      state.refreshPostNumber = postNumber;
    }
    final positionAtOpen = state.positions;
    final held = _store.read<TopicDetail>(siteUrl, topicId);
    if (held != null) opening.received(held);
    if (!isCurrent || positionAtOpen != state.positions) return;
    if (state.reading != null) {
      await open(
        topicId,
        slug: slug,
        postNumber: postNumber,
        force: force,
        opening: opening,
      );
      return;
    }
    if (postNumber == null &&
        !force &&
        !state.stale &&
        held?.resumePostNumber != null &&
        opening.canResume()) {
      final target = opening.resume(held!.resumePostNumber!);
      if (!isCurrent || positionAtOpen != state.positions) return;
      if (target != null && isCurrent) {
        await open(
          topicId,
          slug: target.slug,
          postNumber: target.postNumber,
          opening: opening,
        );
        return;
      }
    }
    if (held != null &&
        !force &&
        !state.stale &&
        _hasPost(topicId, postNumber)) {
      if (_owner.published(siteUrl, held)) _changed();
      return;
    }
    final elapsed = Stopwatch()..start();
    final key = (
      siteUrl: siteUrl,
      session: lease.session,
      topicId: topicId,
      postNumber: postNumber,
    );
    if (force || state.stale) _owner._prefetch.discard(key);
    final prefetched = _owner._prefetch.take(key);
    var stamp = _stamp(topicId);
    final reading = Object();
    state.reading = reading;
    state.refreshPending = false;
    state.refreshPostNumber = null;
    if (force) state.stale = true;
    _changed();
    TopicDetail? received;
    int? resumeNumber;
    var replay = false;
    int? replayNumber;
    int? settledPosition;
    try {
      if (force) {
        await _recoverPendingModeration(topicId);
        if (!isCurrent) return;
        stamp = _stamp(topicId);
      }
      final credential = await _stage(
        _requests.credentials(_owner.credentials),
        elapsed,
        'reading credentials for topic $topicId',
      );
      if (!isCurrent) return;
      final warmed = prefetched == null
          ? null
          : await _stage(
              prefetched,
              elapsed,
              'waiting for topic prefetch $topicId',
            );
      if (!isCurrent) return;
      if (warmed != null) {
        stamp = (
          bookmarks: warmed.bookmarkVersion,
          archive: warmed.archiveVersion,
          removals: warmed.postRemovalVersion,
          streams: stamp.streams,
        );
      }
      final TopicPayload fetched =
          warmed?.payload ??
          await _stage<TopicPayload>(
            credential.run(
              () => _owner.content.topic(
                siteUrl: siteUrl,
                slug: slug,
                id: topicId,
                postNumber: postNumber,
                apiKey: credential.apiKey,
                clientId: credential.clientId,
              ),
            ),
            elapsed,
            'loading topic $topicId',
          );
      if (!isCurrent) return;

      try {
        await _stage(
          _owner.prepareCategories(siteUrl, [
            ?fetched.detail.categoryId,
            for (final source
                in fetched.detail.recommendations?.sources ??
                    const <TopicRecommendationSource>[])
              for (final row in source.topics) ?row.categoryId,
          ]),
          elapsed,
          'loading the category for topic $topicId',
        );
      } on TimeoutException {
        if (!isCurrent) return;
      }
      if (!isCurrent) return;

      received = _publishTopic(fetched, stamp, positioned: postNumber != null);
      if (received != null && isCurrent) {
        opening.received(received);
        if (postNumber == null && opening.canResume()) {
          resumeNumber = received.resumePostNumber;
        }
      }
    } catch (error) {
    } finally {
      if (isCurrent && identical(state.reading, reading)) {
        state.reading = null;
        settledPosition = state.positions;
        replay = state.refreshPending;
        _changed();
      }
      if (replay &&
          isCurrent &&
          state.reading == null &&
          state.refreshPending) {
        replayNumber = state.refreshPostNumber;
        var replaySlug = '';
        if (replayNumber == null &&
            resumeNumber != null &&
            settledPosition == state.positions) {
          final target = opening.resume(resumeNumber);
          if (target != null) {
            replayNumber = target.postNumber;
            replaySlug = target.slug;
          }
        }
        if (isCurrent && state.reading == null && state.refreshPending) {
          unawaited(
            refresh(topicId, slug: replaySlug, postNumber: replayNumber),
          );
        }
      }
    }
    if (!replay &&
        isCurrent &&
        resumeNumber != null &&
        settledPosition == state.positions) {
      final target = opening.resume(resumeNumber);
      if (target != null && isCurrent && settledPosition == state.positions) {
        await open(
          topicId,
          slug: target.slug,
          postNumber: target.postNumber,
          opening: opening,
        );
      }
    }
  }

  Future<void> refresh(int topicId, {String slug = '', int? postNumber}) async {
    if (!isCurrent) return;
    final state = _topic(topicId);
    if (postNumber != null) {
      state.positions++;
    }
    if (state.reading != null) {
      state.refreshPending = true;
      if (postNumber != null) state.refreshPostNumber = postNumber;
      return;
    }
    postNumber ??= state.refreshPostNumber;
    var stamp = _stamp(topicId);
    final reading = Object();
    state.reading = reading;
    state.refreshPending = false;
    state.refreshPostNumber = null;
    state.stale = true;
    try {
      await _recoverPendingModeration(topicId);
      if (!isCurrent) return;
      stamp = _stamp(topicId);
      final credential = await _requests.credentials(_owner.credentials);
      if (!isCurrent) return;
      final payload = await credential.run(
        () => _owner.content.topic(
          siteUrl: siteUrl,
          slug: slug,
          id: topicId,
          postNumber: postNumber,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
      _publishTopic(payload, stamp, positioned: postNumber != null);
    } catch (error) {
      if (isCurrent) state.stale = true;
    } finally {
      if (isCurrent && identical(state.reading, reading)) {
        state.reading = null;
        _changed();
        if (isCurrent && state.reading == null && state.refreshPending) {
          unawaited(refresh(topicId, postNumber: state.refreshPostNumber));
        }
      }
    }
  }

  Future<void> pageIds(
    int topicId, {
    required List<int> ids,
    required bool newer,
    bool reachesEnd = false,
  }) async {
    if (!isCurrent || ids.isEmpty || paging(topicId, newer: newer)) return;
    final state = _topic(topicId);
    final detail = _store.read<TopicDetail>(siteUrl, topicId);
    if (detail == null) return;
    final requested = ids.take(TopicDetail.maximumInitialPosts).toList();
    final recommendations =
        newer && reachesEnd && detail.recommendations == null;
    final stamp = _stamp(topicId);
    final reading = Object();
    if (newer) {
      state.newerPage = reading;
    } else {
      state.earlierPage = reading;
    }
    _changed();
    try {
      final credential = await _requests.keyCredentials(_owner.credentials);
      if (!isCurrent) return;
      final page = recommendations
          ? await credential.run(
              () => _owner.content.topicPosts(
                siteUrl: siteUrl,
                topicId: topicId,
                ids: requested,
                apiKey: credential.apiKey,
              ),
            )
          : (
              posts: await credential.run(
                () => _owner.content.posts(
                  siteUrl: siteUrl,
                  topicId: topicId,
                  ids: requested,
                  apiKey: credential.apiKey,
                ),
              ),
              recommendations: null,
            );
      if (!isCurrent) return;
      final wanted = requested.toSet();
      if (!_publishPosts(
        topicId,
        page.posts.where((post) => wanted.contains(post.id)),
        stamp,
        onlyUnloaded: true,
      )) {
        return;
      }
      if (stamp.streams == state.streams &&
          state.reading == null &&
          state.matchingReads == 0) {
        final stream = _store.read<TopicDetail>(siteUrl, topicId)?.stream;
        final served = {for (final post in page.posts) post.id};
        for (final id in requested) {
          if (!isCurrent ||
              stamp.streams != state.streams ||
              state.reading != null ||
              state.matchingReads != 0) {
            break;
          }
          if (stream?.contains(id) == true &&
              !served.contains(id) &&
              _store.read<Post>(siteUrl, id) == null) {
            removePost(topicId, id);
          }
        }
      }
      if (page.recommendations case final snapshot?) {
        _update<TopicDetail>(
          topicId,
          (held) => held.recommendations == null
              ? held.withRecommendations(snapshot)
              : held,
        );
      }
    } catch (error) {
    } finally {
      if (isCurrent) {
        if (newer && identical(state.newerPage, reading)) {
          state.newerPage = null;
        }
        if (!newer && identical(state.earlierPage, reading)) {
          state.earlierPage = null;
        }
        _changed();
      }
    }
  }

  Future<void> pageMega(
    TopicDetail detail,
    Post edge, {
    required bool newer,
  }) async {
    if (!isCurrent || paging(detail.id, newer: newer)) return;
    final state = _topic(detail.id);
    final stamp = _stamp(detail.id);
    final reading = Object();
    if (newer) {
      state.newerPage = reading;
    } else {
      state.earlierPage = reading;
    }
    _changed();
    try {
      final credential = await _requests.keyCredentials(_owner.credentials);
      if (!isCurrent) return;
      final posts = await credential.run(
        () => _owner.content.postsFromNumber(
          siteUrl: siteUrl,
          topicId: detail.id,
          postNumber: edge.postNumber,
          ascending: newer,
          apiKey: credential.apiKey,
        ),
      );
      if (!isCurrent) return;
      final removed = _removedSince(detail.id, stamp.removals);
      final page = [
        for (final post in posts)
          if (!removed.contains(post.id) &&
              (newer
                  ? post.postNumber > edge.postNumber
                  : post.postNumber < edge.postNumber))
            post,
      ];
      if (!_publishPosts(detail.id, page, stamp)) return;
      _update<TopicDetail>(
        detail.id,
        (held) => held.withMegaTopicPage(
          anchorPostId: edge.id,
          newer: newer,
          postIds: [
            for (final post in page)
              if (!_removedSince(detail.id, stamp.removals).contains(post.id))
                post.id,
          ],
          lastPostIdAtDispatch: detail.lastPostId,
        ),
      );
    } catch (error) {
    } finally {
      if (isCurrent) {
        if (newer && identical(state.newerPage, reading)) {
          state.newerPage = null;
        }
        if (!newer && identical(state.earlierPage, reading)) {
          state.earlierPage = null;
        }
        _changed();
      }
    }
  }

  Future<void> expandGap(
    int topicId, {
    required int anchorPostId,
    required bool before,
  }) async {
    if (!isCurrent) return;
    final detail = _store.read<TopicDetail>(siteUrl, topicId);
    final gap = (before
        ? detail?.gapsBefore
        : detail?.gapsAfter)?[anchorPostId];
    if (gap == null || gap.isEmpty) return;
    final state = _topic(topicId);
    final key = (anchorPostId, before);
    if (state.gaps.containsKey(key)) return;
    final reading = Object();
    state.gaps[key] = reading;
    final requested = gap.take(TopicDetail.maximumInitialPosts).toList();
    final stamp = _stamp(topicId);
    try {
      final credential = await _requests.keyCredentials(_owner.credentials);
      if (!isCurrent) return;
      final posts = await credential.run(
        () => _owner.content.posts(
          siteUrl: siteUrl,
          topicId: topicId,
          ids: requested,
          apiKey: credential.apiKey,
        ),
      );
      if (!isCurrent) return;
      final removed = _removedSince(topicId, stamp.removals);
      final byId = {
        for (final post in posts)
          if (requested.contains(post.id) && !removed.contains(post.id))
            post.id: post,
      };
      final revealed = [
        for (final id in requested)
          if (byId.containsKey(id)) id,
      ];
      if (!_publishPosts(topicId, [
        for (final id in revealed) byId[id]!,
      ], stamp)) {
        return;
      }
      _update<TopicDetail>(
        topicId,
        (held) => held.withExpandedGap(
          anchorPostId: anchorPostId,
          before: before,
          consumedIds: requested,
          revealedIds: [
            for (final id in revealed)
              if (!_removedSince(topicId, stamp.removals).contains(id)) id,
          ],
        ),
      );
      _changed();
    } catch (error) {
    } finally {
      if (isCurrent && identical(state.gaps[key], reading)) {
        state.gaps.remove(key);
      }
    }
  }

  Future<bool> toggleSummary(int topicId, {required String slug}) async {
    if (!isCurrent) return true;
    final state = _topic(topicId);
    if (state.summary != null) {
      state.summary = null;
      _changed();
      return true;
    }
    if (state.summaryRead != null) return true;
    final reading = Object();
    state.summaryRead = reading;
    final stamp = _stamp(topicId);
    _changed();
    try {
      final credential = await _requests.credentials(_owner.credentials);
      if (!isCurrent) return true;
      final response = await credential.run(
        () => _owner.content.topic(
          siteUrl: siteUrl,
          slug: slug,
          id: topicId,
          summary: true,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
      if (!isCurrent) return true;
      final payload = _withoutRemoved(response, stamp.removals);
      if (_publishPosts(topicId, payload.posts, stamp)) {
        state.summary = List.unmodifiable(
          _withoutRemoved(response, stamp.removals).detail.stream,
        );
      }
      return true;
    } catch (error) {
      return false;
    } finally {
      if (isCurrent && identical(state.summaryRead, reading)) {
        state.summaryRead = null;
        _changed();
      }
    }
  }

  Future<Post?> ensurePost(
    int topicId,
    int postId, {
    required bool Function() isInterested,
  }) async {
    if (!isCurrent || !isInterested()) return null;
    final stamp = _stamp(topicId);
    final credential = await _requests.keyCredentials(_owner.credentials);
    if (!isCurrent || !isInterested()) return null;
    final fetched = await credential.run(
      () => _owner.content.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: [postId],
        apiKey: credential.apiKey,
      ),
    );
    if (!isCurrent || !isInterested()) return null;
    final post = fetched.where((post) => post.id == postId).firstOrNull;
    if (post == null) return null;
    return _publishPosts(topicId, [post], stamp)
        ? _store.read<Post>(siteUrl, postId)
        : null;
  }

  void Function()? beginPostWrite(int postId) {
    if (!isCurrent || postWriting(postId) || _unresolvedPost(postId)) {
      return null;
    }
    final release = holdPostWrite(postId);
    _changed();
    return release;
  }

  @override
  void Function() holdPostWrite(int postId, {bool notifyOnRelease = true}) {
    if (!isCurrent) return () {};
    final state = _post(postId);
    final holder = Object();
    state.holders.add(holder);
    if (state.refreshOwner != null) {
      state.refreshOwner = null;
      state.refreshPending = true;
    }
    var released = false;
    return () {
      if (released) return;
      released = true;
      state.holders.remove(holder);
      if (!isCurrent) return;
      if (notifyOnRelease) _changed();
      if (!isCurrent || state.holders.isNotEmpty || !state.refreshPending) {
        return;
      }
      state.refreshPending = false;
      final topicId = state.topicId;
      state.topicId = null;
      if (topicId != null) invalidatePosts(topicId, {postId});
    };
  }

  bool beginPluginWrite(int postId) {
    if (_pluginWrites.containsKey(postId)) return false;
    final release = beginPostWrite(postId);
    if (release == null) return false;
    _pluginWrites[postId] = release;
    return true;
  }

  void endPluginWrite(int postId) => _pluginWrites.remove(postId)?.call();

  bool _awaitsDeletion(int topicId) =>
      _posts.values.any((post) => post.deletion && post.topicId == topicId);

  void acceptTotals(int topicId, {int? likeCount, int? postsCount}) {
    if (!isCurrent) return;
    if (postsCount != null && _awaitsDeletion(topicId)) {
      _topic(topicId).deferredPostsCount = postsCount;
      postsCount = null;
    }
    _setTotals(topicId, likeCount: likeCount, postsCount: postsCount);
  }

  void _releaseTotals(int topicId) {
    final state = _topic(topicId);
    if (state.deferredPostsCount == null || _awaitsDeletion(topicId)) return;
    final count = state.deferredPostsCount;
    state.deferredPostsCount = null;
    _setTotals(topicId, postsCount: count);
  }

  void _setTotals(int topicId, {int? likeCount, int? postsCount}) {
    if (!isCurrent || (likeCount == null && postsCount == null)) return;
    bool holds(int held, int? next) => next == null || held == next;
    var changed = false;
    _update<TopicDetail>(topicId, (detail) {
      if (holds(detail.likeCount, likeCount) &&
          holds(detail.postsCount, postsCount)) {
        return detail;
      }
      changed = true;
      return detail.copyWith(likeCount: likeCount, postsCount: postsCount);
    });
    _update<Topic>(
      topicId,
      (row) =>
          holds(row.likeCount, likeCount) && holds(row.postsCount, postsCount)
          ? row
          : row.copyWith(likeCount: likeCount, postsCount: postsCount),
    );
    if (changed && isCurrent) _owner.liveChanged(siteUrl);
  }

  void invalidatePosts(int topicId, Set<int> postIds, {bool deletion = false}) {
    if (!isCurrent) return;
    final topic = _topic(topicId);
    final eligible = <int>[];
    for (final id in postIds) {
      final post = _post(id);
      if (_store.read<Post>(siteUrl, id) == null) {
        post.deletion = false;
        continue;
      }
      if (deletion) post.deletion = true;
      if (post.holders.isNotEmpty) {
        post.refreshPending = true;
        post.topicId = topicId;
      } else {
        eligible.add(id);
      }
    }
    _releaseTotals(topicId);
    for (final id in eligible) {
      final post = _post(id);
      if (post.refreshOwner == null) {
        var batch = topic.queuedLive;
        if (batch == null) {
          batch = _LiveBatch(topicId);
          topic.queuedLive = batch;
          final queued = batch;
          scheduleMicrotask(() => _sendLive(queued));
        }
        batch.postIds.add(id);
        post.refreshOwner = batch;
        post.topicId = topicId;
      } else if (!identical(post.refreshOwner, topic.queuedLive)) {
        post.refreshPending = true;
      }
    }
  }

  void _sendLive(_LiveBatch batch) {
    if (!isCurrent) return;
    final topic = _topic(batch.topicId);
    if (!identical(topic.queuedLive, batch)) return;
    topic.queuedLive = null;
    final owned = [
      for (final id in batch.postIds)
        if (identical(_post(id).refreshOwner, batch)) id,
    ];
    const page = TopicDetail.maximumInitialPosts;
    for (var start = 0; start < owned.length; start += page) {
      unawaited(
        _readLive(
          batch,
          owned.sublist(start, math.min(start + page, owned.length)),
        ),
      );
    }
  }

  Future<void> _readLive(_LiveBatch batch, List<int> wanted) async {
    bool owns(int id) => identical(_post(id).refreshOwner, batch);
    bool current(int id) =>
        owns(id) && !_post(id).refreshPending && _post(id).holders.isEmpty;
    try {
      final credential = await _requests.keyCredentials(_owner.credentials);
      if (!isCurrent) return;
      final posts = await credential.run(
        () => _owner.content.posts(
          siteUrl: siteUrl,
          topicId: batch.topicId,
          ids: wanted,
          apiKey: credential.apiKey,
        ),
      );
      if (!isCurrent) return;
      final answered = {for (final post in posts) post.id};
      var changed = false;
      for (final post in posts) {
        if (!isCurrent) return;
        if (wanted.contains(post.id) && current(post.id)) {
          _put(post);
          changed = true;
        }
      }
      for (final id in wanted) {
        if (!isCurrent) return;
        if (!answered.contains(id) && current(id) && _post(id).deletion) {
          removePost(batch.topicId, id);
          changed = true;
        }
      }
      if (changed) _changed();
    } catch (error) {
    } finally {
      if (isCurrent) {
        final retry = <int>{};
        for (final id in wanted) {
          final post = _post(id);
          if (!owns(id)) continue;
          post.refreshOwner = null;
          if (post.refreshPending) {
            post.refreshPending = false;
            retry.add(id);
          } else {
            post.topicId = null;
            post.deletion = false;
          }
        }
        _releaseTotals(batch.topicId);
        if (isCurrent && retry.isNotEmpty) {
          invalidatePosts(batch.topicId, retry);
        }
      }
    }
  }

  bool _ownsLease(SiteLease original) =>
      isCurrent &&
      original.isCurrent &&
      identical(original.session, lease.session);

  bool _unresolvedPost(int postId) => _moderationRecoveries.any(
    (recovery) =>
        recovery.postIds.contains(postId) ||
        (recovery.wholeTopic &&
            (_store
                    .read<TopicDetail>(siteUrl, recovery.topicId)
                    ?.stream
                    .contains(postId) ??
                false)),
  );

  PostMutationRecovery? moderationRecoveryFor(
    int topicId,
    Iterable<int> postIds, {
    bool wholeTopic = false,
  }) {
    if (!isCurrent) return null;
    for (final recovery in _moderationRecoveries) {
      if (recovery.topicId == topicId &&
          (wholeTopic ||
              recovery.wholeTopic ||
              postIds.any(recovery.postIds.contains))) {
        return recovery;
      }
    }
    return null;
  }

  PostMutationRecovery postMutationRecovery(
    int topicId,
    List<int> postIds,
    String? apiKey, {
    bool wholeTopic = false,
  }) => _ModerationRecovery(
    this,
    topicId,
    List.unmodifiable(postIds),
    apiKey,
    wholeTopic,
  );

  Future<PostMutationUncertain> reconcileUncertainMutation(
    int topicId,
    List<int> postIds,
    String? apiKey, {
    bool wholeTopic = false,
    bool alreadyHeld = true,
  }) async {
    final recovery = _ModerationRecovery(
      this,
      topicId,
      List.unmodifiable(postIds),
      apiKey,
      wholeTopic,
    );
    if (isCurrent) {
      _moderationRecoveries.add(recovery);
      _changed();
    }
    final projection = alreadyHeld
        ? await _readModerationRecovery(recovery)
        : await recovery.refresh();
    return PostMutationUncertain(projection, recovery);
  }

  Future<void> _recoverPendingModeration(int topicId) async {
    for (final recovery
        in _moderationRecoveries.where((r) => r.topicId == topicId).toList()) {
      if (!isCurrent) return;
      await recovery.refresh();
    }
  }

  Future<PostProjectionFreshness> _recoverModeration(
    _ModerationRecovery recovery,
  ) async {
    if (!isCurrent) return PostProjectionFreshness.retired;
    final ids = <int>{
      ...recovery.postIds,
      if (recovery.wholeTopic)
        ...?_store.read<TopicDetail>(siteUrl, recovery.topicId)?.stream,
    };
    if (ids.any(postWriting)) return PostProjectionFreshness.stale;
    final releases = [
      for (final id in ids) holdPostWrite(id, notifyOnRelease: false),
    ];
    _changed();
    try {
      return await _readModerationRecovery(recovery, heldPostIds: ids);
    } finally {
      for (final release in releases) {
        release();
      }
      _changed();
    }
  }

  Future<PostProjectionFreshness> _readModerationRecovery(
    _ModerationRecovery recovery, {
    Set<int>? heldPostIds,
  }) async {
    if (!isCurrent) return PostProjectionFreshness.retired;
    TopicPayload? payload;
    final stamp = _stamp(recovery.topicId);
    final additionalReleases = <void Function()>[];
    try {
      if (recovery.wholeTopic) {
        try {
          final credential = await _requests.keyCredentials(
            _CapturedKey(recovery.apiKey),
          );
          payload = await credential.run(
            () => _owner.content.topic(
              siteUrl: siteUrl,
              slug: '',
              id: recovery.topicId,
              apiKey: credential.apiKey,
            ),
          );
          if (!isCurrent) return PostProjectionFreshness.retired;
        } catch (error) {
          return isCurrent
              ? PostProjectionFreshness.stale
              : PostProjectionFreshness.retired;
        }
      }
      final ids = <int>{
        ...recovery.postIds,
        if (recovery.wholeTopic)
          ...?_store.read<TopicDetail>(siteUrl, recovery.topicId)?.stream,
        if (payload != null) ...payload.detail.stream,
      };
      final held = heldPostIds ?? recovery.postIds.toSet();
      final additional = ids.difference(held);
      if (additional.any(postWriting)) return PostProjectionFreshness.stale;
      for (final id in additional) {
        additionalReleases.add(holdPostWrite(id, notifyOnRelease: false));
      }
      final projection = await _repair(
        recovery.topicId,
        ids.toList(),
        recovery.apiKey,
        lease,
      );
      if (projection != PostProjectionFreshness.fresh) return projection;
      if (payload != null &&
          _publishTopic((detail: payload.detail, posts: const []), stamp) ==
              null) {
        return PostProjectionFreshness.retired;
      }
      _moderationRecoveries.remove(recovery);
      _changed();
      return isCurrent
          ? PostProjectionFreshness.fresh
          : PostProjectionFreshness.retired;
    } finally {
      for (final release in additionalReleases) {
        release();
      }
    }
  }

  Future<PostProjectionFreshness> repairPost(
    int topicId,
    int postId,
    String? apiKey,
    SiteLease original,
  ) => _repair(topicId, [postId], apiKey, original);

  Future<PostProjectionFreshness> repairSelectedPosts(
    int topicId,
    List<int> postIds,
    String? apiKey,
    SiteLease original,
  ) => _repair(topicId, postIds, apiKey, original);

  Future<PostProjectionFreshness> _repair(
    int topicId,
    List<int> postIds,
    String? apiKey,
    SiteLease original,
  ) async {
    if (!_ownsLease(original)) return PostProjectionFreshness.retired;
    final removals = _topic(topicId).removals;
    final fresh = <int, Post>{};
    try {
      final credential = await _requests.keyCredentials(_CapturedKey(apiKey));
      for (
        var start = 0;
        start < postIds.length;
        start += TopicDetail.maximumInitialPosts
      ) {
        if (!_ownsLease(original)) return PostProjectionFreshness.retired;
        final end = math.min(
          start + TopicDetail.maximumInitialPosts,
          postIds.length,
        );
        final posts = await credential.run(
          () => _owner.content.posts(
            siteUrl: siteUrl,
            topicId: topicId,
            ids: postIds.sublist(start, end),
            apiKey: credential.apiKey,
          ),
        );
        if (!_ownsLease(original)) return PostProjectionFreshness.retired;
        for (final post in posts) {
          if (postIds.contains(post.id)) fresh[post.id] = post;
        }
      }
    } catch (error) {
      if (isCurrent) _topic(topicId).stale = true;

      return isCurrent
          ? PostProjectionFreshness.stale
          : PostProjectionFreshness.retired;
    }
    for (final id in postIds) {
      if (!_ownsLease(original)) return PostProjectionFreshness.retired;
      if (_removedAfter(topicId, id, removals)) continue;
      final post = fresh[id];
      if (post == null) {
        removePost(topicId, id);
      } else {
        _put(post);
        if (!_removedAfter(topicId, id, removals)) {
          _update<TopicDetail>(topicId, (detail) => detail.withPostId(id));
        }
      }
    }
    _changed();
    return isCurrent
        ? PostProjectionFreshness.fresh
        : PostProjectionFreshness.retired;
  }

  void acceptEditedPost(Post updated, {required String raw}) {
    if (!isCurrent) return;
    final held = _store.read<Post>(siteUrl, updated.id);
    final withRaw = updated.raw == null ? updated.withRaw(raw) : updated;
    _put(
      _bookmarks.preservePost(
        held == null
            ? withRaw
            : withRaw
                  .copyWith(isLocalized: held.isLocalized)
                  .withLikesOf(held)
                  .withPostActionsOf(held)
                  .withPlugins(
                    _owner.models.mergeAfterPostEdit(
                      held: held.plugins,
                      incoming: updated.plugins,
                    ),
                  ),
      ),
    );
  }

  void acceptPostAction(Post post) {
    if (!isCurrent) return;
    _put(_bookmarks.preservePost(post));
  }

  void guessLike(int postId, bool liked) {
    _update<Post>(postId, (post) => post.withLike(liked));
  }

  void rejectLike(int postId, {required bool guessed, required bool original}) {
    _update<Post>(
      postId,
      (held) => held.liked == guessed ? held.withLike(original) : held,
    );
  }

  bool publishChecklist(Post previous, Post next) {
    if (!isCurrent) return false;
    final current = _store.read<Post>(siteUrl, previous.id);
    if (current == null ||
        current.cooked != previous.cooked ||
        current.version != previous.version ||
        current.updatedAt != previous.updatedAt ||
        current.canEdit != previous.canEdit ||
        current.isLocalized != previous.isLocalized ||
        current.isDeleted != previous.isDeleted) {
      return false;
    }
    _put(
      current.copyWith(
        cooked: next.cooked,
        raw: next.raw,
        updatedAt: next.updatedAt,
        version: next.version,
        canEdit: next.canEdit,
        isLocalized: next.isLocalized,
      ),
    );
    _changed();
    return isCurrent;
  }

  Future<Post?> checklistPost(int topicId, int postId, String? apiKey) async {
    if (!isCurrent) return null;
    final credential = await _requests.keyCredentials(_CapturedKey(apiKey));
    final posts = await credential.run(
      () => _owner.content.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: [postId],
        includeRaw: true,
        apiKey: credential.apiKey,
      ),
    );
    return isCurrent
        ? posts.where((post) => post.id == postId).firstOrNull
        : null;
  }

  @override
  Future<BookmarkTopicSnapshot?> readBookmarkMetadata(
    int topicId,
    String slug,
  ) async {
    if (!isCurrent) return null;
    final credential = await _requests.credentials(_owner.credentials);
    if (!isCurrent) return null;
    final payload = await credential.run(
      () => _owner.content.topic(
        siteUrl: siteUrl,
        slug: slug,
        id: topicId,
        apiKey: credential.apiKey,
        clientId: credential.clientId,
      ),
    );
    if (!isCurrent) return null;
    return BookmarkTopicSnapshot(
      bookmarks: payload.detail.bookmarks,
      posts: {for (final post in payload.posts) post.id: post.bookmark},
    );
  }

  void acceptArchive(int topicId, bool archived) {
    if (!isCurrent) return;
    _topic(topicId).archive++;
    _update<TopicDetail>(
      topicId,
      (held) => held.copyWith(messageArchived: archived),
    );
  }

  void acceptReply(int topicId, Post post) {
    if (!isCurrent) return;
    final removals = _topic(topicId).removals;
    _put(post);
    if (!_removedAfter(topicId, post.id, removals)) {
      _update<TopicDetail>(topicId, (held) => held.withPostId(post.id));
    }
  }

  void acceptNewTopicPost(Post post) => _put(post);

  void removeTopicPermanently(int topicId) {
    if (!isCurrent) return;
    final detail = _store.read<TopicDetail>(siteUrl, topicId);
    for (final id in detail?.stream ?? const <int>[]) {
      if (!isCurrent) return;
      removePost(topicId, id);
    }
    if (!isCurrent) return;
    _store.remove<TopicDetail>(siteUrl, topicId);
    if (isCurrent) _store.remove<Topic>(siteUrl, topicId);
  }

  static const _reconcileWindow = 5;
  static final _unicodeSpace = RegExp(
    '[\u00A0\u1680\u180E\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]',
  );
  static String _storedRaw(String raw) =>
      raw.replaceAll(_unicodeSpace, ' ').trim();
  static String _titleKey(String title) => title
      .replaceAll(_unicodeSpace, ' ')
      .replaceAll('\u200B', '')
      .toLowerCase()
      .replaceAll(RegExp(r'!+'), '!')
      .replaceAll(RegExp(r'\?+'), '?')
      .replaceAll(RegExp(r'[\s.!?]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<Post?> findReply({
    required int topicId,
    required String slug,
    required String? username,
    required String raw,
    required AccountRequestCredentials credential,
  }) async {
    if (!isCurrent) return null;
    final state = _topic(topicId);
    final stamp = _stamp(topicId);
    state.matchingReads++;
    try {
      final payload = await credential.run(
        () => _owner.content.topic(
          siteUrl: siteUrl,
          slug: slug,
          id: topicId,
          apiKey: credential.apiKey,
        ),
      );
      if (!isCurrent) return null;
      final stream = payload.detail.stream;
      final tail = stream.length <= _reconcileWindow
          ? stream
          : stream.sublist(stream.length - _reconcileWindow);
      final posts = await credential.run(
        () => _owner.content.posts(
          siteUrl: siteUrl,
          topicId: topicId,
          ids: tail,
          includeRaw: true,
          apiKey: credential.apiKey,
        ),
      );
      if (!isCurrent) return null;
      final rawKey = _storedRaw(raw);
      final landed = posts
          .where(
            (post) =>
                post.username == username &&
                post.raw != null &&
                _storedRaw(post.raw!) == rawKey,
          )
          .firstOrNull;
      if (_publishTopic(payload, stamp) == null) return null;
      if (!_publishPosts(topicId, posts, stamp)) return null;
      if (landed != null &&
          !_removedSince(topicId, stamp.removals).contains(landed.id)) {
        _update<TopicDetail>(topicId, (held) => held.withPostId(landed.id));
      }
      return isCurrent ? landed : null;
    } finally {
      state.matchingReads--;
    }
  }

  Future<({int topicId, String slug, String title})?> findCreatedTopic({
    required String username,
    required String title,
    required String raw,
    required bool privateMessage,
    required AccountRequestCredentials credential,
  }) async {
    if (!isCurrent) return null;
    final encoded = Uri.encodeComponent(username);
    final path = privateMessage
        ? '/topics/private-messages-sent/$encoded.json'
        : '/topics/created-by/$encoded.json';
    final candidates =
        <({TopicPayload payload, _ReadStamp stamp, String slug})>[];
    final heldStates = <_TopicState>[];
    try {
      final recent = await credential.run(
        () => _owner.feeds.topicList(
          siteUrl: siteUrl,
          path: path,
          apiKey: credential.apiKey,
        ),
      );
      if (!isCurrent) return null;
      final titleKey = _titleKey(title);
      final rawKey = _storedRaw(raw);
      for (final row
          in recent.topics
              .where((row) => _titleKey(row.title) == titleKey)
              .take(_reconcileWindow)) {
        if (!isCurrent) return null;
        final state = _topic(row.id);
        state.matchingReads++;
        heldStates.add(state);
        final stamp = _stamp(row.id);
        final payload = await credential.run(
          () => _owner.content.topic(
            siteUrl: siteUrl,
            slug: row.slug,
            id: row.id,
            apiKey: credential.apiKey,
          ),
        );
        if (!isCurrent) return null;
        final first = payload.detail.stream.firstOrNull;
        if (first == null) continue;
        final posts = await credential.run(
          () => _owner.content.posts(
            siteUrl: siteUrl,
            topicId: row.id,
            ids: [first],
            includeRaw: true,
            apiKey: credential.apiKey,
          ),
        );
        if (!isCurrent) return null;
        if (posts.firstOrNull?.raw case final posted?
            when _storedRaw(posted) == rawKey) {
          candidates.add((payload: payload, stamp: stamp, slug: row.slug));
        }
      }
      if (!isCurrent || candidates.length != 1) return null;
      final candidate = candidates.single;
      final detail = _publishTopic(candidate.payload, candidate.stamp);
      return detail == null
          ? null
          : (topicId: detail.id, slug: candidate.slug, title: detail.title);
    } finally {
      for (final state in heldStates) {
        state.matchingReads--;
      }
    }
  }
}

final class _ModerationRecovery implements PostMutationRecovery {
  _ModerationRecovery(
    this.session,
    this.topicId,
    this.postIds,
    this.apiKey,
    this.wholeTopic,
  );

  final TopicDataSession session;
  final int topicId;
  final List<int> postIds;
  final String? apiKey;
  final bool wholeTopic;
  Future<PostProjectionFreshness>? _pending;

  @override
  bool get isCurrent => session.isCurrent;

  @override
  Future<PostProjectionFreshness> refresh() =>
      _pending ??= Future<PostProjectionFreshness>(
        () => session._recoverModeration(this),
      ).whenComplete(() => _pending = null);
}
