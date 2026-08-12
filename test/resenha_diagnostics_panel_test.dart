import 'dart:convert';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/diagnostics/resenha_report_exporter.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:discourse_native/src/shell/diagnostics_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adds a Resenha tab backed by the capture controller', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var now = DateTime.utc(2026, 8, 11, 14, 30);
    final diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'resenha-panel-test',
      clock: () => now,
    );
    final resenha = await ResenhaDiagnosticsController.create(
      persistence: MemoryResenhaDiagnosticsPersistence(),
      captureIdFactory: () => 'capture-panel-test',
      clock: () => now,
    );
    final sinkBinding = DiagnosticsSink.install(diagnostics);
    addTearDown(sinkBinding.close);
    resenha.record('call.safe.before_capture', component: 'controller');
    await resenha.startCapture();
    now = now.add(const Duration(seconds: 1));
    resenha.record(
      'call.join.captured',
      component: 'controller',
      correlationId: 'resenha-call-panel',
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
        StateError('native media callback failed'),
        StackTrace.current,
        source: 'platform',
      );
    }, correlationId: 'resenha-call-panel');
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
    addTearDown(diagnostics.close);
    addTearDown(resenha.close);
    final clipboardLimit = resenha.state.retainedBytes - 1;
    expect(clipboardLimit, greaterThan(0));

    final exporter = _NoopExporter();

    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DiagnosticsPanel(
            controller: diagnostics,
            resenhaController: resenha,
            resenhaReportExporter: exporter,
            resenhaClipboardByteLimit: clipboardLimit,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('diagnostics-top-level-tabs')),
      findsOneWidget,
    );
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Resenha'), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics-search')), findsOneWidget);

    await tester.tap(find.text('Resenha'));
    await tester.pumpAndSettle();

    expect(find.text('Recording Off'), findsOneWidget);
    expect(find.textContaining('/latest.json'), findsNothing);
    expect(find.byKey(const ValueKey('diagnostics-freeze')), findsNothing);
    expect(
      find.byKey(const ValueKey('resenha-diagnostics-search')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('resenha-diagnostics-search')),
      'call.safe.before_capture',
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('resenha-diagnostics-timeline')),
        matching: find.text('call.safe.before_capture'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('resenha-diagnostics-clear-search')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('resenha-diagnostics-search')),
      '/resenha/rooms/42/join',
    );
    await tester.pump();
    expect(find.text('POST /resenha/rooms/42/join?token'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('resenha-diagnostics-clear-search')),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('resenha-copy-report')));
    await tester.pumpAndSettle();
    expect(copied, hasLength(1));
    expect(copied.single, contains('"truncated":true'));
    expect(copied.single, contains('"deepRetainedBytes"'));
    expect(copied.single, isNot(contains('private')));

    await tester.tap(find.byKey(const ValueKey('resenha-export-report')));
    await tester.pumpAndSettle();
    final report = exporter.reports.single;
    expect(report, contains('"origin":"ordinary"'));
    expect(report, contains('"origin":"deep"'));
    expect(report, contains('call.safe.before_capture'));
    expect(report, contains('peer.ice.failed'));
    expect(report, contains('/resenha/rooms/42/join?token'));
    expect(report, contains('/resenha/rooms/42/signal?token'));
    expect(report, contains('SocketException'));
    expect(report, isNot(contains('private')));
    expect(report, isNot(contains('198.51.100.77')));
    expect(report, isNot(contains('203.0.113.91')));
    expect(report, isNot(contains('203.0.113.92')));
    expect(report, isNot(contains('HTTP_ERROR_MESSAGE_SENTINEL')));
    expect(report, isNot(contains('HTTP_STACK_SENTINEL')));
    expect(report, isNot(contains('PRIVATE_HTTP_REASON_SENTINEL')));
    expect(report, isNot(contains('PRIVATE_HTTP_HEADER_SENTINEL')));
    expect(report, isNot(contains('forum.example')));
    expect(report, isNot(contains('/latest.json')));
    expect(RegExp('call.join.captured').allMatches(report), hasLength(1));
    final reportTimestamps = const LineSplitter()
        .convert(report)
        .skip(1)
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .map((line) => line['event']! as Map<String, Object?>)
        .map((event) => DateTime.parse(event['timestampUtc']! as String))
        .toList();
    for (var index = 1; index < reportTimestamps.length; index += 1) {
      expect(
        reportTimestamps[index].isBefore(reportTimestamps[index - 1]),
        isFalse,
        reason: 'JSONL event lines must remain chronological',
      );
    }

    await tester.tap(find.text('General'));
    await tester.pump();
    expect(find.byKey(const ValueKey('diagnostics-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics-freeze')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await diagnostics.close();
    await resenha.close();
  });
}

final class _NoopExporter
    implements ResenhaReportExporter, StreamingResenhaReportExporter {
  final List<String> reports = [];

  @override
  String get actionLabel => 'Save report';

  @override
  Future<ResenhaReportExportOutcome> export(
    String report, {
    Rect? sharePositionOrigin,
  }) async {
    reports.add(report);
    return ResenhaReportExportOutcome.saved;
  }

  @override
  Future<ResenhaReportExportOutcome> exportGenerated(
    ResenhaReportWriter writer, {
    Rect? sharePositionOrigin,
  }) async {
    final output = StringBuffer();
    await writer(output);
    reports.add(output.toString());
    return ResenhaReportExportOutcome.saved;
  }
}
