import 'dart:ui' show CheckedState;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/application_component_catalogue.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/message_inbox_menu_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
  DMessageInboxOption(
    value: 'personal:',
    label: 'Personal',
    description: 'Private messages sent directly to you',
    icon: Icon(Icons.person_outline),
  ),
  DMessageInboxOption(
    value: 'group:team',
    label: 'team',
    description: 'Private messages sent to @team',
    icon: Icon(Icons.group_outlined),
  ),
];

Finder _option(String value) => find.byWidgetPredicate(
  (widget) => widget is DDropdownMenuRadioItem<String> && widget.value == value,
);

void main() {
  testWidgets('controlled selection exposes the inbox and restores focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final value = ValueNotifier('personal:');
    addTearDown(value.dispose);
    final changes = <String>[];
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<String>(
                valueListenable: value,
                builder: (context, current, _) => DMessageInboxMenu<String>(
                  value: current,
                  options: _options,
                  onChanged: changes.add,
                ),
              ),
            ),
          ),
        ),
      );
      final trigger = find.byType(DButton);
      expect(
        tester.getSemantics(trigger),
        matchesSemantics(
          label: 'Choose inbox: Personal',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasExpandedState: true,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      final selected = tester
          .getSemantics(_option('personal:'))
          .getSemanticsData();
      expect(selected.flagsCollection.isChecked, CheckedState.isTrue);
      expect(selected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(selected.label, 'Personal. Private messages sent directly to you');

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, ['group:team']);
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(find.text('Personal'), findsOneWidget);
      expect(tester.widget<DButton>(trigger).focusNode!.hasFocus, isTrue);

      value.value = 'group:team';
      await tester.pumpAndSettle();
      expect(find.byTooltip('Choose inbox: team'), findsOneWidget);
      expect(tester.widget<DButton>(trigger).icon, same(_options.last.icon));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      value.value = 'personal:';
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(_option('personal:'))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      expect(
        tester
            .getSemantics(_option('group:team'))
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(tester.widget<DButton>(trigger).focusNode!.hasFocus, isTrue);
      expect(changes, ['group:team']);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('disabled inbox trigger cannot open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DMessageInboxMenu<String>(
            value: 'personal:',
            options: _options,
            onChanged: null,
          ),
        ),
      ),
    );
    expect(tester.widget<DButton>(find.byType(DButton)).onPressed, isNull);
    await tester.tap(find.byType(DButton));
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
  });

  testWidgets(
    'styleguide examples scroll in narrow scaled RTL and update live palettes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      expect(
        componentExamples['message-inbox-menu'],
        same(messageInboxMenuExamples),
      );
      expect(
        applicationComponentCatalogue.any(
          (entry) => entry.id == 'message-inbox-menu',
        ),
        isTrue,
      );

      for (final example in messageInboxMenuExamples.examples) {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final theme in [
          AppTheme.light,
          AppTheme.dark,
          StyleguideTheme.forest.resolve(AppTheme.light),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 640),
                    textScaler: TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Center(child: Builder(builder: example.builder)),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (example.title == 'Disabled') {
            expect(
              tester.widget<DButton>(find.byType(DButton)).onPressed,
              isNull,
            );
            continue;
          }
          if (find.byType(DDropdownMenuContent).evaluate().isEmpty) {
            await tester.tap(find.byType(DButton));
            await tester.pumpAndSettle();
          }
          final popup = tester.getRect(find.byType(DDropdownMenuContent));
          expect(popup.left, greaterThanOrEqualTo(0));
          expect(popup.right, lessThanOrEqualTo(320));
          expect(popup.bottom, lessThanOrEqualTo(640));
          expect(tester.takeException(), isNull, reason: example.title);
        }
        if (example.title == 'Disabled') continue;
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        final lastValue = switch (example.title) {
          'Many groups' => 'group:trust-and-safety',
          'Personal only' => 'personal:',
          _ => 'group:engineers-emea',
        };
        final popup = tester.getRect(find.byType(DDropdownMenuContent));
        final last = tester.getRect(_option(lastValue));
        // Scroll offsets and physical-pixel rounding can differ fractionally.
        expect(last.top, greaterThanOrEqualTo(popup.top - 1));
        expect(last.bottom, lessThanOrEqualTo(popup.bottom + 1));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(
          tester
              .widget<DMessageInboxMenu<String>>(
                find.byType(DMessageInboxMenu<String>),
              )
              .value,
          lastValue,
        );
        expect(tester.takeException(), isNull, reason: example.title);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
