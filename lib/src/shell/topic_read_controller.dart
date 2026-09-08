import 'dart:async';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../models/topic.dart';

typedef TopicReadErrorReporter =
    void Function(Object error, StackTrace stackTrace, String operation);

typedef _TopicReadKey = (String siteUrl, int topicId);

typedef _TopicReadReceipt = ({
  String siteUrl,
  int topicId,
  Set<int> postNumbers,
  SiteLease lease,
});

final class TopicReadController {
  TopicReadController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.store,
    required this.reportError,
  });

  final TopicReadsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;
  final TopicReadErrorReporter reportError;

  final Map<_TopicReadKey, int> _positions = {};
  final Map<_TopicReadKey, _TopicReadReceipt> _retries = {};
  final Map<_TopicReadKey, _TopicReadReceipt> _queued = {};
  final Map<_TopicReadKey, Future<void>> _tasks = {};
  final Map<_TopicReadKey, Object> _runs = {};

  bool _disposed = false;

  Future<void> mark(
    String siteUrl,
    int topicId,
    int postNumber, {
    required bool caughtUp,
  }) {
    if (_disposed || topicId <= 0 || postNumber <= 0) return Future.value();

    final key = (siteUrl, topicId);
    final held = store.read<Topic>(siteUrl, topicId);
    final local = _positions[key] ?? 0;
    final server = held?.lastReadPostNumber ?? 0;
    final position = local > server ? local : server;
    final failed = _retries[key];
    final retryPosts = failed != null && failed.lease.isCurrent
        ? failed.postNumbers.where((post) => post <= postNumber).toSet()
        : <int>{};
    if (position >= postNumber && retryPosts.isEmpty) {
      if (caughtUp) {
        store.update<Topic>(
          siteUrl,
          topicId,
          (row) => _projectRead(row, position, postNumber, caughtUp: true),
        );
      }
      return Future.value();
    }

    final lease = lifecycle.capture(siteUrl);
    final nextPosition = postNumber > position ? postNumber : position;
    _positions[key] = nextPosition;
    failed?.postNumbers.removeAll(retryPosts);
    if (failed != null && failed.postNumbers.isEmpty) _retries.remove(key);
    // Store listeners may advance this topic again, forget it, or replace its
    // account. Accept this receipt before publishing the optimistic position.
    _retain(_queued, key, (
      siteUrl: siteUrl,
      topicId: topicId,
      postNumbers: {if (postNumber > position) postNumber, ...retryPosts},
      lease: lease,
    ));
    store.update<Topic>(
      siteUrl,
      topicId,
      (row) => _projectRead(row, nextPosition, postNumber, caughtUp: caughtUp),
    );

    if (_disposed || !lease.isCurrent) return Future.value();
    final running = _tasks[key];
    if (running != null) return running;
    if (!_queued.containsKey(key)) return Future.value();

    final run = Object();
    final completion = Completer<void>();
    _runs[key] = run;
    _tasks[key] = completion.future;
    completion.complete(_drain(key, run));
    return completion.future;
  }

  void forget(String siteUrl) {
    _positions.removeWhere((key, _) => key.$1 == siteUrl);
    _retries.removeWhere((key, _) => key.$1 == siteUrl);
    _queued.removeWhere((key, _) => key.$1 == siteUrl);
    _tasks.removeWhere((key, _) => key.$1 == siteUrl);
    _runs.removeWhere((key, _) => key.$1 == siteUrl);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _positions.clear();
    _retries.clear();
    _queued.clear();
    _tasks.clear();
    _runs.clear();
  }

  Topic _projectRead(
    Topic row,
    int position,
    int postNumber, {
    required bool caughtUp,
  }) {
    final updated = row.copyWith(
      lastReadPostNumber: position,
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

  Future<void> _drain(_TopicReadKey key, Object run) async {
    while (_isCurrentRun(key, run)) {
      final pending = _queued[key];
      if (pending == null) {
        _finishRun(key, run);
        return;
      }
      final posts = pending.postNumbers
          .take(TopicReadsApi.maximumPostsPerRequest)
          .toSet();
      pending.postNumbers.removeAll(posts);
      if (pending.postNumbers.isEmpty) _queued.remove(key);
      final receipt = (
        siteUrl: pending.siteUrl,
        topicId: pending.topicId,
        postNumbers: posts,
        lease: pending.lease,
      );

      try {
        final apiKey = await credentials.apiKeyFor(receipt.siteUrl);
        if (!_canSend(key, run, receipt.lease)) continue;
        if (apiKey == null) {
          // Defer all admitted posts until another observation can retry with
          // credentials. Do not spin through the remaining batches.
          _retain(_retries, key, receipt);
          final remaining = _queued.remove(key);
          if (remaining != null) _retain(_retries, key, remaining);
          _finishRun(key, run);
          return;
        }

        final clientId = await credentials.clientId();
        if (!_canSend(key, run, receipt.lease)) continue;

        await api.recordTopicReads(
          siteUrl: receipt.siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          topicId: receipt.topicId,
          postNumbers: receipt.postNumbers.toList(),
        );
      } catch (error, stackTrace) {
        if (_canSend(key, run, receipt.lease)) {
          // Notifications are cleared for exact timing keys. A newer local or
          // server position cannot acknowledge these posts. Retry only after
          // another observation, while still attempting pending newer reads.
          _retain(_retries, key, receipt);
          reportError(error, stackTrace, 'topic.markRead');
        }
        // A newer queued position must still be attempted after this failure.
      }
    }
  }

  void _retain(
    Map<_TopicReadKey, _TopicReadReceipt> queue,
    _TopicReadKey key,
    _TopicReadReceipt receipt,
  ) {
    final pending = queue[key];
    if (pending != null &&
        identical(pending.lease.session, receipt.lease.session)) {
      pending.postNumbers.addAll(receipt.postNumbers);
    } else {
      queue[key] = receipt;
    }
  }

  bool _canSend(_TopicReadKey key, Object run, SiteLease lease) =>
      !_disposed && lease.isCurrent && _isCurrentRun(key, run);

  bool _isCurrentRun(_TopicReadKey key, Object run) =>
      identical(_runs[key], run);

  void _finishRun(_TopicReadKey key, Object run) {
    if (!_isCurrentRun(key, run)) return;
    _runs.remove(key);
    final _ = _tasks.remove(key);
  }
}
