import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/kbd_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final palette in [
    StyleguideTheme.light,
    StyleguideTheme.dark,
    StyleguideTheme.forest,
    StyleguideTheme.plum,
  ]) {
    testWidgets(
      '${palette.name} examples fit narrow and wide previews at 200 percent text in both directions',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final width in [240.0, 360.0, 900.0]) {
          tester.view.physicalSize = Size(width, 1000);
          for (final direction in TextDirection.values) {
            for (final example in kbdExamples.examples) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: palette.resolve(AppTheme.light),
                  home: Scaffold(
                    body: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(2),
                        disableAnimations: true,
                      ),
                      child: DDirection(
                        textDirection: direction,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(DSpacing.lg),
                          child: Builder(builder: example.builder),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump();
              expect(
                tester.takeException(),
                isNull,
                reason: '${example.title}: $width, $direction',
              );
            }
          }
        }
      },
    );
  }

  testWidgets(
    'the outline button carries the Enter keycap at its inline end and activates by pointer and keyboard',
    (tester) async {
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await _pumpLive(tester, theme, const KbdActionSample());
        final button = tester.widget<DButton>(find.byType(DButton));
        expect(button.variant, DButtonVariant.outline);
        expect(button.iconPosition, DButtonIconPosition.end);
        final keycap = find.descendant(
          of: find.byType(DButton),
          matching: find.widgetWithText(DKbd, '⏎'),
        );
        expect(keycap, findsOneWidget);
        final label = tester.getRect(find.text('Accept'));
        final cap = tester.getRect(keycap);
        final surface = tester.getRect(find.byType(FilledButton));
        expect(cap.left, greaterThan(label.right));
        expect(cap.right, lessThan(surface.right));
        expect(cap.height, 20);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Accept, Enter')),
          isSemantics(label: 'Accept, Enter', isButton: true),
        );
        await tester.tap(find.byType(DButton));
        await tester.pump();
        expect(find.text('Accepted: 1'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(find.text('Accepted: 2'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'button-group tooltips show keycaps with the live tint and run their shortcuts',
    (tester) async {
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await _pumpLive(tester, theme, const KbdTooltipSample());
        expect(
          find.descendant(
            of: find.byType(DButtonGroup),
            matching: find.byType(DButton),
          ),
          findsNWidgets(2),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(find.text('Save')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Save Changes'), findsOneWidget);
        final hint = find.descendant(
          of: find.byType(DShortcutKeycaps),
          matching: find.widgetWithText(DKbd, 'S'),
        );
        expect(hint, findsOneWidget);
        for (final palette in [
          StyleguideTheme.light,
          StyleguideTheme.dark,
          StyleguideTheme.forest,
          StyleguideTheme.plum,
        ]) {
          theme.value = palette.resolve(AppTheme.light);
          await tester.pumpAndSettle();
          expect(find.text('Save Changes'), findsOneWidget);
          final foreground = theme.value.extension<DTokens>()!.background;
          final surface = tester.widget<AnimatedContainer>(
            find.descendant(of: hint, matching: find.byType(AnimatedContainer)),
          );
          expect(
            (surface.decoration! as BoxDecoration).color,
            foreground.withValues(
              alpha:
                  foreground.a *
                  (theme.value.brightness == Brightness.dark ? 0.10 : 0.20),
            ),
          );
          final label = tester.widget<AnimatedDefaultTextStyle>(
            find.descendant(
              of: hint,
              matching: find.byType(AnimatedDefaultTextStyle),
            ),
          );
          expect(label.style.color, foreground);
        }
        await mouse.moveTo(const Offset(790, 590));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Save Changes'), findsNothing);
        await mouse.moveTo(tester.getCenter(find.text('Print')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Print Document'), findsOneWidget);
        expect(find.widgetWithText(DKbd, 'Ctrl'), findsOneWidget);
        expect(find.widgetWithText(DKbd, 'P'), findsOneWidget);
        await mouse.moveTo(const Offset(790, 590));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.pump();
        expect(find.text('Saved changes.'), findsOneWidget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(find.text('Printed document.'), findsOneWidget);
        // Long press uses the same overlay and can outlive the touch release.
        await tester.longPress(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Save Changes'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '${platform.name} search chord focuses the grouped input and preserves query through live theme and direction',
      (tester) async {
        final theme = ValueNotifier(
          AppTheme.light.copyWith(platform: platform),
        );
        final rtl = ValueNotifier(false);
        addTearDown(theme.dispose);
        addTearDown(rtl.dispose);
        await _pumpLive(
          tester,
          theme,
          ValueListenableBuilder(
            valueListenable: rtl,
            builder: (_, value, child) => DDirection(
              textDirection: value ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
            child: const KbdInputSample(),
          ),
        );
        final apple = platform != TargetPlatform.linux;
        final addon = find.descendant(
          of: find.byType(DInputGroupAddon).last,
          matching: find.byType(DKbd),
        );
        expect(addon, findsNWidgets(2));
        expect(
          find.descendant(of: addon, matching: find.text(apple ? '⌘' : 'Ctrl')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: addon, matching: find.text('K')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.search), findsOneWidget);
        expect(tester.getSize(find.byType(DInputGroup)).width, 320);
        final input = tester
            .widget<DInputGroupInput>(find.byType(DInputGroupInput))
            .focusNode!;
        expect(input.hasFocus, isFalse);
        final modifier = apple
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        expect(input.hasFocus, isTrue);
        await tester.enterText(find.byType(EditableText), 'community');
        theme.value = StyleguideTheme.plum
            .resolve(AppTheme.light)
            .copyWith(platform: platform);
        rtl.value = true;
        await tester.pumpAndSettle();
        expect(input.hasFocus, isTrue);
        expect(find.text('Query: community'), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          'community',
        );
        expect(
          Directionality.of(tester.element(find.byType(DKbd).first)),
          TextDirection.rtl,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _pumpLive(
  WidgetTester tester,
  ValueNotifier<ThemeData> theme,
  Widget child,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder(
        valueListenable: theme,
        builder: (_, value, child) => Theme(data: value, child: child!),
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);
