import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['TOPIC_FEED_CAPTURE_DIR'] == null) return;
    await (FontLoader('TopicFeedReview')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final dark in [false, true]) {
      final scenario = '${platform.name}-flat-${dark ? 'dark' : 'light'}';
      testWidgets('feed menu adapts and scrolls ($scenario)', (tester) async {
        final mobile = platform != TargetPlatform.macOS;
        final size = mobile ? const Size(390, 844) : const Size(1100, 720);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.reset);
        var mode = TopicListMode.latest;
        late StateSetter rebuild;
        final base = dark ? AppTheme.dark : AppTheme.light;
        final theme = base.copyWith(
          platform: platform,
          textTheme: Platform.environment['TOPIC_FEED_CAPTURE_DIR'] == null
              ? base.textTheme
              : base.textTheme.apply(fontFamily: 'TopicFeedReview'),
        );
        final trigger = find.byKey(const ValueKey('topic-list-feed-menu'));
        final menu = find.byType(DDropdownMenuContent);

        for (final scale in [1.0, 2.0]) {
          mode = TopicListMode.latest;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('topic-feed-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                    padding: const EdgeInsets.only(top: 44, bottom: 34),
                  ),
                  child: Scaffold(
                    body: StatefulBuilder(
                      builder: (context, setState) {
                        rebuild = setState;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 130, 16, 16),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: TopicFeedMenu(
                              mode: mode,
                              unifiedNew: true,
                              unreadCount: 2589,
                              newCount: 2677,
                              topicCount: 88,
                              replyCount: 2589,
                              onSelected: (value) =>
                                  rebuild(() => mode = value),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(trigger);
          await tester.pumpAndSettle();

          expect(find.text('Choose topic feed'), findsNothing);
          expect(find.byType(DSheetClose), findsNothing);
          expect(menu, findsOneWidget);
          if (mobile) {
            final sheet = find.byType(DSheetContent);
            expect(sheet, findsOneWidget);
            expect(tester.widget<DSheetContent>(sheet).side, DSheetSide.bottom);
            expect(
              tester.widget<DSheetContent>(sheet).variant,
              DSheetVariant.adaptiveMenu,
            );
            expect(find.byType(DSheetHeader), findsNothing);
            expect(
              find.byKey(const ValueKey('sheet-drag-handle')),
              findsOneWidget,
            );
            final bounds = tester.getRect(sheet);
            expect(bounds.width, size.width);
            expect(bounds.top, closeTo(size.height * .45, 1));
          } else {
            expect(find.byType(DSheetContent), findsNothing);
            final bounds = tester.getRect(menu);
            expect(bounds.left, closeTo(tester.getRect(trigger).left, 1));
            expect(
              bounds.top,
              closeTo(
                tester.getRect(trigger).bottom +
                    tester.widget<DDropdownMenuContent>(menu).sideOffset,
                1,
              ),
            );
            expect(bounds.width, 304);
            expect(bounds.bottom, lessThanOrEqualTo(size.height - 34));
          }
          expect(find.byType(DDropdownMenuGroup), findsNWidgets(2));
          for (final (key, count) in [
            ('unread', '2589'),
            ('new-all', '2677'),
            ('new-topics', '88'),
            ('new-replies', '2589'),
          ]) {
            expect(
              find.descendant(
                of: find.byKey(ValueKey('topic-list-$key')),
                matching: find.text(count),
              ),
              findsOneWidget,
            );
          }
          expect(
            tester.widget<DDropdownMenuContent>(menu).semanticLabel,
            'Choose topic feed',
          );
          await _capture(tester, '$scenario-$scale');

          if (mobile) {
            await tester.drag(
              find.byKey(const ValueKey('sheet-drag-handle')),
              const Offset(0, -350),
            );
            await tester.pumpAndSettle();
            expect(
              tester.getTopLeft(find.byType(DSheetContent)).dy,
              lessThan(size.height * .45 - 1),
            );
          }
          final allTime = find.byKey(
            const ValueKey('topic-list-top-period-all'),
          );
          await tester.ensureVisible(allTime);
          await tester.pumpAndSettle();
          await _capture(tester, '$scenario-$scale-scrolled');
          await tester.tap(allTime);
          await tester.pumpAndSettle();
          expect(mode, TopicListMode.topAll);
          expect(menu, findsNothing);
          expect(tester.widget<DButton>(trigger).expanded, isFalse);
          if (!mobile) {
            expect(tester.widget<DButton>(trigger).focusNode!.hasFocus, isTrue);
          }

          await tester.tap(trigger);
          await tester.pumpAndSettle();
          final check = find.descendant(
            of: allTime,
            matching: find.byType(DIcon),
          );
          expect(check, findsOneWidget);
          await tester.tapAt(Offset(size.width - 16, 80));
          await tester.pumpAndSettle();
          expect(menu, findsNothing);
          expect(mode, TopicListMode.topAll);

          await tester.tap(trigger);
          await tester.pumpAndSettle();
          if (mobile) {
            final handle = find.byKey(const ValueKey('sheet-drag-handle'));
            await tester.drag(handle, const Offset(0, -350));
            await tester.pumpAndSettle();
            expect(
              tester.getTopLeft(find.byType(DSheetContent)).dy,
              lessThan(size.height * .45 - 1),
            );
            await tester.drag(handle, const Offset(0, 700));
            await tester.pumpAndSettle();
            expect(mode, TopicListMode.topAll);
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.end);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(mode, TopicListMode.popular);
          }
          expect(menu, findsNothing);

          await tester.tap(trigger);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(menu, findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['TOPIC_FEED_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('topic-feed-capture')),
        )
        .toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
