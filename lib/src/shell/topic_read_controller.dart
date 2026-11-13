import 'dart:async';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../data/topic_reads_api.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/topic.dart';

final class TopicReadController extends FrameSafeNotifier {
  TopicReadController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.store,
  });

  final TopicReadsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;
  final Map<String, _TopicReadAccount> _accounts = {};

  _TopicReadAccount? _accountFor(String siteUrl) {
    final account = _accounts[siteUrl];
    return account?.lease.isCurrent == true ? account : null;
  }

  _TopicReadAccount _ensureAccount(String siteUrl, {SiteLease? lease}) {
    final held = _accounts[siteUrl];
    if (held?.lease.isCurrent == true) return held!;
    held?.retire();
    final account = _TopicReadAccount(lease ?? lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      if (!identical(_accounts[siteUrl], account)) return;
      _accounts.remove(siteUrl);
      final hadPositions = account.hasPositions;
      account.retire();
      if (hadPositions) notifySafely();
    });
    return account;
  }

  bool _isCurrent(String siteUrl, _TopicReadAccount account) =>
      !isDisposed &&
      account.lease.isCurrent &&
      identical(_accounts[siteUrl], account);

  int? lastReadPostNumberFor(String siteUrl, int topicId) =>
      _accountFor(siteUrl)?.topics[topicId]?.position;

  /// A stale list response must not roll back this session's read progress.
  Topic project(String siteUrl, Topic incoming) {
    final position = lastReadPostNumberFor(siteUrl, incoming.id);
    if (position == null || position < (incoming.lastReadPostNumber ?? 0)) {
      return incoming;
    }
    return _projectRead(
      incoming,
      position,
      position,
      caughtUp:
          incoming.readingPolicy.usesPositionForCatchUp &&
          incoming.highestPostNumber > 0,
    );
  }

  /// Credits [postNumber], the farthest post read, and every other post in
  /// [readPostNumbers] that was read on the same screen.
  Future<void> mark(
    String siteUrl,
    int topicId,
    int postNumber, {
    required bool caughtUp,
    Iterable<int> readPostNumbers = const [],
  }) {
    if (isDisposed || topicId <= 0 || postNumber <= 0) return Future.value();
    final account = _ensureAccount(siteUrl);
    final state = account.topic(topicId);
    if (state.reset != null) return Future.value();
    final held = store.read<Topic>(siteUrl, topicId);
    final local = state.position ?? 0;
    final server = held?.lastReadPostNumber ?? 0;
    final position = local > server ? local : server;
    // A jump raises the row over unread posts the reader may scroll back to.
    // Timing credits therefore track the exact posts observed, independently.
    final credits = state.credits ??= _TopicReadCredits(server);
    if (held?.readingPolicy.usesPositionForCatchUp == false) {
      credits.serverPosition = 0;
    }
    final unread = {
      ...readPostNumbers.where((read) => read < postNumber).toList()..sort(),
      postNumber,
    }.where(credits.admit).toList();
    final retryPosts = state.retries
        .where((post) => post <= postNumber)
        .toSet();
    if (unread.isEmpty && retryPosts.isEmpty) {
      if (caughtUp) {
        store.update<Topic>(
          siteUrl,
          topicId,
          (row) => _projectRead(row, position, postNumber, caughtUp: true),
        );
      }
      return Future.value();
    }

    final nextPosition = postNumber > position ? postNumber : position;
    state.position = nextPosition;
    state.retries.removeAll(retryPosts);
    // Install receipts before store listeners can reset or replace this account.
    state.queued.addAll({...unread, ...retryPosts});
    store.update<Topic>(
      siteUrl,
      topicId,
      (row) => _projectRead(row, nextPosition, postNumber, caughtUp: caughtUp),
    );
    if (!_isCurrent(siteUrl, account)) return Future.value();
    if (nextPosition != local) notifySafely();
    return _drainPending(siteUrl, topicId, account, state);
  }

  Future<void> _drainPending(
    String siteUrl,
    int topicId,
    _TopicReadAccount account,
    _TopicReadState state,
  ) {
    final running = state.run;
    if (running != null) return running.completion.future;
    if (!_isCurrent(siteUrl, account) || state.queued.isEmpty) {
      return Future.value();
    }
    final run = _TopicReadRun();
    state.run = run;
    run.completion.complete(_drain(siteUrl, topicId, account, state, run));
    return run.completion.future;
  }

  bool resetInFlight(String siteUrl, int topicId) =>
      _accountFor(siteUrl)?.topics[topicId]?.reset != null;

  Future<void> reset(
    String siteUrl,
    int topicId, {
    required SiteLease lease,
    required Future<void> Function() write,
    required Future<void> Function() accepted,
    required void Function(Object error, StackTrace stackTrace) onError,
    required void Function() onChanged,
  }) async {
    if (isDisposed || !lease.isCurrent) return;
    final account = _ensureAccount(siteUrl, lease: lease);
    final state = account.topic(topicId);
    if (state.reset != null) return;
    final operation = Object();
    state.reset = operation;
    bool isCurrent() =>
        _isCurrent(siteUrl, account) && identical(state.reset, operation);
    try {
      onChanged();
      if (!isCurrent()) return;
      await _drainPending(siteUrl, topicId, account, state);
      if (!isCurrent()) return;
      await write();
      if (!isCurrent()) return;
      final hadPosition = state.position != null;
      state.clearReads();
      await accepted();
      if (isCurrent() && hadPosition) notifySafely();
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    } finally {
      if (identical(state.reset, operation)) {
        state.reset = null;
        if (_isCurrent(siteUrl, account)) onChanged();
      }
    }
  }

  void forget(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    final hadPositions = account?.hasPositions ?? false;
    account?.retire();
    if (hadPositions) notifySafely();
  }

  @override
  void dispose() {
    if (isDisposed) return;
    for (final account in _accounts.values) {
      account.retire();
    }
    _accounts.clear();
    super.dispose();
  }

  Topic _projectRead(
    Topic row,
    int position,
    int postNumber, {
    required bool caughtUp,
  }) {
    // Core counts a tracked topic's unread posts from its highest post and
    // reports none for untracked topics, so a partial read lowers a count but
    // never starts one. Reaching the row's highest post without catching up
    // means the row is behind the stream: it keeps its count until a list
    // update says how many posts follow.
    if (!row.readingPolicy.usesPositionForCatchUp) return row;
    final remaining = row.highestPostNumber - position;
    final updated = row.copyWith(
      lastReadPostNumber: position,
      unreadPosts: remaining > 0 && remaining < row.unreadPosts
          ? remaining
          : null,
      // A live list update may know about posts beyond the stream on screen.
      markRead:
          caughtUp &&
          (row.highestPostNumber <= 0 || postNumber >= row.highestPostNumber),
    );
    // markRead projects the row's highest post, which can be stale when an
    // older receipt is retried. Keep the optimistic maximum in that case.
    return updated.lastReadPostNumber == position
        ? updated
        : updated.copyWith(lastReadPostNumber: position);
  }

  Future<void> _drain(
    String siteUrl,
    int topicId,
    _TopicReadAccount account,
    _TopicReadState state,
    _TopicReadRun run,
  ) async {
    bool ownsRun() => _isCurrent(siteUrl, account) && identical(state.run, run);
    while (ownsRun()) {
      if (state.queued.isEmpty) {
        state.run = null;
        return;
      }
      final posts = state.queued
          .take(TopicReadsApi.maximumPostsPerRequest)
          .toSet();
      state.queued.removeAll(posts);
      try {
        final auth = await AccountRequestSession(
          siteUrl,
          account.lease,
        ).credentials(credentials);
        final apiKey = auth.apiKey;
        if (!ownsRun()) return;
        if (apiKey == null) {
          // Retry admitted posts on a later observation, without spinning
          // through more batches while credentials remain unavailable.
          state.retries.addAll({...posts, ...state.queued});
          state.queued.clear();
          state.run = null;
          return;
        }
        await auth.run(
          () => api.recordTopicReads(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: auth.clientId,
            topicId: topicId,
            postNumbers: posts.toList(),
          ),
        );
      } catch (_) {
        // A position cannot acknowledge exact timing keys. A later observation
        // retries failed posts, while newer queued batches continue now.
        if (ownsRun()) state.retries.addAll(posts);
      }
    }
  }
}

