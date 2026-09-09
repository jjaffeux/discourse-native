import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    Widget child, {
    TextDirection direction = TextDirection.ltr,
    bool reducedMotion = false,
    Size size = const Size(500, 300),
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );

  Widget carousel({
    DCarouselController? controller,
    Axis axis = Axis.horizontal,
    bool loop = false,
    List<DCarouselPlugin> plugins = const [],
    ValueChanged<int>? onSelected,
    VoidCallback? onStart,
    VoidCallback? onEnd,
    double fraction = 1,
    DCarouselExtentResolver? resolver,
    FocusNode? focusNode,
    double width = 300,
  }) => SizedBox(
    width: width,
    height: axis == Axis.horizontal ? 140 : 240,
    child: DCarousel(
      controller: controller,
      orientation: axis,
      loop: loop,
      plugins: plugins,
      semanticLabel: 'Highlights',
      focusNode: focusNode,
      onSelected: onSelected,
      onScrollStart: onStart,
      onScrollEnd: onEnd,
      children: [
        DCarouselContent(
          height: axis == Axis.horizontal ? 140 : 240,
          extentFraction: fraction,
          extentResolver: resolver,
          children: const [
            DCarouselItem(child: Text('Slide 1')),
            DCarouselItem(child: Text('Slide 2')),
            DCarouselItem(child: Text('Slide 3')),
          ],
        ),
        const DCarouselPrevious(),
        const DCarouselNext(),
      ],
    ),
  );

  testWidgets('controller, controls and event state match bounded snaps', (
    tester,
  ) async {
    final controller = DCarouselController();
    addTearDown(controller.dispose);
    final selected = <int>[];
    var starts = 0, ends = 0;
    await tester.pumpWidget(
      host(
        carousel(
          controller: controller,
          onSelected: selected.add,
          onStart: () => starts++,
          onEnd: () => ends++,
        ),
      ),
    );
    expect(controller.itemCount, 3);
    expect(controller.selectedIndex, 0);
    expect(controller.canScrollPrevious, isFalse);
    expect(controller.canScrollNext, isTrue);
    expect(
      tester
          .widget<DButton>(find.byKey(const ValueKey('d-carousel-previous')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('d-carousel-next')));
    await tester.pumpAndSettle();
    expect(controller.selectedIndex, 1);
    expect(selected, [1]);
    expect(starts, 1);
    expect(ends, 1);

    await controller.select(2, animated: false);
    await tester.pump();
    expect(controller.selectedIndex, 2);
    expect(controller.canScrollNext, isFalse);
  });

  testWidgets('renders minimal track', (tester) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 300,
          height: 140,
          child: DCarousel(
            children: [
              DCarouselContent(
                height: 140,
                children: [DCarouselItem(child: Text('Only'))],
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Only'), findsOneWidget);
  });

  testWidgets('renders navigation', (tester) async {
    await tester.pumpWidget(host(carousel()));
    expect(find.text('Slide 1'), findsOneWidget);
  });

  testWidgets('drag snaps, reports progress and exposes slide semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = DCarouselController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(carousel(controller: controller)));
    expect(find.bySemanticsLabel('Highlights'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Slide 1')).label,
      contains('Slide 1 of 3'),
    );
    await tester.drag(
      find.byKey(const ValueKey('d-carousel-viewport')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedIndex, 1);
    expect(controller.scrollProgress, greaterThan(0));
    semantics.dispose();
  });

  testWidgets('keyboard follows horizontal RTL and vertical direction', (
    tester,
  ) async {
    final rtl = DCarouselController();
    final rtlFocus = FocusNode();
    addTearDown(rtl.dispose);
    addTearDown(rtlFocus.dispose);
    await tester.pumpWidget(
      host(
        carousel(controller: rtl, focusNode: rtlFocus),
        direction: TextDirection.rtl,
      ),
    );
    rtlFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(rtl.selectedIndex, 1);
    expect(find.byIcon(Icons.chevron_left), findsNothing);

    await tester.pumpWidget(const SizedBox());

    final vertical = DCarouselController();
    final verticalFocus = FocusNode();
    addTearDown(vertical.dispose);
    addTearDown(verticalFocus.dispose);
    await tester.pumpWidget(
      host(
        carousel(
          controller: vertical,
          axis: Axis.vertical,
          focusNode: verticalFocus,
        ),
      ),
    );
    verticalFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(vertical.selectedIndex, 1);
  });

  testWidgets('loop wraps through adjacent pages in both directions', (
    tester,
  ) async {
    final controller = DCarouselController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(carousel(controller: controller, loop: true)));
    expect(controller.canScrollPrevious, isTrue);
    final pageController = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    double physicalPage() => (pageController.position as PageMetrics).page!;
    final initialPage = physicalPage();

    await controller.previous(animated: false);
    await tester.pump();
    expect(controller.selectedIndex, 2);
    expect(physicalPage(), initialPage - 1);
    expect(controller.scrollProgress, 1);

    await controller.next(animated: false);
    await tester.pump();
    expect(controller.selectedIndex, 0);
    expect(physicalPage(), initialPage);
    expect(controller.scrollProgress, 0);

    await tester.drag(
      find.byKey(const ValueKey('d-carousel-viewport')),
      const Offset(260, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedIndex, 2);
    expect(physicalPage(), initialPage - 1);

    await tester.drag(
      find.byKey(const ValueKey('d-carousel-viewport')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedIndex, 0);
    expect(physicalPage(), initialPage);
  });

  testWidgets('responsive extent recomputes without resetting selection', (
    tester,
  ) async {
    final controller = DCarouselController();
    addTearDown(controller.dispose);
    var width = 320.0;
    late StateSetter update;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return SizedBox(
              width: width,
              child: carousel(
                controller: controller,
                width: width,
                resolver: (available) => available < 300 ? .5 : 1 / 3,
              ),
            );
          },
        ),
      ),
    );
    await controller.select(1, animated: false);
    await tester.pump();
    update(() => width = 440);
    await tester.pump();
    expect(controller.selectedIndex, 1);
    expect(
      tester
          .widget<PageView>(find.byType(PageView))
          .controller!
          .viewportFraction,
      closeTo(1 / 3, .001),
    );
  });

  testWidgets(
    'autoplay advances, interaction stops and reduced motion suppresses',
    (tester) async {
      final controller = DCarouselController();
      final autoplay = DCarouselAutoplay(
        delay: const Duration(milliseconds: 500),
      );
      addTearDown(controller.dispose);
      addTearDown(autoplay.dispose);
      await tester.pumpWidget(
        host(carousel(controller: controller, loop: true, plugins: [autoplay])),
      );
      await controller.select(2, animated: false);
      await tester.pump();
      final pageController = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      double physicalPage() => (pageController.position as PageMetrics).page!;
      final lastPage = physicalPage();
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.selectedIndex, 0);
      expect(physicalPage(), lastPage + 1);
      autoplay.onInteraction();
      final stoppedAt = controller.selectedIndex;
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.selectedIndex, stoppedAt);

      await tester.pumpWidget(
        host(
          carousel(controller: controller, loop: true, plugins: [autoplay]),
          reducedMotion: true,
        ),
      );
      autoplay.play();
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.selectedIndex, stoppedAt);
    },
  );

  testWidgets('borrowed controller and plugin remain usable after removal', (
    tester,
  ) async {
    final controller = DCarouselController();
    final plugin = _ProbePlugin();
    await tester.pumpWidget(
      host(carousel(controller: controller, plugins: [plugin])),
    );
    await tester.pumpWidget(const SizedBox());
    expect(plugin.detaches, 1);
    expect(() => controller.addListener(() {}), returnsNormally);
    expect(plugin.disposed, isFalse);
    plugin.dispose();
    controller.dispose();
  });
}

class _ProbePlugin extends DCarouselPlugin {
  int detaches = 0;
  bool disposed = false;
  @override
  void attach(DCarouselController controller, BuildContext context) {}
  @override
  void detach() => detaches++;
  @override
  void dispose() => disposed = true;
}
