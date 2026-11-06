import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final link in [false, true]) {
    testWidgets(
      'inline metadata retains activation and semantics (link=$link)',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var activations = 0;
        Future<void> show(bool enabled) => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: DButton(
                label: const Text('Metadata'),
                variant: DButtonVariant.inline,
                density: DButtonDensity.inlineMetadata,
                isLink: link,
                focusNode: focus,
                onPressed: enabled ? () => activations++ : null,
              ),
            ),
          ),
        );
        await show(true);
        final button = find.byType(DButton);
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.flagsCollection.isButton, !link);
        expect(data.flagsCollection.isLink, link);
        expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(data.label, 'Metadata');
        await tester.tap(button, kind: PointerDeviceKind.mouse);
        expect(activations, 1);
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(activations, 3);
        expect(focus.hasFocus, isTrue);
        await show(false);
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(button)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        await tester.tap(button, warnIfMissed: false);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(activations, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('inline metadata animates its keyboard focus ring', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: DButton(
              focusNode: focus,
              density: DButtonDensity.inlineMetadata,
              variant: DButtonVariant.inline,
              label: const Text('Metadata'),
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    DButtonDecoration painted() => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<DButtonDecoration>()
        .single;
    focus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(painted().ringWidth, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(painted().ringWidth, 1);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'inline metadata preserves bounds and type at $platform/$scale',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: DButton(
                      label: const Text('Metadata'),
                      variant: DButtonVariant.inline,
                      density: DButtonDensity.inlineMetadata,
                      onPressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          final button = find.byType(DButton);
          final surface = find.descendant(
            of: button,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is DButtonDecoration,
            ),
          );
          final style = DefaultTextStyle.of(
            tester.element(find.text('Metadata')),
          ).style;
          expect(style.fontSize, 12);
          expect(style.height, 1.5);
          expect(tester.getRect(button), tester.getRect(surface));
          expect(tester.getSize(button).height, 18 * scale);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'inline metadata hover is immediate and cancelled presses do not activate',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Center(
              child: DButton(
                label: const Text('Metadata'),
                variant: DButtonVariant.inline,
                density: DButtonDensity.inlineMetadata,
                onPressed: () => activations++,
              ),
            ),
          ),
        ),
      );
      final button = find.byType(DButton);
      Color? foreground() => DefaultTextStyle.of(
        tester.element(find.text('Metadata')),
      ).style.color;
      final resting = foreground();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pump();
      expect(foreground(), isNot(resting));
      await mouse.down(tester.getCenter(button));
      await mouse.cancel();
      await tester.pumpAndSettle();
      expect(activations, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
