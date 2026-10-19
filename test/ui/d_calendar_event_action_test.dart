import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'calendar event preserves visible focus outside its cell and exact activation bounds',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final boundary = GlobalKey();
      var activations = 0;
      final previous = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = previous);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: Colors.white,
                  child: SizedBox(
                    width: 200,
                    height: 80,
                    child: Center(
                      child: DCalendarEventAction(
                        backgroundColor: Colors.red,
                        semanticLabel: 'Open event',
                        focusNode: focus,
                        onPressed: () => activations++,
                        child: const SizedBox(width: 120, height: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final target = find.byType(DCalendarEventAction);
      final bounds = tester.getRect(target);
      final origin = tester.getTopLeft(find.byKey(boundary));
      final point = Offset(
        bounds.left - origin.dx - 3,
        bounds.center.dy - origin.dy,
      );
      Future<int> pixel() async {
        return (await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return bytes!.getUint32(
              (point.dy.toInt() * image.width + point.dx.toInt()) * 4,
            );
          } finally {
            image.dispose();
          }
        }))!;
      }

      final resting = await pixel();
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(await pixel(), isNot(resting));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activations, 1);
      await tester.tapAt(bounds.centerRight + const Offset(1, 0));
      expect(activations, 1);
      await tester.tap(target);
      expect(activations, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
