import 'dart:async';
import 'dart:io';

/// Each codec owns a lane; cancelling a waiter cannot bypass its predecessor.
class ComposerMediaPreparationLane {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>({
    required Future<void> aborted,
    required T cancelled,
    required Future<T> Function() action,
  }) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = previous.then((_) => done.future);
    var wasCancelled = false;
    final cancellation = aborted.then((_) => wasCancelled = true);
    try {
      final admitted = await Future.any<bool>([
        previous.then((_) => true),
        cancellation.then((_) => false),
      ]);
      if (!admitted || wasCancelled) return cancelled;
      return await action();
    } finally {
      done.complete();
    }
  }
}

/// Copies one source chunk at a time, verifying its declared length before use.
/// The caller owns [input] and removes it when preparation fails.
Future<bool> stageComposerMedia({
  required Stream<List<int>> source,
  required File input,
  required int length,
  required int maximumBytes,
  required Future<void> aborted,
  required Duration timeout,
}) async {
  if (length < 0 || length > maximumBytes) return false;
  final elapsed = Stopwatch()..start();
  Duration remaining() {
    final budget = timeout - elapsed.elapsed;
    if (budget <= Duration.zero) {
      throw TimeoutException('Media staging deadline exceeded', timeout);
    }
    return budget;
  }

  var cancelled = false;
  final cancellation = aborted.then((_) => cancelled = true);
  final iterator = StreamIterator(source);
  RandomAccessFile? sink;
  Future<RandomAccessFile>? writing;
  try {
    sink = await input.open(mode: FileMode.write);
    var copied = 0;
    while (await Future.any<bool>([
      iterator.moveNext(),
      cancellation.then((_) => false),
    ]).timeout(remaining())) {
      if (cancelled) return false;
      final chunk = iterator.current;
      copied += chunk.length;
      if (copied > length) return false;
      for (var start = 0; start < chunk.length; start += 64 * 1024) {
        if (cancelled) return false;
        final end = (start + 64 * 1024).clamp(0, chunk.length);
        writing = sink.writeFrom(chunk, start, end);
        final written = await Future.any<bool>([
          writing.then((_) => true),
          cancellation.then((_) => false),
        ]).timeout(remaining());
        if (!written || cancelled) return false;
        writing = null;
      }
    }
    return !cancelled && copied == length;
  } finally {
    try {
      // A timeout cannot cancel a filesystem write. Keep ownership until it
      // settles, so closing or deleting the input cannot race that writer.
      if (writing != null) await writing;
    } finally {
      try {
        await iterator.cancel().timeout(timeout);
      } finally {
        await sink?.close();
      }
    }
  }
}
