import 'dart:async';

import '../models/post.dart';

typedef TopicPrefetchKey = ({
  String siteUrl,
  Object session,
  int topicId,
  int? postNumber,
});

final class PrefetchedTopic {
  const PrefetchedTopic(
    this.payload,
    this.bookmarkVersion,
    this.archiveVersion,
    this.postRemovalVersion,
  );

  final TopicPayload payload;
  final int bookmarkVersion;
  final int archiveVersion;
  final int postRemovalVersion;
}

final class TopicPrefetchCancellation {
  final _abort = Completer<void>();

  Future<void> get trigger => _abort.future;
  bool get isCancelled => _abort.isCompleted;

  void cancel() {
    if (!isCancelled) _abort.complete();
  }
}

typedef TopicPrefetchLoader =
    Future<PrefetchedTopic?> Function(TopicPrefetchCancellation cancellation);

/// One speculative request, one replaceable hover target, and one retained
/// result. Navigation takes ownership before a row can cancel its hover.
final class TopicPrefetchController {
  TopicPrefetchController({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const hoverDelay = Duration(milliseconds: 40);
  static const lifetime = Duration(seconds: 15);

  final DateTime Function() _clock;
  Timer? _timer;
  Object? _hoverOwner;
  _Prefetch? _candidate;
  _Prefetch? _active;

  /// The returned callback releases only this hover, even if another row has
  /// since requested the same topic.
  void Function() hover(
    TopicPrefetchKey key, {
    required TopicPrefetchLoader load,
    required bool Function() isCurrent,
  }) {
    final owner = Object();
    final held = _candidate;
    if (held == null || held.key != key || !_usable(held)) {
      _discardCandidate();
      final next = _Prefetch(key, load, isCurrent);
      _candidate = next;
      _timer = Timer(hoverDelay, () {
        _timer = null;
        if (!identical(_candidate, next)) return;
        next.ready = true;
        _drain();
      });
    }
    _hoverOwner = owner;
    return () {
      if (!identical(_hoverOwner, owner)) return;
      _hoverOwner = null;
      // Keep a completed response briefly for a return to this row.
      if (_candidate?.completedAt == null) _discardCandidate();
    };
  }

  Future<PrefetchedTopic?>? take(TopicPrefetchKey key) {
    final entry = _candidate;
    if (entry == null || entry.key != key) return null;
    if (!_usable(entry) || !entry.started) {
      _discardCandidate();
      return null;
    }
    _candidate = null;
    _hoverOwner = null;
    _timer?.cancel();
    _timer = null;
    return entry.result.future;
  }

  void discard(TopicPrefetchKey key) {
    if (_candidate?.key == key) _discardCandidate();
  }

  void validate() {
    final entry = _candidate;
    if (entry != null && !_usable(entry)) _discardCandidate();
  }

  bool _usable(_Prefetch entry) =>
      !entry.cancellation.isCancelled &&
      entry.isCurrent() &&
      (entry.completedAt == null ||
          _clock().difference(entry.completedAt!) < lifetime);

  void _discardCandidate() {
    _timer?.cancel();
    _timer = null;
    _candidate?.cancellation.cancel();
    _candidate = null;
    _hoverOwner = null;
  }

  void _drain() {
    if (_active != null) return;
    final entry = _candidate;
    if (entry == null || !entry.ready || entry.started) return;
    if (!_usable(entry)) {
      _discardCandidate();
      return;
    }
    entry.started = true;
    _active = entry;
    unawaited(_load(entry));
  }

  Future<void> _load(_Prefetch entry) async {
    PrefetchedTopic? result;
    try {
      result = await entry.load(entry.cancellation);
    } catch (_) {
      // Hover errors are silent. A click retries through normal topic loading.
    } finally {
      if (entry.cancellation.isCancelled) result = null;
      entry.completedAt = _clock();
      entry.result.complete(result);
      if (result == null && identical(_candidate, entry)) _discardCandidate();
      _active = null;
      _drain();
    }
  }

  /// Used when the window closes or the account session is retired, including
  /// cancellation of a request already adopted by navigation.
  void clear() {
    _discardCandidate();
    _active?.cancellation.cancel();
  }
}

final class _Prefetch {
  _Prefetch(this.key, this.load, this.isCurrent);

  final TopicPrefetchKey key;
  final TopicPrefetchLoader load;
  final bool Function() isCurrent;
  final cancellation = TopicPrefetchCancellation();
  final result = Completer<PrefetchedTopic?>();
  bool ready = false;
  bool started = false;
  DateTime? completedAt;
}
