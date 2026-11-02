import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('last visible line number keeps its contrast', (tester) async {
    final controller = DCodeEditingController(
      text: List.filled(30, 'dzadada').join('\n'),
    );
    addTearDown(controller.dispose);
    final key = GlobalKey();
    var height = 400.0;
    Widget host() => MaterialApp(
      theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 390,
            height: height,
            child: RepaintBoundary(
              key: key,
              child: DCodeEditor(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final rowHeight = tester.getSize(find.text('1')).height;
    height = 32 + rowHeight * 15 + 2;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final first = tester.getRect(find.text('1'));
    final last = tester.getRect(find.text('15'));
    expect(last.bottom, lessThan(height));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int brightestRed(Rect rect) {
        var brightest = 0;
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
          for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
            final red = bytes.getUint8((y * image.width + x) * 4);
            if (red > brightest) brightest = red;
          }
        }
        return brightest;
      }

      expect(
        brightestRed(last),
        closeTo(brightestRed(first), 2),
        reason: 'A fully visible line number must retain its normal ink color',
      );
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('line numbers stay aligned across digit changes at $scale', (
      tester,
    ) async {
      final controller = DCodeEditingController(
        text: List.filled(9, 'x').join('\n'),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SizedBox(
                width: 390,
                height: 320,
                child: DCodeEditor(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oneDigitWidth = tester.getSize(find.text('1')).width;
      var previousDigits = 1;
      var previousWidth = oneDigitWidth;
      for (final count in [10, 9, 99, 100, 1000, 9]) {
        controller.text = List.filled(count, 'x').join('\n');
        await tester.pumpAndSettle();
        final first = tester.getRect(find.text('1'));
        final last = tester.getRect(find.text('$count'));
        expect(
          last.height,
          closeTo(first.height, .01),
          reason: 'Line $count must fit on one row',
        );
        expect(last.right, closeTo(first.right, .01));
        final digits = count.toString().length;
        if (digits > previousDigits) {
          expect(first.width, greaterThan(previousWidth));
        } else if (digits < previousDigits) {
          expect(first.width, lessThan(previousWidth));
        }
        if (digits == 1) expect(first.width, closeTo(oneDigitWidth, .01));
        previousDigits = digits;
        previousWidth = first.width;
        expect(last.top - first.top, closeTo((count - 1) * first.height, .01));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('vertical scrollbar stays on the block edge with long lines', (
    tester,
  ) async {
    final controller = DCodeEditingController(
      text: List.generate(40, (i) => '$i ${'x' * 120}').join('\n'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              height: 320,
              child: DCodeEditor(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.descendant(
      of: find.byType(DCodeEditor),
      matching: find.byWidgetPredicate(
        (w) => w is DScrollBar && w.axis == Axis.vertical,
      ),
    );
    expect(bar, findsOneWidget);
    final bounds = tester.getRect(find.byType(DCodeEditor));
    expect(tester.getRect(bar).right, bounds.right);
    final scroll = tester.widget<DScrollBar>(bar).controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(horizontal),
        scrollDelta: const Offset(100, 0),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SingleChildScrollView>(horizontal).controller!.offset,
      greaterThan(0),
    );
    final before = scroll.offset;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final thumb = Offset(bounds.right - 4, bounds.top + 35);
    await mouse.addPointer(location: thumb);
    await mouse.down(thumb);
    await mouse.moveBy(const Offset(0, 120));
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(before));
    expect(tester.getRect(bar).right, bounds.right);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'edits, indents, highlights and keeps borrowed controller alive',
    (tester) async {
      final controller = DCodeEditingController(
        text: 'flowchart TD\n  A --> B',
        language: 'mermaid',
      );
      addTearDown(controller.dispose);
      var changed = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 250,
              child: DCodeEditor(
                controller: controller,
                onChanged: (value) => changed = value,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'flowchart LR\n  A --> C');
      expect(changed, 'flowchart LR\n  A --> C');
      final field = tester.widget<EditableText>(find.byType(EditableText));
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: field.style,
        withComposing: true,
      );
      expect(span.toPlainText(), controller.text);
      expect(span.children, isNotEmpty);
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.text, endsWith('  '));
      expect(changed, controller.text);
      await tester.pumpWidget(const SizedBox());
      controller.text = 'still usable';
      expect(controller.text, 'still usable');
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'read-only prevents typing and indentation, including a state change',
    (tester) async {
      final controller = DCodeEditingController(
        text: 'A --> B',
        language: 'mermaid',
      );
      addTearDown(controller.dispose);
      Widget host(bool readOnly) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: DCodeEditor(controller: controller, readOnly: readOnly),
          ),
        ),
      );
      await tester.pumpWidget(host(false));
      await tester.tap(find.byType(TextField));
      await tester.pumpWidget(host(true));
      final before = controller.text;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(controller.text, before);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).readOnly,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
