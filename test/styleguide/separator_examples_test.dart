import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/separator_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Usage reproduces the reference column and its controls change the line',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
      try {
        await _pump(tester, separatorExamples.examples[0], theme: theme);
        final separator = find.byKey(const ValueKey('separator-configurable'));
        final title = tester.getRect(find.text('shadcn/ui'));
        final subtitle = tester.getRect(
          find.text('The Foundation for your Design System'),
        );
        final description = tester.getRect(
          find.textContaining('A set of beautifully designed components'),
        );
        expect(tester.getSize(separator), const Size(384, 1));
        expect(tester.getSize(_line(separator)), const Size(384, 1));
        expect(title.height, 14);
        expect(subtitle.top - title.bottom, 6);
        expect(tester.getRect(separator).top - subtitle.bottom, 16);
        expect(description.top - tester.getRect(separator).bottom, 16);
        expect(description.width, 384);
        final tokens = DTokens.of(tester.element(separator));
        for (final (text, color) in [
          ('shadcn/ui', tokens.foreground),
          ('The Foundation for your Design System', tokens.mutedForeground),
          ('A set of beautifully designed components', tokens.foreground),
        ]) {
          final style = tester.widget<Text>(find.textContaining(text)).style!;
          expect(style.fontSize, 14, reason: text);
          expect(style.height, text == 'shadcn/ui' ? 1 : 20 / 14, reason: text);
          expect(
            style.fontWeight,
            text == 'shadcn/ui' ? FontWeight.w500 : FontWeight.w400,
            reason: text,
          );
          expect(style.color, color, reason: text);
        }
        expect(tester.widget<DSeparator>(separator).decorative, isTrue);
        expect(find.bySemanticsLabel('End of introduction'), findsNothing);

        await tester.tap(find.text('Meaningful boundary'));
        await tester.tap(find.text('Asymmetric insets'));
        await tester.tap(find.text('Emphasize boundary'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('End of introduction'), findsOneWidget);
        final line = tester.getRect(_line(separator));
        final outer = tester.getRect(separator);
        expect(outer.height, 3);
        expect(line.height, 3);
        expect(line.left - outer.left, 24);
        expect(outer.right - line.right, 8);

        theme.value = AppTheme.dark;
        await tester.pumpAndSettle();
        expect(tester.widget<DSeparator>(separator).decorative, isFalse);
        expect(tester.getRect(_line(separator)).height, 3);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('Vertical lines fill the 20px row and grow with large text', (
    tester,
  ) async {
    await _pump(tester, separatorExamples.examples[1]);
    final row = find.byKey(const ValueKey('separator-vertical-row'));
    expect(tester.getSize(row).height, 20);
    final lines = find.byType(DSeparator);
    expect(lines, findsNWidgets(2));
    for (final line in lines.evaluate().map((e) => find.byWidget(e.widget))) {
      expect(tester.getSize(line), const Size(1, 20));
      expect(tester.getRect(_line(line)).top, tester.getRect(row).top);
    }
    expect(
      tester.getRect(lines.first).left -
          tester.getRect(find.text('Blog')).right,
      16,
    );
    expect(
      tester.getRect(find.text('Docs')).left -
          tester.getRect(lines.first).right,
      16,
    );

    await _pump(tester, separatorExamples.examples[1], textScale: 2);
    final scaledRow = tester.getSize(row);
    expect(scaledRow.height, greaterThanOrEqualTo(40));
    expect(
      tester.getSize(find.byType(DSeparator).first).height,
      scaledRow.height,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Menu hides Help below the 768px breakpoint and fills the intrinsic row',
    (tester) async {
      for (final width in [320.0, 768.0, 1024.0]) {
        await _pump(tester, separatorExamples.examples[2], width: width);
        final wide = width >= 768;
        final row = find.byKey(const ValueKey('separator-menu-row'));
        final lines = find.byType(DSeparator);
        expect(find.text('Help'), wide ? findsOneWidget : findsNothing);
        expect(
          find.text('Support & docs'),
          wide ? findsOneWidget : findsNothing,
        );
        expect(lines, findsNWidgets(wide ? 2 : 1));
        final rowRect = tester.getRect(row);
        final settings = tester.getRect(find.text('Settings'));
        final manage = tester.getRect(find.text('Manage preferences'));
        expect(settings.height, 20);
        expect(manage.top - settings.bottom, 4);
        // The test font wraps the description inside its narrow flex share;
        // the row and every line still fit the tallest item exactly.
        expect(manage.height, wide ? 16 : 32);
        expect(rowRect.height, settings.height + 4 + manage.height);
        for (final line in lines.evaluate().map(
          (e) => find.byWidget(e.widget),
        )) {
          expect(tester.getSize(line), Size(1, rowRect.height));
          expect(tester.getRect(_line(line)).top, rowRect.top);
        }
        expect(
          tester.getRect(lines.first).left - manage.right,
          wide ? 16 : 8,
          reason: 'gap at $width',
        );
        expect(
          tester.getRect(find.text('Account')).left -
              tester.getRect(lines.first).right,
          wide ? 16 : 8,
          reason: 'gap at $width',
        );
      }

      await _pump(
        tester,
        separatorExamples.examples[2],
        width: 320,
        textScale: 2,
      );
      final row = tester.getRect(
        find.byKey(const ValueKey('separator-menu-row')),
      );
      expect(row.width, lessThanOrEqualTo(320));
      expect(tester.getSize(find.byType(DSeparator)).height, row.height);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('List separates three 20px rows with 8px gaps', (tester) async {
    await _pump(tester, separatorExamples.examples[3]);
    final lines = find.byType(DSeparator);
    expect(lines, findsNWidgets(2));
    final rows = [
      for (var i = 1; i <= 3; i++)
        tester.getRect(find.byKey(ValueKey('separator-list-row-$i'))),
    ];
    for (final row in rows) {
      expect(row.width, 384);
      expect(row.height, 20);
    }
    expect(tester.getRect(find.text('Item 1')).left, rows[0].left);
    expect(tester.getRect(find.text('Value 1')).right, rows[0].right);
    final first = tester.getRect(lines.first);
    final second = tester.getRect(lines.last);
    expect(first.size, const Size(384, 1));
    expect(first.top - rows[0].bottom, 8);
    expect(rows[1].top - first.bottom, 8);
    expect(second.top - rows[1].bottom, 8);
    expect(rows[2].top - second.bottom, 8);
  });

  testWidgets('RTL language choice switches the demo direction and text', (
    tester,
  ) async {
    await _pump(tester, separatorExamples.examples[4]);
    TextDirection directionOf(String text) =>
        Directionality.of(tester.element(find.text(text)));
    expect(find.text('الأساس لنظام التصميم الخاص بك'), findsOneWidget);
    expect(directionOf('shadcn/ui'), TextDirection.rtl);
    expect(
      tester.getRect(find.text('shadcn/ui')).right,
      tester.getRect(find.byType(DSeparator)).right,
    );

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('The Foundation for your Design System'), findsOneWidget);
    expect(directionOf('shadcn/ui'), TextDirection.ltr);
    expect(
      tester.getRect(find.text('shadcn/ui')).left,
      tester.getRect(find.byType(DSeparator)).left,
    );

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('עברית').last);
    await tester.pumpAndSettle();
    expect(find.text('הבסיס למערכת העיצוב שלך'), findsOneWidget);
    expect(directionOf('shadcn/ui'), TextDirection.rtl);
    expect(tester.getSize(find.byType(DSeparator)), const Size(384, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native style example sizes unbounded lines explicitly and paints a hairline',
    (tester) async {
      await _pump(tester, separatorExamples.examples[5]);
      final inset = find.byKey(const ValueKey('separator-inset'));
      expect(
        tester.getRect(_line(inset)).left - tester.getRect(inset).left,
        24,
      );
      expect(
        tester.getRect(inset).right - tester.getRect(_line(inset)).right,
        8,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('separator-explicit-length'))),
        const Size(96, 24),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('separator-explicit-height'))),
        const Size(24, 48),
      );
      final rounded = find.byKey(const ValueKey('separator-rounded'));
      expect(tester.getSize(_line(rounded)).height, 4);
      expect(
        (tester.widget<DecoratedBox>(_line(rounded)).decoration
                as BoxDecoration)
            .borderRadius,
        BorderRadius.circular(2),
      );
      final hairline = find.byKey(const ValueKey('separator-hairline'));
      expect(tester.getSize(hairline).height, 16);
      expect(
        tester.renderObject(_line(hairline)),
        paints..path(style: PaintingStyle.stroke, strokeWidth: 0),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final example in separatorExamples.examples) {
    testWidgets('${example.title} fits scaled RTL layouts in every palette', (
      tester,
    ) async {
      for (final palette in [
        StyleguideTheme.light,
        StyleguideTheme.dark,
        StyleguideTheme.forest,
        StyleguideTheme.plum,
      ]) {
        final theme = ValueNotifier(palette.resolve(AppTheme.light));
        addTearDown(theme.dispose);
        for (final width in [320.0, 768.0]) {
          await _pump(
            tester,
            example,
            theme: theme,
            width: width,
            textScale: 2,
            direction: TextDirection.rtl,
          );
          expect(find.byType(DSeparator), findsWidgets);
          expect(
            tester.takeException(),
            isNull,
            reason: '${palette.name} / $width',
          );
        }
      }
    });
  }

  testWidgets('catalogue search opens the real Separator examples', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ComponentStyleguidePage()),
    );
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'separator',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-separator')),
    );
    await tester.pump();
    expect(find.text('Blog'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('styleguide-preview')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('styleguide-detail-separator')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byKey(const ValueKey('separator-configurable')),
      findsOneWidget,
    );
    await tester.tap(find.text('Meaningful boundary'));
    await tester.pump();
    expect(
      tester
          .widget<DSeparator>(
            find.byKey(const ValueKey('separator-configurable')),
          )
          .decorative,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _line(Finder separator) =>
    find.descendant(of: separator, matching: find.byType(DecoratedBox));

/// Mirrors the styleguide viewport: the preview width is the MediaQuery size
/// and the example receives loose constraints from a centered scroll view.
Future<void> _pump(
  WidgetTester tester,
  StyleguideExample example, {
  ValueNotifier<ThemeData>? theme,
  double width = 760,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previewTheme = theme ?? ValueNotifier(AppTheme.light);
  if (theme == null) addTearDown(previewTheme.dispose);
  await tester.pumpWidget(
    ValueListenableBuilder(
      valueListenable: previewTheme,
      builder: (context, value, _) => MaterialApp(
        theme: value,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: DDirection(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: SingleChildScrollView(
                    child: Center(child: Builder(builder: example.builder)),
                  ),
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
