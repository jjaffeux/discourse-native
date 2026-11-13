import 'dart:async';
import 'dart:io';

import '../foundation/private_file_permissions.dart';

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
  final deadlineError = TimeoutException(
    'Media staging deadline exceeded',
    timeout,
  );
  var timedOut = false;

  var cancelled = false;
  (Object, StackTrace)? abortFailure;
  Completer<bool>? waiting;
  unawaited(
    aborted.then<void>(
      (_) {
        cancelled = true;
        final step = waiting;
        if (step != null && !step.isCompleted) step.complete(false);
      },
      onError: (Object error, StackTrace stack) {
        abortFailure = (error, stack);
        final step = waiting;
        if (step != null && !step.isCompleted) step.completeError(error, stack);
      },
    ),
  );

  bool canStartStep() {
    if (abortFailure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
    if (cancelled) return false;
    if (timedOut || elapsed.elapsed >= timeout) throw deadlineError;
    return true;
  }

  Future<bool> waitForStep(Future<bool> Function() start) async {
    if (!canStartStep()) return false;
    final step = Completer<bool>();
    waiting = step;
    unawaited(
      Future<bool>.sync(start).then<void>(
        (value) {
          if (!step.isCompleted) step.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!step.isCompleted) step.completeError(error, stack);
        },
      ),
    );
    try {
      return await step.future;
    } finally {
      waiting = null;
    }
  }

  final iterator = StreamIterator(source);
  RandomAccessFile? sink;
  Future<RandomAccessFile>? writing;
  var stagingFailed = false;
  final deadline = Timer(timeout, () {
    timedOut = true;
    final step = waiting;
    if (step != null && !step.isCompleted) step.completeError(deadlineError);
  });
  try {
    if (!canStartStep()) return false;
    await ensurePrivateFile(input);
    if (!canStartStep()) return false;
    sink = await input.open(mode: FileMode.write);
    var copied = 0;
    while (await waitForStep(iterator.moveNext)) {
      if (cancelled) return false;
      final chunk = iterator.current;
      copied += chunk.length;
      if (copied > length) return false;
      for (var start = 0; start < chunk.length; start += 64 * 1024) {
        if (cancelled) return false;
        final end = (start + 64 * 1024).clamp(0, chunk.length);
        final written = await waitForStep(() {
          final pending = sink!.writeFrom(chunk, start, end);
          writing = pending;
          return pending.then((_) => true);
        });
        if (!written || cancelled) return false;
        writing = null;
      }
    }
    if (!cancelled && (timedOut || elapsed.elapsed >= timeout)) {
      throw deadlineError;
    }
    return !cancelled && copied == length;
  } on Object {
    stagingFailed = true;
    rethrow;
  } finally {
    deadline.cancel();
    try {
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
    } on Object {
      if (!stagingFailed) rethrow;
    }
  }
}
