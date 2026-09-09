import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/direction_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _arabicTitle = 'تسجيل الدخول إلى حسابك';
const _hebrewTitle = 'התחבר לחשבון שלך';
const _englishTitle = 'Login to your account';

void main() {
  testWidgets(
    'Card RTL follows the chosen language while its selector stays LTR',
    (tester) async {
      final direction = ValueNotifier(TextDirection.ltr);
      addTearDown(direction.dispose);
      await _pump(tester, _example('Card RTL'), direction: direction);
      expect(find.text(_arabicTitle), findsOneWidget);
      expect(_directionOf(tester, _arabicTitle), TextDirection.rtl);
      expect(find.text('Arabic (العربية)'), findsOneWidget);
      expect(_directionOf(tester, 'Arabic (العربية)'), TextDirection.ltr);
      final emailFocus = tester
          .widget<DInput>(find.byType(DInput).first)
          .focusNode;
      await tester.enterText(find.byType(TextField).first, 'm@example.com');

      await tester.tap(find.text('Arabic (العربية)'));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Hebrew (עברית)'), findsOneWidget);
      expect(_directionOf(tester, 'English'), TextDirection.ltr);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text(_arabicTitle), findsNothing);
      expect(find.text(_englishTitle), findsOneWidget);
      expect(find.text('Forgot your password?'), findsOneWidget);
      expect(_directionOf(tester, _englishTitle), TextDirection.ltr);
      expect(
        tester.widget<DInput>(find.byType(DInput).first).focusNode,
        same(emailFocus),
      );
      expect(_editorText(tester), 'm@example.com');

      // The preview direction reaches neither the fixed selector nor the
      // language-owned card.
      direction.value = TextDirection.rtl;
      await tester.pump();
      expect(_directionOf(tester, 'English'), TextDirection.ltr);
      expect(_directionOf(tester, _englishTitle), TextDirection.ltr);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(_directionOf(tester, 'Hebrew (עברית)'), TextDirection.ltr);
      await tester.tap(find.text('Hebrew (עברית)'));
      await tester.pumpAndSettle();
      expect(find.text(_hebrewTitle), findsOneWidget);
      expect(find.text('שכחת את הסיסמה?'), findsOneWidget);
      expect(_directionOf(tester, _hebrewTitle), TextDirection.rtl);
      expect(find.text('Hebrew (עברית)'), findsOneWidget);
      expect(_editorText(tester), 'm@example.com');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Card RTL validates locally and reports its actions', (
    tester,
  ) async {
    await _pump(tester, _example('Card RTL'));
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pump();
    expect(find.text('Enter an email address'), findsOneWidget);
    expect(find.text('Enter a password'), findsOneWidget);
    expect(find.text('Signed in locally'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'm@example.com');
    await tester.enterText(find.byType(TextField).last, 'local-only');
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pump();
    expect(find.text('Enter an email address'), findsNothing);
    expect(find.text('Signed in locally'), findsOneWidget);

    await tester.tap(find.text('إنشاء حساب'));
    await tester.pump();
    expect(find.text('Sign up selected'), findsOneWidget);
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pump();
    expect(find.text('Password recovery selected'), findsOneWidget);
    await tester.tap(find.text('تسجيل الدخول باستخدام Google'));
    await tester.pump();
    expect(find.text('Google login selected'), findsOneWidget);
  });

  testWidgets('live editor inherits and overrides without losing saved state', (
    tester,
  ) async {
    final direction = ValueNotifier(TextDirection.ltr);
    addTearDown(direction.dispose);
    await _pump(
      tester,
      _example('Live direction and editing'),
      direction: direction,
    );
    await tester.enterText(find.byType(TextField), 'ليلى');
    await tester.tap(find.widgetWithText(DButton, 'Save locally'));
    await tester.pump();
    expect(find.text('Saved: ليلى'), findsOneWidget);
    expect(find.text('Current direction: LTR'), findsOneWidget);

    direction.value = TextDirection.rtl;
    await tester.pump();
    expect(find.text('Current direction: RTL'), findsOneWidget);
    await tester.tap(find.widgetWithText(DToggle, 'LTR'));
    await tester.pump();
    expect(find.text('Current direction: LTR'), findsOneWidget);
    await tester.tap(find.widgetWithText(DToggle, 'Inherit'));
    await tester.pump();
    expect(find.text('Current direction: RTL'), findsOneWidget);
    expect(find.text('Saved: ليلى'), findsOneWidget);
    expect(_editorText(tester), 'ليلى');
    await tester.tap(find.widgetWithText(DButton, 'Clear'));
    await tester.pump();
    expect(find.text('No saved name'), findsOneWidget);
    expect(_editorText(tester), isEmpty);
  });

  testWidgets(
    'nested example keeps URL direction and resumes the outer scope',
    (tester) async {
      await _pump(tester, _example('Nested overrides and fixed content'));
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
      _example('Inherited direction in a dropdown menu'),
      direction: direction,
      theme: theme,
    );
    final trigger = find.widgetWithText(DButton, 'Open direction menu');
    expect(find.byType(MenuAnchor), findsNothing);
    expect(find.byType(DDropdownMenu), findsOneWidget);
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

    // Updating the first row's label must not reorder keyboard navigation.
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Selected: RTL'), findsOneWidget);
    expect(find.text('Menu direction: RTL'), findsNothing);
    expect(tester.widget<DButton>(trigger).focusNode!.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Selected: Second action'), findsOneWidget);
    expect(tester.widget<DButton>(trigger).focusNode!.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Menu direction: RTL'), findsNothing);
    expect(tester.widget<DButton>(trigger).focusNode!.hasPrimaryFocus, isTrue);

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
          switch (example.title) {
            case 'Card RTL':
              await tester.tap(find.text('Arabic (العربية)'));
              await tester.pumpAndSettle();
              expect(find.text('Hebrew (עברית)'), findsOneWidget);
              expect(_directionOf(tester, 'Hebrew (עברית)'), TextDirection.ltr);
              expect(tester.takeException(), isNull);
            case 'Inherited direction in a dropdown menu':
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

StyleguideExample _example(String title) =>
    directionExamples.examples.singleWhere((entry) => entry.title == title);

TextDirection _directionOf(WidgetTester tester, String text) =>
    DDirection.of(tester.element(find.text(text)));

String _editorText(WidgetTester tester) => tester
    .widget<EditableText>(find.byType(EditableText).first)
    .controller
    .text;

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
