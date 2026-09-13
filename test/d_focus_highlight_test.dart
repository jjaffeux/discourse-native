import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/control_style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      builder: (context, child) => DFocusHighlight(child: child!),
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    );

CustomPaint fieldPaint(WidgetTester tester, Type type) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(type),
        matching: find.byType(CustomPaint),
      ),
    )
    .singleWhere((widget) => widget.child is AnimatedContainer);

double buttonRing(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(DButton),
        matching: find.byType(AnimatedContainer),
      ),
    )
    .map((widget) => widget.decoration)
    .whereType<DControlDecoration>()
    .single
    .ringWidth;

void main() {
  for (final brightness in Brightness.values) {
    for (final textarea in [false, true]) {
      testWidgets(
        '$brightness ${textarea ? 'textarea' : 'input'} uses Tab outlines',
        (tester) async {
          final node = FocusNode();
          addTearDown(node.dispose);
          final type = textarea ? DTextarea : DInput;
          await tester.pumpWidget(
            host(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  textarea
                      ? DTextarea(focusNode: node)
                      : DInput(focusNode: node),
                  DButton(onPressed: () {}, label: const Text('Next')),
                ],
              ),
              brightness: brightness,
            ),
          );
          node.requestFocus();
          await tester.pump();
          expect(fieldPaint(tester, type).foregroundPainter, isNull);
          await tester.tap(find.byType(type), kind: PointerDeviceKind.mouse);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
          await tester.pump();
          expect(node.hasFocus, isTrue);
          expect(fieldPaint(tester, type).foregroundPainter, isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(buttonRing(tester), 3);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();
          expect(node.hasFocus, isTrue);
          expect(fieldPaint(tester, type).foregroundPainter, isNotNull);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );

          await mouse.moveTo(tester.getCenter(find.byType(type)));
          await tester.pump();
          expect(fieldPaint(tester, type).foregroundPainter, isNotNull);
          await tester.tap(find.byType(type), kind: PointerDeviceKind.mouse);
          await tester.pump();
          expect(node.hasFocus, isTrue);
          expect(fieldPaint(tester, type).foregroundPainter, isNull);
          await tester.enterText(find.byType(type), 'Still editable');
          expect(find.text('Still editable'), findsOneWidget);
          await mouse.removePointer();
        },
      );
    }
  }

  testWidgets(
    'pointer buttons hide outlines and restore the global strategy on disposal',
    (tester) async {
      final previous = FocusManager.instance.highlightStrategy;
      final node = FocusNode();
      addTearDown(node.dispose);
      var presses = 0;
      await tester.pumpWidget(
        host(
          DButton(
            focusNode: node,
            onPressed: () => presses++,
            label: const Text('Action'),
          ),
        ),
      );
      await tester.tap(find.text('Action'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(presses, 1);
      expect(buttonRing(tester), 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(buttonRing(tester), 3);
      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();
      expect(presses, 2);
      expect(buttonRing(tester), 0);
      await tester.pumpWidget(const SizedBox());
      expect(FocusManager.instance.highlightStrategy, previous);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(FocusManager.instance.highlightStrategy, previous);
    },
  );

  testWidgets(
    'dialog routes share the policy and pointer focus restoration stays hidden',
    (tester) async {
      final trigger = FocusNode();
      final editor = FocusNode();
      addTearDown(trigger.dispose);
      addTearDown(editor.dispose);
      late BuildContext routeContext;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              routeContext = context;
              return DButton(
                focusNode: trigger,
                label: const Text('Open'),
                onPressed: () {},
              );
            },
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(buttonRing(tester), 3);
      final route = showDialog<void>(
        context: routeContext,
        builder: (context) => Center(
          child: Material(
            child: SizedBox(width: 300, child: DInput(focusNode: editor)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      editor.requestFocus();
      await tester.pumpAndSettle();
      expect(editor.hasFocus, isTrue);
      expect(fieldPaint(tester, DInput).foregroundPainter, isNotNull);
      await tester.tap(find.byType(DInput));
      await tester.pump();
      expect(fieldPaint(tester, DInput).foregroundPainter, isNull);
      Navigator.of(routeContext).pop();
      await tester.pumpAndSettle();
      await route;
      trigger.requestFocus();
      await tester.pumpAndSettle();
      expect(buttonRing(tester), 0);
    },
  );

  testWidgets('validation rings remain visible before keyboard navigation', (
    tester,
  ) async {
    await tester.pumpWidget(host(DInput(invalid: true)));
    expect(fieldPaint(tester, DInput).foregroundPainter, isNotNull);
  });
}
