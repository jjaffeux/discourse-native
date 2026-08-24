import 'dart:convert';

import 'package:discourse_native/src/diagnostics/resenha_report_exporter.dart';
import 'package:discourse_native/src/shell/resenha_diagnostics_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('deep capture requires consent and stops immediately', (
    tester,
  ) async {
    final harness = _Harness();
    await _pumpView(tester, harness);

    expect(find.text('Recording Off'), findsOneWidget);
    expect(find.textContaining('Secrets are redacted'), findsOneWidget);
    expect(find.textContaining('Restarting the app turns'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('resenha-capture-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Turn on deep Resenha capture?'), findsOneWidget);
    expect(find.textContaining('raw SDP and ICE'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(harness.state.value.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('resenha-capture-switch')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('resenha-confirm-start-capture')),
    );
    await tester.pumpAndSettle();

    expect(harness.startCount, 1);
    expect(find.text('Recording On'), findsOneWidget);
    expect(find.text('Capture capture-1'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('resenha-clear-capture')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('resenha-capture-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Turn on deep Resenha capture?'), findsNothing);
    expect(harness.stopCount, 1);
    expect(find.text('Recording Off'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('resenha-clear-capture')));
    await tester.pumpAndSettle();
    expect(find.text('Clear Resenha capture?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('resenha-confirm-clear-capture')),
    );
    await tester.pumpAndSettle();
    expect(harness.clearCount, 1);
  });

  testWidgets('shows metadata and searches latest-first capture details', (
    tester,
  ) async {
    final harness = _Harness(
      state: const ResenhaDiagnosticsUiState(
        enabled: false,
        retainedBytes: 1572864,
        droppedRecords: 3,
        truncated: true,
      ),
      events: [
        _event(
          sequence: 1,
          event: 'room.join.requested',
          component: 'controller',
          message: 'Joining room',
          data: const {'username': 'old-user'},
        ),
        _event(
          sequence: 2,
          event: 'peer.connection.failed',
          component: 'mesh',
          message: 'ICE negotiation failed',
          data: const {'username': 'sam', 'candidate': '10.0.0.2'},
        ),
      ],
    );
    await _pumpView(tester, harness);

    expect(find.text('1.5 MiB'), findsOneWidget);
    expect(find.text('3 dropped'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('resenha-truncated-indicator')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('peer.connection.failed')).dy,
      lessThan(tester.getTopLeft(find.text('room.join.requested')).dy),
    );

    await tester.enterText(
      find.byKey(const ValueKey('resenha-diagnostics-search')),
      'sam',
    );
    await tester.pump();
    expect(find.text('peer.connection.failed'), findsOneWidget);
    expect(find.text('room.join.requested'), findsNothing);

    await tester.tap(find.text('peer.connection.failed'));
    await tester.pump();
    expect(find.text('Event'), findsOneWidget);
    expect(find.textContaining('10.0.0.2'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('resenha-diagnostics-detail-back')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('resenha-diagnostics-search')),
      findsOneWidget,
    );
  });

  testWidgets('an appended tail event alone is projected and search-indexed', (
    tester,
  ) async {
    final projected = <String>[];
    final indexed = <String>[];
    final harness = _Harness(
      events: [
        for (var sequence = 1; sequence <= 2000; sequence += 1)
          _event(
            sequence: sequence,
            event: 'retained.event.$sequence',
            component: 'capture',
            message: 'retained-$sequence',
            data: {'sequence': sequence},
          ),
      ],
    );
    await _pumpView(
      tester,
      harness,
      onEventProjected: projected.add,
      onSearchTextBuilt: indexed.add,
    );

    expect(projected, hasLength(2000));
    expect(indexed, isEmpty);
    projected.clear();

    await tester.enterText(
      find.byKey(const ValueKey('resenha-diagnostics-search')),
      'retained',
    );
    await tester.pump();
    expect(indexed, hasLength(2000));
    indexed.clear();

    harness.append(
      _event(
        sequence: 2001,
        event: 'retained.event.2001',
        component: 'capture',
        message: 'retained-2001',
        data: const {'sequence': 2001},
      ),
    );
    await tester.pump();

    expect(projected, ['2001']);
    expect(indexed, ['2001']);
  });

  testWidgets('copies a bounded recent report and exports the full report', (
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

    final report = [
      for (var index = 0; index < 20; index += 1)
        jsonEncode({'sequence': index, 'message': 'record-$index-${'x' * 30}'}),
    ].join('\n');
    final harness = _Harness(report: report);
    await _pumpView(tester, harness, clipboardByteLimit: 320);

    await tester.tap(find.byKey(const ValueKey('resenha-copy-report')));
    await tester.pumpAndSettle();
    expect(harness.clipboardBuildCount, 1);
    expect(harness.reportBuildCount, 0);
    expect(copied, hasLength(1));
    expect(copied.single, contains('"truncated":true'));
    expect(copied.single, contains('clipboard_limit'));
    expect(copied.single, contains('record-19'));
    expect(copied.single, isNot(contains('record-0-')));

    await tester.tap(find.byKey(const ValueKey('resenha-export-report')));
    await tester.pumpAndSettle();
    expect(harness.reportBuildCount, 0);
    expect(harness.streamingWriteCount, 1);
    expect(harness.exporter.reports, [report]);
    expect(find.text('Resenha report saved'), findsOneWidget);
  });
}

Map<String, Object?> _event({
  required int sequence,
  required String event,
  required String component,
  required String message,
  required Map<String, Object?> data,
}) => {
  'sequence': sequence,
  'timestampUtc': DateTime.utc(2026, 8, 11, 12, 0, sequence).toIso8601String(),
  'event': event,
  'component': component,
  'severity': sequence == 2 ? 'error' : 'info',
  'message': message,
  'data': data,
};

Future<void> _pumpView(
  WidgetTester tester,
  _Harness harness, {
  int clipboardByteLimit = 10 * 1024 * 1024,
  ValueChanged<String>? onEventProjected,
  ValueChanged<String>? onSearchTextBuilt,
}) async {
  tester.view.physicalSize = const Size(440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(harness.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ResenhaDiagnosticsView(
          stateListenable: harness.state,
          eventsListenable: harness.eventsListenable,
          readState: () => harness.state.value,
          readEvents: () => harness.events,
          startCapture: harness.startCapture,
          stopCapture: harness.stopCapture,
          clear: harness.clear,
          buildJsonReport: harness.buildJsonReport,
          buildClipboardReport: harness.buildClipboardReport,
          writeJsonReportTo: harness.writeJsonReportTo,
          exporter: harness.exporter,
          clipboardByteLimit: clipboardByteLimit,
          onEventProjected: onEventProjected,
          onSearchTextBuilt: onSearchTextBuilt,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Harness {
  _Harness({
    ResenhaDiagnosticsUiState state = const ResenhaDiagnosticsUiState(
      enabled: false,
      retainedBytes: 0,
      droppedRecords: 0,
      truncated: false,
    ),
    this.events = const [],
    this.report = '{"kind":"resenha_report"}',
  }) : state = ValueNotifier(state);

  final ValueNotifier<ResenhaDiagnosticsUiState> state;
  final ChangeNotifier eventsListenable = ChangeNotifier();
  final List<Map<String, Object?>> events;
  final String report;
  final _FakeExporter exporter = _FakeExporter();
  int startCount = 0;
  int stopCount = 0;
  int clearCount = 0;
  int reportBuildCount = 0;
  int clipboardBuildCount = 0;
  int streamingWriteCount = 0;

  void append(Map<String, Object?> event) {
    events.add(event);
    eventsListenable.notifyListeners();
  }

  Future<void> startCapture() async {
    startCount += 1;
    state.value = ResenhaDiagnosticsUiState(
      enabled: true,
      captureId: 'capture-1',
      startedAtUtc: DateTime.utc(2026, 8, 11, 12),
      retainedBytes: state.value.retainedBytes,
      droppedRecords: state.value.droppedRecords,
      truncated: state.value.truncated,
    );
  }

  Future<void> stopCapture() async {
    stopCount += 1;
    state.value = ResenhaDiagnosticsUiState(
      enabled: false,
      captureId: state.value.captureId,
      startedAtUtc: state.value.startedAtUtc,
      retainedBytes: state.value.retainedBytes,
      droppedRecords: state.value.droppedRecords,
      truncated: state.value.truncated,
    );
  }

  Future<void> clear() async {
    clearCount += 1;
  }

  Future<String> buildJsonReport() async {
    reportBuildCount += 1;
    return report;
  }

  Future<ResenhaClipboardReport> buildClipboardReport(int byteLimit) async {
    clipboardBuildCount += 1;
    return boundResenhaReportForClipboard(report, byteLimit: byteLimit);
  }

  Future<void> writeJsonReportTo(StringSink output) async {
    streamingWriteCount += 1;
    output.write(report);
  }

  void dispose() {
    state.dispose();
    eventsListenable.dispose();
  }
}

final class _FakeExporter
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
    return export(output.toString(), sharePositionOrigin: sharePositionOrigin);
  }
}
