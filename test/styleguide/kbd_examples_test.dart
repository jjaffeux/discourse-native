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
    'button keycaps preserve pointer, keyboard action and live tooltip composition',
    (tester) async {
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await _pumpLive(tester, theme, const KbdActionSample());
        await tester.tap(find.widgetWithText(DButton, 'Accept'));
        await tester.pump();
        expect(find.text('Accepted: 1'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pump();
        expect(find.text('Accepted: 2'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(find.text('Accepted: 3'), findsOneWidget);
        final focus = FocusManager.instance.primaryFocus;
        final tooltip = tester.widget<RawTooltip>(
          find.descendant(
            of: find.byType(DTooltip),
            matching: find.byType(RawTooltip),
          ),
        );
        expect(tooltip.semanticsTooltip, 'Accept invitation, F6');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(find.text('Inspect hint')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Accept invitation'), findsOneWidget);
        final hint = find.descendant(
          of: find.byType(DShortcutKeycaps),
          matching: find.byType(DKbd),
        );
        for (final palette in [
          StyleguideTheme.dark,
          StyleguideTheme.forest,
          StyleguideTheme.plum,
        ]) {
          theme.value = palette.resolve(AppTheme.light);
          await tester.pumpAndSettle();
          expect(find.text('Accept invitation'), findsOneWidget);
          expect(FocusManager.instance.primaryFocus, focus);
          expect(find.text('Accepted: 3'), findsOneWidget);
          final surface = tester.widget<AnimatedContainer>(
            find.descendant(of: hint, matching: find.byType(AnimatedContainer)),
          );
          expect(
            (surface.decoration! as BoxDecoration).color,
            theme.value.extension<DTokens>()!.muted,
          );
        }
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Accept invitation'), findsNothing);
        // Long press uses the same overlay and can outlive the touch release.
        await tester.longPress(find.text('Inspect hint'));
        await tester.pumpAndSettle();
        expect(find.text('Accept invitation'), findsOneWidget);
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
      '${platform.name} search chord focuses native input and preserves query through live theme and direction',
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
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final input = tester
            .widget<TextField>(find.byType(TextField))
            .focusNode!;
        final modifier = platform == TargetPlatform.linux
            ? LogicalKeyboardKey.controlLeft
            : LogicalKeyboardKey.metaLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        expect(input.hasFocus, isTrue);
        await tester.enterText(find.byType(TextField), 'community');
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
          Directionality.of(tester.element(find.byType(DShortcutKeycaps))),
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
