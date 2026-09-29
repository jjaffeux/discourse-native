// Opt-in operation tracing (debug timings are not native frame evidence):
// flutter test --enable-vmservice --dart-define=CATEGORY_LAYOUT_TRACE=true \
//   test/category_grid_layout_trace_test.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service_io.dart';

import 'support/category_grid_fixture.dart';

void main() {
  for (final copies in [1, 5]) {
    for (final width in [390.0, 700.0, 1100.0]) {
      testWidgets('category layout trace ${copies * 12} at $width', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final categories = categoryGridFixture(copies: copies);
        final controller = await categoryGridController(categories);
        addTearDown(controller.dispose);
        final service = await tester.runAsync(() async {
          final info = await developer.Service.getInfo();
          final service = await vmServiceConnectUri(
            info.serverWebSocketUri!.toString(),
          );
          await service.setVMTimelineFlags(['Dart']);
          return service;
        });
        for (var repeat = 0; repeat < 4; repeat++) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() => service!.clearVMTimeline());
          debugProfileLayoutsEnabled = true;
          final geometry = <String, List<double>>{};
          void capture() {
            for (final c in categories) {
              final card = find.byKey(ValueKey('category-row-${c.id}'));
              if (card.evaluate().isNotEmpty) {
                final r = tester.getRect(card);
                geometry['${c.id}'] = [r.left, r.width, r.height];
              }
            }
          }

          final start = developer.Timeline.now;
          await tester.pumpWidget(categoryGridHost(controller, width));
          await tester.pumpAndSettle();
          capture();
          final scroll = tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!;
          for (var i = 0; i < 30; i++) {
            scroll.jumpTo(
              (scroll.offset + 180).clamp(0, scroll.position.maxScrollExtent),
            );
            await tester.pump();
            capture();
          }
          final end = developer.Timeline.now;
          debugProfileLayoutsEnabled = false;
          await tester.runAsync(() async {
            final timeline = await service!.getVMTimeline(
              timeOriginMicros: start,
              timeExtentMicros: end - start,
            );
            final counts = <String, int>{};
            for (final event in timeline.traceEvents!) {
              final json = event.json!;
              if (json['ph'] == 'B' || json['ph'] == 'X') {
                counts.update(
                  json['name'] as String,
                  (n) => n + 1,
                  ifAbsent: () => 1,
                );
              }
            }
            final result = {'counts': counts, 'geometry': geometry};
            File(
              '/tmp/category-trace-${copies * 12}-$width-$repeat.json',
            ).writeAsStringSync(jsonEncode(result));
          });
        }
        await tester.runAsync(() => service!.dispose());
      }, skip: !const bool.fromEnvironment('CATEGORY_LAYOUT_TRACE'));
    }
  }
}
