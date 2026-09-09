import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  DResizableController c, {
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
          controller: c,
          orientation: axis,
          layout: layout,
          onLayoutChange: onChange,
          children:
              children ??
              const [
                DResizablePanel(
                  id: 'a',
                  defaultSize: DResizableSize.pixels(200),
                  minSize: DResizableSize.pixels(100),
                  maxSize: DResizableSize.pixels(400),
                  collapsible: true,
                  child: Text('A'),
                ),
                DResizableHandle(withHandle: true),
                DResizablePanel(
                  id: 'b',
                  defaultSize: DResizableSize.pixels(200),
                  minSize: DResizableSize.pixels(100),
                  maxSize: DResizableSize.pixels(250),
                  child: Text('B'),
                ),
                DResizableHandle(),
                DResizablePanel(
                  id: 'c',
                  defaultSize: DResizableSize.pixels(200),
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
  for (final direction in TextDirection.values) {
    testWidgets(
      'iOS $direction keeps collapsed-edge drag and semantics target inside its group',
      (tester) async {
        final c = DResizableController();
        addTearDown(c.dispose);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              home: Directionality(
                textDirection: direction,
                child: Center(
                  child: SizedBox(
                    width: 301,
                    height: 200,
                    child: DResizablePanelGroup(
                      key: const ValueKey('touch-group'),
                      controller: c,
                      children: const [
                        DResizablePanel(
                          id: 'a',
                          collapsible: true,
                          defaultSize: DResizableSize.pixels(0),
                          minSize: DResizableSize.pixels(100),
                          child: Text('A'),
                        ),
                        DResizableHandle(
                          semanticLabel: 'Touch resize',
                          dividerKey: ValueKey('touch-line'),
                        ),
                        DResizablePanel(id: 'b', child: Text('B')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          final group = tester.getRect(
            find.byKey(const ValueKey('touch-group')),
          );
          final handle = tester.getRect(find.bySemanticsLabel('Touch resize'));
          expect(handle.width, 48);
          expect(handle.left, greaterThanOrEqualTo(group.left));
          expect(handle.right, lessThanOrEqualTo(group.right));
          final line = tester.getRect(find.byKey(const ValueKey('touch-line')));
          expect(line.width, 1);
          expect(
            direction == TextDirection.ltr ? line.left : line.right,
            direction == TextDirection.ltr ? group.left : group.right,
          );
          final point = Offset(
            direction == TextDirection.ltr ? handle.right - 2 : handle.left + 2,
            handle.center.dy,
          );
          final sign = direction == TextDirection.ltr ? 1.0 : -1.0;
          final gesture = await tester.startGesture(point);
          await gesture.moveBy(Offset(20 * sign, 0));
          await tester.pump();
          await gesture.moveBy(Offset(60 * sign, 0));
          await tester.pump();
          expect(c.layout, {'a': 100, 'b': 200});
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 350));
        } finally {
          semantics.dispose();
        }
      },
    );
  }
  testWidgets(
    'divider and pill keep reference geometry and live palette with borrowed focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final c = DResizableController();
      addTearDown(c.dispose);
      final theme = ValueNotifier(ThemeData.light());
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<ThemeData>(
          valueListenable: theme,
          builder: (context, value, _) => MaterialApp(
            theme: value,
            home: SizedBox(
              width: 600,
              height: 300,
              child: DResizablePanelGroup(
                controller: c,
                children: [
                  const DResizablePanel(id: 'a', child: Text('A')),
                  DResizableHandle(
                    withHandle: true,
                    focusNode: focus,
                    dividerKey: const ValueKey('divider'),
                  ),
                  const DResizablePanel(id: 'b', child: Text('B')),
                ],
              ),
            ),
          ),
        ),
      );
      final divider = find.byKey(const ValueKey('divider'));
      expect(tester.getSize(divider).width, 1);
      final pill = find.descendant(
        of: find.byType(DResizableHandle),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).borderRadius != null,
        ),
      );
      expect(tester.getSize(pill), const Size(4, 24));
      theme.value = ThemeData.dark().copyWith(
        extensions: [
          DTokens.fromTheme(
            ThemeData.dark(),
          ).copyWith(border: Colors.purple, radius: 0),
        ],
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Container>(divider).color, Colors.purple);
      expect(
        (tester.widget<Container>(pill).decoration! as BoxDecoration)
            .borderRadius,
        BorderRadius.zero,
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(() => focus.requestFocus(), returnsNormally);
      expect(c.layout, isEmpty);
    },
  );
  testWidgets(
    'pixel-preserving panel survives container resize while relative panel absorbs space',
    (tester) async {
      final c = DResizableController();
      addTearDown(c.dispose);
      const panels = [
        DResizablePanel(
          id: 'fixed',
          defaultSize: DResizableSize.pixels(100),
          preservePixelSize: true,
          child: Text('Fixed'),
        ),
        DResizableHandle(),
        DResizablePanel(id: 'fluid', child: Text('Fluid')),
      ];
      await tester.pumpWidget(host(c, width: 401, children: panels));
      expect(c.layout, {'fixed': 100, 'fluid': 300});
      await tester.pumpWidget(host(c, width: 601, children: panels));
      expect(c.layout, {'fixed': 100, 'fluid': 500});
    },
  );
  for (final capacity in [80.0, 200.0]) {
    testWidgets(
      'pointer midpoint snap conserves extent with $capacity opposite capacity and a disabled neighbour',
      (tester) async {
        final c = DResizableController();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          host(
            c,
            children: [
              const DResizablePanel(
                id: 'a',
                defaultSize: DResizableSize.pixels(100),
                minSize: DResizableSize.pixels(100),
                collapsible: true,
                child: Text('A'),
              ),
              const DResizableHandle(),
              const DResizablePanel(
                id: 'fixed',
                defaultSize: DResizableSize.pixels(100),
                disabled: true,
                child: Text('Fixed'),
              ),
              const DResizableHandle(),
              DResizablePanel(
                id: 'b',
                defaultSize: const DResizableSize.pixels(400),
                minSize: const DResizableSize.pixels(100),
                maxSize: DResizableSize.pixels(400 + capacity),
                child: const Text('B'),
              ),
            ],
          ),
        );
        final handle = find.byType(DResizableHandle).first;
        var gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump();
        expect(c.layout['a'], 100);
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
        expect(
          c.layout,
          capacity < 100
              ? {'a': 100, 'fixed': 100, 'b': 400}
              : {'a': 0, 'fixed': 100, 'b': 500},
        );
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 350));
        if (capacity >= 100) {
          gesture = await tester.startGesture(tester.getCenter(handle));
          await gesture.moveBy(const Offset(20, 0));
          await tester.pump();
          await gesture.moveBy(const Offset(40, 0));
          await tester.pump();
          expect(c.layout['a'], 0);
          await gesture.moveBy(const Offset(20, 0));
          await tester.pump();
          expect(c.layout, {'a': 100, 'fixed': 100, 'b': 400});
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 350));
        }
        expect(c.layout.values.reduce((a, b) => a + b), 600);
      },
    );
  }
  testWidgets(
    'programmatic resizing propagates past adjacent minimum and preserves total',
    (tester) async {
      final c = DResizableController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(c));
      expect(c.layout, {'a': 200, 'b': 200, 'c': 200});
      c.resize('a', const DResizableSize.pixels(400));
      await tester.pump();
      expect(c.layout, {'a': 400, 'b': 100, 'c': 100});
      c.collapse('a');
      await tester.pump();
      expect(c.isCollapsed('a'), isTrue);
      expect(c.layout.values.reduce((a, b) => a + b), 600);
      c.expand('a');
      await tester.pump();
      expect(c.layout, {'a': 400, 'b': 100, 'c': 100});
    },
  );
  testWidgets('disabled panel remains fixed while surrounding panels resize', (
    tester,
  ) async {
    final c = DResizableController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      host(
        c,
        children: const [
          DResizablePanel(id: 'a', child: Text('A')),
          DResizableHandle(),
          DResizablePanel(
            id: 'b',
            defaultSize: DResizableSize.pixels(100),
            disabled: true,
            child: Text('B'),
          ),
          DResizableHandle(),
          DResizablePanel(id: 'c', child: Text('C')),
        ],
      ),
    );
    c.resize('a', const DResizableSize.pixels(400));
    await tester.pump();
    expect(c.layout, {'a': 400, 'b': 100, 'c': 100});
    c.resize('b', const DResizableSize.pixels(200));
    await tester.pump();
    expect(c.layout['b'], 100);
  });
  for (final direction in TextDirection.values) {
    testWidgets(
      '$direction arrows, Home and Enter resize and collapse with focus',
      (tester) async {
        final c = DResizableController();
        addTearDown(c.dispose);
        await tester.pumpWidget(host(c, direction: direction));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(
          direction == TextDirection.ltr
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowLeft,
        );
        await tester.pump();
        expect(c.layout['a'], 210);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(c.isCollapsed('a'), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(c.layout['a'], 210);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        expect(c.isCollapsed('a'), isTrue);
      },
    );
  }
  testWidgets('controlled parent may reject proposed layout', (tester) async {
    final c = DResizableController();
    addTearDown(c.dispose);
    DResizableLayout? proposed;
    await tester.pumpWidget(
      host(
        c,
        layout: const {
          'a': DResizableSize.pixels(200),
          'b': DResizableSize.pixels(200),
          'c': DResizableSize.pixels(200),
        },
        onChange: (v) => proposed = v,
      ),
    );
    c.resize('a', const DResizableSize.pixels(300));
    await tester.pump();
    expect(proposed?['a'], 300);
    expect(c.layout['a'], 200);
  });
  testWidgets('stable IDs retain child state through reorder and removal', (
    tester,
  ) async {
    final c = DResizableController();
    addTearDown(c.dispose);
    List<Widget> panels(List<String> ids) => [
      for (var i = 0; i < ids.length; i++) ...[
        if (i > 0) const DResizableHandle(),
        DResizablePanel(
          id: ids[i],
          child: Material(child: TextField(key: ValueKey('input-${ids[i]}'))),
        ),
      ],
    ];
    await tester.pumpWidget(host(c, children: panels(['a', 'b', 'c'])));
    await tester.enterText(find.byKey(const ValueKey('input-a')), 'retained');
    await tester.pumpWidget(host(c, children: panels(['c', 'a', 'b'])));
    expect(find.text('retained'), findsOneWidget);
    await tester.pumpWidget(host(c, children: panels(['c', 'a'])));
    expect(c.layout.keys, unorderedEquals(['c', 'a']));
    expect(find.text('retained'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(c.layout, isEmpty);
    expect(() => c.collapse('a'), throwsStateError);
  });
  testWidgets('vertical gesture and cancellation commit actual geometry', (
    tester,
  ) async {
    final c = DResizableController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      host(
        c,
        axis: Axis.vertical,
        children: const [
          DResizablePanel(
            id: 'a',
            defaultSize: DResizableSize.percent(25),
            child: Text('A'),
          ),
          DResizableHandle(withHandle: true),
          DResizablePanel(id: 'b', child: Text('B')),
        ],
      ),
    );
    expect(c.layout['a'], 74.75);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DResizableHandle)),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 350));
    expect(c.layout['a'], greaterThan(74.75));
    expect(c.layout.values.reduce((a, b) => a + b), closeTo(299, .001));
    expect(tester.takeException(), isNull);
  });
}
