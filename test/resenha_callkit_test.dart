import 'package:discourse_native/src/plugins/resenha/resenha_callkit.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _RecordedDiagnostic = ({
  String event,
  String component,
  String? correlationId,
  Map<String, Object?> data,
});

final class _DiagnosticsRecorder implements ResenhaDiagnosticsRecorder {
  final List<_RecordedDiagnostic> records = [];

  @override
  bool get captureEnabled => false;

  @override
  void record(
    String event, {
    String component = 'runtime',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  }) {
    records.add((
      event: event,
      component: component,
      correlationId: correlationId,
      data: data,
    ));
  }

  @override
  void recordRaw(
    String event, {
    String component = 'sdk',
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
  }) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'forwards native diagnostic messages with the call correlation',
    () async {
      final diagnostics = _DiagnosticsRecorder();
      final systemCall = NativeResenhaSystemCall(diagnostics: diagnostics)
        ..associateDiagnostics('call-123');
      addTearDown(systemCall.dispose);

      await systemCall.handleNativeMethodCall(
        const MethodCall('diagnostic', {
          'event': 'callkit.audio.route_changed',
          'component': 'callkit.native',
          'data': {
            'route': 'speaker',
            'participantId': 'private-participant',
            'deviceId': 'private-device',
            'address': '203.0.113.99',
          },
        }),
      );

      final record = diagnostics.records.singleWhere(
        (entry) => entry.event == 'callkit.audio.route_changed',
      );
      expect(record.component, 'callkit.native');
      expect(record.correlationId, 'call-123');
      expect(record.data, {'route': 'speaker'});
    },
  );

  test('a delayed old dispose cannot clear the new CallKit handler', () async {
    final oldDiagnostics = _DiagnosticsRecorder();
    final newDiagnostics = _DiagnosticsRecorder();
    final oldSystemCall = NativeResenhaSystemCall(
      diagnostics: oldDiagnostics,
      installMethodCallHandlerForTesting: true,
    );
    final newSystemCall = NativeResenhaSystemCall(
      diagnostics: newDiagnostics,
      installMethodCallHandlerForTesting: true,
    )..associateDiagnostics('new-call');
    addTearDown(oldSystemCall.dispose);
    addTearDown(newSystemCall.dispose);

    // This models a ShellController disposal which begins only after its
    // replacement has already claimed the process-wide method channel.
    await oldSystemCall.dispose();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'org.discourse.native/resenha_callkit',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('diagnostic', {
              'event': 'callkit.new_owner.event',
              'data': {'owner': 'new'},
            }),
          ),
          null,
        );

    expect(
      oldDiagnostics.records.where(
        (record) => record.event == 'callkit.new_owner.event',
      ),
      isEmpty,
    );
    expect(
      newDiagnostics.records
          .singleWhere((record) => record.event == 'callkit.new_owner.event')
          .correlationId,
      'new-call',
    );
  });
}
