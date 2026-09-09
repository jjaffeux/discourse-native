// Manual font-loaded render evidence; does not launch a native application.
// flutter test --no-pub tool/native_select_render_test.dart \
//   --dart-define=NATIVE_SELECT_EVIDENCE=/absolute/evidence/directory
// The directory must contain Geist.ttf and NotoSansArabic.ttf exported from
// the observed official page assets; production fonts remain inherited.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/native_select_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const evidence = String.fromEnvironment('NATIVE_SELECT_EVIDENCE');
final boundaryKey = GlobalKey();

Future<void> loadReviewFonts() async {
  for (final item in {
    'MaterialIcons': '$evidence/MaterialIcons-Regular.otf',
    'Geist': '$evidence/Geist.ttf',
    'Noto Sans Arabic': '$evidence/NotoSansArabic.ttf',
    '.AppleSystemUIFont': '/System/Library/Fonts/SFNS.ttf',
    '.SF UI Text': '/System/Library/Fonts/SFNS.ttf',
    '.SF UI Display': '/System/Library/Fonts/SFNS.ttf',
    'Native Arabic': '/System/Library/Fonts/SFArabic.ttf',
  }.entries) {
    final loader = FontLoader(item.key)
      ..addFont(File(item.value).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(
    '$evidence/flutter-$name.png',
  ).writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}

ThemeData referenceTheme(bool dark, {bool arabic = false}) {
  final base = dark ? AppTheme.dark : AppTheme.light;
  final colors = base.colorScheme.copyWith(
    surface: dark ? const Color(0xff0a0a0a) : Colors.white,
    onSurface: dark ? const Color(0xfffafafa) : Colors.black,
    onSurfaceVariant: dark ? const Color(0xffa1a1a1) : const Color(0xff737373),
    outlineVariant: dark ? const Color(0x26ffffff) : const Color(0xffe5e5e5),
    primary: const Color(0xffa1a1a1),
    error: dark ? const Color(0xffff6467) : const Color(0xffe7000b),
  );
  return base.copyWith(
    platform: TargetPlatform.macOS,
    scaffoldBackgroundColor: colors.surface,
    colorScheme: colors,
    textTheme: base.textTheme.apply(
      fontFamily: arabic ? 'Noto Sans Arabic' : 'Geist',
    ),
    extensions: [
      base.extension<DTokens>()!.copyWith(colors: colors, radius: 10),
    ],
  );
}

void main() {
  testWidgets(
    'capture registered examples with loaded reference and host fonts',
    (tester) async {
      debugDisableShadows = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.runAsync(loadReviewFonts);
      tester.view.physicalSize = const Size(390, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final measurements = <Object>[];
      for (final dark in [false, true]) {
        for (final host in [false, true]) {
          for (final scale in [1.0, 2.0]) {
            for (final example in nativeSelectExamples.examples) {
              final name =
                  '${dark ? 'dark' : 'light'}-${host ? 'host' : 'reference'}-${scale.toInt()}-${example.title.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}';
              final theme = host
                  ? (dark ? AppTheme.dark : AppTheme.light).copyWith(
                      platform: TargetPlatform.macOS,
                      textTheme: (dark ? AppTheme.dark : AppTheme.light)
                          .textTheme
                          .apply(fontFamilyFallback: const ['Native Arabic']),
                    )
                  : referenceTheme(dark, arabic: example.title.contains('RTL'));
              await tester.pumpWidget(
                RepaintBoundary(
                  key: boundaryKey,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme,
                    home: Scaffold(
                      body: MediaQuery(
                        data: MediaQueryData(
                          textScaler: TextScaler.linear(scale),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: scale == 1 ? 342 : 240,
                            child: SingleChildScrollView(
                              child: Builder(builder: example.builder),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: name);
              for (final anchor in find.byType(MenuAnchor).evaluate()) {
                final selector = find.byElementPredicate((e) => e == anchor);
                final text = find
                    .descendant(of: selector, matching: find.byType(Text))
                    .first;
                final artwork = find
                    .descendant(
                      of: selector,
                      matching: find.byType(CustomPaint),
                    )
                    .last;
                final rect = tester.getRect(selector);
                final textRect = tester.getRect(text);
                measurements.add({
                  'name': name,
                  'control': [rect.left, rect.top, rect.width, rect.height],
                  'text': [
                    textRect.left,
                    textRect.top,
                    textRect.width,
                    textRect.height,
                  ],
                  'label': tester.widget<Text>(text).data,
                  'font': tester.widget<Text>(text).style?.fontFamily,
                  'icon': tester.getRect(artwork).toString(),
                });
              }
              await tester.runAsync(() => capture(tester, name));
              if (!host && scale == 1 && example.title == 'Reference status') {
                tester
                    .widget<FocusableActionDetector>(
                      find.byType(FocusableActionDetector).first,
                    )
                    .focusNode!
                    .requestFocus();
                await tester.sendKeyEvent(
                  LogicalKeyboardKey.keyB,
                  character: 'b',
                );
                await tester.pumpAndSettle();
                await tester.runAsync(() => capture(tester, '$name-focused'));
              }
              if (!host &&
                  scale == 1 &&
                  example.title == 'Reference departments') {
                await tester.tap(find.byType(MenuAnchor));
                await tester.pumpAndSettle();
                await tester.runAsync(() => capture(tester, '$name-open'));
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                await tester.pumpAndSettle();
              }
            }
          }
        }
      }
      await tester.runAsync(
        () => File('$evidence/flutter-metrics.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(measurements),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    },
    skip: evidence.isEmpty,
  );
}
