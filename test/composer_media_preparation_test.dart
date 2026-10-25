import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/composer_media_preparation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> never() => Completer<void>().future;

  test(
    'cancelled waiters retain the active predecessor and queue order',
    () async {
      final lane = ComposerMediaPreparationLane();
      final started = Completer<void>();
      final finish = Completer<void>();
      final calls = <int>[];
      final first = lane.run(
        aborted: never(),
        cancelled: 0,
        action: () async {
          calls.add(1);
          started.complete();
          await finish.future;
          return 1;
        },
      );
      await started.future;
      final abort = Completer<void>();
      final second = lane.run(
        aborted: abort.future,
        cancelled: 0,
        action: () async => calls..add(2),
      );
      final third = lane.run(
        aborted: never(),
        cancelled: 0,
        action: () async => calls..add(3),
      );
      abort.complete();
      expect(await second, 0);
      await pumpEventQueue();
      expect(calls, [1]);
      finish.complete();
      await first;
      await third;
      expect(calls, [1, 3]);
    },
  );

  test('already cancelled admission never invokes the action', () async {
    final lane = ComposerMediaPreparationLane();
    final abort = Future<void>.value();
    await abort;
    final result = await lane.run(
      aborted: abort,
      cancelled: false,
      action: () async => throw StateError('Must not run'),
    );
    expect(result, isFalse);
  });

  test(
    'action failures release the lane and lanes run independently',
    () async {
      final firstLane = ComposerMediaPreparationLane();
      final secondLane = ComposerMediaPreparationLane();
      final started = Completer<void>();
      final finish = Completer<void>();
      final failed = firstLane.run(
        aborted: never(),
        cancelled: false,
        action: () async {
          started.complete();
          await finish.future;
          throw StateError('encoder failed');
        },
      );
      final failure = expectLater(failed, throwsStateError);
      await started.future;
      expect(
        await secondLane.run(
          aborted: never(),
          cancelled: false,
          action: () async => true,
        ),
        isTrue,
      );
      finish.complete();
      await failure;
      expect(
        await firstLane.run(
          aborted: never(),
          cancelled: false,
          action: () async => true,
        ),
        isTrue,
      );
    },
  );

  group('staging', () {
    late Directory temporary;
    late File input;
    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('media-staging-test-');
      input = File('${temporary.path}/source');
    });
    tearDown(() async => temporary.delete(recursive: true));

    Future<bool> stage(
      Stream<List<int>> source, {
      int length = 3,
      int maximumBytes = 10,
      Future<void>? aborted,
      Duration timeout = const Duration(seconds: 1),
      File? destination,
    }) => stageComposerMedia(
      source: source,
      input: destination ?? input,
      length: length,
      maximumBytes: maximumBytes,
      aborted: aborted ?? never(),
      timeout: timeout,
    );

    test('streams exact bytes into a closed reusable file', () async {
      expect(
        await stage(
          Stream.fromIterable([
            [1],
            [2, 3],
          ]),
        ),
        isTrue,
      );
      expect(await input.readAsBytes(), [1, 2, 3]);
      await input.delete();
    });

    for (final length in [2, 4]) {
      test('rejects a mismatched declared length $length', () async {
        expect(await stage(Stream.value([1, 2, 3]), length: length), isFalse);
      });
    }

    test('rejects an oversized source before reading it', () async {
      final writer = _Writer();
      expect(
        await stage(
          Stream.value(List.filled(11, 1)),
          length: 11,
          destination: _Destination(writer),
        ),
        isFalse,
      );
      expect(writer.writes, isEmpty);
    });

    test('source errors close the destination', () async {
      final writer = _Writer();
      await expectLater(
        stage(
          Stream.error(StateError('source failed')),
          destination: _Destination(writer),
        ),
        throwsStateError,
      );
      expect(writer.closed, isTrue);
    });

    test('stalled source times out and detaches its subscription', () async {
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(onCancel: cancelled.complete);
      await expectLater(
        stage(source.stream, timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      await cancelled.future;
      await source.close();
      await input.delete();
    });

    test('empty chunks cannot extend the staging deadline', () async {
      Stream<List<int>> source() async* {
        while (true) {
          await Future<void>.delayed(Duration.zero);
          yield [];
        }
      }

      await expectLater(
        stage(source(), timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      await input.delete();
    });

    test('source cancellation timeout still closes the destination', () async {
      final listened = Completer<void>();
      final onCancel = Completer<void>();
      final source = StreamController<List<int>>(
        onListen: listened.complete,
        onCancel: () => onCancel.future,
      );
      final abort = Completer<void>();
      final writer = _Writer();
      final pending = stage(
        source.stream,
        aborted: abort.future,
        timeout: const Duration(milliseconds: 10),
        destination: _Destination(writer),
      );
      final assertion = expectLater(pending, throwsA(isA<TimeoutException>()));
      await listened.future;
      abort.complete();
      await assertion;
      expect(writer.closed, isTrue);
      onCancel.complete();
      await source.close();
    });

    test('writes are bounded and source waits for each write', () async {
      final writer = _Writer();
      final gate = Completer<void>();
      writer.writeGate = gate.future;
      var requestedNext = false;
      Stream<List<int>> source() async* {
        yield List.filled(128 * 1024 + 1, 1);
        requestedNext = true;
        yield [2];
      }

      final pending = stage(
        source(),
        length: 128 * 1024 + 2,
        maximumBytes: 1024 * 1024,
        destination: _Destination(writer),
      );
      await writer.started.future;
      await pumpEventQueue();
      expect(requestedNext, isFalse);
      expect(writer.writes, [64 * 1024]);
      gate.complete();
      expect(await pending, isTrue);
      expect(writer.writes, [64 * 1024, 64 * 1024, 1, 1]);
      expect(writer.closed, isTrue);
    });

    for (final cancel in [true, false]) {
      test(
        '${cancel ? 'cancellation' : 'timeout'} drains a pending write before releasing the lane',
        () async {
          final lane = ComposerMediaPreparationLane();
          final writer = _Writer();
          final gate = Completer<void>();
          writer.writeGate = gate.future;
          final abort = Completer<void>();
          final timedOut = Completer<void>();
          var returned = false;
          var nextStarted = false;
          final pending = lane.run(
            aborted: abort.future,
            cancelled: false,
            action: () => stage(
              Stream.fromIterable([
                [1],
                [2, 3],
              ]),
              destination: _Destination(writer),
              aborted: abort.future,
              timeout: const Duration(milliseconds: 20),
            ),
          );
          final assertion = cancel
              ? expectLater(pending, completion(isFalse))
              : expectLater(pending, throwsA(isA<TimeoutException>()));
          unawaited(
            pending.then<void>(
              (_) => returned = true,
              onError: (Object _) {
                returned = true;
              },
            ),
          );
          await writer.started.future;
          final next = lane.run(
            aborted: never(),
            cancelled: false,
            action: () async => nextStarted = true,
          );
          if (cancel) {
            abort.complete();
            await pumpEventQueue();
          } else {
            Timer(const Duration(milliseconds: 40), timedOut.complete);
            await timedOut.future;
          }
          expect(returned, isFalse);
          expect(writer.closed, isFalse);
          expect(nextStarted, isFalse);
          gate.complete();
          await assertion;
          await next;
          expect(writer.writes, [1]);
          expect(writer.closed, isTrue);
          expect(nextStarted, isTrue);
        },
      );
    }
  });
}

class _Destination implements File {
  _Destination(this.writer);
  final _Writer writer;
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      writer;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Writer implements RandomAccessFile {
  final started = Completer<void>();
  final writes = <int>[];
  Future<void>? writeGate;
  bool closed = false;
  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    expect(closed, isFalse);
    writes.add((end ?? buffer.length) - start);
    if (!started.isCompleted) started.complete();
    await writeGate;
    expect(closed, isFalse);
    return this;
  }

  @override
  Future<void> close() async => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
