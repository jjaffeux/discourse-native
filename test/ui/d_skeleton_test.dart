import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/site_appearance_fixtures.dart';

void main() {
  testWidgets('standalone shapes obey constraints, aspect ratio and radius', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DSkeleton(key: ValueKey('full-line'), height: 16),
                FractionallySizedBox(
                  widthFactor: 0.75,
                  child: DSkeleton(key: ValueKey('short-line'), height: 16),
                ),
                AspectRatio(
                  aspectRatio: 2,
                  child: DSkeleton(key: ValueKey('cover')),
                ),
                DSkeleton.circle(key: ValueKey('avatar'), diameter: 40),
                DSkeleton(
                  key: ValueKey('pill'),
                  width: 100,
                  height: 20,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('full-line'))),
      const Size(200, 16),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('short-line'))),
      const Size(150, 16),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('cover'))),
      const Size(200, 100),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('avatar'))),
      const Size(40, 40),
    );
    expect(_decoration(tester, 'avatar').shape, BoxShape.circle);
    expect(
      _decoration(tester, 'pill').borderRadius,
      BorderRadius.circular(999),
    );
    expect(_fade(tester, 'full-line').opacity.value, closeTo(1, 0.001));
    await tester.pump(DMotion.pulse);
    expect(_fade(tester, 'full-line').opacity.value, closeTo(0.5, 0.001));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unbounded dimensions collapse and intrinsic regions stay small',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UnconstrainedBox(child: DSkeleton(key: ValueKey('unbounded'))),
                DSkeletonRegion(
                  key: ValueKey('intrinsic'),
                  semanticsLabel: 'Loading inline item',
                  child: DSkeleton(width: 120, height: 20),
                ),
                SizedBox(
                  width: 32,
                  child: DSkeleton(width: 120, height: 20, animate: false),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('unbounded'))),
        Size.zero,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('intrinsic'))),
        const Size(120, 20),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('theme and directional corners update without restarting pulse', (
    tester,
  ) async {
    final settings = ValueNotifier((
      theme: AppTheme.light,
      direction: TextDirection.ltr,
    ));
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: settings,
        builder: (context, value, child) => MaterialApp(
          theme: value.theme,
          themeAnimationDuration: Duration.zero,
          home: DDirection(
            textDirection: value.direction,
            child: Scaffold(body: child),
          ),
        ),
        child: const Column(
          children: [
            DSkeleton(key: ValueKey('default-radius'), width: 120, height: 20),
            DSkeleton(
              key: ValueKey('directional'),
              width: 120,
              height: 20,
              borderRadius: BorderRadiusDirectional.only(
                topStart: Radius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final animation = _fade(tester, 'default-radius').opacity;
    final opacity = animation.value;
    expect(
      _decoration(tester, 'directional').borderRadius,
      const BorderRadius.only(topLeft: Radius.circular(12)),
    );
    for (final theme in [
      AppTheme.dark,
      AppTheme.fromPalette(sitePalette()),
      ThemeData.light(),
    ]) {
      settings.value = (theme: theme, direction: TextDirection.rtl);
      await tester.pump();
      final tokens = DTokens.of(
        tester.element(find.byKey(const ValueKey('default-radius'))),
      );
      expect(_decoration(tester, 'default-radius').color, tokens.muted);
      expect(
        _decoration(tester, 'default-radius').borderRadius,
        BorderRadius.circular(tokens.radius * 0.8),
      );
      expect(
        _decoration(tester, 'directional').borderRadius,
        const BorderRadius.only(topRight: Radius.circular(12)),
      );
      expect(_fade(tester, 'default-radius').opacity, same(animation));
      expect(animation.value, opacity);
    }
  });

  testWidgets('live motion settings stop frames and resume both pulse owners', (
    tester,
  ) async {
    final settings = ValueNotifier((
      animate: true,
      reduced: false,
      ticker: true,
    ));
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder(
          valueListenable: settings,
          builder: (context, value, _) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: value.reduced),
            child: TickerMode(
              enabled: value.ticker,
              child: Column(
                children: [
                  DSkeleton(
                    key: const ValueKey('standalone'),
                    width: 100,
                    height: 20,
                    animate: value.animate,
                  ),
                  DSkeletonRegion(
                    semanticsLabel: 'Loading group',
                    animate: value.animate,
                    child: const DSkeleton(
                      key: ValueKey('grouped'),
                      width: 100,
                      height: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (final paused in [
      (animate: true, reduced: true, ticker: true),
      (animate: true, reduced: false, ticker: false),
      (animate: false, reduced: false, ticker: true),
    ]) {
      settings.value = paused;
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(_fade(tester, 'grouped').opacity.value, 1);
      if (paused.animate) expect(_fade(tester, 'standalone').opacity.value, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      settings.value = (animate: true, reduced: false, ticker: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_fade(tester, 'standalone').opacity.value, lessThan(1));
      expect(_fade(tester, 'grouped').opacity.value, lessThan(1));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a static shape opts out of its region pulse', (tester) async {
    await tester.pumpWidget(
      _app(
        const DSkeletonRegion(
          semanticsLabel: 'Loading partly animated preview',
          child: Row(
            children: [
              DSkeleton(key: ValueKey('animated'), width: 100, height: 20),
              DSkeleton(
                key: ValueKey('static'),
                width: 100,
                height: 20,
                animate: false,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('static')),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    await tester.pump(DMotion.pulse);
    expect(_fade(tester, 'animated').opacity.value, closeTo(0.5, 0.001));
    expect(
      _decoration(tester, 'static').color,
      _decoration(tester, 'animated').color,
    );
  });

  testWidgets('loading descendants cannot receive touch or keyboard focus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final first = FocusNode();
    final hidden = FocusNode();
    final last = FocusNode();
    addTearDown(first.dispose);
    addTearDown(hidden.dispose);
    addTearDown(last.dispose);
    var taps = 0;
    final loading = ValueNotifier(true);
    addTearDown(loading.dispose);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            TextButton(
              focusNode: first,
              onPressed: () {},
              child: const Text('Before'),
            ),
            ValueListenableBuilder(
              valueListenable: loading,
              builder: (context, value, _) => value
                  ? DSkeletonRegion(
                      semanticsLabel: 'Loading account',
                      liveRegion: false,
                      child: TextButton(
                        focusNode: hidden,
                        onPressed: () => taps++,
                        child: const Text('Hidden action'),
                      ),
                    )
                  : const Text('Account ready'),
            ),
            TextButton(
              focusNode: last,
              onPressed: () => taps++,
              child: const Text('After'),
            ),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Loading account'), findsOneWidget);
    expect(find.bySemanticsLabel('Hidden action'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Loading account'))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isFalse,
    );
    await tester.tapAt(tester.getCenter(find.text('Hidden action')));
    hidden.requestFocus();
    await tester.pump();
    expect(hidden.hasFocus, isFalse);
    expect(taps, 0);
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(last.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    loading.value = false;
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loading account'), findsNothing);
    expect(find.bySemanticsLabel('Account ready'), findsOneWidget);
    expect(last.hasPrimaryFocus, isTrue);
    semantics.dispose();
  });

  testWidgets('takes all available bounded space', (tester) async {
    await tester.pumpWidget(
      _app(
        const Align(
          child: DSkeletonRegion(
            expand: true,
            key: ValueKey('full-size-skeleton'),
            semanticsLabel: 'Loading content',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [DSkeleton(width: 120, height: 9)],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('full-size-skeleton'))),
      const Size(800, 600),
    );
  });

  testWidgets('keeps its natural size on an unbounded axis', (tester) async {
    await tester.pumpWidget(
      _app(
        const SingleChildScrollView(
          child: DSkeletonRegion(
            expand: true,
            key: ValueKey('scroll-skeleton'),
            semanticsLabel: 'Loading content',
            child: SizedBox(height: 40),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('scroll-skeleton'))),
      const Size(800, 40),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('matches the two-second shadcn pulse with synchronized blocks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const DSkeletonRegion(
          expand: true,
          key: ValueKey('pulse-skeleton'),
          semanticsLabel: 'Loading content',
          child: Column(
            children: [
              DSkeleton(width: 120, height: 9),
              DSkeleton.circle(diameter: 32),
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
    expect(fades[0].opacity.value, closeTo(1, 0.001));
    for (final expected in [0.75, 0.5, 0.75, 1.0]) {
      await tester.pump(const Duration(milliseconds: 500));
      expect(fades[0].opacity.value, closeTo(expected, 0.001));
    }

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
        const DSkeletonRegion(
          expand: true,
          key: ValueKey('reduced-motion-skeleton'),
          semanticsLabel: 'Loading content',
          child: DSkeleton(width: 120, height: 9),
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
    try {
      await tester.pumpWidget(
        _app(
          const DSkeletonRegion(
            expand: true,
            semanticsLabel: 'Loading content',
            child: Column(
              children: [
                Text('Decorative stand-in'),
                DSkeleton(width: 120, height: 9),
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
    } finally {
      semantics.dispose();
    }
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
          const DSkeletonRegion(
            expand: true,
            semanticsLabel: 'Loading content',
            child: DSkeleton(
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
      final tokens = DTokens.of(
        tester.element(find.byKey(const ValueKey('themed-skeleton-block'))),
      );
      expect(decoration.color, tokens.muted);
      // shadcn deliberately uses subtle bg-muted, including a 0.5 trough.
      // Do not impose a text-contrast threshold on decorative placeholders.
      expect(tokens.muted, isNot(tokens.background));

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

BoxDecoration _decoration(WidgetTester tester, String key) =>
    tester
            .widget<DecoratedBox>(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(DecoratedBox),
              ),
            )
            .decoration
        as BoxDecoration;

FadeTransition _fade(WidgetTester tester, String key) =>
    tester.widget<FadeTransition>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(FadeTransition),
      ),
    );
