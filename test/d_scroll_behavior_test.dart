import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _ground = Color(0xff224466);
const _ink = Color(0xffee8844);

Future<List<int>> _pixel(
  WidgetTester tester,
  GlobalKey key,
  int y, {
  int x = 50,
}) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final index = (y * image.width + x) * 4;
    final pixel = [
      for (var channel = 0; channel < 4; channel++)
        data.getUint8(index + channel),
    ];
    image.dispose();
    return pixel;
  }))!;
}

void _expectInk(List<int> pixel, double opacity) {
  final color = Color.lerp(_ground, _ink, opacity)!;
  expect(pixel[0], closeTo(color.r * 255, 3));
  expect(pixel[1], closeTo(color.g * 255, 3));
  expect(pixel[2], closeTo(color.b * 255, 3));
  expect(pixel[3], 255);
}

Widget _host(
  GlobalKey key,
  Widget child, {
  double height = 180,
  bool nativeBehavior = true,
}) => MaterialApp(
  scrollBehavior: nativeBehavior ? const DScrollBehavior() : null,
  home: Center(
    child: SizedBox(
      width: 200,
      height: height,
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(color: _ground, child: child),
      ),
    ),
  ),
);

Widget _list(ScrollController scroll, {bool reverse = false, int count = 30}) =>
    ListView.builder(
      controller: scroll,
      reverse: reverse,
      padding: EdgeInsets.zero,
      itemExtent: 30,
      itemCount: count,
      itemBuilder: (_, index) => const ColoredBox(color: _ink),
    );

