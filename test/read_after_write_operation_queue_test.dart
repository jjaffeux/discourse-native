import 'dart:async';

import 'package:discourse_native/src/data/serial_operation_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an idle read never delays a later write', () async {
    final queue = ReadAfterWriteOperationQueue();
    final owner = Object();
    final finishRead = Completer<void>();
    final read = queue.read<void>(
      owner: owner,
      key: 'forum',
      operation: () => finishRead.future,
    );

    var wrote = false;
    await queue.write<void>(
      owner: owner,
      key: 'forum',
      operation: () async => wrote = true,
    );

    expect(wrote, isTrue);
    finishRead.complete();
    await read;
  });

  test('a read accepted after writes observes all of them in order', () async {
    final queue = ReadAfterWriteOperationQueue();
    final owner = Object();
    final firstStarted = Completer<void>();
    final finishFirst = Completer<void>();
    var value = 0;

    final first = queue.write<void>(
      owner: owner,
      key: 'forum',
      operation: () async {
        firstStarted.complete();
        await finishFirst.future;
        value = 1;
      },
    );
    await firstStarted.future;
    final second = queue.write<void>(
      owner: owner,
      key: 'forum',
      operation: () async => value = 2,
    );
    final read = queue.read<int>(
      owner: owner,
      key: 'forum',
      operation: () async => value,
    );

    var readCompleted = false;
    unawaited(read.then<void>((_) => readCompleted = true));
    await Future<void>.delayed(Duration.zero);
    expect(readCompleted, isFalse);

    finishFirst.complete();
    await Future.wait([first, second]);
    expect(await read, 2);
  });

  test(
    'a failed write clears the barrier and does not poison the lane',
    () async {
      final queue = ReadAfterWriteOperationQueue();
      final owner = Object();

      await expectLater(
        queue.write<void>(
          owner: owner,
          key: 'forum',
          operation: () async => throw StateError('failed'),
        ),
        throwsStateError,
      );

      expect(
        await queue.read<int>(
          owner: owner,
          key: 'forum',
          operation: () async => 3,
        ),
        3,
      );
      expect(
        await queue.write<int>(
          owner: owner,
          key: 'forum',
          operation: () async => 4,
        ),
        4,
      );
    },
  );

  test('different keys and owners remain independent', () async {
    final queue = ReadAfterWriteOperationQueue();
    final firstOwner = Object();
    final secondOwner = Object();
    final finishBlocked = Completer<void>();
    final blocked = queue.write<void>(
      owner: firstOwner,
      key: 'forum',
      operation: () => finishBlocked.future,
    );

    expect(
      await queue.read<int>(
        owner: firstOwner,
        key: 'another-forum',
        operation: () async => 1,
      ),
      1,
    );
    expect(
      await queue.read<int>(
        owner: secondOwner,
        key: 'forum',
        operation: () async => 2,
      ),
      2,
    );

    finishBlocked.complete();
    await blocked;
  });
}
