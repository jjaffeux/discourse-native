import 'dart:ui' show ImageByteFormat;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('document tab keeps reference paint through clicks ($dark)', (
      tester,
    ) async {
      final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
        platform: TargetPlatform.macOS,
        highlightColor: Colors.pink,
        splashColor: Colors.green,
        focusColor: Colors.blue,
      );
      var selected = false;
      var selections = 0;
      var closes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: DFocusHighlight(
            child: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: const ValueKey('paint'),
                  child: Material(
                    color: theme.colorScheme.surface,
                    child: SizedBox(
                      width: 240,
                      child: StatefulBuilder(
                        builder: (context, setState) => DDocumentTab(
                          selected: selected,
                          onSelect: () => setState(() {
                            selected = true;
                            selections++;
                          }),
                          onClose: () => closes++,
                          closeLabel: 'Close Review',
                          child: const Text('Review'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tab = find.byType(DDocumentTab);
      final buttons = find.descendant(of: tab, matching: find.byType(DButton));
      expect(buttons, findsNWidgets(2));
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      final tokens = DTokens.of(tester.element(tab));
      final fill = Color.lerp(tokens.background, tokens.foreground, .10)!;
      final border = Color.lerp(tokens.background, tokens.foreground, .22)!;
      final before = tester.getRect(tab);
      ShapeDecoration decoration() =>
          tester
                  .widget<Container>(
                    find
                        .descendant(of: tab, matching: find.byType(Container))
                        .first,
                  )
                  .decoration!
              as ShapeDecoration;
      expect(decoration().color, Colors.transparent);
      expect(
        (decoration().shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(4),
      );
      expect(
        (decoration().shape as OutlinedBorder).side.color,
        Colors.transparent,
      );
      await pointer.moveTo(tester.getCenter(buttons.first));
      await tester.pump();
      await _expectFill(tester, fill);
      for (var click = 0; click < 2; click++) {
        await pointer.down(tester.getCenter(buttons.first));
        for (final elapsed in [0, 16, 75, 150]) {
          await tester.pump(Duration(milliseconds: elapsed));
          await _expectFill(tester, fill);
        }
        await pointer.up();
        for (final elapsed in [0, 16, 150, 350]) {
          await tester.pump(Duration(milliseconds: elapsed));
          await _expectFill(tester, fill);
        }
        expect(selections, click + 1);
        expect(buttonSurface(tester, of: buttons.first).ringWidth, 0);
      }
      await pointer.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await _expectFill(tester, fill);
      expect(tester.getRect(tab), before);
      expect((decoration().shape as OutlinedBorder).side.color, border);
      expect((decoration().shape as OutlinedBorder).side.width, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        buttonSurface(tester, of: buttons.first).ringWidth,
        greaterThan(0),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selections, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(buttonSurface(tester, of: buttons.last).ringWidth, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(closes, 1);
      expect(selections, 3);
    });
  }
}

Future<void> _expectFill(WidgetTester tester, Color expected) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('paint')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      final offset = (5 * image.width + 140) * 4;
      final actual = [for (var i = 0; i < 3; i++) bytes.getUint8(offset + i)];
      final channels = [expected.r, expected.g, expected.b];
      for (var i = 0; i < 3; i++) {
        expect(actual[i], closeTo(channels[i] * 255, 1));
      }
    } finally {
      image.dispose();
    }
  });
}
