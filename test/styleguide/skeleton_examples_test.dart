import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/skeleton_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('registered Skeleton examples are reachable through search', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    expect(componentExamples['skeleton'], same(skeletonExamples));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ComponentStyleguidePage()),
    );
    await tester.tap(find.byKey(const ValueKey('styleguide-navigation')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'skeleton',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-skeleton')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('styleguide-preview')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('styleguide-detail-skeleton')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(DSkeleton), findsNWidgets(8));
    expect(tester.takeException(), isNull);
  });

  for (final example in skeletonExamples.examples) {
    for (final (width, scale, direction, theme) in [
      (320.0, 2.0, TextDirection.rtl, StyleguideTheme.plum),
      (1024.0, 1.0, TextDirection.ltr, StyleguideTheme.forest),
    ]) {
      testWidgets(
        '${example.title} fits $width px at ${scale}x in ${theme.name}',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await _pump(
            tester,
            example,
            scale: scale,
            direction: direction,
            theme: theme.resolve(AppTheme.light),
          );
          expect(find.byType(DSkeleton), findsWidgets);
          expect(tester.takeException(), isNull);
          if (example != skeletonExamples.examples.first) {
            await tester.tap(find.widgetWithText(ChoiceChip, 'Ready'));
            await tester.pumpAndSettle();
            expect(find.byType(DSkeleton), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.tap(find.widgetWithText(ChoiceChip, 'Error'));
            await tester.pumpAndSettle();
            expect(find.text('Could not load this sample.'), findsOneWidget);
            await tester.ensureVisible(find.text('Retry'));
            await tester.tap(find.text('Retry'));
            await tester.pumpAndSettle();
            expect(find.byType(DSkeleton), findsWidgets);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets('geometry controls alter shapes and respond to keyboard', (
    tester,
  ) async {
    await _pump(
      tester,
      skeletonExamples.examples.first,
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    );
    final width = find.byType(Slider).first;
    await tester.ensureVisible(width);
    await tester.tap(width);
    await tester.pumpAndSettle();
    final sliderFocus = tester
        .widget<FocusableActionDetector>(
          find.descendant(
            of: width,
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .focusNode!;
    for (var step = 0; step < 10 && !sliderFocus.hasPrimaryFocus; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(sliderFocus.hasPrimaryFocus, isTrue);
    final before = tester.widget<Slider>(width).value;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(width).value, greaterThan(before));
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Circle'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Circle'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DSkeleton>(
            find.byKey(const ValueKey('skeleton-geometry-shape')),
          )
          .shape,
      BoxShape.circle,
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Pulse'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DSkeleton>(
            find.byKey(const ValueKey('skeleton-geometry-shape')),
          )
          .animate,
      isFalse,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pill'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DSkeleton>(
            find.byKey(const ValueKey('skeleton-geometry-shape')),
          )
          .borderRadius,
      BorderRadius.circular(999),
    );
  });

  testWidgets('frozen examples preserve shadcn dimensions and spacing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<Rect> shapes() => [
      for (var i = 0; i < find.byType(DSkeleton).evaluate().length; i++)
        tester.getRect(find.byType(DSkeleton).at(i)),
    ];

    await _pump(tester, skeletonExamples.examples[1]);
    var bounds = shapes();
    expect(bounds.map((r) => r.size), [
      const Size(40, 40),
      const Size(150, 16),
      const Size(100, 16),
    ]);
    expect(bounds[1].left - bounds[0].right, 16);
    expect(bounds[2].top - bounds[1].bottom, 8);

    await _pump(tester, skeletonExamples.examples[2]);
    bounds = shapes();
    final card = tester.getRect(find.byType(DSkeletonRegion));
    expect(card.size, const Size(320, 246));
    expect(bounds.map((r) => r.size), [
      const Size(192, 16),
      const Size(144, 16),
      const Size(288, 162),
    ]);
    expect(bounds[0].left - card.left, 16);
    expect(bounds[0].top - card.top, 16);
    expect(bounds[1].top - bounds[0].bottom, 4);
    expect(bounds[2].top - bounds[1].bottom, 16);
    expect(card.bottom - bounds[2].bottom, 16);

    await _pump(tester, skeletonExamples.examples[3]);
    bounds = shapes();
    expect(bounds.map((r) => r.size), [
      const Size(320, 16),
      const Size(320, 16),
      const Size(240, 16),
    ]);
    expect(bounds[1].top - bounds[0].bottom, 8);
    expect(bounds[2].top - bounds[1].bottom, 8);

    await _pump(tester, skeletonExamples.examples[4]);
    bounds = shapes();
    expect(bounds.map((r) => r.size), [
      const Size(80, 16),
      const Size(320, 32),
      const Size(96, 16),
      const Size(320, 32),
      const Size(96, 32),
    ]);
    expect(bounds[1].top - bounds[0].bottom, 12);
    expect(bounds[2].top - bounds[1].bottom, 28);
    expect(bounds[3].top - bounds[2].bottom, 12);
    expect(bounds[4].top - bounds[3].bottom, 28);

    await _pump(tester, skeletonExamples.examples[5]);
    bounds = shapes();
    expect(bounds, hasLength(15));
    expect(tester.getSize(find.byType(DSkeletonRegion)), const Size(384, 112));
    for (var row = 0; row < 5; row++) {
      final i = row * 3;
      expect(bounds[i].size, const Size(176, 16));
      expect(bounds[i + 1].size, const Size(96, 16));
      expect(bounds[i + 2].size, const Size(80, 16));
      expect(bounds[i + 1].left - bounds[i].right, 16);
      expect(bounds[i + 2].left - bounds[i + 1].right, 16);
      if (row > 0) expect(bounds[i].top - bounds[i - 3].bottom, 8);
    }

    await _pump(tester, skeletonExamples.examples[6]);
    bounds = shapes();
    expect(bounds.map((r) => r.size), [
      const Size(48, 48),
      const Size(250, 16),
      const Size(200, 16),
    ]);
    expect(bounds[0].left - bounds[1].right, 16);
    expect(bounds[2].right, bounds[1].right);
    expect(bounds[2].top - bounds[1].bottom, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready form validates, saves and retains edits across themes', (
    tester,
  ) async {
    final theme = ValueNotifier(AppTheme.light);
    addTearDown(theme.dispose);
    await _pump(tester, skeletonExamples.examples[4], liveTheme: theme);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ready'));
    await tester.pumpAndSettle();
    final name = find.byType(TextFormField).first;
    await tester.enterText(name, '');
    await tester.tap(find.widgetWithText(DButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    await tester.enterText(name, 'Grace');
    theme.value = StyleguideTheme.plum.resolve(AppTheme.light);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'Grace',
    );
    await tester.tap(find.widgetWithText(DButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved: Grace'), findsOneWidget);
    expect(find.text('Enter a name'), findsNothing);
  });

  testWidgets('ready card action and table scrolling remain interactive', (
    tester,
  ) async {
    await _pump(tester, skeletonExamples.examples[2]);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ready'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Follow'));
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(find.text('Following'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(240, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, skeletonExamples.examples[5]);
    final scroll = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    );
    final state = tester.state<ScrollableState>(scroll);
    expect(state.position.maxScrollExtent, greaterThan(0));
    await tester.drag(scroll, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ready'));
    await tester.pumpAndSettle();
    expect(find.text('Ken'), findsOneWidget);
    expect(state.position.pixels, greaterThan(0));
  });
}

Future<void> _pump(
  WidgetTester tester,
  StyleguideExample example, {
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
  ValueNotifier<ThemeData>? liveTheme,
}) async {
  final hostTheme = liveTheme ?? ValueNotifier(theme ?? AppTheme.light);
  if (liveTheme == null) addTearDown(hostTheme.dispose);
  await tester.pumpWidget(
    ValueListenableBuilder(
      key: ValueKey(example.title),
      valueListenable: hostTheme,
      builder: (context, data, _) => MaterialApp(
        theme: data,
        themeAnimationDuration: Duration.zero,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: DDirection(
              textDirection: direction,
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(DSpacing.lg),
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
