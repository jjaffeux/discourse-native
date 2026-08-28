import 'dart:convert';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_resenha/src/resenha_diagnostics.dart';
import 'package:discourse_resenha/src/resenha_diagnostics_report.dart';
import 'package:discourse_resenha/src/resenha_report_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reuses timeline projections when the retained tail advances', () async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'resenha-report-projection',
      clock: () => now,
    );
    final resenha = await ResenhaDiagnosticsController.create(
      persistence: MemoryResenhaDiagnosticsPersistence(),
      captureIdFactory: () => 'capture-tail',
      clock: () => now,
    );
    addTearDown(() async {
      await resenha.close();
      await diagnostics.close();
    });

    await resenha.startCapture();
    for (var sequence = 1; sequence <= 2000; sequence += 1) {
      resenha.recordRaw(
        'retained.event.$sequence',
        component: 'capture',
        data: {'sequence': sequence},
      );
    }
    await resenha.flush();

    final projected = <String>[];
    final report = ResenhaDiagnosticsReport(
      diagnostics: diagnostics,
      resenha: resenha,
      onEventProjected: projected.add,
    );
    final first = report.events;
    expect(
      first,
      hasLength(ResenhaDiagnosticsController.defaultEventsTailLimit),
    );
    expect(projected, hasLength(first.length));
    final firstById = {for (final event in first) event['id']!: event};
    final firstIds = first.map((event) => event['id']! as String).toList();
    expect(firstIds, [...firstIds]..sort());
    projected.clear();

    resenha.recordRaw(
      'retained.event.appended',
      component: 'capture',
      data: const {'sequence': 2001},
    );
    await resenha.flush();
    final second = report.events;
    final appended = second.singleWhere(
      (event) => event['event'] == 'retained.event.appended',
    );

    expect(projected, [appended['id']]);
    for (final event in second) {
      if (identical(event, appended)) continue;
      expect(event, same(firstById[event['id']]));
    }
  });

  test(
    'combines reports with one privacy, de-duplication, and ordering policy',
    () async {
      var now = DateTime.utc(2026, 8, 11, 14, 30);
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'resenha-report-test',
        clock: () => now,
      );
      final persistence = _TrackingResenhaDiagnosticsPersistence();
      final resenha = await ResenhaDiagnosticsController.create(
        persistence: persistence,
        captureIdFactory: () => 'capture-report-test',
        clock: () => now,
      );
      final sinkBinding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        sinkBinding.close();
        await resenha.close();
        await diagnostics.close();
      });

      final exactTie = now;
      resenha.record('call.safe.before_capture', component: 'controller');
      await resenha.startCapture();
      now = now.add(const Duration(seconds: 1));
      resenha.record(
        'call.join.captured',
        component: 'controller',
        correlationId: 'resenha-call-report',
      );
      now = now.add(const Duration(seconds: 1));
      resenha.recordRaw(
        'peer.ice.failed',
        component: 'mesh',
        severity: DiagnosticSeverity.error,
        message: 'ICE negotiation failed',
        data: const {'username': 'sam', 'candidate': '10.0.0.2'},
      );
      now = now.add(const Duration(seconds: 1));
      await resenha.stopCapture();

      DiagnosticsSink.runOperation('resenha.join', () {
        diagnostics.recordHttp(
          HttpDiagnosticRecord(
            eventId: 'resenha-http',
            phase: HttpDiagnosticPhase.started,
            timestamp: now,
            method: 'POST',
            uri: Uri.parse(
              'https://forum.example/resenha/rooms/42/join?token=private',
            ),
            sentBytes: 120,
            receivedBytes: 0,
          ),
        );
        diagnostics.recordHttp(
          HttpDiagnosticRecord(
            eventId: 'resenha-http',
            phase: HttpDiagnosticPhase.completed,
            timestamp: now.add(const Duration(milliseconds: 180)),
            method: 'POST',
            uri: Uri.parse(
              'https://forum.example/resenha/rooms/42/join?token=private',
            ),
            statusCode: 200,
            reasonPhrase: 'PRIVATE_HTTP_REASON_SENTINEL',
            responseHeaders: const {
              'x-request-id': 'PRIVATE_HTTP_HEADER_SENTINEL',
            },
            totalDuration: const Duration(milliseconds: 180),
            sentBytes: 120,
            receivedBytes: 2048,
          ),
        );
        diagnostics.recordHttp(
          HttpDiagnosticRecord(
            eventId: 'resenha-http-failed',
            phase: HttpDiagnosticPhase.started,
            timestamp: now.add(const Duration(milliseconds: 200)),
            method: 'POST',
            uri: Uri.parse(
              'https://198.51.100.77/resenha/rooms/42/signal?token=private',
            ),
            sentBytes: 80,
            receivedBytes: 0,
          ),
        );
        diagnostics.recordHttp(
          HttpDiagnosticRecord(
            eventId: 'resenha-http-failed',
            phase: HttpDiagnosticPhase.failed,
            timestamp: now.add(const Duration(milliseconds: 240)),
            method: 'POST',
            uri: Uri.parse(
              'https://198.51.100.77/resenha/rooms/42/signal?token=private',
            ),
            totalDuration: const Duration(milliseconds: 40),
            sentBytes: 80,
            receivedBytes: 0,
            errorType: 'SocketException',
            errorMessage:
                'HTTP_ERROR_MESSAGE_SENTINEL candidate 203.0.113.91:5000',
            stackTrace: 'HTTP_STACK_SENTINEL 203.0.113.92',
          ),
        );
        diagnostics.reportError(
          StateError('PRIVATE_ERROR_MESSAGE_SENTINEL'),
          StackTrace.current,
          source: 'platform',
        );
      }, correlationId: 'resenha-call-report');
      diagnostics.recordHttp(
        HttpDiagnosticRecord(
          eventId: 'unrelated-http',
          phase: HttpDiagnosticPhase.started,
          timestamp: now,
          method: 'GET',
          uri: Uri.parse('https://forum.example/latest.json'),
          sentBytes: 0,
          receivedBytes: 0,
        ),
      );

      final report = ResenhaDiagnosticsReport(
        diagnostics: diagnostics,
        resenha: resenha,
      );
      final timeline = report.events;
      expect(
        timeline.any((event) => event['event'] == 'GET /latest.json'),
        isFalse,
      );
      expect(
        timeline.any(
          (event) => event['event'] == 'POST /resenha/rooms/42/join?token',
        ),
        isTrue,
      );

      final retainedBytes = resenha.state.retainedBytes;
      expect(retainedBytes, greaterThan(1));
      final recent = await report.buildClipboard(retainedBytes - 1);
      expect(persistence.materializedBuildCount, 0);
      expect(recent.truncated, isTrue);
      expect(recent.text, contains('"deepRetainedBytes"'));
      expect(recent.text, isNot(contains('private')));
      expect(
        utf8.encode(recent.text).length,
        lessThanOrEqualTo(retainedBytes - 1),
      );

      await report.buildClipboard(retainedBytes);
      expect(
        persistence.materializedBuildCount,
        1,
        reason: 'retainedBytes equal to the limit uses the full-report branch',
      );

      final materialized = await report.buildJson();
      expect(persistence.materializedBuildCount, 2);
      final streamed = StringBuffer();
      await report.writeJsonTo(streamed);
      expect(persistence.streamingBuildCount, 1);
      expect(persistence.legacyIdScanCount, 0);
      expect(streamed.toString(), materialized);

      expect(materialized, contains('"origin":"ordinary"'));
      expect(materialized, contains('"origin":"deep"'));
      expect(materialized, contains('call.safe.before_capture'));
      expect(materialized, contains('peer.ice.failed'));
      expect(materialized, contains('/resenha/rooms/42/join?token'));
      expect(materialized, contains('/resenha/rooms/42/signal?token'));
      expect(materialized, contains('SocketException'));
      expect(materialized, isNot(contains('private')));
      expect(materialized, isNot(contains('198.51.100.77')));
      expect(materialized, isNot(contains('203.0.113.91')));
      expect(materialized, isNot(contains('203.0.113.92')));
      expect(materialized, isNot(contains('HTTP_ERROR_MESSAGE_SENTINEL')));
      expect(materialized, isNot(contains('HTTP_STACK_SENTINEL')));
      expect(materialized, isNot(contains('PRIVATE_ERROR_MESSAGE_SENTINEL')));
      expect(materialized, isNot(contains('PRIVATE_HTTP_REASON_SENTINEL')));
      expect(materialized, isNot(contains('PRIVATE_HTTP_HEADER_SENTINEL')));
      expect(materialized, isNot(contains('forum.example')));
      expect(materialized, isNot(contains('/latest.json')));
      expect(
        RegExp('call.join.captured').allMatches(materialized),
        hasLength(1),
      );

      final lines = const LineSplitter().convert(materialized);
      final header = jsonDecode(lines.first) as Map<String, Object?>;
      final streams = header['streams']! as Map<String, Object?>;
      final ordinaryStream = streams['ordinary']! as Map<String, Object?>;
      final records = [
        for (final line in lines.skip(1))
          jsonDecode(line) as Map<String, Object?>,
      ];
      final ordinaryCount = records
          .where((record) => record['origin'] == 'ordinary')
          .length;
      expect(ordinaryStream['eventCount'], ordinaryCount);
      expect(ordinaryStream['retentionHours'], greaterThan(0));

      final events = [
        for (final record in records) record['event']! as Map<String, Object?>,
      ];
      final reportTimestamps = [
        for (final event in events)
          DateTime.parse(event['timestampUtc']! as String),
      ];
      for (var index = 1; index < reportTimestamps.length; index += 1) {
        expect(
          reportTimestamps[index].isBefore(reportTimestamps[index - 1]),
          isFalse,
          reason: 'JSONL event lines must remain chronological',
        );
      }
      final tiedOrigins = [
        for (var index = 0; index < records.length; index += 1)
          if (reportTimestamps[index] == exactTie) records[index]['origin'],
      ];
      expect(tiedOrigins, ['deep', 'ordinary']);
    },
  );

  test(
    'nested deep event-ID fields do not suppress ordinary report events',
    () async {
      var now = DateTime.utc(2026, 8, 11, 15);
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'resenha-report-nested-event-id',
        clock: () => now,
      );
      final resenha = await ResenhaDiagnosticsController.create(
        persistence: MemoryResenhaDiagnosticsPersistence(),
        captureIdFactory: () => 'capture-nested-event-id',
        clock: () => now,
      );
      final sinkBinding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        sinkBinding.close();
        await resenha.close();
        await diagnostics.close();
      });

      resenha.record('ordinary.must.remain', component: 'controller');
      await diagnostics.flush();
      final ordinary = diagnostics.events
          .whereType<DiagnosticLogEvent>()
          .singleWhere((event) => event.name == 'ordinary.must.remain');
      final ordinaryId =
          ordinary.attributes[resenhaDiagnosticsEventIdField]! as String;

      await resenha.startCapture();
      now = now.add(const Duration(seconds: 1));
      resenha.recordRaw(
        'deep.nested.impostor',
        component: 'sdk',
        data: {
          'nested': {resenhaDiagnosticsEventIdField: ordinaryId},
        },
      );
      now = now.add(const Duration(seconds: 1));
      await resenha.stopCapture();

      final report = ResenhaDiagnosticsReport(
        diagnostics: diagnostics,
        resenha: resenha,
      );
      final materialized = await report.buildJson();
      final streamed = StringBuffer();
      await report.writeJsonTo(streamed);

      expect(streamed.toString(), materialized);
      final records = [
        for (final line in const LineSplitter().convert(materialized).skip(1))
          jsonDecode(line) as Map<String, Object?>,
      ];
      final ordinaryNames = [
        for (final record in records)
          if (record['origin'] == 'ordinary')
            (record['event']! as Map<String, Object?>)['name'],
      ];
      expect(ordinaryNames, contains('ordinary.must.remain'));
      final header =
          jsonDecode(const LineSplitter().convert(materialized).first)
              as Map<String, Object?>;
      final streams = header['streams']! as Map<String, Object?>;
      final ordinaryStream = streams['ordinary']! as Map<String, Object?>;
      expect(ordinaryStream['eventCount'], 1);
    },
  );

  test(
    'materialized fallback de-duplicates against the report snapshot',
    () async {
      var now = DateTime.utc(2026, 8, 11, 15, 30);
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'resenha-report-fallback',
        clock: () => now,
      );
      final persistence = _ClearingAfterBuildPersistence();
      final resenha = await ResenhaDiagnosticsController.create(
        persistence: persistence,
        captureIdFactory: () => 'capture-fallback-test',
        clock: () => now,
      );
      final sinkBinding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        sinkBinding.close();
        await resenha.close();
        await diagnostics.close();
      });

      await resenha.startCapture();
      now = now.add(const Duration(seconds: 1));
      resenha.record('fallback.captured.once', component: 'controller');
      now = now.add(const Duration(seconds: 1));
      await resenha.stopCapture();
      persistence.clearAfterNextBuild = true;

      final output = StringBuffer();
      await ResenhaDiagnosticsReport(
        diagnostics: diagnostics,
        resenha: resenha,
      ).writeJsonTo(output);
      final report = output.toString();

      expect(persistence.clearedAfterBuild, isTrue);
      expect(RegExp('fallback.captured.once').allMatches(report), hasLength(1));
      final lines = const LineSplitter().convert(report);
      final header = jsonDecode(lines.first) as Map<String, Object?>;
      final streams = header['streams']! as Map<String, Object?>;
      final ordinary = streams['ordinary']! as Map<String, Object?>;
      expect(ordinary['eventCount'], 0);
      final captured = lines
          .skip(1)
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .singleWhere(
            (line) =>
                (line['event']! as Map<String, Object?>)['event'] ==
                'fallback.captured.once',
          );
      expect(captured['origin'], 'deep');
    },
  );

  test('bounds materialized clipboard reports by UTF-8 whole lines', () {
    final old = 'old-${'é' * 200}';
    final newest = 'new-${'🙂' * 10}';
    final bounded = boundResenhaReportForClipboard(
      '$old\n$newest',
      byteLimit: 260,
    );

    expect(bounded.truncated, isTrue);
    expect(bounded.text, contains('clipboard_limit'));
    expect(bounded.text, contains(newest));
    expect(bounded.text, isNot(contains(old)));
    expect(utf8.encode(bounded.text).length, lessThanOrEqualTo(260));
  });
}

