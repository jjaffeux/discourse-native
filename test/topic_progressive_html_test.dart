import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_post_list.dart';

import 'support/topic_scroll_fixture.dart';

void main() {
  for (final inbox in [false, true]) {
    testWidgets(
      'reveals a long post after restoring an offset inside it (inbox=$inbox)',
      (tester) async {
        final controller = await topicScrollController();
        addTearDown(controller.dispose);
        controller.store.update<Post>(
          controller.currentInstance!.url,
          1,
          (post) => post.copyWith(
            cooked: List.filled(
              450,
              '<p>Anchored paragraph for saved reading position.</p>',
            ).join(),
          ),
        );
        controller.saveTopicScrollPost(7, 1, viewportOffset: -600);
        await tester.pumpWidget(
          TopicScrollFixture(controller: controller, inbox: inbox),
        );
        final target = find.byKey(const ValueKey(1));
        await _until(tester, () => target.evaluate().isNotEmpty);
        await tester.pumpAndSettle();
        expect(_paragraphs('Anchored paragraph'), findsNWidgets(450));
        expect(
          find.byKey(const ValueKey('topic-loading-skeleton')),
          findsNothing,
        );
        final top = topicReadingViewportRect(tester).top - 600;
        expect(tester.getTopLeft(target).dy, closeTo(top, 1));
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getTopLeft(target).dy, closeTo(top, 1));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (inbox, oversized) in [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    testWidgets(
      'jump survives an unfinished long post above it (inbox=$inbox, oversized=$oversized)',
      (tester) async {
        final controller = await topicScrollController();

        addTearDown(controller.dispose);

        // Close under the fake clock even when the body fails: a close first
        // reached from a tearDown never completes, because it waits on futures
        // created under the fake clock, which nothing drives once the body has
        // returned.
        try {
          final site = controller.currentInstance!.url;
          controller.store.update<Post>(
            site,
            20,
            (post) => Post(
              id: post.id,
              postNumber: post.postNumber,
              username: post.username,
              createdAt: post.createdAt,
              cooked:
                  List.generate(
                    450,
                    (i) =>
                        '<p>Variable $i: '
                        '${List.filled((i < 40) == oversized ? 15 : 1, 'long paragraph content ').join()}</p>',
                  ).join() +
                  (oversized
                      ? '<!--${List.filled(300000, 'x').join()}-->'
                      : ''),
            ),
          );
          await tester.pumpWidget(
            TopicScrollFixture(controller: controller, inbox: inbox),
          );
          await _until(
            tester,
            () => _paragraphs('Post 1:').evaluate().isNotEmpty,
          );
          await tester.pumpAndSettle();
          final list = topicPostList(tester);
          list.listController!.jumpToItem(
            index: 38,
            scrollController: list.controller!,
            alignment: 0,
          );
          await _until(
            tester,
            () => _paragraphs('Variable').evaluate().isNotEmpty,
          );
          expect(_paragraphs('Variable').evaluate().length, lessThan(450));
          final firstParagraph = tester.element(_paragraphs('Variable').first);
          final body = tester.widget<CookedHtml>(
            find.byWidgetPredicate(
              (widget) => widget is CookedHtml && widget.post?.id == 20,
            ),
          );
          expect(body.renderMode, isA<ProgressiveHtmlMode>());
          list.listController!.jumpToItem(
            index: 80,
            scrollController: list.controller!,
            alignment: 0,
          );
          await tester.pump();
          final target = find.byKey(const ValueKey(41));
          expect(target, findsOneWidget);
          final before = tester.getTopLeft(target).dy;
          if (!oversized) {
            final retainedBody = find.byWidgetPredicate(
              (widget) => widget is CookedHtml && widget.post?.id == 20,
              skipOffstage: false,
            );
            await _until(
              tester,
              () => !TickerMode.getValuesNotifier(
                tester.element(retainedBody),
              ).value.enabled,
            );
            final hidden = _paragraphs('Variable', skipOffstage: false);
            final pausedCount = hidden.evaluate().length;
            expect(pausedCount, inExclusiveRange(0, 450));
            for (var frame = 0; frame < 6; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              expect(hidden.evaluate().length, pausedCount);
              expect(tester.getTopLeft(target).dy, closeTo(before, 1));
            }
          }
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(target).dy, closeTo(before, 1));
          expect(tester.takeException(), isNull);
          list.listController!.jumpToItem(
            index: 38,
            scrollController: list.controller!,
            alignment: 0,
          );
          await _until(
            tester,
            () => _paragraphs('Variable').evaluate().isNotEmpty,
          );
          await tester.pumpAndSettle();
          expect(_paragraphs('Variable'), findsNWidgets(450));
          if (!oversized) {
            expect(
              tester.element(_paragraphs('Variable').first),
              same(firstParagraph),
            );
          }
          final cooked = find.byWidgetPredicate(
            (widget) => widget is CookedHtml && widget.post?.id == 20,
          );
          // An unfinished estimate must not become a permanent minimum height
          // when an oversized body is recycled before its last batch is
          // mounted.
          expect(
            tester.getSize(find.byKey(const ValueKey(20))).height -
                tester.getSize(cooked).height,
            lessThan(250),
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}

Finder _paragraphs(String prefix, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().startsWith(prefix),
      skipOffstage: skipOffstage,
    );

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}
