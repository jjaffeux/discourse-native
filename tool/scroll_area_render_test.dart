// Run explicitly with flutter test tool/scroll_area_render_test.dart.
// Local font-loaded exports are review evidence, not native screenshots.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/scroll_area_review_main.dart' as fixture;
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      final loader = FontLoader(family);
      for (final path in [
        '/System/Library/Fonts/SFNS.ttf',
        '/System/Library/Fonts/SFArabic.ttf',
      ]) {
        loader.addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      }
      await loader.load();
    }
    final arabic = FontLoader('Review Arabic')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('/System/Library/Fonts/SFArabic.ttf').readAsBytesSync(),
          ),
        ),
      );
    await arabic.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final mono = FontLoader('JetBrains Mono')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'));
    await mono.load();
  });
  testWidgets(
    'export actual registered examples and migrated production fixtures',
    (tester) async {
      final out = Directory('/tmp/scroll-area-visual')
        ..createSync(recursive: true);
      final fixtureErrors = <String, String>{};
      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          for (final name in ['ornella', 'tom', 'vladimir']) {
            await precacheImage(
              AssetImage(
                'packages/discourse_native/src/styleguide/assets/scroll_area/$name.jpg',
              ),
              tester.element(find.byType(Scaffold).first),
            );
          }
        });
        await tester.pumpAndSettle();
        final boundary = tester.binding.renderViews.single;
        final layer = boundary.debugLayer! as OffsetLayer;
        await tester.runAsync(() async {
          final image = await layer.toImage(
            Offset.zero & tester.view.physicalSize,
          );
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${out.path}/$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        final error = tester.takeException();
        if (error != null && name.startsWith('fixture-')) {
          fixtureErrors[name] = error.toString();
        } else {
          expect(error, isNull, reason: name);
        }
      }

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 520);
      addTearDown(tester.view.reset);
      final themes = {
        'light': AppTheme.light,
        'dark': AppTheme.dark,
        'custom': AppTheme.light.copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff16734c)),
          extensions: [
            ...AppTheme.light.extensions.values.where((e) => e is! DTokens),
            DTokens.fromTheme(
              ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff16734c),
                ),
              ),
            ).copyWith(radius: 10),
          ],
        ),
      };
      for (final entry in themes.entries) {
        for (final (index, example)
            in componentExamples['scroll-area']!.examples.indexed) {
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              themeAnimationDuration: Duration.zero,
              theme: entry.value.copyWith(
                textTheme: entry.value.textTheme.copyWith(
                  bodyMedium: entry.value.textTheme.bodyMedium!.copyWith(
                    fontFamilyFallback: const ['Review Arabic'],
                  ),
                ),
              ),
              home: Scaffold(
                body: Center(child: Builder(builder: example.builder)),
              ),
            ),
          );
          await capture('flutter-${entry.key}-$index');
        }
      }
      tester.view.physicalSize = const Size(360, 720);
      for (final (index, example)
          in componentExamples['scroll-area']!.examples.indexed) {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            themeAnimationDuration: Duration.zero,
            theme: AppTheme.dark.copyWith(
              textTheme: AppTheme.dark.textTheme.copyWith(
                bodyMedium: AppTheme.dark.textTheme.bodyMedium!.copyWith(
                  fontFamilyFallback: const ['Review Arabic'],
                ),
              ),
            ),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        );
        await capture('flutter-narrow200-rtl-$index');
      }
      tester.view.physicalSize = const Size(480, 520);
      for (final focused in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            themeAnimationDuration: Duration.zero,
            theme: themes['custom'],
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 192,
                  height: 288,
                  child: DScrollArea(child: SizedBox(height: 1000)),
                ),
              ),
            ),
          ),
        );
        if (focused) {
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        }
        await capture('flutter-transparent-focus-$focused');
      }
      tester.view.physicalSize = const Size(1200, 850);
      await tester.runAsync(fixture.main);
      await tester.pumpAndSettle();
      for (final label in [
        'Sidebar',
        'Code',
        'Alerts',
        'Calendar',
        'Assignments',
        'Diagnostics',
        'Voice',
      ]) {
        await tester.tap(find.widgetWithText(DButton, label));
        await capture('fixture-${label.toLowerCase()}');
      }
      final review = tester.widget<fixture.ScrollAreaReviewApp>(
        find.byType(fixture.ScrollAreaReviewApp),
      );
      for (final scenario in ['custom', 'narrow200']) {
        tester.view.physicalSize = scenario == 'custom'
            ? const Size(1200, 850)
            : const Size(360, 1000);
        await tester.pumpWidget(
          fixture.ScrollAreaReviewApp(
            diagnostics: review.diagnostics,
            themeOverride: themes['custom'],
            textScale: scenario == 'custom' ? 1 : 2,
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [
          'Sidebar',
          'Code',
          'Alerts',
          'Calendar',
          'Assignments',
          'Diagnostics',
          'Voice',
        ]) {
          await tester.tap(find.widgetWithText(DButton, label));
          await capture('fixture-$scenario-${label.toLowerCase()}');
        }
      }
      File(
        '${out.path}/fixture-render-errors.json',
      ).writeAsStringSync(jsonEncode(fixtureErrors));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
