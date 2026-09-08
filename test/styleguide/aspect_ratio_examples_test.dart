import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/aspect_ratio_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Aspect Ratio examples are registered and searchable', (
    tester,
  ) async {
    expect(componentExamples['aspect-ratio'], same(aspectRatioExamples));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ComponentStyleguidePage()),
    );
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'aspect ratio',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-aspect-ratio')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('styleguide-preview')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('styleguide-detail-aspect-ratio')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DAspectRatio), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final example in aspectRatioExamples.examples) {
    for (final (theme, width, scale, direction) in [
      (StyleguideTheme.light, 768.0, 1.0, TextDirection.ltr),
      (StyleguideTheme.dark, 320.0, 2.0, TextDirection.rtl),
      (StyleguideTheme.forest, 768.0, 1.0, TextDirection.rtl),
      (StyleguideTheme.plum, 320.0, 2.0, TextDirection.ltr),
    ]) {
      testWidgets(
        '${example.title} fits $width px at ${scale}x in ${theme.name}',
        (tester) async {
          await _pump(
            tester,
            example,
            width: width,
            scale: scale,
            theme: theme,
            direction: direction,
          );
          expect(find.byType(DAspectRatio), findsWidgets);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('frozen covers keep exact geometry and live image treatment', (
    tester,
  ) async {
    for (final (index, size) in [
      (0, const Size(384, 216)),
      (1, const Size(192, 192)),
      (2, const Size(160, 160 * 16 / 9)),
      (3, const Size(384, 216)),
    ]) {
      for (final palette in [
        StyleguideTheme.light,
        StyleguideTheme.dark,
        StyleguideTheme.forest,
        StyleguideTheme.plum,
      ]) {
        await _pump(
          tester,
          aspectRatioExamples.examples[index],
          theme: palette,
          width: 600,
        );
        expect(tester.getSize(find.byType(DAspectRatio)), size);
        final context = tester.element(find.byType(DAspectRatio));
        final tokens = DTokens.of(context);
        expect(
          tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
          tokens.borderRadius,
        );
        final fill = find.descendant(
          of: find.byType(DAspectRatio),
          matching: find.byType(ColoredBox),
        );
        expect(tester.widget<ColoredBox>(fill).color, tokens.muted);
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.fit, BoxFit.cover);
        expect(image.image, isA<AssetImage>());
        final brightness = Theme.of(context).brightness == Brightness.dark
            ? 0.2
            : 1.0;
        expect(
          tester.widget<ColorFiltered>(find.byType(ColorFiltered)).colorFilter,
          ColorFilter.matrix([
            0.2126 * brightness,
            0.7152 * brightness,
            0.0722 * brightness,
            0,
            0,
            0.2126 * brightness,
            0.7152 * brightness,
            0.0722 * brightness,
            0,
            0,
            0.2126 * brightness,
            0.7152 * brightness,
            0.0722 * brightness,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
        );
        if (index == 3) {
          final caption = find.text('منظر طبيعي جميل');
          expect(
            tester.getTopLeft(caption).dy -
                tester.getBottomLeft(find.byType(DAspectRatio)).dy,
            8,
          );
          final render = tester.renderObject<RenderParagraph>(caption);
          expect(render.text.style!.fontSize, 14);
          expect(render.text.style!.height, 20 / 14);
          expect(render.textAlign, TextAlign.center);
          expect(render.textDirection, TextDirection.rtl);
        }
      }
    }
  });

  testWidgets(
    'arbitrary ratio responds to keyboard and independent fit/clipping controls',
    (tester) async {
      await _pump(tester, aspectRatioExamples.examples[4]);
      final slider = find.byType(Slider);
      await tester.tap(slider);
      await tester.pumpAndSettle();
      final focus = tester
          .widget<FocusableActionDetector>(
            find.descendant(
              of: slider,
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!;
      focus.requestFocus();
      await tester.pump();
      final before = tester.widget<Slider>(slider).value;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final after = tester.widget<Slider>(slider).value;
      expect(after, greaterThan(before));
      expect(
        tester.widget<DAspectRatio>(find.byType(DAspectRatio)).ratio,
        after,
      );
      await tester.tap(find.text('Use contain'));
      await tester.pump();
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      await tester.tap(find.text('Square corners'));
      await tester.pump();
      expect(
        tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
        BorderRadius.zero,
      );
    },
  );

  testWidgets(
    'interactive draft and counter survive ratio, palette, direction and scale changes',
    (tester) async {
      final example = aspectRatioExamples.examples.last;
      await _pump(tester, example);
      await tester.enterText(find.byType(TextField), 'Still here');
      await tester.tap(find.byKey(const ValueKey('aspect-ratio-increment')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('aspect-ratio-resize')));
      await tester.pump();
      for (final theme in [
        StyleguideTheme.dark,
        StyleguideTheme.forest,
        StyleguideTheme.plum,
      ]) {
        await _pump(
          tester,
          example,
          theme: theme,
          width: 320,
          scale: 2,
          direction: TextDirection.rtl,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Still here',
        );
        expect(
          tester.widget<DAspectRatio>(find.byType(DAspectRatio)).ratio,
          3 / 2,
        );
        expect(find.text('Count: 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final button = find.byKey(const ValueKey('aspect-ratio-increment'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Count: 2'), findsOneWidget);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  StyleguideExample example, {
  double width = 500,
  double scale = 1,
  StyleguideTheme theme = StyleguideTheme.light,
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.resolve(AppTheme.light),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Align(
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
