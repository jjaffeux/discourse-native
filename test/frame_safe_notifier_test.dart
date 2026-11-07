import 'package:discourse_native/src/foundation/frame_safe_notifier.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'retirement during notification finishes the admitted dispatch and releases listeners',
    (tester) async {
      final notifier = FrameSafeValueNotifier(0);
      final calls = <String>[];
      notifier.addListener(() {
        calls.add('retire');
        notifier.dispose();
        notifier.value = 2;
        notifier.notifyListeners();
      });
      notifier.addListener(() => calls.add('admitted'));
      notifier.value = 1;
      expect(tester.takeException(), isNull);
      expect(calls, ['retire', 'admitted']);
      expect(() => notifier.addListener(() {}), throwsFlutterError);
      expect(notifier.value, 1);
      expect(notifier.dispose, returnsNormally);
      notifier.value = 3;
      expect(calls, ['retire', 'admitted']);
    },
  );

  testWidgets('nested notification retirement waits for the outer dispatch', (
    tester,
  ) async {
    final notifier = FrameSafeValueNotifier(0);
    var admitted = 0;
    notifier.addListener(() {
      if (notifier.value == 1) {
        notifier.value = 2;
      } else {
        notifier.dispose();
      }
    });
    notifier.addListener(() => admitted++);
    notifier.value = 1;
    expect(tester.takeException(), isNull);
    expect(admitted, 2);
    expect(() => notifier.addListener(() {}), throwsFlutterError);
  });

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
