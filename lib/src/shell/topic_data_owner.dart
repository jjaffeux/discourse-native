import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../data/topic_content_api.dart';
import '../data/topic_feeds_api.dart';
import '../data/topic_tracking_reconciler.dart';
import '../models/discourse_model_codec.dart';
import '../models/post.dart';
import '../models/post_mutation_outcome.dart';
import '../models/storable.dart';
import '../models/topic.dart';
import '../models/topic_link.dart';
import '../plugin_api/topic_reader.dart';
import 'bookmark_transactions.dart';
import 'checklist_topic_data.dart';
import 'topic_prefetch_controller.dart';

typedef TopicDataPosition = ({String slug, int postNumber});

final class TopicOpening {
  const TopicOpening({
    required this.received,
    required this.resume,
    required this.canResume,
    this.sessionRead,
  });

  final void Function(TopicDetail detail) received;
  final TopicDataPosition? Function(int postNumber) resume;
  final bool Function() canResume;

  /// The farthest post of the topic this session has read, if any.
  final int? Function()? sessionRead;

  int? _resumeFor(TopicDetail detail) =>
      detail.resumePostNumberAfter(sessionRead?.call());
}

final class ReplySendBoundary {
  const ReplySendBoundary._(this._session, this._topicId, this._maxPostId);

  final TopicDataSession _session;
  final int _topicId;
  final int _maxPostId;
}

sealed class ReplyLookupResult {
  const ReplyLookupResult();
}

final class ReplyFound extends ReplyLookupResult {
  const ReplyFound(this.post);

  final Post post;
}

final class ReplyIndeterminate extends ReplyLookupResult {
  const ReplyIndeterminate();
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
    this.lastPostResolved,
    required this.prepareCategories,

    required this.loadTimeout,
    required this.bookmarkReads,
    this.notificationReads,
    this.usesReader,
    this.postSelected,
    this.acceptedPost,
    this.ignoredUsernames,
    this.currentUserId,
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
  final void Function(String siteUrl, int topicId, int postNumber)?
  lastPostResolved;
  final Future<void> Function(String siteUrl, Iterable<int> ids)
  prepareCategories;

  final Duration loadTimeout;
  final BookmarkReadProjection Function(String, SiteLease) bookmarkReads;
  final TopicNotificationRead? Function(String, SiteLease, int)?
  notificationReads;
  final bool Function(String siteUrl, TopicDetail topic)? usesReader;
  final bool Function(String siteUrl, int topicId, int postId)? postSelected;
  final void Function(String siteUrl, int topicId, Post post)? acceptedPost;
  final Set<String> Function(String siteUrl)? ignoredUsernames;
  final int? Function(String siteUrl)? currentUserId;
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
  final Set<int> readerPosts = {};
  Object? readerFailure;
  Object? reading;
  Completer<void>? readSettled;
  int acceptedReads = 0;
  bool refreshPending = false;
  int? refreshPostNumber;
  bool stale = false;
  Object? newerPage;
  Object? earlierPage;
  Object? summaryRead;
  List<int>? summary;
  final Map<(int, bool), Object> gaps = {};
  final Map<TopicStatusProperty, int> statuses = {};
  final Map<_MetadataField, int> metadata = {};
  int deletion = 0;
  int pin = 0;
  bool pinPending = false;
  int archive = 0;
  int removals = 0;
  int streams = 0;
  int likes = 0;
  final Map<int, int> likedAt = {};
  int positions = 0;
  int matchingReads = 0;
  final Map<int, int> removedAt = {};
  _LiveBatch? queuedLive;
  int? deferredPostsCount;
  final Set<int> createdPosts = {};
  bool readingCreated = false;
}

enum _MetadataField { title, category, tags }

final class _PostState {
  final Set<Object> holders = {};
  Object? refreshOwner;
  bool refreshPending = false;
  int? topicId;
  bool deletion = false;
  PostLikeWrite? likeWrite;
}

/// One optimistic like, admitted against the latest post in this account.
final class PostLikeWrite {
  PostLikeWrite._(this._session, this._state, this._original, this._guess);

  final TopicDataSession _session;
  final _PostState _state;
  final Post _original;
  final Post _guess;

  bool get liked => _guess.liked;
  bool get isCurrent => _session.isCurrent && identical(_state.likeWrite, this);

  bool accept(Post post) {
    if (!isCurrent) return false;
    _session.acceptPostAction(post);
    return isCurrent;
  }

  bool reject() {
    if (!isCurrent) return false;
    _session._update<Post>(_original.id, (held) {
      // Unrelated edits retain the guess; a newer like projection owns itself.
      return _likes(held) == _likes(_guess)
          ? held.withLikesOf(_original)
          : held;
    });
    return isCurrent;
  }

  void finish() {
    if (identical(_state.likeWrite, this)) _state.likeWrite = null;
  }

  static (bool, int, bool, bool) _likes(Post post) =>
      (post.liked, post.likeCount, post.canLike, post.canUnlike);
}

typedef _ReadStamp = ({
  TopicNotificationRead? notification,
  int bookmarks,
  int actions,
  int archive,
  int removals,
  int streams,
  int likes,
  Map<int, Post> redacted,
});

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

final class TopicDataSession implements BookmarkTopicData, ChecklistTopicData {
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
  int _actionEpoch = 0;

  int get actionEpoch => _actionEpoch;

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

  bool readerResolved(int topicId) =>
      isCurrent &&
      (_owner.usesReader == null || _topic(topicId).acceptedReads > 0);

  Object? readerFailure(int topicId) =>
      isCurrent ? _topic(topicId).readerFailure : null;

  bool usesReader(int topicId) {
    final detail = _store.read<TopicDetail>(siteUrl, topicId);
    return readerResolved(topicId) &&
        detail != null &&
        _owner.usesReader?.call(siteUrl, detail) == true;
  }

