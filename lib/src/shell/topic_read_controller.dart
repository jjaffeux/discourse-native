import 'dart:async';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/origin_cooldown.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../data/topic_read_outbox.dart';
import '../data/topic_reads_api.dart';
import '../data/write_failure.dart';
import '../foundation/frame_safe_notifier.dart';
import '../foundation/site_scoped_state.dart';
import '../models/topic.dart';

/// Read progress is credited to the site as timings. Timings the site has not
/// confirmed are also kept in [outbox], so reading through a failure or just
/// before the app is killed is offered again by [flush] instead of being lost.
/// A timing sent twice only adds its half second to the post's read time: the
/// site moves a read position to the highest post it is given.
final class TopicReadController extends FrameSafeNotifier
    with AccountScopedState {
  TopicReadController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.store,
    this.outbox,
    this.accountFor,
    void Function() Function(void Function(String origin) observer)?
    originSuccesses,
    Duration Function()? elapsed,
    OriginCooldown Function()? cooldownFactory,
    this.confirmedSaveDelay = const Duration(seconds: 2),
  }) : _elapsed = elapsed ?? _monotonicClock(),
       _cooldownFactory = cooldownFactory ?? OriginCooldown.new {
    _detachOriginSuccesses = originSuccesses?.call(_originAnswered);
    final outbox = this.outbox;
    if (outbox != null) {
      unawaited(
        outbox.sites().then((sites) {
          if (!isDisposed) _waitingSites.addAll(sites);
        }),
      );
    }
  }

  /// A site that keeps refusing timings while answering everything else is
  /// offered them again no more often than this.
  static const answeredFlushInterval = Duration(seconds: 30);

  final TopicReadsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;

  /// Null keeps unconfirmed timings in memory only.
  final TopicReadOutbox? outbox;

  /// Names the signed-in account of a site, or null while it has none. The
  /// outbox holds timings for that account alone.
  final String? Function(String siteUrl)? accountFor;

  /// A confirmed timing left in the file is only sent once more after a
  /// kill, so its removal waits this long for another write to carry it
  /// instead of costing a write per batch.
  final Duration confirmedSaveDelay;

  final Duration Function() _elapsed;
  final OriginCooldown Function() _cooldownFactory;
  void Function()? _detachOriginSuccesses;
  final Map<String, _TopicReadAccount> _accounts = {};

  /// Sites that may hold unconfirmed timings, in memory or in [outbox].
  final Set<String> _waitingSites = {};
  final Map<String, Duration> _answeredFlushes = {};

  _TopicReadAccount? _accountFor(String siteUrl) {
    final account = _accounts[siteUrl];
    return account?.lease.isCurrent == true ? account : null;
  }

  _TopicReadAccount _ensureAccount(String siteUrl, {SiteLease? lease}) {
    final held = _accounts[siteUrl];
    if (held?.lease.isCurrent == true) return held!;
    held?.retire();
    final account = _TopicReadAccount(
      lease ?? lifecycle.capture(siteUrl),
      _cooldownFactory(),
    );
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      if (!identical(_accounts[siteUrl], account)) return;
      _accounts.remove(siteUrl);
      final hadPositions = account.hasPositions;
      account.retire();
      if (hadPositions) notifySafely();
    });
    _restore(siteUrl, account);
    return account;
  }

  /// Takes what an earlier session left for this account. A save issued
  /// before that has arrived would overwrite it, so [_save] waits for it.
  void _restore(String siteUrl, _TopicReadAccount account) {
    final outbox = this.outbox;
    if (outbox == null || account.restore != null) return;
    final identity = account.identity ??= accountFor?.call(siteUrl);
    if (identity == null) return;
    account.restore = outbox.restore(siteUrl, identity).then((held) {
      if (!_isCurrent(siteUrl, account)) return;
      for (final entry in (held ?? const <int, List<int>>{}).entries) {
        final state = account.topic(entry.key);
        // A reset in flight clears the topic's reads once the site accepts it.
        if (state.reset != null) continue;
        // Posts this session already admitted are queued, sent or held, and
        // posts under the site's position need no timing.
        final credits = state.credits;
        state.retries.addAll(
          credits == null ? entry.value : entry.value.where(credits.admit),
        );
      }
      account.restored = true;
      if (account.hasPending) _waitingSites.add(siteUrl);
      _save(siteUrl, account);
    });
  }

  void _save(String siteUrl, _TopicReadAccount account) {
    final outbox = this.outbox;
    if (outbox == null || !_isCurrent(siteUrl, account)) return;
    account.settle?.cancel();
    account.settle = null;
    _restore(siteUrl, account);
    final identity = account.identity;
    if (identity == null || !account.restored) return;
    final pending = account.pending;
    unawaited(outbox.save(siteUrl, identity, pending.isEmpty ? null : pending));
  }

  void _saveSoon(String siteUrl, _TopicReadAccount account) {
    if (outbox == null || account.settle != null) return;
    account.settle = Timer(confirmedSaveDelay, () {
      account.settle = null;
      _save(siteUrl, account);
    });
  }

  /// Offers the site every timing it has not confirmed for [siteUrl], from
  /// this session and from earlier ones. Call it when the site may be
  /// reachable again: on app resume and from a connectivity signal. A site
  /// answering any request does so by itself.
  ///
  /// Topics are sent one after another, so a recovered site is not handed the
  /// whole backlog at once. The pass stops when the site does not answer or
  /// turns the account away, which costs an unreachable site one request; a
  /// topic the site fails on by itself does not hold back the ones after it.
  Future<void> flush(String siteUrl) {
    if (isDisposed) return Future.value();
    // Only an outbox can hold timings for a site this session has not read.
    final account = outbox == null || accountFor?.call(siteUrl) == null
        ? _accountFor(siteUrl)
        : _ensureAccount(siteUrl);
    if (account == null) return Future.value();
    return account.flush ??= _flush(siteUrl, account).whenComplete(() {
      account.flush = null;
    });
  }

  Future<void> _flush(String siteUrl, _TopicReadAccount account) async {
    _restore(siteUrl, account);
    await account.restore;
    if (!_isCurrent(siteUrl, account)) return;
    for (final topicId in account.topics.keys.toList()) {
      if (account.cooldown.remaining != null) return;
      final state = account.topics[topicId];
      if (state == null || state.reset != null || state.retries.isEmpty) {
        continue;
      }
      state.queued.addAll(state.retries);
      state.retries.clear();
      account.unanswered = false;
      await _drainPending(siteUrl, topicId, account, state);
      if (!_isCurrent(siteUrl, account)) return;
      if (account.unanswered) return;
    }
    if (!account.hasPending && (outbox == null || account.restored)) {
      _waitingSites.remove(siteUrl);
    }
  }

  void _originAnswered(String origin) {
    if (isDisposed || _waitingSites.isEmpty) return;
    for (final siteUrl in _waitingSites.toList()) {
      if (_originOf(siteUrl) != origin) continue;
      final now = _elapsed();
      final last = _answeredFlushes[siteUrl];
      if (last != null && now - last < answeredFlushInterval) continue;
      _answeredFlushes[siteUrl] = now;
      unawaited(flush(siteUrl));
    }
  }

  /// A site key read from the file is not known to be an HTTP URL.
  static String? _originOf(String siteUrl) {
    try {
      return Uri.parse(siteUrl).origin;
    } catch (_) {
      return null;
    }
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
    _save(siteUrl, account);
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
      _save(siteUrl, account);
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

  /// The account has left the site, so nobody can send what it left unread
  /// there. A lease that retires without this call keeps the file: the same
  /// account restores it under its next lease, and any other account drops it.
  @override
  void forget(String siteUrl) {
    final account = _accounts.remove(siteUrl);
    final hadPositions = account?.hasPositions ?? false;
    account?.retire();
    _waitingSites.remove(siteUrl);
    _answeredFlushes.remove(siteUrl);
    unawaited(outbox?.forget(siteUrl));
    if (hadPositions) notifySafely();
  }

  /// The outbox keeps what is unconfirmed for the next launch.
  @override
  void dispose() {
    if (isDisposed) return;
    _detachOriginSuccesses?.call();
    _detachOriginSuccesses = null;
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
      state.sending.addAll(posts);
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
          state.sending.removeAll(posts);
          state.retries.addAll({...posts, ...state.queued});
          state.queued.clear();
          state.run = null;
          _waitingSites.add(siteUrl);
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
        if (!ownsRun()) return;
        state.sending.removeAll(posts);
        _saveSoon(siteUrl, account);
      } catch (error) {
        if (!ownsRun()) return;
        state.sending.removeAll(posts);
        account.unanswered = switch (error) {
          WriteException(:final statusCode?) =>
            statusCode == 401 || statusCode == 403 || statusCode == 429,
          _ => true,
        };
        if (_refused(error)) {
          _saveSoon(siteUrl, account);
          continue;
        }
        // A position cannot acknowledge exact timing keys. A later observation
        // or flush retries failed posts, while newer queued batches continue
        // now.
        state.retries.addAll(posts);
        _waitingSites.add(siteUrl);
        if (error is WriteException &&
            error.failure == WriteFailure.rateLimited) {
          account.cooldown.extend(
            error.retryWait,
            onExpired: () {
              if (_isCurrent(siteUrl, account)) unawaited(flush(siteUrl));
            },
          );
        }
        _save(siteUrl, account);
      }
    }
  }

  /// The site answered and will answer the same way again: the topic is gone
  /// or closed to this account. Holding the timing would resend it forever.
  static bool _refused(Object error) => switch (error) {
    WriteException(:final statusCode?) =>
      statusCode >= 400 &&
          statusCode < 500 &&
          statusCode != 408 &&
          statusCode != 429,
    _ => false,
  };
}

