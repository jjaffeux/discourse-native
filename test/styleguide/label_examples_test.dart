import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/label_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Label is registered with runnable documented compositions', () {
    expect(componentExamples['label'], same(labelExamples));
    expect(labelExamples.examples.map((example) => example.title), [
      'Control association and disabled state',
      'Rich labels and wrapping',
      'Label in a native form',
      'RTL labels',
    ]);
  });

  testWidgets('disabled control preserves checked state across live themes', (
    tester,
  ) async {
    final theme = ValueNotifier(AppTheme.light);
    addTearDown(theme.dispose);
    await _pump(tester, labelExamples.examples[0], theme: theme);
    await tester.tap(find.text('Accept terms and conditions'));
    await tester.tap(find.text('Enable terms control'));
    await tester.pump();
    expect(find.text('Terms accepted'), findsOneWidget);
    final checkbox = find.byKey(const ValueKey('label-terms'));
    expect(tester.widget<DCheckbox>(checkbox).onChanged, isNull);
    await tester.tap(
      find.text('Accept terms and conditions'),
      warnIfMissed: false,
    );
    theme.value = StyleguideTheme.plum.resolve(AppTheme.light);
    await tester.pumpAndSettle();
    expect(find.text('Terms accepted'), findsOneWidget);
    expect(tester.widget<DCheckbox>(checkbox).onChanged, isNull);
    await tester.tap(find.text('Enable terms control'));
    await tester.pump();
    await tester.tap(find.text('Accept terms and conditions'));
    await tester.pump();
    expect(find.text('Terms not accepted'), findsOneWidget);
  });

  testWidgets(
    'rich label and independent terms action both work without truncation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          labelExamples.examples[1],
          width: 216,
          textScale: 2,
        );
        final terms = find.text('Read example terms');
        expect(
          tester.renderObject<RenderParagraph>(terms).didExceedMaxLines,
          isFalse,
        );
        final checkbox = find.byType(DCheckbox);
        await tester.tap(find.byType(DLabel));
        await tester.pump();
        expect(tester.widget<DCheckbox>(checkbox).value, isTrue);
        await tester.ensureVisible(terms);
        await tester.tap(terms);
        await tester.pump();
        expect(find.textContaining('No email is sent'), findsOneWidget);
        expect(tester.widget<DCheckbox>(checkbox).value, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'native form keeps focus, required semantics, errors, save and reset',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(tester, labelExamples.examples[2]);
        await tester.tapAt(tester.getCenter(find.text('Your email address')));
        await tester.pump();
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.focusNode.hasFocus, isTrue);
        final fieldNode = tester.getSemantics(find.byType(EditableText));
        expect(
          fieldNode.getSemanticsData().flagsCollection.isRequired,
          Tristate.isTrue,
        );
        expect(fieldNode.label, contains('Your email address'));

        await tester.tap(find.text('Submit example'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter an email address containing @.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byType(TextFormField),
          'reader@example.test',
        );
        await tester.tap(find.text('Send me product updates'));
        await tester.tap(find.text('Submit example'));
        await tester.pumpAndSettle();
        expect(find.text('Enter an email address containing @.'), findsNothing);
        expect(find.text('Saved locally: reader@example.test'), findsOneWidget);
        await tester.tap(find.text('Reset form'));
        await tester.pumpAndSettle();
        expect(editable.controller.text, isEmpty);
        expect(tester.widget<DCheckbox>(find.byType(DCheckbox)).value, isFalse);
        expect(find.textContaining('Saved locally:'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Arabic and Hebrew labels toggle native leading controls in RTL',
    (tester) async {
      await _pump(tester, labelExamples.examples[3]);
      for (final (key, text) in [
        ('label-arabic', 'قبول الشروط والأحكام'),
        ('label-hebrew', 'קבל תנאים והגבלות'),
      ]) {
        final tile = find.byKey(ValueKey(key));
        final control = find.descendant(
          of: tile,
          matching: find.byType(AnimatedContainer),
        );
        expect(
          tester.getCenter(control).dx,
          greaterThan(tester.getCenter(find.text(text)).dx),
        );
        await tester.tap(find.text(text));
        await tester.pump();
        expect(tester.widget<DCheckbox>(tile).value, isTrue);
      }
    },
  );

  for (final example in labelExamples.examples) {
    testWidgets(
      '${example.title} stays readable at 200% in narrow and wide themes',
      (tester) async {
        final theme = ValueNotifier(AppTheme.light);
        addTearDown(theme.dispose);
        for (final width in [216.0, 720.0]) {
          await _pump(
            tester,
            example,
            width: width,
            textScale: 2,
            theme: theme,
          );
          for (final value in [
            AppTheme.light,
            AppTheme.dark,
            StyleguideTheme.forest.resolve(AppTheme.light),
            StyleguideTheme.plum.resolve(AppTheme.light),
          ]) {
            theme.value = value;
            await tester.pumpAndSettle();
            for (final richText
                in find
                    .descendant(
                      of: find.byType(DLabel),
                      matching: find.byType(RichText),
                    )
                    .evaluate()) {
              final paragraph = richText.renderObject! as RenderParagraph;
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '$width: ${paragraph.text.toPlainText()}',
              );
            }
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }

  testWidgets(
    'styleguide preview controls preserve Label state and reset clears it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const ComponentStyleguidePage(),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('styleguide-search')),
        'label',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('styleguide-component-label')),
      );
      await tester.pumpAndSettle();
      final terms = find.text('Accept terms and conditions');
      await tester.scrollUntilVisible(
        terms,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('styleguide-detail-label')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(terms);
      await tester.tap(terms);
      await tester.pump();
      await _choose(tester, 'Theme', 'Forest site');
      await _choose(tester, 'Viewport width', '360 px');
      await _choose(tester, 'Text scale', '200%');
      await tester.ensureVisible(find.text('Right to left'));
      await tester.tap(find.text('Right to left'));
      await tester.tap(find.text('Reduce motion'));
      await tester.pumpAndSettle();
      expect(find.text('Terms accepted'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('styleguide-reset')),
      );
      await tester.tap(find.byKey(const ValueKey('styleguide-reset')));
      await tester.pumpAndSettle();
      expect(find.text('Terms not accepted'), findsOneWidget);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  StyleguideExample example, {
  double width = 480,
  double textScale = 1,
  ValueNotifier<ThemeData>? theme,
}) async {
  await tester.pumpWidget(
    ValueListenableBuilder(
      valueListenable: theme ?? AlwaysStoppedAnimation(AppTheme.light),
      builder: (context, value, _) => MaterialApp(
        theme: value,
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  child: Builder(builder: example.builder),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label, String option) async {
  if (label == 'Text scale') {
    final settings = find.byKey(const ValueKey('styleguide-settings'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pump();
  }
  final dropdown = find.byKey(ValueKey('styleguide-$label'));
  await tester.scrollUntilVisible(
    dropdown,
    -200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('styleguide-detail-label')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}
