import 'dart:ui' show SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('live orientation updates an unchanged menu child', (
    tester,
  ) async {
    final axis = ValueNotifier(Axis.horizontal);
    addTearDown(axis.dispose);
    final menu = _menu(onRoute: (_) {}) as DNavigationMenu<String>;
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<Axis>(
          valueListenable: axis,
          builder: (context, orientation, child) => DNavigationMenu<String>(
            orientation: orientation,
            child: menu.child,
          ),
        ),
      ),
    );
    axis.value = Axis.vertical;
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Components')).dy,
      greaterThan(tester.getCenter(find.text('Getting started')).dy + 30),
    );
  });

  testWidgets('vertical list roves with Down and enters content with Right', (
    tester,
  ) async {
    final horizontal = _menu(onRoute: (_) {}) as DNavigationMenu<String>;
    await tester.pumpWidget(
      _app(
        DNavigationMenu<String>(
          orientation: Axis.vertical,
          child: horizontal.child,
        ),
      ),
    );
    _menuFocus(tester, 'getting').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_menuFocus(tester, 'components').hasFocus, isTrue);
    expect(find.text('Alert Dialog'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Alert Dialog'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Navigation menu link',
    );
  });

  testWidgets('trigger state follows opening, switching and closing', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_menu(onRoute: (_) {})));
    void expectTurns(List<double> turns) {
      expect(
        tester
            .widgetList<AnimatedRotation>(find.byType(AnimatedRotation))
            .map((widget) => widget.turns),
        turns,
      );
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((widget) => widget.properties.expanded != null)
            .map((widget) => widget.properties.expanded),
        turns.map((turn) => turn != 0),
      );
    }

    expectTurns([0, 0]);
    await tester.tap(find.text('Getting started'));
    await tester.pumpAndSettle();
    expectTurns([.5, 0]);
    final indicator = find.byKey(const ValueKey('d-navigation-menu-indicator'));
    expect(
      tester.getSize(
        find.descendant(of: indicator.first, matching: find.byType(Container)),
      ),
      const Size(8, 8),
    );
    await tester.tap(find.text('Components'));
    await tester.pumpAndSettle();
    expectTurns([0, .5]);
    await tester.tap(find.text('Components'));
    await tester.pumpAndSettle();
    expectTurns([0, 0]);
    expect(find.text('Alert Dialog'), findsNothing);
  });

  testWidgets('trigger opens shared viewport and routed link closes it', (
    tester,
  ) async {
    String? route;
    await tester.pumpWidget(
      _app(_menu(onRoute: (value) => route = value, closeOnActivate: true)),
    );

    await tester.tap(find.text('Getting started'));
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);
    expect(find.byType(DPopoverContent), findsOneWidget);

    await tester.tap(find.text('Introduction'));
    await tester.pumpAndSettle();
    expect(route, 'intro');
    expect(find.text('Introduction'), findsNothing);
  });

  testWidgets('hover travels between triggers using one viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_menu(onRoute: (_) {})));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: const Offset(1, 1));
    await pointer.moveTo(tester.getCenter(find.text('Getting started')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);

    await pointer.moveTo(tester.getCenter(find.text('Components')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('Alert Dialog'), findsOneWidget);
    expect(find.text('Introduction'), findsNothing);
    expect(find.byType(DPopoverContent), findsOneWidget);
  });

  testWidgets('only new content animates while viewport and indicator travel', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_transitionMenu()));

    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DPopoverContent)).width, 240);
    final firstIndicator = tester.getCenter(
      find.byKey(const ValueKey('d-navigation-menu-indicator')),
    );

    await tester.tap(find.text('Second'));
    await tester.pump();

    final incomingAtStart = _slideOffset(tester, 'second');
    expect(find.text('First panel'), findsNothing);
    expect(incomingAtStart.dx, closeTo(.5, .001));
    expect(tester.getSize(find.byType(DPopoverContent)).width, 240);

    await tester.pump(const Duration(milliseconds: 175));
    final incomingMidway = _slideOffset(tester, 'second');
    expect(find.text('First panel'), findsNothing);
    expect(incomingMidway.dx, greaterThan(0));
    expect(incomingMidway.dx, lessThan(incomingAtStart.dx));
    expect(
      tester.getSize(find.byType(DPopoverContent)).width,
      allOf(greaterThan(240), lessThan(400)),
    );
    final movingIndicator = tester.getCenter(
      find.byKey(const ValueKey('d-navigation-menu-indicator')),
    );
    expect(movingIndicator.dx, greaterThan(firstIndicator.dx));

    await tester.pumpAndSettle();
    expect(find.text('First panel'), findsNothing);
    expect(find.text('Second panel'), findsOneWidget);
    expect(tester.getSize(find.byType(DPopoverContent)).width, 400);
    final secondIndicator = tester.getCenter(
      find.byKey(const ValueKey('d-navigation-menu-indicator')),
    );
    expect(movingIndicator.dx, lessThan(secondIndicator.dx));
  });

  testWidgets('stretch content replaces the previous panel immediately', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_stretchTransitionMenu()));

    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second'));
    await tester.pump();

    expect(find.text('First row'), findsNothing);
    expect(find.text('Second row'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('First row'), findsNothing);
    expect(find.text('Second row'), findsOneWidget);
  });

  testWidgets('reduced-motion RTL swaps stretch panels immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MediaQuery(
          data: MediaQueryData(size: Size(800, 600), disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: DNavigationMenu<String>(child: _stretchTransitionList),
          ),
        ),
      ),
    );

    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();

    expect(find.text('First row'), findsNothing);
    expect(find.text('Second row'), findsOneWidget);
    expect(tester.getSize(find.byType(DPopoverContent)).width, 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new panel travel mirrors for reverse and RTL switches', (
    tester,
  ) async {
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      await tester.pumpWidget(
        _app(
          Directionality(
            key: ValueKey(direction),
            textDirection: direction,
            child: _transitionMenu(),
          ),
        ),
      );
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First'));
      await tester.pump();

      final incoming = _slideOffset(tester, 'first').dx;
      final expectedSign = direction == TextDirection.ltr ? -1 : 1;
      expect(incoming.sign, expectedSign);
      expect(find.text('Second panel'), findsNothing);

      await tester.pump(const Duration(milliseconds: 175));
      final incomingMidway = _slideOffset(tester, 'first').dx;
      expect(incomingMidway.sign, expectedSign);
      expect(incomingMidway.abs(), lessThan(incoming.abs()));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('controlled switches retain direction after repeated updates', (
    tester,
  ) async {
    final value = ValueNotifier<String?>('first');
    addTearDown(value.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<String?>(
          valueListenable: value,
          builder: (context, selected, child) =>
              DNavigationMenu<String>.controlled(
                value: selected,
                child: _stretchTransitionList,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    value.value = 'second';
    await tester.pumpAndSettle();
    value.value = 'first';
    await tester.pump();

    expect(_slideOffset(tester, 'first').dx, closeTo(-.5, .001));
    expect(find.text('Second row'), findsNothing);
    await tester.pump(const Duration(milliseconds: 175));
    expect(_slideOffset(tester, 'first').dx, greaterThan(-.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('logical arrows rove triggers in LTR and RTL', (tester) async {
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      await tester.pumpWidget(
        _app(
          Directionality(
            textDirection: direction,
            child: _menu(onRoute: (_) {}),
          ),
        ),
      );
      _menuFocus(tester, 'getting').requestFocus();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('getting'),
      );
      await tester.sendKeyEvent(
        direction == TextDirection.ltr
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft,
      );
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        contains('components'),
      );
    }
  });

  testWidgets(
    'roving focus reveals offscreen items at 200 percent in LTR and RTL',
    (tester) async {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        await tester.pumpWidget(
          _app(
            MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 600),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Directionality(
                key: ValueKey(direction),
                textDirection: direction,
                child: SizedBox(
                  key: const ValueKey('menu-viewport'),
                  width: 240,
                  child: _menu(onRoute: (_) {}),
                ),
              ),
            ),
          ),
        );
        _menuFocus(tester, 'getting').requestFocus();
        await tester.pumpAndSettle();
        final viewport = tester.getRect(
          find.byKey(const ValueKey('menu-viewport')),
        );
        expect(
          viewport.contains(tester.getCenter(find.text('Documentation'))),
          isFalse,
        );

        for (final (key, value, label) in [
          (
            direction == TextDirection.ltr
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft,
            'components',
            'Components',
          ),
          (LogicalKeyboardKey.end, 'docs', 'Documentation'),
          (LogicalKeyboardKey.home, 'getting', 'Getting started'),
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          expect(_menuFocus(tester, value).hasFocus, isTrue);
          expect(
            viewport.contains(tester.getCenter(find.text(label))),
            isTrue,
            reason: '$label must be visible after keyboard traversal',
          );
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Tab enters the roving list once and then exits', (tester) async {
    final before = FocusNode(debugLabel: 'before menu');
    final after = FocusNode(debugLabel: 'after menu');
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            TextButton(
              focusNode: before,
              onPressed: () {},
              child: const Text('Before'),
            ),
            _menu(onRoute: (_) {}),
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('After'),
            ),
          ],
        ),
      ),
    );
    before.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('getting'));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, after);
  });

  testWidgets('Down enters content and Escape restores trigger focus', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_menu(onRoute: (_) {})));
    _menuFocus(tester, 'getting').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('link'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('getting'));
  });

  testWidgets('leaving the keyboard menu closes without stealing focus', (
    tester,
  ) async {
    final after = FocusNode(debugLabel: 'after open menu');
    addTearDown(after.dispose);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            _menu(onRoute: (_) {}),
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('After'),
            ),
          ],
        ),
      ),
    );
    _menuFocus(tester, 'getting').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);

    after.requestFocus();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsNothing);
    expect(FocusManager.instance.primaryFocus, after);
  });

  testWidgets('controlled null remains closed until owner accepts request', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _ControlledHarness(accept: false)));
    await tester.tap(find.text('Getting started'));
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsNothing);

    await tester.pumpWidget(_app(const _ControlledHarness(accept: true)));
    await tester.tap(find.text('Getting started'));
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);
  });

  testWidgets('controlled owner can reject Escape dismissal', (tester) async {
    await tester.pumpWidget(_app(const _ControlledCloseHarness()));
    await tester.pumpAndSettle();
    _menuFocus(tester, 'getting').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('Navigation menu content'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('Navigation menu content'),
    );
  });

  testWidgets('borrowed controller opens and ignores calls after detach', (
    tester,
  ) async {
    final controller = DNavigationMenuController<String>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        DNavigationMenu<String>(
          controller: controller,
          child: const DNavigationMenuList<String>(
            children: [
              DNavigationMenuItem<String>(
                value: 'getting',
                trigger: DNavigationMenuTrigger(child: Text('Getting started')),
                content: DNavigationMenuContent(child: Text('Introduction')),
              ),
            ],
          ),
        ),
      ),
    );
    controller.open('getting');
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);
    expect(controller.value, 'getting');

    await tester.pumpWidget(_app(const SizedBox()));
    controller.close();
    expect(controller.value, isNull);
  });

  testWidgets('disposing a borrowed controller while mounted is harmless', (
    tester,
  ) async {
    final controller = DNavigationMenuController<String>();
    await tester.pumpWidget(_app(_menuWithController(controller: controller)));
    controller.dispose();

    await tester.tap(find.text('Getting started'));
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controlled owner is notified when its open item is removed', (
    tester,
  ) async {
    final changes = <DNavigationMenuChange<String>>[];
    final harnessKey = GlobalKey<_DynamicControlledHarnessState>();
    await tester.pumpWidget(
      _app(
        _DynamicControlledHarness(
          key: harnessKey,
          onSelectionChanged: changes.add,
        ),
      ),
    );
    await tester.tap(find.text('Getting started'));
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsOneWidget);

    harnessKey.currentState!.removeItem();
    await tester.pumpAndSettle();
    expect(find.text('Introduction'), findsNothing);
    expect(changes.last.value, isNull);
    expect(changes.last.reason, DNavigationMenuChangeReason.dynamic);
  });

  testWidgets('direct active destination exposes link and current semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_menu(onRoute: (_) {})));
    final data = tester
        .getSemantics(
          find.byWidgetPredicate(
            (widget) => widget is DNavigationMenuLink && widget.active,
          ),
        )
        .getSemanticsData();
    expect(data.flagsCollection.isLink, isTrue);
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets(
    'disabled dynamic entry is skipped and narrow RTL does not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(216, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          const MediaQuery(
            data: MediaQueryData(
              size: Size(216, 640),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: 216,
                child: DNavigationMenu<String>(
                  child: DNavigationMenuList<String>(
                    children: [
                      DNavigationMenuItem<String>(
                        value: 'disabled',
                        disabled: true,
                        trigger: DNavigationMenuTrigger(
                          child: Text('Disabled'),
                        ),
                        content: DNavigationMenuContent(child: Text('Nope')),
                      ),
                      DNavigationMenuItem<String>(
                        value: 'enabled',
                        trigger: DNavigationMenuTrigger(child: Text('Enabled')),
                        content: DNavigationMenuContent(
                          width: 600,
                          child: Text('Narrow content wraps correctly'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Disabled'));
      await tester.pump();
      expect(find.text('Nope'), findsNothing);
      await tester.ensureVisible(find.text('Enabled'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enabled'));
      await tester.pumpAndSettle();
      expect(find.text('Narrow content wraps correctly'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

FocusNode _menuFocus(WidgetTester tester, String label) => tester
    .widgetList<Focus>(find.byType(Focus))
    .map((widget) => widget.focusNode)
    .whereType<FocusNode>()
    .singleWhere((node) => node.debugLabel?.contains(label) ?? false);

Offset _slideOffset(WidgetTester tester, String value) => tester
    .widget<SlideTransition>(
      find.byKey(
        ValueKey<Object?>(('d-navigation-menu-panel', ValueKey<String>(value))),
      ),
    )
    .position
    .value;

Widget _transitionMenu() => const DNavigationMenu<String>(
  child: DNavigationMenuList<String>(
    children: [
      DNavigationMenuItem<String>(
        value: 'first',
        trigger: DNavigationMenuTrigger(child: Text('First')),
        content: DNavigationMenuContent(
          width: 240,
          child: SizedBox(height: 60, child: Text('First panel')),
        ),
      ),
      DNavigationMenuItem<String>(
        value: 'second',
        trigger: DNavigationMenuTrigger(child: Text('Second')),
        content: DNavigationMenuContent(
          width: 400,
          child: SizedBox(height: 140, child: Text('Second panel')),
        ),
      ),
    ],
  ),
);

Widget _stretchTransitionMenu() =>
    const DNavigationMenu<String>(child: _stretchTransitionList);

const _stretchTransitionList = DNavigationMenuList<String>(
  children: [
    DNavigationMenuItem<String>(
      value: 'first',
      trigger: DNavigationMenuTrigger(child: Text('First')),
      content: DNavigationMenuContent(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Text('First row')],
        ),
      ),
    ),
    DNavigationMenuItem<String>(
      value: 'second',
      trigger: DNavigationMenuTrigger(child: Text('Second')),
      content: DNavigationMenuContent(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Text('Second row')],
        ),
      ),
    ),
  ],
);

Widget _menu({
  required ValueChanged<String> onRoute,
  bool closeOnActivate = false,
}) => DNavigationMenu<String>(
  child: DNavigationMenuList<String>(
    children: [
      DNavigationMenuItem<String>(
        value: 'getting',
        trigger: const DNavigationMenuTrigger(child: Text('Getting started')),
        content: DNavigationMenuContent(
          width: 300,
          child: DNavigationMenuLink(
            closeOnActivate: closeOnActivate,
            onPressed: () => onRoute('intro'),
            child: const Text('Introduction'),
          ),
        ),
      ),
      DNavigationMenuItem<String>(
        value: 'components',
        trigger: const DNavigationMenuTrigger(child: Text('Components')),
        content: DNavigationMenuContent(
          width: 300,
          child: DNavigationMenuLink(
            onPressed: () => onRoute('alert'),
            child: const Text('Alert Dialog'),
          ),
        ),
      ),
      DNavigationMenuItem<String>.link(
        value: 'docs',
        link: DNavigationMenuLink(
          triggerStyle: true,
          active: true,
          onPressed: () => onRoute('docs'),
          child: const Text('Documentation'),
        ),
      ),
    ],
  ),
);

Widget _menuWithController({
  required DNavigationMenuController<String> controller,
}) => DNavigationMenu<String>(
  controller: controller,
  child: const DNavigationMenuList<String>(
    children: [
      DNavigationMenuItem<String>(
        value: 'getting',
        trigger: DNavigationMenuTrigger(child: Text('Getting started')),
        content: DNavigationMenuContent(child: Text('Introduction')),
      ),
    ],
  ),
);

class _ControlledHarness extends StatefulWidget {
  const _ControlledHarness({required this.accept});
  final bool accept;

  @override
  State<_ControlledHarness> createState() => _ControlledHarnessState();
}

class _ControlledHarnessState extends State<_ControlledHarness> {
  String? value;

  @override
  Widget build(BuildContext context) => DNavigationMenu<String>.controlled(
    value: value,
    onValueChanged: (next) {
      if (widget.accept) setState(() => value = next);
    },
    child: const DNavigationMenuList<String>(
      children: [
        DNavigationMenuItem<String>(
          value: 'getting',
          trigger: DNavigationMenuTrigger(child: Text('Getting started')),
          content: DNavigationMenuContent(child: Text('Introduction')),
        ),
      ],
    ),
  );
}

class _ControlledCloseHarness extends StatelessWidget {
  const _ControlledCloseHarness();

  @override
  Widget build(BuildContext context) => DNavigationMenu<String>.controlled(
    value: 'getting',
    onValueChanged: (_) {},
    child: const DNavigationMenuList<String>(
      children: [
        DNavigationMenuItem<String>(
          value: 'getting',
          trigger: DNavigationMenuTrigger(child: Text('Getting started')),
          content: DNavigationMenuContent(child: Text('Introduction')),
        ),
      ],
    ),
  );
}

class _DynamicControlledHarness extends StatefulWidget {
  const _DynamicControlledHarness({
    super.key,
    required this.onSelectionChanged,
  });

  final ValueChanged<DNavigationMenuChange<String>> onSelectionChanged;

  @override
  State<_DynamicControlledHarness> createState() =>
      _DynamicControlledHarnessState();
}

class _DynamicControlledHarnessState extends State<_DynamicControlledHarness> {
  String? value;
  bool showItem = true;

  void removeItem() => setState(() => showItem = false);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DNavigationMenu<String>.controlled(
        value: value,
        onValueChanged: (next) => setState(() => value = next),
        onSelectionChanged: widget.onSelectionChanged,
        child: DNavigationMenuList<String>(
          children: [
            if (showItem)
              const DNavigationMenuItem<String>(
                value: 'getting',
                trigger: DNavigationMenuTrigger(child: Text('Getting started')),
                content: DNavigationMenuContent(child: Text('Introduction')),
              ),
          ],
        ),
      ),
      TextButton(
        onPressed: () => setState(() => showItem = false),
        child: const Text('Remove item'),
      ),
    ],
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);
