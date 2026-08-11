import 'package:discourse_native/src/shell/loading_skeleton.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/site_appearance_fixtures.dart';

void main() {
  testWidgets('pulses every block together through the approved cycle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const LoadingSkeleton(
          key: ValueKey('pulse-skeleton'),
          semanticsLabel: 'Loading content',
          child: Column(
            children: [
              LoadingSkeletonBlock(width: 120, height: 9),
              LoadingSkeletonBlock.circle(diameter: 32),
            ],
          ),
        ),
      ),
    );

    final fades = tester
        .widgetList<FadeTransition>(
          find.descendant(
            of: find.byKey(const ValueKey('pulse-skeleton')),
            matching: find.byType(FadeTransition),
          ),
        )
        .toList();
    expect(fades, hasLength(2));
    expect(identical(fades[0].opacity, fades[1].opacity), isTrue);
    expect(fades[0].opacity.value, closeTo(0.62, 0.001));

    await tester.pump(const Duration(milliseconds: 675));
    expect(fades[0].opacity.value, closeTo(1, 0.001));

    await tester.pump(const Duration(milliseconds: 675));
    expect(fades[0].opacity.value, closeTo(0.62, 0.001));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion is static at full opacity', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      _app(
        const LoadingSkeleton(
          key: ValueKey('reduced-motion-skeleton'),
          semanticsLabel: 'Loading content',
          child: LoadingSkeletonBlock(width: 120, height: 9),
        ),
      ),
    );

    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('reduced-motion-skeleton')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);

    await tester.pump(const Duration(milliseconds: 2700));
    expect(fade.opacity.value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('exposes one live loading label and excludes its shapes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        const LoadingSkeleton(
          semanticsLabel: 'Loading content',
          child: Column(
            children: [
              Text('Decorative stand-in'),
              LoadingSkeletonBlock(width: 120, height: 9),
            ],
          ),
        ),
      ),
    );

    final loadingSemantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Loading content',
    );
    expect(loadingSemantics, findsOneWidget);
    final widget = tester.widget<Semantics>(loadingSemantics);
    expect(widget.container, isTrue);
    expect(widget.properties.liveRegion, isTrue);
    expect(find.bySemanticsLabel('Decorative stand-in'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  final customSitePalette = sitePalette();
  for (final entry in [
    (name: 'light', theme: AppTheme.light),
    (name: 'dark', theme: AppTheme.dark),
    (name: 'site', theme: AppTheme.fromPalette(customSitePalette)),
  ]) {
    testWidgets('uses the ${entry.name} theme skeleton surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const LoadingSkeleton(
            semanticsLabel: 'Loading content',
            child: LoadingSkeletonBlock(
              key: ValueKey('themed-skeleton-block'),
              width: 120,
              height: 9,
            ),
          ),
          theme: entry.theme,
        ),
      );

      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byKey(const ValueKey('themed-skeleton-block')),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, entry.theme.colorScheme.surfaceContainerHighest);
      if (entry.name == 'site') {
        expect(decoration.color, customSitePalette.primaryLow);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

Widget _app(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(body: child),
  );
}
