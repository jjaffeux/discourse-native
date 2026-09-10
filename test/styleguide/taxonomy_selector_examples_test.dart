import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/taxonomy_selector_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final variant in [
    (name: 'light narrow', theme: AppTheme.light, width: 320.0),
    (name: 'dark wide', theme: AppTheme.dark, width: 640.0),
  ]) {
    testWidgets(
      'category removal has one highlight during hover and keyboard navigation (${variant.name})',
      (tester) async {
        tester.view.physicalSize = Size(variant.width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final example = categorySelectorExamples.examples.singleWhere(
          (example) => example.title == 'Category removal',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: variant.theme.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: Center(child: Builder(builder: example.builder)),
            ),
          ),
        );
        await tester.tap(find.byType(DButton));
        await tester.pumpAndSettle();

        List<int> paintedHighlights() {
          final values = <int>[];
          for (final element in find.byType(DComboboxItem<int>).evaluate()) {
            final background = tester.widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byWidget(element.widget),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            );
            final color = (background.decoration as BoxDecoration).color;
            if (color != null && color.a > 0) {
              values.add((element.widget as DComboboxItem<int>).option.value);
            }
          }
          return values;
        }

        expect(paintedHighlights(), [1]);
        final removal = find.byKey(
          const ValueKey(('category-selector-option', 0)),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(removal));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(paintedHighlights(), [0]);

        // Keyboard navigation must replace hover even with a stationary mouse.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(paintedHighlights(), [1]);
        expect(
          tester
              .widget<TopicCategorySelector>(find.byType(TopicCategorySelector))
              .selected
              ?.id,
          1,
        );

        await mouse.moveTo(Offset.zero);
        await mouse.moveTo(tester.getCenter(removal));
        await tester.pump();
        await mouse.down(tester.getCenter(removal));
        await tester.pump(const Duration(milliseconds: 40));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(find.byType(DComboboxContent), findsNothing);
        expect(
          tester
              .widget<TopicCategorySelector>(find.byType(TopicCategorySelector))
              .selected,
          isNull,
        );
      },
    );
  }

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
        findsNWidgets(entry.id == 'category-selector' ? 5 : 3),
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
