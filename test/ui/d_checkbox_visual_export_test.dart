import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/plugins/voice/voice_join.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/styleguide/examples/checkbox_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final output = Platform.environment['CHECKBOX_EXPORT_DIR'];
  testWidgets('font-loaded checkbox examples and real application fixtures', (
    tester,
  ) async {
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
      await (FontLoader('Review Hebrew')..addFont(
            Future.value(
              ByteData.sublistView(
                File('/System/Library/Fonts/SFHebrew.ttf').readAsBytesSync(),
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
    Future<void> capture(
      String name,
      ThemeData theme,
      Widget child, {
      double width = 384,
      double height = 360,
      double scale = 1,
      bool rtl = false,
      int tabs = 0,
      bool legal = false,
    }) async {
      final boundaryKey = GlobalKey();
      tester.view.physicalSize = Size(width, height);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              platform: TargetPlatform.macOS,
              textTheme: theme.textTheme.apply(
                fontFamilyFallback: ['Review Arabic', 'Review Hebrew'],
              ),
            ),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: child,
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
      for (var i = 0; i < tabs; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      if (legal) {
        await tester.enterText(
          find.byType(TextField),
          'Local review explanation',
        );
        await tester.tap(
          find.byKey(const ValueKey('post-flag-illegal-confirmation')),
        );
        await tester.pumpAndSettle();
      }
      if (name.contains('voice')) {
        await tester.ensureVisible(find.text("Don't show this again"));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), null, reason: name);
      await tester.runAsync(() async {
        final image =
            await (boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$output/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }

    for (final palette in [StyleguideTheme.light, StyleguideTheme.dark]) {
      final theme = palette.resolve(AppTheme.light);
      for (var i = 0; i < checkboxExamples.examples.length; i++) {
        await capture(
          'flutter-${palette.name}-example-$i',
          theme,
          Builder(builder: checkboxExamples.examples[i].builder),
          width: i == 3 ? 600 : 408,
          height: i == 5 ? 460 : 360,
        );
      }
      await capture(
        'flutter-${palette.name}-card-focus',
        theme,
        Builder(builder: checkboxExamples.examples[0].builder),
        width: 408,
        tabs: 3,
      );
    }
    for (final palette in [StyleguideTheme.forest, StyleguideTheme.plum]) {
      await capture(
        'flutter-${palette.name}-rtl200',
        palette.resolve(AppTheme.light),
        Builder(builder: checkboxExamples.examples[5].builder),
        width: 360,
        height: 800,
        scale: 2,
        rtl: true,
      );
    }
    await capture(
      'flutter-real-legal-light',
      AppTheme.light,
      PostFlagEditor(
        siteUrl: 'https://checkbox.example.test',
        targetUsername: 'sample',
        flagTypes: const [
          PostFlagType(
            id: 8,
            nameKey: 'illegal',
            name: 'Illegal',
            description: '<p>This may break the law.</p>',
            requireMessage: true,
            appliesTo: ['Post'],
          ),
        ],
        minimumMessageLength: 5,
        save: (type, {message}) async => 'Local fixture error',
        onComplete: () {},
      ),
      width: 360,
      height: 560,
      legal: true,
    );
    await capture(
      'flutter-real-voice-plum-rtl200',
      StyleguideTheme.plum.resolve(AppTheme.light),
      const VoiceMeshPrivacyDialog(),
      width: 360,
      height: 800,
      scale: 2,
      rtl: true,
    );
  }, skip: output == null);
}
