// Run with flutter test --no-pub tool/benchmarks/users_scroll_benchmark.dart
// Debug widget workload benchmark; wall times are not native frame timings.
import 'dart:convert';

import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('users scroll workload', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final columns = List.generate(
      10,
      (i) => UserDirectoryColumn(
        id: i,
        name: 'metric_$i',
        type: UserDirectoryColumnType.automatic,
        position: i,
      ),
    );
    final items = List.generate(
      1000,
      (i) => UserDirectoryItem(
        id: i,
        user: UserDirectoryUser(id: i, username: 'member$i', name: 'Member $i'),
        values: {for (var c = 0; c < 10; c++) 'metric_$c': (i + 1) * (c + 1)},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UsersPage(
            siteUrl: '',
            data: UsersPageData(items: items, columns: columns, loaded: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .singleWhere(
          (state) => state.widget.axisDirection == AxisDirection.down,
        );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 400));
    addTearDown(mouse.removePointer);
    final times = <int>[];
    var builds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) => builds++;
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (var step = 0; step < 240; step++) {
      final clock = Stopwatch()..start();
      scroll.position.jumpTo(step < 120 ? step * 40.0 : (239 - step) * 40.0);
      await tester.pump(const Duration(milliseconds: 16));
      times.add(clock.elapsedMicroseconds);
    }
    times.sort();
    debugPrint(
      jsonEncode({
        'frames': times.length,
        'builds': builds,
        'median_us': times[times.length ~/ 2],
        'p95_us': times[(times.length * .95).floor()],
        'total_us': times.fold<int>(0, (a, b) => a + b),
      }),
    );
    expect(tester.takeException(), isNull);
  });
}
