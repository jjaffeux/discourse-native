import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('closed hatch and rules hand over toward the trailing edge', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final direction in TextDirection.values) {
        for (final selected in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Directionality(
                  textDirection: direction,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      key: const ValueKey('paint'),
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: SizedBox(
                          width: 360,
                          child: DItem(
                            closed: true,
                            closedRuleAbove: true,
                            closedRuleBelow: true,
                            selected: selected,
                            selectionStyle: DItemSelectionStyle.filled,
                            showSelectionIndicator: false,
                            padding: const EdgeInsets.all(12),
                            children: const [SizedBox(height: 48)],
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
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('paint')),
          );
          final pixels = (await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final width = image.width;
            image.dispose();
            return (bytes: bytes, width: width);
          }))!;
          final bytes = pixels.bytes;
          Color pixel(int x, int y) {
            final offset = (y * pixels.width + x) * 4;
            return Color.fromARGB(
              bytes.getUint8(offset + 3),
              bytes.getUint8(offset),
              bytes.getUint8(offset + 1),
              bytes.getUint8(offset + 2),
            );
          }

          // The leading half is completely unhatched, including on selection.
          final clear = pixel(direction == TextDirection.ltr ? 30 : 329, 30);
          double ink(int start, int end, int top, int bottom) {
            var total = 0.0;
            for (var x = start; x < end; x++) {
              for (var y = top; y < bottom; y++) {
                final value = pixel(x, y);
                total += [
                  value.r - clear.r,
                  value.g - clear.g,
                  value.b - clear.b,
                ].map((channel) => (channel * 255).abs()).reduce(math.max);
              }
            }
            return total / ((end - start) * (bottom - top));
          }

          double directionalInk(int start, int end, int top, int bottom) =>
              direction == TextDirection.ltr
              ? ink(start, end, top, bottom)
              : ink(360 - end, 360 - start, top, bottom);
          expect(directionalInk(20, 150, 10, 62), 0);
          final nearEnd = directionalInk(320, 348, 10, 62);
          final transition = directionalInk(210, 238, 10, 62);
          expect(
            nearEnd,
            greaterThan(1),
            reason: "${theme.brightness}/$direction/$selected",
          );
          expect(nearEnd, greaterThan(transition * 2));
          // Rules retain the ordinary 12px inset and fade opposite the hatch.
          final tokens = DTokens.of(tester.element(find.byType(DItem)));
          final leadingX = direction == TextDirection.ltr ? 30 : 329;
          expect(pixel(leadingX, 0).toARGB32(), tokens.footerBorder.toARGB32());
          expect(
            pixel(leadingX, 71).toARGB32(),
            tokens.footerBorder.toARGB32(),
          );
          if (!selected) {
            expect(directionalInk(0, 10, 0, 1), lessThan(1));
          }
          if (selected) {
            expect(clear.toARGB32(), isNot(tokens.background.toARGB32()));
          } else {
            expect(clear.toARGB32(), tokens.background.toARGB32());
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  // Impeller shades each gradient-stroked line in its own offscreen pass, so
  // per-stroke draws made one visible closed row cost milliseconds of raster
  // time every frame on a wide desktop panel.
  testWidgets('closed hatch is one draw however wide the row', (tester) async {
    tester.view.physicalSize = const Size(2400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final direction in TextDirection.values) {
      for (final width in [360.0, 2200.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Directionality(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const DItem(
                    closed: true,
                    padding: EdgeInsets.all(12),
                    children: [SizedBox(height: 96)],
                  ),
                ),
              ),
            ),
          ),
        );
        final hatch = find.descendant(
          of: find.byType(DItem),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter.runtimeType.toString() == '_ClosedHatch',
          ),
        );
        final box = tester.renderObject<RenderCustomPaint>(hatch);
        expect(box, paintsExactlyCountTimes(#drawLine, 0));
        expect(box, paintsExactlyCountTimes(#drawPath, 1));
      }
    }
  });

  testWidgets('closed lock flows on the title first line and follows its ink', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final direction in TextDirection.values) {
      for (final width in [320.0, 900.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final read in [false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Directionality(
                      textDirection: direction,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: width,
                          child: TopicListRow(
                            siteUrl: 'https://example.com',
                            topic: Topic(
                              id: 1,
                              title: direction == TextDirection.ltr
                                  ? 'A closed topic with a long title that wraps across several lines ' *
                                        2
                                  : 'נושא סגור עם כותרת ארוכה שממשיכה לשורות נוספות ' *
                                        2,
                              slug: 'closed',
                              closed: true,
                              lastReadPostNumber: read ? 10 : null,
                              highestPostNumber: 10,
                            ),
                            onTap: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final title = find.byType(TopicTitle);
            final lock = find.byKey(const ValueKey('topic-row-lock-1'));
            final style = tester.widget<TopicTitle>(title).style!;
            expect(tester.widget<DIcon>(lock).color, style.color);
            expect(tester.widget<DIcon>(lock).size, 11);
            expect(
              tester
                  .widget<DTooltip>(
                    find
                        .ancestor(of: lock, matching: find.byType(DTooltip))
                        .first,
                  )
                  .message,
              'Closed',
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: title, matching: find.byType(RichText)).first,
            );
            final first = paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 1, extentOffset: 2),
                )
                .first
                .toRect()
                .shift(paragraph.localToGlobal(Offset.zero));
            expect(
              tester.getCenter(lock).dy,
              closeTo(first.center.dy, 2 * scale),
            );
            final gap = direction == TextDirection.ltr
                ? first.left - tester.getRect(lock).right
                : tester.getRect(lock).left - first.right;
            expect(gap, closeTo(style.fontSize! * .4 * scale, .1));
            final row = tester.getRect(
              find.byKey(const ValueKey('topic-card-1')),
            );
            expect(row.left, 4);
            expect(row.right, width - 4);
            final content = tester.getRect(find.byType(DItemContent));
            expect(content.left, 16);
            expect(content.right, width - 16);
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });

  testWidgets(
    'live closing and reopening transfers rules between adjacent rows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final site = instance('closed.example');
      final topics = [
        for (var id = 1; id <= 4; id++)
          Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
      ];
      final shell = ShellController(
        instanceStore: FakeInstanceStore([site]),
        api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      await shell.loadFeed('latest');
      final feed = shell.currentFeed!;
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: TopicListView(feed: feed, inbox: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      DItem row(int id) =>
          tester.widget<DItem>(find.byKey(ValueKey('topic-card-$id')));
      Future<void> close(int id, bool value) async {
        shell.store.put(
          site.url,
          shell.store.read<Topic>(site.url, id)!.copyWith(closed: value),
        );
        await tester.pumpAndSettle();
      }

      expect(find.byType(DSeparator), findsNWidgets(3));
      await close(2, true);
      expect(row(2).closed, isTrue);
      expect(row(2).closedRuleAbove, isTrue);
      expect(row(2).closedRuleBelow, isTrue);
      expect(find.byType(DSeparator), findsOneWidget);
      await close(3, true);
      expect(row(2).closedRuleBelow, isFalse);
      expect(row(3).closedRuleAbove, isTrue);
      expect(row(3).closedRuleBelow, isTrue);
      expect(find.byType(DSeparator), findsNothing);
      await close(1, true);
      await close(4, true);
      expect(row(1).closedRuleAbove, isFalse);
      expect(row(1).closedRuleBelow, isFalse);
      expect(row(4).closedRuleAbove, isTrue);
      expect(row(4).closedRuleBelow, isFalse);
      await tester.tap(find.byKey(const ValueKey('topic-card-3')));
      await tester.pumpAndSettle();
      expect(row(3).selected, isTrue);
      expect(row(4).closedRuleAbove, isFalse);
      await close(3, false);
      expect(row(3).closed, isFalse);
      expect(row(2).closedRuleBelow, isFalse);
      expect(row(4).closedRuleAbove, isFalse);
      expect(find.byKey(const ValueKey('topic-row-lock-3')), findsNothing);
      await close(1, false);
      await close(2, false);
      await close(4, false);
      expect(find.byType(DSeparator), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );
}
