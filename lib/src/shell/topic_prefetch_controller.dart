import 'dart:async';

import '../diagnostics/topic_prefetch_trace.dart';
import '../models/post.dart';

enum TopicPrefetchIntent { hover, keyboard, trajectory }

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

/// One speculative request, one replaceable intent target, and one retained
/// result. Navigation takes ownership before the list can release its interest.
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
    TopicPrefetchIntent intent = TopicPrefetchIntent.hover,
  }) {
    final owner = Object();
    final held = _candidate;
    if (held == null || held.key != key || !_usable(held)) {
      _discardCandidate();
      final next = _Prefetch(key, load, isCurrent, intent);
      _candidate = next;
      next.ready = intent == TopicPrefetchIntent.trajectory;
      if (!next.ready) {
        _timer = Timer(hoverDelay, () {
          _timer = null;
          if (!identical(_candidate, next)) return;
          next.ready = true;
          _drain();
        });
      }
    }
    _hoverOwner = owner;
    _drain();
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
    entry.adopted = true;
    _trace(entry, 'adopted');
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
    final entry = _candidate;
    if (entry != null) {
      if (entry.started && entry.completedAt == null) {
        _trace(entry, 'cancelled');
      } else if (entry.hasResult) {
        _trace(entry, 'unused');
      }
      entry.discarded = true;
      entry.cancellation.cancel();
    }
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
    entry.startedAt = _clock();
    _trace(entry, 'started');
    _active = entry;
    unawaited(_load(entry));
  }

  Future<void> _load(_Prefetch entry) async {
    PrefetchedTopic? result;
    try {
      result = await entry.load(entry.cancellation);
    } catch (_) {
      // Speculative errors are silent. A click retries through normal topic loading.
    } finally {
      if (entry.cancellation.isCancelled) result = null;
      entry.completedAt = _clock();
      entry.hasResult = result != null;
      if (!entry.discarded) {
        _trace(entry, result == null ? 'failed' : 'ready');
      }
      entry.result.complete(result);
      if (result == null && identical(_candidate, entry)) _discardCandidate();
      _active = null;
      _drain();
    }
  }

  void _trace(_Prefetch entry, String event) {
    if (!TopicPrefetchTrace.enabled) return;
    TopicPrefetchTrace.record(event, {
      'request': entry.traceId,
      'intent': entry.intent.name,
      'elapsedMs': entry.startedAt == null
          ? 0
          : _clock().difference(entry.startedAt!).inMilliseconds,
      'completed': entry.completedAt != null,
      'adopted': entry.adopted,
    });
  }

  /// Used when the window closes or the account session is retired, including
  /// cancellation of a request already adopted by navigation.
  void clear() {
    _discardCandidate();
    final active = _active;
    if (active != null && !active.discarded) {
      _trace(active, 'cancelled');
      active.discarded = true;
      active.cancellation.cancel();
    }
  }
}

final class _Prefetch {
  _Prefetch(this.key, this.load, this.isCurrent, this.intent);

  final TopicPrefetchKey key;
  final TopicPrefetchIntent intent;
  final traceId = TopicPrefetchTrace.nextId();
  DateTime? startedAt;
  bool adopted = false;
  bool discarded = false;
  bool hasResult = false;
  final TopicPrefetchLoader load;
  final bool Function() isCurrent;
  final cancellation = TopicPrefetchCancellation();
  final result = Completer<PrefetchedTopic?>();
  bool ready = false;
  bool started = false;
  DateTime? completedAt;
}
