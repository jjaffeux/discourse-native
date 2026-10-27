import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _canvas = Color(0xff808080);
const _probe = ValueKey('depth-probe');
const _surface = ValueKey('depth-surface');

/// What one rendered surface looks like on a mid-grey canvas, 60px of which
/// surround it on every side.
class _Capture {
  _Capture(this.bytes, this.width, this.surface);

  final ByteData bytes;
  final int width;
  final Rect surface;

  Color at(double x, double y) {
    final offset = ((y.floor()) * width + x.floor()) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  /// The canvas just under the surface's foot, middle of its width.
  Color below([double by = 14]) => at(surface.center.dx, surface.bottom + by);

  /// The canvas just over the surface's head, middle of its width.
  Color above([double by = 4]) => at(surface.center.dx, surface.top - by);

  /// The canvas beside the surface, level with its middle.
  Color beside([double by = 4]) => at(surface.right + by, surface.center.dy);
}

/// Eight bits a channel: a blend computed in doubles rounds to within one
/// step of what the rasteriser stores.
Matcher _near(Color expected) => isA<Color>().having(
  (c) => [
    for (final (a, b) in [
      (c.r, expected.r),
      (c.g, expected.g),
      (c.b, expected.b),
    ])
      ((a - b) * 255).abs() <= 1.01,
  ].every((ok) => ok),
  'within one step of $expected',
  isTrue,
);

int _lum(Color c) =>
    (c.r * 255).round() + (c.g * 255).round() + (c.b * 255).round();

Future<_Capture> _capture(
  WidgetTester tester,
  Brightness brightness,
  Widget surface, {
  Size size = const Size(200, 160),
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: AppTheme.forBrightness(brightness),
      home: Center(
        child: RepaintBoundary(
          key: _probe,
          child: ColoredBox(
            color: _canvas,
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: SizedBox.fromSize(
                key: _surface,
                size: size,
                child: surface,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final origin = tester.getTopLeft(find.byKey(_probe));
  final rect = tester.getRect(find.byKey(_surface)).shift(-origin);
  late _Capture capture;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_probe))
        .toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    capture = _Capture(bytes, image.width, rect);
    image.dispose();
  });
  return capture;
}

void main() {
  group('edges match the mockup in light and dark', () {
    const black = Color(0xff000000);
    const white = Color(0xffffffff);
    Color a(Color c, double alpha) => c.withValues(alpha: alpha);

    test('panels: rim, catch of light and one wide shadow', () {
      final dark = DSurfaceEdges.of(DSurfaceDepth.panel, Brightness.dark);
      expect(dark.rim, a(white, .07));
      expect(dark.highlight, a(white, .07));
      expect(dark.shadows, [
        DCastShadow(const Offset(0, 12), 40, a(black, .24)),
      ]);
      final light = DSurfaceEdges.of(DSurfaceDepth.panel, Brightness.light);
      expect(light.rim, a(black, .07));
      expect(light.highlight, a(white, .8));
      expect(light.shadows, [
        DCastShadow(const Offset(0, 12), 40, a(black, .09)),
      ]);
    });

    test('the drawer sidebar keeps the rim alone', () {
      for (final brightness in Brightness.values) {
        final edges = DSurfaceEdges.of(DSurfaceDepth.rim, brightness);
        expect(
          edges.rim,
          DSurfaceEdges.of(DSurfaceDepth.panel, brightness).rim,
        );
        expect(edges.highlight, isNull);
        expect(edges.shadows, isEmpty);
      }
    });

    test('menus: catch of light, a close shadow and a wide one, no rim', () {
      final dark = DSurfaceEdges.of(DSurfaceDepth.menu, Brightness.dark);
      expect(dark.rim, isNull);
      expect(dark.highlight, a(white, .07));
      expect(dark.shadows, [
        DCastShadow(const Offset(0, 2), 6, a(black, .2)),
        DCastShadow(const Offset(0, 18), 44, a(black, .38)),
      ]);
      final light = DSurfaceEdges.of(DSurfaceDepth.menu, Brightness.light);
      expect(light.rim, isNull);
      expect(light.highlight, a(white, .8));
      expect(light.shadows, [
        DCastShadow(const Offset(0, 2), 6, a(black, .08)),
        DCastShadow(const Offset(0, 18), 44, a(black, .16)),
      ]);
    });

    test('place cards rest and rise', () {
      final dark = DSurfaceEdges.of(DSurfaceDepth.place, Brightness.dark);
      expect(dark.rim, isNull);
      expect(dark.highlight, a(white, .06));
      expect(dark.shadows, [
        DCastShadow(const Offset(0, 1), 2, a(black, .14)),
        DCastShadow(const Offset(0, 4), 14, a(black, .12)),
      ]);
      final light = DSurfaceEdges.of(DSurfaceDepth.place, Brightness.light);
      expect(light.highlight, a(white, .9));
      expect(light.shadows, [
        DCastShadow(const Offset(0, 1), 2, a(black, .06)),
        DCastShadow(const Offset(0, 4), 14, a(black, .06)),
      ]);
      final darkUp = DSurfaceEdges.of(
        DSurfaceDepth.placeHovered,
        Brightness.dark,
      );
      expect(darkUp.highlight, a(white, .09));
      expect(darkUp.shadows, [
        DCastShadow(const Offset(0, 2), 4, a(black, .16)),
        DCastShadow(const Offset(0, 10), 24, a(black, .18)),
      ]);
      final lightUp = DSurfaceEdges.of(
        DSurfaceDepth.placeHovered,
        Brightness.light,
      );
      expect(lightUp.highlight, a(white, .9));
      expect(lightUp.shadows, [
        DCastShadow(const Offset(0, 2), 4, a(black, .07)),
        DCastShadow(const Offset(0, 10), 24, a(black, .1)),
      ]);
    });

    test('blocks inside a panel: rim, a soft catch of light, a small '
        'shadow', () {
      final dark = DSurfaceEdges.of(DSurfaceDepth.block, Brightness.dark);
      expect(dark.rim, a(white, .07));
      expect(dark.highlight!.a, closeTo(.098, 1e-9));
      expect(dark.highlightBlur, 1);
      expect(dark.shadows, [
        DCastShadow(const Offset(0, 4), 16, a(black, .08)),
      ]);
      final light = DSurfaceEdges.of(DSurfaceDepth.block, Brightness.light);
      expect(light.rim, a(black, .07));
      expect(light.highlight, white, reason: 'CSS clamps .8 * 1.4 to 1');
      expect(light.highlightBlur, 1);
      expect(light.shadows, [
        DCastShadow(const Offset(0, 4), 16, a(black, .08)),
      ]);
    });

    test('a toast, the suggestions, the timeline thumb, a lifted place and '
        'a sheet to write on cast one shadow each', () {
      // 35% black, to the byte.
      expect(
        DMobileDockReorder.shadow,
        const DCastShadow(Offset(0, 8), 24, Color(0x59000000)),
      );
      for (final brightness in Brightness.values) {
        final thumb = DSurfaceEdges.of(DSurfaceDepth.thumb, brightness);
        expect(thumb.rim, isNull);
        expect(thumb.highlight, isNull);
        expect(thumb.shadows, [
          DCastShadow(const Offset(0, 2), 6, a(black, .3)),
        ]);
        final toast = DSurfaceEdges.of(DSurfaceDepth.floating, brightness);
        expect(toast.rim, isNull);
        expect(toast.highlight, isNull);
        expect(toast.shadows, [
          DCastShadow(const Offset(0, 8), 24, a(black, .25)),
        ]);
        final full = DSurfaceEdges.of(DSurfaceDepth.fullSheet, brightness);
        expect(full.rim, isNull);
        expect(full.highlight, isNull);
        expect(full.shadows, [
          DCastShadow(const Offset(0, -8), 32, a(black, .22)),
        ]);
      }
    });

    test('a CSS blur length is twice the standard deviation', () {
      expect(const DCastShadow(Offset.zero, 40, black).sigma, 20);
    });
  });

  group('a panel', () {
    for (final brightness in Brightness.values) {
      testWidgets('draws its rim, catch of light and shadow ($brightness)', (
        tester,
      ) async {
        const fill = Color(0xff404040);
        final shot = await _capture(
          tester,
          brightness,
          const DCard(
            border: false,
            spacing: 0,
            backgroundColor: fill,
            borderRadius: BorderRadius.all(Radius.circular(22)),
            depth: DSurfaceDepth.panel,
            child: Expanded(child: SizedBox.expand()),
          ),
        );
        final s = shot.surface;
        final inside = shot.at(s.center.dx, s.center.dy);
        expect(inside, fill, reason: 'the fill is untouched in the middle');
        final edge = shot.at(s.left + .5, s.center.dy);
        final top = shot.at(s.center.dx, s.top + .5);
        final edges = DSurfaceEdges.of(DSurfaceDepth.panel, brightness);
        // The catch of light runs along the top row, under the rim.
        expect(
          top,
          _near(
            Color.alphaBlend(
              edges.rim!,
              Color.alphaBlend(edges.highlight!, fill),
            ),
          ),
        );
        expect(edge, _near(Color.alphaBlend(edges.rim!, fill)));
        expect(
          _lum(shot.below()),
          lessThan(_lum(_canvas) - 6),
          reason: 'its shadow falls under its foot',
        );
        expect(
          _lum(shot.beside(30)),
          lessThan(_lum(_canvas)),
          reason: 'and spreads out to its sides',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('casts nothing under a translucent fill', (tester) async {
      const fill = Color(0x00000000);
      final shot = await _capture(
        tester,
        Brightness.dark,
        const DCard(
          border: false,
          spacing: 0,
          backgroundColor: fill,
          borderRadius: BorderRadius.all(Radius.circular(22)),
          depth: DSurfaceDepth.panel,
          child: Expanded(child: SizedBox.expand()),
        ),
      );
      final s = shot.surface;
      expect(shot.at(s.center.dx, s.bottom - 10), _canvas);
      expect(_lum(shot.below()), lessThan(_lum(_canvas)));
    });

    testWidgets('stays flat when no depth is asked for', (tester) async {
      final shot = await _capture(
        tester,
        Brightness.dark,
        const DCard(
          border: false,
          spacing: 0,
          backgroundColor: Color(0xff404040),
          child: Expanded(child: SizedBox.expand()),
        ),
      );
      expect(shot.below(), _canvas);
      expect(
        shot.at(shot.surface.center.dx, shot.surface.top + .5),
        const Color(0xff404040),
      );
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('a block draws its rim inside its transparent border '
        '($brightness)', (tester) async {
      const fill = Color(0xff505050);
      final shot = await _capture(
        tester,
        brightness,
        const DCard(
          variant: DCardVariant.well,
          spacing: 0,
          backgroundColor: fill,
          borderColor: Colors.transparent,
          depth: DSurfaceDepth.block,
          child: Expanded(child: SizedBox.expand()),
        ),
      );
      final s = shot.surface;
      final edges = DSurfaceEdges.of(DSurfaceDepth.block, brightness);
      expect(shot.at(s.left + .5, s.center.dy), fill);
      // The soft light leaks a little round the sides too, as in CSS, so
      // the rim's own pixel is only known to differ from the fill.
      expect(shot.at(s.left + 1.5, s.center.dy), isNot(fill));
      expect(shot.at(s.left + 2.5, s.center.dy), _near(fill));
      expect(
        _lum(shot.at(s.center.dx, s.top + 1.5)),
        greaterThan(_lum(Color.alphaBlend(edges.rim!, fill))),
        reason: 'the light catches under the top rim',
      );
      expect(_lum(shot.below(6)), lessThan(_lum(_canvas) - 3));
    });
  }

  group('phone pages', () {
    Widget host(Widget child) =>
        ForumWindowBackground(mobile: true, child: child);

    for (final brightness in Brightness.values) {
      testWidgets('a page card stands as a panel ($brightness)', (
        tester,
      ) async {
        final shot = await _capture(
          tester,
          brightness,
          host(const ForumMobileSurface(child: SizedBox.expand())),
        );
        expect(_lum(shot.below()), lessThan(_lum(_canvas) - 6));
        final s = shot.surface;
        final fill = shot.at(s.center.dx, s.center.dy);
        final top = shot.at(s.center.dx, s.top + .5);
        expect(top, isNot(fill), reason: 'its top row catches the light');
      });

      testWidgets('the drawer sidebar has its rim and no shadow '
          '($brightness)', (tester) async {
        final shot = await _capture(
          tester,
          brightness,
          host(const ForumMobileSurface.sidebar(child: SizedBox.expand())),
        );
        expect(shot.below(), _canvas);
        expect(shot.beside(), _canvas);
        final s = shot.surface;
        final fill = shot.at(s.center.dx, s.center.dy);
        final edges = DSurfaceEdges.of(DSurfaceDepth.rim, brightness);
        expect(
          shot.at(s.left + .5, s.center.dy),
          _near(Color.alphaBlend(edges.rim!, fill)),
        );
        expect(
          shot.at(s.center.dx, s.top + .5),
          _near(Color.alphaBlend(edges.rim!, fill)),
        );
      });
    }

    testWidgets('a page under a page sheet leaves the depth to the sheet', (
      tester,
    ) async {
      final shot = await _capture(
        tester,
        Brightness.dark,
        host(
          const ForumMobileSurface(
            coveredBySheet: true,
            child: SizedBox.expand(),
          ),
        ),
      );
      expect(shot.below(), _canvas);
    });

    testWidgets('a pushed page sheet stands as a panel', (tester) async {
      final shot = await _capture(
        tester,
        Brightness.dark,
        const DSheetContent(
          side: DSheetSide.bottom,
          variant: DSheetVariant.page,
          showCloseButton: false,
          children: [Expanded(child: SizedBox.expand())],
        ),
      );
      expect(_lum(shot.below()), lessThan(_lum(_canvas) - 6));
    });
  });

  group('menus', () {
    for (final brightness in Brightness.values) {
      testWidgets('a menu sheet is edged round its top and sides and lit '
          'inside its edge ($brightness)', (tester) async {
        final shot = await _capture(
          tester,
          brightness,
          const DSheetContent(
            side: DSheetSide.bottom,
            variant: DSheetVariant.menu,
            showCloseButton: false,
            backgroundColor: Color(0xff404040),
            children: [SizedBox(height: 120)],
          ),
        );
        final s = shot.surface;
        final border = AppTheme.forBrightness(
          brightness,
        ).extension<DTokens>()!.border;
        expect(shot.at(s.left + .5, s.center.dy), border, reason: 'side edge');
        expect(shot.at(s.center.dx, s.top + .5), border, reason: 'top edge');
        final edges = DSurfaceEdges.of(DSurfaceDepth.menu, brightness);
        expect(
          shot.at(s.center.dx, s.top + 1.5),
          _near(Color.alphaBlend(edges.highlight!, const Color(0xff404040))),
          reason: 'the catch of light lies inside the edge, not under it',
        );
        expect(_lum(shot.below()), lessThan(_lum(_canvas) - 6));
      });
    }

    testWidgets('a sheet to write on has no edge and casts its shadow up', (
      tester,
    ) async {
      const fill = Color(0xff404040);
      final shot = await _capture(
        tester,
        Brightness.dark,
        const DSheetContent(
          side: DSheetSide.bottom,
          variant: DSheetVariant.menu,
          showCloseButton: false,
          fillAvailableHeight: true,
          extendBehindKeyboard: true,
          backgroundColor: fill,
          children: [Expanded(child: SizedBox.expand())],
        ),
      );
      final s = shot.surface;
      expect(shot.at(s.center.dx, s.top + .5), fill);
      expect(shot.at(s.left + .5, s.center.dy), fill);
      expect(_lum(shot.above()), lessThan(_lum(_canvas) - 6));
    });

    for (final brightness in Brightness.values) {
      testWidgets('a popover casts the menus\' shadow ($brightness)', (
        tester,
      ) async {
        final shot = await _capture(
          tester,
          brightness,
          const Align(
            alignment: Alignment.topCenter,
            child: DPopoverContent(
              width: 200,
              scrollable: false,
              child: SizedBox(height: 100),
            ),
          ),
        );
        final origin = tester.getTopLeft(find.byKey(_probe));
        final box = tester.getRect(find.byType(DPopoverContent)).shift(-origin);
        final fill = shot.at(box.center.dx, box.center.dy);
        expect(shot.at(box.center.dx, box.top + .5), isNot(fill));
        expect(
          _lum(shot.at(box.center.dx, box.bottom + 14)),
          lessThan(_lum(_canvas) - 6),
        );
      });
    }

    testWidgets('a dialog casts the menus\' shadow', (tester) async {
      final shot = await _capture(
        tester,
        Brightness.dark,
        const Align(
          alignment: Alignment.topCenter,
          child: DDialogContent(
            showCloseButton: false,
            children: [SizedBox(height: 60)],
          ),
        ),
      );
      final box = tester.getRect(find.byType(DDialogContent));
      final origin = tester.getTopLeft(find.byKey(_probe));
      final bottom = box.bottom - origin.dy;
      expect(
        _lum(shot.at(shot.surface.center.dx, bottom + 14)),
        lessThan(_lum(_canvas) - 6),
      );
    });
  });

  testWidgets('the composer\'s suggestions float with their own shadow', (
    tester,
  ) async {
    final shot = await _capture(
      tester,
      Brightness.dark,
      const Align(
        alignment: Alignment.topCenter,
        child: DCommand<String>(
          outlined: true,
          depth: DSurfaceDepth.floating,
          child: SizedBox(height: 80),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byKey(_probe));
    final box = tester.getRect(find.byType(DCommand<String>)).shift(-origin);
    expect(
      _lum(shot.at(box.center.dx, box.bottom + 10)),
      lessThan(_lum(_canvas) - 6),
    );
  });

  group('place cards', () {
    Widget card({bool selected = false}) => Align(
      alignment: Alignment.topCenter,
      child: DPlaceCard(
        leading: const SizedBox.square(dimension: 29),
        title: const Text('General'),
        footer: const Text('12 topics'),
        selected: selected,
        onPressed: () {},
      ),
    );

    for (final brightness in Brightness.values) {
      testWidgets('stand off the panel and rise under the pointer '
          '($brightness)', (tester) async {
        final shot = await _capture(tester, brightness, card());
        final box = tester.getRect(find.byType(DPlaceCard));
        final origin = tester.getTopLeft(find.byKey(_probe));
        final foot = box.bottom - origin.dy;
        final x = box.center.dx - origin.dx;
        final title = tester.getRect(find.text('General'));
        // A pointer raises a card where hover highlights are shown, as on a
        // desktop.
        final resting = _lum(shot.at(x, foot + 6));
        expect(resting, lessThan(_lum(_canvas)));

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(box.center);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text('General')).top,
          title.top - 1,
          reason: 'it rises a pixel',
        );
        late _Capture raised;
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(_probe))
              .toImage();
          raised = _Capture(
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
            image.width,
            shot.surface,
          );
          image.dispose();
        });
        expect(_lum(raised.at(x, foot + 6)), lessThan(resting));
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }

    testWidgets('lie flat once chosen', (tester) async {
      final shot = await _capture(
        tester,
        Brightness.dark,
        card(selected: true),
      );
      final box = tester.getRect(find.byType(DPlaceCard));
      final origin = tester.getTopLeft(find.byKey(_probe));
      expect(
        shot.at(box.center.dx - origin.dx, box.bottom - origin.dy + 6),
        _canvas,
      );
    });
  });

  testWidgets('a toast casts its own shadow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RepaintBoundary(
          key: _probe,
          child: ColoredBox(
            color: _canvas,
            child: DToaster(
              child: Builder(
                builder: (context) => DButton(
                  label: const Text('Save'),
                  onPressed: () => DToast.show(context, 'Saved'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final card = tester.getRect(
      find
          .ancestor(
            of: find.text('Saved'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    late _Capture shot;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(_probe))
          .toImage();
      shot = _Capture(
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        image.width,
        card,
      );
      image.dispose();
    });
    expect(_lum(shot.below(10)), lessThan(_lum(_canvas) - 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
