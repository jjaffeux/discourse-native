import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _background = Color(0xff101010);
const _boundary = ValueKey('input-pixels');

ThemeData _theme({bool dark = true, Color? inputColor}) {
  final colors = (dark ? const ColorScheme.dark() : const ColorScheme.light())
      .copyWith(
        surface: dark ? _background : Colors.white,
        onSurface: dark ? Colors.white : Colors.black,
        outlineVariant: inputColor ?? Colors.white.withValues(alpha: .15),
        primary: Colors.red.withValues(alpha: .6),
        error: Colors.green.withValues(alpha: .8),
      );
  return ThemeData(
    colorScheme: colors,
    platform: TargetPlatform.macOS,
    fontFamily: 'InputPixelFont',
    extensions: [
      DTokens(
        colors: colors,
        background: colors.surface,
        surface: colors.surface,
        muted: colors.surface,
        border: Colors.purple,
        hover: Colors.transparent,
        selected: Colors.blue,
        selectedForeground: Colors.white,
        radius: 10,
      ),
    ],
  );
}

Future<Uint8List> _capture(
  WidgetTester tester,
  Widget child,
  String name, {
  ThemeData? theme,
}) async {
  theme ??= _theme();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _boundary,
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: SizedBox(
                width: 340,
                height: 72,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: KeyedSubtree(key: ValueKey(name), child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final directory = Platform.environment['INPUT_PIXEL_EXPORT_DIR'];
      if (directory != null) {
        final png = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png').writeAsBytes(png);
      }
      return bytes;
    } finally {
      image.dispose();
    }
  }))!;
}

Color _pixel(Uint8List data, int x, int y) {
  final offset = (y * 340 + x) * 4;
  return Color.fromARGB(
    data[offset + 3],
    data[offset],
    data[offset + 1],
    data[offset + 2],
  );
}

void _near(Color actual, Color expected) {
  final a = actual.toARGB32(), e = expected.toARGB32();
  for (final shift in [0, 8, 16]) {
    expect((a >> shift) & 255, closeTo((e >> shift) & 255, 2));
  }
}

