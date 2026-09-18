import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/profile_foreground_gate.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('startup waits for resumed and rejects a non-resumed timeout', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final gate = ProfileForegroundGate();
    addTearDown(gate.dispose);
    await expectLater(
      gate.waitUntilResumed(timeout: Duration.zero),
      throwsStateError,
    );
    final ready = gate.waitUntilResumed();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await ready;
    expect(await gate.runCapture(() async => 42), 42);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final readyAgain = gate.waitUntilResumed();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await readyAgain;
  });

  test('each capture independently requires resumed', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final gate = ProfileForegroundGate();
    addTearDown(gate.dispose);
    await gate.waitUntilResumed();
    expect(await gate.runCapture(() async => 1), 1);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    var called = false;
    await expectLater(
      gate.runCapture(() async {
        called = true;
      }),
      throwsStateError,
    );
    expect(called, isFalse);
  });

  test(
    'foreground loss rejects without waiting for a stalled capture',
    () async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final gate = ProfileForegroundGate();
      addTearDown(gate.dispose);
      final stalled = Completer<int>();
      final result = gate.runCapture(() => stalled.future);
      final rejected = expectLater(result, throwsStateError);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await rejected;
      expect(stalled.isCompleted, isFalse);
      stalled.complete(1);
    },
  );

  test(
    'resuming before completion cannot rehabilitate an invalid sample',
    () async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final gate = ProfileForegroundGate();
      addTearDown(gate.dispose);
      final pending = Completer<int>();
      final result = gate.runCapture(() => pending.future);
      final rejected = expectLater(result, throwsStateError);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      pending.complete(1);
      await rejected;
    },
  );
}
