import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 344×88 canvas: a 320×64 field with a 12px inset on every side.
const _background = Color(0xff181818);
const _canvasWidth = 344;

final _colors =
    ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ).copyWith(
      surface: _background,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xffa3a3a3),
      outlineVariant: const Color(0x26ffffff),
      primary: const Color(0xff737373),
      error: const Color(0xffef4444),
    );

final _theme = ThemeData(
  platform: TargetPlatform.macOS,
  colorScheme: _colors,
  fontFamily: 'TextareaReference',
);

/// Radius 10 with deliberately different border and input roles so a render
/// proves the input role was used.
final _tokens = DTokens.fromTheme(
  _theme,
).copyWith(radius: 10, border: Colors.purple);

ThemeData _resolve({required bool dark}) => dark
    ? _theme.copyWith(extensions: [_tokens])
    : _theme.copyWith(
        brightness: Brightness.light,
        colorScheme: _colors.copyWith(
          brightness: Brightness.light,
          surface: Colors.white,
          onSurface: Colors.black,
          outlineVariant: const Color(0xffe5e5e5),
        ),
        extensions: [
          _tokens.copyWith(
            colors: _colors.copyWith(
              brightness: Brightness.light,
              onSurface: Colors.black,
              outlineVariant: const Color(0xffe5e5e5),
            ),
          ),
        ],
      );

Future<void> _loadReferenceFont(WidgetTester tester) async {
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

/// Renders one state from an unfocused, settled field; [settle] false captures
/// the first frame after the focus change instead of the finished transition.
Future<List<int>> _render(
  WidgetTester tester, {
  required GlobalKey key,
  required FocusNode focus,
  bool invalid = false,
  bool focused = false,
  bool enabled = true,
  bool dark = true,
  bool settle = true,
  String? export,
}) async {
  focus.unfocus();
  await tester.pumpWidget(
    MaterialApp(
      theme: _resolve(dark: dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: dark ? _background : Colors.white,
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
  await tester.pump(const Duration(milliseconds: 200));
  if (focused) {
    focus.requestFocus();
  } else {
    focus.unfocus();
  }
  // Focus changes apply in a microtask; the second pump draws the frame that
  // starts the transition.
  await tester.pump();
  await tester.pump();
  if (settle) await tester.pump(const Duration(milliseconds: 200));
  return (await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
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

List<int> _pixel(List<int> bytes, int x, int y) =>
    bytes.sublist((y * _canvasWidth + x) * 4, (y * _canvasWidth + x) * 4 + 4);

void main() {
  testWidgets('input alpha and exterior rings preserve interior pixels', (
    tester,
  ) async {
    final export = Platform.environment['TEXTAREA_EXPORT'];
    if (export != null) await _loadReferenceFont(tester);
    final key = GlobalKey();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Future<List<int>> render({
      bool invalid = false,
      bool focused = false,
      bool enabled = true,
      bool dark = true,
    }) => _render(
      tester,
      key: key,
      focus: focus,
      invalid: invalid,
      focused: focused,
      enabled: enabled,
      dark: dark,
      export: export,
    );
    final normal = await render();
    final focused = await render(focused: true);
    final invalid = await render(invalid: true);
    expect(_pixel(normal, 170, 65), _pixel(focused, 170, 65));
    expect(_pixel(normal, 170, 65), _pixel(invalid, 170, 65));
    // .149 * .3 input alpha over #181818, with rounding to the nearest byte.
    expect(_pixel(normal, 170, 65)[0], closeTo(34, 1));
    expect(_pixel(normal, 170, 8), [24, 24, 24, 255]);
    expect(_pixel(focused, 170, 8), [24, 24, 24, 255]);
    expect(_pixel(focused, 170, 10), isNot(_pixel(normal, 170, 10)));
    expect(_pixel(invalid, 170, 10), isNot(_pixel(normal, 170, 10)));
    final disabled = await render(enabled: false);
    expect(_pixel(disabled, 170, 65)[0], closeTo(38, 1));
    await render(dark: false);
    await render(dark: false, focused: true);
    await render(dark: false, invalid: true);
    await render(dark: false, enabled: false);
  });

  testWidgets('the focus ring paints at once while the border color eases', (
    tester,
  ) async {
    final key = GlobalKey();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final normal = await _render(tester, key: key, focus: focus);
    final settled = await _render(
      tester,
      key: key,
      focus: focus,
      focused: true,
    );
    final first = await _render(
      tester,
      key: key,
      focus: focus,
      focused: true,
      settle: false,
    );
    // Row 10 lies in the 3px exterior ring; row 12 is the 1px border.
    expect(_pixel(first, 170, 10), _pixel(settled, 170, 10));
    expect(_pixel(first, 170, 10), isNot(_pixel(normal, 170, 10)));
    expect(_pixel(first, 170, 12), _pixel(normal, 170, 12));
    expect(_pixel(settled, 170, 12), isNot(_pixel(normal, 170, 12)));
  });
}
