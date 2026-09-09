import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/dropdown_menu_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dropdown Menu registers every frozen documented example', () {
    expect(componentExamples['dropdown-menu'], same(dropdownMenuExamples));
    expect(dropdownMenuExamples.status, ComponentStatus.implemented);
    expect(dropdownMenuExamples.examples.map((example) => example.title), [
      'Composition',
      'Basic',
      'Submenu',
      'Shortcuts',
      'Icons',
      'Checkboxes',
      'Checkboxes Icons',
      'Radio Group',
      'Radio Icons',
      'Destructive',
      'Avatar',
      'Complex',
      'RTL',
    ]);
  });

  testWidgets('every example mounts in narrow large-text live palettes', (
    tester,
  ) async {
    for (final example in dropdownMenuExamples.examples) {
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
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 240,
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets(
    'checkbox, radio, and complex examples expose live interactions',
    (tester) async {
      Future<void> show(String title) async {
        final example = dropdownMenuExamples.examples.firstWhere(
          (example) => example.title == title,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(child: Builder(builder: example.builder)),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show('Checkboxes');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panel'));
      await tester.pump();
      expect(find.text('Panel'), findsOneWidget);

      await show('Radio Group');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Top'));
      await tester.pump();
      expect(find.text('Top'), findsOneWidget);

      await show('Complex');
      await tester.tap(find.text('Complex Menu'));
      await tester.pumpAndSettle();
      expect(find.text('New File'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    },
  );
}
