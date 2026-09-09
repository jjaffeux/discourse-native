import 'dart:ui' show CheckedState;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/menubar_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Menubar registers every frozen documented example', () {
    expect(componentExamples['menubar'], same(menubarExamples));
    expect(menubarExamples.status, ComponentStatus.baseline);
    expect(menubarExamples.examples.map((example) => example.title), [
      'Composition',
      'Checkbox',
      'Radio',
      'Submenu',
      'With Icons',
      'RTL',
    ]);
  });

  testWidgets('all examples mount in live palettes at narrow 200 percent RTL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final example in menubarExamples.examples) {
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        StyleguideTheme.plum.resolve(AppTheme.light),
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

  testWidgets('composition example opens and updates checkbox and radio', (
    tester,
  ) async {
    final example = menubarExamples.examples.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmarks Bar'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmarks Bar'), findsOneWidget);

    await tester.tapAt(const Offset(340, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Andy'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Andy')).flagsCollection.isChecked,
      CheckedState.isTrue,
    );
  });

  testWidgets('composition reveals a focused trigger at narrow 200 percent', (
    tester,
  ) async {
    final example = menubarExamples.examples.first;
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Builder(builder: example.builder),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(DMenubar));
    final lastTrigger = tester.getRect(find.text('Profiles'));
    expect(lastTrigger.left, greaterThanOrEqualTo(bar.left + 4));
    expect(lastTrigger.right, lessThanOrEqualTo(bar.right - 4));
  });

  testWidgets('icon example exposes the destructive command', (tester) async {
    final example = menubarExamples.examples.firstWhere(
      (example) => example.title == 'With Icons',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(MenubarReferenceIcon), findsNWidgets(3));
  });
}
