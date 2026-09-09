import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'reference metrics keep host fonts, native scaling and caller emphasis',
    (tester) async {
      const scaler = AppTextScaler(
        platformScaler: _NonlinearScaler(),
        appScale: 2,
      );
      final base = AppTheme.light;
      final custom = base.copyWith(
        textTheme: base.textTheme.apply(
          fontFamily: 'Host font',
          fontSizeFactor: 1.1,
        ),
      );
      for (final theme in [
        ThemeData(),
        AppTheme.light,
        AppTheme.dark,
        custom,
      ]) {
        await _pump(
          tester,
          DProse(
            children: [
              for (final variant in DTextVariant.values)
                DText(variant.name, variant: variant),
              const DText(
                'Caller emphasis',
                variant: DTextVariant.h4,
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          theme: theme,
          scaler: scaler,
        );
        final text = Theme.of(
          tester.element(find.byType(DProse).first),
        ).textTheme;
        final roles = [
          text.headlineLarge!,
          text.headlineMedium!,
          text.headlineSmall!,
          text.titleLarge!,
          text.bodyLarge!,
          text.titleLarge!,
          text.titleMedium!,
          text.labelLarge!,
          text.bodyMedium!,
          text.bodyMedium!,
        ];
        // Frozen shadcn Typography utilities, converted from a 16px root rem.
        // tracking-tight is -0.025em of the rendered size.
        const metrics = [
          (36.0, 40.0, FontWeight.w800, true),
          (30.0, 36.0, FontWeight.w600, true),
          (24.0, 32.0, FontWeight.w600, true),
          (20.0, 28.0, FontWeight.w600, true),
          (16.0, 28.0, FontWeight.w400, false),
          (20.0, 28.0, FontWeight.w400, false),
          (18.0, 28.0, FontWeight.w600, false),
          (14.0, 14.0, FontWeight.w500, false),
          (14.0, 20.0, FontWeight.w400, false),
          (14.0, 20.0, FontWeight.w600, false),
        ];
        for (final (index, variant) in DTextVariant.values.indexed) {
          final paragraph = _paragraph(tester, variant.name);
          final style = paragraph.text.style!;
          final role = roles[index];
          final (size, leading, weight, tight) = metrics[index];
          expect(style.fontSize, size, reason: variant.name);
          expect(style.height, leading / size, reason: variant.name);
          expect(style.fontWeight, weight, reason: variant.name);
          expect(
            style.letterSpacing,
            closeTo(tight ? -0.025 * scaler.scale(size) : 0, 0.00001),
            reason: variant.name,
          );
          expect(
            style.fontFamily,
            variant == DTextVariant.inlineCode
                ? 'JetBrains Mono'
                : role.fontFamily,
          );
          expect(
            paragraph.textScaler.scale(style.fontSize!),
            const _NonlinearScaler().scale(size) * 2,
          );
        }
        final emphasis = _paragraph(tester, 'Caller emphasis').text.style!;
        expect(emphasis.fontSize, 20);
        expect(emphasis.color, Colors.orange);
        expect(emphasis.fontWeight, FontWeight.w400);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('heading tracking follows the inherited text scaler', (
    tester,
  ) async {
    for (final scaler in [
      TextScaler.noScaling,
      const TextScaler.linear(2),
      const _NonlinearScaler(),
    ]) {
      await _pump(
        tester,
        Builder(
          builder: (context) => DProse(
            children: [
              const DText('Heading', variant: DTextVariant.h1),
              DText.rich(
                TextSpan(
                  text: 'Span',
                  style: DText.styleOf(context, DTextVariant.h4),
                ),
              ),
              const DText('Body'),
            ],
          ),
        ),
        scaler: scaler,
      );
      expect(
        _paragraph(tester, 'Heading').text.style!.letterSpacing,
        closeTo(-0.025 * scaler.scale(36), 0.000001),
        reason: '$scaler',
      );
      final span =
          (_paragraph(tester, 'Span').text as TextSpan).children!.single;
      expect(
        span.style!.letterSpacing,
        closeTo(-0.025 * scaler.scale(20), 0.000001),
        reason: '$scaler',
      );
      expect(_paragraph(tester, 'Body').text.style!.letterSpacing, 0);
    }
  });

  testWidgets(
    'standalone code keeps fixed 4px corners and paints one translucent background',
    (tester) async {
      const muted = Color(0x3300AA00);
      final theme = AppTheme.light;
      await _pump(
        tester,
        Builder(
          builder: (context) => DProse(
            children: [
              const DText('alone', variant: DTextVariant.inlineCode),
              DText.rich(
                TextSpan(
                  text: 'span',
                  style: DText.styleOf(context, DTextVariant.inlineCode),
                ),
              ),
            ],
          ),
        ),
        theme: theme.copyWith(
          extensions: [
            theme.extension<DTokens>()!.copyWith(radius: 10, muted: muted),
          ],
        ),
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.widgetWithText(DText, 'alone'),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(4));
      expect(decoration.color, muted);
      expect(_paragraph(tester, 'alone').text.style!.backgroundColor, isNull);
      final span =
          (_paragraph(tester, 'span').text as TextSpan).children!.single;
      expect(span.style!.backgroundColor, muted);
      expect(span.style!.fontFamily, 'JetBrains Mono');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'link style inherits the enclosing text and a recognizer exposes link semantics',
    (tester) async {
      final handle = tester.ensureSemantics();
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      var taps = 0;
      recognizer.onTap = () => taps++;
      try {
        await _pump(
          tester,
          Builder(
            builder: (context) => DProse(
              children: [
                DText.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Read '),
                      TextSpan(
                        text: 'the plan',
                        style: DText.linkStyleOf(context),
                        recognizer: recognizer,
                      ),
                      const TextSpan(text: ' now.'),
                    ],
                  ),
                  variant: DTextVariant.lead,
                ),
              ],
            ),
          ),
        );
        final tokens = DTokens.of(tester.element(find.byType(DProse)));
        final paragraph = _paragraph(tester, 'Read the plan now.');
        TextSpan? link;
        paragraph.text.visitChildren((span) {
          if (span is TextSpan && span.text == 'the plan') link = span;
          return link == null;
        });
        final style = link!.style!;
        expect(style.fontSize, isNull);
        expect(style.height, isNull);
        expect(style.fontWeight, FontWeight.w500);
        expect(style.color, tokens.primary);
        expect(style.decoration, TextDecoration.underline);
        expect(style.decorationColor, tokens.primary);
        final linkBox = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 5, extentOffset: 13),
            )
            .single
            .toRect();
        final textBox = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 4),
            )
            .single
            .toRect();
        expect(linkBox.height, textBox.height);
        final node = _semanticsWithLabel(
          tester,
          'Read the plan now.',
          'the plan',
        );
        expect(node.getSemanticsData().flagsCollection.isLink, isTrue);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        expect(taps, 1);
        await tester.tapAt(paragraph.localToGlobal(linkBox.center));
        await tester.pump();
        expect(taps, 2);
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'balanced heading yields to an inherited line limit and bold text',
    (tester) async {
      const words = 'Taxing Laughter: The Joke Tax Chronicles';
      await _pump(
        tester,
        const DefaultTextStyle(
          style: TextStyle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: DProse(children: [DText(words, variant: DTextVariant.h1)]),
        ),
        width: 400,
      );
      final limited = _paragraph(tester, words);
      expect(limited.didExceedMaxLines, isTrue);
      expect(limited.size.width, 400);

      await _pump(
        tester,
        const MediaQuery(
          data: MediaQueryData(boldText: true),
          child: DProse(
            children: [
              DText(words, variant: DTextVariant.h1),
              DText.rich(TextSpan(text: words), variant: DTextVariant.h1),
            ],
          ),
        ),
        width: 400,
      );
      final bold = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .where((value) => value.text.toPlainText() == words)
          .toList();
      expect(bold[0].text.style!.fontWeight, FontWeight.bold);
      expect(bold[0].size.height, bold[1].size.height);
      expect(bold[0].didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plain h1 balances lines without changing content or line count',
    (tester) async {
      const words = 'Taxing Laughter: The Joke Tax Chronicles';
      await _pump(
        tester,
        const DProse(
          children: [
            DText(words, variant: DTextVariant.h1),
            DText.rich(TextSpan(text: words), variant: DTextVariant.h1),
          ],
        ),
        width: 640,
      );
      final paragraphs = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .where((value) => value.text.toPlainText() == words)
          .toList();
      final balanced = paragraphs[0];
      final natural = paragraphs[1];
      const selection = TextSelection(
        baseOffset: 0,
        extentOffset: words.length,
      );
      expect(balanced.size.width, lessThan(natural.size.width));
      expect(
        balanced.getBoxesForSelection(selection).length,
        natural.getBoxesForSelection(selection).length,
      );
      expect(balanced.size.height, natural.size.height);
      expect(balanced.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);

      // Large text with a word wider than the viewport must retain all of the
      // available measure rather than introducing more breaks within words.
      await _pump(
        tester,
        const DProse(
          children: [
            DText(words, variant: DTextVariant.h1),
            DText.rich(TextSpan(text: words), variant: DTextVariant.h1),
          ],
        ),
        width: 360,
        scaler: const TextScaler.linear(2),
      );
      final large = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .where((value) => value.text.toPlainText() == words)
          .toList();
      expect(large[0].size, large[1].size);
      expect(large[0].didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('headings announce levels and explicit semantics overrides', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        const DProse(
          children: [
            DText('One', variant: DTextVariant.h1),
            DText('Two', variant: DTextVariant.h2),
            DText.rich(TextSpan(text: 'Three'), variant: DTextVariant.h3),
            DText('Four', variant: DTextVariant.h4),
            DText(
              'Compact section',
              variant: DTextVariant.large,
              headingLevel: 2,
            ),
            DText('Visual only', variant: DTextVariant.h1, headingLevel: 0),
            DText('abbr', semanticsLabel: 'Expanded label'),
          ],
        ),
      );
      for (final (index, text) in ['One', 'Two', 'Three', 'Four'].indexed) {
        expect(
          tester.getSemantics(find.text(text)).getSemanticsData().headingLevel,
          index + 1,
        );
      }
      expect(
        tester
            .getSemantics(find.text('Compact section'))
            .getSemanticsData()
            .headingLevel,
        2,
      );
      expect(
        tester
            .getSemantics(find.text('Visual only'))
            .getSemanticsData()
            .headingLevel,
        0,
      );
      expect(find.bySemanticsLabel('Expanded label'), findsOneWidget);
      expect(find.bySemanticsLabel('abbr'), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets(
    'quote and list follow live direction with native list semantics',
    (tester) async {
      final handle = tester.ensureSemantics();
      final direction = ValueNotifier(TextDirection.ltr);
      try {
        addTearDown(direction.dispose);
        await _pump(
          tester,
          ValueListenableBuilder(
            valueListenable: direction,
            builder: (_, value, child) =>
                DDirection(textDirection: value, child: child!),
            child: const DProse(
              children: [
                DBlockquote(
                  key: ValueKey('quote'),
                  child: Text('A wrapping quotation.'),
                ),
                DTextList(
                  ordered: true,
                  start: 9,
                  children: [Text('First item'), Text('Second item')],
                ),
                DTextList(children: [Text('Bulleted item')]),
              ],
            ),
          ),
          width: 320,
          scaler: const TextScaler.linear(2),
        );
        for (final value in TextDirection.values) {
          direction.value = value;
          await tester.pump();
          final quote = tester.getRect(find.byKey(const ValueKey('quote')));
          final words = tester.getRect(find.text('A wrapping quotation.'));
          expect(
            value == TextDirection.ltr
                ? words.left - quote.left
                : quote.right - words.right,
            DSpacing.xl + 2,
          );
          expect(
            _paragraph(tester, 'A wrapping quotation.').text.style!.fontStyle,
            FontStyle.italic,
          );
          final marker = tester.getRect(find.text('9.'));
          final item = tester.getRect(find.text('First item'));
          expect(
            value == TextDirection.ltr
                ? marker.right < item.left
                : marker.left > item.right,
            isTrue,
          );
          expect(find.text('10.'), findsOneWidget);
          final semantics = tester
              .getSemantics(find.text('First item'))
              .getSemanticsData();
          expect(semantics.role, SemanticsRole.listItem);
          expect(find.bySemanticsLabel('•'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'empty flows have no height and nested lists retain all content',
    (tester) async {
      await _pump(
        tester,
        const DProse(
          spacing: DSpacing.sm,
          children: [
            DProse(key: ValueKey('empty-prose'), children: []),
            DTextList(key: ValueKey('empty-list'), children: []),
            DTextList(
              ordered: true,
              start: 99,
              children: [
                DProse(
                  spacing: DSpacing.sm,
                  children: [
                    Text('Parent item with enough text to wrap.'),
                    DTextList(
                      children: [Text('Nested item with enough text to wrap.')],
                    ),
                  ],
                ),
                Text('Last item'),
              ],
            ),
          ],
        ),
        width: 320,
        scaler: const TextScaler.linear(2),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('empty-prose'))).height,
        0,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('empty-list'))).height,
        0,
      );
      expect(find.text('100.'), findsOneWidget);
      expect(
        _paragraph(
          tester,
          'Nested item with enough text to wrap.',
        ).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wrapping and explicit truncation preserve the complete semantic text',
    (tester) async {
      const long = 'LongUnbrokenCommunityConfigurationIdentifier0123456789';
      await _pump(
        tester,
        const DProse(
          children: [
            DText(long, variant: DTextVariant.inlineCode),
            DText(
              'tiny',
              variant: DTextVariant.inlineCode,
              textAlign: TextAlign.end,
            ),
            DText(
              'A deliberately long preview which must be truncated.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            DText('No wrap', softWrap: false, textAlign: TextAlign.end),
            DText(''),
          ],
        ),
        width: 200,
        scaler: const TextScaler.linear(2),
      );
      final codeBox = tester.getRect(
        find.descendant(
          of: find.widgetWithText(DText, 'tiny'),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(codeBox.width, lessThan(200));
      expect(
        codeBox.right,
        tester.getRect(find.widgetWithText(DText, 'tiny')).right,
      );
      final code = _paragraph(tester, long);
      expect(
        code.size.height,
        greaterThan(
          code.textScaler.scale(code.text.style!.fontSize!) *
              code.text.style!.height!,
        ),
      );
      expect(code.didExceedMaxLines, isFalse);
      final truncated = _paragraph(
        tester,
        'A deliberately long preview which must be truncated.',
      );
      expect(truncated.didExceedMaxLines, isTrue);
      expect(truncated.overflow, TextOverflow.ellipsis);
      expect(_paragraph(tester, 'No wrap').softWrap, isFalse);
      expect(_paragraph(tester, 'No wrap').textAlign, TextAlign.end);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
    testWidgets(
      'native selection copies rich code and lists on ${platform.name}',
      (tester) async {
        String? selected;
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await _pump(
          tester,
          SelectionArea(
            onSelectionChanged: (content) => selected = content?.plainText,
            child: Builder(
              builder: (context) => DProse(
                children: [
                  const DText('Welcome', variant: DTextVariant.h3),
                  DText.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Run '),
                        TextSpan(
                          text: 'flutter test',
                          style: DText.styleOf(
                            context,
                            DTextVariant.inlineCode,
                          ),
                        ),
                        const TextSpan(text: ' locally.'),
                      ],
                    ),
                  ),
                  const DTextList(
                    children: [Text('First item'), Text('Second item')],
                  ),
                ],
              ),
            ),
          ),
          theme: AppTheme.light.copyWith(platform: platform),
        );
        await tester.tap(find.text('Run flutter test locally.'));
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
        expect(selected, contains('Welcome'));
        expect(selected, contains('Run flutter test locally.'));
        expect(selected, contains('First item'));
        expect(selected, contains('Second item'));
        expect(selected, isNot(contains('•')));
        expect(copied, selected);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double width = 640,
  TextScaler scaler = TextScaler.noScaling,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  ),
);

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

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + (fontSize < 20 ? 6 : 3);
  @override
  double get textScaleFactor => 1.25;
}
