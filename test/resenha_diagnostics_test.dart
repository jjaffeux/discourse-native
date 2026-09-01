import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('diagnostic capture', () {
    test(
      'defaults to off, forwards structured logs, and gates raw records',
      () async {
        final now = DateTime.utc(2026, 8, 11, 12);
        final ordinary = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          clock: () => now,
          sessionId: 'ordinary',
        );
        final binding = DiagnosticsSink.install(ordinary);
        final deep = await ResenhaDiagnosticsController.create(
          reporter: PluginDiagnosticsReporter.fixed(ordinary),
          persistence: MemoryResenhaDiagnosticsPersistence(),
          clock: () => now,
          captureIdFactory: () => 'capture-1',
        );
        addTearDown(() async {
          binding.close();
          await deep.close();
          await ordinary.close();
        });

        expect(deep.captureEnabled, isFalse);
        deep.recordRaw('sdk.off', message: 'must not persist');
        deep.record(
          'call.join.requested',
          component: 'controller',
          correlationId: 'call-1',
          data: const {'transport': 'mesh'},
        );

        expect(deep.events, isEmpty);
        final ordinaryLog = ordinary.events
            .whereType<DiagnosticLogEvent>()
            .single;
        expect(ordinaryLog.name, 'call.join.requested');
        expect(ordinaryLog.source, 'resenha');
        expect(ordinaryLog.component, 'controller');
        expect(ordinaryLog.correlationId, 'call-1');

        await deep.startCapture();
        deep.record('call.join.connected', component: 'controller');
        deep.recordRaw('sdk.on', component: 'livekit', message: 'verbose line');
        await deep.stopCapture();

        expect(deep.captureEnabled, isFalse);
        expect(
          deep.events.map((record) => record.event),
          containsAllInOrder([
            'capture.started',
            'call.join.connected',
            'sdk.on',
            'capture.stopped',
          ]),
        );
        expect(
          ordinary.events.whereType<DiagnosticLogEvent>().map(
            (event) => event.name,
          ),
          isNot(contains('sdk.on')),
        );
        final connectedOrdinary = ordinary.events
            .whereType<DiagnosticLogEvent>()
            .singleWhere((event) => event.name == 'call.join.connected');
        final connectedDeep = deep.events.singleWhere(
          (event) => event.event == 'call.join.connected',
        );
        expect(
          connectedDeep.data[resenhaDiagnosticsEventIdField],
          connectedOrdinary.attributes[resenhaDiagnosticsEventIdField],
        );
        expect(
          deep.events.singleWhere((event) => event.event == 'sdk.on').data,
          isNot(contains(resenhaDiagnosticsEventIdField)),
        );
      },
    );

    test('redacts secrets without erasing negotiation context', () async {
      final now = DateTime.utc(2026, 8, 11, 13);
      final deep = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        clock: () => now,
        captureIdFactory: () => 'capture-redaction',
        homeDirectory: '/Users/example',
      );
      addTearDown(deep.close);
      await deep.startCapture();
      deep.recordRaw(
        'sdk.webrtc.log',
        component: 'webrtc',
        message:
            'home=/Users/example/private '
            'Bearer bearer-secret '
            'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
            'abcdefghijklmnop\n'
            'a=ice-ufrag:sdp-ufrag-secret\n'
            'participant_session_id=inline-participant-session-secret\n'
            'LiveKit kALL iceServers: [urls: turn:turn.example\n'
            'username: inline-turn-username-secret\n'
            'credential: inline-turn-credential-secret\n'
            ']',
        data: const {
          'username': 'participant-alice',
          'participantId': 42,
          'apiKey': 'discourse-api-secret',
          'authorization': 'Bearer another-secret',
          'cookie': '_forum=private-cookie',
          'livekitToken': 'livekit-secret',
          'url': 'wss://live.example/rtc?token=url-secret&room=staff',
          'sdp':
              'v=0\r\n'
              'a=ice-pwd:sdp-password\r\n'
              'a=candidate:1 1 udp 1 192.0.2.7 5000 typ host',
          'candidate': 'candidate:2 1 udp 1 198.51.100.2 6000 typ srflx',
          'ip': '203.0.113.8',
          'deviceId': 'microphone-stable-id',
          'deviceLabel': "Alice's AirPods",
          'clientId': 'discourse-client-id-secret',
          'participantSessionId': 'participant-session-secret',
          'icePwd': 'structured-ice-pwd-secret',
          'ice_ufrag': 'structured-ice-ufrag-secret',
          'rawJson':
              '{"api_key":"quoted-api-secret",'
              '"credential":"quoted-credential-secret",'
              '"username":"quoted-participant"}',
          'escapedJson':
              r'{"ice-pwd":"prefix\"escaped-ice-secret",'
              r'"client_id":"escaped-client-secret"}',
          'iceServer': {
            'urls': ['turn:turn.example?transport=udp'],
            'username': 'turn-secret-username',
            'credential': 'turn-secret-password',
          },
        },
      );
      await deep.flush();

      final report = await deep.buildJsonReport();
      for (final secret in const [
        '/Users/example',
        'bearer-secret',
        'another-secret',
        'discourse-api-secret',
        'private-cookie',
        'livekit-secret',
        'url-secret',
        'staff',
        'sdp-password',
        'turn-secret-username',
        'turn-secret-password',
        'quoted-api-secret',
        'quoted-credential-secret',
        'sdp-ufrag-secret',
        'discourse-client-id-secret',
        'participant-session-secret',
        'inline-participant-session-secret',
        'structured-ice-pwd-secret',
        'structured-ice-ufrag-secret',
        'escaped-ice-secret',
        'escaped-client-secret',
        'inline-turn-username-secret',
        'inline-turn-credential-secret',
        'abcdefghijklmnop',
      ]) {
        expect(report, isNot(contains(secret)), reason: secret);
      }
      for (final useful in const [
        '<home>',
        'participant-alice',
        '"participantId":42',
        'a=candidate:1',
        '192.0.2.7',
        'candidate:2',
        '198.51.100.2',
        '203.0.113.8',
        'microphone-stable-id',
        "Alice's AirPods",
        'quoted-participant',
        'wss://live.example/rtc?token&room',
        'turn:turn.example?transport',
      ]) {
        expect(report, contains(useful), reason: useful);
      }
    });
  });

  group('diagnostics persistence', () {
    test('caps each JSONL record at 256 KiB and marks truncation', () async {
      final now = DateTime.utc(2026, 8, 11, 14);
      final deep = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        clock: () => now,
        captureIdFactory: () => 'capture-large',
      );
      addTearDown(deep.close);
      await deep.startCapture();
      deep.recordRaw('sdk.large', message: 'x' * (400 * 1024));
      await deep.flush();

      final large = deep.events.singleWhere(
        (record) => record.event == 'sdk.large',
      );
      expect(large.truncated, isTrue);
      expect(deep.state.truncated, isTrue);
      expect(
        resenhaDiagnosticSerializedBytes(large),
        lessThanOrEqualTo(resenhaDiagnosticsMaximumRecordBytes),
      );
      final lines = const LineSplitter().convert(await deep.buildJsonReport());
      expect(lines, hasLength(deep.events.length + 1));
      expect(
        lines.skip(1).map((line) => utf8.encode(line).length + 1),
        everyElement(lessThanOrEqualTo(resenhaDiagnosticsMaximumRecordBytes)),
      );
    });

    test('repairs a corrupt tail and marks the interrupted capture', () async {
      final directory = await Directory.systemTemp.createTemp(
        'resenha-diagnostics-interrupted-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/nested/resenha.jsonl');
      final now = DateTime.utc(2026, 8, 11, 15);
      final persistence = FileResenhaDiagnosticsPersistence(file);
      await persistence.append([
        _record(1, now, event: 'capture.started', captureId: 'capture-crashed'),
        _record(
          2,
          now,
          event: 'mesh.peer.connected',
          captureId: 'capture-crashed',
        ),
      ], nowUtc: now);
      await persistence.close();
      await file.writeAsString(
        '{"version":1,"record":"event","event":',
        mode: FileMode.append,
      );

      final recovered = await ResenhaDiagnosticsController.create(
        persistence: FileResenhaDiagnosticsPersistence(file),
        clock: () => now.add(const Duration(minutes: 1)),
        captureIdFactory: () => 'new-capture',
      );
      addTearDown(recovered.close);

      expect(recovered.captureEnabled, isFalse);
      expect(recovered.state.droppedRecords, greaterThanOrEqualTo(1));
      expect(recovered.state.truncated, isTrue);
      expect(
        recovered.events.map((record) => record.event),
        containsAll(['mesh.peer.connected', 'capture.interrupted']),
      );
      expect(
        await file.readAsString(),
        isNot(endsWith('{"version":1,"record":"event","event":')),
      );
      expect(
        const LineSplitter()
            .convert(await file.readAsString())
            .every((line) => jsonDecode(line) is Map),
        isTrue,
      );
    });

    test(
      'validates and re-redacts every legacy JSONL line before export',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-legacy-redaction-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 15, 30);
        final legacy = jsonEncode({
          'version': resenhaDiagnosticsFormatVersion,
          'record': 'event',
          'origin': 'deep',
          'event': {
            'sequence': 1,
            'timestampUtc': now.toIso8601String(),
            'captureId': 'legacy-capture',
            'event': 'legacy.needs-redaction',
            'component': 'test',
            'severity': 'info',
            'data': const {'apiKey': 'LEGACY_API_SENTINEL'},
            'truncated': false,
          },
        });
        final malformed =
            '${jsonEncode(resenhaDiagnosticLine(_record(2, now, event: 'malformed.regex-match')))} trailing-junk';
        final healthy = jsonEncode(
          resenhaDiagnosticLine(_record(3, now, event: 'healthy.after-legacy')),
        );
        await file.writeAsString('$legacy\n$malformed\n$healthy\n');

        final persistence = FileResenhaDiagnosticsPersistence(
          file,
          decodedTailLimit: 1,
        );
        final stored = await persistence.load(nowUtc: now);
        final report = await persistence.buildJsonReport(
          generatedAtUtc: now,
          reportFormatVersion: 1,
          state: const {},
        );

        expect(stored.records, hasLength(1));
        expect(stored.droppedRecords, greaterThanOrEqualTo(1));
        expect(stored.truncated, isTrue);
        expect(report, contains('legacy.needs-redaction'));
        expect(report, contains('<redacted>'));
        expect(report, isNot(contains('LEGACY_API_SENTINEL')));
        expect(report, isNot(contains('trailing-junk')));
        expect(
          const LineSplitter()
              .convert(report)
              .every((line) => jsonDecode(line) is Map),
          isTrue,
        );
      },
    );

    test(
      'rotates owner-private JSONL segments within their bounds and keeps the newest events',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-rotation-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/nested/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 16);
        final persistence = FileResenhaDiagnosticsPersistence(
          file,
          segmentCount: 3,
          segmentBytes: 2048,
        );
        final controller = await ResenhaDiagnosticsController.create(
          persistence: persistence,
          clock: () => now,
          captureIdFactory: () => 'capture-rotation',
        );
        addTearDown(controller.close);
        await controller.startCapture();
        for (var index = 0; index < 40; index += 1) {
          controller.recordRaw(
            'sdk.line.$index',
            message: '${index.toString().padLeft(2, '0')}-${'x' * 300}',
          );
          await controller.flush();
        }

        final segments = [
          for (var index = 0; index < 3; index += 1)
            if (await persistence.segmentFile(index).exists())
              persistence.segmentFile(index),
        ];
        expect(segments, isNotEmpty);
        expect(segments, hasLength(lessThanOrEqualTo(3)));
        expect(
          await Future.wait(segments.map((segment) => segment.length())),
          everyElement(lessThanOrEqualTo(2048)),
        );
        if (!Platform.isWindows) {
          expect((await file.parent.stat()).mode & 0x1ff, 0x1c0);
          for (final segment in segments) {
            expect((await segment.stat()).mode & 0x1ff, 0x180);
          }
        }
        expect(controller.state.droppedRecords, greaterThan(0));
        expect(controller.state.truncated, isTrue);
        expect(
          controller.events.map((record) => record.event),
          contains('sdk.line.39'),
        );
        expect(
          controller.events.map((record) => record.event),
          isNot(contains('sdk.line.0')),
        );
      },
    );

    test(
      'promotes an interrupted compaction temp and deduplicates mixed segments',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-compaction-',
        );
        addTearDown(() async {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });
        final file = File('${directory.path}/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 16, 30);
        final persistence = FileResenhaDiagnosticsPersistence(
          file,
          segmentCount: 2,
          segmentBytes: 4096,
        );
        await persistence.append([
          _record(1, now, event: 'healthy.before-compaction'),
        ], nowUtc: now);
        await persistence.close();

        final temporary = File('${file.path}.tmp');
        await file.rename(temporary.path);
        await temporary.copy('${file.path}.1');

        final recovered = await FileResenhaDiagnosticsPersistence(
          file,
          segmentCount: 2,
          segmentBytes: 4096,
        ).load(nowUtc: now);

        expect(await file.exists(), isTrue);
        expect(await temporary.exists(), isFalse);
        expect(
          recovered.records.where(
            (record) => record.event == 'healthy.before-compaction',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'loads only the bounded decoded tail while preserving the full JSONL history',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-many-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 16, 45);
        final persistence = FileResenhaDiagnosticsPersistence(file);
        await persistence.append([
          for (var sequence = 1; sequence <= 5000; sequence += 1)
            _record(sequence, now, event: 'event.$sequence'),
        ], nowUtc: now);
        await persistence.close();

        final reloaded = await FileResenhaDiagnosticsPersistence(
          file,
        ).load(nowUtc: now);

        expect(reloaded.records, hasLength(2000));
        expect(reloaded.records.first.sequence, 3001);
        expect(reloaded.records.last.sequence, 5000);
        final report = await FileResenhaDiagnosticsPersistence(file)
            .buildJsonReport(
              generatedAtUtc: now,
              reportFormatVersion: 1,
              state: const {},
            );
        expect(const LineSplitter().convert(report), hasLength(5001));
      },
    );

    test('keeps the near-cap decoded tail within its byte bound', () async {
      final directory = await Directory.systemTemp.createTemp(
        'resenha-diagnostics-near-cap-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/resenha.jsonl');
      final now = DateTime.utc(2026, 8, 11, 16, 50);
      final persistence = FileResenhaDiagnosticsPersistence(
        file,
        segmentCount: 3,
        segmentBytes: 32 * 1024,
        decodedTailLimit: 1000,
        decodedTailBytes: 8 * 1024,
      );
      final stored = await persistence.append([
        for (var sequence = 1; sequence <= 400; sequence += 1)
          _record(
            sequence,
            now,
            writerId: 'writer-near-cap',
            event: 'near-cap.$sequence',
            message: 'payload-${'x' * 240}',
          ),
      ], nowUtc: now);

      expect(
        stored.records.fold<int>(
          0,
          (total, record) => total + resenhaDiagnosticSerializedBytes(record),
        ),
        lessThanOrEqualTo(8 * 1024),
      );
      expect(stored.retainedBytes, lessThanOrEqualTo(3 * 32 * 1024));
      expect(stored.droppedRecords, greaterThan(0));
      final report = await persistence.buildJsonReport(
        generatedAtUtc: now,
        reportFormatVersion: 1,
        state: const {},
      );
      expect(
        const LineSplitter().convert(report).length,
        greaterThan(stored.records.length + 1),
      );
      final artifact = File('${directory.path}/report.jsonl');
      final sink = artifact.openWrite();
      await persistence.writeJsonReportTo(
        sink,
        generatedAtUtc: now,
        reportFormatVersion: 1,
        state: const {},
      );
      await sink.flush();
      await sink.close();
      expect(await artifact.readAsString(), report);
      for (var index = 0; index < 3; index += 1) {
        final segment = persistence.segmentFile(index);
        if (await segment.exists()) {
          expect(await segment.length(), lessThanOrEqualTo(32 * 1024));
        }
      }
    });

    test('finds retained deep event IDs outside the decoded tail', () async {
      final directory = await Directory.systemTemp.createTemp(
        'resenha-diagnostics-event-ids-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/resenha.jsonl');
      final now = DateTime.utc(2026, 8, 11, 16, 52);
      final seed = FileResenhaDiagnosticsPersistence(file, decodedTailLimit: 1);
      await seed.append([
        for (var sequence = 1; sequence <= 10; sequence += 1)
          _record(
            sequence,
            now,
            event: 'event-id.$sequence',
            data: {resenhaDiagnosticsEventIdField: 'ordinary-$sequence'},
          ),
      ], nowUtc: now);
      final controller = await ResenhaDiagnosticsController.create(
        persistence: FileResenhaDiagnosticsPersistence(
          file,
          decodedTailLimit: 1,
        ),
        clock: () => now,
      );
      addTearDown(controller.close);

      expect(controller.events, hasLength(1));
      expect(
        await controller.findRetainedEventIds({
          'ordinary-1',
          'ordinary-5',
          'ordinary-10',
          'ordinary-missing',
        }),
        {'ordinary-1', 'ordinary-5', 'ordinary-10'},
      );
      await expectLater(
        controller.findRetainedEventIds(
          List.generate(
            ResenhaDiagnosticsController.maximumRetainedEventIdCandidates + 1,
            (index) => 'candidate-$index',
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'releases the global lock before caller factory and sink work',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-report-snapshot-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 16, 54);
        final first = FileResenhaDiagnosticsPersistence(file);
        await first.append([
          _record(
            1,
            now,
            event: 'snapshot.deep.event',
            message: 'utf8-boundary-${'🙂' * 17000}',
            data: {resenhaDiagnosticsEventIdField: 'ordinary-snapshot-event'},
          ),
        ], nowUtc: now);

        final factoryGo = File('${directory.path}/factory.go');
        final factoryDone = File('${directory.path}/factory.done');
        final sinkGo = File('${directory.path}/sink.go');
        final sinkDone = File('${directory.path}/sink.done');
        final concurrentMutation = Isolate.run(
          () => _mutateStoreWhileSnapshotOutputIsHeld(
            storePath: file.path,
            factoryGoPath: factoryGo.path,
            factoryDonePath: factoryDone.path,
            sinkGoPath: sinkGo.path,
            sinkDonePath: sinkDone.path,
            timestampMicros: now.microsecondsSinceEpoch,
          ),
        );
        final report = StringBuffer();
        var factoryCalls = 0;
        await first.writeJsonReportSnapshotTo(
          candidateEventIds: const {
            'ordinary-snapshot-event',
            'ordinary-missing',
          },
          outputForRetainedEventIds: (retainedEventIds) {
            factoryCalls += 1;
            expect(retainedEventIds, {'ordinary-snapshot-event'});
            expect(
              () => retainedEventIds.add('must-be-unmodifiable'),
              throwsUnsupportedError,
            );
            factoryGo.writeAsStringSync('go', flush: true);
            _waitForFileSync(factoryDone);
            expect(factoryDone.readAsStringSync(), 'appended');
            return _GatedStringSink(report, () {
              sinkGo.writeAsStringSync('go', flush: true);
              _waitForFileSync(sinkDone);
              expect(sinkDone.readAsStringSync(), 'cleared');
            });
          },
          generatedAtUtc: now,
          reportFormatVersion: 1,
          state: const {},
        );
        await concurrentMutation;

        expect(factoryCalls, 1);
        expect(_reportEventNames(report.toString()), ['snapshot.deep.event']);
        expect(report.toString(), contains('🙂'));
        expect(report.toString(), isNot(contains('concurrent.append')));
        expect(await _reportSnapshotFiles(file), isEmpty);
        final afterClear = await first.buildJsonReport(
          generatedAtUtc: now,
          reportFormatVersion: 1,
          state: const {},
        );
        expect(_reportEventNames(afterClear), isEmpty);
      },
    );

    test(
      'scavenges stale snapshot artifacts and removes snapshots after caller errors',
      () async {
        final directory = await Directory(
          '.dart_tool',
        ).createTemp('resenha-diagnostics-report-cleanup-');
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/resenha.jsonl');
        expect(file.path, isNot(file.absolute.path));
        final now = DateTime.utc(2026, 8, 11, 16, 54, 30);
        final persistence = FileResenhaDiagnosticsPersistence(file);
        await persistence.append([
          _record(
            1,
            now,
            event: 'snapshot.cleanup.event',
            data: {resenhaDiagnosticsEventIdField: 'ordinary-cleanup-event'},
          ),
        ], nowUtc: now);
        final stale = File(
          '${file.absolute.path}.9999.${'a' * 32}'
          '.resenha-report-snapshot.tmp',
        );
        final similarlyNamed = File(
          '${file.absolute.path}.9999.${'g' * 32}'
          '.resenha-report-snapshot.tmp',
        );
        await stale.writeAsString('stale private snapshot');
        await stale.setLastModified(DateTime.utc(2000));
        await similarlyNamed.writeAsString('belongs to another protocol');

        await expectLater(
          persistence.writeJsonReportSnapshotTo(
            candidateEventIds: const {'ordinary-cleanup-event'},
            outputForRetainedEventIds: (_) =>
                throw StateError('factory failed'),
            generatedAtUtc: now,
            reportFormatVersion: 1,
            state: const {},
          ),
          throwsA(isA<StateError>()),
        );
        expect(await stale.exists(), isFalse);
        expect(await similarlyNamed.exists(), isTrue);
        expect(await _reportSnapshotFiles(file), isEmpty);

        await expectLater(
          persistence.writeJsonReportSnapshotTo(
            candidateEventIds: const {'ordinary-cleanup-event'},
            outputForRetainedEventIds: (_) => _ThrowingStringSink(),
            generatedAtUtc: now,
            reportFormatVersion: 1,
            state: const {},
          ),
          throwsA(isA<StateError>()),
        );
        expect(await _reportSnapshotFiles(file), isEmpty);
      },
    );

    test(
      'serializes concurrent instances without dropping colliding writer sequences',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-multiprocess-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 16, 55);
        final first = FileResenhaDiagnosticsPersistence(
          file,
          segmentCount: 3,
          segmentBytes: 8192,
        );
        final second = FileResenhaDiagnosticsPersistence(
          file,
          segmentCount: 3,
          segmentBytes: 8192,
        );

        await Future.wait([
          first.append([
            for (var sequence = 1; sequence <= 20; sequence += 1)
              _record(
                sequence,
                now,
                writerId: 'writer-a',
                event: 'writer-a.$sequence',
              ),
          ], nowUtc: now),
          second.append([
            for (var sequence = 1; sequence <= 20; sequence += 1)
              _record(
                sequence,
                now,
                writerId: 'writer-b',
                event: 'writer-b.$sequence',
              ),
          ], nowUtc: now),
        ]);

        final report = await first.buildJsonReport(
          generatedAtUtc: now,
          reportFormatVersion: 1,
          state: const {},
        );
        final names = _reportEventNames(report);
        expect(
          names.where((name) => name.startsWith('writer-a.')),
          hasLength(20),
        );
        expect(
          names.where((name) => name.startsWith('writer-b.')),
          hasLength(20),
        );
        expect(names.toSet(), hasLength(40));
        if (!Platform.isWindows) {
          expect((await File('${file.path}.lock').stat()).mode & 0x1ff, 0x180);
        }
      },
    );

    test(
      'clamps out-of-order writer timestamps and rejects expired input',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-multiwriter-order-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 16, 56);
        final first = FileResenhaDiagnosticsPersistence(file);
        final second = FileResenhaDiagnosticsPersistence(file);
        await first.append([
          _record(1, now, writerId: 'writer-newer', event: 'writer.newer'),
        ], nowUtc: now);
        await second.append([
          _record(
            1,
            now.subtract(const Duration(hours: 1)),
            writerId: 'writer-older',
            event: 'writer.older-appended-later',
          ),
        ], nowUtc: now.subtract(const Duration(hours: 1)));
        final afterExpired = await second.append([
          _record(
            1,
            now.subtract(const Duration(days: 8)),
            writerId: 'writer-expired',
            event: 'writer.expired-input',
          ),
        ], nowUtc: now);

        final lines = const LineSplitter().convert(
          await first.buildJsonReport(
            generatedAtUtc: now,
            reportFormatVersion: 1,
            state: const {},
          ),
        );
        final events = [
          for (final line in lines.skip(1))
            (jsonDecode(line) as Map<String, dynamic>)['event']
                as Map<String, dynamic>,
        ];
        final timestamps = [
          for (final event in events)
            DateTime.parse(event['timestampUtc'] as String).toUtc(),
        ];
        expect(events.map((event) => event['event']), [
          'writer.newer',
          'writer.older-appended-later',
        ]);
        expect(timestamps[1].isBefore(timestamps[0]), isFalse);
        expect(timestamps[1], timestamps[0]);
        expect(afterExpired.droppedRecords, greaterThanOrEqualTo(1));
        expect(
          events.map((event) => event['event']),
          isNot(contains('writer.expired-input')),
        );
      },
    );

    test(
      "preserves another writer's active capture when one writer stops",
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-active-writers-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 16, 57);
        final first = FileResenhaDiagnosticsPersistence(
          file,
          compactionFaultInjector: (_, _) {},
        );
        final second = FileResenhaDiagnosticsPersistence(file);
        await first.append([
          _record(
            1,
            now,
            writerId: 'writer-active-a',
            captureId: 'capture-active-a',
            event: 'capture.started',
          ),
        ], nowUtc: now);
        await second.append([
          _record(
            1,
            now,
            writerId: 'writer-active-b',
            captureId: 'capture-active-b',
            event: 'capture.started',
          ),
        ], nowUtc: now);
        await first.compact(nowUtc: now);
        final stoppedFirst = await first.append([
          _record(
            2,
            now,
            writerId: 'writer-active-a',
            captureId: 'capture-active-a',
            event: 'capture.stopped',
          ),
        ], nowUtc: now);

        expect(stoppedFirst.activeCaptures, hasLength(1));
        expect(
          stoppedFirst.activeCaptures['writer-active-b']?.captureId,
          'capture-active-b',
        );
        final reloaded = await FileResenhaDiagnosticsPersistence(
          file,
        ).load(nowUtc: now);
        expect(reloaded.activeCaptureId, 'capture-active-b');
        expect(reloaded.activeCaptures, isNot(contains('writer-active-a')));
      },
    );

    test('bounds outstanding capture metadata by writer', () async {
      final now = DateTime.utc(2026, 8, 11, 16, 57, 15);
      final persistence = MemoryResenhaDiagnosticsPersistence();
      final stored = await persistence.append([
        for (var index = 0; index < 10; index += 1)
          _record(
            1,
            now,
            writerId: 'writer-active-$index',
            captureId: 'capture-active-$index',
            event: 'capture.started',
          ),
      ], nowUtc: now);

      expect(stored.activeCaptures, hasLength(4));
      expect(stored.activeCaptures.keys, [
        'writer-active-6',
        'writer-active-7',
        'writer-active-8',
        'writer-active-9',
      ]);
    });

    test(
      'leaves a live writer uninterrupted when a second controller opens',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-live-writer-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final file = File('${directory.path}/resenha.jsonl');
        final now = DateTime.utc(2026, 8, 11, 16, 57, 30);
        final first = await ResenhaDiagnosticsController.create(
          persistence: FileResenhaDiagnosticsPersistence(file),
          clock: () => now,
          captureIdFactory: () => 'capture-live-writer',
        );
        await first.startCapture();
        final second = await ResenhaDiagnosticsController.create(
          persistence: FileResenhaDiagnosticsPersistence(file),
          clock: () => now,
          captureIdFactory: () => 'capture-second-writer',
        );

        expect(
          second.events.map((record) => record.event),
          isNot(contains('capture.interrupted')),
        );
        await second.close();
        await first.stopCapture();
        await first.close();

        final report = await FileResenhaDiagnosticsPersistence(file)
            .buildJsonReport(
              generatedAtUtc: now,
              reportFormatVersion: 1,
              state: const {},
            );
        expect(
          _reportEventNames(report),
          isNot(contains('capture.interrupted')),
        );
      },
    );

    test('recovers compaction without exposing mixed generations', () async {
      for (var failAt = 0; failAt < 7; failAt += 1) {
        final directory = await Directory.systemTemp.createTemp(
          'resenha-diagnostics-generation-$failAt-',
        );
        try {
          final file = File('${directory.path}/resenha.jsonl');
          final now = DateTime.utc(2026, 8, 11, 16, 58);
          final seed = FileResenhaDiagnosticsPersistence(
            file,
            segmentCount: 3,
            segmentBytes: 2048,
          );
          await seed.append([
            for (var sequence = 1; sequence <= 30; sequence += 1)
              _record(
                sequence,
                now,
                writerId: 'writer-generation',
                event: 'generation.$sequence',
                message: 'payload-${'x' * 160}',
              ),
          ], nowUtc: now);
          final before = _reportEventNames(
            await seed.buildJsonReport(
              generatedAtUtc: now,
              reportFormatVersion: 1,
              state: const {},
            ),
          );
          var mutation = 0;
          final crashing = FileResenhaDiagnosticsPersistence(
            file,
            segmentCount: 3,
            segmentBytes: 2048,
            compactionFaultInjector: (phase, _) {
              if (phase != 'after_backup' &&
                  phase != 'after_install' &&
                  phase != 'after_commit') {
                return;
              }
              if (mutation++ == failAt) throw StateError('simulated crash');
            },
          );
          await expectLater(crashing.compact(nowUtc: now), throwsStateError);
          final sameInstanceRecovered = await crashing.load(nowUtc: now);
          expect(
            sameInstanceRecovered.records.map((record) => record.event),
            before,
            reason: 'same-instance recovery mutation $failAt',
          );

          final recovered = FileResenhaDiagnosticsPersistence(
            file,
            segmentCount: 3,
            segmentBytes: 2048,
          );
          final after = _reportEventNames(
            await recovered.buildJsonReport(
              generatedAtUtc: now,
              reportFormatVersion: 1,
              state: const {},
            ),
          );
          expect(after, before, reason: 'failed replacement mutation $failAt');
          expect(after.toSet(), hasLength(after.length));
        } finally {
          if (await directory.exists()) await directory.delete(recursive: true);
        }
      }
    });
  });

  group('SDK bridge lifecycle', () {
    test('installs the bridge only for the explicit capture window', () async {
      final now = DateTime.utc(2026, 8, 11, 17);
      ResenhaDiagnosticsRecorder? installedRecorder;
      var installs = 0;
      var uninstalls = 0;
      final bridge = CallbackResenhaDiagnosticsSdkLogBridge(
        install: (recorder) {
          installs += 1;
          installedRecorder = recorder;
          expect(recorder.captureEnabled, isTrue);
          recorder.recordRaw('sdk.bridge.installed');
        },
        uninstall: () {
          uninstalls += 1;
          installedRecorder!.recordRaw('sdk.bridge.uninstalled');
        },
      );
      final controller = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        clock: () => now,
        captureIdFactory: () => 'capture-bridge',
        sdkLogBridges: [bridge],
      );
      addTearDown(controller.close);

      installedRecorder?.recordRaw('sdk.before');
      await controller.startCapture();
      await controller.stopCapture();
      installedRecorder!.recordRaw('sdk.after');

      expect(installs, 1);
      expect(uninstalls, 1);
      expect(
        controller.events.map((record) => record.event),
        containsAll(['sdk.bridge.installed', 'sdk.bridge.uninstalled']),
      );
      expect(
        controller.events.map((record) => record.event),
        isNot(containsAll(['sdk.before', 'sdk.after'])),
      );
    });

    test('waits for a pending SDK bridge install before closing', () async {
      final now = DateTime.utc(2026, 8, 11, 17, 30);
      final installStarted = Completer<void>();
      final installGate = Completer<void>();
      var sdkActive = false;
      var uninstalls = 0;
      final bridge = CallbackResenhaDiagnosticsSdkLogBridge(
        install: (_) async {
          sdkActive = true;
          installStarted.complete();
          await installGate.future;
        },
        uninstall: () {
          sdkActive = false;
          uninstalls += 1;
        },
      );
      final controller = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        clock: () => now,
        captureIdFactory: () => 'capture-close-race',
        sdkLogBridges: [bridge],
      );
      addTearDown(() async {
        if (!installGate.isCompleted) installGate.complete();
        await controller.close();
      });

      final starting = controller.startCapture();
      await installStarted.future;
      final closing = controller.close();
      expect(sdkActive, isTrue);
      installGate.complete();
      await starting;
      await closing;

      expect(sdkActive, isFalse);
      expect(uninstalls, 1);
      expect(controller.captureEnabled, isFalse);
    });

    test('unwinds a bridge that throws after a partial install', () async {
      final now = DateTime.utc(2026, 8, 11, 17, 45);
      var healthyActive = false;
      var partialActive = false;
      final healthy = CallbackResenhaDiagnosticsSdkLogBridge(
        install: (_) => healthyActive = true,
        uninstall: () => healthyActive = false,
      );
      final partial = CallbackResenhaDiagnosticsSdkLogBridge(
        install: (_) {
          partialActive = true;
          throw StateError('partial install');
        },
        uninstall: () => partialActive = false,
      );
      final controller = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        clock: () => now,
        captureIdFactory: () => 'capture-partial-bridge',
        sdkLogBridges: [healthy, partial],
      );
      addTearDown(controller.close);

      await controller.startCapture();
      expect(healthyActive, isTrue);
      expect(partialActive, isFalse);
      await controller.stopCapture();
      expect(healthyActive, isFalse);
    });
  });

  group('the diagnostics controller', () {
    test(
      'notifies capture-enabled listeners only on capture transitions',
      () async {
        final now = DateTime.utc(2026, 8, 11, 17, 15);
        final controller = await ResenhaDiagnosticsController.create(
          persistence: MemoryResenhaDiagnosticsPersistence(),
          clock: () => now,
          captureIdFactory: () => 'capture-listenable',
        );
        addTearDown(controller.close);
        var notifications = 0;
        controller.captureEnabledListenable.addListener(
          () => notifications += 1,
        );

        await controller.startCapture();
        for (var index = 0; index < 100; index += 1) {
          controller.recordRaw('sdk.verbose.$index');
        }
        await controller.flush();
        expect(notifications, 1);

        await controller.stopCapture();
        expect(notifications, 2);
      },
    );

    testWidgets('coalesces burst persistence and UI-tail notifications', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 8, 11, 17, 20);
      final persistence = _CountingPersistence();
      final controller = await ResenhaDiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
        captureIdFactory: () => 'capture-burst',
      );
      addTearDown(controller.close);
      await controller.startCapture();
      persistence.appendCalls = 0;
      var eventNotifications = 0;
      var stateNotifications = 0;
      controller.eventsListenable.addListener(() => eventNotifications += 1);
      controller.stateListenable.addListener(() => stateNotifications += 1);

      for (var index = 0; index < 20; index += 1) {
        controller.recordRaw('sdk.pending.$index');
        await tester.pump(const Duration(milliseconds: 2));
      }
      expect(persistence.appendCalls, 0);
      expect(eventNotifications, 0);
      expect(stateNotifications, 0);

      for (var index = 0; index < 2500; index += 1) {
        controller.recordRaw('sdk.burst.$index');
      }
      await controller.flush();

      expect(persistence.appendCalls, 1);
      expect(eventNotifications, 1);
      expect(stateNotifications, 1);
      expect(controller.events, hasLength(2000));
      expect(controller.events.last.event, 'sdk.burst.2499');
      await controller.close();
    });

    test('bounds its decoded event tail by bytes as well as count', () async {
      final now = DateTime.utc(2026, 8, 11, 17, 25);
      final controller = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        clock: () => now,
        captureIdFactory: () => 'capture-byte-tail',
        eventsTailLimit: 2000,
        eventsTailBytesLimit: 4096,
      );
      addTearDown(controller.close);
      await controller.startCapture();
      for (var index = 0; index < 100; index += 1) {
        controller.recordRaw('sdk.byte-tail.$index', message: 'x' * 300);
      }
      await controller.flush();

      expect(
        controller.events.fold<int>(
          0,
          (total, record) => total + resenhaDiagnosticSerializedBytes(record),
        ),
        lessThanOrEqualTo(4096),
      );
      expect(controller.events.length, lessThan(100));
      expect(controller.events.last.event, 'sdk.byte-tail.99');
    });

    test(
      'preserves the capture stop marker under pending-write backpressure',
      () async {
        final now = DateTime.utc(2026, 8, 11, 17, 27);
        final persistence = MemoryResenhaDiagnosticsPersistence();
        final controller = await ResenhaDiagnosticsController.create(
          persistence: persistence,
          clock: () => now,
          captureIdFactory: () => 'capture-backpressure',
          pendingWritesBytesLimit: 1024,
        );
        await controller.startCapture();
        for (var index = 0; index < 100; index += 1) {
          controller.recordRaw('sdk.backpressure.$index', message: 'x' * 400);
        }
        await controller.stopCapture();

        expect(controller.state.droppedRecords, greaterThan(0));
        expect(
          _reportEventNames(await controller.buildJsonReport()),
          contains('capture.stopped'),
        );
        await controller.close();

        final reopened = await ResenhaDiagnosticsController.create(
          persistence: persistence,
          clock: () => now.add(const Duration(minutes: 1)),
          captureIdFactory: () => 'capture-after-backpressure',
        );
        addTearDown(reopened.close);
        expect(
          reopened.events.map((record) => record.event),
          isNot(contains('capture.interrupted')),
        );
      },
    );

    test('surfaces clear failures without changing retained state', () async {
      final now = DateTime.utc(2026, 8, 11, 17, 28);
      final persistence = _CountingPersistence();
      final controller = await ResenhaDiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
        captureIdFactory: () => 'capture-clear-failure',
      );
      addTearDown(controller.close);
      await controller.startCapture();
      controller.recordRaw('before.failed.clear');
      await controller.stopCapture();
      final retainedBytes = controller.state.retainedBytes;
      final retainedEvents = controller.events
          .map((event) => event.identity)
          .toList();
      persistence.failClear = true;

      await expectLater(controller.clear(), throwsStateError);

      expect(controller.state.retainedBytes, retainedBytes);
      expect(controller.events.map((event) => event.identity), retainedEvents);
      expect(
        await controller.buildJsonReport(),
        contains('before.failed.clear'),
      );
    });

    test(
      'resumes an expired active capture with a fresh marker after clear',
      () async {
        final initial = DateTime.utc(2026, 8, 11, 17, 28, 30);
        var now = initial;
        final controller = await ResenhaDiagnosticsController.create(
          persistence: MemoryResenhaDiagnosticsPersistence(),
          clock: () => now,
          captureIdFactory: () => 'capture-clear-resume',
        );
        addTearDown(controller.close);
        await controller.startCapture();
        now = initial.add(const Duration(days: 8));

        await controller.clear();

        final resumed = controller.events.singleWhere(
          (record) => record.event == 'capture.started',
        );
        expect(resumed.timestampUtc, now);
        expect(resumed.data, containsPair('resumedAfterClear', true));
        expect(controller.state.retainedBytes, greaterThan(0));
      },
    );
  });

  group('controller failure handling', () {
    test(
      'redacts original create-failure details from General diagnostics',
      () async {
        const secret = 'CREATE_FAILURE_SENTINEL_9cf2';
        final ordinary = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'ordinary-create-failure',
        );
        final binding = DiagnosticsSink.install(ordinary);
        final controller = await ResenhaDiagnosticsController.create(
          reporter: PluginDiagnosticsReporter.fixed(ordinary),
          persistenceFactory: () async => throw const _SentinelFailure(secret),
        );
        addTearDown(() async {
          await controller.close();
          binding.close();
          await ordinary.close();
        });

        await expectLater(controller.clear(), throwsStateError);
        final general = ordinary.buildJsonReport();
        expect(controller.events, isEmpty);
        expect(general, isNot(contains(secret)));
        expect(general, contains('resenha.deep_capture.create'));
        expect(general, contains('resenha.deep_capture.clear'));
        expect(general, contains('_SentinelFailure'));
      },
    );

    test(
      'redacts original load-failure details from General diagnostics',
      () async {
        const secret = 'LOAD_FAILURE_SENTINEL_34ab';
        final ordinary = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'ordinary-load-failure',
        );
        final binding = DiagnosticsSink.install(ordinary);
        final persistence = _CountingPersistence()
          ..loadError = const _SentinelFailure(secret);
        final controller = await ResenhaDiagnosticsController.create(
          reporter: PluginDiagnosticsReporter.fixed(ordinary),
          persistence: persistence,
        );
        addTearDown(() async {
          await controller.close();
          binding.close();
          await ordinary.close();
        });

        final general = ordinary.buildJsonReport();
        expect(controller.events, isEmpty);
        expect(general, isNot(contains(secret)));
        expect(general, contains('resenha.deep_capture.load'));
        expect(general, contains('_SentinelFailure'));
      },
    );

    test('keeps the durable store clearable after load failure', () async {
      final now = DateTime.utc(2026, 8, 11, 17, 29);
      final persistence = _CountingPersistence();
      await persistence.seed(
        _record(1, now, event: 'durable.residue'),
        nowUtc: now,
      );
      persistence.loadError = const _SentinelFailure(
        'DURABLE_LOAD_FAILURE_SENTINEL',
      );
      final controller = await ResenhaDiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
      );
      addTearDown(controller.close);

      expect(controller.events, isEmpty);
      await controller.clear();

      expect(persistence.clearCalls, 1);
      persistence.loadError = null;
      expect((await persistence.load(nowUtc: now)).records, isEmpty);
      expect(controller.state.retainedBytes, 0);
    });

    test(
      'redacts original append-failure details from General diagnostics',
      () async {
        const secret = 'APPEND_FAILURE_SENTINEL_a884';
        final ordinary = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'ordinary-append-failure',
        );
        final binding = DiagnosticsSink.install(ordinary);
        final persistence = _CountingPersistence();
        final controller = await ResenhaDiagnosticsController.create(
          reporter: PluginDiagnosticsReporter.fixed(ordinary),
          persistence: persistence,
          captureIdFactory: () => 'capture-append-failure',
        );
        addTearDown(() async {
          persistence.appendError = null;
          await controller.close();
          binding.close();
          await ordinary.close();
        });
        persistence.appendError = const _SentinelFailure(secret);

        await controller.startCapture();
        final general = ordinary.buildJsonReport();
        expect(general, isNot(contains(secret)));
        expect(general, contains('resenha.deep_capture.append'));
        expect(general, contains('_SentinelFailure'));
        persistence.appendError = null;
        await controller.stopCapture();
      },
    );

    test(
      'keeps SDK bridge failure details in deep-capture diagnostics only',
      () async {
        const secret = 'BRIDGE_FAILURE_SENTINEL_c613';
        final ordinary = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'ordinary-bridge-failure',
        );
        final binding = DiagnosticsSink.install(ordinary);
        final bridge = CallbackResenhaDiagnosticsSdkLogBridge(
          install: (_) => throw const _SentinelFailure(secret),
          uninstall: () {},
        );
        final controller = await ResenhaDiagnosticsController.create(
          reporter: PluginDiagnosticsReporter.fixed(ordinary),
          persistence: MemoryResenhaDiagnosticsPersistence(),
          captureIdFactory: () => 'capture-bridge-failure',
          sdkLogBridges: [bridge],
        );
        addTearDown(() async {
          await controller.close();
          binding.close();
          await ordinary.close();
        });

        await controller.startCapture();
        final general = ordinary.buildJsonReport();
        final deep = await controller.buildJsonReport();
        expect(general, isNot(contains(secret)));
        expect(general, contains('resenha.deep_capture.sdk_bridge.install'));
        expect(general, contains('_SentinelFailure'));
        expect(deep, contains(secret));
        await controller.stopCapture();
      },
    );
  });

  group('retention and expiry', () {
    test('clamp backward clock jumps and expire only an old prefix', () async {
      final initial = DateTime.utc(2026, 8, 11, 18);
      var now = initial;
      final controller = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        clock: () => now,
        captureIdFactory: () => 'capture-clock',
      );
      addTearDown(controller.close);
      await controller.startCapture();
      controller.recordRaw('before.jump');
      now = initial.subtract(const Duration(hours: 2));
      controller.recordRaw('after.backward.jump');
      await controller.flush();
      expect(
        controller.events[2].timestampUtc.isBefore(
          controller.events[1].timestampUtc,
        ),
        isFalse,
      );

      now = initial.add(const Duration(days: 8));
      controller.recordRaw('after.retention');
      await controller.flush();
      expect(controller.events.map((record) => record.event), [
        'after.retention',
      ]);
      expect(controller.state.droppedRecords, greaterThanOrEqualTo(3));
    });

    test('remove seven-day history when an idle capture is exported', () async {
      final initial = DateTime.utc(2026, 8, 11, 18, 30);
      var now = initial;
      final controller = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        clock: () => now,
        captureIdFactory: () => 'capture-idle-expiry',
      );
      addTearDown(controller.close);
      await controller.startCapture();
      controller.recordRaw('old.idle.event');
      await controller.stopCapture();

      now = initial.add(const Duration(days: 8));
      final report = await controller.buildJsonReport();

      expect(report, isNot(contains('old.idle.event')));
      expect(controller.events, isEmpty);
      expect(controller.state.retainedBytes, 0);
      expect(controller.state.droppedRecords, greaterThanOrEqualTo(3));
    });

    test('remove idle retained history passively after seven days', () async {
      final initial = DateTime.utc(2026, 8, 11, 18, 45);
      var now = initial;
      late _ManualTimer expiry;
      final persistence = MemoryResenhaDiagnosticsPersistence();
      final controller = await ResenhaDiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
        timerFactory: (duration, callback) {
          expiry = _ManualTimer(duration, callback);
          return expiry;
        },
        captureIdFactory: () => 'capture-passive-expiry',
        eventsTailLimit: 1,
      );
      addTearDown(controller.close);
      await controller.startCapture();
      now = initial.add(const Duration(days: 1));
      controller.recordRaw('old.passive.event');
      await controller.stopCapture();

      expect(expiry.delay, const Duration(days: 6));
      expect(controller.events, hasLength(1));
      now = initial.add(const Duration(days: 8));
      expiry.fire();
      await pumpEventQueue();

      expect(controller.events, isEmpty);
      expect(controller.state.retainedBytes, 0);
      expect((await persistence.load(nowUtc: now)).records, isEmpty);
    });

    test(
      'keep events as a bounded tail while the JSONL report retains full history',
      () async {
        final now = DateTime.utc(2026, 8, 11, 18);
        final controller = await ResenhaDiagnosticsController.create(
          persistence: MemoryResenhaDiagnosticsPersistence(),
          clock: () => now,
          captureIdFactory: () => 'capture-tail',
          eventsTailLimit: 3,
        );
        addTearDown(controller.close);
        await controller.startCapture();
        for (var index = 0; index < 5; index += 1) {
          controller.recordRaw('event.$index');
        }
        await controller.flush();

        expect(controller.events, hasLength(3));
        final reportLines = const LineSplitter().convert(
          await controller.buildJsonReport(),
        );
        expect(reportLines.first, contains('"record":"report"'));
        final header = jsonDecode(reportLines.first) as Map<String, dynamic>;
        expect(header['captureFormatVersion'], resenhaDiagnosticsFormatVersion);
        expect(header['app'], containsPair('version', isA<String>()));
        expect(
          header['platform'],
          containsPair('operatingSystem', Platform.operatingSystem),
        );
        expect(header['retention'], containsPair('segmentCount', 5));
        expect(reportLines.length, greaterThan(controller.events.length + 1));
        expect(
          reportLines.skip(1).every((line) => jsonDecode(line) is Map),
          isTrue,
        );
        expect(
          (jsonDecode(reportLines[1]) as Map<String, dynamic>)['origin'],
          'deep',
        );
      },
    );
  });
}