int _brightest(Uint8List bytes, Rect bounds) {
  var maximum = 0;
  for (var y = bounds.top.ceil(); y < bounds.bottom.floor(); y++) {
    for (var x = bounds.left.ceil(); x < bounds.right.floor(); x++) {
      final red = bytes[(y * 340 + x) * 4];
      if (red > maximum) maximum = red;
    }
  }
  return maximum;
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('InputPixelFont')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    await loader.load();
  });

  testWidgets(
    'unfocused site input remains outlined on a matching dialog surface',
    (tester) async {
      final theme = AppTheme.fromPalette(
        ResolvedSitePalette.fromJson(const {
          'brightness': 'dark',
          'primary': 0xFFDDDDDD,
          'secondary': 0xFF222222,
          'tertiary': 0xFF0088CC,
          'primaryLow': 0xFF333333,
          'primaryLowMid': 0xFF777777,
          'secondaryVeryHigh': 0xFF333333,
        }),
      );
      final pixels = await _capture(
        tester,
        DInput(hintText: 'meta.discourse.org'),
        'site-dialog-unfocused',
        theme: theme.copyWith(
          platform: TargetPlatform.macOS,
          textTheme: theme.textTheme.apply(fontFamily: 'InputPixelFont'),
          colorScheme: theme.colorScheme.copyWith(
            surface: theme.shell.floating,
          ),
        ),
      );
      _near(
        _pixel(pixels, 20, 36),
        theme.extension<DTokens>()!.controls!.outline.border,
      );
      expect(_pixel(pixels, 20, 36), isNot(_pixel(pixels, 10, 36)));
    },
  );

  testWidgets(
    'translucent input fill uses input role and remains unchanged under exterior focus and invalid rings',
    (tester) async {
      final defaultPixels = await _capture(
        tester,
        DInput(hintText: 'Enter text'),
        'dark-default',
      );
      final fill = Color.alphaBlend(
        Colors.white.withValues(alpha: .15 * .3),
        _background,
      );
      _near(_pixel(defaultPixels, 280, 36), fill);
      _near(
        _pixel(defaultPixels, 20, 36),
        Color.alphaBlend(Colors.white.withValues(alpha: .15), fill),
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final focused = await _capture(
        tester,
        DInput(focusNode: focus, autofocus: true, hintText: 'Enter text'),
        'dark-focused',
      );
      _near(_pixel(focused, 280, 36), fill);
      _near(
        _pixel(focused, 18, 36),
        Color.alphaBlend(Colors.red.withValues(alpha: .6 * .5), _background),
      );
      _near(_pixel(focused, 16, 36), _background);
      final invalid = await _capture(
        tester,
        DInput(invalid: true, hintText: 'Error'),
        'dark-invalid',
      );
      _near(_pixel(invalid, 280, 36), fill);
      _near(
        _pixel(invalid, 18, 36),
        Color.alphaBlend(Colors.green.withValues(alpha: .8 * .4), _background),
      );
      final disabled = await _capture(
        tester,
        DInput(enabled: false, hintText: 'Email'),
        'dark-disabled',
      );
      _near(
        _pixel(disabled, 280, 36),
        Color.alphaBlend(
          Colors.white.withValues(alpha: .15 * .8 * .5),
          _background,
        ),
      );
    },
  );

  testWidgets(
    'light and custom alpha fills preserve the source modifier without ring bleed',
    (tester) async {
      for (final dark in [false, true]) {
        final theme = _theme(
          dark: dark,
          inputColor: Colors.blue.withValues(alpha: .35),
        );
        final image = await _capture(
          tester,
          DInput(invalid: true, hintText: 'Error'),
          dark ? 'custom-dark-invalid' : 'light-invalid',
          theme: theme,
        );
        _near(
          _pixel(image, 280, 36),
          dark
              ? Color.alphaBlend(
                  Colors.blue.withValues(alpha: .35 * .3),
                  _background,
                )
              : Colors.white,
        );
      }
    },
  );

  testWidgets(
    'disabled file trigger and filename receive one half-opacity treatment and remain noninteractive',
    (tester) async {
      var picks = 0;
      Future<List<String>?> pick() async {
        picks++;
        return ['file.txt'];
      }

      final enabled = await _capture(
        tester,
        DFileInput(onPick: pick),
        'file-enabled',
      );
      final offset = tester.getTopLeft(find.byKey(_boundary));
      final trigger = tester.getRect(find.text('Choose file')).shift(-offset);
      final filename = tester
          .getRect(find.text('No file chosen'))
          .shift(-offset);
      expect(trigger.right, lessThan(filename.left));
      final disabled = await _capture(
        tester,
        DFileInput(onPick: pick, enabled: false),
        'file-disabled',
      );
      final disabledOffset = tester.getTopLeft(find.byKey(_boundary));
      expect(
        tester.getRect(find.text('Choose file')).shift(-disabledOffset),
        trigger,
      );
      expect(
        tester.getRect(find.text('No file chosen')).shift(-disabledOffset),
        filename,
      );
      // Real font glyph cores are opaque white, not the square Ahem test font.
      expect(_brightest(enabled, trigger), greaterThan(245));
      expect(_brightest(enabled, filename), greaterThan(245));
      expect(_brightest(disabled, trigger), closeTo(136, 3));
      expect(_brightest(disabled, filename), closeTo(136, 3));
      expect(tester.widget<DButton>(find.byType(DButton)).onPressed, isNull);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        tester
            .getSemantics(find.byType(DButton))
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        ui.Tristate.isFalse,
      );
      semantics.dispose();
      await tester.tap(find.text('Choose file'), warnIfMissed: false);
      expect(picks, 0);
    },
  );
}
