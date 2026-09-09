import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('painted artwork matches the official Lucide SVG', (
    tester,
  ) async {
    const boundaryKey = ValueKey('reference-comparison');
    await _pump(
      tester,
      RepaintBoundary(
        key: boundaryKey,
        child: SvgPicture.string(
          File('test/fixtures/spinner/loader-circle.svg').readAsStringSync(),
          width: 96,
          height: 96,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final reference = (await tester.runAsync(() => boundary.toImage()))!;
    addTearDown(reference.dispose);
    await _pump(
      tester,
      const RepaintBoundary(
        key: boundaryKey,
        child: DSpinner(size: 96, color: Colors.black, animating: false),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(boundaryKey),
      matchesReferenceImage(reference),
    );
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('reference artwork size and color on ${platform.name}', (
      tester,
    ) async {
      for (final size in [12.0, 16.0, 24.0, 32.0]) {
        await _pump(
          tester,
          DSpinner(size: size, color: const Color(0xff126f53), strokeWidth: 3),
          platform: platform,
        );
        expect(tester.getSize(find.byType(DSpinner)), Size.square(size));
        expect(_artwork(tester).theme!.currentColor, const Color(0xff126f53));
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
    });
  }

  testWidgets('tight constraints and large text do not distort the spinner', (
    tester,
  ) async {
    await _pump(
      tester,
      const SizedBox.square(dimension: 10, child: DSpinner(size: 32)),
      scale: 3,
    );
    expect(tester.getSize(find.byType(DSpinner)), const Size.square(10));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicitly oversized custom artwork fits the requested diameter',
    (tester) async {
      await _pump(
        tester,
        const DSpinner(
          size: 24,
          animating: false,
          child: Icon(Icons.autorenew, size: 100),
        ),
      );
      expect(
        tester.getRect(find.byIcon(Icons.autorenew)),
        tester.getRect(find.byType(DSpinner)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final (platform, custom) in [
    (TargetPlatform.macOS, false),
    (TargetPlatform.linux, false),
    (TargetPlatform.macOS, true),
  ]) {
    testWidgets(
      'one busy status survives reduced motion on ${platform.name}, custom=$custom',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final spinner = DSpinner(
            semanticLabel: 'Saving draft',
            child: custom
                ? const Icon(Icons.autorenew, semanticLabel: 'Hidden artwork')
                : null,
          );
          await _pump(tester, spinner, platform: platform);
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.binding.transientCallbackCount, greaterThan(0));

          await _pump(tester, spinner, platform: platform, reducedMotion: true);
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
          final node = tester.getSemantics(
            find.bySemanticsLabel('Saving draft'),
          );
          expect(node.getSemanticsData().role, SemanticsRole.loadingSpinner);
          expect(node.getSemanticsData().value, isEmpty);
          expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
          expect(find.bySemanticsLabel('Hidden artwork'), findsNothing);
          expect(find.bySemanticsLabel('Loading'), findsNothing);
          expect(find.byType(DSpinner), findsOneWidget);

          await _pump(tester, spinner, platform: platform);
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.binding.transientCallbackCount, greaterThan(0));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('custom rotation pauses, resumes, and remains clockwise in RTL', (
    tester,
  ) async {
    Widget spinner({bool animate = true}) =>
        DSpinner(animating: animate, child: const Icon(Icons.autorenew));
    double turns() => tester
        .widget<RotationTransition>(
          find.descendant(
            of: find.byType(DSpinner),
            matching: find.byType(RotationTransition),
          ),
        )
        .turns
        .value;
    await _pump(tester, spinner());
    await tester.pump(const Duration(milliseconds: 200));
    final first = turns();
    expect(first, greaterThan(0));
    await _pump(tester, spinner(), direction: TextDirection.rtl);
    await tester.pump(const Duration(milliseconds: 200));
    expect(turns(), greaterThan(first));
    await _pump(tester, spinner(animate: false));
    final paused = turns();
    await tester.pump(const Duration(seconds: 2));
    expect(turns(), paused);
    expect(tester.binding.transientCallbackCount, 0);
    await _pump(tester, spinner());
    await tester.pump(const Duration(milliseconds: 200));
    expect(turns(), isNot(paused));
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
    testWidgets(
      'an unfocused window keeps default and custom motion while a disabled ticker subtree pauses it on ${platform.name}',
      (tester) async {
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        const indicators = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DSpinner(),
            DSpinner(child: Icon(Icons.autorenew)),
          ],
        );
        await _pump(tester, indicators, platform: platform);
        await tester.pump(const Duration(milliseconds: 100));
        // Desktop reports inactive whenever another window is key; the
        // reference keeps spinning in a visible unfocused page.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        final unfocused = _turns(tester);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.binding.transientCallbackCount, 2);
        expect(_turns(tester)[0], greaterThan(unfocused[0]));
        expect(_turns(tester)[1], greaterThan(unfocused[1]));
        // Hidden and paused windows stop scheduling frames in the framework;
        // the spinner adds no observer of its own.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        expect(tester.binding.framesEnabled, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(tester.binding.framesEnabled, isTrue);
        final resumed = _turns(tester);
        await tester.pump(const Duration(milliseconds: 100));
        expect(_turns(tester)[0], greaterThan(resumed[0]));
        await _pump(tester, indicators, platform: platform, tickers: false);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        final paused = _turns(tester);
        await tester.pump(const Duration(seconds: 2));
        expect(_turns(tester), paused);
        await _pump(tester, indicators, platform: platform);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.binding.transientCallbackCount, 2);
        expect(_turns(tester)[1], isNot(paused[1]));
      },
    );
  }

  testWidgets(
    'decorative custom artwork adds no semantics, focus or pointer target',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final artworkFocus = FocusNode();
        final actionFocus = FocusNode();
        addTearDown(artworkFocus.dispose);
        addTearDown(actionFocus.dispose);
        var presses = 0;
        var artworkPresses = 0;
        await _pump(
          tester,
          Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => presses++,
                child: DSpinner(
                  size: 48,
                  semanticLabel: null,
                  child: TextButton(
                    focusNode: artworkFocus,
                    onPressed: () => artworkPresses++,
                    child: const Text('Artwork'),
                  ),
                ),
              ),
              TextButton(
                focusNode: actionFocus,
                onPressed: () => presses++,
                child: const Text('Next action'),
              ),
            ],
          ),
        );
        expect(find.bySemanticsLabel('Loading'), findsNothing);
        expect(find.bySemanticsLabel('Artwork'), findsNothing);
        await tester.tapAt(tester.getCenter(find.byType(DSpinner)));
        expect(presses, 1);
        expect(artworkPresses, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(artworkFocus.hasFocus, isFalse);
        expect(actionFocus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(presses, 2);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('live site palettes and explicit colors reach custom artwork', (
    tester,
  ) async {
    for (final sample in [
      StyleguideTheme.light,
      StyleguideTheme.dark,
      StyleguideTheme.forest,
      StyleguideTheme.plum,
    ]) {
      final theme = sample.resolve(AppTheme.light);
      await _pump(
        tester,
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DSpinner(child: Icon(Icons.autorenew)),
            DSpinner(color: Color(0xfff2ab34), child: Icon(Icons.refresh)),
          ],
        ),
        theme: theme,
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.autorenew))).color,
        theme.iconTheme.color,
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.refresh))).color,
        const Color(0xfff2ab34),
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.autorenew))).size,
        16,
      );
    }
  });

  testWidgets(
    'loading button spinner inherits its variant color and keeps one named action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        for (final theme in [
          AppTheme.light,
          AppTheme.dark,
          StyleguideTheme.forest.resolve(AppTheme.light),
          StyleguideTheme.plum.resolve(AppTheme.light),
        ]) {
          for (final variant in DButtonVariant.values) {
            await _pump(
              tester,
              DButton(
                label: const Text('Save changes'),
                loadingLabel: const Text('Saving…'),
                loading: true,
                variant: variant,
                onPressed: () => presses++,
              ),
              theme: theme,
              platform: TargetPlatform.macOS,
            );
            // The button animates its icon color between variants for 150ms.
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.byType(DSpinner), findsOneWidget);
            final renderedButton = tester.widget<FilledButton>(
              find.byType(FilledButton),
            );
            final expected = renderedButton.style!.iconColor!.resolve({
              WidgetState.disabled,
            });
            expect(_artwork(tester).theme!.currentColor, expected);
            expect(find.bySemanticsLabel('Loading'), findsNothing);
            final node = tester
                .getSemantics(find.bySemanticsLabel('Save changes'))
                .getSemanticsData();
            expect(node.value, 'Loading');
            expect(node.flagsCollection.isButton, isTrue);
            expect(node.hasAction(SemanticsAction.tap), isFalse);
            await tester.tap(find.byType(DButton));
            expect(presses, 0);
          }
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'an open dialog receives live palette changes without replacing its spinner',
    (tester) async {
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<ThemeData>(
          valueListenable: theme,
          builder: (context, value, child) => MaterialApp(
            theme: value.copyWith(platform: TargetPlatform.macOS),
            themeAnimationDuration: Duration.zero,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: DButton(
                  label: const Text('Open busy dialog'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    useRootNavigator: false,
                    builder: (context) =>
                        const Dialog(child: Center(child: DSpinner())),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open busy dialog'));
      await tester.pumpAndSettle();
      final rotation = _rotation(tester);
      expect(
        _artwork(tester).theme!.currentColor,
        AppTheme.light.iconTheme.color,
      );
      theme.value = StyleguideTheme.plum.resolve(AppTheme.light);
      await tester.pumpAndSettle();
      expect(_rotation(tester), same(rotation));
      expect(_artwork(tester).theme!.currentColor, theme.value.iconTheme.color);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DSpinner), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  TargetPlatform platform = TargetPlatform.linux,
  ThemeData? theme,
  double scale = 1,
  bool reducedMotion = false,
  bool tickers = true,
  TextDirection direction = TextDirection.ltr,
}) => tester.pumpWidget(
  MaterialApp(
    theme: (theme ?? AppTheme.light).copyWith(platform: platform),
    themeAnimationDuration: Duration.zero,
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reducedMotion,
      ),
      child: Directionality(
        textDirection: direction,
        child: TickerMode(
          enabled: tickers,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  ),
);

Animation<double> _rotation(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(
        of: find.byType(DSpinner),
        matching: find.byType(RotationTransition),
      ),
    )
    .turns;

List<double> _turns(WidgetTester tester) => [
  for (final transition in tester.widgetList<RotationTransition>(
    find.descendant(
      of: find.byType(DSpinner),
      matching: find.byType(RotationTransition),
    ),
  ))
    transition.turns.value,
];

SvgStringLoader _artwork(WidgetTester tester) =>
    tester
            .widget<SvgPicture>(
              find.descendant(
                of: find.byType(DSpinner),
                matching: find.byType(SvgPicture),
              ),
            )
            .bytesLoader
        as SvgStringLoader;
