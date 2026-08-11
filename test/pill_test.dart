import 'package:discourse_native/src/shell/pill.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BoxDecoration decoration(WidgetTester tester, Key key) =>
      tester
              .widget<Container>(
                find.descendant(
                  of: find.byKey(key),
                  matching: find.byType(Container),
                ),
              )
              .decoration!
          as BoxDecoration;

  testWidgets('actionable pills change only their fill while hovered', (
    tester,
  ) async {
    const projectedKey = ValueKey('projected-pill');
    const linkedKey = ValueKey('linked-pill');
    const inertKey = ValueKey('inert-pill');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Pill(
                  key: projectedKey,
                  label: 'Poll',
                  baseStyle: TextStyle(fontSize: 16),
                  hoverable: true,
                  highlighted: true,
                ),
                SizedBox(width: 24),
                Pill(
                  key: linkedKey,
                  label: '@someone',
                  baseStyle: TextStyle(fontSize: 16),
                  onTap: _noop,
                ),
                SizedBox(width: 24),
                Pill(
                  key: inertKey,
                  label: 'Assigned',
                  baseStyle: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final theme = Theme.of(tester.element(find.byKey(projectedKey)));
    final hover = Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(alpha: 0.08),
      theme.shell.mention,
    );
    final projectedRect = tester.getRect(find.byKey(projectedKey));
    final linkedRect = tester.getRect(find.byKey(linkedKey));
    final selectedForeground = tester
        .widget<Container>(
          find.descendant(
            of: find.byKey(projectedKey),
            matching: find.byType(Container),
          ),
        )
        .foregroundDecoration;
    expect(decoration(tester, projectedKey).color, theme.shell.mention);
    expect(decoration(tester, linkedKey).color, theme.shell.mention);
    expect(decoration(tester, inertKey).color, theme.shell.mention);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(projectedKey)));
    await tester.pump();

    expect(decoration(tester, projectedKey).color, hover);
    expect(tester.getRect(find.byKey(projectedKey)), projectedRect);
    expect(
      tester
          .widget<Container>(
            find.descendant(
              of: find.byKey(projectedKey),
              matching: find.byType(Container),
            ),
          )
          .foregroundDecoration,
      selectedForeground,
    );
    final border = selectedForeground! as BoxDecoration;
    final side = (border.border! as Border).top;
    expect(side.color, theme.colorScheme.primary);
    expect(side.width, 1.5);
    expect(side.strokeAlign, BorderSide.strokeAlignInside);

    await mouse.moveTo(tester.getCenter(find.byKey(linkedKey)));
    await tester.pump();
    expect(decoration(tester, projectedKey).color, theme.shell.mention);
    expect(decoration(tester, linkedKey).color, hover);
    expect(tester.getRect(find.byKey(linkedKey)), linkedRect);

    await mouse.moveTo(tester.getCenter(find.byKey(inertKey)));
    await tester.pump();
    expect(decoration(tester, linkedKey).color, theme.shell.mention);
    expect(decoration(tester, inertKey).color, theme.shell.mention);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(decoration(tester, linkedKey).color, theme.shell.mention);
  });

  testWidgets('touch does not apply the mouse hover fill', (tester) async {
    const key = ValueKey('touch-pill');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: Pill(
              key: key,
              label: 'Poll',
              baseStyle: TextStyle(fontSize: 16),
              hoverable: true,
            ),
          ),
        ),
      ),
    );

    final theme = Theme.of(tester.element(find.byKey(key)));
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(decoration(tester, key).color, theme.shell.mention);
    await touch.up();
    await tester.pump();
    expect(decoration(tester, key).color, theme.shell.mention);
  });
}

void _noop() {}
