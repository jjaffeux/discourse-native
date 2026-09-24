import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/topic_skeleton.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Discourse's default schemes, as a site's CSS resolves them. The dark
  // scheme's --primary-very-low sits a few levels above its page.
  final discourseDark = ResolvedSitePalette.fromJson(const {
    'brightness': 'dark',
    'primary': 0xFFDDDDDD,
    'secondary': 0xFF222222,
    'tertiary': 0xFF099DD7,
    'primaryVeryLow': 0xFF282828,
    'primaryLow': 0xFF313131,
    'primaryLowMid': 0xFF7A7A7A,
    'contentBorderColor': 0xFF313131,
  });
  final discourseLight = ResolvedSitePalette.fromJson(const {
    'brightness': 'light',
    'primary': 0xFF222222,
    'secondary': 0xFFFFFFFF,
    'tertiary': 0xFF0088CC,
    'primaryVeryLow': 0xFFF8F8F8,
    'primaryLow': 0xFFE9E9E9,
    'primaryLowMid': 0xFFBDBDBD,
    'contentBorderColor': 0xFFE9E9E9,
  });

  testWidgets('topic placeholders stay visible at the pulse trough', (
    tester,
  ) async {
    final themes = <String, ThemeData>{
      'app dark': AppTheme.dark,
      'app light': AppTheme.light,
      'Discourse dark': AppTheme.fromPalette(discourseDark),
      'Discourse light': AppTheme.fromPalette(discourseLight),
      for (final preset in forumThemePresets)
        for (final brightness in Brightness.values)
          '${preset.id} ${brightness.name}': AppTheme.fromPalette(
            preset.resolve(brightness),
          ),
    };
    for (final MapEntry(key: name, value: theme) in themes.entries) {
      late Color fill;
      late Color page;
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: theme,
          home: Builder(
            builder: (context) {
              fill = topicSkeletonColor(context);
              page = DTokens.of(context).background;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // The pulse halves the fill's opacity. The UI kit's muted fill reached
      // only 1.02-1.05 there on dark palettes: indistinguishable from the page.
      final trough = Color.alphaBlend(fill.withValues(alpha: fill.a / 2), page);
      expect(_contrast(trough, page), greaterThanOrEqualTo(1.08), reason: name);
    }
  });

  testWidgets(
    'placeholders stay transparent and still through the grace period',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: TopicSkeletonReveal(
              child: DSkeletonRegion(
                semanticsLabel: 'Loading topic',
                child: DSkeleton(key: ValueKey('shape'), width: 80, height: 10),
              ),
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      try {
        double opacity() => tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .opacity;
        bool ticking() => TickerMode.valuesOf(
          tester.element(find.byKey(const ValueKey('shape'))),
        ).enabled;

        expect(
          tester.getSize(find.byKey(const ValueKey('shape'))),
          const Size(80, 10),
        );
        expect(opacity(), 0);
        expect(ticking(), isFalse);
        expect(find.bySemanticsLabel('Loading topic'), findsOneWidget);

        await tester.pump(
          TopicSkeletonReveal.delay - const Duration(milliseconds: 1),
        );
        expect(opacity(), 0);

        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(DMotion.enter);
        expect(opacity(), 1);
        expect(ticking(), isTrue);
      } finally {
        handle.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + .05) / (darker + .05);
}