void main() {
  for (final direction in TextDirection.values) {
    for (final reverse in [false, true]) {
      testWidgets('opt-in horizontal fades follow physical edges in '
          '$direction, reverse=$reverse', (tester) async {
        final key = GlobalKey();
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          _host(
            key,
            Directionality(
              textDirection: direction,
              child: DScrollFadeScope(
                horizontalExtent: 30,
                child: SingleChildScrollView(
                  controller: scroll,
                  scrollDirection: Axis.horizontal,
                  reverse: reverse,
                  child: const SizedBox(
                    width: 1000,
                    height: 180,
                    child: ColoredBox(color: _ink),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final leftward = scroll.position.axisDirection == AxisDirection.left;
        _expectInk(await _pixel(tester, key, 90, x: 0), leftward ? .5 / 30 : 1);
        _expectInk(
          await _pixel(tester, key, 90, x: 199),
          leftward ? 1 : .5 / 30,
        );
        // Horizontal fades do not borrow the vertical top/bottom geometry.
        _expectInk(await _pixel(tester, key, 0, x: 100), 1);
        scroll.jumpTo(150);
        await tester.pumpAndSettle();
        _expectInk(await _pixel(tester, key, 90, x: 0), .5 / 30);
        _expectInk(await _pixel(tester, key, 90, x: 15), 15.5 / 30);
        _expectInk(await _pixel(tester, key, 90, x: 30), 1);
        _expectInk(await _pixel(tester, key, 90, x: 184), 15.5 / 30);
        _expectInk(await _pixel(tester, key, 90, x: 199), .5 / 30);
        scroll.jumpTo(scroll.position.maxScrollExtent - 1);
        await tester.pumpAndSettle();
        _expectInk(await _pixel(tester, key, 90, x: 0), leftward ? 1 : .5 / 30);
        _expectInk(
          await _pixel(tester, key, 90, x: 199),
          leftward ? .5 / 30 : 1,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('horizontal fades update after resize and content changes '
      'without consuming edge hits', (tester) async {
    final key = GlobalKey();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var contentWidth = 600.0;
    var width = 200.0;
    var taps = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return SizedBox(
                width: width,
                height: 180,
                child: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: _ground,
                    child: DScrollFadeScope(
                      horizontalExtent: 30,
                      child: DScrollArea(
                        controller: scroll,
                        axes: DScrollAxes.horizontal,
                        showScrollbar: false,
                        child: Listener(
                          onPointerDown: (_) => taps++,
                          child: SizedBox(
                            width: contentWidth,
                            height: 180,
                            child: const ColoredBox(color: _ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final position = scroll.position;
    _expectInk(await _pixel(tester, key, 90, x: 199), .5 / 30);
    scroll.jumpTo(100);
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byKey(key));
    await tester.tapAt(bounds.centerLeft + const Offset(1, 0));
    await tester.tapAt(bounds.centerRight - const Offset(1, 0));
    expect(taps, 2);
    update(() => contentWidth = 200);
    await tester.pumpAndSettle();
    _expectInk(await _pixel(tester, key, 90, x: 0), 1);
    _expectInk(await _pixel(tester, key, 90, x: 199), 1);
    update(() => width = 100);
    await tester.pumpAndSettle();
    _expectInk(await _pixel(tester, key, 90, x: 99), .5 / 30);
    update(() => width = 200);
    await tester.pumpAndSettle();
    _expectInk(await _pixel(tester, key, 90, x: 199), 1);
    expect(scroll.position, same(position));
    expect(tester.takeException(), isNull);
  });

  for (final reverse in [false, true]) {
    testWidgets(
      'fades only continuing physical edges, reverse=$reverse',
      (tester) async {
        final key = GlobalKey();
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(_host(key, _list(scroll, reverse: reverse)));
        await tester.pumpAndSettle();
        _expectInk(await _pixel(tester, key, 0), reverse ? .5 / 14 : 1);
        _expectInk(await _pixel(tester, key, 179), reverse ? 1 : .5 / 20);
        scroll.jumpTo(150);
        await tester.pumpAndSettle();
        _expectInk(await _pixel(tester, key, 0), .5 / 14);
        _expectInk(await _pixel(tester, key, 7), 7.5 / 14);
        _expectInk(await _pixel(tester, key, 90), 1);
        _expectInk(await _pixel(tester, key, 170), 9.5 / 20);
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        _expectInk(await _pixel(tester, key, 0), reverse ? 1 : .5 / 14);
        _expectInk(await _pixel(tester, key, 179), reverse ? .5 / 20 : 1);
        // The mockup treats the last two pixels as the reached edge.
        scroll.jumpTo(scroll.position.maxScrollExtent - 1);
        await tester.pumpAndSettle();
        _expectInk(await _pixel(tester, key, 0), reverse ? 1 : .5 / 14);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets(
    'short content and resized or shortened lists clear obsolete fades',
    (tester) async {
      final key = GlobalKey();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var count = 30;
      late StateSetter update;
      await tester.pumpWidget(
        _host(
          key,
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return _list(scroll, count: count);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 179), .5 / 20);
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      update(() => count = 6);
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 0), 1);
      _expectInk(await _pixel(tester, key, 179), 1);
      await tester.pumpWidget(_host(key, _list(scroll, count: 6), height: 120));
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 119), .5 / 20);
      await tester.pumpWidget(_host(key, _list(scroll, count: 6), height: 180));
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 179), 1);
    },
  );

  testWidgets(
    'Native scrollbars add one fade even when globally configured or hidden',
    (tester) async {
      final key = GlobalKey();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      for (final global in [false, true]) {
        for (final visible in [false, true]) {
          await tester.pumpWidget(
            _host(
              key,
              DScrollBar(
                controller: scroll,
                showScrollbar: visible,
                child: _list(scroll),
              ),
              nativeBehavior: global,
            ),
          );
          await tester.pumpAndSettle();
          _expectInk(await _pixel(tester, key, 170), 9.5 / 20);
          final position = scroll.position;
          scroll.jumpTo(150);
          await tester.pumpAndSettle();
          _expectInk(await _pixel(tester, key, 7), 7.5 / 14);
          expect(scroll.position, same(position));
          scroll.jumpTo(0);
        }
      }
    },
  );

  testWidgets(
    'virtualized page fade follows the header without replacing its position',
    (tester) async {
      final key = GlobalKey();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          key,
          DPageSurface.scrollable(
            framed: false,
            hideHeaderOnScroll: true,
            header: const SizedBox(height: 40),
            headerControls: const SizedBox(height: 20),
            bodyBuilder: (_, header) => CustomScrollView(
              controller: scroll,
              slivers: [
                SliverToBoxAdapter(child: header.spacer),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 1000, child: ColoredBox(color: _ink)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final position = scroll.position;
      position.jumpTo(200);
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 60), .5 / 14);
      _expectInk(await _pixel(tester, key, 67), 7.5 / 14);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 20), .5 / 14);
      _expectInk(await _pixel(tester, key, 27), 7.5 / 14);
      expect(scroll.position, same(position));
      // Let the header's mockup hold interval expire before reversing intent.
      await tester.pump(const Duration(milliseconds: 401));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 60), .5 / 14);
      expect(scroll.position, same(position));
    },
  );

  testWidgets(
    'nested vertical lists use their own edges and ignore header insets',
    (tester) async {
      final key = GlobalKey();
      final outer = ScrollController();
      final inner = ScrollController(initialScrollOffset: 50);
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      await tester.pumpWidget(
        _host(
          key,
          DScrollFadeScope(
            topExtent: 26,
            bottomExtent: 26,
            topInset: () => 40,
            child: ListView(
              controller: outer,
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 40),
                SizedBox(height: 100, child: _list(inner)),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 40), .5 / 14);
      _expectInk(await _pixel(tester, key, 47), 7.5 / 14);
      _expectInk(await _pixel(tester, key, 139), .5 / 20);
    },
  );

  testWidgets(
    'horizontal viewports stay unfaded and vertical edge hits reach content',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        _host(
          key,
          const DScrollArea(
            axes: DScrollAxes.horizontal,
            child: SizedBox(
              width: 1000,
              height: 180,
              child: ColoredBox(color: _ink),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectInk(await _pixel(tester, key, 0), 1);
      _expectInk(await _pixel(tester, key, 179), 1);
      var taps = 0;
      final scroll = ScrollController(initialScrollOffset: 100);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          key,
          ListView(
            controller: scroll,
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 1000,
                child: Listener(
                  onPointerDown: (_) => taps++,
                  child: const ColoredBox(color: _ink),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byKey(key));
      await tester.tapAt(bounds.topLeft + const Offset(50, 1));
      await tester.tapAt(bounds.bottomLeft + const Offset(50, -1));
      expect(taps, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
