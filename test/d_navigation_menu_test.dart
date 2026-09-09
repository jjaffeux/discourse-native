import 'dart:ui' show SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
