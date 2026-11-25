import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'content-sized rows include their trailing controls immediately',
    (tester) async {
      for (final count in ['1234', '123456', '1']) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: IntrinsicWidth(
                  child: DSidebarMenuItem(
                    badge: DSidebarMenuBadge(child: Text(count)),
                    action: DSidebarMenuAction(
                      semanticLabel: 'Project actions',
                      onPressed: () {},
                      child: const Icon(Icons.more_horiz),
                    ),
                    child: DSidebarMenuButton(
                      onPressed: () {},
                      child: const Text('Projects'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final label = tester.renderObject<RenderParagraph>(
          find.text('Projects'),
        );
        expect(
          label.size.width,
          closeTo(label.getMaxIntrinsicWidth(100), .001),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('intrinsic height includes wrapping after trailing reservation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 220,
                child: IntrinsicHeight(
                  child: DSidebarMenuItem(
                    badge: const DSidebarMenuBadge(child: Text('1234')),
                    child: DSidebarMenuButton(
                      onPressed: () {},
                      child: const Text('Project navigation'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final label = tester.renderObject<RenderParagraph>(
      find.text('Project navigation'),
    );
    expect(
      label.size.height,
      closeTo(label.getMaxIntrinsicHeight(label.size.width), .001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dry layout predicts resized rows with wrapping badges', (
    tester,
  ) async {
    Future<void> show(double width) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: UnconstrainedBox(
              constrainedAxis: Axis.horizontal,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: DSidebarMenuItem(
                  badge: const DSidebarMenuBadge(
                    child: Wrap(children: [Text('Live'), Text('1234')]),
                  ),
                  child: DSidebarMenuButton(
                    onPressed: () {},
                    child: const Text('Project navigation'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await show(300);
    for (final width in [180.0, 260.0, 200.0]) {
      final row = tester.renderObject<RenderBox>(find.byType(DSidebarMenuItem));
      final expected = row.getDryLayout(BoxConstraints.tightFor(width: width));
      await show(width);
      expect(tester.getSize(find.byType(DSidebarMenuItem)), expected);
      expect(tester.takeException(), isNull);
    }
  });

  for (final direction in TextDirection.values) {
    testWidgets('a nested submenu paints every ancestor guide in $direction', (
      tester,
    ) async {
      const capture = ValueKey('ancestor-guide-capture');
      Widget row(int depth) => DSidebarMenuButton(
        key: ValueKey(('row', depth)),
        icon: SizedBox(key: ValueKey(('mark', depth)), width: 18, height: 18),
        iconSize: 18,
        onPressed: () {},
        child: Text('Category $depth'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Directionality(
              textDirection: direction,
              child: RepaintBoundary(
                key: capture,
                child: DSidebarContent.slivers(
                  slivers: [
                    DSidebarMenu.sliverBuilder(
                      itemCount: 1,
                      itemExtent: 30,
                      itemBuilder: (_, _) => row(0),
                    ),
                    for (var depth = 1; depth <= 2; depth++)
                      DSidebarMenuSub.sliverBuilder(
                        depth: depth,
                        itemCount: 1,
                        itemExtent: 30,
                        itemBuilder: (_, _) => row(depth),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final marks = [
        for (var depth = 0; depth <= 2; depth++)
          tester.getCenter(find.byKey(ValueKey(('mark', depth)))),
      ];
      final sign = direction == TextDirection.ltr ? 1 : -1;
      expect(marks[1].dx - marks[0].dx, 18 * sign);
      expect(marks[2].dx - marks[1].dx, 18 * sign);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final origin = tester.getTopLeft(find.byKey(capture));
      final rowY = (marks[2].dy - origin.dy).floor();
      final guideX = [
        for (final mark in marks.take(2))
          (mark.dx - origin.dx).floor() -
              (direction == TextDirection.rtl ? 1 : 0),
      ];
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int pixel(int x) => pixels.getUint32(4 * (rowY * image.width + x));
          for (final x in guideX) {
            expect(pixel(x), isNot(pixel(x - 2 * sign)));
          }
          expect(pixel(guideX.first), pixel(guideX.last));
        } finally {
          image.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    });
  }

  for (final submenu in [false, true]) {
    testWidgets('lazy row focus follows its stable key (submenu=$submenu)', (
      tester,
    ) async {
      var values = ['first', 'second', 'third'];
      String? selected;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                Widget row(BuildContext context, int index) {
                  final value = values[index];
                  return DSidebarMenuButton(
                    key: ValueKey(value),
                    onPressed: () => selected = value,
                    child: Text(value),
                  );
                }

                int? findIndex(Key key) {
                  final index = values.indexOf((key as ValueKey<String>).value);
                  return index < 0 ? null : index;
                }

                return DSidebarContent.slivers(
                  slivers: [
                    if (submenu)
                      DSidebarMenuSub.sliverBuilder(
                        itemCount: values.length,
                        itemExtent: 32,
                        itemBuilder: row,
                        findChildIndexCallback: findIndex,
                      )
                    else
                      DSidebarMenu.sliverBuilder(
                        itemCount: values.length,
                        itemExtent: 32,
                        itemBuilder: row,
                        findChildIndexCallback: findIndex,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final focused = tester
          .widget<FocusableActionDetector>(
            find.descendant(
              of: find.byKey(const ValueKey('first')),
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!;
      focused.requestFocus();
      await tester.pump();
      update(() => values = ['third', 'second', 'first']);
      await tester.pump();
      expect(focused.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, 'first');
      expect(tester.takeException(), isNull);
    });
  }
}
