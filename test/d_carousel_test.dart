import 'dart:ui' show PointerDeviceKind, SemanticsRole;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final selected = <DCarouselController, int>{};
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

    ValueChanged<int>? onSelected,
    VoidCallback? onStart,
    VoidCallback? onEnd,
    double fraction = 1,
    FocusNode? focusNode,
    double width = 300,
  }) => SizedBox(
    width: width,
    height: axis == Axis.horizontal ? 140 : 240,
    child: DCarousel(
      controller: controller,

      loop: loop,

      semanticLabel: 'Highlights',

      onSelected: (index) {
        if (controller != null) selected[controller] = index;
        onSelected?.call(index);
      },

      children: [
        DCarouselContent(
          height: axis == Axis.horizontal ? 140 : 240,

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

  testWidgets('controller and controls match bounded snaps', (tester) async {
    final controller = DCarouselController();
    addTearDown(controller.dispose);
    final changes = <int>[];

    await tester.pumpWidget(
      host(carousel(controller: controller, onSelected: changes.add)),
    );
    expect(
      tester
          .widget<DCarouselContent>(find.byType(DCarouselContent))
          .children
          .length,
      3,
    );
    expect((selected[controller] ?? 0), 0);
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
    expect((selected[controller] ?? 0), 1);
    expect(changes, [1]);

    await controller.select(2, animated: false);
    await tester.pump();
    expect((selected[controller] ?? 0), 2);
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
      tester.getSemantics(find.bySemanticsLabel('Highlights')).role,
      SemanticsRole.region,
    );
    expect(
      tester.getSemantics(find.text('Slide 1')).label,
      contains('Slide 1 of 3'),
    );
    await tester.drag(
      find.byKey(const ValueKey('d-carousel-viewport')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect((selected[controller] ?? 0), 1);
    expect((selected[controller] ?? 0) / 2, greaterThan(0));

    final mouse = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('d-carousel-viewport'))),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-260, 0));
    await mouse.up();
    await tester.pumpAndSettle();
    expect((selected[controller] ?? 0), 2);
    semantics.dispose();
  });

  testWidgets('keyboard follows horizontal RTL direction', (tester) async {
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
    Focus.of(tester.element(find.text('Slide 1'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(selected[rtl], 1);
    expect(find.byIcon(Icons.chevron_left), findsNothing);

    await tester.pumpWidget(const SizedBox());
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

    final previous = controller.previous();
    await tester.pumpAndSettle();
    await previous;
    expect((selected[controller] ?? 0), 2);
    expect(physicalPage(), initialPage - 1);
    expect((selected[controller] ?? 0) / 2, 1);

    final next = controller.next();
    await tester.pumpAndSettle();
    await next;
    expect((selected[controller] ?? 0), 0);
    expect(physicalPage(), initialPage);
    expect((selected[controller] ?? 0) / 2, 0);

    await tester.drag(
      find.byKey(const ValueKey('d-carousel-viewport')),
      const Offset(260, 0),
    );
    await tester.pumpAndSettle();
    expect((selected[controller] ?? 0), 2);
    expect(physicalPage(), initialPage - 1);

    await tester.drag(
      find.byKey(const ValueKey('d-carousel-viewport')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect((selected[controller] ?? 0), 0);
    expect(physicalPage(), initialPage);
  });

  testWidgets('resizing preserves selection', (tester) async {
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
              child: carousel(controller: controller, width: width),
            );
          },
        ),
      ),
    );
    await controller.select(1, animated: false);
    await tester.pump();
    update(() => width = 440);
    await tester.pump();
    expect((selected[controller] ?? 0), 1);
    expect(
      tester
          .widget<PageView>(find.byType(PageView))
          .controller!
          .viewportFraction,
      1.0,
    );
  });

  testWidgets('borrowed controller remains usable after removal', (
    tester,
  ) async {
    final controller = DCarouselController();

    await tester.pumpWidget(host(carousel(controller: controller)));
    await tester.pumpWidget(const SizedBox());

    expect(() => controller.addListener(() {}), returnsNormally);

    controller.dispose();
  });
}
