import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pins, releases at its boundary, and preserves interaction', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final semantics = tester.ensureSemantics();
    try {
      var taps = 0;
      final avatar = DButton(
        key: const ValueKey('avatar'),
        onPressed: () => taps++,
        label: const Text('A'),
      );
      await _pump(tester, scroll: scroll, child: avatar);
      final target = find.byKey(const ValueKey('avatar'));
      final viewportTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final initialTop = tester.getTopLeft(target).dy;
      expect(initialTop, viewportTop + 100);

      scroll.jumpTo(160);
      await tester.pump();
      expect(tester.getTopLeft(target).dy, closeTo(viewportTop + 12, .01));
      expect(
        tester
            .getSemantics(target)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(target);
      await tester.pump();
      expect(taps, 1);

      scroll.jumpTo(390);
      await tester.pump();
      expect(tester.getBottomLeft(target).dy, closeTo(viewportTop + 10, .01));
      scroll.jumpTo(20);
      await tester.pump();
      expect(tester.getTopLeft(target).dy, closeTo(initialTop - 20, .01));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('scrolling only repaints the sticky child', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final counts = _Counts();
    await _pump(
      tester,
      scroll: scroll,
      child: _Probe(counts: counts),
    );
    final layouts = counts.layouts;
    final builds = counts.builds;
    final paints = counts.paints;
    for (final offset in [160.0, 200.0, 260.0]) {
      scroll.jumpTo(offset);
      await tester.pump();
      final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      expect(counts.paintedTop, closeTo(top + 12, .01));
    }
    expect(counts.layouts, layouts);
    expect(counts.builds, builds);
    expect(counts.paints, greaterThan(paints));
    expect(
      tester.renderObject<RenderBox>(find.byType(DSticky)).paintBounds.size,
      const Size.square(32),
    );
  });

  testWidgets('updates after content before it changes height', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final prefix = ValueNotifier<double>(100);
    addTearDown(prefix.dispose);
    final counts = _Counts();
    await _pump(
      tester,
      scroll: scroll,
      prefix: prefix,
      child: _Probe(counts: counts),
    );
    scroll.jumpTo(160);
    await tester.pump();
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    expect(counts.paintedTop, closeTo(top + 12, .01));
    prefix.value = 200;
    await tester.pump();
    expect(counts.paintedTop, closeTo(top + 40, .01));
  });

  testWidgets('short slots and content resizing respect the bottom', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final height = ValueNotifier<double>(300);
    addTearDown(height.dispose);
    await _pump(
      tester,
      scroll: scroll,
      height: height,
      child: const SizedBox(key: ValueKey('avatar'), width: 32, height: 32),
    );
    scroll.jumpTo(160);
    await tester.pump();
    height.value = 80;
    await tester.pump();
    final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('avatar'))).dy,
      closeTo(top + 20, .01),
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ScrollController scroll,
  required Widget child,
  ValueNotifier<double>? prefix,
  ValueNotifier<double>? height,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 240,
          height: 200,
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              DStickySliver(
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: prefix == null
                          ? const SizedBox(height: 100)
                          : ValueListenableBuilder(
                              valueListenable: prefix,
                              builder: (_, value, _) => SizedBox(height: value),
                            ),
                    ),
                    SliverToBoxAdapter(
                      child: RepaintBoundary(
                        child: height == null
                            ? SizedBox(
                                height: 300,
                                child: DSticky(topOffset: 12, child: child),
                              )
                            : ValueListenableBuilder(
                                valueListenable: height,
                                child: DSticky(topOffset: 12, child: child),
                                builder: (_, value, child) =>
                                    SizedBox(height: value, child: child),
                              ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 500)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

class _Counts {
  int builds = 0;
  int layouts = 0;
  int paints = 0;
  double? paintedTop;
}

class _Probe extends StatelessWidget {
  const _Probe({required this.counts});
  final _Counts counts;

  @override
  Widget build(BuildContext context) {
    counts.builds++;
    return _PaintProbe(counts);
  }
}

class _PaintProbe extends LeafRenderObjectWidget {
  const _PaintProbe(this.counts);
  final _Counts counts;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderProbe(counts);
}

class _RenderProbe extends RenderBox {
  _RenderProbe(this.counts);
  final _Counts counts;

  @override
  void performLayout() {
    counts.layouts++;
    size = constraints.constrain(const Size.square(32));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    counts.paints++;
    counts.paintedTop = localToGlobal(Offset.zero).dy;
  }
}
