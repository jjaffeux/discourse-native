import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The builder is made once, so a rebuild of what holds it leaves it alone
  // and every build counted is one its listenable asked for.
  Widget builder(Listenable listenable, VoidCallback onBuild) =>
      DShownListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          onBuild();
          return const SizedBox.shrink();
        },
      );

  Widget host({required bool shown, required Widget child}) =>
      TickerMode(enabled: shown, child: child);

  testWidgets('builds for each change while it can be seen', (tester) async {
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    var builds = 0;
    await tester.pumpWidget(
      host(shown: true, child: builder(changes, () => builds++)),
    );
    expect(builds, 1);

    changes.notifyListeners();
    await tester.pump();
    changes.notifyListeners();
    await tester.pump();
    expect(builds, 3);
  });

  testWidgets('holds changes while out of sight and catches up once', (
    tester,
  ) async {
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    var builds = 0;
    final child = builder(changes, () => builds++);
    await tester.pumpWidget(host(shown: false, child: child));
    expect(builds, 1);

    for (var change = 0; change < 5; change++) {
      changes.notifyListeners();
      await tester.pump();
    }
    expect(builds, 1);

    // Shown again, it is current in that same frame, and only once.
    await tester.pumpWidget(host(shown: true, child: child));
    expect(builds, 2);
    await tester.pump();
    expect(builds, 2);
  });

  testWidgets('shown again with nothing held, it stands as built', (
    tester,
  ) async {
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    var builds = 0;
    final child = builder(changes, () => builds++);
    await tester.pumpWidget(host(shown: false, child: child));
    await tester.pumpWidget(host(shown: true, child: child));
    await tester.pump();
    expect(builds, 1);
  });

  testWidgets('follows a replaced listenable and leaves the old one', (
    tester,
  ) async {
    final first = ChangeNotifier();
    final second = ChangeNotifier();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var builds = 0;
    void onBuild() => builds++;
    await tester.pumpWidget(host(shown: true, child: builder(first, onBuild)));
    await tester.pumpWidget(host(shown: true, child: builder(second, onBuild)));
    final afterSwap = builds;

    first.notifyListeners();
    await tester.pump();
    expect(builds, afterSwap);
    second.notifyListeners();
    await tester.pump();
    expect(builds, afterSwap + 1);
  });
}
