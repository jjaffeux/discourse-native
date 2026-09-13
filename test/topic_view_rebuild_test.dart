import 'dart:collection';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/topic_post_list.dart';
import 'support/topic_scroll_capture.dart';
import 'support/topic_scroll_fixture.dart';

void main() {
  test('post index projection scans a retained stream only once', () {
    final postIds = _CountingIntList([
      for (var postId = 1; postId <= 10000; postId++) postId,
      5000,
    ]);

    final projection = TopicPostIndexProjection(postIds);

    expect(postIds.reads, postIds.length);
    postIds.reads = 0;
    for (var postId = 1; postId <= 10000; postId++) {
      expect(projection[postId], postId - 1);
    }
    expect(projection[5000], 4999);
    expect(projection[10001], isNull);
    expect(postIds.reads, 0);
  });

  testWidgets('unrelated shell notifications do not rebuild cooked posts', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      topics: {
        7: topicPayload(
          id: 7,
          title: 'A topic',
          posts: const [
            Post(
              id: 1,
              postNumber: 1,
              username: 'sam',
              cooked: '<p>Already rendered</p>',
            ),
          ],
        ),
      },
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    controller.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
    );
    await controller.loadTopic(7, 'a-topic');

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: TopicView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CookedHtml), findsOneWidget);
    expect(find.byType(PostActions), findsOneWidget);

    var cookedRebuilds = 0;
    final rebuilt = <Element>{};
    final actions = tester.element(find.byType(PostActions));
    final actionChildren = <Element>[];
    actions.visitChildren(actionChildren.add);
    expect(actionChildren, hasLength(1));
    final actionsSelector = actionChildren.single;
    final previousRebuildHook = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousRebuildHook?.call(element, builtOnce);
      rebuilt.add(element);
      if (builtOnce && element.widget is CookedHtml) cookedRebuilds += 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previousRebuildHook);

    controller.selectInstance(0);
    await tester.pump();

    expect(cookedRebuilds, 0);
    expect(rebuilt, isNot(contains(actions)));
    expect(rebuilt, isNot(contains(actionsSelector)));
  });

  testWidgets(
    'floating day and progress changes leave the topic content stable',
    (tester) async {
      final firstDay = DateTime(2020, 1, 2);
      final secondDay = DateTime(2020, 1, 3);
      final posts = [
        for (var id = 1; id <= 12; id++)
          Post(
            id: id,
            postNumber: id,
            username: 'sam',
            cooked: List.filled(4, '<p>Post $id</p>').join(),
            createdAt: (id <= 6 ? firstDay : secondDay).add(
              Duration(minutes: id),
            ),
          ),
      ];
      final api = FakeDiscourseApi(
        topics: {7: topicPayload(id: 7, title: 'A topic', posts: posts)},
      );
      final controller = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      controller.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
      );
      await controller.loadTopic(7, 'a-topic');

      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: TopicView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listFinder = topicPostListFinder();
      final list = topicPostList(tester);
      final listElement = tester.element(listFinder);
      final topicViewElement = tester.element(find.byType(TopicView));
      final headerElement = tester.element(
        find.byKey(const ValueKey('topic-content-header')),
      );
      final cookedElements = tester
          .elementList(find.byType(CookedHtml))
          .toSet();
      final actionElements = tester
          .elementList(find.byType(PostActions))
          .toSet();
      final initialProgress = tester
          .widget<TopicProgressButton>(find.byType(TopicProgressButton))
          .position;
      expect(
        find.byKey(ValueKey(('topic-floating-day', firstDay))),
        findsNothing,
      );

      final rebuilt = <Element>{};
      final previousRebuildHook = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousRebuildHook?.call(element, builtOnce);
        rebuilt.add(element);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousRebuildHook);

      list.listController!.jumpToItem(
        index: 3 * 2,
        scrollController: list.controller!,
        alignment: 0,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey(('topic-floating-day', firstDay))),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TopicProgressButton>(find.byType(TopicProgressButton))
            .position,
        greaterThan(initialProgress),
      );
      expect(rebuilt, isNot(contains(topicViewElement)));
      expect(rebuilt, isNot(contains(headerElement)));
      expect(rebuilt, isNot(contains(listElement)));
      expect(rebuilt.intersection(cookedElements), isEmpty);
      expect(rebuilt.intersection(actionElements), isEmpty);
    },
  );

  for (final retain in [true, false]) {
    testWidgets(
      retain
          ? 'returning to a long post reuses its rendered HTML without rebuilding the topic'
          : 'oversized posts recycle without repeated geometry refreshes',
      (tester) async {
        final posts = [
          Post(
            id: 1,
            postNumber: 1,
            username: 'sam',
            cooked:
                List.filled(450, '<p>A tall first post</p>').join() +
                (retain ? '' : '<!--${List.filled(256 * 1024, 'x').join()}-->'),
          ),
          for (var id = 2; id <= 25; id++)
            Post(
              id: id,
              postNumber: id,
              username: 'sam',
              cooked: List.filled(5, '<p>Post $id</p>').join(),
            ),
        ];
        final api = FakeDiscourseApi(
          topics: {7: topicPayload(id: 7, title: 'A topic', posts: posts)},
        );
        final controller = ShellController(
          instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(controller.dispose);

        await controller.load();
        controller.pushContent(
          ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
        );
        await controller.loadTopic(7, 'a-topic');
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(body: TopicView()),
            ),
          ),
        );
        await tester.pump();
        await _pumpUntilRendered(tester, 'A tall first post');
        final firstHtml = tester.element(find.byType(CookedHtml).first);

        final topicViewElement = tester.element(find.byType(TopicView));
        var topicViewRebuilds = 0;
        final previousRebuildHook = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previousRebuildHook?.call(element, builtOnce);
          if (identical(element, topicViewElement)) topicViewRebuilds++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previousRebuildHook);

        final list = topicPostList(tester);
        list.listController!.jumpToItem(
          index: 40,
          scrollController: list.controller!,
          alignment: 0,
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const ValueKey(1)), findsNothing);
        expect(firstHtml.mounted, retain);
        expect(topicViewRebuilds, retain ? 0 : greaterThan(0));
        final rebuildsAfterFirstRecycle = topicViewRebuilds;

        list.listController!.jumpToItem(
          index: 0,
          scrollController: list.controller!,
          alignment: 0,
        );
        await tester.pump();
        await _pumpUntilRendered(tester, 'A tall first post');
        expect(find.byKey(const ValueKey(1)), findsOneWidget);
        expect(
          tester.element(find.byType(CookedHtml).first),
          retain ? same(firstHtml) : isNot(same(firstHtml)),
        );

        list.listController!.jumpToItem(
          index: 40,
          scrollController: list.controller!,
          alignment: 0,
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const ValueKey(1)), findsNothing);
        expect(topicViewRebuilds, rebuildsAfterFirstRecycle);
      },
    );
  }

  testWidgets('retained inbox posts accept edits and evict old HTML trees', (
    tester,
  ) async {
    final controller = await topicScrollController();
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: topicScrollCaptureWithoutVm(),
    );
    addTearDown(controller.dispose);
    addTearDown(diagnostics.close);
    final site = controller.currentInstance!.url;
    final longHtml = controller.store.read<Post>(site, 1)!.cooked;
    // Neighboring async placeholders can temporarily share the first viewport.
    for (final id in [2, 3, 4, 35, 50]) {
      controller.store.update<Post>(
        site,
        id,
        (post) => Post(
          id: post.id,
          postNumber: post.postNumber,
          username: post.username,
          createdAt: post.createdAt,
          cooked: longHtml.replaceAll('Post 1:', 'Post $id:'),
        ),
      );
    }
    await tester.pumpWidget(
      TopicScrollFixture(controller: controller, diagnostics: diagnostics),
    );
    await _pumpUntilRendered(tester, 'Post 1:');
    Finder htmlFor(int id, {bool offscreen = false}) => find.byWidgetPredicate(
      (widget) => widget is CookedHtml && widget.post?.id == id,
      skipOffstage: !offscreen,
    );
    final firstHtml = tester.element(htmlFor(1));
    final list = topicPostList(tester);
    Future<void> jumpTo(int id) async {
      list.listController!.jumpToItem(
        index: (id - 1) * 2,
        scrollController: list.controller!,
        alignment: 0,
      );
      await tester.pump();
      await _pumpUntilRendered(tester, 'Post $id:');
      await tester.pumpAndSettle();
    }

    await jumpTo(20);
    expect(firstHtml.mounted, isTrue);
    controller.store.update<Post>(
      site,
      1,
      (post) => Post(
        id: post.id,
        postNumber: post.postNumber,
        username: post.username,
        createdAt: post.createdAt,
        cooked: longHtml.replaceAll('Post 1:', 'Edited 1:'),
      ),
    );
    await _pumpUntilRendered(tester, 'Post 20:');
    // An offscreen async edit still needs layout for text selection.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<CookedHtml>(htmlFor(1, offscreen: true)).html,
      contains('Edited 1:'),
    );

    await jumpTo(35);
    await jumpTo(50);
    expect(firstHtml.mounted, isFalse);
    final retainedLongPosts = tester
        .widgetList<CookedHtml>(find.byType(CookedHtml, skipOffstage: false))
        .where(
          (widget) =>
              widget.post != null &&
              CookedHtml.buildsAsynchronously(widget.html),
        );
    expect(retainedLongPosts.length, lessThanOrEqualTo(3));

    final retainedElements = tester
        .elementList(find.byType(CookedHtml, skipOffstage: false))
        .toList();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(retainedElements.every((element) => !element.mounted), isTrue);
    expect(tester.takeException(), isNull);
    await diagnostics.close();
  });
}

Future<void> _pumpUntilRendered(WidgetTester tester, String text) async {
  final rendered = find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
    description: 'rendered cooked text containing "$text"',
  );
  const timeout = Duration(seconds: 5);
  final elapsed = Stopwatch()..start();
  while (rendered.evaluate().isEmpty && elapsed.elapsed < timeout) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  if (rendered.evaluate().isNotEmpty) return;
  fail('Cooked HTML did not finish rendering "$text" within $timeout.');
}

final class _CountingIntList extends ListBase<int> {
  _CountingIntList(this._values);

  final List<int> _values;
  int reads = 0;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  int operator [](int index) {
    reads += 1;
    return _values[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}
