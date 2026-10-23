import 'dart:async';

import 'package:discourse_native/src/ui/foundation/native_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(NativeGlass.resetProbeForTesting);

  tearDown(() {
    messenger.setMockMessageHandler(NativeGlass.channel.name, null);
    NativeGlass.available.value = false;
    NativeGlass.resetProbeForTesting();
  });

  Future<void> onMacOS(Future<void> Function() body) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  }

  testWidgets('the first frame waits for the host to answer the probe', (
    tester,
  ) async {
    await onMacOS(() async {
      final answer = Completer<bool>();
      messenger.setMockMethodCallHandler(
        NativeGlass.channel,
        (call) async => call.method == 'available' ? answer.future : null,
      );

      NativeGlass.probeBeforeFirstFrame();
      await tester.pump();

      expect(tester.binding.sendFramesToEngine, isFalse);
      expect(NativeGlass.available.value, isFalse);

      answer.complete(true);
      await tester.pump();

      expect(NativeGlass.available.value, isTrue);
      expect(tester.binding.sendFramesToEngine, isTrue);
    });
  });

  testWidgets('a host without the glass channel still gets its first frame', (
    tester,
  ) async {
    await onMacOS(() async {
      // An unregistered plugin answers with no envelope at all.
      messenger.setMockMessageHandler(NativeGlass.channel.name, (_) async {
        return null;
      });

      NativeGlass.probeBeforeFirstFrame();
      await tester.pump();

      expect(NativeGlass.available.value, isFalse);
      expect(tester.binding.sendFramesToEngine, isTrue);
    });
  });
}