  bool containsPost(int topicId, int postId) =>
      isCurrent &&
      (_topic(topicId).readerPosts.contains(postId) ||
          _store.read<TopicDetail>(siteUrl, topicId)?.stream.contains(postId) ==
              true);

  Set<int> readerPostIds(int topicId) =>
      isCurrent ? Set.unmodifiable(_topic(topicId).readerPosts) : const {};

  Future<AcceptedTopicContent<T>?> ingestReaderContent<T>(
    int topicId,
    Future<TopicContentResult<T>> Function() read, {
    required bool Function() sourceCurrent,
  }) async {
    if (!isCurrent || !sourceCurrent() || !usesReader(topicId)) return null;
    final stamp = _stamp(topicId);
    final before = {
      for (final post in _store.readMatching<Post>(siteUrl, (_) => true))
        post.id: post,
    };
    final result = await read();
    if (!_readIsCurrent(stamp) || !sourceCurrent() || !usesReader(topicId)) {
      return null;
    }
    if (result.metadata != null && result.metadata!.id != topicId) {
      throw const FormatException('Topic metadata belongs to another reader.');
    }
    final accepted = <int>{};
    for (final item in result.posts) {
      if (!_readIsCurrent(stamp) || !sourceCurrent() || !usesReader(topicId)) {
        return null;
      }
      final post = item.post;
      if (post.id <= 0 || post.postNumber <= 0) {
        throw const FormatException('Invalid canonical post identity.');
      }
      if (_removedAfter(topicId, post.id, stamp.removals)) continue;
      final held = _store.read<Post>(siteUrl, post.id);
      if (item.disposition != TopicContentDisposition.redacted &&
          (postWriting(post.id) || !identical(held, before[post.id]))) {
        if (held != null) {
          accepted.add(post.id);
          _topic(topicId).readerPosts.add(post.id);
        }
        continue;
      }
      final incoming = item.disposition == TopicContentDisposition.redacted
          ? post.redactedContent()
          : _bookmarks.postFromRead(topicId, stamp.bookmarks, post);
      if (held?.contentRedacted == true && !incoming.contentRedacted) {
        _update<Post>(post.id, (_) => incoming);
      } else {
        _put(incoming);
      }
      if (!_readIsCurrent(stamp) || !sourceCurrent() || !usesReader(topicId)) {
        return null;
      }
      if (_store.containsRecord<Post>(siteUrl, post.id)) {
        accepted.add(post.id);
        _topic(topicId).readerPosts.add(post.id);
      }
    }
    final held = _store.read<TopicDetail>(siteUrl, topicId);
    if (result.metadata case final metadata? when held != null) {
      var incoming =
          _actionsFromRead(
            stamp.actions,
            _bookmarks.detailFromRead(stamp.bookmarks, metadata),
          ).copyWith(
            stream: held.stream,
            gapsBefore: held.gapsBefore,
            gapsAfter: held.gapsAfter,
            messageArchived: stamp.archive == _topic(topicId).archive
                ? metadata.messageArchived
                : held.messageArchived,
          );
      if (stamp.notification case final notification?) {
        final level = notification.reconcile(incoming.notificationLevel);
        if (level == null) return null;
        incoming = incoming.copyWith(notificationLevel: level);
      }
      _put(incoming);
      if (!_readIsCurrent(stamp) || !sourceCurrent()) return null;
      _update<Topic>(topicId, (row) {
        final accepted = _store.read<TopicDetail>(siteUrl, topicId) ?? incoming;
        return actionRowFromRead(
          stamp.actions,
          row
              .copyWith(
                title: accepted.title,
                postsCount: accepted.postsCount,
                closed: accepted.closed,
                archived: accepted.archived,
                visible: accepted.visible,
                deletedAt: accepted.deletedAt,
                clearDeletedAt: accepted.deletedAt == null,
                muted:
                    accepted.notificationLevel == TopicNotificationLevel.muted,
              )
              .withPlugins(accepted.plugins),
        );
      });
    }
    if (!_readIsCurrent(stamp) || !sourceCurrent()) return null;
    _changed();
    if (!sourceCurrent() || !usesReader(topicId)) return null;
    return AcceptedTopicContent(
      value: result.value,
      postIds: accepted,
      revision: ++_readerRevision,
    );
  }