ResenhaDiagnosticRecord _record(
  int sequence,
  DateTime at, {
  required String event,
  String captureId = 'capture',
  String writerId = 'legacy',
  String? message,
  Map<String, Object?> data = const {},
}) => ResenhaDiagnosticRecord(
  writerId: writerId,
  sequence: sequence,
  timestampUtc: at,
  captureId: captureId,
  event: event,
  component: 'test',
  severity: DiagnosticSeverity.info,
  message: message,
  data: data,
);

List<String> _reportEventNames(String report) => [
  for (final line in const LineSplitter().convert(report).skip(1))
    (((jsonDecode(line) as Map<String, dynamic>)['event']
            as Map<String, dynamic>)['event']
        as String),
];

Future<void> _mutateStoreWhileSnapshotOutputIsHeld({
  required String storePath,
  required String factoryGoPath,
  required String factoryDonePath,
  required String sinkGoPath,
  required String sinkDonePath,
  required int timestampMicros,
}) async {
  final persistence = FileResenhaDiagnosticsPersistence(File(storePath));
  final now = DateTime.fromMicrosecondsSinceEpoch(timestampMicros, isUtc: true);
  await _waitForFile(File(factoryGoPath));
  try {
    await persistence.append([
      _record(
        2,
        now.add(const Duration(seconds: 1)),
        writerId: 'concurrent-isolate',
        event: 'concurrent.append',
      ),
    ], nowUtc: now);
    await _publishSignal(File(factoryDonePath), 'appended');
  } on Object catch (error) {
    await _publishSignal(
      File(factoryDonePath),
      'append failed: ${error.runtimeType}',
    );
    return;
  }

  await _waitForFile(File(sinkGoPath));
  try {
    await persistence.clear();
    await _publishSignal(File(sinkDonePath), 'cleared');
  } on Object catch (error) {
    await _publishSignal(
      File(sinkDonePath),
      'clear failed: ${error.runtimeType}',
    );
  }
}

