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
  int postNumber,
  SiteLease lease,
});

/// Owns optimistic topic read positions and their serialized server receipts.
///
/// Viewport observations can arrive faster than the network. One receipt is
/// sent at a time for each topic, while waiting observations collapse to the
/// newest position because read positions only move forwards. Account changes
/// invalidate both the credential lookup and the queued work before either can
/// cross the HTTP boundary.
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
  final Map<_TopicReadKey, _TopicReadReceipt> _queued = {};
  final Map<_TopicReadKey, Future<void>> _tasks = {};
  final Map<_TopicReadKey, Object> _runs = {};

  bool _disposed = false;

  /// Credits the reader through the farthest post the viewport has shown.
  ///
  /// The local list row moves first so reopening it in this session uses the
  /// new position even while the network write is in flight. Failed receipts
  /// are not rolled back: a later personalized list refresh is authoritative,
  /// and putting unread state back under a reader would be misleading.
  Future<void> mark(
    String siteUrl,
    int topicId,
    int postNumber, {
    required bool caughtUp,
  }) {
    if (_disposed || postNumber <= 0) return Future.value();

    final key = (siteUrl, topicId);
    final held = store.read<Topic>(siteUrl, topicId);
    final local = _positions[key] ?? 0;
    final server = held?.lastReadPostNumber ?? 0;
    if ((local > server ? local : server) >= postNumber) {
      return Future.value();
    }

    final lease = lifecycle.capture(siteUrl);
    _positions[key] = postNumber;
    store.update<Topic>(
      siteUrl,
      topicId,
      (row) => row.copyWith(
        lastReadPostNumber: postNumber,
        // A live list update can know about a newer post than the detail
        // stream on screen. Reaching that stream's end must not clear unread
        // state for a post the reader has not received yet.
        markRead:
            caughtUp &&
            (row.highestPostNumber <= 0 || postNumber >= row.highestPostNumber),
      ),
    );

    _queued[key] = (
      siteUrl: siteUrl,
      topicId: topicId,
      postNumber: postNumber,
      lease: lease,
    );
    final running = _tasks[key];
    if (running != null) return running;

    final run = Object();
    _runs[key] = run;
    final task = _drain(key, run);
    _tasks[key] = task;
    return task;
  }

  /// Drops exactly one site's local positions and prevents its late work from
  /// issuing another request or reporting an error into a replacement account.
  void forget(String siteUrl) {
    _positions.removeWhere((key, _) => key.$1 == siteUrl);
    _queued.removeWhere((key, _) => key.$1 == siteUrl);
    _tasks.removeWhere((key, _) => key.$1 == siteUrl);
    _runs.removeWhere((key, _) => key.$1 == siteUrl);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _positions.clear();
    _queued.clear();
    _tasks.clear();
    _runs.clear();
  }

  /// Sends one receipt at a time and collapses waiting positions to the newest.
  Future<void> _drain(_TopicReadKey key, Object run) async {
    while (_isCurrentRun(key, run)) {
      final receipt = _queued.remove(key);
      if (receipt == null) {
        _finishRun(key, run);
        return;
      }

      try {
        final apiKey = await credentials.apiKeyFor(receipt.siteUrl);
        if (!_canSend(key, run, receipt.lease) || apiKey == null) continue;

        final clientId = await credentials.clientId();
        if (!_canSend(key, run, receipt.lease)) continue;

        await api.recordTopicRead(
          siteUrl: receipt.siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          topicId: receipt.topicId,
          postNumber: receipt.postNumber,
        );
      } catch (error, stackTrace) {
        if (_canSend(key, run, receipt.lease)) {
          reportError(error, stackTrace, 'topic.markRead');
        }
        // A newer queued position must still be attempted after this failure.
      }
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
