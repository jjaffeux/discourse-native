import 'dart:ui' as ui;

import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

void main() {
  group('DIcon', () {
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
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        picture.colorFilter,
        isNull,
        reason: 'runtime SVG color filters paint through Canvas.saveLayer',
      );
    });

    testWidgets('bakes the tint into the picture without a paint-time layer', (
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

      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(picture.colorFilter, isNull);

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

    test('aliases resolve to the icon Discourse maps them to', () {
      expect(DIcons.byName['d-liked'], DIcons.heart);
      expect(DIcons.byName['d-unliked'], DIcons.farHeart);
      expect(DIcons.byName['topic.closed'], DIcons.lock);
      expect(DIcons.byName['notification.mentioned'], DIcons.at);
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
