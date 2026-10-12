import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  _LayoutProbe c, {
  List<Widget>? children,
  TextDirection direction = TextDirection.ltr,
  Axis axis = Axis.horizontal,
  double width = 602,
  Map<String, DResizableSize>? layout,
  ValueChanged<DResizableLayout>? onChange,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: Center(
      child: SizedBox(
        width: width,
        height: 300,
        child: DResizablePanelGroup(
          orientation: axis,
          layout: layout,
          onLayoutChange: (value) {
            c.layout = value;
            onChange?.call(value);
          },
          children:
              children ??
              const [
                DResizablePanel(
                  id: 'a',

                  minSize: DResizableSize.pixels(100),

                  child: Text('A'),
                ),
                DResizableHandle(withHandle: true),
                DResizablePanel(
                  id: 'b',

                  minSize: DResizableSize.pixels(100),

                  child: Text('B'),
                ),
                DResizableHandle(),
                DResizablePanel(
                  id: 'c',

                  minSize: DResizableSize.pixels(100),
                  child: Text('C'),
                ),
              ],
        ),
      ),
    ),
  ),
);

void main() {
  for (final axis in Axis.values) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'workspace gutter resizes along its whole $axis in $direction',
        (tester) async {
          final c = _LayoutProbe();
          addTearDown(c.dispose);
          const gestureKey = ValueKey('gutter-gesture');
          await tester.pumpWidget(
            _host(
              c,
              axis: axis,
              direction: direction,
              children: const [
                DResizablePanel(id: 'a', child: Text('A')),
                DResizableHandle(
                  withHandle: true,
                  dividerThickness: 0,
                  gestureKey: gestureKey,
                ),
                DResizablePanel(id: 'b', child: Text('B')),
              ],
            ),
          );
          final horizontal = axis == Axis.horizontal;
          final gutter = find.byKey(gestureKey);
          expect(
            tester.getSize(gutter),
            horizontal ? const Size(12, 300) : const Size(602, 12),
          );
          final pill = find.descendant(
            of: gutter,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).borderRadius != null,
            ),
          );
          expect(
            tester.getSize(pill),
            horizontal ? const Size(4, 36) : const Size(36, 4),
          );
          final target = tester.renderObject(gutter);
          final rect = tester.getRect(gutter);
          final outside = horizontal
              ? Offset(rect.left - .5, rect.center.dy)
              : Offset(rect.center.dx, rect.top - .5);
          expect(
            tester
                .hitTestOnBinding(outside)
                .path
                .any((e) => e.target == target),
            isFalse,
          );
          for (final corner in [
            const Offset(.05, .05),
            const Offset(.95, .05),
            const Offset(.05, .95),
            const Offset(.95, .95),
          ]) {
            final rect = tester.getRect(gutter);
            final before = c.layout['a']!;
            final total = c.layout.values.reduce((a, b) => a + b);
            final gesture = await tester.startGesture(
              Offset(
                rect.left + rect.width * corner.dx,
                rect.top + rect.height * corner.dy,
              ),
            );
            final delta = horizontal
                ? Offset(direction == TextDirection.ltr ? 20 : -20, 0)
                : const Offset(0, 20);
            await gesture.moveBy(delta);
            await gesture.moveBy(delta);
            await gesture.up();
            await tester.pumpAndSettle();
            expect(c.layout['a'], greaterThan(before));
            expect(
              c.layout.values.reduce((a, b) => a + b),
              closeTo(total, .001),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final disabled in [false]) {
    testWidgets(
      'workspace grip hover and drag colors with disabled=$disabled',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 12,
                height: 200,
                child: DResizableHandle.standalone(
                  withHandle: true,
                  dividerThickness: 0,

                  value: 100,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        final handle = find.byType(DResizableHandle);
        final tokens = DTokens.of(tester.element(handle));
        final pill = find.descendant(
          of: handle,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).borderRadius != null,
          ),
        );
        Color? color() =>
            (tester.widget<Container>(pill).decoration! as BoxDecoration).color;
        expect(color(), tokens.border);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        final rect = tester.getRect(handle);
        await mouse.moveTo(Offset(rect.left + .5, rect.top + 5));
        await tester.pump();
        expect(color(), disabled ? tokens.border : tokens.primary);
        await mouse.down(Offset(rect.left + .5, rect.top + 5));
        await mouse.moveBy(const Offset(20, 0));
        await tester.pump();
        await mouse.moveBy(const Offset(20, 0));
        await tester.pump();
        expect(color(), disabled ? tokens.border : tokens.primary);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(color(), tokens.border);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets('$direction arrows and Home resize with focus', (tester) async {
      final c = _LayoutProbe();
      addTearDown(c.dispose);
      await tester.pumpWidget(_host(c, direction: direction));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(
        direction == TextDirection.ltr
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft,
      );
      await tester.pump();
      expect(c.layout['a'], 210);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(c.layout['a'], 100);
    });
  }
  testWidgets('controlled parent may reject proposed layout', (tester) async {
    final c = _LayoutProbe();
    addTearDown(c.dispose);
    DResizableLayout? proposed;
    await tester.pumpWidget(
      _host(
        c,
        layout: const {
          'a': DResizableSize.pixels(200),
          'b': DResizableSize.pixels(200),
          'c': DResizableSize.pixels(200),
        },
        onChange: (v) => proposed = v,
      ),
    );
    await tester.drag(
      find.byType(DResizableHandle).first,
      const Offset(100, 0),
    );
    await tester.pump();
    expect(proposed?['a'], greaterThan(200));
    expect(tester.getSize(find.byType(DResizablePanel).first).width, 200);
    await tester.pumpAndSettle();
  });
  testWidgets('stable IDs retain child state through reorder and removal', (
    tester,
  ) async {
    final c = _LayoutProbe();
    addTearDown(c.dispose);
    List<Widget> panels(List<String> ids) => [
      for (var i = 0; i < ids.length; i++) ...[
        if (i > 0) const DResizableHandle(),
        DResizablePanel(
          id: ids[i],
          child: Material(child: DInput(key: ValueKey('input-${ids[i]}'))),
        ),
      ],
    ];
    await tester.pumpWidget(_host(c, children: panels(['a', 'b', 'c'])));
    await tester.enterText(find.byKey(const ValueKey('input-a')), 'retained');
    await tester.pumpWidget(_host(c, children: panels(['c', 'a', 'b'])));
    expect(find.text('retained'), findsOneWidget);
    await tester.pumpWidget(_host(c, children: panels(['c', 'a'])));
    expect(c.layout.keys, unorderedEquals(['c', 'a']));
    expect(find.text('retained'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

class _LayoutProbe {
  DResizableLayout layout = {};
  void dispose() {}
}
