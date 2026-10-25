import 'dart:ui' show PointerDeviceKind, SemanticsRole;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
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
    bool loop = false,
    ValueChanged<int>? onSelected,
    double width = 300,
  }) => SizedBox(
    width: width,
    height: 140,
    child: DCarousel(
      controller: controller,

      loop: loop,

      semanticLabel: 'Highlights',

      onSelected: (index) {
        if (controller != null) selected[controller] = index;
        onSelected?.call(index);
      },

      children: const [
        DCarouselContent(
          height: 140,

          children: [
            DCarouselItem(child: Text('Slide 1')),
            DCarouselItem(child: Text('Slide 2')),
            DCarouselItem(child: Text('Slide 3')),
          ],
        ),
        DCarouselPrevious(),
        DCarouselNext(),
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

  testWidgets('owned controller navigates and respects track boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(host(carousel()));
    final previous = find.byKey(const ValueKey('d-carousel-previous'));
    final next = find.byKey(const ValueKey('d-carousel-next'));
    expect(find.text('Slide 1').hitTestable(), findsOneWidget);
    expect(tester.widget<DButton>(previous).onPressed, isNull);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Slide 2').hitTestable(), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Slide 3').hitTestable(), findsOneWidget);
    expect(tester.widget<DButton>(next).onPressed, isNull);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Slide 2').hitTestable(), findsOneWidget);
  });

  testWidgets('drag snaps and exposes slide semantics', (tester) async {
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

  for (final direction in TextDirection.values) {
    testWidgets('keyboard follows $direction with matching navigation icons', (
      tester,
    ) async {
      final controller = DCarouselController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(carousel(controller: controller), direction: direction),
      );
      final rtl = direction == TextDirection.rtl;
      final previous = tester.widget<DButton>(
        find.byKey(const ValueKey('d-carousel-previous')),
      );
      final next = tester.widget<DButton>(
        find.byKey(const ValueKey('d-carousel-next')),
      );
      expect(
        (previous.icon as DIcon).icon,
        rtl ? DIcons.chevronRight : DIcons.chevronLeft,
      );
      expect(
        (next.icon as DIcon).icon,
        rtl ? DIcons.chevronLeft : DIcons.chevronRight,
      );
      Focus.of(tester.element(find.text('Slide 1'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(
        rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
      );
      await tester.pumpAndSettle();
      expect(selected[controller], 1);
      expect(find.text('Slide 2').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(
        rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft,
      );
      await tester.pumpAndSettle();
      expect(selected[controller], 0);
      expect(find.text('Slide 1').hitTestable(), findsOneWidget);
    });
  }

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

    final next = controller.next();
    await tester.pumpAndSettle();
    await next;
    expect((selected[controller] ?? 0), 0);
    expect(physicalPage(), initialPage);

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
    expect(find.text('Slide 2').hitTestable(), findsOneWidget);
    update(() => width = 440);
    await tester.pump();
    expect((selected[controller] ?? 0), 1);
    expect(find.text('Slide 2').hitTestable(), findsOneWidget);
    expect(find.text('Slide 1').hitTestable(), findsNothing);
    expect(find.text('Slide 3').hitTestable(), findsNothing);
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
