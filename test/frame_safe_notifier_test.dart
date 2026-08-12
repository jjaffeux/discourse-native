import 'package:discourse_native/src/foundation/frame_safe_notifier.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notifies immediately outside layout', (tester) async {
    final notifier = FrameSafeValueNotifier(0);
    addTearDown(notifier.dispose);
    var notifications = 0;
    notifier.addListener(() => notifications++);

    notifier.value = 1;

    expect(notifications, 1);
    expect(notifier.value, 1);
  });

  testWidgets('coalesces notifications raised while building', (tester) async {
    final notifier = FrameSafeValueNotifier(0);
    addTearDown(notifier.dispose);
    var notifications = 0;
    notifier.addListener(() => notifications++);

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          notifier.value = 1;
          notifier.value = 2;
          return const SizedBox.shrink();
        },
      ),
    );

    expect(notifier.value, 2);
    expect(notifications, 1);
  });

  testWidgets('does not dirty an ancestor during a descendant build', (
    tester,
  ) async {
    final notifier = FrameSafeValueNotifier(0);
    addTearDown(notifier.dispose);
    var builds = 0;

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: notifier,
        builder: (context, child) {
          builds += 1;
          return Builder(
            builder: (context) {
              if (notifier.value == 0) notifier.value = 1;
              return const SizedBox.shrink();
            },
          );
        },
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(notifier.value, 1);
    expect(builds, 2);
  });

  testWidgets('drops a deferred notification after disposal', (tester) async {
    final notifier = FrameSafeValueNotifier(0);
    var notifications = 0;
    notifier.addListener(() => notifications++);

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          notifier.value = 1;
          notifier.dispose();
          return const SizedBox.shrink();
        },
      ),
    );

    expect(notifications, 0);
  });
}
