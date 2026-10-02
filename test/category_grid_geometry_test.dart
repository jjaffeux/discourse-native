import 'dart:math' as math;

import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/category_grid_fixture.dart';

void main() {
  for (final width in [390.0, 700.0, 1100.0]) {
    testWidgets('renders real category activity rows at $width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final categories = categoryGridFixture();
      final controller = await categoryGridController(categories);
      addTearDown(controller.dispose);
      await tester.pumpWidget(categoryGridHost(controller, width));
      await tester.pumpAndSettle();
      final geometry = <String, List<double>>{};
      void capture() {
        for (final category in categories) {
          final finder = find.byKey(ValueKey('category-row-${category.id}'));
          if (finder.evaluate().isEmpty) continue;
          final rect = tester.getRect(finder);
          geometry['${category.id}'] = [rect.left, rect.width, rect.height];
        }
      }

      capture();
      final intrinsicRows = find.descendant(
        of: find.byType(CategoriesPage),
        matching: find.byType(IntrinsicHeight),
      );
      expect(intrinsicRows, findsNothing);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      for (var step = 0; step < 30; step++) {
        scroll.jumpTo(
          (scroll.offset + 180).clamp(0, scroll.position.maxScrollExtent),
        );
        await tester.pump();
        capture();
      }
      expect(geometry.length, categories.length);
      final first = geometry.values.first;
      for (final rect in geometry.values) {
        expect(rect[0], first[0]);
        expect(rect[1], first[1]);
        expect(
          rect[1],
          greaterThan(math.min(width, ContentReadingLane.maxWidth) * .8),
        );
        expect(rect[0] + rect[1], lessThanOrEqualTo(width));
        expect(rect[2], greaterThan(0));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
