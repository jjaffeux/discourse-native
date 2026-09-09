import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/typography_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [
    StyleguideTheme.light,
    StyleguideTheme.dark,
    StyleguideTheme.forest,
    StyleguideTheme.plum,
  ]) {
    testWidgets(
      'every frozen example wraps at narrow and wide 200% in ${theme.name}',
      (tester) async {
        for (final width in [320.0, 960.0]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          for (final direction in TextDirection.values) {
            for (final example in typographyExamples.examples) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme.resolve(AppTheme.light),
                  home: Scaffold(
                    body: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(2),
                        disableAnimations: true,
                      ),
                      child: DDirection(
                        textDirection: direction,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(DSpacing.lg),
                          child: Builder(builder: example.builder),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump();
              expect(
                tester.takeException(),
                isNull,
                reason: '${example.title}, $width, $direction',
              );
              for (final paragraph in tester.renderObjectList<RenderParagraph>(
                find.byType(RichText),
              )) {
                if (paragraph.maxLines == 1) {
                  continue; // Intentional ellipsis example.
                }
                expect(
                  paragraph.didExceedMaxLines,
                  isFalse,
                  reason: '${example.title}: ${paragraph.text.toPlainText()}',
                );
              }
            }
          }
        }
      },
    );
  }

  testWidgets(
    'rich action keeps keyboard focus and state through live preview changes',
    (tester) async {
      final theme = ValueNotifier(AppTheme.light);
      final rtl = ValueNotifier(false);
      addTearDown(theme.dispose);
      addTearDown(rtl.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: theme,
              builder: (_, value, child) => Theme(data: value, child: child!),
              child: ValueListenableBuilder(
                valueListenable: rtl,
                builder: (_, value, child) => DDirection(
                  textDirection: value ? TextDirection.rtl : TextDirection.ltr,
                  child: child!,
                ),
                child: SingleChildScrollView(
                  child: Builder(
                    builder: _example(
                      'Inline code, rich text and keyboard actions',
                    ).builder,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // The selection area also participates in traversal; Tab reaches the native action.
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (Focus.of(tester.element(find.text('Show details'))).hasFocus) break;
      }
      expect(
        Focus.of(tester.element(find.text('Show details'))).hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        find.text('Welcome messages can include a friendly introduction.'),
        findsOneWidget,
      );
      final focus = FocusManager.instance.primaryFocus;
      theme.value = StyleguideTheme.plum.resolve(AppTheme.light);
      rtl.value = true;
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(find.text('Hide details'), findsOneWidget);
      final codeBox =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.widgetWithText(DText, 'community_guidelines'),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(
        codeBox.color,
        DTokens.of(tester.element(find.text('community_guidelines'))).muted,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('Details are hidden.'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNot(same(focus)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native table has column semantics, alignment and live token borders',
    (tester) async {
      final handle = tester.ensureSemantics();
      final theme = ValueNotifier(AppTheme.light);
      try {
        addTearDown(theme.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: theme,
                builder: (_, value, child) => Theme(data: value, child: child!),
                child: Builder(
                  builder: _example(
                    'Table composition and column alignment',
                  ).builder,
                ),
              ),
            ),
          ),
        );
        expect(
          tester
              .getSemantics(find.text("King's Treasury"))
              .getSemanticsData()
              .role,
          SemanticsRole.columnHeader,
        );
        expect(
          tester.getSemantics(find.text('Empty')).getSemanticsData().role,
          SemanticsRole.cell,
        );
        expect(
          tester.widget<Text>(find.text("King's Treasury")).textAlign,
          TextAlign.start,
        );
        expect(
          tester.widget<Text>(find.text('Overflowing')).textAlign,
          TextAlign.center,
        );
        expect(
          tester.widget<Text>(find.text('Satisfied')).textAlign,
          TextAlign.end,
        );
        theme.value = StyleguideTheme.forest.resolve(AppTheme.light);
        await tester.pump();
        final tokens = DTokens.of(tester.element(find.byType(Table)));
        expect(
          tester.widget<Table>(find.byType(Table)).border!.top.color,
          tokens.border,
        );
        expect(
          (tester.widget<Table>(find.byType(Table)).children[2].decoration!
                  as BoxDecoration)
              .color,
          tokens.muted,
        );
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('reference demo link follows a tap and exposes link semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: _example('Shadcn reference demo').builder,
              ),
            ),
          ),
        ),
      );
      const sentence =
          'The king thought long and hard, and finally came up with '
          'a brilliant plan: he would tax the jokes in the kingdom.';
      final paragraph = _paragraph(tester, sentence);
      final start = sentence.indexOf('a brilliant plan');
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: start,
              extentOffset: start + 'a brilliant plan'.length,
            ),
          )
          .first
          .toRect();
      final node = _semanticsWithLabel(tester, sentence, 'a brilliant plan');
      expect(node.getSemanticsData().flagsCollection.isLink, isTrue);
      expect(find.text('Link followed: a brilliant plan'), findsNothing);
      await tester.tapAt(paragraph.localToGlobal(box.center));
      await tester.pump();
      expect(find.text('Link followed: a brilliant plan'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.text('Link followed: a brilliant plan'))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'RTL reference switches language and document direction from Arabic',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(builder: _example('Shadcn RTL reference').builder),
            ),
          ),
        ),
      );
      TextDirection directionOf(String text) =>
          Directionality.of(tester.element(find.text(text)));
      const arabic = 'فرض الضرائب على الضحك: سجلات ضريبة النكتة';
      const english = 'Taxing Laughter: The Joke Tax Chronicles';
      const hebrew = 'מיסוי הצחוק: כרוניקות מס הבדיחה';
      expect(directionOf(arabic), TextDirection.rtl);
      expect(directionOf('English'), TextDirection.ltr);
      expect(find.text('خزينة الملك'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text(arabic), findsNothing);
      expect(directionOf(english), TextDirection.ltr);
      expect(find.text("King's Treasury"), findsOneWidget);
      await tester.tap(find.text('עברית'));
      await tester.pumpAndSettle();
      expect(directionOf(hebrew), TextDirection.rtl);
      expect(find.text('אוצר המלך'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

StyleguideExample _example(String title) => typographyExamples.examples
    .singleWhere((example) => example.title == title);

/// The inline span node with [label] beneath the paragraph showing [text].
SemanticsNode _semanticsWithLabel(
  WidgetTester tester,
  String text,
  String label,
) {
  SemanticsNode? found;
  void visit(SemanticsNode node) {
    if (node.label == label) found = node;
    node.visitChildren((child) {
      visit(child);
      return found == null;
    });
  }

  visit(tester.getSemantics(_richText(text)));
  return found!;
}

Finder _richText(String text) => find
    .byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    )
    .last;

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(_richText(text));
