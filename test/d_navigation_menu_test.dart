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

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);
