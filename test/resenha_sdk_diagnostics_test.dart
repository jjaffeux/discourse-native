import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_sdk_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:logger/logger.dart' as native_logger;
import 'package:logging/logging.dart' as dart_logging;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SDK cleanup runs every reset and rethrows the first failure', () async {
    final completed = <String>[];
    final firstFailure = StateError('native logger reset failed');

    await expectLater(
      runResenhaSdkCleanup([
        () {
          completed.add('webrtc');
          throw firstFailure;
        },
        () async {
          completed.add('subscription');
        },
        () {
          completed.add('livekit-level');
          throw StateError('level restore also failed');
        },
        () async {
          completed.add('logger');
        },
      ]),
      throwsA(same(firstFailure)),
    );

    expect(completed, ['webrtc', 'subscription', 'livekit-level', 'logger']);
  });

  test(
    'flutter_webrtc logger changes await the native severity hook',
    () async {
      const channel = MethodChannel('FlutterWebRTC.Method');
      final severityInvoked = Completer<void>();
      final releaseSeverity = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setLogSeverity') {
              severityInvoked.complete();
              await releaseSeverity.future;
            }
            return null;
          });
      addTearDown(() {
        if (!releaseSeverity.isCompleted) releaseSeverity.complete();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final logger = native_logger.Logger(
        filter: native_logger.ProductionFilter(),
        level: native_logger.Level.off,
      );
      addTearDown(logger.close);

      var completed = false;
      final setting = rtc.Helper.setLogger(logger, 'none').then((_) {
        completed = true;
      });
      await severityInvoked.future;
      expect(completed, isFalse);

      releaseSeverity.complete();
      await setting;
      expect(completed, isTrue);
    },
  );

  test('a stale bridge cannot disable a newer global SDK capture', () async {
    const channel = MethodChannel('FlutterWebRTC.Method');
    final severities = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setLogSeverity') {
            severities.add(
              (call.arguments as Map<Object?, Object?>)['severity']! as String,
            );
          }
          return null;
        });
    final hierarchicalLogging = dart_logging.hierarchicalLoggingEnabled;
    final baseline = hierarchicalLogging
        ? livekit.logger.level
        : dart_logging.Logger.root.level;
    final nativeWebRtcLogging = Platform.isIOS || Platform.isMacOS;
    final oldBridge = NativeResenhaDiagnosticsSdkLogBridge();
    final newBridge = NativeResenhaDiagnosticsSdkLogBridge();
    final recorder = _RawRecorder();
    addTearDown(() async {
      await newBridge.uninstall();
      await oldBridge.uninstall();
      if (hierarchicalLogging) {
        livekit.logger.level = baseline;
      } else {
        dart_logging.Logger.root.level = baseline;
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await oldBridge.install(recorder);
    await newBridge.install(recorder);
    expect(livekit.getLoggingLevel().name, 'ALL');
    expect(severities, nativeWebRtcLogging ? ['verbose', 'verbose'] : isEmpty);

    await oldBridge.uninstall();
    expect(livekit.getLoggingLevel().name, 'ALL');
    expect(severities, nativeWebRtcLogging ? ['verbose', 'verbose'] : isEmpty);

    await newBridge.uninstall();
    expect(livekit.logger.level, baseline);
    expect(
      severities,
      nativeWebRtcLogging ? ['verbose', 'verbose', 'none'] : isEmpty,
    );
  });
}

final class _RawRecorder implements ResenhaDiagnosticsRecorder {
  @override
  bool get captureEnabled => true;

  @override
  void record(
    String event, {
    String component = 'runtime',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  }) {}

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
