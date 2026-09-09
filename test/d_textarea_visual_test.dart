import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('input alpha and exterior rings preserve interior pixels', (
    tester,
  ) async {
    final export = Platform.environment['TEXTAREA_EXPORT'];
    if (export != null) {
      final loader = FontLoader('TextareaReference')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '/System/Library/Fonts/Supplemental/Arial.ttf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await tester.runAsync(loader.load);
    }
    final key = GlobalKey();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    const background = Color(0xff181818);
    final colors =
        ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ).copyWith(
          surface: background,
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xffa3a3a3),
          outlineVariant: const Color(0x26ffffff),
          primary: const Color(0xff737373),
          error: const Color(0xffef4444),
        );
    final theme = ThemeData(
      platform: TargetPlatform.macOS,
      colorScheme: colors,
      fontFamily: 'TextareaReference',
    );
    final tokens = DTokens.fromTheme(
      theme,
    ).copyWith(radius: 10, border: Colors.purple);
    Future<List<int>> render({
      bool invalid = false,
      bool focused = false,
      bool enabled = true,
      bool dark = true,
    }) async {
      final current = dark
          ? theme.copyWith(extensions: [tokens])
          : theme.copyWith(
              brightness: Brightness.light,
              colorScheme: colors.copyWith(
                brightness: Brightness.light,
                surface: Colors.white,
                onSurface: Colors.black,
                outlineVariant: const Color(0xffe5e5e5),
              ),
              extensions: [
                tokens.copyWith(
                  colors: colors.copyWith(
                    brightness: Brightness.light,
                    onSurface: Colors.black,
                    outlineVariant: const Color(0xffe5e5e5),
                  ),
                ),
              ],
            );
      await tester.pumpWidget(
        MaterialApp(
          theme: current,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: dark ? background : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 320,
                      child: DTextarea(
                        focusNode: focus,
                        hintText: 'Type your message here.',
                        invalid: invalid,
                        enabled: enabled,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (focused) {
        focus.requestFocus();
      } else {
        focus.unfocus();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      return (await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData();
        if (export != null) {
          final file = File(
            '$export/${dark ? 'dark' : 'light'}-${!enabled
                ? 'disabled'
                : invalid
                ? 'invalid'
                : focused
                ? 'focus'
                : 'default'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List(),
          );
        }
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    List<int> pixel(List<int> bytes, int x, int y) =>
        bytes.sublist((y * 344 + x) * 4, (y * 344 + x) * 4 + 4);
    final normal = await render();
    final focused = await render(focused: true);
    final invalid = await render(invalid: true);
    expect(pixel(normal, 170, 65), pixel(focused, 170, 65));
    expect(pixel(normal, 170, 65), pixel(invalid, 170, 65));
    // .149 * .3 input alpha over #181818, with rounding to the nearest byte.
    expect(pixel(normal, 170, 65)[0], closeTo(34, 1));
    expect(pixel(normal, 170, 8), [24, 24, 24, 255]);
    expect(pixel(focused, 170, 8), [24, 24, 24, 255]);
    expect(pixel(focused, 170, 10), isNot(pixel(normal, 170, 10)));
    expect(pixel(invalid, 170, 10), isNot(pixel(normal, 170, 10)));
    final disabled = await render(enabled: false);
    expect(pixel(disabled, 170, 65)[0], closeTo(38, 1));
    await render(dark: false);
    await render(dark: false, focused: true);
    await render(dark: false, invalid: true);
    await render(dark: false, enabled: false);
  });
}
