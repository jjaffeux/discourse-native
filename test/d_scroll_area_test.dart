import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
}
