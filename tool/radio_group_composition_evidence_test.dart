import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/radio_group_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const output = 'docs/component-library/evidence/radio-group/final-compositions';
ThemeData neutral(bool dark) {
  final base = dark ? AppTheme.dark : AppTheme.light;
  final bg = Color(dark ? 0xff0a0a0a : 0xffffffff);
  final fg = Color(dark ? 0xfffafafa : 0xff0a0a0a);
  final muted = Color(dark ? 0xff262626 : 0xfff5f5f5);
  final colors = base.colorScheme.copyWith(
    surface: bg,
    onSurface: fg,
    primary: Color(dark ? 0xffe5e5e5 : 0xff000000),
    onPrimary: Color(dark ? 0xff171717 : 0xfffafafa),
    outlineVariant: dark ? const Color(0x26ffffff) : const Color(0xffe5e5e5),
    error: Color(dark ? 0xffff6467 : 0xffe7000b),
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: bg,
    extensions: [
      ...base.extensions.values.where((x) => x is! DTokens),
      DTokens(
        colors: colors,
        background: bg,
        surface: bg,
        muted: muted,
        border: dark ? const Color(0x26ffffff) : const Color(0xffe5e5e5),
        hover: muted,
        selected: muted,
        selectedForeground: fg,
        radius: 10,
      ),
    ],
  );
}

void main() {
  testWidgets(
    'export font-loaded Radio compositions',
    (tester) async {
      Directory(output).createSync(recursive: true);
      await tester.runAsync(() async {
        for (final family in [
          '.AppleSystemUIFont',
          'Roboto',
          'SF Pro Text',
          'SF Pro Display',
        ]) {
          await (FontLoader(family)..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync(),
                  ),
                ),
              ))
              .load();
        }
        await (FontLoader('Review Arabic')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('/System/Library/Fonts/SFArabic.ttf').readAsBytesSync(),
                ),
              ),
            ))
            .load();
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(
                ByteData.sublistView(
                  File(
                    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                  ).readAsBytesSync(),
                ),
              ),
            ))
            .load();
      });

      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> save(String name, Finder boundary) async {
        await tester.runAsync(() async {
          final render = tester.renderObject<RenderRepaintBoundary>(boundary);
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$output/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final measurements = <String, Object?>{};
      Future<void> capture(
        String name,
        ThemeData theme,
        String title, {
        double width = 440,
        double height = 320,
        double scale = 1,
        bool rtl = false,
        bool focus = false,
      }) async {
        tester.view.physicalSize = Size(width, height);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(
                  fontFamilyFallback: ['Review Arabic'],
                ),
              ),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, height),
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Builder(
                          builder: radioGroupExamples.examples
                              .singleWhere((e) => e.title == title)
                              .builder,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (focus) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: name);
        final radios = title == 'Default'
            ? find.byType(RawRadio<String>)
            : find.byType(DField);
        final bounds = [
          for (final e in radios.evaluate())
            tester.getRect(find.byWidget(e.widget)),
        ];
        measurements[name] = {
          'rows': [
            for (final r in bounds)
              {'x': r.left, 'y': r.top, 'width': r.width, 'height': r.height},
          ],
          'groupHeight': bounds.last.bottom - bounds.first.top,
          'indicators': [
            for (final element in find.byType(RawRadio<String>).evaluate())
              {
                'width': tester.getSize(find.byWidget(element.widget)).width,
                'height': tester.getSize(find.byWidget(element.widget)).height,
              },
          ],
          if (find.byType(DFieldLegend).evaluate().isNotEmpty)
            'headerDescriptionGap':
                tester.getTopLeft(find.byType(DFieldDescription).first).dy -
                tester.getBottomLeft(find.byType(DFieldLegend)).dy,
          if (title == 'Choice Card')
            'cardHeight': tester
                .getSize(
                  find
                      .byWidgetPredicate(
                        (widget) => widget is DFieldLabel && widget.choice,
                      )
                      .first,
                )
                .height,
        };
        File('$output/measurements.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(measurements),
        );
        await save(name, find.byKey(key));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }

      for (final dark in [false, true]) {
        final prefix = dark ? 'dark' : 'light';
        for (final title in [
          'Default',
          'Description',
          'Choice Card',
          'Fieldset',
          'Disabled',
          'Invalid',
          'RTL',
        ]) {
          await capture(
            'flutter-$prefix-${title.toLowerCase().replaceAll(' ', '-')}',
            neutral(dark),
            title,
          );
        }
        await capture(
          'flutter-$prefix-card-focus',
          neutral(dark),
          'Choice Card',
          focus: true,
        );
      }
      for (final palette in [StyleguideTheme.forest, StyleguideTheme.plum]) {
        await capture(
          'flutter-${palette.name}-card-rtl200',
          palette.resolve(AppTheme.light),
          'Choice Card',
          width: 360,
          height: 650,
          scale: 2,
          rtl: true,
        );
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    skip:
        !Platform.isMacOS ||
        !const bool.fromEnvironment('RADIO_REVIEW_EVIDENCE'),
  );
}