  int _readerRevision = 0;
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
    for (final state in _topics.values) {
      state.readSettled?.complete();
    }
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
    final stream = _store.read<TopicDetail>(siteUrl, topicId)?.stream;
    return (
      notification: _owner.notificationReads?.call(siteUrl, lease, topicId),
      bookmarks: _bookmarks.revision(topicId),
      actions: actionEpoch,
      archive: state.archive,
      removals: state.removals,
      streams: state.streams,
      likes: state.likes,
      redacted: {
        for (final post in _store.retainedRecords<Post>(siteUrl))
          if (post != null &&
              post.contentRedacted &&
              (state.readerPosts.contains(post.id) ||
                  stream?.contains(post.id) == true))
            post.id: post,
      },
    );
  }

  void projectAcceptedStatus(
    int topicId,
    TopicStatusProperty status,
    bool enabled,
  ) {
    if (!isCurrent) return;
    _topic(topicId).statuses[status] = ++_actionEpoch;
    _update<TopicDetail>(
      topicId,
      (detail) => detail.withStatus(status, enabled),
    );
    _update<Topic>(topicId, (row) {
      final accepted = _store.read<TopicDetail>(siteUrl, topicId);
      return row.copyWith(
        closed: status == TopicStatusProperty.closed
            ? accepted?.closed ?? enabled
            : null,
        archived: status == TopicStatusProperty.archived
            ? accepted?.archived ?? enabled
            : null,
        visible: status == TopicStatusProperty.visible
            ? accepted?.visible ?? enabled
            : null,
      );
    });
  }

  void projectAcceptedMetadata(
    int topicId, {
    String? title,
    String? localizedTitle,
    int? categoryId,
    bool clearCategory = false,
    List<TopicTag>? tags,
  }) {
    if (!isCurrent) return;
    final fields = _topic(topicId).metadata;
    if (title != null) fields[_MetadataField.title] = ++_actionEpoch;
    if (categoryId != null || clearCategory) {
      fields[_MetadataField.category] = ++_actionEpoch;
    }
    if (tags != null) fields[_MetadataField.tags] = ++_actionEpoch;
    _update<TopicDetail>(
      topicId,
      (detail) => detail.copyWith(
        title: title,
        localizedTitle: localizedTitle,
        clearLocalizedTitle:
            localizedTitle == null && title != null && title != detail.title,
        categoryId: categoryId,
        clearCategory: clearCategory,
        tags: tags,
      ),
    );
    _update<Topic>(topicId, (row) {
      final accepted = _store.read<TopicDetail>(siteUrl, topicId);
      final projectsCategory = categoryId != null || clearCategory;
      final projectedTitle = title == null ? null : accepted?.title ?? title;
      final category = accepted == null ? categoryId : accepted.categoryId;
      return row.copyWith(
        title: projectedTitle,
        localizedTitle: localizedTitle,
        clearLocalizedTitle:
            localizedTitle == null &&
            projectedTitle != null &&
            projectedTitle != row.title,
        categoryId: projectsCategory ? category : null,
        clearCategory: projectsCategory && category == null,
        tags: tags == null ? null : accepted?.tags ?? tags,
      );
    });
  }

  bool projectAcceptedDeletion(int topicId, bool deleted, DateTime at) {
    if (!isCurrent) return false;
    final held = _store.read<TopicDetail>(siteUrl, topicId);
    if (held == null) return false;
    final next = deleted ? held.afterDeletion(at) : held.afterRecovery();
    if (identical(next, held)) return false;
    if (next.closed != held.closed) {
      _topic(topicId).statuses[TopicStatusProperty.closed] = ++_actionEpoch;
    }
    _topic(topicId).deletion = ++_actionEpoch;
    _update<TopicDetail>(topicId, (_) => next);
    _update<Topic>(topicId, (row) {
      final accepted = _store.read<TopicDetail>(siteUrl, topicId) ?? next;
      return row.copyWith(
        closed: accepted.closed,
        deletedAt: accepted.deletedAt,
        clearDeletedAt: accepted.deletedAt == null,
      );
    });
    return isCurrent;
  }

  void projectPinPreference(int topicId, bool pinned) {
    if (!isCurrent) return;
    final state = _topic(topicId);
    state.pin = ++_actionEpoch;
    state.pinPending = true;
    _update<TopicDetail>(
      topicId,
      (detail) => detail.copyWith(pinned: pinned, unpinned: !pinned),
    );
    _update<Topic>(
      topicId,
      (row) => row.copyWith(
        pinned: _store.read<TopicDetail>(siteUrl, topicId)?.pinned ?? pinned,
      ),
    );
  }

  void settlePinPreference(
    int topicId, {
    TopicDetail? rollback,
    Topic? rollbackRow,
  }) {
    if (!isCurrent) return;
    final state = _topic(topicId);
    state.pin = ++_actionEpoch;
    state.pinPending = false;
    if (rollback == null) return;
    _update<TopicDetail>(
      topicId,
      (detail) =>
          detail.pinned == !rollback.pinned &&
              detail.unpinned == rollback.pinned
          ? detail.copyWith(
              pinned: rollback.pinned,
              unpinned: rollback.unpinned,
            )
          : detail,
    );
    if (rollbackRow != null) {
      _update<Topic>(
        topicId,
        (row) => row.pinned == !rollback.pinned
            ? row.copyWith(pinned: rollbackRow.pinned)
            : row,
      );
    }
  }

  TopicDetail _actionsFromRead(int atDispatch, TopicDetail incoming) {
    final held = _store.read<TopicDetail>(siteUrl, incoming.id);
    final row = _store.read<Topic>(siteUrl, incoming.id);
    if (held == null && row == null) return incoming;
    final state = _topic(incoming.id);
    if ((state.metadata[_MetadataField.title] ?? 0) > atDispatch) {
      final localizedTitle = held == null
          ? row?.localizedTitle
          : held.localizedTitle;
      incoming = incoming.copyWith(
        title: held?.title ?? row?.title,
        localizedTitle: localizedTitle,
        clearLocalizedTitle: localizedTitle == null,
      );
    }
    if ((state.metadata[_MetadataField.category] ?? 0) > atDispatch) {
      final categoryId = held == null ? row?.categoryId : held.categoryId;
      incoming = incoming.copyWith(
        categoryId: categoryId,
        clearCategory: categoryId == null,
      );
    }
    if ((state.metadata[_MetadataField.tags] ?? 0) > atDispatch) {
      incoming = incoming.copyWith(tags: held?.tags ?? row?.tags);
    }
    if (held == null) return incoming;
    for (final entry in state.statuses.entries) {
      if (entry.value > atDispatch) {
        incoming = incoming.withStatus(entry.key, held.statusValue(entry.key));
      }
    }
    if (state.deletion > atDispatch) {
      incoming = incoming.copyWith(
        deletedAt: held.deletedAt,
        clearDeletedAt: held.deletedAt == null,
        canDeleteTopic: held.canDeleteTopic,
        canRecoverTopic: held.canRecoverTopic,
      );
    }
    if (incoming.hasPinPreference &&
        (state.pinPending || state.pin > atDispatch)) {
      incoming = incoming.copyWith(
        pinned: held.pinned,
        unpinned: held.unpinned,
      );
    }
    return incoming;
  }

  Topic actionRowFromRead(int atDispatch, Topic incoming) {
    if (!isCurrent) return incoming;
    final state = _topics[incoming.id];
    if (state == null) return incoming;
    final held = _store.read<TopicDetail>(siteUrl, incoming.id);
    final row = _store.read<Topic>(siteUrl, incoming.id);
    if ((state.metadata[_MetadataField.title] ?? 0) > atDispatch &&
        (row != null || held != null)) {
      final localizedTitle = row == null
          ? held?.localizedTitle
          : row.localizedTitle;
      incoming = incoming.copyWith(
        title: row?.title ?? held?.title,
        localizedTitle: localizedTitle,
        clearLocalizedTitle: localizedTitle == null,
      );
    }
    if ((state.metadata[_MetadataField.category] ?? 0) > atDispatch) {
      final categoryId = row == null ? held?.categoryId : row.categoryId;
      incoming = incoming.copyWith(
        categoryId: categoryId,
        clearCategory: categoryId == null,
      );
    }
    if ((state.metadata[_MetadataField.tags] ?? 0) > atDispatch) {
      incoming = incoming.copyWith(tags: row?.tags ?? held?.tags);
    }
    if ((state.statuses[TopicStatusProperty.closed] ?? 0) > atDispatch) {
      incoming = incoming.copyWith(closed: row?.closed ?? held?.closed);
    }
    if ((state.statuses[TopicStatusProperty.archived] ?? 0) > atDispatch) {
      incoming = incoming.copyWith(archived: row?.archived ?? held?.archived);
    }
    if ((state.statuses[TopicStatusProperty.visible] ?? 0) > atDispatch) {
      incoming = incoming.copyWith(visible: row?.visible ?? held?.visible);
    }
    if (state.deletion > atDispatch) {
      final deletedAt = row == null ? held?.deletedAt : row.deletedAt;
      incoming = incoming.copyWith(
        deletedAt: deletedAt,
        clearDeletedAt: deletedAt == null,
      );
    }
    if (state.pinPending || state.pin > atDispatch) {
      incoming = incoming.copyWith(pinned: row?.pinned ?? held?.pinned);
    }
    return incoming;
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
    state.readerPosts.remove(postId);
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

  bool _readIsCurrent(_ReadStamp stamp) =>
      isCurrent && stamp.notification?.isCurrent != false;

  bool _publishPosts(
    int topicId,
    Iterable<Post> incoming,
    _ReadStamp stamp, {
    bool onlyUnloaded = false,
    bool? restoreRedacted,
  }) {
    for (final post in incoming) {
      if (!_readIsCurrent(stamp)) return false;
      final state = _topic(topicId);
      if ((state.removedAt[post.id] ?? 0) > stamp.removals ||
          (onlyUnloaded && _store.containsRecord<Post>(siteUrl, post.id))) {
        continue;
      }
      final held = _store.read<Post>(siteUrl, post.id);
      var incoming = _bookmarks.postFromRead(topicId, stamp.bookmarks, post);
      if (held != null && (state.likedAt[post.id] ?? 0) > stamp.likes) {
        incoming = incoming.withLikesOf(held);
      }
      if ((restoreRedacted ?? !usesReader(topicId)) &&
          held?.contentRedacted == true &&
          identical(held, stamp.redacted[post.id]) &&
          !postWriting(post.id)) {
        _update<Post>(post.id, (_) => incoming);
      } else {
        _put(incoming);
      }
    }
    return _readIsCurrent(stamp);
  }

  TopicDetail? _publishTopic(
    TopicPayload response,
    _ReadStamp stamp, {
    bool positioned = false,
  }) {
    if (!_readIsCurrent(stamp)) return null;
    final payload = _withoutRemoved(response, stamp.removals);
    final topicId = payload.detail.id;
    final state = _topic(topicId);
    state.streams++;
    if (!_publishPosts(
      topicId,
      payload.posts,
      stamp,
      restoreRedacted: _owner.usesReader?.call(siteUrl, payload.detail) != true,
    )) {
      return null;
    }
    final held = _store.read<TopicDetail>(siteUrl, topicId);
    final latest = _withoutRemoved(response, stamp.removals);
    var incoming = _actionsFromRead(
      stamp.actions,
      _bookmarks.detailFromRead(stamp.bookmarks, latest.detail),
    );
    if (held != null && stamp.archive != state.archive) {
      incoming = incoming.copyWith(messageArchived: held.messageArchived);
    }
    final notification = stamp.notification;
    if (notification != null) {
      final level = notification.reconcile(incoming.notificationLevel);
      if (level == null) return null;
      incoming = incoming.copyWith(notificationLevel: level);
    }
    final stored = _put(incoming);
    if (!_readIsCurrent(stamp) || stored == null) return null;
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
    if (!_readIsCurrent(stamp)) return null;
    state.stale = false;
    state.acceptedReads++;
    _update<Topic>(topicId, (row) {
      final accepted = _store.read<TopicDetail>(siteUrl, topicId) ?? detail;
      final projected = actionRowFromRead(
        stamp.actions,
        _bookmarks.projectTopicRow(
          row
              .copyWith(
                title: accepted.title,
                localizedTitle: accepted.localizedTitle,
                clearLocalizedTitle: accepted.localizedTitle == null,
                categoryId: accepted.categoryId,
                clearCategory: accepted.categoryId == null,
                tags: accepted.tags,
                postsCount: accepted.postsCount,
                closed: accepted.closed,
                archived: accepted.archived,
                visible: accepted.visible,
                deletedAt: accepted.deletedAt,
                clearDeletedAt: accepted.deletedAt == null,
                muted:
                    accepted.notificationLevel == TopicNotificationLevel.muted,
                pinned: accepted.pinned,
              )
              .withPlugins(accepted.plugins),
        ),
      );
      return accepted.hasPinPreference
          ? projected
          : projected.copyWith(pinned: false);
    });
    if (!_readIsCurrent(stamp)) return null;
    detail = _store.read<TopicDetail>(siteUrl, topicId) ?? detail;
    _owner.published(siteUrl, detail);
    return _readIsCurrent(stamp)
        ? _store.read<TopicDetail>(siteUrl, topicId)
        : null;
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
            (postNumber == TopicLink.lastPostNumber &&
                _cachedLastPostNumber(held) != null) ||
            held.stream.any(
              (id) => _store.read<Post>(siteUrl, id)?.postNumber == postNumber,
            ));
  }

  int? _cachedLastPostNumber(TopicDetail detail) {
    if (!detail.isMegaTopic) {
      if (detail.stream.isEmpty) return 1;
      return _store.read<Post>(siteUrl, detail.stream.last)?.postNumber;
    }
    final last = detail.lastPostId;
    if (last != null && detail.stream.contains(last)) {
      final post = _store.read<Post>(siteUrl, last);
      if (post != null) return post.postNumber;
    }
    if (detail.highestPostNumber > 0) {
      for (final id in detail.stream) {
        final number = _store.read<Post>(siteUrl, id)?.postNumber;
        if (number == detail.highestPostNumber) return number;
      }
    }
    if (detail.stream.isEmpty && detail.postsCount == 0) return 1;
    return null;
  }

  void _resolveLastPost(int topicId, int? requested, int position, int number) {
    if (isCurrent &&
        requested == TopicLink.lastPostNumber &&
        position == _topic(topicId).positions) {
      _owner.lastPostResolved?.call(siteUrl, topicId, number);
    }
  }

  int _lastReturnedPostNumber(TopicPayload payload, _ReadStamp stamp) =>
      _withoutRemoved(
        payload,
        stamp.removals,
      ).posts.fold(1, (number, post) => math.max(number, post.postNumber));

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
    required int? postNumber,
    required TopicPrefetchIntent intent,
    required bool Function() isInterested,
  }) {
    if (!isCurrent ||
        loading(topic.id) ||
        (!_topic(topic.id).stale && _hasPost(topic.id, postNumber))) {
      return () {};
    }
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
          if (credential == null ||
              !_readIsCurrent(stamp) ||
              cancellation.isCancelled) {
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
          if (!_readIsCurrent(stamp) || cancellation.isCancelled) return null;
          return PrefetchedTopic(
            payload,
            stamp.bookmarks,
            stamp.archive,
            stamp.removals,
            stamp.actions,
            notificationRead: stamp.notification,
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
    final requestedPost = postNumber;
    final discovery = _owner.usesReader != null && state.acceptedReads == 0;
    final customReader =
        held != null &&
        !discovery &&
        _owner.usesReader?.call(siteUrl, held) == true;
    if (discovery || customReader) postNumber = null;
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
    final resumeHeld = held == null || discovery || customReader
        ? null
        : opening._resumeFor(held);
    if (postNumber == null &&
        !force &&
        !state.stale &&
        resumeHeld != null &&
        opening.canResume()) {
      final target = opening.resume(resumeHeld);
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
    if (!discovery &&
        held != null &&
        !force &&
        !state.stale &&
        _hasPost(topicId, postNumber)) {
      final changed = _owner.published(siteUrl, held);
      final last = postNumber == TopicLink.lastPostNumber
          ? _cachedLastPostNumber(
              _store.read<TopicDetail>(siteUrl, topicId) ?? held,
            )
          : null;
      if (postNumber != TopicLink.lastPostNumber || last != null) {
        if (last != null) {
          _resolveLastPost(topicId, postNumber, positionAtOpen, last);
        }
        if (changed || last != null) _changed();
        return;
      }
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
    state.readerFailure = null;
    state.readSettled = Completer<void>();
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
      final candidate = prefetched == null || stamp.redacted.isNotEmpty
          ? null
          : await _stage(
              prefetched,
              elapsed,
              'waiting for topic prefetch $topicId',
            );
      if (!isCurrent) return;
      final warmed = candidate?.notificationRead?.isCurrent == false
          ? null
          : candidate;
      if (warmed != null) {
        stamp = (
          notification: warmed.notificationRead,
          bookmarks: warmed.bookmarkVersion,
          actions: warmed.actionVersion,
          archive: warmed.archiveVersion,
          removals: warmed.postRemovalVersion,
          streams: stamp.streams,
          likes: stamp.likes,
          redacted: const {},
        );
      }
      if (!_readIsCurrent(stamp)) return;
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
        final custom = _owner.usesReader?.call(siteUrl, received) == true;
        if (!custom) {
          _resolveLastPost(
            topicId,
            postNumber,
            positionAtOpen,
            _lastReturnedPostNumber(fetched, stamp),
          );
        }
        opening.received(received);
        if (!custom && discovery && requestedPost != null) {
          resumeNumber = requestedPost;
        } else if (!custom && postNumber == null && opening.canResume()) {
          resumeNumber = opening._resumeFor(received);
        }
      }
    } catch (error) {
      if (isCurrent && identical(state.reading, reading)) {
        state.readerFailure = error;
      }
    } finally {
      if (isCurrent && identical(state.reading, reading)) {
        state.reading = null;
        final settled = state.readSettled;
        state.readSettled = null;
        settled?.complete();
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
    final positionAtOpen = state.positions;
    var stamp = _stamp(topicId);
    final reading = Object();
    state.reading = reading;
    state.readSettled = Completer<void>();
    state.refreshPending = false;
    state.refreshPostNumber = null;
    state.stale = true;
    state.readerFailure = null;
    try {
      await _recoverPendingModeration(topicId);
      if (!isCurrent) return;
      stamp = _stamp(topicId);
      final credential = await _requests.credentials(_owner.credentials);
      if (!_readIsCurrent(stamp)) return;
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
      final received = _publishTopic(
        payload,
        stamp,
        positioned: postNumber != null,
      );
      if (received != null) {
        _resolveLastPost(
          topicId,
          postNumber,
          positionAtOpen,
          _lastReturnedPostNumber(payload, stamp),
        );
      }
    } catch (error) {
      if (isCurrent) {
        state.stale = true;
        state.readerFailure = error;
      }
    } finally {
      if (isCurrent && identical(state.reading, reading)) {
        state.reading = null;
        final settled = state.readSettled;
        state.readSettled = null;
        settled?.complete();
        _changed();
        if (isCurrent && state.reading == null && state.refreshPending) {
          unawaited(refresh(topicId, postNumber: state.refreshPostNumber));
        }
      }
    }
  }

  Future<bool> refreshAfterMutation(int topicId) async {
    if (!isCurrent) return false;
    final state = _topic(topicId);
    final accepted = state.acceptedReads;
    unawaited(refresh(topicId));
    try {
      while (isCurrent && state.reading != null) {
        await state.readSettled!.future.timeout(_owner.loadTimeout);
      }
      return isCurrent && state.acceptedReads > accepted && !state.stale;
    } on TimeoutException {
      if (isCurrent) state.stale = true;
      return false;
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
      if (!_readIsCurrent(stamp)) return;
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
    } catch (_) {
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
      if (!_readIsCurrent(stamp)) return;
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
      final page = [
        for (final post in posts)
          if (!_removedAfter(detail.id, post.id, stamp.removals) &&
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
              if (!_removedAfter(detail.id, post.id, stamp.removals)) post.id,
          ],
          lastPostIdAtDispatch: detail.lastPostId,
        ),
      );
    } catch (_) {
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
      if (!_readIsCurrent(stamp)) return;
      final posts = await credential.run(
        () => _owner.content.posts(
          siteUrl: siteUrl,
          topicId: topicId,
          ids: requested,
          apiKey: credential.apiKey,
        ),
      );
      if (!isCurrent) return;
      final byId = {
        for (final post in posts)
          if (requested.contains(post.id) &&
              !_removedAfter(topicId, post.id, stamp.removals))
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
              if (!_removedAfter(topicId, id, stamp.removals)) id,
          ],
        ),
      );
      _changed();
    } catch (_) {
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
      if (!_readIsCurrent(stamp)) return true;
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
    final held = await ensurePosts(
      topicId,
      [postId],
      shouldFetch: isInterested,
      shouldPublish: isInterested,
    );
    return held ? _store.read<Post>(siteUrl, postId) : null;
  }

  /// Ensures [postIds] are cached. [shouldFetch] gates the request, and
  /// [shouldPublish] gates the cache update after the response.
  Future<bool> ensurePosts(
    int topicId,
    List<int> postIds, {
    required bool Function() shouldFetch,
    required bool Function() shouldPublish,
  }) async {
    if (!isCurrent || !shouldFetch()) return false;
    bool isMissing(int id) => !_store.containsRecord<Post>(siteUrl, id);
    if (!postIds.any(isMissing)) return true;
    final stamp = _stamp(topicId);
    final credential = await _requests.keyCredentials(_owner.credentials);
    if (!_readIsCurrent(stamp) || !shouldFetch()) return false;
    final missing = postIds.where(isMissing).toList();
    if (missing.isEmpty) return true;
    final fetched = await credential.run(
      () => _owner.content.posts(
        siteUrl: siteUrl,
        topicId: topicId,
        ids: missing,
        apiKey: credential.apiKey,
      ),
    );
    if (!isCurrent || !shouldPublish()) return false;
    if (!_publishPosts(topicId, fetched, stamp)) return false;
    return postIds.every((id) => _store.containsRecord<Post>(siteUrl, id));
  }

  /// Reads the run of a mega topic around [postNumber] so a route can settle
  /// on it without waiting, answering the post number to settle on: a deleted
  /// number has none of its own. Publishing replaces a run that does not
  /// overlap, which is why it is dropped once [isInterested] answers false.
  Future<int?> ensureMegaRun(
    int topicId, {
    required String slug,
    required int postNumber,
    required bool Function() isInterested,
  }) async {
    if (!isCurrent || !isInterested()) return null;
    final held = _heldMegaPostNumber(topicId, postNumber);
    if (held != null) return held;
    final stamp = _stamp(topicId);
    final credential = await _requests.credentials(_owner.credentials);
    if (!_readIsCurrent(stamp) || !isInterested()) return null;
    final refreshed = _heldMegaPostNumber(topicId, postNumber);
    if (refreshed != null) return refreshed;
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
    if (!isCurrent || !isInterested()) return null;
    if (_publishTopic(payload, stamp, positioned: true) == null) return null;
    int? landed;
    for (final post in payload.posts) {
      if (post.postNumber >= postNumber &&
          (landed == null || post.postNumber < landed)) {
        landed = post.postNumber;
      }
    }
    return landed;
  }

  /// The post the held run has at [postNumber], or the next one when that
  /// number falls in a gap the run spans. Answers null outside the run.
  int? _heldMegaPostNumber(int topicId, int postNumber) {
    final stream = _store.read<TopicDetail>(siteUrl, topicId)?.stream;
    if (stream == null) return null;
    int? previous;
    for (final id in stream) {
      final number = _store.read<Post>(siteUrl, id)?.postNumber;
      if (number == postNumber) return number;
      if (number != null && number > postNumber) {
        return previous == null ? null : number;
      }
      previous = number;
    }
    return null;
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
        if (deletion) _dropUnreadPost(topicId, id);
        if (!isCurrent) return;
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

  /// A like announced on the topic's channel, applied from its own total as
  /// the web client's PostStream#triggerLikedPost does. False leaves it to a
  /// read of the post: a write or a read already out could answer with a count
  /// from either side of this one, and the announced total includes the likes
  /// of users this viewer ignores, which PostSerializer leaves out.
  bool acceptLiveLike(
    int topicId,
    int postId, {
    required int likeCount,
    required bool liked,
    required int? actorId,
  }) {
    if (!isCurrent || _store.read<Post>(siteUrl, postId) == null) return true;
    final state = _post(postId);
    final own =
        actorId != null && actorId == _owner.currentUserId?.call(siteUrl);
    if (own && state.likeWrite != null) return true;
    if (state.holders.isNotEmpty ||
        state.refreshOwner != null ||
        _owner.ignoredUsernames?.call(siteUrl).isNotEmpty == true) {
      return false;
    }
    final topic = _topic(topicId);
    topic.likedAt[postId] = ++topic.likes;
    _update<Post>(
      postId,
      (held) =>
          (own ? held.withLike(liked) : held).copyWith(likeCount: likeCount),
    );
    // A plugin reader reads posts on the shell's notification, not their refs.
    if (isCurrent && usesReader(topicId)) _changed();
    return true;
  }

  /// An id announced with no read behind it has no re-read to remove it, and
  /// a later topic read keeps an id past the posts it returned.
  void _dropUnreadPost(int topicId, int postId) {
    _topic(topicId).createdPosts.remove(postId);
    final stream = _store.read<TopicDetail>(siteUrl, topicId)?.stream;
    if (stream?.contains(postId) != true) return;
    removePost(topicId, postId);
    _changed();
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
      // A tile follows its own post's ref. The shell hears of a re-read only
      // for what reads posts on its notification instead: a plugin reader and
      // the selected-posts toolbar.
      final readByPlugin = usesReader(batch.topicId);
      var changed = false;
      for (final post in posts) {
        if (!isCurrent) return;
        if (wanted.contains(post.id) && current(post.id)) {
          _put(post);
          if (readByPlugin ||
              _owner.postSelected?.call(siteUrl, batch.topicId, post.id) ==
                  true) {
            changed = true;
          }
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
    } catch (_) {
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
      const pageSize = TopicDetail.maximumInitialPosts;
      const concurrentPages = 3;
      for (
        var start = 0;
        start < postIds.length;
        start += pageSize * concurrentPages
      ) {
        if (!_ownsLease(original)) return PostProjectionFreshness.retired;
        final pages = await Future.wait([
          for (
            var offset = start;
            offset < postIds.length &&
                offset < start + pageSize * concurrentPages;
            offset += pageSize
          )
            credential.run(
              () => _owner.content.posts(
                siteUrl: siteUrl,
                topicId: topicId,
                ids: postIds.sublist(
                  offset,
                  math.min(offset + pageSize, postIds.length),
                ),
                apiKey: credential.apiKey,
              ),
            ),
        ]);
        if (!_ownsLease(original)) return PostProjectionFreshness.retired;
        for (final posts in pages) {
          for (final post in posts) {
            if (postIds.contains(post.id)) fresh[post.id] = post;
          }
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

  PostLikeWrite? beginLike(Post source) {
    if (!isCurrent) return null;
    final current = _store.read<Post>(siteUrl, source.id);
    if (current != null && current.liked != source.liked) return null;
    final state = _post(source.id);
    if (state.likeWrite != null) return null;
    final original = current ?? source;
    final guess = original.withLike(!source.liked);
    final write = PostLikeWrite._(this, state, original, guess);
    state.likeWrite = write;
    _update<Post>(source.id, (_) => guess);
    return write;
  }

  @override
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

  @override
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
    if (usesReader(topicId)) _topic(topicId).readerPosts.add(post.id);
    if (!_removedAfter(topicId, post.id, removals)) {
      _update<TopicDetail>(topicId, (held) => held.withPostId(post.id));
    }
    if (isCurrent) _owner.acceptedPost?.call(siteUrl, topicId, post);
  }

  /// A post announced on the topic's channel, handled as the web client's
  /// PostStream#triggerNewPostsInStream does: a reader holding the stream's
  /// end reads the post, and any other reader only learns the id for paging
  /// to reach. A mega topic has no stream to append to.
  void acceptCreatedPost(
    int topicId,
    int postId, {
    required String slug,
    int? postNumber,
    String? username,
  }) {
    if (!isCurrent) return;
    final detail = _store.read<TopicDetail>(siteUrl, topicId);
    if (detail == null || detail.isMegaTopic || !readerResolved(topicId)) {
      unawaited(refresh(topicId, slug: slug));
      return;
    }
    final state = _topic(topicId);
    // A read already out can answer with the count from before this post, on
    // top of the `stats` message that follows it.
    if (state.reading != null) state.refreshPending = true;
    if (postNumber != null) {
      _update<TopicDetail>(
        topicId,
        (held) => held.withHighestPostNumber(postNumber),
      );
      if (!isCurrent) return;
    }
    if (username != null && _ignores(username)) return;
    state.createdPosts.add(postId);
    if (state.readingCreated) return;
    state.readingCreated = true;
    scheduleMicrotask(() => unawaited(_readCreatedPosts(topicId, slug)));
  }

  bool _ignores(String username) =>
      _owner.ignoredUsernames?.call(siteUrl).contains(username) == true;

  Future<void> _readCreatedPosts(int topicId, String slug) async {
    final state = _topic(topicId);
    try {
      while (isCurrent && state.createdPosts.isNotEmpty) {
        await _readCreatedBatch(topicId, slug);
      }
    } finally {
      if (isCurrent) state.readingCreated = false;
    }
  }

  Future<void> _readCreatedBatch(int topicId, String slug) async {
    final state = _topic(topicId);
    final detail = _store.read<TopicDetail>(siteUrl, topicId);
    if (detail == null || detail.isMegaTopic) {
      state.createdPosts.clear();
      return;
    }
    final wanted = [
      for (final id in state.createdPosts)
        if (!detail.stream.contains(id) && !state.removedAt.containsKey(id)) id,
    ];
    state.createdPosts.clear();
    final tail = detail.stream.lastOrNull;
    if (tail != null && _store.read<Post>(siteUrl, tail) == null) {
      _appendCreated(topicId, wanted);
      return;
    }
    final batch = wanted.take(TopicDetail.maximumInitialPosts).toList();
    state.createdPosts.addAll(wanted.skip(batch.length));
    if (batch.isEmpty) return;
    final stamp = _stamp(topicId);
    try {
      final credential = await _requests.keyCredentials(_owner.credentials);
      if (!isCurrent) return;
      final posts = await credential.run(
        () => _owner.content.posts(
          siteUrl: siteUrl,
          topicId: topicId,
          ids: batch,
          apiKey: credential.apiKey,
        ),
      );
      if (!isCurrent) return;
      final byId = {for (final post in posts) post.id: post};
      final visible = [
        for (final id in batch)
          if (byId[id] case final post? when !_ignores(post.username)) post,
      ];
      if (!_publishPosts(topicId, visible, stamp, onlyUnloaded: true)) return;
      _update<TopicDetail>(
        topicId,
        (held) => held.withAnnouncedPosts([
          for (final post in visible)
            if (!_removedAfter(topicId, post.id, stamp.removals)) post.id,
        ]),
      );
      if (!isCurrent) return;
      if (_store.read<TopicDetail>(siteUrl, topicId) case final held?) {
        _owner.published(siteUrl, held);
      }
      _changed();
      // A status change is announced as a small action, and only a topic read
      // carries the status itself.
      if (isCurrent && visible.any((post) => post.isSmallAction)) {
        unawaited(refresh(topicId, slug: slug));
      }
    } catch (_) {
      if (isCurrent) {
        _appendCreated(topicId, [
          for (final id in batch)
            if (!_removedAfter(topicId, id, stamp.removals)) id,
        ]);
      }
    }
  }

  /// Leaves [postIds] for paging to read. Whether one of them changed the
  /// topic's status is unknown until then, so the next open reads the topic.
  void _appendCreated(int topicId, List<int> postIds) {
    if (postIds.isEmpty) return;
    _update<TopicDetail>(topicId, (held) => held.withAnnouncedPosts(postIds));
    refreshWhenOpened(topicId);
    _changed();
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

  static bool _hasReplyBoundaryStream(TopicDetail detail) =>
      !detail.isMegaTopic &&
      detail.stream.isNotEmpty &&
      detail.stream.length >= detail.postsCount &&
      detail.gapsBefore.isEmpty &&
      detail.gapsAfter.isEmpty &&
      detail.stream.every((id) => id > 0);

  Future<ReplySendBoundary?> captureReplySendBoundary({
    required int topicId,
    required String slug,
    required AccountRequestCredentials credential,
  }) async {
    if (!isCurrent) return null;
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
      final detail = payload.detail;
      if (detail.id != topicId || !_hasReplyBoundaryStream(detail)) {
        return null;
      }
      return ReplySendBoundary._(this, topicId, detail.stream.reduce(math.max));
    } catch (_) {
      return null;
    }
  }

  Future<ReplyLookupResult> findReply({
    required int topicId,
    required String slug,
    required String? username,
    required String raw,
    required bool whisper,
    required ReplySendBoundary? boundary,
    required AccountRequestCredentials credential,
  }) async {
    if (!isCurrent ||
        username == null ||
        username.trim().isEmpty ||
        boundary == null ||
        !identical(boundary._session, this) ||
        boundary._topicId != topicId) {
      return const ReplyIndeterminate();
    }
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
      if (!isCurrent || payload.detail.id != topicId) {
        return const ReplyIndeterminate();
      }
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
      if (!isCurrent) return const ReplyIndeterminate();
      final rawKey = _storedRaw(raw);
      final expectedType = whisper
          ? Post.whisperPostType
          : Post.regularPostType;
      final matches = posts
          .where(
            (post) =>
                post.id > boundary._maxPostId &&
                tail.contains(post.id) &&
                post.username == username &&
                post.postType == expectedType &&
                post.raw != null &&
                _storedRaw(post.raw!) == rawKey,
          )
          .toList();
      if (_publishTopic(payload, stamp) == null ||
          !_publishPosts(topicId, posts, stamp) ||
          !isCurrent ||
          matches.length != 1) {
        return const ReplyIndeterminate();
      }
      final landed = matches.single;
      final newIds = stream.where((id) => id > boundary._maxPostId);
      if (!_hasReplyBoundaryStream(payload.detail) ||
          !newIds.every(
            (id) =>
                tail.contains(id) &&
                posts.any(
                  (post) =>
                      post.id == id &&
                      post.username.trim().isNotEmpty &&
                      (post.username != username ||
                          post.postType != expectedType ||
                          post.raw != null),
                ),
          )) {
        return const ReplyIndeterminate();
      }
      if (_removedAfter(topicId, landed.id, stamp.removals)) {
        return const ReplyIndeterminate();
      }
      _update<TopicDetail>(topicId, (held) => held.withPostId(landed.id));
      return isCurrent ? ReplyFound(landed) : const ReplyIndeterminate();
    } catch (_) {
      return const ReplyIndeterminate();
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
      Future<({TopicPayload payload, _ReadStamp stamp, String slug})?> check(
        Topic row,
      ) async {
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
        if (first == null) return null;
        final posts = await credential.run(
          () => _owner.content.posts(
            siteUrl: siteUrl,
            topicId: row.id,
            ids: [first],
            includeRaw: true,
            apiKey: credential.apiKey,
          ),
        );
        if (posts.firstOrNull?.raw case final posted?
            when isCurrent && _storedRaw(posted) == rawKey) {
          return (payload: payload, stamp: stamp, slug: row.slug);
        }
        return null;
      }

      final matches = await Future.wait([
        for (final row
            in recent.topics
                .where((row) => _titleKey(row.title) == titleKey)
                .take(_reconcileWindow))
          check(row),
      ]);
      final candidates = matches.nonNulls;
      if (!isCurrent || candidates.length != 1) return null;
      final candidate = candidates.single;
      final detail = _publishTopic(candidate.payload, candidate.stamp);
      return detail == null
          ? null
          : (
              topicId: detail.id,
              slug: candidate.slug,
              title: detail.displayTitle,
            );
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
