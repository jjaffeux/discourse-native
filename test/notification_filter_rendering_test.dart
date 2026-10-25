import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = ValueKey('filter-render-capture');

void main() => notificationFilterRenderingTests();

/// Shared with the simulator runner so the same paint assertions exercise
/// the native Impeller renderer as well as the desktop widget-test backend.
void notificationFilterRenderingTests() {
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });
  for (final dark in [false, true]) {
    testWidgets('scrolling filters retain their painted pills: $dark flat', (
      tester,
    ) async {
      final shadowsDisabled = debugDisableShadows;
      debugDisableShadows = false;
      try {
        final palette = forumThemePresets
            .firstWhere((theme) => theme.id == (dark ? 'dracula' : 'solarized'))
            .resolve(dark ? Brightness.dark : Brightness.light);
        final theme = AppTheme.fromPalette(palette, fontFamily: 'Lato');
        var activations = 0;
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            themeAnimationStyle: AnimationStyle.noAnimation,
            theme: theme,
            home: RepaintBoundary(
              key: _capture,
              child: Scaffold(
                backgroundColor: palette.secondary,
                body: Center(
                  child: SizedBox(
                    width: 288,
                    child: DToggleGroup<String>(
                      density: DToggleDensity.menuFilter,
                      scrollable: true,
                      spacing: 1.5,
                      allowEmptySelection: false,
                      onItemActivated: (_) => activations++,
                      items: const [
                        DToggleGroupItem(value: 'all', child: Text('All 6')),
                        DToggleGroupItem(
                          value: 'replies',
                          child: Text('Replies'),
                        ),
                        DToggleGroupItem(value: 'likes', child: Text('Likes')),
                        DToggleGroupItem(
                          value: 'messages',
                          child: Text('Messages'),
                        ),
                        DToggleGroupItem(
                          value: 'bookmarks',
                          child: Text('Bookmarks'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replies'));
        await tester.pumpAndSettle();
        final selected = find.ancestor(
          of: find.text('Replies'),
          matching: find.byType(DToggle),
        );
        expect(tester.widget<DToggle>(selected).pressed, isTrue);
        expect(tester.getSize(selected).height, 26);
        expect(activations, 1);
        await tester.tapAt(
          tester.getRect(selected).bottomCenter + const Offset(0, 3),
        );
        await tester.pumpAndSettle();
        expect(
          activations,
          1,
          reason: 'The shadow is outside the button target',
        );
        await _assertPillPaint(
          tester,
          selected,
          '${dark ? 'dark' : 'light'}-flat-replies',
        );
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(-180, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Messages'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DToggle>(
                find.ancestor(
                  of: find.text('Messages'),
                  matching: find.byType(DToggle),
                ),
              )
              .pressed,
          isTrue,
        );
        await _assertPillPaint(
          tester,
          find.ancestor(
            of: find.text('Messages'),
            matching: find.byType(DToggle),
          ),
          '${dark ? 'dark' : 'light'}-flat-messages',
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = shadowsDisabled;
      }
    });
  }
}

Future<void> _assertPillPaint(
  WidgetTester tester,
  Finder pill,
  String name,
) async {
  final rect = tester
      .getRect(pill)
      .shift(-tester.getRect(find.byKey(_capture)).topLeft);
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_capture))
        .toImage(pixelRatio: 2);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      List<int> pixel(Offset point) {
        final offset =
            ((point.dy * 2).floor() * image.width + (point.dx * 2).floor()) * 4;
        return [for (var c = 0; c < 3; c++) bytes.getUint8(offset + c)];
      }

      final left = pixel(Offset(rect.left + 8, rect.center.dy));
      final right = pixel(Offset(rect.right - 8, rect.center.dy));
      for (var c = 0; c < 3; c++) {
        expect(
          left[c],
          closeTo(right[c], 12),
          reason: 'The pill fill must cover both pill ends',
        );
      }
      final backdrop = pixel(Offset(rect.center.dx, rect.top - 10));
      final below = pixel(Offset(rect.center.dx, rect.bottom + 3));
      expect(
        [
          for (var c = 0; c < 3; c++) backdrop[c] - below[c],
        ].reduce((a, b) => a + b),
        0,
        reason: 'Flat filter fills leave the surrounding canvas clear',
      );
      for (final x in [rect.left + 3, rect.right - 3]) {
        final aboveCorner = pixel(Offset(x, rect.bottom - 1));
        final belowCorner = pixel(Offset(x, rect.bottom + 1));
        expect(
          [
            for (var c = 0; c < 3; c++) (aboveCorner[c] - belowCorner[c]).abs(),
          ].reduce((a, b) => a + b),
          lessThan(10),
          reason: 'The corner shadow must fade without a hard offset block',
        );
      }
      expect(
        [
          for (var c = 0; c < 3; c++) (right[c] - backdrop[c]).abs(),
        ].reduce((a, b) => a + b),
        greaterThan(25),
        reason: 'The selected pill must paint its accent fill',
      );
      const output = String.fromEnvironment('NOTIFICATION_FILTER_CAPTURE_DIR');
      final directory = output.isEmpty
          ? Platform.environment['NOTIFICATION_FILTER_CAPTURE_DIR']
          : output;
      if (directory != null && directory.isNotEmpty) {
        await Directory(directory).create(recursive: true);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$directory/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_capture),
        );
        final detail = await (boundary.debugLayer! as OffsetLayer).toImage(
          rect.inflate(12),
          pixelRatio: 2,
        );
        try {
          final detailBytes = await detail.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '$directory/$name-detail.png',
          ).writeAsBytes(detailBytes!.buffer.asUint8List());
        } finally {
          detail.dispose();
        }
      }
    } finally {
      image.dispose();
    }
  });
}
