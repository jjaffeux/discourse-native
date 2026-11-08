import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_icons.dart';
import 'package:discourse_native/src/theme/d_icon_glyph.dart';
import 'package:discourse_native/src/theme/d_icon_sets.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';
import 'support/pixel_samples.dart';

void main() {
  group('DIcon', () {
    testWidgets('alternate families render mapped icons and retain fallback', (
      tester,
    ) async {
      for (final set in DIconSet.values.skip(1)) {
        expect(alternateIconSvg(set, 'gear'), isNotNull);
        expect(alternateIconSvg(set, 'unmapped-icon'), isNull);
        await tester.pumpWidget(
          MaterialApp(
            home: DIconSetScope(
              iconSet: set,
              child: const Row(
                children: [DIcon(DIcons.gear), DIcon(DIcons.asterisk)],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: set.name);
      }
    });

    testWidgets('every mapped alternate SVG parses', (tester) async {
      for (final set in DIconSet.values.skip(1)) {
        for (final name in DIcons.byName.keys) {
          if (alternateIconSvg(set, name) == null) continue;
          await tester.pumpWidget(
            MaterialApp(
              home: DIconSetScope(
                iconSet: set,
                child: Center(child: DIcon(DIcons.byName[name]!)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '${set.name}/$name');
        }
      }
    });

    testWidgets('every bundled icon renders', (tester) async {
      // A malformed generated or app-specific SVG fails at parse time, inside
      // a future, where nothing else would notice.
      final icons = {...DIcons.byName.values, ...DNativeIcons.byName.values};
      for (final icon in icons) {
        await tester.pumpWidget(
          MaterialApp(home: Center(child: DIcon(icon, size: 24))),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${icon.name} did not render',
        );
        expect(find.dIcon(icon), findsOneWidget);
      }
    });

    testWidgets('sizes to the box it is given, not the viewBox', (
      tester,
    ) async {
      // `hand-point-right` is 448x512, so a widget that passed the viewBox
      // through would not be square.
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: DIcon(DIcons.handPointRight, size: 32)),
        ),
      );

      expect(
        tester.getSize(find.dIcon(DIcons.handPointRight)),
        const Size(32, 32),
      );
    });

    for (final preserveColors in [false, true]) {
      testWidgets(
        'edge strokes remain whole at fractional sizes, preserveColors=$preserveColors',
        (tester) async {
          const boundaryKey = ValueKey('fractional-icon');
          final icon = DIconData(
            'edge-stroke',
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
                '<path d="M0 0H16V16H0Z" fill="none" '
                'stroke="white" stroke-width="2"/></svg>',
            preserveColors: preserveColors,
          );
          for (final scale in [0.9, 1.1, 1.25, 1.5]) {
            final size = 16 * scale;
            await tester.pumpWidget(
              MaterialApp(
                home: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox.square(
                      dimension: 48,
                      child: Center(
                        child: Transform.translate(
                          offset: const Offset(.3, .2),
                          child: DIconGlyphTheme(
                            scale: 1,
                            naturalWidth: true,
                            child: DIcon(icon, size: size, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final bounds = tester
                .getRect(find.byType(DIcon))
                .shift(-tester.getTopLeft(find.byKey(boundaryKey)));
            expect(bounds.width, closeTo(size.roundToDouble(), .001));
            expect(bounds.height, closeTo(size, .001));
            final pixels = await samplePixels(tester, find.byKey(boundaryKey), [
              bounds.centerLeft - Offset(.4 * scale, 0),
              bounds.topCenter - Offset(0, .4 * scale),
              bounds.centerRight + Offset(.4 * scale, 0),
              bounds.bottomCenter + Offset(0, .4 * scale),
            ]);
            for (var edge = 0; edge < pixels.length; edge++) {
              expect(
                pixels[edge].a,
                greaterThan(.7),
                reason: 'scale=$scale edge=$edge must retain the outer stroke',
              );
            }
          }
        },
      );
    }

    testWidgets('plus fills the reference arm extents', (tester) async {
      const key = ValueKey('reference-plus');
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: DIconGlyphTheme(
              scale: 1,
              naturalWidth: true,
              child: RepaintBoundary(
                key: key,
                child: DIcon(DIcons.plus, size: 64, color: Colors.white),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(key)), const Size(56, 64));
      expect(
        await samplePixels(tester, find.byKey(key), const [
          Offset(1, 32),
          Offset(28, 5),
          Offset(55, 32),
          Offset(28, 59),
          Offset.zero,
        ]),
        const [
          Colors.white,
          Colors.white,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
      );
    });

    testWidgets('smile keeps the reference mouth weight', (tester) async {
      const key = ValueKey('reference-smile');
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: DIconGlyphTheme(
              scale: 1,
              child: RepaintBoundary(
                key: key,
                child: DIcon(DIcons.faceSmile, size: 64, color: Colors.white),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        await samplePixels(tester, find.byKey(key), const [
          Offset(32, 51),
          Offset(32, 53),
          Offset(22, 26),
          Offset(32, 32),
        ]),
        const [
          Colors.transparent,
          Colors.white,
          Colors.transparent,
          Colors.white,
        ],
      );
    });

    testWidgets('takes its size from IconTheme without a paint-time filter', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IconTheme(
            data: IconThemeData(size: 18, color: Color(0xFF00FF00)),
            child: Center(child: DIcon(DIcons.gear)),
          ),
        ),
      );

      expect(tester.getSize(find.dIcon(DIcons.gear)), const Size(18, 18));
      expect(
        tester.widget<TintedIconGlyph>(find.byType(TintedIconGlyph)).color,
        const Color(0xFF00FF00),
      );
      expect(
        find.byType(SvgPicture),
        findsNothing,
        reason: 'runtime SVG color filters paint through Canvas.saveLayer',
      );
    });

    testWidgets('paints the tint into the glyph without a paint-time layer', (
      tester,
    ) async {
      const boundaryKey = ValueKey('tinted-icon-boundary');
      const iconWithoutRootFill = DIconData(
        'icon-without-root-fill',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
            '<circle cx="8" cy="8" r="8"/></svg>',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: ColoredBox(
            color: Colors.white,
            child: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: DIcon(
                  iconWithoutRootFill,
                  size: 32,
                  color: Color(0xFF00FF00),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TintedIconGlyph), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final centerPixel = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final center =
              (image.width * (image.height ~/ 2) + image.width ~/ 2) * 4;
          return pixels!.buffer.asUint8List(center, 4);
        } finally {
          image.dispose();
        }
      }))!;
      expect(centerPixel, [0, 255, 0, 255]);
    });

    testWidgets('a tinted icon mounts one render object', (tester) async {
      final mounted = <String, (int, int)>{};
      for (final label in const [null, 'Settings']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: DIcon(DIcons.gear, size: 24, semanticLabel: label),
            ),
          ),
        );
        expect(find.byType(TintedIconGlyph), findsOneWidget);
        expect(find.byType(SvgPicture), findsNothing);

        var elements = 0;
        var renderObjects = 0;
        void visit(Element element) {
          elements++;
          if (element is RenderObjectElement) renderObjects++;
          element.visitChildren(visit);
        }

        tester.element(find.byType(DIcon)).visitChildren(visit);

        final side = label == null ? 'unlabelled' : 'labelled';
        // ignore: avoid_print
        print('PERF_PROOF d-icon render_objects_$side=$renderObjects');
        // ignore: avoid_print
        print('PERF_PROOF d-icon elements_$side=$elements');
        mounted[side] = (renderObjects, elements);
      }
      expect(mounted, const {'unlabelled': (1, 1), 'labelled': (1, 1)});
    });

    group('semantics, layout and hit testing of a tinted icon', () {
      // Half as wide as tall, so a 24 box holds a 10.5x21 glyph inset by 6.75
      // at the sides and 1.5 at the top and bottom.
      const narrow = DIconData(
        'narrow',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 16">'
            '<path d="M0 0h8v16H0z"/></svg>',
      );

      Rect globalRect(SemanticsNode node) {
        var rect = node.rect;
        for (SemanticsNode? n = node; n != null; n = n.parent) {
          if (n.transform case final transform?) {
            rect = MatrixUtils.transformRect(transform, rect);
          }
        }
        return rect;
      }

      Widget app(Widget child, {TextDirection? direction}) => MaterialApp(
        home: Directionality(
          textDirection: direction ?? TextDirection.ltr,
          child: Center(child: child),
        ),
      );

      void expectRect(Rect actual, Rect expected) {
        expect(actual.left, closeTo(expected.left, .001));
        expect(actual.top, closeTo(expected.top, .001));
        expect(actual.right, closeTo(expected.right, .001));
        expect(actual.bottom, closeTo(expected.bottom, .001));
      }

      testWidgets('a label is an image node over the glyph, not the box', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(const DIcon(narrow, size: 24, semanticLabel: 'Point')),
        );

        final node = tester.getSemantics(find.bySemanticsLabel('Point'));
        expect(
          node,
          matchesSemantics(
            label: 'Point',
            isImage: true,
            textDirection: TextDirection.ltr,
          ),
        );
        final box = tester.getRect(find.byType(DIcon));
        expect(box.size, const Size(24, 24));
        expectRect(
          globalRect(node),
          Rect.fromCenter(center: box.center, width: 10.5, height: 21),
        );
      });

      testWidgets('an unlabelled icon annotates the enclosing node', (
        tester,
      ) async {
        await tester.pumpWidget(
          app(
            Semantics(
              container: true,
              label: 'Enclosing',
              child: const DIcon(narrow, size: 24),
            ),
          ),
        );

        final node = tester.getSemantics(find.bySemanticsLabel('Enclosing'));
        expect(
          node,
          matchesSemantics(
            label: 'Enclosing',
            isImage: true,
            textDirection: TextDirection.ltr,
          ),
        );
        expect(node.childrenCount, 0);
      });

      testWidgets('a rebuilt icon republishes its label and direction', (
        tester,
      ) async {
        Future<void> pump(String? label, TextDirection direction) =>
            tester.pumpWidget(
              app(
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  label: 'Enclosing',
                  child: DIcon(narrow, size: 24, semanticLabel: label),
                ),
                direction: direction,
              ),
            );

        await pump(null, TextDirection.ltr);
        expect(find.bySemanticsLabel('First'), findsNothing);

        await pump('First', TextDirection.ltr);
        expect(
          tester.getSemantics(find.bySemanticsLabel('First')),
          matchesSemantics(
            label: 'First',
            isImage: true,
            textDirection: TextDirection.ltr,
          ),
        );

        await pump('Second', TextDirection.rtl);
        expect(find.bySemanticsLabel('First'), findsNothing);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Second')),
          matchesSemantics(
            label: 'Second',
            isImage: true,
            textDirection: TextDirection.rtl,
          ),
        );

        await pump(null, TextDirection.rtl);
        expect(find.bySemanticsLabel('Second'), findsNothing);
      });

      testWidgets(
        'the labelled rect follows a glyph resize inside a fixed box',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetDevicePixelRatio);
          Future<void> pump(double scale) => tester.pumpWidget(
            app(
              DIconGlyphTheme(
                scale: scale,
                child: const DIcon(narrow, size: 24, semanticLabel: 'Point'),
              ),
            ),
          );

          await pump(1);
          final box = tester.getRect(find.byType(DIcon));
          expectRect(
            globalRect(tester.getSemantics(find.bySemanticsLabel('Point'))),
            Rect.fromCenter(center: box.center, width: 12, height: 24),
          );

          await pump(.5);
          expect(tester.getRect(find.byType(DIcon)), box);
          expectRect(
            globalRect(tester.getSemantics(find.bySemanticsLabel('Point'))),
            Rect.fromCenter(center: box.center, width: 6, height: 12),
          );
        },
      );

      testWidgets('a box smaller than the icon clamps the glyph into it', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            const SizedBox.square(
              dimension: 10,
              child: DIcon(narrow, size: 24, semanticLabel: 'Point'),
            ),
          ),
        );

        final box = tester.getRect(find.byType(DIcon));
        expect(box.size, const Size(10, 10));
        expectRect(
          globalRect(tester.getSemantics(find.bySemanticsLabel('Point'))),
          box,
        );
      });

      testWidgets('intrinsics and dry layout report the box', (tester) async {
        await tester.pumpWidget(
          app(
            const DIconGlyphTheme(
              scale: 1,
              naturalWidth: true,
              child: DIcon(narrow, size: 32),
            ),
          ),
        );

        final render = tester.renderObject<RenderBox>(find.byType(DIcon));
        expect(render.size, const Size(16, 32));
        expect(render.getMinIntrinsicWidth(double.infinity), 16);
        expect(render.getMaxIntrinsicWidth(double.infinity), 16);
        expect(render.getMinIntrinsicHeight(double.infinity), 32);
        expect(render.getMaxIntrinsicHeight(double.infinity), 32);
        expect(
          render.getDryLayout(const BoxConstraints.tightFor(width: 10)),
          const Size(10, 32),
        );
      });

      testWidgets('only the glyph rect takes a pointer', (tester) async {
        var hits = 0;
        await tester.pumpWidget(
          app(
            Listener(
              onPointerDown: (_) => hits++,
              child: const DIcon(narrow, size: 24),
            ),
          ),
        );
        final box = tester.getRect(find.byType(DIcon));

        await tester.tapAt(box.center);
        expect(hits, 1);

        await tester.tapAt(box.centerLeft + const Offset(6, 0));
        await tester.tapAt(box.topCenter + const Offset(0, 1));
        expect(hits, 1, reason: 'inside the box, outside the glyph');

        await tester.tapAt(box.centerLeft + const Offset(7, 0));
        expect(hits, 2);
      });

      testWidgets('a rebuilt icon repaints its new colour and glyph', (
        tester,
      ) async {
        const key = ValueKey('rebuilt-icon');
        Future<Color> paint(DIconData icon, Color color) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: key,
                  child: DIcon(icon, size: 32, color: color),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          return (await samplePixels(tester, find.byKey(key), const [
            Offset(16, 16),
          ])).single;
        }

        const filled = DIconData(
          'rebuilt-filled',
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
              '<circle cx="8" cy="8" r="8"/></svg>',
        );
        const hollow = DIconData(
          'rebuilt-hollow',
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
              '<path d="M0 0h2v2H0z"/></svg>',
        );

        expect(
          await paint(filled, const Color(0xFF00FF00)),
          const Color(0xFF00FF00),
        );
        expect(
          await paint(filled, const Color(0xFFFF0000)),
          const Color(0xFFFF0000),
        );
        expect(
          await paint(hollow, const Color(0xFFFF0000)),
          Colors.transparent,
        );
      });
    });

    test('aliases resolve to the icon Discourse maps them to', () {
      expect(DIcons.byName['d-liked'], DIcons.heart);
      expect(DIcons.byName['d-unliked'], DIcons.farHeart);
      expect(DIcons.byName['topic.closed'], DIcons.lock);
      expect(DIcons.byName['notification.mentioned'], DIcons.at);
    });

    testWidgets('AI badge keeps its fixed artwork across theme changes', (
      tester,
    ) async {
      const key = ValueKey('ai-icon');
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Center(
              child: RepaintBoundary(
                key: key,
                child: DIcon(
                  DiscourseAiIcons.ai,
                  size: 128,
                  color: Color(0xFFFF0000),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final colors = await samplePixels(tester, find.byKey(key), const [
          Offset(64, 30), // Background above the lettering.
          Offset(83, 46), // Top bar of the I.
          Offset.zero, // Outside the rounded artwork.
        ]);
        expect(colors, const [
          Color(0xFF333333),
          Colors.white,
          Colors.transparent,
        ]);
        expect(DiscourseAiIcons.ai.preserveColors, isTrue);
        expect(
          tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
          isNull,
        );
      }
    });

    testWidgets('preserves SVG colors, palette changes and icon opacity', (
      tester,
    ) async {
      const key = ValueKey('preserved-colors');
      const icon = DIconData(
        'palette-test',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 10">'
            '<path d="M0 0h10v10H0z"/>'
            '<path d="M10 0h10v10H10z" fill="#ff6600"/>'
            '<path d="M20 0h10v10H20z" fill="var(--secondary)"/>'
            '<path d="M30 0h10v10H30z" fill="var(--tertiary)"/>'
            '<path d="M40 0h10v10H40z" fill="var(--danger)"/>'
            '<path d="M50 0h10v10H50z" fill="var(--custom-color, #123456)"/>'
            '</svg>',
        preserveColors: true,
      );
      for (final brightness in Brightness.values) {
        final theme = ThemeData(brightness: brightness);
        for (final opacity in [1.0, 0.5]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: IconTheme(
                data: IconThemeData(
                  color: const Color(0xFF00FF00),
                  opacity: opacity,
                ),
                child: const Center(
                  child: RepaintBoundary(
                    key: key,
                    child: DIcon(icon, size: 60),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          final samples = (await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba,
              ))!.buffer.asUint8List();
              return [
                for (var i = 0; i < 6; i++)
                  bytes.sublist(
                    (30 * image.width +
                            (3.75 + (i * 10 + 5) * DIcon.glyphScale).floor()) *
                        4,
                    (30 * image.width +
                                (3.75 + (i * 10 + 5) * DIcon.glyphScale)
                                    .floor()) *
                            4 +
                        4,
                  ),
              ];
            } finally {
              image.dispose();
            }
          }))!;
          final colors = [
            const Color(0xFF00FF00),
            const Color(0xFFFF6600),
            theme.colorScheme.surface,
            theme.colorScheme.primary,
            theme.colorScheme.error,
            const Color(0xFF123456),
          ];
          for (var i = 0; i < colors.length; i++) {
            final color = colors[i];
            final expected = [
              (color.r * 255).round(),
              (color.g * 255).round(),
              (color.b * 255).round(),
              (opacity * 255).round(),
            ];
            for (var channel = 0; channel < 4; channel++) {
              expect(
                samples[i][channel],
                closeTo(expected[channel], 1),
                reason:
                    '$brightness opacity $opacity paint $i channel $channel',
              );
            }
          }
          expect(
            tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
            isNull,
          );
        }
      }
    });

    test('core catalog excludes optional plugin resources and aliases', () {
      for (final name in const [
        'discourse-sparkles',
        'gif',
        'square-poll-horizontal',
        'd-chat',
      ]) {
        expect(DIcons.byName, isNot(contains(name)), reason: name);
      }
    });
  });
}
