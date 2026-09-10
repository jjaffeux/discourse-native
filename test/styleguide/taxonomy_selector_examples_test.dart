import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/taxonomy_selector_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in [
    (
      id: 'category-selector',
      name: 'Category selector',
      type: TopicCategorySelector,
    ),
    (id: 'tag-selector', name: 'Tag selector', type: TopicTagSelector),
  ]) {
    testWidgets('styleguide search opens the real ${entry.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: const ComponentStyleguidePage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('styleguide-search')),
          matching: find.byType(TextField),
        ),
        entry.name,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('styleguide-component-${entry.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(entry.type),
        findsNWidgets(entry.id == 'category-selector' ? 4 : 3),
      );
      final trigger = find.descendant(
        of: find.byType(entry.type).first,
        matching: find.byType(DButton),
      );
      await tester.ensureVisible(trigger);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxContent), findsOneWidget);
      final option = entry.id == 'category-selector'
          ? const ValueKey(('category-selector-option', 2))
          : const ValueKey(('tag-selector-option', 'design'));
      await tester.tap(find.byKey(option));
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxContent), findsNothing);
      expect(
        find.descendant(
          of: find.byType(entry.type).first,
          matching: find.text(
            entry.id == 'category-selector' ? 'Support' : 'design',
          ),
        ),
        findsOneWidget,
      );
    });
  }

  for (final examples in [categorySelectorExamples, tagSelectorExamples]) {
    testWidgets('${examples.description} stays usable at 320px and 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Builder(builder: examples.examples[1].builder),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controls = find.byType(DButton);
      for (var index = 0; index < controls.evaluate().length; index++) {
        await tester.tap(controls.at(index));
        await tester.pumpAndSettle();
        final popup = tester.getRect(find.byType(DComboboxContent));
        expect(popup.left, greaterThanOrEqualTo(0));
        expect(popup.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        // Move focus off the restored trigger before testing the next control.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
    });
  }
}
