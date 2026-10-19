import 'dart:ui' show SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inline badges change only their fill while hovered', (
    tester,
  ) async {
    const projectedKey = ValueKey('projected-badge');
    const linkedKey = ValueKey('linked-badge');
    const inertKey = ValueKey('inert-badge');
    await _pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _badge('Poll', key: projectedKey, hoverable: true, highlighted: true),
          const SizedBox(width: 24),
          _badge('@someone', key: linkedKey, onPressed: () {}),
          const SizedBox(width: 24),
          _badge('Assigned', key: inertKey),
        ],
      ),
    );

    final theme = Theme.of(tester.element(find.byKey(projectedKey)));
    final hover = Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(alpha: .08),
      theme.shell.mention,
    );
    final projectedRect = tester.getRect(find.byKey(projectedKey));
    final linkedRect = tester.getRect(find.byKey(linkedKey));
    final foreground = _container(tester, projectedKey).foregroundDecoration;
    expect(_fill(tester, projectedKey), theme.shell.mention);
    expect(_fill(tester, linkedKey), theme.shell.mention);
    expect(_fill(tester, inertKey), theme.shell.mention);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(projectedKey)));
    await tester.pump();

    expect(_fill(tester, projectedKey), hover);
    expect(tester.getRect(find.byKey(projectedKey)), projectedRect);
    expect(_container(tester, projectedKey).foregroundDecoration, foreground);
    final border = (foreground! as BoxDecoration).border! as Border;
    expect(border.top.color, theme.colorScheme.primary);
    expect(border.top.width, 1.5);
    expect(border.top.strokeAlign, BorderSide.strokeAlignInside);

    await mouse.moveTo(tester.getCenter(find.byKey(linkedKey)));
    await tester.pump();
    expect(_fill(tester, projectedKey), theme.shell.mention);
    expect(_fill(tester, linkedKey), hover);
    expect(tester.getRect(find.byKey(linkedKey)), linkedRect);

    await mouse.moveTo(tester.getCenter(find.byKey(inertKey)));
    await tester.pump();
    expect(_fill(tester, linkedKey), theme.shell.mention);
    expect(_fill(tester, inertKey), theme.shell.mention);
  });

  testWidgets('touch does not apply mouse hover to a static inline badge', (
    tester,
  ) async {
    const key = ValueKey('touch-badge');
    await _pump(tester, _badge('Poll', key: key, hoverable: true));
    final theme = Theme.of(tester.element(find.byKey(key)));
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(_fill(tester, key), theme.shell.mention);
    await touch.up();
    await tester.pump();
    expect(_fill(tester, key), theme.shell.mention);
  });

  testWidgets('only actionable inline badges are named keyboard buttons', (
    tester,
  ) async {
    const actionableKey = ValueKey('actionable-badge');
    const hoverOnlyKey = ValueKey('hover-only-badge');
    const inertKey = ValueKey('inert-badge');
    var activations = 0;
    await _pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _badge(
            '@someone',
            key: actionableKey,
            onPressed: () => activations++,
          ),
          const SizedBox(width: 24),
          _badge('Poll', key: hoverOnlyKey, hoverable: true),
          const SizedBox(width: 24),
          _badge('Assigned', key: inertKey),
        ],
      ),
    );
    final semantics = tester.ensureSemantics();
    await tester.pump();
    try {
      final actionable = tester.getSemantics(find.text('@someone'));
      expect(actionable.label, '@someone');
      expect(actionable.flagsCollection.isButton, isTrue);
      expect(
        actionable.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(actionable.flagsCollection.isFocused, Tristate.isFalse);
      expect(
        tester.semantics.simulatedAccessibilityTraversal().where(
          (node) => node.flagsCollection.isFocused != Tristate.none,
        ),
        [actionable],
      );
      for (final label in ['Poll', 'Assigned']) {
        final node = tester.getSemantics(find.text(label));
        expect(node.flagsCollection.isButton, isFalse);
        expect(node.flagsCollection.isFocused != Tristate.none, isFalse);
      }
      final theme = Theme.of(tester.element(find.byKey(actionableKey)));
      final focusFill = Color.alphaBlend(
        theme.colorScheme.onSurface.withValues(alpha: .08),
        theme.shell.mention,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('@someone')).flagsCollection.isFocused,
        Tristate.isTrue,
      );
      expect(_fill(tester, actionableKey), focusFill);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(activations, 2);
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('@someone')).flagsCollection.isFocused,
        Tristate.isFalse,
      );
      tester.semantics.performAction(
        find.semantics.byLabel('@someone'),
        SemanticsAction.focus,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('@someone')).flagsCollection.isFocused,
        Tristate.isTrue,
      );
    } finally {
      semantics.dispose();
    }
  });
}

Widget _badge(
  String label, {
  required Key key,
  bool hoverable = false,
  bool highlighted = false,
  VoidCallback? onPressed,
}) => Builder(
  builder: (context) => DBadge.inline(
    key: key,
    baseStyle: const TextStyle(fontSize: 16),
    backgroundColor: Theme.of(context).shell.mention,
    hoverable: hoverable,
    highlighted: highlighted,
    onPressed: onPressed,
    child: Text(label),
  ),
);

AnimatedContainer _container(WidgetTester tester, Key key) =>
    tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(AnimatedContainer),
      ),
    );

Color? _fill(WidgetTester tester, Key key) =>
    (_container(tester, key).decoration! as BoxDecoration).color;

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: Center(child: child)),
  ),
);
