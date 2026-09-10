import 'dart:ui' show Tristate;

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
  (widget) =>
      widget is DComboboxItem<DMessageInboxOption<String>> &&
      widget.option.value.value == value,
);

Finder _itemSemantics(String value) => find.descendant(
  of: _option(value),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.button == true,
  ),
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
          .getSemantics(_itemSemantics('personal:'))
          .getSemanticsData();
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      expect(selected.label, contains('Personal'));
      expect(selected.label, contains('Private messages sent directly to you'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, ['group:team']);
      expect(find.byType(DComboboxContent), findsNothing);
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
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(_itemSemantics('personal:'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(_itemSemantics('group:team'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxContent), findsNothing);
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
    expect(find.byType(DComboboxContent), findsNothing);
  });

  testWidgets(
    'search filters names, handles no matches, and resets on reopen',
    (tester) async {
      final example = messageInboxMenuExamples.examples.firstWhere(
        (example) => example.title == 'Many groups',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: Builder(builder: example.builder)),
          ),
        ),
      );
      final trigger = find.byType(DButton);
      String currentInbox() => tester
          .widget<DMessageInboxMenu<String>>(
            find.byType(DMessageInboxMenu<String>),
          )
          .value;
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(
        find.byType(DComboboxItem<DMessageInboxOption<String>>),
        findsNWidgets(16),
      );
      await tester.enterText(find.byType(TextField), 'SAFETY');
      await tester.pumpAndSettle();
      expect(_option('group:trust-and-safety'), findsOneWidget);
      expect(_option('personal:'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(currentInbox(), 'group:trust-and-safety');
      expect(find.byType(DComboboxContent), findsNothing);

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(_option('personal:'), findsOneWidget);
      // Descriptions are not search keywords: their shared wording would match
      // every inbox and make name filtering less useful.
      await tester.enterText(find.byType(TextField), 'Private messages');
      await tester.pumpAndSettle();
      expect(find.text('No inboxes found.'), findsOneWidget);
      expect(
        find.byType(DComboboxItem<DMessageInboxOption<String>>),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(currentInbox(), 'group:trust-and-safety');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxContent), findsNothing);
      expect(tester.widget<DButton>(trigger).focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), '  personal  ');
      await tester.pumpAndSettle();
      expect(_option('personal:'), findsOneWidget);
      await tester.tap(_option('personal:'));
      await tester.pumpAndSettle();
      expect(currentInbox(), 'personal:');
      expect(tester.takeException(), isNull);
    },
  );

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
          if (find.byType(DComboboxContent).evaluate().isEmpty) {
            await tester.tap(find.byType(DButton));
            await tester.pumpAndSettle();
          }
          final popup = tester.getRect(find.byType(DComboboxContent));
          expect(popup.left, greaterThanOrEqualTo(0));
          expect(popup.right, lessThanOrEqualTo(320));
          expect(popup.bottom, lessThanOrEqualTo(640));
          expect(popup.height, lessThanOrEqualTo(288));
          expect(tester.takeException(), isNull, reason: example.title);
        }
        if (example.title == 'Disabled') continue;
        final count = find
            .byType(DComboboxItem<DMessageInboxOption<String>>)
            .evaluate()
            .length;
        for (var index = 1; index < count; index++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        }
        await tester.pumpAndSettle();
        final lastValue = switch (example.title) {
          'Many groups' => 'group:trust-and-safety',
          'Personal only' => 'personal:',
          _ => 'group:engineers-emea',
        };
        final popup = tester.getRect(find.byType(DComboboxContent));
        final list = find.byType(DComboboxList<DMessageInboxOption<String>>);
        final last = tester.getRect(_option(lastValue));
        expect(last.overlaps(tester.getRect(list)), isTrue);
        // At 200% with the test font, a rich row can exceed the capped list.
        // Its remaining description must still be reachable by scrolling.
        await tester.drag(list, Offset(0, -last.height));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(_option(lastValue)).bottom,
          lessThanOrEqualTo(popup.bottom + 1),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(DComboboxContent), findsNothing);
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
