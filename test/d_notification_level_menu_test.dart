import 'dart:ui' show CheckedState;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/application_component_catalogue.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/notification_level_menu_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
  DNotificationLevelOption(
    value: 3,
    label: 'Watching',
    description: 'Every reply and unread count',
    icon: Icon(Icons.notifications_active_outlined),
    emphasized: true,
  ),
  DNotificationLevelOption(
    value: 1,
    label: 'Normal',
    description: 'Mentions and replies only',
    icon: Icon(Icons.notifications_outlined),
  ),
  DNotificationLevelOption(
    value: 0,
    label: 'Muted',
    description: 'No notifications; hidden from Latest',
    icon: Icon(Icons.notifications_off_outlined),
  ),
];

Finder _option(int value) => find.byWidgetPredicate(
  (widget) => widget is DDropdownMenuRadioItem<int> && widget.value == value,
);

void main() {
  for (final showLabel in [false, true]) {
    testWidgets('outlined trigger selects a level (label: $showLabel)', (
      tester,
    ) async {
      final changes = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DButtonGroup(
                children: [
                  const DButton(
                    label: Text('Reply'),
                    variant: DButtonVariant.outline,
                    onPressed: null,
                  ),
                  DNotificationLevelMenu<int>(
                    value: 3,
                    options: _options,
                    semanticLabel: 'Topic notifications',
                    showLabel: showLabel,
                    variant: DButtonVariant.outline,
                    onChanged: changes.add,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final trigger = find.descendant(
        of: find.byType(DNotificationLevelMenu<int>),
        matching: find.byType(DButton),
      );
      expect(tester.widget<DButton>(trigger).variant, DButtonVariant.outline);
      expect(find.byTooltip('Topic notifications: Watching'), findsOneWidget);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(_option(0));
      await tester.pumpAndSettle();
      expect(changes, [0]);
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(tester.widget<DButton>(trigger).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'selection announces the value, closes, and follows caller state',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final value = ValueNotifier(1);
      addTearDown(value.dispose);
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: value,
                  builder: (context, current, _) => DNotificationLevelMenu<int>(
                    value: current,
                    options: _options,
                    semanticLabel: 'Topic notifications',
                    showLabel: true,
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
            label: 'Topic notifications: Normal',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
            hasExpandedState: true,
          ),
        );
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final selected = tester.getSemantics(_option(1)).getSemanticsData();
        expect(selected.flagsCollection.isChecked, CheckedState.isTrue);
        expect(selected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
        expect(selected.label, 'Normal. Mentions and replies only');

        await tester.tap(_option(3));
        await tester.pumpAndSettle();
        expect(changes, [3]);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(find.text('Normal'), findsOneWidget);

        value.value = 3;
        await tester.pumpAndSettle();
        expect(find.byTooltip('Topic notifications: Watching'), findsOneWidget);
        expect(find.text('Watching'), findsOneWidget);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        value.value = 0;
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(_option(0))
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          CheckedState.isTrue,
        );
        expect(
          tester
              .getSemantics(_option(3))
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          CheckedState.isFalse,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('keyboard selection and dismissal restore the button focus', (
    tester,
  ) async {
    final changes = <int>[];
    await _pump(tester, onChanged: changes.add);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changes, [0]);
    expect(
      tester.widget<DButton>(find.byType(DButton)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(
      tester.widget<DButton>(find.byType(DButton)).focusNode!.hasFocus,
      isTrue,
    );
    expect(changes, [0]);
  });

  testWidgets(
    'disabled controls cannot open and changing owner retires a menu',
    (tester) async {
      await _pump(tester);
      expect(tester.widget<DButton>(find.byType(DButton)).onPressed, isNull);
      await tester.tap(find.byType(DButton));
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);

      final changes = <int>[];
      await _pump(tester, onChanged: changes.add);
      await tester.tap(find.byType(DButton));
      await tester.pumpAndSettle();
      await _pump(tester, onChanged: changes.add, owner: 'other-topic');
      await tester.pumpAndSettle();
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(changes, isEmpty);
    },
  );

  testWidgets(
    'styleguide menus fit scaled RTL and retain selection across palettes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      expect(
        componentExamples['notification-level-menu'],
        same(notificationLevelMenuExamples),
      );
      expect(
        applicationComponentCatalogue.any(
          (entry) => entry.id == 'notification-level-menu',
        ),
        isTrue,
      );
      for (final example in notificationLevelMenuExamples.examples) {
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
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (example.title == 'Disabled') {
            expect(
              tester
                  .widgetList<DButton>(find.byType(DButton))
                  .every((button) => button.onPressed == null),
              isTrue,
            );
            continue;
          }
          if (find.byType(DDropdownMenuContent).evaluate().isEmpty) {
            await tester.tap(find.byType(DButton));
            await tester.pumpAndSettle();
          }
          final menuRect = tester.getRect(find.byType(DDropdownMenuContent));
          expect(menuRect.left, greaterThanOrEqualTo(0));
          expect(menuRect.right, lessThanOrEqualTo(320));
          expect(menuRect.bottom, lessThanOrEqualTo(640));
          expect(tester.takeException(), isNull, reason: example.title);
        }
        if (example.title != 'Disabled') {
          await tester.sendKeyEvent(LogicalKeyboardKey.end);
          await tester.pumpAndSettle();
          final popup = tester.getRect(find.byType(DDropdownMenuContent));
          final last = tester.getRect(
            _option(example.title == 'Thread notifications' ? 3 : 0),
          );
          expect(last.top, greaterThanOrEqualTo(popup.top));
          expect(last.bottom, lessThanOrEqualTo(popup.bottom));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.byType(DDropdownMenuContent), findsNothing);
          expect(
            tester.widget<DButton>(find.byType(DButton)).tooltip,
            endsWith(
              example.title == 'Thread notifications' ? 'Watching' : 'Muted',
            ),
          );
        }
      }
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  ValueChanged<int>? onChanged,
  String owner = 'topic',
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: DNotificationLevelMenu<int>(
          key: ValueKey(owner),
          value: 1,
          options: _options,
          semanticLabel: 'Topic notifications',
          onChanged: onChanged,
        ),
      ),
    ),
  ),
);
