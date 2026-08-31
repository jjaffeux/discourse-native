import 'dart:async';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 31, 12);

  group('DiagnosticsJournal', () {
    test('orders by sequence and ID while replacing an ID exactly once', () {
      final journal = DiagnosticsJournal(sizeOf: (_) => 99);
      journal
        ..put(_event('z', 3, now), serializedBytes: 30)
        ..put(_event('b', 2, now), serializedBytes: 20)
        ..put(_event('a', 2, now), serializedBytes: 10)
        ..put(_event('z', 1, now), serializedBytes: 7);

      expect(journal.events.map((event) => event.id), ['z', 'a', 'b']);
      expect(journal.eventById('z')?.sequence, 1);
      expect(journal.totalSerializedBytes, 37);
      expect(journal.serializedBytesFor('z'), 7);
    });

    test('restores premeasured serialized bytes without measuring again', () {
      final source = DiagnosticsJournal(sizeOf: (_) => 99)
        ..put(_event('one', 1, now), serializedBytes: 11)
        ..put(_event('two', 2, now), serializedBytes: 13)
        ..setLastSeenSequence(2);
      var measurements = 0;

      final restored = DiagnosticsJournal.fromSnapshot(
        source.snapshot(),
        sizeOf: (_) {
          measurements += 1;
          return 100;
        },
      );

      expect(measurements, 0);
      expect(restored.totalSerializedBytes, 24);
      expect(restored.lastSeenSequence, 2);
    });

    test('applies age and count retention to the canonical order', () {
      final journal = DiagnosticsJournal(sizeOf: (_) => 1)
        ..put(_event('expired', 0, now.subtract(diagnosticsRetentionAge)));
      for (
        var sequence = 1;
        sequence <= diagnosticsRetentionCount + 2;
        sequence += 1
      ) {
        journal.put(_event('event-$sequence', sequence, now));
      }

      final retention = journal.retain(nowUtc: now);

      expect(retention.evicted, isTrue);
      expect(journal.events, hasLength(diagnosticsRetentionCount));
      expect(journal.events.first.id, 'event-3');
      expect(journal.events.last.id, 'event-5002');
      expect(
        retention.evictedEvents.map((event) => event.id),
        contains('expired'),
      );
    });

    test(
      'drops oversized entries then retains the newest byte-bounded suffix',
      () {
        final journal = DiagnosticsJournal(sizeOf: (_) => 1)
          ..put(_event('old-small', 1, now), serializedBytes: 4)
          ..put(
            _event('oversized', 2, now),
            serializedBytes: diagnosticsEventBudgetBytes + 1,
          )
          ..put(
            _event('new-large', 3, now),
            serializedBytes: diagnosticsEventBudgetBytes - 5,
          );

        journal.retain(nowUtc: now);
        expect(journal.events.map((event) => event.id), [
          'old-small',
          'new-large',
        ]);
        expect(journal.totalSerializedBytes, diagnosticsEventBudgetBytes - 1);

        journal
          ..put(_event('newest', 4, now), serializedBytes: 10)
          ..retain(nowUtc: now);

        expect(journal.events.map((event) => event.id), ['newest']);
        expect(journal.totalSerializedBytes, 10);
      },
    );

    test('rebases unseen errors on replacement, retention, and last-seen', () {
      final journal = DiagnosticsJournal(sizeOf: (_) => 1, lastSeenSequence: 1)
        ..put(_error('first', 2, now))
        ..put(_error('second', 3, now))
        ..put(_event('ordinary', 4, now));
      expect(journal.unseenErrorCount, 2);

      expect(journal.markErrorsSeen(), 3);
      expect(journal.unseenErrorCount, 0);

      journal.put(_error('first', 5, now));
      expect(journal.unseenErrorCount, 1);

      journal.setLastSeenSequence(5);
      expect(journal.unseenErrorCount, 0);

      journal.put(_error('expired', 6, now.subtract(diagnosticsRetentionAge)));
      expect(journal.unseenErrorCount, 1);
      journal.retain(nowUtc: now);
      expect(journal.unseenErrorCount, 0);
      expect(journal.maximumSequence, 5);
    });
  });

  test(
    'DiagnosticsJournalOperationQueue preserves order and recovers after failure',
    () async {
      final queue = DiagnosticsJournalOperationQueue();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final order = <String>[];

      final first = queue.run(() async {
        order.add('first-start');
        firstStarted.complete();
        await releaseFirst.future;
        order.add('first-end');
        throw StateError('expected failure');
      });
      final second = queue.run(() async => order.add('second'));

      await firstStarted.future;
      expect(order, ['first-start']);
      releaseFirst.complete();
      await expectLater(first, throwsA(isA<StateError>()));
      await second;
      await queue.done;

      expect(order, ['first-start', 'first-end', 'second']);
    },
  );
}

DiagnosticSessionEvent _event(String id, int sequence, DateTime at) =>
    DiagnosticSessionEvent(
      id: id,
      sessionId: 'session',
      sequence: sequence,
      timestampUtc: at,
      updatedAtUtc: at,
      state: DiagnosticSessionState.started,
    );

ErrorDiagnosticEvent _error(String id, int sequence, DateTime at) =>
    ErrorDiagnosticEvent(
      id: id,
      sessionId: 'session',
      sequence: sequence,
      timestampUtc: at,
      updatedAtUtc: at,
      source: 'test',
      handled: true,
      degraded: true,
      errorType: 'StateError',
      message: 'failure',
      stackTrace: '#0 test',
    );
