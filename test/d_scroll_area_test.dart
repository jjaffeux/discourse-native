import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 200, height: 180, child: child)),
    ),
  );
  testWidgets(
    'touch and keyboard scroll the borrowed position and retain it on rebuild',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget area() => DScrollArea(
        controller: controller,
        child: const SizedBox(height: 1000, child: Text('Content')),
      );
      await tester.pumpWidget(host(area()));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      final offset = controller.offset;
      await tester.pumpWidget(host(area()));
      expect(controller.offset, offset);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(controller.offset, controller.position.maxScrollExtent);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      await tester.pumpWidget(const SizedBox());
      expect(controller.hasClients, isFalse);
      controller.addListener(() {});
    },
  );
  testWidgets(
    'combined overflow keeps one position per axis and responds to resize',
    (tester) async {
      final vertical = ScrollController();
      final horizontal = ScrollController();
      addTearDown(vertical.dispose);
      addTearDown(horizontal.dispose);
      Widget area(double size) => DScrollArea(
        axes: DScrollAxes.both,
        controller: vertical,
        horizontalController: horizontal,
        child: SizedBox(width: size, height: size),
      );
      await tester.pumpWidget(host(area(1000)));
      expect(vertical.positions.length, 1);
      expect(horizontal.positions.length, 1);
      expect(horizontal.position.maxScrollExtent, 800);
      vertical.jumpTo(400);
      horizontal.jumpTo(400);
      await tester.pumpWidget(host(area(100)));
      await tester.pumpAndSettle();
      expect(vertical.offset, 0);
      expect(horizontal.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('mouse thumb dragging and wheel events reach the intended axis', (
    tester,
  ) async {
    final vertical = ScrollController();
    final horizontal = ScrollController();
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(
      host(
        DScrollArea(
          axes: DScrollAxes.both,
          controller: vertical,
          horizontalController: horizontal,
          child: const SizedBox(width: 1000, height: 1000),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(DScrollArea));
    await tester.dragFrom(
      Offset(rect.right - 4, rect.top + 10),
      const Offset(0, 60),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(vertical.offset, greaterThan(0));
    expect(horizontal.offset, 0);
    await tester.dragFrom(
      Offset(rect.left + 10, rect.bottom - 4),
      const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(horizontal.offset, greaterThan(0));
    final before = vertical.offset;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: rect.center,
        scrollDelta: const Offset(0, 30),
      ),
    );
    await tester.pumpAndSettle();
    expect(vertical.offset, greaterThan(before));
  });
  testWidgets(
    'controller replacement detaches borrowed resources and RTL starts at the right edge',
    (tester) async {
      final first = ScrollController();
      final second = ScrollController(initialScrollOffset: 40);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget area(ScrollController controller) => Directionality(
        textDirection: TextDirection.rtl,
        child: DScrollArea(
          axes: DScrollAxes.horizontal,
          controller: controller,
          child: const SizedBox(
            width: 1000,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Start'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(area(first)));
      expect(
        tester.getRect(find.text('Start')).right,
        tester.getRect(find.byType(DScrollArea)).right,
      );
      first.jumpTo(60);
      await tester.pumpWidget(host(area(second)));
      expect(first.hasClients, isFalse);
      expect(second.offset, 60);
      await tester.pumpWidget(host(const DScrollArea(child: Text('Owned'))));
      expect(second.hasClients, isFalse);
      first.addListener(() {});
      second.addListener(() {});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'nonoverflow skips only the root and overflow transitions preserve child editing and traversal',
    (tester) async {
      final before = FocusNode();
      final editor = FocusNode();
      final button = FocusNode();
      final after = FocusNode();
      final text = TextEditingController(text: 'Retained');
      final scroll = ScrollController();
      for (final node in [before, editor, button, after]) {
        addTearDown(node.dispose);
      }
      addTearDown(text.dispose);
      addTearDown(scroll.dispose);
      var presses = 0;
      Widget scene(double contentHeight, {double viewportHeight = 180}) =>
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  DButton(
                    focusNode: before,
                    label: const Text('Before'),
                    onPressed: () {},
                  ),
                  SizedBox(
                    width: 240,
                    height: viewportHeight,
                    child: DScrollArea(
                      controller: scroll,
                      child: SizedBox(
                        height: contentHeight,
                        child: Column(
                          children: [
                            TextField(focusNode: editor, controller: text),
                            DButton(
                              focusNode: button,
                              label: const Text('Child'),
                              onPressed: () => presses++,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  DButton(
                    focusNode: after,
                    label: const Text('After'),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          );
      await tester.pumpWidget(scene(120));
      await tester.pumpAndSettle();
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'Kept through resize');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(text.selection.baseOffset, text.text.length - 1);
      expect(scroll.offset, 0);
      final selection = text.selection;
      await tester.pumpWidget(scene(700));
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      expect(text.text, 'Kept through resize');
      expect(text.selection, selection);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(button.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(presses, 1);
      final childOffset = scroll.offset;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(presses, 2);
      expect(scroll.offset, childOffset);
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      final rootFocus = FocusManager.instance.primaryFocus;
      await tester.pumpWidget(scene(120));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(rootFocus));
      expect(scroll.offset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(scene(120, viewportHeight: 80));
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(scroll.offset, 40);
      await tester.pumpWidget(scene(120));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'Space pages down, Shift Space pages up and modified keys bubble',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final bubbled = <LogicalKeyboardKey>[];
      await tester.pumpWidget(
        host(
          Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  [
                    LogicalKeyboardKey.space,
                    LogicalKeyboardKey.arrowDown,
                  ].contains(event.logicalKey)) {
                bubbled.add(event.logicalKey);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: DScrollArea(
              controller: controller,
              child: const SizedBox(height: 1000),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.offset, 162);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(bubbled, isEmpty);
      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.shiftLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        if (modifier != LogicalKeyboardKey.shiftLeft) {
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
        }
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(
        bubbled.where((key) => key == LogicalKeyboardKey.arrowDown).length,
        4,
      );
      expect(bubbled.where((key) => key == LogicalKeyboardKey.space).length, 3);
    },
  );
  testWidgets(
    'focus ring paints only outside transparent content and multiplies token alpha',
    (tester) async {
      const background = Color(0xff204060);
      final key = GlobalKey();
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
        ).copyWith(primary: const Color(0x80ff0000)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(
                color: background,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: DScrollArea(
                      borderRadius: BorderRadius.zero,
                      child: SizedBox(height: 500),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<List<int>> pixel(int x, int y) async =>
          (await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final offset = (y * image.width + x) * 4;
            final result = bytes!.buffer.asUint8List().sublist(
              offset,
              offset + 4,
            );
            image.dispose();
            return result;
          }))!;
      expect(await pixel(50, 50), [32, 64, 96, 255]);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(await pixel(50, 50), [32, 64, 96, 255]);
      final ring = await pixel(8, 50);
      // Existing 50% alpha multiplied by ring 50% gives a 25% red blend.
      expect(ring[0], closeTo(88, 1));
      expect(ring[1], closeTo(48, 1));
      expect(ring[2], closeTo(72, 1));
      expect(await pixel(6, 50), [32, 64, 96, 255]);
    },
  );
}
