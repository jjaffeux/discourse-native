import 'dart:async';

import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/mixed_topic_scroll_fixture.dart';
import 'support/topic_post_list.dart';
import 'support/topic_scroll_fixture.dart';

void main() {
  for (final firstLoaded in [21, 61]) {
    for (final inbox in [true, false]) {
      for (final dragging in [false, true]) {
        testWidgets(
          'prepending before $firstLoaded only mounts laid-out replies (inbox: $inbox, dragging: $dragging)',
          (tester) async {
            final gate = Completer<void>();
            final api = FakeDiscourseApi(
              postGate: gate,
              topics: {},
              postsById: {},
            );
            final controller = await mixedTopicScrollController(
              api: api,
              firstLoaded: firstLoaded,
              initialPostNumber: firstLoaded + 10,
            );
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              TopicScrollFixture(controller: controller, inbox: inbox),
            );
            await tester.pumpAndSettle();
            final list = topicPostList(tester);
            final originals = <int, Element>{};
            // Warm several offscreen replies as well as the visible anchor.
            for (final offset in [3, 6, 10]) {
              list.listController!.jumpToItem(
                index: (offset + 1) * 2,
                scrollController: list.controller!,
                alignment: 0,
              );
              await tester.pumpAndSettle();
              for (final element in tester.elementList(
                find.byType(CookedHtml),
              )) {
                if ((element.widget as CookedHtml).post case final post?) {
                  originals[post.id] = element;
                }
              }
            }
            expect(
              originals.values.every((element) => element.mounted),
              isTrue,
            );
            final anchor = find.byKey(ValueKey(firstLoaded + 10));
            final gesture = dragging
                ? await tester.startGesture(
                    tester.getCenter(topicPostListFinder()),
                  )
                : null;
            if (gesture != null) {
              await gesture.moveBy(const Offset(0, 20));
              await gesture.moveBy(const Offset(0, 60));
              await tester.pump();
            }
            final top = tester.getTopLeft(anchor).dy;
            final premature = <int>{};
            final previous = debugOnRebuildDirtyWidget;
            debugOnRebuildDirtyWidget = (element, builtOnce) {
              previous?.call(element, builtOnce);
              if (element.widget case CookedHtml(post: final post?)) {
                if (post.id < firstLoaded) premature.add(post.id);
              }
            };
            addTearDown(() => debugOnRebuildDirtyWidget = previous);
            final loading = controller.loadEarlierPosts();
            final loadingMore = dragging ? controller.loadMorePosts() : null;
            await tester.pump();
            gate.complete();
            await loading;
            if (loadingMore != null) await loadingMore;
            await tester.pumpAndSettle();
            expect(controller.currentPostIds.first, firstLoaded - 20);
            expect(tester.getTopLeft(anchor).dy, closeTo(top, 1));
            expect(
              premature,
              isEmpty,
              reason:
                  'Offscreen replacements must not mount HTML or evict retained replies',
            );
            for (final entry in originals.entries) {
              expect(entry.value.mounted, isTrue, reason: 'Post ${entry.key}');
            }
            if (gesture != null) {
              await gesture.moveBy(const Offset(0, -60));
              await tester.pump();
              expect(tester.getTopLeft(anchor).dy, closeTo(top - 60, 1));
              await gesture.up();
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final inbox in [true, false]) {
    testWidgets('ordinary replies survive scroll reversals (inbox: $inbox)', (
      tester,
    ) async {
      final controller = await mixedTopicScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        TopicScrollFixture(controller: controller, inbox: inbox, dark: !inbox),
      );
      await tester.pumpAndSettle();
      final list = topicPostList(tester);
      Future<void> jump(int postNumber) async {
        list.listController!.jumpToItem(
          index: (postNumber - 1) * 2,
          scrollController: list.controller!,
          alignment: 0,
        );
        await tester.pumpAndSettle();
      }

      Finder htmlFor(int id) => find.byWidgetPredicate(
        (widget) => widget is CookedHtml && widget.post?.id == id,
      );
      await jump(8);
      final original = tester.element(htmlFor(8));
      expect((original.widget as CookedHtml).html.length, lessThan(10000));
      await jump(16);
      expect(htmlFor(8), findsNothing);
      expect(original.mounted, isTrue);

      // The retained tree must still subscribe to edits while offscreen.
      controller.store.update<Post>(
        controller.currentInstance!.url,
        8,
        (post) => Post(
          id: post.id,
          postNumber: post.postNumber,
          username: post.username,
          cooked: '<p>Edited ordinary reply</p>',
        ),
      );
      await tester.pumpAndSettle();
      await jump(8);
      expect(tester.element(htmlFor(8)), same(original));
      expect(tester.widget<CookedHtml>(htmlFor(8)).html, contains('Edited'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(original.mounted, isFalse);
    });
  }

  testWidgets('paging leaves already rendered reply subtrees untouched', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeDiscourseApi(postGate: gate, topics: {}, postsById: {});
    final controller = await mixedTopicScrollController(api: api);
    addTearDown(controller.dispose);
    await tester.pumpWidget(TopicScrollFixture(controller: controller));
    await tester.pumpAndSettle();
    final original = <Element>{};
    void collect(Element element) {
      original.add(element);
      element.visitChildren(collect);
    }

    for (final element in tester.elementList(find.byType(PostActions))) {
      collect(element);
    }
    expect(original, isNotEmpty);
    final rebuilt = <Element>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (original.contains(element)) rebuilt.add(element);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    final loading = controller.loadMorePosts();
    await tester.pump();
    await tester.pump();
    expect(controller.loadingMorePosts, isTrue);
    expect(
      rebuilt,
      isEmpty,
      reason: 'Starting a page must not rebuild replies',
    );
    gate.complete();
    await loading;
    await tester.pumpAndSettle();
    expect(controller.currentPostIds, hasLength(40));
    expect(
      rebuilt,
      isEmpty,
      reason: 'Appending a page must not rebuild replies',
    );

    // The stable subtree still responds to changes in its actual inputs.
    final topic = controller.currentTopic!;
    controller.store.put(
      controller.currentInstance!.url,
      topicPayload(
        id: topic.id,
        title: topic.title,
        stream: topic.stream,
        postsCount: topic.postsCount,
        archived: true,
      ).detail,
    );
    controller.selectInstance(0);
    await tester.pumpAndSettle();
    final body = find.byWidgetPredicate(
      (widget) => widget is CookedHtml && widget.post?.id == 1,
    );
    expect(tester.widget<CookedHtml>(body).containingTopic?.archived, isTrue);
    await tester.pumpWidget(
      TopicScrollFixture(controller: controller, dark: true),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<CookedHtml>(body).textStyle?.color,
      AppTheme.dark.textTheme.bodyLarge?.color,
    );
  });
}
