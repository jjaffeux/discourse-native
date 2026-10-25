import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_conversation_header.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = ValueKey('chat-header-render');

void main() {
  setUpAll(() async {
    await (FontLoader(
      'HeaderReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });

  for (final width in [390.0, 1100.0]) {
    {
      for (final thread in [false, true]) {
        testWidgets('conversation header $width flat thread=$thread', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(width, 700));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final theme = AppTheme.dark;
          Widget header(bool compact) => ChatConversationHeader(
            key: ValueKey(compact ? 'compact' : 'full'),
            title: thread
                ? 'Rate limiting logging added by Discourse'
                : 'general',
            kindLabel: thread ? 'Thread in #general' : 'Channel',
            color: const Color(0xff888888),
            messageCount: 19,
            threadCount: thread ? 1 : 3,
            latest: DateTime(2026, 10, 15, 11, 14),
            now: DateTime(2026, 10, 15, 12),
            compact: compact,
          );
          late DPageHeaderGeometry geometry;
          await tester.pumpWidget(
            RepaintBoundary(
              key: _capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.copyWith(
                  platform: width < 500
                      ? TargetPlatform.iOS
                      : TargetPlatform.macOS,
                  textTheme: theme.textTheme.apply(fontFamily: 'HeaderReview'),
                ),
                home: Scaffold(
                  body: DPageSurface.scrollable(
                    framed: false,
                    hideHeaderOnScroll: true,
                    measureCompactHeader: true,
                    limitContentSize: true,
                    header: header(false),
                    compactHeader: header(true),
                    bodyBuilder: (_, value) {
                      geometry = value;
                      return ListView(
                        controller: scroll,
                        children: [
                          value.spacer,
                          for (var i = 0; i < 40; i++)
                            const SizedBox(height: 60),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final fullExtent = geometry.naturalExtent;
          final marker = find.byKey(
            const ValueKey('chat-channel-header-marker'),
          );
          final title = find
              .byType(DText)
              .evaluate()
              .map((element) => element.widget as DText)
              .singleWhere((text) => text.headingLevel == 1);
          expect(title.variant, DTextVariant.h3);
          expect(tester.getSize(marker), const Size.square(12));
          final titleRect = tester.getRect(find.byWidget(title));
          expect(titleRect.left - tester.getRect(marker).right, 10);
          expect(
            find.byKey(const ValueKey('content-header-separator')),
            findsOneWidget,
          );
          final name = '${width.toInt()}-flat-${thread ? 'thread' : 'channel'}';
          await _export(tester, '$name-full');

          scroll.jumpTo(200);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('compact')), findsOneWidget);
          expect(find.byKey(const ValueKey('full')), findsNothing);
          expect(geometry.naturalExtent, fullExtent);
          expect(scroll.offset, 200);
          expect(
            find.byKey(const ValueKey('content-header-separator')),
            findsNothing,
          );
          expect(tester.getSize(marker), const Size.square(10));
          final count = find.byKey(
            const ValueKey('chat-compact-message-count'),
          );
          expect(find.text('19 messages'), findsOneWidget);
          final compactTitle = find
              .byType(DText)
              .evaluate()
              .map((element) => element.widget as DText)
              .singleWhere((text) => text.headingLevel == 1);
          expect(
            tester.getRect(find.byWidget(compactTitle)).right,
            lessThanOrEqualTo(tester.getRect(count).left - 8),
          );
          await _export(tester, '$name-compact');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final rtl in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets('narrow large text compact=$compact rtl=$rtl', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: ChatConversationHeader(
                    title: 'A very long conversation title that must truncate',
                    kindLabel: 'Thread in #a-long-channel-name',
                    messageCount: 12345,
                    partial: true,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final marker = tester.getRect(
          find.byKey(const ValueKey('chat-channel-header-marker')),
        );
        expect(rtl ? marker.right : marker.left, rtl ? 304 : 16);
        if (compact) {
          final count = tester.getRect(
            find.byKey(const ValueKey('chat-compact-message-count')),
          );
          expect(count.left, greaterThanOrEqualTo(16));
          expect(count.right, lessThanOrEqualTo(304));
        }
      });
    }
  }
}

Future<void> _export(WidgetTester tester, String name) async {
  final directory = Platform.environment['CHAT_HEADER_EXPORT_DIR'];
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
