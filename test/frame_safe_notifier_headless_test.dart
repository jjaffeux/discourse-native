// Kept apart from frame_safe_notifier_test.dart on purpose: declaring even one
// testWidgets initializes the test binding for the whole file, and this suite
// exists to pin the no-binding contract. Pure-Dart entry points (VM tests,
// tools, secondary isolates) construct controllers whose notifiers must not
// require a scheduler.
import 'package:discourse_native/src/foundation/frame_safe_notifier.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notifies synchronously when no scheduler binding exists', () {
    final notifier = FrameSafeValueNotifier(0);
    addTearDown(notifier.dispose);
    var notifications = 0;
    notifier.addListener(() => notifications++);

    notifier.value = 1;

    expect(notifications, 1);
    expect(notifier.value, 1);
  });

  test('adopts a binding built after the first headless notification', () {
    final notifier = FrameSafeValueNotifier(0);
    addTearDown(notifier.dispose);
    var notifications = 0;
    notifier.addListener(() => notifications++);

    notifier.value = 1;
    expect(notifications, 1);

    // A cached "no binding" would keep answering synchronously forever, which
    // is how a notification lands inside a layout pass.
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);

    notifier.value = 2;
    expect(notifications, 2);
  });

  test('keeps notifying across repeated changes without a binding', () {
    final notifier = FrameSafeValueNotifier(0);
    addTearDown(notifier.dispose);
    final seen = <int>[];
    notifier.addListener(() => seen.add(notifier.value));

    notifier.value = 1;
    notifier.value = 2;
    notifier.value = 2;

    expect(seen, [1, 2]);
  });
}
