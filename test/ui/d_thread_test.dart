import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'narrow connectors keep their paint inside the slot in both directions',
    (tester) async {
      final key = GlobalKey();
      for (final direction in TextDirection.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: Directionality(
                  textDirection: direction,
                  child: const SizedBox(
                    width: 16,
                    height: 40,
                    child: Row(
                      children: [
                        DThreadConnector(width: 5, junction: 24),
                        SizedBox(width: 11),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final pixels = (await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        }))!;
        final overflow = <Offset>[];
        for (var y = 0; y < 40; y++) {
          for (var x = 0; x < 16; x++) {
            final outside = direction == TextDirection.ltr ? x >= 5 : x < 11;
            if (outside && pixels[(y * 16 + x) * 4 + 3] != 0) {
              overflow.add(Offset(x.toDouble(), y.toDouble()));
            }
          }
        }
        expect(
          overflow,
          isEmpty,
          reason:
              'A connector must not paint over its neighbour in $direction.',
        );
      }
    },
  );

  testWidgets('connector gap passes clicks through to underlay', (
    tester,
  ) async {
    var underlay = 0;
    var connector = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 32,
              height: 40,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => underlay++,
                    ),
                  ),
                  DThreadConnector(
                    width: 32,
                    junction: 20,
                    onPressed: () => connector++,
                    semanticLabel: 'Collapse',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(DThreadConnector));
    await tester.tapAt(origin + const Offset(20, 8));
    expect(connector, 0);
    expect(underlay, 1);
    await tester.tapAt(origin + const Offset(20, 20));
    expect(connector, 1);
    expect(underlay, 1);
  });
  testWidgets('connector activates on its curve and line but not its gaps', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 32,
              height: 40,
              child: DThreadConnector(
                width: 32,
                junction: 20,
                onPressed: () => activations++,
                semanticLabel: 'Collapse replies',
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(DThreadConnector));
    await tester.tapAt(origin + const Offset(20, 8));
    expect(activations, 0);
    await tester.tapAt(origin + const Offset(3, 18));
    expect(activations, 1);
    await tester.tapAt(origin + const Offset(20, 20));
    expect(activations, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 4);
  });

  testWidgets('continuing branches have an unbroken rail and mirror in RTL', (
    tester,
  ) async {
    final key = GlobalKey();
    Future<List<int>> pixels(TextDirection direction, bool continues) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: Directionality(
                textDirection: direction,
                child: SizedBox(
                  width: 32,
                  height: 64,
                  child: DThreadConnector(
                    width: 32,
                    junction: 24,
                    continuesBelow: continues,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final picture = await boundary.toImage(pixelRatio: 1);
        final data = await picture.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        picture.dispose();
        return data!.buffer.asUint32List().toList();
      }))!;
    }

    final branch = await pixels(TextDirection.ltr, true);
    expect(branch[20 * 32 + 1], branch[4 * 32 + 1]);
    expect(branch[56 * 32 + 1], branch[4 * 32 + 1]);
    expect(branch[20 * 32 + 1], isNot(0));
    final terminal = await pixels(TextDirection.ltr, false);
    expect(terminal[56 * 32 + 1], 0);
    final mirrored = await pixels(TextDirection.rtl, true);
    expect(mirrored[20 * 32 + 31], branch[20 * 32 + 1]);
    expect(mirrored[56 * 32 + 31], branch[56 * 32 + 1]);
  });

  testWidgets('rail activates only on its stroke and accepts keyboard input', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 48,
              height: 80,
              child: DThreadRail(
                semanticLabel: 'Collapse replies',
                onPressed: () => activations++,
              ),
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(DThreadRail));
    await tester.tapAt(center + const Offset(20, 0));
    expect(activations, 0);
    await tester.tapAt(center);
    expect(activations, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 3);
  });

  testWidgets('decorative rail has no button semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 32, height: 60, child: DThreadRail()),
      ),
    );
    expect(find.bySemanticsLabel('Collapse replies'), findsNothing);
    semantics.dispose();
  });

  testWidgets('unbounded and zero height branches lay out safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            DThreadConnector(width: 32, junction: 16),
            DThreadRail(),
            SizedBox(height: 0, child: DThreadRail()),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
