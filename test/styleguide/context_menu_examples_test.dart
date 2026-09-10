import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/context_menu_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Context Menu registers every frozen documentation example', () {
    expect(componentExamples['context-menu'], same(contextMenuExamples));
    expect(contextMenuExamples.status, ComponentStatus.implemented);
    expect(contextMenuExamples.examples.map((example) => example.title), [
      'Basic',
      'Submenu',
      'Shortcuts',
      'Groups',
      'Icons',
      'Checkboxes',
      'Radio',
      'Destructive',
      'Sides',
      'RTL',
      'Reference demo',
    ]);
  });

  testWidgets('examples mount at narrow 200 percent RTL in live palettes', (
    tester,
  ) async {
    for (final example in contextMenuExamples.examples) {
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
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: 216,
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets('Basic example invokes an action at the pointer', (tester) async {
    await _pumpExample(tester, 'Basic');
    await tester.tapAt(
      tester.getCenter(find.text('Right click or long press here')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Forward'), findsOneWidget);

    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(find.text('No action selected'), findsNothing);
    expect(find.text('Reload'), findsOneWidget);
  });

  testWidgets('Checkbox and Radio examples retain their menu while changing', (
    tester,
  ) async {
    await _pumpExample(tester, 'Checkboxes');
    await tester.tapAt(
      tester.getCenter(find.text('Right click or long press here')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Bookmarks Bar'));
    await tester.pumpAndSettle();
    expect(find.text('Show Developer Tools'), findsOneWidget);

    await _pumpExample(tester, 'Radio');
    await tester.tapAt(
      tester.getCenter(find.text('Right click or long press here')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colm Tuite'));
    await tester.pumpAndSettle();
    expect(find.text('System'), findsOneWidget);
  });
}

Future<void> _pumpExample(WidgetTester tester, String title) async {
  final example = contextMenuExamples.examples.firstWhere(
    (example) => example.title == title,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Center(child: Builder(builder: example.builder)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