Future<void> _publishSignal(File signal, String value) async {
  final pending = File('${signal.path}.$pid.pending');
  await pending.writeAsString(value, flush: true);
  await pending.rename(signal.path);
}

Future<void> _waitForFile(File signal) async {
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  while (!await signal.exists()) {
    if (!DateTime.now().isBefore(deadline)) {
      throw TimeoutException('Timed out waiting for ${signal.path}.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void _waitForFileSync(File signal) {
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  while (!signal.existsSync()) {
    if (!DateTime.now().isBefore(deadline)) {
      throw TimeoutException('Timed out waiting for ${signal.path}.');
    }
    sleep(const Duration(milliseconds: 10));
  }
}

Future<List<File>> _reportSnapshotFiles(File store) async {
  final ownedSnapshot = RegExp(
    '^${RegExp.escape(store.absolute.path)}\\.\\d+\\.[0-9a-f]{32}'
    r'\.resenha-report-snapshot\.tmp$',
  );
  return [
    await for (final entity in store.parent.absolute.list(followLinks: false))
      if (entity is File && ownedSnapshot.hasMatch(entity.path)) entity,
  ];
}

final class _GatedStringSink implements StringSink {
  _GatedStringSink(this._delegate, this._beforeFirstWrite);

  final StringSink _delegate;
  final void Function() _beforeFirstWrite;
  bool _started = false;

  void _start() {
    if (_started) return;
    _started = true;
    _beforeFirstWrite();
  }

  @override
  void write(Object? object) {
    _start();
    _delegate.write(object);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _start();
    _delegate.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    _start();
    _delegate.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    _start();
    _delegate.writeln(object);
  }
}

final class _ThrowingStringSink implements StringSink {
  Never _fail() => throw StateError('sink failed');

  @override
  void write(Object? object) => _fail();

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) => _fail();

  @override
  void writeCharCode(int charCode) => _fail();

  @override
  void writeln([Object? object = '']) => _fail();
}

final class _CountingPersistence implements ResenhaDiagnosticsPersistence {
  final MemoryResenhaDiagnosticsPersistence _delegate =
      MemoryResenhaDiagnosticsPersistence();
  int appendCalls = 0;
  int clearCalls = 0;
  bool failClear = false;
  Object? loadError;
  Object? appendError;

  @override
  Future<ResenhaDiagnosticsPersistenceState> append(
    List<ResenhaDiagnosticRecord> records, {
    required DateTime nowUtc,
  }) {
    appendCalls += 1;
    if (appendError case final error?) {
      return Future.error(error, StackTrace.current);
    }
    return _delegate.append(records, nowUtc: nowUtc);
  }

  @override
  Future<String> buildJsonReport({
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) => _delegate.buildJsonReport(
    generatedAtUtc: generatedAtUtc,
    reportFormatVersion: reportFormatVersion,
    state: state,
  );

  @override
  Future<void> clear() {
    clearCalls += 1;
    if (failClear) throw StateError('simulated clear failure');
    return _delegate.clear();
  }

  Future<void> seed(
    ResenhaDiagnosticRecord record, {
    required DateTime nowUtc,
  }) => _delegate.append([record], nowUtc: nowUtc);

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<ResenhaDiagnosticsPersistenceState> compact({
    required DateTime nowUtc,
  }) => _delegate.compact(nowUtc: nowUtc);

  @override
  Future<void> flush() => _delegate.flush();

  @override
  Future<ResenhaDiagnosticsPersistenceState> load({required DateTime nowUtc}) {
    if (loadError case final error?) {
      return Future.error(error, StackTrace.current);
    }
    return _delegate.load(nowUtc: nowUtc);
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

final class _SentinelFailure implements Exception {
  const _SentinelFailure(this.secret);

  final String secret;

  @override
  String toString() => 'SentinelFailure($secret)';
}
