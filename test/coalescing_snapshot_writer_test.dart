import 'dart:async';

import 'package:discourse_native/src/data/coalescing_snapshot_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a superseded save waits for the newer snapshot to be durable',
    () async {
      final owner = Object();
      final blockerStarted = Completer<void>();
      final releaseBlocker = Completer<void>();
      final replacementStarted = Completer<void>();
      final releaseReplacement = Completer<void>();
      String? durableSnapshot;

      final blocker = CoalescingSnapshotWriter<String>(
        owner: owner,
        key: 'snapshot',
        writeSnapshot: (value) async {
          blockerStarted.complete();
          await releaseBlocker.future;
          durableSnapshot = value;
        },
      );
      final writer = CoalescingSnapshotWriter<String>(
        owner: owner,
        key: 'snapshot',
        writeSnapshot: (value) async {
          replacementStarted.complete();
          await releaseReplacement.future;
          durableSnapshot = value;
        },
      );

      final blockerSave = blocker.save('blocker');
      await blockerStarted.future;
      final supersededSave = writer.save('superseded');
      var supersededSaveCompleted = false;
      unawaited(
        supersededSave.whenComplete(() => supersededSaveCompleted = true),
      );
      final replacementSave = writer.save('replacement');
      expect(replacementSave, same(supersededSave));

      releaseBlocker.complete();
      await blockerSave;
      await replacementStarted.future;
      await Future<void>.delayed(Duration.zero);

      expect(supersededSaveCompleted, isFalse);
      expect(durableSnapshot, 'blocker');

      releaseReplacement.complete();
      await Future.wait([supersededSave, replacementSave]);
      expect(durableSnapshot, 'replacement');
    },
  );

  test('an already queued save writes before a newer pending save', () async {
    final owner = Object();
    final readStarted = Completer<void>();
    final releaseRead = Completer<void>();
    final firstPhysicalWrite = Completer<String>();
    final releaseFirstWrite = Completer<void>();
    final writes = <String>[];
    String? durableSnapshot;

    final writer = CoalescingSnapshotWriter<String>(
      owner: owner,
      key: 'snapshot',
      writeSnapshot: (value) async {
        writes.add(value);
        if (!firstPhysicalWrite.isCompleted) {
          firstPhysicalWrite.complete(value);
        }
        if (value == 'first') await releaseFirstWrite.future;
        durableSnapshot = value;
      },
    );

    final blockingRead = writer.read<void>(() async {
      readStarted.complete();
      await releaseRead.future;
    });
    await readStarted.future;

    final firstSave = writer.save('first');
    var firstSaveCompleted = false;
    unawaited(firstSave.whenComplete(() => firstSaveCompleted = true));
    final secondSave = writer.save('second');
    expect(secondSave, isNot(same(firstSave)));

    releaseRead.complete();
    await blockingRead;
    expect(await firstPhysicalWrite.future, 'first');
    await Future<void>.delayed(Duration.zero);

    expect(firstSaveCompleted, isFalse);
    expect(durableSnapshot, isNull);

    releaseFirstWrite.complete();
    await firstSave;
    expect(durableSnapshot, 'first');

    await secondSave;
    expect(writes, ['first', 'second']);
    expect(durableSnapshot, 'second');
  });

  test(
    'a failed replacement fails its coalesced older pending snapshot',
    () async {
      final owner = Object();
      final firstWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      final writes = <String>[];
      String? durableSnapshot;

      final oldWriter = CoalescingSnapshotWriter<String>(
        owner: owner,
        key: 'snapshot',
        writeSnapshot: (value) async {
          writes.add(value);
          if (value == 'in-flight') {
            firstWriteStarted.complete();
            await releaseFirstWrite.future;
          }
          durableSnapshot = value;
        },
      );
      final replacementFailure = StateError('disk unavailable');
      final replacementWriter = CoalescingSnapshotWriter<String>(
        owner: owner,
        key: 'snapshot',
        writeSnapshot: (value) async {
          writes.add(value);
          throw replacementFailure;
        },
      );

      final inFlightSave = oldWriter.save('in-flight');
      await firstWriteStarted.future;
      final staleSave = oldWriter.save('stale-pending');
      final replacementSave = replacementWriter.save('replacement');
      final replacementError = expectLater(
        replacementSave,
        throwsA(same(replacementFailure)),
      );
      expect(staleSave, same(replacementSave));
      final loading = oldWriter.read(() async => durableSnapshot);

      await Future<void>.delayed(Duration.zero);
      expect(writes, ['in-flight']);

      releaseFirstWrite.complete();
      await inFlightSave;
      await replacementError;

      expect(writes, ['in-flight', 'replacement']);
      expect(await loading, 'in-flight');
    },
  );

  test(
    'a replacement persists after the older in-flight write fails',
    () async {
      final owner = Object();
      final firstWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      final writes = <String>[];
      String? durableSnapshot;
      final oldFailure = StateError('old disk write failed');

      final oldWriter = CoalescingSnapshotWriter<String>(
        owner: owner,
        key: 'snapshot',
        writeSnapshot: (value) async {
          writes.add(value);
          firstWriteStarted.complete();
          await releaseFirstWrite.future;
          throw oldFailure;
        },
      );
      final replacementWriter = CoalescingSnapshotWriter<String>(
        owner: owner,
        key: 'snapshot',
        writeSnapshot: (value) async {
          writes.add(value);
          durableSnapshot = value;
        },
      );

      final inFlightSave = oldWriter.save('in-flight');
      final inFlightError = expectLater(
        inFlightSave,
        throwsA(same(oldFailure)),
      );
      await firstWriteStarted.future;
      final staleSave = oldWriter.save('stale-pending');
      final replacementSave = replacementWriter.save('replacement');
      final loading = replacementWriter.read(() async => durableSnapshot);

      await Future<void>.delayed(Duration.zero);
      expect(writes, ['in-flight']);

      releaseFirstWrite.complete();
      await inFlightError;
      await Future.wait([staleSave, replacementSave]);

      expect(writes, ['in-flight', 'replacement']);
      expect(await loading, 'replacement');
    },
  );
}
