// flutter run --profile -d macos -t tool/benchmarks/users_native_scroll.dart
// Offline native frame benchmark. Automatically scrolls and logs JSON frame timings.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

final _page = GlobalKey();

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
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
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: UsersPage(
          key: _page,
          siteUrl: '',
          data: UsersPageData(items: items, columns: columns, loaded: true),
        ),
      ),
    ),
  );
  binding.addPostFrameCallback((_) => unawaited(_measure()));
}

Future<void> _measure() async {
  await Future<void>.delayed(const Duration(seconds: 2));
  ScrollPosition? position;
  void visit(Element element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      final state = element.state as ScrollableState;
      if (state.widget.axisDirection == AxisDirection.down) {
        position = state.position;
      }
    }
    element.visitChildren(visit);
  }

  visit(_page.currentContext! as Element);
  final scroll = position!;
  final frames = <FrameTiming>[];
  void collect(List<FrameTiming> batch) => frames.addAll(batch);
  final binding = WidgetsBinding.instance;
  // Warm layout/shaders before sampling steady scrolling.
  await scroll.animateTo(
    4000,
    duration: const Duration(seconds: 3),
    curve: Curves.linear,
  );
  await scroll.animateTo(
    0,
    duration: const Duration(seconds: 3),
    curve: Curves.linear,
  );
  await Future<void>.delayed(const Duration(seconds: 1));
  binding.addTimingsCallback(collect);
  for (var round = 0; round < 2; round++) {
    await scroll.animateTo(
      8000,
      duration: const Duration(seconds: 4),
      curve: Curves.linear,
    );
    await scroll.animateTo(
      0,
      duration: const Duration(seconds: 4),
      curve: Curves.linear,
    );
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  binding.removeTimingsCallback(collect);
  Map<String, Object> summarize(List<int> values) {
    values.sort();
    return {
      'p50_us': values[values.length ~/ 2],
      'p95_us': values[(values.length * .95).floor()],
      'max_us': values.last,
      'over_16ms': values.where((v) => v > 16667).length,
    };
  }

  final result = {
    'frames': frames.length,
    'build': summarize(
      frames.map((f) => f.buildDuration.inMicroseconds).toList(),
    ),
    'raster': summarize(
      frames.map((f) => f.rasterDuration.inMicroseconds).toList(),
    ),
    'total': summarize(frames.map((f) => f.totalSpan.inMicroseconds).toList()),
  };
  debugPrint('NATIVE_SCROLL ${jsonEncode(result)}');
  exit(0);
}
