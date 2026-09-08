import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all variants keep host sizes, leading, fonts and caller emphasis',
    (tester) async {
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
          scaler: const AppTextScaler(
            platformScaler: _NonlinearScaler(),
            appScale: 2,
          ),
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
        for (final (index, variant) in DTextVariant.values.indexed) {
          final paragraph = _paragraph(tester, variant.name);
          final style = paragraph.text.style!;
          final role = roles[index];
          expect(style.fontSize, role.fontSize, reason: variant.name);
          expect(style.height, role.height, reason: variant.name);
          expect(
            style.fontFamily,
            variant == DTextVariant.inlineCode
                ? 'JetBrains Mono'
                : role.fontFamily,
          );
          expect(
            paragraph.textScaler.scale(style.fontSize!),
            const _NonlinearScaler().scale(role.fontSize!) * 2,
          );
        }
        final emphasis = _paragraph(tester, 'Caller emphasis').text.style!;
        expect(emphasis.fontSize, text.titleLarge!.fontSize);
        expect(emphasis.color, Colors.orange);
        expect(emphasis.fontWeight, FontWeight.w400);
        expect(tester.takeException(), isNull);
      }
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
            DSpacing.xl,
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

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find
          .byWidgetPredicate(
            (widget) => widget is RichText && widget.text.toPlainText() == text,
          )
          .last,
    );

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + (fontSize < 20 ? 6 : 3);
  @override
  double get textScaleFactor => 1.25;
}
