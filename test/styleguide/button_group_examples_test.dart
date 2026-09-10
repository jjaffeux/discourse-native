import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/button_group_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registers every frozen documented composition', () {
    expect(componentExamples['button-group'], same(buttonGroupExamples));
    expect(buttonGroupExamples.examples.map((example) => example.title), [
      'Composition and independent actions',
      'Orientation',
      'Sizes',
      'Nested groups',
      'Separator and split action',
      'Input',
      'Input Group composition',
      'Dropdown menu',
      'Select composition',
      'Popover composition',
      'RTL',
      'Reference demo',
    ]);
    expect(
      buttonGroupExamples.examples.every(
        (example) => example.code.contains('DButtonGroup'),
      ),
      isTrue,
    );
  });

  for (var index = 0; index < buttonGroupExamples.examples.length; index++) {
    testWidgets('example $index fits a narrow RTL large-text preview', (
      tester,
    ) async {
      await _pump(tester, index, direction: TextDirection.rtl, textScale: 2);
      expect(find.byType(DButtonGroup), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'input and controlled fixture state survives a live theme change',
    (tester) async {
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<ThemeData>(
          valueListenable: theme,
          builder: (context, value, child) => MaterialApp(
            theme: value,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: buttonGroupExamples.examples[5].builder,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'retained query');
      theme.value = AppTheme.dark;
      await tester.pump();
      expect(find.text('retained query'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nested fixture spaces complete button and input groups', (
    tester,
  ) async {
    await _pump(tester, 3);

    expect(find.byType(DButtonGroup), findsNWidgets(3));
    expect(find.byType(DInputGroup), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DInputGroup),
        matching: find.byType(DInputGroupButton),
      ),
      findsOneWidget,
    );

    final attachment = tester.getRect(find.byTooltip('Add attachment'));
    final composer = tester.getRect(find.byType(DInputGroup));
    final group = tester.getRect(find.byType(DButtonGroup).first);
    expect(composer.left - attachment.right, DSpacing.sm);
    expect(group.width, 252);
    expect(composer.width, group.width - attachment.width - DSpacing.sm);
  });

  testWidgets('dropdown trigger opens and remains an independent button', (
    tester,
  ) async {
    await _pump(tester, 7);
    await tester.tap(find.byTooltip('More follow actions'));
    await tester.pumpAndSettle();
    expect(find.text('Mute conversation'), findsOneWidget);
    expect(find.byType(DDropdownMenuContent), findsOneWidget);
    expect(find.byType(DDropdownMenuItem), findsNWidgets(4));
  });

  testWidgets('currency fixture updates without resetting amount editing', (
    tester,
  ) async {
    await _pump(tester, 8);
    expect(find.byType(DSelect<String>), findsOneWidget);
    await tester.enterText(find.byType(TextField), '42.50');
    await tester.tap(find.text(r'$'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('€').last);
    await tester.pumpAndSettle();
    expect(find.text('€'), findsOneWidget);
    expect(find.text('42.50'), findsOneWidget);
  });

  testWidgets('input fixture matches the documented two-control composition', (
    tester,
  ) async {
    await _pump(tester, 5);

    expect(find.byType(DField), findsNothing);
    expect(find.byType(DButtonGroupText), findsNothing);
    expect(find.byType(DInput), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);

    final group = tester.getRect(find.byType(DButtonGroup));
    final input = tester.getRect(find.byType(DInput));
    final action = tester.getRect(find.byTooltip('Search'));
    expect(group.width, 229);
    expect(input.left, group.left);
    expect(input.right, action.left);
    expect(action.right, group.right);

    await tester.enterText(find.byType(TextField), 'retained query');
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    expect(find.text('retained query'), findsOneWidget);
  });

  testWidgets('input group fixture preserves editing and voice action state', (
    tester,
  ) async {
    await _pump(tester, 6);

    expect(find.byType(DButtonGroup), findsNWidgets(3));
    final attachment = tester.getRect(find.byTooltip('Add attachment'));
    final composer = tester.getRect(find.byType(DInputGroup));
    final group = tester.getRect(find.byType(DButtonGroup).first);
    expect(composer.left - attachment.right, DSpacing.sm);
    expect(composer.width, group.width - attachment.width - DSpacing.sm);

    await tester.enterText(find.byType(TextField), 'voice note');
    await tester.tap(find.byTooltip('Enable voice mode'));
    await tester.pumpAndSettle();
    expect(find.text('voice note'), findsOneWidget);
    expect(find.byTooltip('Disable voice mode'), findsOneWidget);
    expect(find.byType(DInputGroup), findsOneWidget);
    expect(find.byType(DInputGroupInput), findsOneWidget);
    expect(find.byType(DInputGroupButton), findsOneWidget);
  });

  testWidgets(
    'popover fixture uses the public overlay and restores its trigger',
    (tester) async {
      await _pump(tester, 9);
      final trigger = find.byTooltip('Open Copilot task form');
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.text('Start a new task with Copilot'), findsOneWidget);
      expect(find.byType(DPopoverContent), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DPopoverContent), findsNothing);
      expect(
        Focus.of(tester.element(find.byType(FilledButton).last)).hasFocus,
        isTrue,
      );
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  int index, {
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Builder(
                builder: buttonGroupExamples.examples[index].builder,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