final class _TrackingResenhaDiagnosticsPersistence
    implements
        ResenhaDiagnosticsPersistence,
        StreamingResenhaDiagnosticsPersistence,
        SnapshotStreamingResenhaDiagnosticsPersistence,
        RetainedResenhaDiagnosticsEventIdsPersistence {
  final MemoryResenhaDiagnosticsPersistence _delegate =
      MemoryResenhaDiagnosticsPersistence();

  int materializedBuildCount = 0;
  int streamingBuildCount = 0;
  int legacyIdScanCount = 0;

  @override
  Future<ResenhaDiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _delegate.load(nowUtc: nowUtc);

  @override
  Future<ResenhaDiagnosticsPersistenceState> append(
    List<ResenhaDiagnosticRecord> records, {
    required DateTime nowUtc,
  }) => _delegate.append(records, nowUtc: nowUtc);

  @override
  Future<ResenhaDiagnosticsPersistenceState> compact({
    required DateTime nowUtc,
  }) => _delegate.compact(nowUtc: nowUtc);

  @override
  Future<String> buildJsonReport({
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) {
    materializedBuildCount += 1;
    return _delegate.buildJsonReport(
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: state,
    );
  }

  @override
  Future<void> writeJsonReportTo(
    StringSink output, {
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) async {
    streamingBuildCount += 1;
    final report = await _delegate.buildJsonReport(
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: state,
    );
    final chunked = report.replaceAll('\n', '\r\n');
    for (var offset = 0; offset < chunked.length; offset += 7) {
      final end = offset + 7 < chunked.length ? offset + 7 : chunked.length;
      output.write(chunked.substring(offset, end));
    }
  }

  @override
  Future<void> writeJsonReportSnapshotTo({
    required Set<String> candidateEventIds,
    required ResenhaDiagnosticsReportSinkFactory outputForRetainedEventIds,
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) async {
    streamingBuildCount += 1;
    final report = await _delegate.buildJsonReport(
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: state,
    );
    final retainedEventIds = _retainedEventIdsInReport(
      report,
      candidateEventIds,
    );
    final output = outputForRetainedEventIds(
      Set<String>.unmodifiable(retainedEventIds),
    );
    final chunked = report.replaceAll('\n', '\r\n');
    for (var offset = 0; offset < chunked.length; offset += 7) {
      final end = offset + 7 < chunked.length ? offset + 7 : chunked.length;
      output.write(chunked.substring(offset, end));
    }
  }

  @override
  Future<Set<String>> findRetainedEventIds(
    Set<String> candidateIds, {
    required DateTime nowUtc,
  }) {
    legacyIdScanCount += 1;
    return _delegate.findRetainedEventIds(candidateIds, nowUtc: nowUtc);
  }

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<void> flush() => _delegate.flush();

  @override
  Future<void> close() => _delegate.close();
}

final class _ClearingAfterBuildPersistence
    implements ResenhaDiagnosticsPersistence {
  final MemoryResenhaDiagnosticsPersistence _delegate =
      MemoryResenhaDiagnosticsPersistence();

  bool clearAfterNextBuild = false;
  bool clearedAfterBuild = false;

  @override
  Future<ResenhaDiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _delegate.load(nowUtc: nowUtc);

  @override
  Future<ResenhaDiagnosticsPersistenceState> append(
    List<ResenhaDiagnosticRecord> records, {
    required DateTime nowUtc,
  }) => _delegate.append(records, nowUtc: nowUtc);

  @override
  Future<ResenhaDiagnosticsPersistenceState> compact({
    required DateTime nowUtc,
  }) => _delegate.compact(nowUtc: nowUtc);

  @override
  Future<String> buildJsonReport({
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) async {
    final report = await _delegate.buildJsonReport(
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: state,
    );
    if (clearAfterNextBuild) {
      clearAfterNextBuild = false;
      await _delegate.clear();
      clearedAfterBuild = true;
    }
    return report;
  }

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<void> flush() => _delegate.flush();

  @override
  Future<void> close() => _delegate.close();
}

Set<String> _retainedEventIdsInReport(
  String report,
  Set<String> candidateEventIds,
) => {
  for (final line in const LineSplitter().convert(report).skip(1))
    if (jsonDecode(line) case final Map<String, dynamic> record)
      if (record['event'] case final Map<String, dynamic> event)
        if (event['data'] case final Map<String, dynamic> data)
          if (data[resenhaDiagnosticsEventIdField] case final String id
              when candidateEventIds.contains(id))
            id,
};
