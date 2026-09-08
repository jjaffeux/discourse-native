import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/direction_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('live editor inherits and overrides without losing saved state', (
    tester,
  ) async {
    final direction = ValueNotifier(TextDirection.ltr);
    addTearDown(direction.dispose);
    await _pump(tester, directionExamples.examples[0], direction: direction);
    await tester.enterText(find.byType(TextField), 'ليلى');
    await tester.tap(find.widgetWithText(DButton, 'Save locally'));
    await tester.pump();
    expect(find.text('Saved: ليلى'), findsOneWidget);
    expect(find.text('Current direction: LTR'), findsOneWidget);

    direction.value = TextDirection.rtl;
    await tester.pump();
    expect(find.text('Current direction: RTL'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'LTR'));
    await tester.pump();
    expect(find.text('Current direction: LTR'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Inherit'));
    await tester.pump();
    expect(find.text('Current direction: RTL'), findsOneWidget);
    expect(find.text('Saved: ليلى'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'ليلى',
    );
    await tester.tap(find.widgetWithText(DButton, 'Clear'));
    await tester.pump();
    expect(find.text('No saved name'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
  });

  testWidgets(
    'nested example keeps URL direction and resumes the outer scope',
    (tester) async {
      await _pump(tester, directionExamples.examples[1]);
      expect(find.text('Outer section: RTL'), findsOneWidget);
      expect(find.text('URL island: LTR'), findsOneWidget);
      expect(find.text('Inherited island: LTR'), findsOneWidget);
      expect(find.text('Outer sibling: RTL'), findsOneWidget);
      expect(
        DDirection.of(tester.element(find.byType(SelectableText))),
        TextDirection.ltr,
      );
    },
  );

  testWidgets('open menu follows live direction, palette and native keyboard', (
    tester,
  ) async {
    final direction = ValueNotifier(TextDirection.ltr);
    final theme = ValueNotifier(AppTheme.light);
    addTearDown(direction.dispose);
    addTearDown(theme.dispose);
    await _pump(
      tester,
      directionExamples.examples[2],
      direction: direction,
      theme: theme,
    );
    final trigger = find.widgetWithText(TextButton, 'Open direction menu');
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('Menu direction: LTR'), findsOneWidget);

    direction.value = TextDirection.rtl;
    theme.value = StyleguideTheme.plum.resolve(AppTheme.light);
    await tester.pumpAndSettle();
    final menuLabel = find.text('Menu direction: RTL');
    expect(menuLabel, findsOneWidget);
    expect(DDirection.of(tester.element(menuLabel)), TextDirection.rtl);
    expect(
      Theme.of(tester.element(menuLabel)).colorScheme,
      theme.value.colorScheme,
    );
    expect(DTokens.of(tester.element(menuLabel)).radius, 12);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Selected: RTL'), findsOneWidget);
    expect(find.text('Menu direction: RTL'), findsNothing);
    expect(
      tester.widget<TextButton>(trigger).focusNode!.hasPrimaryFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Menu direction: RTL'), findsNothing);
    expect(
      tester.widget<TextButton>(trigger).focusNode!.hasPrimaryFocus,
      isTrue,
    );

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(600, 400));
    await tester.pumpAndSettle();
    expect(find.text('Menu direction: RTL'), findsNothing);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final example in directionExamples.examples) {
    for (final (theme, width, scale, direction) in [
      (StyleguideTheme.light, 1024.0, 1.0, TextDirection.ltr),
      (StyleguideTheme.dark, 360.0, 2.0, TextDirection.rtl),
      (StyleguideTheme.forest, 320.0, 2.0, TextDirection.rtl),
      (StyleguideTheme.plum, 768.0, 1.0, TextDirection.ltr),
    ]) {
      testWidgets(
        '${example.title} fits ${theme.name} at $width px and ${scale}x text',
        (tester) async {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final themeValue = ValueNotifier(theme.resolve(AppTheme.light));
          final directionValue = ValueNotifier(direction);
          addTearDown(themeValue.dispose);
          addTearDown(directionValue.dispose);
          await _pump(
            tester,
            example,
            theme: themeValue,
            direction: directionValue,
            scale: scale,
            reducedMotion: true,
          );
          expect(tester.takeException(), isNull);
          final context = tester.element(find.byKey(const ValueKey('example')));
          expect(MediaQuery.disableAnimationsOf(context), isTrue);
          expect(MediaQuery.textScalerOf(context).scale(14), 14 * scale);
          expect(Theme.of(context).colorScheme, themeValue.value.colorScheme);
          if (example == directionExamples.examples[2]) {
            await tester.tap(find.text('Open direction menu'));
            await tester.pumpAndSettle();
            expect(
              find.text('Menu direction: ${direction.name.toUpperCase()}'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}

Future<void> _pump(
  WidgetTester tester,
  StyleguideExample example, {
  ValueNotifier<TextDirection>? direction,
  ValueNotifier<ThemeData>? theme,
  double scale = 1,
  bool reducedMotion = false,
}) async {
  final hostDirection = direction ?? ValueNotifier(TextDirection.ltr);
  final hostTheme = theme ?? ValueNotifier(AppTheme.light);
  if (direction == null) addTearDown(hostDirection.dispose);
  if (theme == null) addTearDown(hostTheme.dispose);
  await tester.pumpWidget(
    ValueListenableBuilder(
      valueListenable: hostTheme,
      builder: (context, themeData, _) => MaterialApp(
        theme: themeData,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => ValueListenableBuilder(
          valueListenable: hostDirection,
          builder: (context, value, _) => DDirection(
            textDirection: value,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reducedMotion,
              ),
              child: child!,
            ),
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(DSpacing.lg),
            child: Builder(
              key: const ValueKey('example'),
              builder: example.builder,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
