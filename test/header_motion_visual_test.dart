import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_post_list.dart';
import 'support/topic_scroll_fixture.dart';

const _capture = ValueKey('header-motion-render');
Future<void> _export(WidgetTester tester, String name) async {
  final directory = Platform.environment['HEADER_MOTION_EXPORT_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'HeaderReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [const Size(390, 844), const Size(1100, 800)]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'production topic motion ${size.width} dark=$dark scale=$scale',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final controller = await topicScrollController();
            addTearDown(controller.dispose);
            final theme = dark ? AppTheme.dark : AppTheme.light;
            await tester.pumpWidget(
              ShellScope(
                controller: controller,
                child: RepaintBoundary(
                  key: _capture,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme.copyWith(
                      platform: size.width < 500
                          ? TargetPlatform.iOS
                          : TargetPlatform.macOS,
                      textTheme: theme.textTheme.apply(
                        fontFamily: 'HeaderReview',
                      ),
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: Scaffold(
                      body: TopicView(
                        inbox: true,
                        route: controller.currentContent,
                      ),
                    ),
                  ),
                ),
              ),
            );
            for (var frame = 0; frame < 40; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            final viewport = topicPostListFinder();
            final header = DPageSurface.headerGeometryOf(
              tester.element(viewport),
            )!;
            final position = topicPostList(tester).controller!.position;
            position.jumpTo(700);
            for (var frame = 0; frame < 40; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            final viewportRect = tester.getRect(viewport);
            final name =
                '${size.width.toInt()}-${dark ? 'dark' : 'light'}-${scale.toInt()}x';
            await _export(tester, '$name-shown');
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: topicReadingViewportRect(tester).center,
                scrollDelta: Offset(0, header.naturalExtent * .5),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 40));
            expect(
              header.visibleExtent,
              inExclusiveRange(0, header.naturalExtent),
            );
            expect(tester.getRect(viewport), viewportRect);
            await _export(tester, '$name-partial');
            for (var frame = 0; frame < 40; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(header.visibleExtent, 0);
            expect(tester.getRect(viewport), viewportRect);
            await _export(tester, '$name-hidden');
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
