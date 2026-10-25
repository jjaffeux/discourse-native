import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/collapsible_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final example in collapsibleExamples.examples) {
    testWidgets('${example.title} renders at narrow RTL large text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
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
                    width: 240,
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('styled triggers use the reference focus treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: collapsibleExamples.examples
                .firstWhere((example) => example.title == 'Basic')
                .builder,
          ),
        ),
      ),
    );

    final outline = find
        .descendant(
          of: find.byType(DCollapsibleTrigger),
          matching: find.byType(CustomPaint),
        )
        .first;
    expect(outline, isNot(paints..rrect()));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    // The reference treatment: a one-pixel border inside the control and a
    // three-pixel ring at half the focus colour outside it.
    final ring = DTokens.of(tester.element(outline)).focusRing;
    final bounds = BorderRadius.circular(
      DTokens.of(tester.element(outline)).radius,
    ).toRRect(Offset.zero & tester.getSize(outline));
    expect(
      outline,
      paints
        ..rrect(rrect: bounds.deflate(.5), color: ring, strokeWidth: 1)
        ..drrect(
          outer: bounds.inflate(3),
          inner: bounds,
          color: ring.withValues(alpha: ring.a * .5),
        ),
    );
  });

  testWidgets('file tree uses the current 16rem reference width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: collapsibleExamples.examples
                  .firstWhere((example) => example.title == 'File Tree')
                  .builder,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(DCard)).width, 256);
  });

  testWidgets(
    'settings edits survive disclosure and nested tree retains opened folder',
    (tester) async {
      Future<void> show(String title) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: collapsibleExamples.examples
                    .firstWhere((e) => e.title == title)
                    .builder,
              ),
            ),
          ),
        ),
      );
      await show('Settings Panel');
      await tester.tap(find.bySemanticsLabel('More radius settings'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '17');
      await tester.tap(find.bySemanticsLabel('More radius settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('More radius settings'));
      await tester.pumpAndSettle();
      expect(find.text('17'), findsOneWidget);
      await show('File Tree');
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();
      expect(find.text('No symbols in the selected file.'), findsOneWidget);
      expect(find.text('components'), findsNothing);
      await tester.tap(find.text('Explorer'));
      await tester.pumpAndSettle();
      expect(find.text('No symbols in the selected file.'), findsNothing);
      await tester.tap(find.text('components'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ui'));
      await tester.pumpAndSettle();
      expect(find.text('button.tsx'), findsOneWidget);
      await tester.tap(find.text('components'));
      await tester.pumpAndSettle();
      expect(find.text('button.tsx'), findsNothing);
      await tester.tap(find.text('components'));
      await tester.pumpAndSettle();
      expect(find.text('button.tsx'), findsOneWidget);
    },
  );
}
