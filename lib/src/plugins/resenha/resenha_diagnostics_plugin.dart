import 'package:flutter/material.dart';

import '../../diagnostics/diagnostics_controller.dart';
import '../../diagnostics/resenha_report_exporter.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/resenha_diagnostics_view.dart';
import 'resenha_diagnostics.dart';
import 'resenha_diagnostics_report.dart';
import 'resenha_sdk_diagnostics.dart';

/// Resenha's complete app-level diagnostics integration.
///
/// This object is registered both as a lifecycle and as a diagnostics
/// capability. The session receives only its recorder interface, while core
/// discovers the generic [DiagnosticsPlugin] surface through the registry.
final class ResenhaDiagnosticsPlugin extends PluginAppLifecycle
    implements SitePlugin, DiagnosticsPlugin, ResenhaDiagnosticsRecorder {
  ResenhaDiagnosticsPlugin({
    ResenhaDiagnosticsController? controller,
    ResenhaReportExporter? exporter,
  }) : this._(controller, exporter ?? NativeResenhaReportExporter());

  ResenhaDiagnosticsPlugin._(this._controller, this._exporter);

  ResenhaDiagnosticsController? _controller;
  final ResenhaReportExporter _exporter;

  @override
  String get name => 'resenha';

  @override
  String get diagnosticsId => 'resenha';

  @override
  String get diagnosticsLabel => 'Resenha';

  @override
  Listenable get diagnosticsStatusListenable =>
      _controller?.captureEnabledListenable ?? const _NeverListenable();

  @override
  bool get isDiagnosticsRecording => _controller?.captureEnabled ?? false;

  @override
  String? get diagnosticsRecordingLabel =>
      isDiagnosticsRecording ? 'Resenha capture recording' : null;

  @override
  Future<void> startPhase(PluginStartupPhase phase) async {
    if (phase != PluginStartupPhase.bootstrap || _controller != null) return;
    _controller = await ResenhaDiagnosticsController.create(
      sdkLogBridges: [NativeResenhaDiagnosticsSdkLogBridge()],
    );
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.close();
  }

  @override
  bool get captureEnabled => _controller?.captureEnabled ?? false;

  @override
  void record(
    String event, {
    String component = 'runtime',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  }) {
    _controller?.record(
      event,
      component: component,
      severity: severity,
      correlationId: correlationId,
      data: data,
    );
  }

  @override
  void recordRaw(
    String event, {
    String component = 'sdk',
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
  }) {
    _controller?.recordRaw(
      event,
      component: component,
      severity: severity,
      correlationId: correlationId,
      message: message,
      data: data,
    );
  }

  @override
  void recordAppLifecycle(String state, {required bool foreground}) {
    record(
      'app.lifecycle.changed',
      component: 'app',
      data: {'state': state, 'foreground': foreground},
    );
  }

  @override
  Future<void> flushDiagnostics() async => _controller?.flush();

  @override
  Widget buildDiagnostics(
    BuildContext context,
    DiagnosticsController diagnostics,
  ) {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: Text('Resenha diagnostics are unavailable.'));
    }
    final report = ResenhaDiagnosticsReport(
      diagnostics: diagnostics,
      resenha: controller,
    );
    return ResenhaDiagnosticsView(
      stateListenable: controller.stateListenable,
      eventsListenable: Listenable.merge([
        controller.eventsListenable,
        diagnostics.eventsListenable,
      ]),
      readState: () {
        final state = controller.state;
        return ResenhaDiagnosticsUiState(
          enabled: state.enabled,
          captureId: state.captureId,
          startedAtUtc: state.startedAtUtc,
          retainedBytes: state.retainedBytes,
          droppedRecords: state.droppedRecords,
          truncated: state.truncated,
        );
      },
      readEvents: () => report.events,
      startCapture: controller.startCapture,
      stopCapture: controller.stopCapture,
      clear: controller.clear,
      buildJsonReport: report.buildJson,
      buildClipboardReport: report.buildClipboard,
      writeJsonReportTo: report.writeJsonTo,
      exporter: _exporter,
    );
  }
}

final class _NeverListenable implements Listenable {
  const _NeverListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