Duration Function() _monotonicClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}

final class _TopicReadAccount {
  _TopicReadAccount(this.lease, this.cooldown);

  final SiteLease lease;

  /// Holds [TopicReadController.flush] while the site asks to be left alone.
  final OriginCooldown cooldown;
  final Map<int, _TopicReadState> topics = {};
  void Function()? detach;
  String? identity;
  Future<void>? restore;
  bool restored = false;
  Future<void>? flush;
  Timer? settle;

  /// The last failed batch says the site is unreachable, rate limited or
  /// closed to this account, so the topics after it would fare no better.
  bool unanswered = false;

  _TopicReadState topic(int id) => topics.putIfAbsent(id, _TopicReadState.new);
  bool get hasPositions => topics.values.any((state) => state.position != null);
  bool get hasPending => topics.values.any((state) => state.hasPending);

  PendingTopicReads get pending => boundTopicReads({
    for (final entry in topics.entries)
      if (entry.value.hasPending)
        entry.key: {
          ...entry.value.queued,
          ...entry.value.sending,
          ...entry.value.retries,
        },
  });

  void retire() {
    detach?.call();
    detach = null;
    cooldown.cancel();
    settle?.cancel();
    settle = null;
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

  /// The batch on the wire, which is neither queued nor failed yet.
  final Set<int> sending = {};
  _TopicReadRun? run;
  Object? reset;

  bool get hasPending =>
      retries.isNotEmpty || queued.isNotEmpty || sending.isNotEmpty;

  void clearReads() {
    position = null;
    credits = null;
    retries.clear();
    queued.clear();
    sending.clear();
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
