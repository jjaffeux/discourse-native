import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:discourse_native/src/styleguide/examples/marker_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  double width = 384,
  double scale = 1,
  bool rtl = false,
  bool reduced = false,
  TargetPlatform platform = TargetPlatform.macOS,
  bool dark = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(platform: platform),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('inline and border preserve source geometry', (tester) async {
    for (final variant in [DMarkerVariant.inline, DMarkerVariant.border]) {
      await pump(
        tester,
        DMarker(
          variant: variant,
          icon: const DMarkerIcon(child: Icon(Icons.check)),
          child: const DMarkerContent(child: Text('Complete')),
        ),
      );
      expect(
        tester.getSize(find.byType(DMarker)).height,
        variant == DMarkerVariant.border ? 29 : 20,
      );
      expect(tester.getSize(find.byType(DMarkerIcon)), const Size(16, 16));
      expect(
        tester.getTopLeft(find.text('Complete')).dx -
            tester.getTopRight(find.byType(DMarkerIcon)).dx,
        8,
      );
    }
  });

  testWidgets('separator centers intrinsic label and retains equal lines', (
    tester,
  ) async {
    await pump(
      tester,
      const DMarker(
        variant: DMarkerVariant.separator,
        child: DMarkerContent(child: Text('Today')),
      ),
    );
    expect(
      tester.getCenter(find.text('Today')).dx,
      tester.getCenter(find.byType(DMarker)).dx,
    );
    final rules = find.byType(ColoredBox);
    expect(rules, findsNWidgets(2));
    expect(tester.getSize(rules.first).width, tester.getSize(rules.last).width);
    expect(tester.getSize(rules.first).width, greaterThan(100));
    expect(
      tester.getRect(find.text('Today')).left -
          tester.getRect(rules.first).right,
      12,
    );
  });

  testWidgets('status announces text and excludes decorative spinner', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pump(
      tester,
      const DMarker(
        liveRegion: true,
        icon: DMarkerIcon(child: DSpinner(semanticLabel: 'Hidden busy')),
        child: DMarkerContent(child: Text('Running tests')),
      ),
    );
    final node = tester.getSemantics(find.byType(DMarker));
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(find.bySemanticsLabel('Hidden busy'), findsNothing);
    expect(find.bySemanticsLabel('Running tests'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('button keyboard and pointer actions disable and borrow focus', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var calls = 0;
    Widget marker(bool enabled) => DMarker(
      action: DMarkerAction.button,
      focusNode: focus,
      onPressed: enabled ? () => calls++ : null,
      child: const DMarkerContent(child: Text('Revert')),
    );
    await pump(tester, marker(true));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.tap(find.text('Revert'));
    expect(calls, 3);
    await pump(tester, marker(false));
    await tester.tap(find.text('Revert'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 3);
    await pump(tester, const Text('Removed'));
    focus.requestFocus();
  });

  testWidgets('link semantics and touch bounds remain distinct from desktop', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    final child = DMarker(
      action: DMarkerAction.link,
      onPressed: () {},
      child: const DMarkerContent(child: Text('Details')),
    );
    await pump(tester, child, platform: TargetPlatform.iOS);
    expect(tester.getSize(find.byType(DMarker)).height, 48);
    expect(
      tester
          .getSemantics(find.byType(DMarker))
          .getSemanticsData()
          .flagsCollection
          .isLink,
      isTrue,
    );
    await pump(tester, child);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DMarker)).height, 20);
    handle.dispose();
  });

  testWidgets(
    'shimmer stops under reduced motion and lifecycle then disposes',
    (tester) async {
      const child = DMarker(
        child: DMarkerContent(shimmer: true, child: Text('Thinking...')),
      );
      await pump(tester, child);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await pump(tester, child, reduced: true);
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await pump(tester, const Text('Removed'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final example in markerExamples.examples) {
    testWidgets('${example.title} wraps at narrow RTL large text', (
      tester,
    ) async {
      await pump(
        tester,
        SingleChildScrollView(
          child: example.builder(tester.element(find.byType(View))),
        ),
        width: 220,
        scale: 2,
        rtl: true,
        reduced: true,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'examples complete status and activate local navigation and revert',
    (tester) async {
      await pump(
        tester,
        Builder(builder: markerExamples.examples[1].builder),
        reduced: true,
      );
      await tester.tap(find.text('Complete work'));
      await tester.pump();
      expect(find.text('Conversation compacted'), findsNWidgets(2));
      expect(find.byType(DSpinner), findsNothing);
      await pump(tester, Builder(builder: markerExamples.examples[3].builder));
      await tester.tap(find.text('View the pull request'));
      await tester.pump();
      expect(
        find.text(
          'Pull request #42: Update the conversation notes. All checks passed.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Revert this change'));
      await tester.pump();
      expect(find.text('Change reverted'), findsOneWidget);
      await pump(
        tester,
        Builder(builder: markerExamples.examples[3].builder),
        dark: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Change reverted'), findsOneWidget);
    },
  );

  testWidgets(
    'live theme changes foreground and border without replacing content',
    (tester) async {
      const child = DMarker(
        variant: DMarkerVariant.border,
        child: DMarkerContent(child: Text('Note')),
      );
      await pump(tester, child);
      final state = tester.state(find.byType(DMarkerContent));
      Color? textColor() =>
          DefaultTextStyle.of(tester.element(find.text('Note'))).style.color;
      final light = textColor();
      await pump(tester, child, dark: true);
      await tester.pumpAndSettle();
      expect(textColor(), isNot(light));
      expect(tester.state(find.byType(DMarkerContent)), same(state));
      final context = tester.element(find.byType(DMarker));
      final boxes = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(DMarker),
          matching: find.byType(Container),
        ),
      );
      final border =
          boxes
                  .map((box) => box.decoration)
                  .whereType<BoxDecoration>()
                  .single
                  .border!
              as Border;
      expect(border.bottom.color, DTokens.of(context).border);
    },
  );

  testWidgets(
    'migrated date keeps label-only callback and fixed timeline slot',
    (tester) async {
      var calls = 0;
      await pump(
        tester,
        StreamDaySeparator(day: DateTime.now(), onTap: () => calls++),
      );
      expect(tester.getSize(find.byType(StreamDaySeparator)).height, 44);
      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(calls, 1);
      await tester.tapAt(
        tester.getRect(find.byType(StreamDaySeparator)).centerLeft +
            const Offset(20, 0),
      );
      expect(calls, 1);
      await pump(
        tester,
        StreamDaySeparator(
          day: DateTime.now(),
          floating: true,
          onTap: () => calls++,
        ),
        dark: true,
      );
      expect(
        tester.widget<DMarker>(find.byType(DMarker)).variant,
        DMarkerVariant.inline,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
