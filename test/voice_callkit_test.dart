import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _RecordedDiagnostic = ({
  String event,
  String component,
  String? correlationId,
  Map<String, Object?> data,
});

final class _DiagnosticsRecorder implements VoiceDiagnosticsRecorder {
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

final class _FakeAudioSession implements VoiceAudioSession {
  _FakeAudioSession(this.name, this.state);

  final String name;
  final _AudioState state;
  Completer<void>? prepareStarted;
  Completer<void>? prepareGate;
  Completer<void>? resetStarted;
  Completer<void>? resetGate;

  @override
  Future<void> prepare() async {
    state.calls.add('$name.prepare');
    prepareStarted?.complete();
    await prepareGate?.future;
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

Future<void> _sendNativeCommands(NativeVoiceSystemCall systemCall) async {
  await Future.wait([
    systemCall.start(roomName: 'Room', siteName: 'Forum'),
    systemCall.connected(),
    systemCall.failed(),
    systemCall.setMuted(true),
    systemCall.setMuted(false),
    systemCall.end(),
    systemCall.answerIncomingCall(),
    systemCall.declineIncomingCall(),
    systemCall.endIncomingCall(VoiceIncomingCallEndReason.unanswered),
    systemCall.endIncomingCall(VoiceIncomingCallEndReason.answeredElsewhere),
  ]);
}

Future<bool> _reportIncomingCall(NativeVoiceSystemCall systemCall) => systemCall
    .reportIncomingCall(callerName: 'Kim', roomName: 'Call', handle: 'kim');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'forwards native diagnostic messages with the call correlation',
    () async {
      final diagnostics = _DiagnosticsRecorder();
      final systemCall = NativeVoiceSystemCall(diagnostics: diagnostics)
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

  test('system answer and decline arrive as call actions', () async {
    final systemCall = NativeVoiceSystemCall(
      installMethodCallHandlerForTesting: true,
    );
    addTearDown(systemCall.dispose);
    final actions = <VoiceSystemCallAction>[];
    systemCall.actions.listen(actions.add);

    await systemCall.handleNativeMethodCall(const MethodCall('answer'));
    await systemCall.handleNativeMethodCall(const MethodCall('decline'));
    await systemCall.handleNativeMethodCall(const MethodCall('end'));
    await pumpEventQueue();

    expect(actions, [
      VoiceSystemCallAction.answer,
      VoiceSystemCallAction.decline,
      VoiceSystemCallAction.end,
    ]);
  });

  test('a ring is not presented where there is no system call UI', () async {
    final diagnostics = _DiagnosticsRecorder();
    final systemCall = NativeVoiceSystemCall(diagnostics: diagnostics);
    addTearDown(systemCall.dispose);

    expect(
      await systemCall.reportIncomingCall(
        callerName: 'Kim',
        roomName: 'Call',
        handle: 'kim',
      ),
      isFalse,
    );
    expect(
      diagnostics.records
          .singleWhere((record) => record.event == 'callkit.command.skipped')
          .data,
      {'method': 'reportIncomingCall'},
    );
  }, skip: Platform.isIOS ? 'exercises the non-iOS fallback' : false);

  test('a delayed old dispose cannot clear the new CallKit handler', () async {
    final oldDiagnostics = _DiagnosticsRecorder();
    final newDiagnostics = _DiagnosticsRecorder();
    final oldSystemCall = NativeVoiceSystemCall(
      diagnostics: oldDiagnostics,
      installMethodCallHandlerForTesting: true,
    );
    final newSystemCall = NativeVoiceSystemCall(
      diagnostics: newDiagnostics,
      installMethodCallHandlerForTesting: true,
    )..associateDiagnostics('new-call');
    addTearDown(oldSystemCall.dispose);
    addTearDown(newSystemCall.dispose);

    await oldSystemCall.dispose();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'org.discourse.native/voice_callkit',
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
      final oldSystemCall = NativeVoiceSystemCall(
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
      final newSystemCall = NativeVoiceSystemCall(
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
    final oldSystemCall = NativeVoiceSystemCall(
      audioSessionForTesting: oldAudio,
    );
    await oldSystemCall.audioSessionReadyForTesting;

    final newAudio = _FakeAudioSession('new', state);
    final newSystemCall = NativeVoiceSystemCall(
      audioSessionForTesting: newAudio,
    );
    addTearDown(newSystemCall.dispose);
    await newSystemCall.audioSessionReadyForTesting;

    await oldSystemCall.dispose();

    expect(state.calls, ['old.prepare', 'new.prepare']);
    expect(state.owner, 'new');
    expect(state.mode, 'external');
  });

  group('native commands', () {
    const channel = MethodChannel('org.discourse.native/voice_callkit');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> commands;
    Future<Object?> Function(MethodCall)? respond;

    setUp(() {
      commands = [];
      respond = null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        commands.add(call);
        if (respond case final handler?) return handler(call);
        return call.method == 'reportIncomingCall' ? true : null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    NativeVoiceSystemCall createSystemCall({
      _FakeAudioSession? audio,
      VoiceDiagnosticsRecorder diagnostics =
          const NoopVoiceDiagnosticsRecorder(),
    }) {
      final systemCall = NativeVoiceSystemCall(
        diagnostics: diagnostics,
        audioSessionForTesting:
            audio ?? _FakeAudioSession('current', _AudioState()),
        invokeNativeCommandsForTesting: true,
      );
      addTearDown(systemCall.dispose);
      return systemCall;
    }

    for (final retirement in ['disposal', 'replacement']) {
      test(
        'drops commands waiting for audio prepare after $retirement',
        () async {
          final state = _AudioState();
          final prepareStarted = Completer<void>();
          final prepareGate = Completer<void>();
          final oldSystemCall = createSystemCall(
            audio: _FakeAudioSession('old', state)
              ..prepareStarted = prepareStarted
              ..prepareGate = prepareGate,
          );
          final pendingCommands = _sendNativeCommands(oldSystemCall);
          final report = _reportIncomingCall(oldSystemCall);
          late Future<void> retired;
          try {
            await prepareStarted.future;
            retired = retirement == 'disposal'
                ? oldSystemCall.dispose()
                : createSystemCall(
                    audio: _FakeAudioSession('new', state),
                  ).audioSessionReadyForTesting;
            expect(commands, isEmpty);
          } finally {
            prepareGate.complete();
          }

          await retired;
          await pendingCommands;
          expect(commands, isEmpty);
          expect(await report, isFalse);
          expect(state.calls, [
            'old.prepare',
            if (retirement == 'disposal') 'old.reset' else 'new.prepare',
          ]);

          await _sendNativeCommands(oldSystemCall);
          expect(await _reportIncomingCall(oldSystemCall), isFalse);
          expect(commands, isEmpty);
        },
      );

      test('ignores an audio prepare error after $retirement', () async {
        final prepareStarted = Completer<void>();
        final prepareGate = Completer<void>();
        final diagnostics = _DiagnosticsRecorder();
        final oldSystemCall = createSystemCall(
          diagnostics: diagnostics,
          audio: _FakeAudioSession('old', _AudioState())
            ..prepareStarted = prepareStarted
            ..prepareGate = prepareGate,
        );
        final commandCompletes = expectLater(oldSystemCall.end(), completes);
        final report = _reportIncomingCall(oldSystemCall);
        late Future<void> retired;
        try {
          await prepareStarted.future;
          retired = retirement == 'disposal'
              ? oldSystemCall.dispose()
              : createSystemCall().audioSessionReadyForTesting;
        } finally {
          prepareGate.completeError(StateError('prepare failed'));
        }

        await retired;
        await commandCompletes;
        expect(await report, isFalse);
        expect(commands, isEmpty);
        expect(
          diagnostics.records.where(
            (record) => record.event == 'callkit.command.failed',
          ),
          isEmpty,
        );
      });

      for (final outcome in ['success', 'error']) {
        test('ignores native $outcome arriving after $retirement', () async {
          final nativeStarted = Completer<void>();
          final response = Completer<Object?>();
          respond = (_) {
            if (commands.length == 2) nativeStarted.complete();
            return response.future;
          };
          final diagnostics = _DiagnosticsRecorder();
          final oldSystemCall = createSystemCall(diagnostics: diagnostics);
          final commandCompletes = expectLater(oldSystemCall.end(), completes);
          final report = _reportIncomingCall(oldSystemCall);
          try {
            await nativeStarted.future;
            if (retirement == 'disposal') {
              await oldSystemCall.dispose();
            } else {
              await createSystemCall().audioSessionReadyForTesting;
            }
          } finally {
            if (outcome == 'success') {
              response.complete(true);
            } else {
              response.completeError(PlatformException(code: 'retired'));
            }
          }

          await commandCompletes;
          expect(await report, isFalse);
          expect(commands, [
            isMethodCall('end', arguments: null),
            isMethodCall(
              'reportIncomingCall',
              arguments: {
                'callerName': 'Kim',
                'roomName': 'Call',
                'handle': 'kim',
              },
            ),
          ]);
          expect(
            diagnostics.records.where(
              (record) => const {
                'callkit.command.completed',
                'callkit.command.failed',
              }.contains(record.event),
            ),
            isEmpty,
          );
        });
      }
    }

    test('sends current commands and reports after audio is ready', () async {
      final prepareStarted = Completer<void>();
      final prepareGate = Completer<void>();
      final diagnostics = _DiagnosticsRecorder();
      final systemCall = createSystemCall(
        diagnostics: diagnostics,
        audio: _FakeAudioSession('current', _AudioState())
          ..prepareStarted = prepareStarted
          ..prepareGate = prepareGate,
      );
      final pendingCommands = _sendNativeCommands(systemCall);
      final report = _reportIncomingCall(systemCall);
      try {
        await prepareStarted.future;
        expect(commands, isEmpty);
      } finally {
        prepareGate.complete();
      }

      await pendingCommands;
      expect(await report, isTrue);
      expect(commands, [
        isMethodCall(
          'start',
          arguments: {'roomName': 'Room', 'siteName': 'Forum'},
        ),
        isMethodCall('connected', arguments: null),
        isMethodCall('failed', arguments: null),
        isMethodCall('setMuted', arguments: {'muted': true}),
        isMethodCall('setMuted', arguments: {'muted': false}),
        isMethodCall('end', arguments: null),
        isMethodCall('answerIncomingCall', arguments: null),
        isMethodCall('declineIncomingCall', arguments: null),
        isMethodCall('endIncomingCall', arguments: {'reason': 'unanswered'}),
        isMethodCall(
          'endIncomingCall',
          arguments: {'reason': 'answered_elsewhere'},
        ),
        isMethodCall(
          'reportIncomingCall',
          arguments: {'callerName': 'Kim', 'roomName': 'Call', 'handle': 'kim'},
        ),
      ]);
      expect(
        diagnostics.records
            .where((record) => record.event == 'callkit.command.completed')
            .map((record) => record.data),
        [
          for (final command in commands)
            {
              'method': command.method,
              if (command.method == 'reportIncomingCall') 'presented': true,
            },
        ],
      );
    });

    test('preserves current command errors from audio preparation', () async {
      final prepareStarted = Completer<void>();
      final prepareGate = Completer<void>();
      final error = StateError('prepare failed');
      final state = _AudioState();
      final systemCall = createSystemCall(
        audio: _FakeAudioSession('current', state)
          ..prepareStarted = prepareStarted
          ..prepareGate = prepareGate,
      );
      final commandFails = expectLater(systemCall.end(), throwsA(same(error)));
      try {
        await prepareStarted.future;
      } finally {
        prepareGate.completeError(error);
      }

      await commandFails;
      expect(await _reportIncomingCall(systemCall), isFalse);
      await systemCall.dispose();
      expect(commands, isEmpty);
      expect(state.calls, ['current.prepare']);
    });

    test('preserves current native command errors', () async {
      respond = (_) async => throw PlatformException(code: 'command_failed');
      final diagnostics = _DiagnosticsRecorder();
      final systemCall = createSystemCall(diagnostics: diagnostics);

      await expectLater(
        systemCall.end(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'command_failed',
          ),
        ),
      );

      expect(commands, [isMethodCall('end', arguments: null)]);
      expect(
        diagnostics.records
            .singleWhere((record) => record.event == 'callkit.command.failed')
            .data,
        {'method': 'end', 'errorType': 'PlatformException'},
      );
    });

    for (final outcome in [
      (name: 'refused', response: false),
      (name: 'null', response: null),
      (name: 'a platform error', response: PlatformException(code: 'refused')),
      (name: 'a missing plugin', response: MissingPluginException()),
    ]) {
      test(
        'returns false when the current report receives ${outcome.name}',
        () async {
          respond = (_) async {
            if (outcome.response case final Exception error) throw error;
            return outcome.response;
          };

          expect(await _reportIncomingCall(createSystemCall()), isFalse);
          expect(commands, [
            isMethodCall(
              'reportIncomingCall',
              arguments: {
                'callerName': 'Kim',
                'roomName': 'Call',
                'handle': 'kim',
              },
            ),
          ]);
        },
      );
    }
  });
}
