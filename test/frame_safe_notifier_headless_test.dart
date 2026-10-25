// Kept apart from frame_safe_notifier_test.dart on purpose: declaring even one
// testWidgets initializes the test binding for the whole file, and this suite
// exists to pin the no-binding contract. Pure-Dart entry points (VM tests,
// tools, secondary isolates) construct controllers whose notifiers must not
// require a scheduler.
//
// One test, because the binding is a process-wide singleton: once built it
// cannot be torn down, and CI shuffles test order within a file, so a
// separate headless test could run after the binding exists.
import 'package:discourse_native/src/foundation/frame_safe_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'notifies synchronously without a binding and adopts one built later',
    () {
      expect(BindingBase.debugBindingType(), isNull);

      final notifier = FrameSafeValueNotifier(0);
      addTearDown(notifier.dispose);
      final seen = <int>[];
      notifier.addListener(() => seen.add(notifier.value));

      notifier.value = 1;
      notifier.value = 2;
      notifier.value = 2;
      expect(seen, [1, 2]);

      // A cached "no binding" would keep answering synchronously forever,
      // which is how a notification lands inside a layout pass.
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      List<int>? seenDuringLayout;
      binding.addPersistentFrameCallback((_) {
        if (seenDuringLayout != null) return;
        notifier.value = 3;
        seenDuringLayout = [...seen];
      });
      binding
        ..handleBeginFrame(Duration.zero)
        ..handleDrawFrame();

      expect(seenDuringLayout, [1, 2]);
      expect(seen, [1, 2, 3]);
    },
  );
}
