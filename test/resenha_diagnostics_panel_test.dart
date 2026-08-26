import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/diagnostics/resenha_report_exporter.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics_plugin.dart';
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
          totalDuration: const Duration(milliseconds: 180),
          sentBytes: 120,
          receivedBytes: 2048,
        ),
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
            plugins: [
              ResenhaDiagnosticsPlugin(controller: resenha, exporter: exporter),
            ],
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
    expect(copied.single, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('resenha-export-report')));
    await tester.pumpAndSettle();
    expect(exporter.reports.single, isNotEmpty);

    final replacementDiagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'replacement-panel-test',
      clock: () => now,
    );
    final replacementResenha = await ResenhaDiagnosticsController.create(
      persistence: MemoryResenhaDiagnosticsPersistence(),
      captureIdFactory: () => 'replacement-capture',
      clock: () => now,
    );
    addTearDown(replacementDiagnostics.close);
    addTearDown(replacementResenha.close);
    await replacementResenha.startCapture();
    replacementResenha.recordRaw(
      'replacement.controller.event',
      component: 'replacement',
    );
    await replacementResenha.stopCapture();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DiagnosticsPanel(
            controller: replacementDiagnostics,
            plugins: [
              ResenhaDiagnosticsPlugin(
                controller: replacementResenha,
                exporter: exporter,
              ),
            ],
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('replacement.controller.event'), findsOneWidget);
    expect(find.text('call.safe.before_capture'), findsNothing);

    await tester.tap(find.text('General'));
    await tester.pump();
    expect(find.byKey(const ValueKey('diagnostics-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics-freeze')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await replacementResenha.close();
    await replacementDiagnostics.close();
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
