import 'dart:async';

import 'package:discourse_resenha/src/resenha_callkit.dart';
import 'package:discourse_resenha/src/resenha_diagnostics.dart';
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

final class _AudioState {
  String? owner;
  String mode = 'automatic';
  final List<String> calls = [];
}

final class _FakeAudioSession implements ResenhaAudioSession {
  _FakeAudioSession(this.name, this.state);

  final String name;
  final _AudioState state;
  Completer<void>? resetStarted;
  Completer<void>? resetGate;

  @override
  Future<void> prepare() async {
    state.calls.add('$name.prepare');
    state
      ..owner = name
      ..mode = 'external';
  }

  @override
  Future<void> activate() async {
    state.calls.add('$name.activate');
    state.mode = 'active';
  }

  @override
  Future<void> deactivate() async {
    state.calls.add('$name.deactivate');
    state.mode = 'inactive';
  }

  @override
  Future<void> reset() async {
    state.calls.add('$name.reset');
    resetStarted?.complete();
    await resetGate?.future;
    state
      ..owner = null
      ..mode = 'automatic';
  }
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

      await systemCall.handleNativeMethodCall(
        const MethodCall('diagnostic', {
          'event': 'callkit.provider.end.skipped',
          'component': 'callkit',
          'data': {'reason': 'stale_call', 'callId': 'private-call-id'},
        }),
      );

      expect(
        diagnostics.records
            .singleWhere(
              (entry) => entry.event == 'callkit.provider.end.skipped',
            )
            .data,
        {'reason': 'stale_call'},
      );
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

  test(
    'a delayed old audio reset cannot replace the new session state',
    () async {
      final state = _AudioState();
      final oldAudio = _FakeAudioSession('old', state);
      final oldSystemCall = NativeResenhaSystemCall(
        audioSessionForTesting: oldAudio,
      );
      addTearDown(oldSystemCall.dispose);
      await oldSystemCall.audioSessionReadyForTesting;
      expect(state.owner, 'old');
      expect(state.mode, 'external');

      final resetStarted = Completer<void>();
      final resetGate = Completer<void>();
      addTearDown(() {
        if (!resetGate.isCompleted) resetGate.complete();
      });
      oldAudio
        ..resetStarted = resetStarted
        ..resetGate = resetGate;
      final oldDisposal = oldSystemCall.dispose();
      await resetStarted.future;

      final newAudio = _FakeAudioSession('new', state);
      final newSystemCall = NativeResenhaSystemCall(
        audioSessionForTesting: newAudio,
      );
      addTearDown(newSystemCall.dispose);
      resetGate.complete();

      await oldDisposal;
      await newSystemCall.audioSessionReadyForTesting;

      expect(state.calls, ['old.prepare', 'old.reset', 'new.prepare']);
      expect(state.owner, 'new');
      expect(state.mode, 'external');
    },
  );

  test('an old owner cannot reset audio claimed by its replacement', () async {
    final state = _AudioState();
    final oldAudio = _FakeAudioSession('old', state);
    final oldSystemCall = NativeResenhaSystemCall(
      audioSessionForTesting: oldAudio,
    );
    await oldSystemCall.audioSessionReadyForTesting;

    final newAudio = _FakeAudioSession('new', state);
    final newSystemCall = NativeResenhaSystemCall(
      audioSessionForTesting: newAudio,
    );
    addTearDown(newSystemCall.dispose);
    await newSystemCall.audioSessionReadyForTesting;

    await oldSystemCall.dispose();

    expect(state.calls, ['old.prepare', 'new.prepare']);
    expect(state.owner, 'new');
    expect(state.mode, 'external');
  });
}
