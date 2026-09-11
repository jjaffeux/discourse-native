import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Optional font-loaded visual evidence, using the Button export convention:
// CHECKBOX_EXPORT_DIR=/absolute/path flutter test test/ui/d_checkbox_paint_test.dart
void main() {
  final exportDirectory = Platform.environment['CHECKBOX_EXPORT_DIR'];
  for (final (name, theme) in [
    ('app-light', AppTheme.light),
    ('app-dark', AppTheme.dark),
    (
      'site-dark',
      AppTheme.fromPalette(
        ResolvedSitePalette.fromJson(const {
          'brightness': 'dark',
          'primary': 0xffdddddd,
          'secondary': 0xff222222,
          'tertiary': 0xff0099cc,
          'contentBorderColor': 0xff333333,
          'secondaryVeryHigh': 0xff333333,
          'primaryLowMid': 0xff808080,
        }),
      ),
    ),
  ]) {
    testWidgets('$name paints the shared input border on a popup', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 96);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final boundaryKey = GlobalKey();
      final background = theme.extension<DTokens>()!.surface;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              backgroundColor: background,
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: DCheckbox(
                    value: false,
                    title: const Text('approved'),
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = tester.getRect(find.byType(AnimatedContainer));
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset =
            (control.center.dy.floor() * image.width + control.left.floor()) *
            4;
        final outline = Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
        expect(
          outline,
          theme.colorScheme.outlineVariant,
          reason:
              'The painted outline follows the shared subtle control theme.',
        );
        if (exportDirectory != null) {
          Directory(exportDirectory).createSync(recursive: true);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$exportDirectory/$name-popup.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        }
        image.dispose();
      });
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} unchecked focus and invalid rings stay outside translucent inputs',
      (tester) async {
        if (exportDirectory != null) {
          await tester.runAsync(() async {
            final font = ByteData.sublistView(
              File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync(),
            );
            for (final family in ['.AppleSystemUIFont', 'Roboto']) {
              await (FontLoader(family)..addFont(Future.value(font))).load();
            }
          });
        }
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 96);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final background = Color(dark ? 0xff101010 : 0xffffffff);
        const input = Color(0x2690a0b0);
        const focusColor = Color(0x804060c0);
        const error = Color(0x80e05050);
        final colors =
            ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: dark ? Brightness.dark : Brightness.light,
            ).copyWith(
              surface: background,
              outlineVariant: input,
              primary: focusColor,
              error: error,
            );
        final tokens = DTokens(
          colors: colors,
          background: background,
          surface: background,
          muted: background,
          border: const Color(0xffff00ff), // Must not supply border-input.
          hover: background,
          selected: background,
          selectedForeground: colors.onSurface,
        );
        final interior = dark
            ? Color.alphaBlend(
                input.withValues(alpha: input.a * .3),
                background,
              )
            : background;
        for (final state in ['default', 'focus', 'invalid']) {
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  platform: TargetPlatform.macOS,
                  colorScheme: colors,
                  scaffoldBackgroundColor: background,
                  extensions: [tokens],
                ),
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 280,
                      child: DCheckbox(
                        key: ValueKey(state),
                        value: false,
                        invalid: state == 'invalid',
                        title: Text('Unchecked · $state'),
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          if (state == 'focus') {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          }
          await tester.pumpAndSettle();
          final control = tester.getRect(find.byType(AnimatedContainer));
          expect(control.size, const Size(16, 16));
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            Color pixel(double x, double y) {
              final offset = (y.floor() * image.width + x.floor()) * 4;
              return Color.fromARGB(
                bytes.getUint8(offset + 3),
                bytes.getUint8(offset),
                bytes.getUint8(offset + 1),
                bytes.getUint8(offset + 2),
              );
            }

            void matches(Color actual, Color expected, String region) {
              for (final (a, e) in [
                (actual.r, expected.r),
                (actual.g, expected.g),
                (actual.b, expected.b),
              ]) {
                expect(
                  a,
                  closeTo(e, 2 / 255),
                  reason: '$state $region: $actual vs $expected',
                );
              }
            }

            matches(
              pixel(control.center.dx, control.center.dy),
              interior,
              'interior',
            );
            final ring = state == 'invalid'
                ? error.withValues(alpha: error.a * (dark ? .4 : .2))
                : state == 'focus'
                ? focusColor.withValues(alpha: focusColor.a * .5)
                : Colors.transparent;
            matches(
              pixel(control.left - 2, control.center.dy),
              Color.alphaBlend(ring, background),
              'exterior ring',
            );
            final border = state == 'invalid'
                ? (dark ? error.withValues(alpha: error.a * .5) : error)
                : state == 'focus'
                ? focusColor
                : input;
            matches(
              pixel(control.left, control.center.dy),
              Color.alphaBlend(border, interior),
              'inner border',
            );
            if (exportDirectory != null) {
              Directory(exportDirectory).createSync(recursive: true);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '$exportDirectory/${dark ? 'dark' : 'light'}-$state.png',
              ).writeAsBytesSync(png!.buffer.asUint8List());
            }
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