final class _TopicReadAccount {
  _TopicReadAccount(this.lease);

  final SiteLease lease;
  final Map<int, _TopicReadState> topics = {};
  void Function()? detach;

  _TopicReadState topic(int id) => topics.putIfAbsent(id, _TopicReadState.new);
  bool get hasPositions => topics.values.any((state) => state.position != null);

  void retire() {
    detach?.call();
    detach = null;
    for (final state in topics.values) {
      state.clearReads();
      state.reset = null;
    }
    topics.clear();
  }
}

final class _TopicReadState {
  int? position;
  _TopicReadCredits? credits;
  final Set<int> retries = {};
  final Set<int> queued = {};
  _TopicReadRun? run;
  Object? reset;

  void clearReads() {
    position = null;
    credits = null;
    retries.clear();
    queued.clear();
    run = null;
  }
}

final class _TopicReadRun {
  final completion = Completer<void>();
}

/// The posts one account session has admitted for a timing in one topic.
final class _TopicReadCredits {
  _TopicReadCredits(this.serverPosition);

  // Reading is mostly contiguous, but posts left out of the readable set, such
  // as small actions and deleted or filtered posts, split the ranges.
  // Forgetting a range only sends a duplicate timing, so the one farthest from
  // the reader is dropped.
  static const _maximumRanges = 64;

  /// The server's last read post when this session first observed the topic.
  /// Chronological readers skip earlier posts. An activity reader removes
  /// this floor because a caught-up position does not prove they were viewed.
  int serverPosition;

  // Sorted, disjoint and non-adjacent inclusive ranges above serverPosition.
  final List<(int, int)> _ranges = [];

  /// Records [post] and answers whether it still needed a timing.
  bool admit(int post) {
    if (post <= serverPosition) return false;
    var index = 0;
    while (index < _ranges.length && _ranges[index].$2 < post - 1) {
      index++;
    }
    if (index < _ranges.length) {
      final (first, last) = _ranges[index];
      if (first <= post && post <= last) return false;
      if (last == post - 1) {
        final next = index + 1 < _ranges.length ? _ranges[index + 1] : null;
        if (next != null && next.$1 == post + 1) {
          _ranges[index] = (first, next.$2);
          _ranges.removeAt(index + 1);
        } else {
          _ranges[index] = (first, post);
        }
        return true;
      }
      if (first == post + 1) {
        _ranges[index] = (post, last);
        return true;
      }
    }
    _ranges.insert(index, (post, post));
    if (_ranges.length > _maximumRanges) {
      if (post - _ranges.first.$2 > _ranges.last.$1 - post) {
        _ranges.removeAt(0);
      } else {
        _ranges.removeLast();
      }
    }
    return true;
  }
}
