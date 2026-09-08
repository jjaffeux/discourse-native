import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late File file;
  late DateTime now;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'discourse-native-diagnostics-',
    );
    file = File('${temporaryDirectory.path}/nested/diagnostics-v1.jsonl');
    now = DateTime.utc(2026, 8, 8, 10);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('file loading', () {
    test(
      'folds JSONL lifecycle updates by event ID and restores last-seen sequence',
      () async {
        final persistence = FileDiagnosticsPersistence(file);
        final pending = _request(
          id: 'request-1',
          sequence: 1,
          at: now,
          state: DiagnosticHttpState.pending,
        );
        final completed = pending.copyWith(
          sequence: 2,
          updatedAtUtc: now.add(const Duration(seconds: 1)),
          state: DiagnosticHttpState.completed,
          statusCode: 200,
          totalDuration: const Duration(seconds: 1),
          receivedBytes: 42,
        );
        await persistence.appendEvents([pending], nowUtc: now);
        await persistence.appendEvents([completed], nowUtc: now);
        await persistence.writeLastSeenSequence(2);
        await persistence.close();

        final reloaded = await FileDiagnosticsPersistence(
          file,
        ).load(nowUtc: now);

        expect(reloaded.events, hasLength(1));
        final event = reloaded.events.single as HttpDiagnosticEvent;
        expect(event.id, 'request-1');
        expect(event.sequence, 2);
        expect(event.state, DiagnosticHttpState.completed);
        expect(event.statusCode, 200);
        expect(event.totalDuration, const Duration(seconds: 1));
        expect(event.receivedBytes, 42);
        expect(reloaded.lastSeenSequence, 2);
      },
    );

    test('retains valid records around corrupt and incomplete lines', () async {
      final persistence = FileDiagnosticsPersistence(file);
      await persistence.appendEvents([_error('first', 1, now)], nowUtc: now);
      await persistence.close();
      await file.writeAsString(
        'this is not json\n{"version":1,"record":"event","event":',
        mode: FileMode.append,
      );

      final reloaded = await FileDiagnosticsPersistence(file).load(nowUtc: now);

      expect(reloaded.events.map((event) => event.id), ['first']);
    });

    for (final record in ['lastSeen', 'event']) {
      test(
        'ignores a negative $record sequence beside healthy lines',
        () async {
          await _writeJournalRecords(file, [
            {'record': 'event', 'event': _error('first', 0, now).toJson()},
            {'record': 'lastSeen', 'sequence': 0},
            if (record == 'lastSeen')
              {'record': record, 'sequence': -1}
            else
              {'record': record, 'event': _error('first', -1, now).toJson()},
            {'record': 'event', 'event': _error('second', 1, now).toJson()},
          ]);

          final reloaded = await FileDiagnosticsPersistence(
            file,
          ).load(nowUtc: now);

          expect(reloaded.events.map((event) => event.id), ['first', 'second']);
          expect(reloaded.events.map((event) => event.sequence), [0, 1]);
          expect(reloaded.lastSeenSequence, 0);
        },
      );
    }

    test(
      'rebases excessive sequences with ties and the seen boundary intact',
      () async {
        const highSequence = 0x7ffffffffffffffd;
        await _writeJournalRecords(file, [
          {'record': 'event', 'event': _error('low', 12, now).toJson()},
          {'record': 'event', 'event': _error('b', highSequence, now).toJson()},
          {'record': 'event', 'event': _error('a', highSequence, now).toJson()},
          {'record': 'lastSeen', 'sequence': highSequence + 1},
          {
            'record': 'event',
            'event': _error('unseen', highSequence + 2, now).toJson(),
          },
        ]);

        final persistence = FileDiagnosticsPersistence(file);
        final reloaded = await persistence.load(nowUtc: now);
        await persistence.close();

        expect(reloaded.events.map((event) => event.id), [
          'low',
          'a',
          'b',
          'unseen',
        ]);
        expect(reloaded.events.map((event) => event.sequence), [1, 2, 2, 3]);
        expect(reloaded.lastSeenSequence, 2);
        for (final event in reloaded.events) {
          expect(
            reloaded.serializedEventBytes[event.id],
            diagnosticEventSerializedBytes(event),
          );
        }
        expect(await file.readAsString(), isNot(contains('$highSequence')));
        final again = await FileDiagnosticsPersistence(file).load(nowUtc: now);
        expect(
          again.events.map((event) => event.toJson()),
          reloaded.events.map((event) => event.toJson()),
        );
        expect(again.lastSeenSequence, reloaded.lastSeenSequence);
      },
    );

    test('keeps a subsequent event separate from an unterminated tail', () async {
      final persistence = FileDiagnosticsPersistence(file);
      await persistence.appendEvents([_error('first', 1, now)], nowUtc: now);
      await persistence.close();
      // What a kill mid-write leaves behind: a record with no newline after it.
      await file.writeAsString(
        '{"version":1,"record":"event","event":',
        mode: FileMode.append,
      );

      final next = FileDiagnosticsPersistence(file);
      await next.load(nowUtc: now);
      await next.appendEvents([_error('second', 2, now)], nowUtc: now);
      await next.close();

      // Appended onto the fragment, the new record would be spliced into an
      // unparseable line and lost with it — and the file would stay a line out
      // of step for every write after that.
      final reloaded = await FileDiagnosticsPersistence(file).load(nowUtc: now);
      expect(reloaded.events.map((event) => event.id), ['first', 'second']);
    });

    test('skips an oversized corrupt line and compacts it away', () async {
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      addTearDown(sink.close);
      final chunk = List<int>.filled(256 * 1024, 0x78);
      var corruptBytes = 0;
      while (corruptBytes <= diagnosticsRetentionBytes) {
        sink.add(chunk);
        corruptBytes += chunk.length;
      }
      sink
        ..writeln()
        ..add([0xff, 0x0a])
        ..writeln(
          jsonEncode({
            'version': FileDiagnosticsPersistence.formatVersion,
            'record': 'event',
            'event': _error('after-corruption', 1, now).toJson(),
          }),
        );
      await sink.close();

      final reloaded = await FileDiagnosticsPersistence(file).load(nowUtc: now);

      expect(reloaded.events.map((event) => event.id), ['after-corruption']);
      expect(await file.length(), lessThan(diagnosticsRetentionBytes));
      expect(await file.readAsString(), isNot(contains('xxxxxxxx')));
    });

    test('incrementally retains the newest bounded event set', () async {
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      addTearDown(sink.close);
      for (
        var sequence = 1;
        sequence <= diagnosticsRetentionCount * 2;
        sequence += 1
      ) {
        sink.writeln(
          jsonEncode({
            'version': FileDiagnosticsPersistence.formatVersion,
            'record': 'event',
            'event': _error('event-$sequence', sequence, now).toJson(),
          }),
        );
      }
      await sink.close();

      final reloaded = await FileDiagnosticsPersistence(file).load(nowUtc: now);

      expect(reloaded.events, hasLength(diagnosticsRetentionCount));
      expect(reloaded.events.first.id, 'event-5001');
      expect(reloaded.events.last.id, 'event-10000');
      final compacted = await file.readAsString();
      expect(compacted, isNot(contains('"id":"event-1"')));
      expect(compacted, contains('"id":"event-10000"'));
    });
  });

  group('journal adapter contract', () {
    test(
      'memory and file decoding produce the same replacement, order, sizes, and last-seen state',
      () async {
        final memory = MemoryDiagnosticsPersistence();
        final disk = FileDiagnosticsPersistence(file);
        addTearDown(memory.close);
        addTearDown(disk.close);
        final stale = _error('stale', 0, now.subtract(diagnosticsRetentionAge));
        final pending = _request(
          id: 'request',
          sequence: 5,
          at: now,
          state: DiagnosticHttpState.pending,
        );
        final completed = pending.copyWith(
          sequence: 2,
          updatedAtUtc: now.add(const Duration(seconds: 1)),
          state: DiagnosticHttpState.completed,
          statusCode: 204,
        );
        final batches = [
          [_error('z', 3, now), _error('a', 3, now), pending, stale],
          [completed],
        ];

        for (final persistence in <DiagnosticsPersistence>[memory, disk]) {
          for (final batch in batches) {
            await persistence.appendEvents(batch, nowUtc: now);
          }
          final firstSeen = persistence.writeLastSeenSequence(5);
          final lastSeen = persistence.writeLastSeenSequence(2);
          await Future.wait([firstSeen, lastSeen]);
        }
        await disk.close();

        final memoryState = await memory.load(nowUtc: now);
        final decodedState = await FileDiagnosticsPersistence(
          file,
        ).load(nowUtc: now);

        expect(decodedState.events.map((event) => event.id), [
          'request',
          'a',
          'z',
        ]);
        expect(
          decodedState.events.map((event) => event.toJson()),
          memoryState.events.map((event) => event.toJson()),
        );
        expect(
          decodedState.serializedEventBytes,
          memoryState.serializedEventBytes,
        );
        expect(decodedState.lastSeenSequence, 2);
        expect(decodedState.lastSeenSequence, memoryState.lastSeenSequence);
      },
    );

    test(
      'a failed file write does not poison the next accepted write',
      () async {
        await Directory(file.path).create(recursive: true);
        final persistence = FileDiagnosticsPersistence(file);

        await expectLater(
          persistence.appendEvents([
            _error('failed-write', 1, now),
          ], nowUtc: now),
          throwsA(isA<FileSystemException>()),
        );
        await Directory(file.path).delete();

        await persistence.appendEvents([
          _error('recovered-write', 2, now),
        ], nowUtc: now);
        await persistence.close();

        final reloaded = await FileDiagnosticsPersistence(
          file,
        ).load(nowUtc: now);
        expect(reloaded.events.map((event) => event.id), ['recovered-write']);
      },
    );
  });

  group('compaction', () {
    test('atomically removes expired records from disk', () async {
      final persistence = FileDiagnosticsPersistence(file);
      final stale = _error(
        'stale-secret-id',
        1,
        now.subtract(const Duration(hours: 25)),
      );
      final fresh = _error('fresh-id', 2, now);
      await persistence.appendEvents([stale], nowUtc: now);
      await persistence.appendEvents([fresh], nowUtc: now);
      await persistence.compact(nowUtc: now);

      final contents = await file.readAsString();
      expect(contents, contains('fresh-id'));
      expect(contents, isNot(contains('stale-secret-id')));
      expect(await File('${file.path}.tmp').exists(), isFalse);

      final lines = const LineSplitter().convert(contents);
      expect(
        lines.every((line) => jsonDecode(line) is Map<String, dynamic>),
        isTrue,
      );
    });

    test("preserves another instance's append from a stale snapshot", () async {
      final first = FileDiagnosticsPersistence(file);
      final second = FileDiagnosticsPersistence(file);
      await Future.wait([first.load(nowUtc: now), second.load(nowUtc: now)]);

      await first.appendEvents([_error('from-first', 1, now)], nowUtc: now);
      await second.appendEvents([_error('from-second', 2, now)], nowUtc: now);

      // `first` still has the snapshot from before `second` appended. Compaction
      // must reconcile the shared file rather than replace it from that snapshot.
      await first.compact(nowUtc: now);

      final reloaded = await FileDiagnosticsPersistence(file).load(nowUtc: now);
      expect(reloaded.events.map((event) => event.id), [
        'from-first',
        'from-second',
      ]);
    });

    test(
      'repairs legacy permissions and keeps compacted history owner-only',
      () async {
        final persistence = FileDiagnosticsPersistence(file);
        await persistence.appendEvents([
          _error('private-history', 1, now),
        ], nowUtc: now);

        await _setMode(file.parent.path, '0755');
        await _setMode(file.path, '0644');

        await FileDiagnosticsPersistence(file).load(nowUtc: now);

        expect((await file.parent.stat()).mode & 0x1ff, 0x1c0); // 0700
        expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
        expect(
          (await File('${file.path}.lock').stat()).mode & 0x1ff,
          0x180,
        ); // 0600

        await persistence.compact(nowUtc: now);

        expect((await file.parent.stat()).mode & 0x1ff, 0x1c0); // 0700
        expect((await file.stat()).mode & 0x1ff, 0x180); // 0600
      },
      skip: Platform.isWindows
          ? 'Windows does not expose POSIX owner-only permission bits.'
          : false,
    );

    test('releases expired event objects from memory persistence', () async {
      final persistence = MemoryDiagnosticsPersistence();
      await persistence.appendEvents([
        _error('memory-expired', 1, now),
      ], nowUtc: now);
      expect(persistence.retainedEventCount, 1);

      await persistence.compact(nowUtc: now.add(diagnosticsRetentionAge));

      expect(persistence.retainedEventCount, 0);
    });

    test('physically removes age-evicted records during append', () async {
      final persistence = FileDiagnosticsPersistence(file);
      final beforeCutoff = now.subtract(const Duration(hours: 25));
      await persistence.appendEvents([
        _error('expired-without-size-pressure', 1, beforeCutoff),
      ], nowUtc: beforeCutoff);
      expect(await file.length(), lessThan(diagnosticsRetentionBytes));

      await persistence.appendEvents([
        _error('fresh-after-expiry', 2, now),
      ], nowUtc: now);

      final contents = await file.readAsString();
      expect(contents, contains('fresh-after-expiry'));
      expect(contents, isNot(contains('expired-without-size-pressure')));
    });

    test('physically removes retention-evicted records during load', () async {
      final persistence = FileDiagnosticsPersistence(file);
      final oldNow = now.subtract(const Duration(hours: 25));
      await persistence.appendEvents([
        _error('expired-on-load', 1, oldNow),
        _error('fresh-on-load', 2, now),
      ], nowUtc: oldNow);
      await persistence.close();

      await FileDiagnosticsPersistence(file).load(nowUtc: now);

      final contents = await file.readAsString();
      expect(contents, contains('fresh-on-load'));
      expect(contents, isNot(contains('expired-on-load')));
    });
  });

  group('retention accounting', () {
    test('applies the 24-hour age and 5,000-event count limits', () {
      final events = [
        _error('expired', 0, now.subtract(const Duration(hours: 25))),
        for (var index = 1; index <= diagnosticsRetentionCount + 5; index += 1)
          _error('event-$index', index, now),
      ];

      final retained = retainDiagnosticEvents(events, nowUtc: now);

      expect(retained, hasLength(diagnosticsRetentionCount));
      expect(retained.first.id, 'event-6');
      expect(retained.last.id, 'event-5005');
      expect(retained.any((event) => event.id == 'expired'), isFalse);
    });

    test('counts UTF-8 bytes and the JSONL newline in event size', () {
      final event = _error('multibyte', 1, now, message: 'café');
      final line = jsonEncode({
        'version': FileDiagnosticsPersistence.formatVersion,
        'record': 'event',
        'event': event.toJson(),
      });

      expect(
        diagnosticEventSerializedBytes(event),
        utf8.encode(line).length + 1,
      );
      expect(utf8.encode(line).length, greaterThan(line.length));
    });

    test('applies the byte budget to premeasured event sizes', () {
      final events = [
        for (var index = 1; index <= 4; index += 1)
          _error('large-$index', index, now),
      ];
      const simulatedEventBytes = diagnosticsEventBudgetBytes ~/ 4 + 1;

      final retained = retainDiagnosticEvents(
        events,
        nowUtc: now,
        bytesOf: (_) => simulatedEventBytes,
      );

      expect(retained.map((event) => event.id), [
        'large-2',
        'large-3',
        'large-4',
      ]);
      expect(
        retained.length * simulatedEventBytes,
        lessThanOrEqualTo(diagnosticsEventBudgetBytes),
      );
      expect(
        (retained.length + 1) * simulatedEventBytes,
        greaterThan(diagnosticsEventBudgetBytes),
      );
    });
  });

  group('persistence cleanup', () {
    test(
      'removes events, the last-seen marker, and backing files on clear',
      () async {
        final persistence = FileDiagnosticsPersistence(file);
        await persistence.appendEvents([_error('event', 1, now)], nowUtc: now);
        await persistence.writeLastSeenSequence(1);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString('sensitive interrupted compaction');

        await persistence.clear();

        expect(await file.exists(), isFalse);
        expect(await temporary.exists(), isFalse);
        final empty = await persistence.load(nowUtc: now);
        expect(empty.events, isEmpty);
        expect(empty.lastSeenSequence, 0);
      },
    );

    test('removes temporary history after failed compaction', () async {
      await Directory(file.path).create(recursive: true);
      final temporary = File('${file.path}.tmp');
      final persistence = FileDiagnosticsPersistence(file);

      await expectLater(
        persistence.compact(nowUtc: now),
        throwsA(isA<FileSystemException>()),
      );

      expect(await temporary.exists(), isFalse);
    });

    test('deletes orphaned compaction history on reload', () async {
      final persistence = FileDiagnosticsPersistence(file);
      await persistence.appendEvents([_error('event', 1, now)], nowUtc: now);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString('stale full history sentinel', flush: true);

      final reloaded = await FileDiagnosticsPersistence(file).load(nowUtc: now);

      expect(reloaded.events.single.id, 'event');
      expect(await temporary.exists(), isFalse);
    });
  });

  group('controller restart recovery', () {
    test(
      'keeps new events that cross the rebase watermark on restart',
      () async {
        const sequence = 0x1fffffffffffff;
        await _writeJournalRecords(file, [
          {
            'record': 'event',
            'event': _error('retained', sequence, now).toJson(),
          },
          {'record': 'lastSeen', 'sequence': sequence},
        ]);
        final first = await DiagnosticsController.create(
          persistence: FileDiagnosticsPersistence(file),
          clock: () => now,
          sessionId: 'before-rebase',
        );
        addTearDown(first.close);
        expect(first.events.first.sequence, sequence);
        first.reportError(StateError('across watermark'), StackTrace.empty);
        expect(first.events.last.sequence, greaterThan(sequence));
        expect(first.unseenErrorCountListenable.value, 1);
        await first.close();

        final second = await DiagnosticsController.create(
          persistence: FileDiagnosticsPersistence(file),
          clock: () => now,
          sessionId: 'after-rebase',
        );
        addTearDown(second.close);
        expect(
          second.events.whereType<ErrorDiagnosticEvent>().map(
            (event) => event.message,
          ),
          ['failure', 'Bad state: across watermark'],
        );
        expect(second.unseenErrorCountListenable.value, 1);
        second.reportError(StateError('after watermark'), StackTrace.empty);
        expect(
          (second.events.last as ErrorDiagnosticEvent).message,
          'Bad state: after watermark',
        );
        expect(second.unseenErrorCountListenable.value, 2);
      },
    );

    test(
      'rebases an excessive seen marker after all history expires',
      () async {
        await _writeJournalRecords(file, [
          {
            'record': 'event',
            'event': _error(
              'expired',
              1,
              now.subtract(diagnosticsRetentionAge),
            ).toJson(),
          },
          {'record': 'lastSeen', 'sequence': 0x7fffffffffffffff},
        ]);
        final controller = await DiagnosticsController.create(
          persistence: FileDiagnosticsPersistence(file),
          clock: () => now,
          sessionId: 'after-expiry',
        );
        addTearDown(controller.close);
        controller.reportError(StateError('after expiry'), StackTrace.empty);
        await controller.flush();

        expect(
          controller.events.any((event) => event.id == 'expired'),
          isFalse,
        );
        expect(controller.events.every((event) => event.sequence > 0), isTrue);
        expect(controller.unseenErrorCountListenable.value, 1);
        expect(await file.readAsString(), isNot(contains('expired')));
      },
    );

    for (final record in ['lastSeen', 'event']) {
      test('recovers an excessive $record sequence across restarts', () async {
        const excessiveSequence = 0x7fffffffffffffff;
        await _writeJournalRecords(file, [
          {
            'record': 'event',
            'event': _error('healthy-before', 10, now).toJson(),
          },
          {'record': 'lastSeen', 'sequence': 10},
          if (record == 'lastSeen')
            {'record': record, 'sequence': excessiveSequence}
          else
            {
              'record': record,
              'event': _error('excessive', excessiveSequence, now).toJson(),
            },
          {
            'record': 'event',
            'event': _error('healthy-after', 20, now).toJson(),
          },
          {
            'record': 'event',
            'event': _request(
              id: 'prior-pending',
              sequence: 15,
              at: now,
              state: DiagnosticHttpState.pending,
            ).toJson(),
          },
        ]);

        final controller = DiagnosticsController.start(
          persistence: FileDiagnosticsPersistence(file),
          clock: () => now,
          sessionId: 'recovering-session',
        );
        addTearDown(controller.close);
        controller.reportError(StateError('startup error'), StackTrace.empty);
        await controller.flush();

        final historyIds = [
          'healthy-before',
          'healthy-after',
          if (record == 'event') 'excessive',
          'prior-pending',
        ];
        final startup = controller.events
            .whereType<ErrorDiagnosticEvent>()
            .singleWhere(
              (event) => event.message == 'Bad state: startup error',
            );
        expect(startup.sequence, greaterThan(0));
        expect(controller.events.last.id, startup.id);
        expect(
          controller.events.take(historyIds.length).map((event) => event.id),
          historyIds,
        );
        expect(controller.events.every((event) => event.sequence > 0), isTrue);
        expect(
          controller.events.whereType<HttpDiagnosticEvent>().single.state,
          DiagnosticHttpState.interrupted,
        );
        expect(
          controller.unseenErrorCountListenable.value,
          record == 'lastSeen' ? 1 : 3,
        );

        controller.markSeen();
        await controller.flush();
        expect(controller.unseenErrorCountListenable.value, 0);
        controller.reportError(StateError('new error'), StackTrace.empty);
        await controller.flush();
        final newest = controller.events.last as ErrorDiagnosticEvent;
        expect(newest.message, 'Bad state: new error');
        expect(newest.sequence, greaterThan(startup.sequence));
        expect(controller.unseenErrorCountListenable.value, 1);
        await controller.close();

        final restarted = await DiagnosticsController.create(
          persistence: FileDiagnosticsPersistence(file),
          clock: () => now,
          sessionId: 'restarted-session',
        );
        addTearDown(restarted.close);
        expect(
          restarted.events.take(historyIds.length).map((event) => event.id),
          historyIds,
        );
        expect(restarted.unseenErrorCountListenable.value, 1);
        restarted.markSeen();
        restarted.reportError(StateError('after restart'), StackTrace.empty);
        await restarted.flush();
        expect(restarted.events.last.sequence, greaterThan(newest.sequence));
        expect(restarted.unseenErrorCountListenable.value, 1);

        await restarted.clear();
        expect(restarted.events, isEmpty);
        expect(restarted.unseenErrorCountListenable.value, 0);
        restarted.reportError(StateError('after clear'), StackTrace.empty);
        await restarted.flush();
        expect(restarted.events.single.sequence, greaterThan(newest.sequence));
        expect(restarted.unseenErrorCountListenable.value, 1);
      });
    }

    test('marks prior pending requests as interrupted', () async {
      final firstPersistence = FileDiagnosticsPersistence(file);
      final first = await DiagnosticsController.create(
        persistence: firstPersistence,
        clock: () => now,
        sessionId: 'first-session',
      );
      first.recordHttp(
        HttpDiagnosticRecord(
          eventId: 'pending-request',
          phase: HttpDiagnosticPhase.started,
          timestamp: now,
          method: 'GET',
          uri: Uri.parse('https://example.com/t/42.json'),
          sentBytes: 0,
          receivedBytes: 0,
        ),
      );
      await first.flush();

      final later = now.add(const Duration(minutes: 3));
      final second = await DiagnosticsController.create(
        persistence: FileDiagnosticsPersistence(file),
        clock: () => later,
        sessionId: 'second-session',
      );
      await second.flush();

      final disk = await FileDiagnosticsPersistence(file).load(nowUtc: later);
      final request = disk.events.whereType<HttpDiagnosticEvent>().singleWhere(
        (event) => event.id == 'pending-request',
      );
      expect(request.state, DiagnosticHttpState.interrupted);
      expect(request.isError, isFalse);
      await second.close();
    });
  });
}

