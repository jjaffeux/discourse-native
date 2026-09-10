import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/dropdown_menu_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  for (final brightness in Brightness.values) {
    testWidgets(
      'Composition keeps stale focus hidden between hovered rows in $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? AppTheme.dark
                : AppTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: Builder(
                  builder: dropdownMenuExamples.examples.first.builder,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(find.text('My Account')));
        await tester.pump();
        expect(_rowColor(tester, 'Profile'), Colors.transparent);
        await mouse.moveTo(tester.getCenter(find.text('Invite users')));
        await tester.pumpAndSettle();
        expect(find.text('Email'), findsOneWidget);

        await mouse.moveTo(tester.getCenter(find.text('New Team')));
        await tester.pumpAndSettle();
        expect(find.text('Email'), findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          contains('Invite users'),
        );
        expect(_rowColor(tester, 'New Team'), isNot(Colors.transparent));
        expect(_rowColor(tester, 'Invite users'), Colors.transparent);

        await mouse.moveTo(
          tester.getCenter(find.byType(DDropdownMenuSeparator).at(1)),
        );
        await tester.pumpAndSettle();
        expect(_rowColor(tester, 'Invite users'), Colors.transparent);
        expect(_rowColor(tester, 'New Team'), Colors.transparent);
        expect(_rowColor(tester, 'GitHub'), Colors.transparent);

        await mouse.moveTo(tester.getCenter(find.text('GitHub')));
        await tester.pump();
        expect(_rowColor(tester, 'GitHub'), isNot(Colors.transparent));
        expect(_rowColor(tester, 'Invite users'), Colors.transparent);

        final popup = tester.getRect(find.byType(DDropdownMenuContent));
        for (final position in [
          tester.getCenter(find.text('API')),
          tester.getCenter(find.text('My Account')),
          Offset(popup.left + 2, popup.center.dy),
          Offset.zero,
        ]) {
          await mouse.moveTo(position);
          await tester.pump();
          expect(_rowColor(tester, 'Invite users'), Colors.transparent);
          expect(_rowColor(tester, 'GitHub'), Colors.transparent);
        }

        await mouse.moveTo(tester.getCenter(find.text('Invite users')));
        await tester.pumpAndSettle();
        await mouse.moveTo(tester.getCenter(find.text('Message')));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Message'), findsNothing);
        expect(_rowColor(tester, 'Invite users'), isNot(Colors.transparent));
      },
    );
  }

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

Color _rowColor(WidgetTester tester, String label) {
  final row = tester.widget<Container>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        )
        .first,
  );
  return (row.decoration! as BoxDecoration).color!;
}
