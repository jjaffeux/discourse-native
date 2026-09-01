import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import 'voice_diagnostics.dart';
import 'voice_diagnostics_report.dart';
import 'voice_diagnostics_view.dart';
import 'voice_report_exporter.dart';
import 'voice_sdk_diagnostics.dart';

/// This object is registered both as a lifecycle and as a diagnostics
/// capability. The session receives only its recorder interface, while core
/// discovers the generic [DiagnosticsPlugin] surface through the registry.
final class VoiceDiagnosticsPlugin extends PluginAppLifecycle
    implements
        SitePlugin,
        DiagnosticsPlugin,
        VoiceDiagnosticsRecorder,
        VoiceDiagnosticsFlusher {
  VoiceDiagnosticsPlugin({
    VoiceDiagnosticsController? controller,
    VoiceReportExporter? exporter,
  }) : this._(
         controller,
         exporter ?? NativeVoiceReportExporter(),
         ownsController: false,
       );

  VoiceDiagnosticsPlugin._(
    this._controller,
    this._exporter, {
    required this._ownsController,
  }) {
    _controller?.captureEnabledListenable.addListener(_notifyStatusChanged);
  }

  VoiceDiagnosticsController? _controller;
  final VoiceReportExporter _exporter;
  bool _ownsController;
  final _DiagnosticsStatusListenable _diagnosticsStatus =
      _DiagnosticsStatusListenable();
  bool _closed = false;

  @override
  String get name => 'voice';

  @override
  String get diagnosticsId => 'voice';

  @override
  String get diagnosticsLabel => 'Voice';

  @override
  Listenable get diagnosticsStatusListenable => _diagnosticsStatus;

  @override
  bool get isDiagnosticsRecording => _controller?.captureEnabled ?? false;

  @override
  String? get diagnosticsRecordingLabel =>
      isDiagnosticsRecording ? 'Voice capture recording' : null;

  @override
  Future<void> startPhase(
    PluginStartupPhase phase,
    PluginHostBindings bindings,
  ) async {
    if (phase != PluginStartupPhase.bootstrap) return;
    final reporter = bindings.require(pluginDiagnosticsReporterPort);
    if (_controller != null || _closed) return;
    final controller = await VoiceDiagnosticsController.create(
      reporter: reporter,
      sdkLogBridges: [NativeVoiceDiagnosticsSdkLogBridge()],
    );
    if (_closed) {
      await controller.close();
      return;
    }
    _ownsController = true;
    _replaceController(controller);
  }

  @override
  Future<void> close() async {
    _closed = true;
    final controller = _controller;
    final ownsController = _ownsController;
    _ownsController = false;
    _replaceController(null);
    if (ownsController) await controller?.close();
  }

  void _replaceController(VoiceDiagnosticsController? controller) {
    if (identical(_controller, controller)) return;
    _controller?.captureEnabledListenable.removeListener(_notifyStatusChanged);
    _controller = controller;
    controller?.captureEnabledListenable.addListener(_notifyStatusChanged);
    _notifyStatusChanged();
  }

  void _notifyStatusChanged() => _diagnosticsStatus.changed();

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
  void observeAppState(String state, {required bool foreground}) {
    record(
      'app.lifecycle.changed',
      component: 'app',
      data: {'state': state, 'foreground': foreground},
    );
  }

  @override
  Future<void> flush() async => _controller?.flush();

  @override
  Future<void> flushDiagnostics() => flush();

  @override
  Widget buildDiagnostics(
    BuildContext context,
    PluginDiagnosticsReadExportHost diagnostics,
  ) {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: Text('Voice diagnostics are unavailable.'));
    }
    final report = VoiceDiagnosticsReport(
      diagnostics: diagnostics,
      voice: controller,
    );
    return VoiceDiagnosticsView(
      stateListenable: controller.stateListenable,
      eventsListenable: Listenable.merge([
        controller.eventsListenable,
        diagnostics.eventsListenable,
      ]),
      readState: () {
        final state = controller.state;
        return VoiceDiagnosticsUiState(
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

final class _DiagnosticsStatusListenable extends ChangeNotifier {
  void changed() => notifyListeners();
}