Future<void> _writeJournalRecords(
  File file,
  List<Map<String, Object?>> records,
) async {
  await file.parent.create(recursive: true);
  final lines = [
    for (final record in records)
      jsonEncode({
        'version': FileDiagnosticsPersistence.formatVersion,
        ...record,
      }),
  ];
  await file.writeAsString('${lines.join('\n')}\n');
}

ErrorDiagnosticEvent _error(
  String id,
  int sequence,
  DateTime at, {
  String message = 'failure',
}) => ErrorDiagnosticEvent(
  id: id,
  sessionId: 'session',
  sequence: sequence,
  timestampUtc: at,
  updatedAtUtc: at,
  source: 'test',
  handled: true,
  degraded: true,
  errorType: 'StateError',
  message: message,
  stackTrace: '#0 test',
);

HttpDiagnosticEvent _request({
  required String id,
  required int sequence,
  required DateTime at,
  required DiagnosticHttpState state,
}) => HttpDiagnosticEvent(
  id: id,
  sessionId: 'session',
  sequence: sequence,
  timestampUtc: at,
  updatedAtUtc: at,
  severity: DiagnosticSeverity.info,
  method: 'GET',
  uri: 'https://example.com/t/42.json',
  state: state,
);

Future<void> _setMode(String path, String mode) async {
  final result = await Process.run('chmod', [mode, path]);
  expect(
    result.exitCode,
    0,
    reason: 'chmod $mode $path failed: ${result.stderr}',
  );
}
