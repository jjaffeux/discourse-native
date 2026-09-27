import 'dart:ui' show AppLifecycleState;

import 'package:discourse_native/src/foundation/foreground_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only hidden, paused and detached leave the foreground', () {
    expect(isForegroundLifecycle(null), isTrue);
    expect(isForegroundLifecycle(AppLifecycleState.resumed), isTrue);
    // A desktop window that lost focus to another app is still on screen.
    expect(isForegroundLifecycle(AppLifecycleState.inactive), isTrue);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      expect(isForegroundLifecycle(state), isFalse, reason: state.name);
    }
  });
}
