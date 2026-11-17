import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {TargetPlatform platform = TargetPlatform.macOS}) =>
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: Center(child: SizedBox(width: 200, height: 180, child: child)),
        ),
      );
  testWidgets('page scrollbar clears its header while nested bars stay local', (
    tester,
  ) async {
    final scroll = ScrollController();
    final nestedScroll = ScrollController();
    addTearDown(scroll.dispose);
    addTearDown(nestedScroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: DPageSurface.scrollable(
          framed: false,
          hideHeaderOnScroll: true,
          header: const SizedBox(height: 80),
          bodyBuilder: (_, header) => DScrollBar(
            controller: scroll,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverToBoxAdapter(child: header.spacer),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: DScrollArea(
                      controller: nestedScroll,
                      child: const SizedBox(height: 1000),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final painters = tester
        .widgetList<CustomPaint>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.foregroundPainter is ScrollbarPainter,
          ),
        )
        .map((widget) => widget.foregroundPainter! as ScrollbarPainter)
        .toList();
    expect(painters, hasLength(2));
    expect(painters.first.padding.resolve(TextDirection.ltr).top, 80);
    expect(painters.last.padding.resolve(TextDirection.ltr).top, 0);
    expect(
      painters.first.hitTestOnlyThumbInteractive(
        const Offset(796, 88),
        PointerDeviceKind.mouse,
      ),
      isTrue,
    );
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(400, 400),
        scrollDelta: Offset(0, 160),
      ),
    );
    await tester.pumpAndSettle();
    expect(painters.first.padding.resolve(TextDirection.ltr).top, 0);
    expect(painters.last.padding.resolve(TextDirection.ltr).top, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phones scroll with no visible or interactive scrollbar',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          DScrollArea(
            controller: controller,
            child: const SizedBox(height: 1000),
          ),
          platform: defaultTargetPlatform,
        ),
      );
      await tester.pumpAndSettle();
      final thumb = tester.widget<RawScrollbar>(
        find.byWidgetPredicate((widget) => widget is RawScrollbar),
      );
      expect(thumb.thumbVisibility, isFalse);
      expect(thumb.interactive, isFalse);
      expect(thumb.thumbColor, Colors.transparent);
      final viewport = find.byType(SingleChildScrollView);
      final bounds = tester.getRect(viewport);
      await tester.tapAt(bounds.topRight + const Offset(-4, 130));
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      await tester.drag(viewport, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('touch scrollbar gestures stay inside the painted track', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        DScrollArea(
          controller: controller,
          child: const SizedBox(height: 1000),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paint = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter,
    );
    final painter =
        tester.widget<CustomPaint>(paint).foregroundPainter!
            as ScrollbarPainter;
    final bounds = tester.getRect(paint);
    for (final kind in [
      PointerDeviceKind.mouse,
      PointerDeviceKind.touch,
      PointerDeviceKind.trackpad,
    ]) {
      expect(painter.hitTestInteractive(const Offset(184, 100), kind), isFalse);
      expect(painter.hitTestInteractive(const Offset(192, 100), kind), isFalse);
      expect(painter.hitTestInteractive(const Offset(198, 100), kind), isFalse);
      expect(
        painter.hitTestOnlyThumbInteractive(const Offset(184, 10), kind),
        isFalse,
      );
      expect(painter.hitTestInteractive(const Offset(196, 100), kind), isTrue);
      expect(
        painter.hitTestOnlyThumbInteractive(const Offset(196, 10), kind),
        isTrue,
      );
    }
    await tester.tapAt(bounds.topLeft + const Offset(184, 100));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    await tester.tapAt(bounds.topLeft + const Offset(196, 100));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });
  testWidgets(
    'faded thumbs reappear when a mouse hovers only the painted band',
    (tester) async {
      for (final direction in TextDirection.values) {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          host(
            Directionality(
              textDirection: direction,
              child: DScrollArea(
                key: ValueKey(direction),
                controller: controller,
                thumbVisibility: false,
                child: const SizedBox(height: 1000),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paint = find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is ScrollbarPainter,
        );
        final opacity =
            (tester.widget<CustomPaint>(paint).foregroundPainter!
                    as ScrollbarPainter)
                .fadeoutOpacityAnimation;
        final bounds = tester.getRect(paint);
        // The 4px band sits 3px inside the 200px-wide area's trailing edge.
        Offset at(double x) =>
            bounds.topLeft +
            Offset(direction == TextDirection.ltr ? x : 200 - x, 100);
        expect(opacity.value, 0);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: at(100));
        // Flutter's faded hover target spans 48px around the thumb and its
        // track includes the unpainted margins on both sides of the band.
        for (final x in [184.0, 192.0, 198.0]) {
          await mouse.moveTo(at(x));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(opacity.value, 0, reason: '$direction x=$x is off the band');
        }
        await mouse.moveTo(at(196));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(opacity.value, 1, reason: '$direction hover reveals the thumb');

        await mouse.down(at(196) - const Offset(0, 90));
        await mouse.moveBy(const Offset(0, 60));
        await mouse.up();
        await mouse.removePointer();
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(0));
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  // Reads pixels of a RepaintBoundary, at [ratio] device pixels per point.
  Future<List<Color>> pixelsAt(
    WidgetTester tester,
    GlobalKey boundary,
    List<Offset> points, {
    double ratio = 1,
  }) async => (await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: ratio);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final colors = [
      for (final point in points)
        () {
          final rgba = bytes.getUint32(
            ((point.dy * ratio).floor() * image.width +
                    (point.dx * ratio).floor()) *
                4,
          );
          return Color.fromARGB(
            rgba & 0xff,
            rgba >> 24,
            (rgba >> 16) & 0xff,
            (rgba >> 8) & 0xff,
          );
        }(),
    ];
    image.dispose();
    return colors;
  }))!;

  Matcher drawn(Color expected, {String? reason}) => predicate<Color>(
    (color) =>
        (color.r - expected.r).abs() * 255 <= 2 &&
        (color.g - expected.g).abs() * 255 <= 2 &&
        (color.b - expected.b).abs() * 255 <= 2,
    'within 2 of $expected',
  );

  Color thumbOn(Color background, Color ink, {bool active = false}) =>
      Color.alphaBlend(ink.withValues(alpha: active ? .36 : .24), background);

  testWidgets(
    'automatic desktop scrollbars are a thumb with no track on hover',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final boundaryKey = GlobalKey();
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final direction in TextDirection.values) {
          final tokens = theme.extension<DTokens>()!;
          final background = tokens.background;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(platform: TargetPlatform.macOS),
              home: Directionality(
                textDirection: direction,
                child: Center(
                  child: SizedBox(
                    width: 200,
                    height: 180,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: ColoredBox(
                        color: background,
                        child: ListView(
                          controller: controller,
                          children: const [SizedBox(height: 2000)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(Scrollbar), findsOneWidget);
          final rect = tester.getRect(find.byKey(boundaryKey));
          double x(double fromEnd) =>
              direction == TextDirection.ltr ? 200 - fromEnd : fromEnd;
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: rect.topLeft + Offset(x(50), 10));
          await mouse.moveTo(rect.topLeft + Offset(x(5), 10));
          controller.jumpTo(controller.offset == 0 ? 10 : 0);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          final pixels = await pixelsAt(tester, boundaryKey, [
            Offset(x(2.75), 10),
            Offset(x(5), 10),
            Offset(x(5), 150),
          ], ratio: 2);
          expect(
            pixels[0],
            drawn(background),
            reason: 'The full 3px inset stays clear at 2x scale',
          );
          expect(
            pixels[1],
            drawn(thumbOn(background, tokens.foreground, active: true)),
            reason: 'The hovered thumb is the ink at 36%',
          );
          expect(
            pixels[2],
            drawn(background),
            reason: 'No track is drawn under a hovered scrollbar',
          );
          await mouse.removePointer();
        }
      }
    },
  );

  testWidgets('thumbs are the ink at 24% on any surface and keep a 3px inset', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final boundaryKey = GlobalKey();
    final ink = AppTheme.light.extension<DTokens>()!.foreground;
    for (final direction in TextDirection.values) {
      for (final background in [
        Colors.white,
        Colors.black,
        const Color(0xff777777),
        const Color(0xff173852),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Center(
              child: SizedBox(
                width: 200,
                height: 180,
                child: Directionality(
                  textDirection: direction,
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: ColoredBox(
                      color: background,
                      child: DScrollArea(
                        controller: controller,
                        axes: DScrollAxes.both,
                        child: const SizedBox(width: 1000, height: 1000),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        double x(double fromEnd) =>
            direction == TextDirection.ltr ? 200 - fromEnd : fromEnd;
        final pixels = await pixelsAt(tester, boundaryKey, [
          Offset(x(2.5), 20),
          Offset(x(5), 20),
          Offset(x(5), 170),
          const Offset(100, 177.5),
          Offset(x(180), 175),
        ]);
        expect(pixels[0], drawn(background), reason: 'Clear vertical edge');
        expect(
          pixels[1],
          drawn(thumbOn(background, ink)),
          reason: 'The vertical thumb is the ink at 24%',
        );
        expect(pixels[2], drawn(background), reason: 'No vertical track');
        expect(pixels[3], drawn(background), reason: 'Clear bottom edge');
        expect(
          pixels[4],
          isNot(drawn(background)),
          reason: 'The horizontal thumb inside the inset',
        );
      }
    }
  });

  testWidgets(
    'a kit thumb darkens under the pointer and while dragged, with no track',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final boundaryKey = GlobalKey();
      final tokens = AppTheme.dark.extension<DTokens>()!;
      final background = tokens.background;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: Center(
            child: SizedBox(
              width: 200,
              height: 180,
              child: RepaintBoundary(
                key: boundaryKey,
                child: ColoredBox(
                  color: background,
                  child: DScrollArea(
                    controller: controller,
                    child: const SizedBox(height: 1000),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(boundaryKey));
      final rest = thumbOn(background, tokens.foreground);
      final active = thumbOn(background, tokens.foreground, active: true);
      Future<List<Color>> sample(double thumbY) => pixelsAt(
        tester,
        boundaryKey,
        [Offset(195, thumbY), const Offset(195, 160), Offset(198.5, thumbY)],
      );

      var pixels = await sample(10);
      expect(pixels[0], drawn(rest), reason: 'At rest, the ink at 24%');

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.topLeft + const Offset(150, 10));
      await mouse.moveTo(rect.topLeft + const Offset(195, 10));
      await tester.pump();
      pixels = await sample(10);
      expect(pixels[0], drawn(active), reason: 'Hovered, the ink at 36%');
      expect(pixels[1], drawn(background), reason: 'No track on hover');
      expect(pixels[2], drawn(background), reason: 'Gutter clear on hover');

      await mouse.moveTo(rect.topLeft + const Offset(195, 120));
      await tester.pump();
      pixels = await sample(10);
      expect(pixels[0], drawn(rest), reason: 'Off the thumb, back to 24%');

      await mouse.moveTo(rect.topLeft + const Offset(195, 10));
      await mouse.down(rect.topLeft + const Offset(195, 10));
      await tester.pump();
      await mouse.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(controller.offset, greaterThan(0));
      pixels = await sample(50);
      expect(pixels[0], drawn(active), reason: 'Dragged, the ink at 36%');
      expect(pixels[1], drawn(background), reason: 'No track while dragged');

      await mouse.up();
      await mouse.moveTo(rect.topLeft + const Offset(100, 100));
      await tester.pump();
      pixels = await sample(50);
      expect(pixels[0], drawn(rest), reason: 'Let go and left, back to 24%');
      await mouse.removePointer();
    },
  );

  testWidgets(
    'hidden scrollbars preserve touch, keyboard and position when shown again',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var showScrollbar = false;
      Widget area() => DScrollArea(
        controller: controller,
        showScrollbar: showScrollbar,
        child: const SizedBox(height: 1000, child: Text('Content')),
      );
      await tester.pumpWidget(host(area()));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      final offset = controller.offset;
      await tester.pumpWidget(host(area()));
      expect(controller.offset, offset);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(controller.offset, controller.position.maxScrollExtent);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      controller.jumpTo(200);
      final position = controller.position;
      showScrollbar = true;
      await tester.pumpWidget(host(area()));
      await tester.pumpAndSettle();
      expect(controller.position, same(position));
      expect(controller.offset, 200);
      await tester.pumpWidget(const SizedBox());
      expect(controller.hasClients, isFalse);
      controller.addListener(() {});
    },
  );

  testWidgets(
    'controller replacement detaches borrowed resources and RTL starts at the right edge',
    (tester) async {
      final first = ScrollController();
      final second = ScrollController(initialScrollOffset: 40);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget area(ScrollController controller) => Directionality(
        textDirection: TextDirection.rtl,
        child: DScrollArea(
          axes: DScrollAxes.horizontal,
          controller: controller,
          child: const SizedBox(
            width: 1000,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Start'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(area(first)));
      expect(
        tester.getRect(find.text('Start')).right,
        tester.getRect(find.byType(DScrollArea)).right,
      );
      first.jumpTo(60);
      await tester.pumpWidget(host(area(second)));
      expect(first.hasClients, isFalse);
      expect(second.offset, 60);
      await tester.pumpWidget(host(const DScrollArea(child: Text('Owned'))));
      expect(second.hasClients, isFalse);
      first.addListener(() {});
      second.addListener(() {});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'nonoverflow skips only the root and overflow transitions preserve child editing and traversal',
    (tester) async {
      final before = FocusNode();
      final editor = FocusNode();
      final button = FocusNode();
      final after = FocusNode();
      final text = TextEditingController(text: 'Retained');
      final scroll = ScrollController();
      for (final node in [before, editor, button, after]) {
        addTearDown(node.dispose);
      }
      addTearDown(text.dispose);
      addTearDown(scroll.dispose);
      var presses = 0;
      Widget scene(double contentHeight, {double viewportHeight = 180}) =>
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  DButton(
                    focusNode: before,
                    label: const Text('Before'),
                    onPressed: () {},
                  ),
                  SizedBox(
                    width: 240,
                    height: viewportHeight,
                    child: DScrollArea(
                      controller: scroll,
                      child: SizedBox(
                        height: contentHeight,
                        child: Column(
                          children: [
                            TextField(focusNode: editor, controller: text),
                            DButton(
                              focusNode: button,
                              label: const Text('Child'),
                              onPressed: () => presses++,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  DButton(
                    focusNode: after,
                    label: const Text('After'),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          );
      await tester.pumpWidget(scene(120));
      await tester.pumpAndSettle();
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'Kept through resize');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(text.selection.baseOffset, text.text.length - 1);
      expect(scroll.offset, 0);
      final selection = text.selection;
      await tester.pumpWidget(scene(700));
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      expect(text.text, 'Kept through resize');
      expect(text.selection, selection);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(button.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(presses, 1);
      final childOffset = scroll.offset;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(presses, 2);
      expect(scroll.offset, childOffset);
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      final rootFocus = FocusManager.instance.primaryFocus;
      await tester.pumpWidget(scene(120));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(rootFocus));
      expect(scroll.offset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(scene(120, viewportHeight: 80));
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(scroll.offset, 40);
      await tester.pumpWidget(scene(120));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      before.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(editor.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'Space pages down, Shift Space pages up and modified keys bubble',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final bubbled = <LogicalKeyboardKey>[];
      await tester.pumpWidget(
        host(
          Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  [
                    LogicalKeyboardKey.space,
                    LogicalKeyboardKey.arrowDown,
                  ].contains(event.logicalKey)) {
                bubbled.add(event.logicalKey);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: DScrollArea(
              controller: controller,
              child: const SizedBox(height: 1000),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.offset, 162);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(bubbled, isEmpty);
      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.shiftLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        if (modifier != LogicalKeyboardKey.shiftLeft) {
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
        }
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(
        bubbled.where((key) => key == LogicalKeyboardKey.arrowDown).length,
        4,
      );
      expect(bubbled.where((key) => key == LogicalKeyboardKey.space).length, 3);
    },
  );
  testWidgets(
    'focus ring paints only outside transparent content and multiplies token alpha',
    (tester) async {
      const background = Color(0xff204060);
      final key = GlobalKey();
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
        ).copyWith(primary: const Color(0x80ff0000)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(
                color: background,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: DScrollArea(child: SizedBox(height: 500)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<List<int>> pixel(int x, int y) async =>
          (await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final offset = (y * image.width + x) * 4;
            final result = bytes!.buffer.asUint8List().sublist(
              offset,
              offset + 4,
            );
            image.dispose();
            return result;
          }))!;
      expect(await pixel(50, 50), [32, 64, 96, 255]);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(await pixel(50, 50), [32, 64, 96, 255]);
      final ring = await pixel(8, 50);
      // Existing 50% alpha multiplied by ring 50% gives a 25% red blend.
      expect(ring[0], closeTo(88, 1));
      expect(ring[1], closeTo(48, 1));
      expect(ring[2], closeTo(72, 1));
      expect(await pixel(6, 50), [32, 64, 96, 255]);
    },
  );

  testWidgets('focused descendants do not outline the scroll viewport', (
    tester,
  ) async {
    const background = Color(0xff204060);
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    final boundaryKey = GlobalKey();
    final childFocus = FocusNode();
    addTearDown(childFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red,
          ).copyWith(primary: const Color(0xffff0000)),
        ),
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: background,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: DScrollArea(
                    child: SizedBox(
                      height: 500,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: DSidebarMenuButton(
                          focusNode: childFocus,
                          onPressed: _noop,
                          child: const Text('Section'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<List<int>> pixel(
      int x,
      int y,
    ) async => (await tester.runAsync(() async {
      final image =
          await (boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (y * image.width + x) * 4;
      final result = bytes!.buffer.asUint8List().sublist(offset, offset + 4);
      image.dispose();
      return result;
    }))!;

    await tester.tap(find.text('Section'));
    await tester.pumpAndSettle();
    expect(childFocus.hasPrimaryFocus, isTrue);
    expect(await pixel(8, 50), [32, 64, 96, 255]);
  });
}

void _noop() {}
