import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://one.example';
const _rows = [
  Topic(
    id: 1,
    title: 'First topic',
    slug: 'first',
    highestPostNumber: 8,
    lastReadPostNumber: 4,
  ),
  Topic(id: 2, title: 'Second topic', slug: 'second'),
];

void main() {
  Future<(ShellController, _Api)> setup(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.macOS,
    bool panels = false,
    FakeAuthenticator? authenticator,
  }) async {
    final api = _Api();
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('one.example'),
        instance('two.example'),
      ]),
      api: api,
      authenticator: authenticator ?? FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.desktopTopicTabs = panels;
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller.topicFeeds,
              builder: (context, _) => controller.currentFeed == null
                  ? const SizedBox.shrink()
                  : TopicListView(feed: controller.currentFeed!),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, api);
  }

  Future<TestGesture> hover(WidgetTester tester, int id) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(790, 590));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(ValueKey('topic-card-$id'))),
    );
    return mouse;
  }

  for (final completed in [false, true]) {
    testWidgets(
      'click reuses ${completed ? 'completed' : 'running'} hover with unread destination',
      (tester) async {
        final (controller, api) = await setup(tester);
        final mouse = await hover(tester, 1);
        await tester.pump(const Duration(milliseconds: 39));
        expect(api.requests, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(api.requests, hasLength(1));
        expect(api.requests.single.postNumber, 5);
        expect(controller.currentContent?.isTopic, isFalse);
        expect(controller.store.read<TopicDetail>(_site, 1), isNull);
        expect(api.topicReadsRecorded, isEmpty);
        if (completed) {
          api.requests.single.complete();
          await tester.pump();
          expect(controller.store.read<TopicDetail>(_site, 1), isNull);
        }
        await tester.tap(find.byKey(const ValueKey('topic-card-1')));
        await mouse.moveTo(const Offset(790, 590));
        await tester.pump();
        expect(api.requests, hasLength(1));
        expect(api.requests.single.aborted, isFalse);
        if (!completed) api.requests.single.complete();
        await tester.pumpAndSettle();
        expect(controller.currentContent?.topicId, 1);
        expect(controller.store.read<TopicDetail>(_site, 1), isNotNull);
        expect(api.requests, hasLength(1));
      },
    );
  }

  testWidgets('desktop reader adopts the hover request from the list tab', (
    tester,
  ) async {
    final (controller, api) = await setup(tester, panels: true);
    final listTab = controller.activeTabId;
    final mouse = await hover(tester, 1);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const ValueKey('topic-card-1')));
    await mouse.moveTo(const Offset(790, 590));
    await tester.pump();
    expect(api.requests, hasLength(1));
    expect(api.requests.single.aborted, isFalse);
    api.requests.single.complete();
    await tester.pumpAndSettle();
    // An ordinary click reads the topic in the list's own tab.
    expect(controller.activeTabId, listTab);
    expect(controller.tabsForCurrentForum, hasLength(1));
    expect(controller.currentContent?.topicId, 1);
    expect(controller.store.read<TopicDetail>(_site, 1), isNotNull);
    expect(api.requests, hasLength(1));
  });

  testWidgets('forced navigation discards speculative work', (tester) async {
    final (controller, api) = await setup(tester);
    await hover(tester, 1);
    await tester.pump(const Duration(milliseconds: 40));
    final loading = controller.loadTopic(
      1,
      'first',
      force: true,
      postNumber: 5,
    );
    await tester.pump();
    expect(api.requests, hasLength(2));
    expect(api.requests.first.aborted, isTrue);
    expect(api.requests.last.abortTrigger, isNull);
    api.requests.last.complete();
    await loading;
  });

  testWidgets(
    'a full desktop workspace still prefetches current-tab topic opens',
    (tester) async {
      final (controller, api) = await setup(tester, panels: true);
      while (controller.canCreateTab) {
        controller.createTab();
      }
      await tester.pumpAndSettle();
      await hover(tester, 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.requests, hasLength(1));
      api.requests.single.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('cancelled credential lookup does not block the next hover', (
    tester,
  ) async {
    final auth = _DelayedAuthenticator();
    final (_, api) = await setup(tester, authenticator: auth);
    final blocked = Completer<String?>();
    auth.pending = blocked;
    final mouse = await hover(tester, 1);
    await tester.pump(const Duration(milliseconds: 40));
    expect(api.requests, isEmpty);
    auth.pending = null;
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('topic-card-2'))),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(api.requests.single.id, 2);
    blocked.complete(null);
    api.requests.single.complete();
    await tester.pump();
    expect(api.requests, hasLength(1));
  });

  testWidgets('already loaded topics do not send speculative requests', (
    tester,
  ) async {
    final (controller, api) = await setup(tester);
    final payload = topicPayload(
      id: 1,
      posts: const [
        Post(id: 10, postNumber: 5, username: 'user', cooked: '<p>Hello</p>'),
      ],
    );
    controller.store.put(_site, payload.detail);
    controller.store.putAll(_site, payload.posts);
    await hover(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.requests, isEmpty);
  });

  testWidgets('account retirement discards a completed hover response', (
    tester,
  ) async {
    final (controller, api) = await setup(tester);
    await hover(tester, 1);
    await tester.pump(const Duration(milliseconds: 40));
    api.requests.single.complete();
    await tester.pump();
    controller.lifecycle.invalidate(_site);
    controller.clearAccountSessionState(_site);
    final loading = controller.loadTopic(1, 'first', postNumber: 5);
    await tester.pump();
    expect(api.requests, hasLength(2));
    api.requests.last.complete();
    await loading;
    expect(controller.store.read<TopicDetail>(_site, 1), isNotNull);
  });

  testWidgets('click before 40 ms sends only the normal request', (
    tester,
  ) async {
    final (controller, api) = await setup(tester);
    await hover(tester, 1);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const ValueKey('topic-card-1')));
    await tester.pump();
    expect(api.requests, hasLength(1));
    expect(api.requests.single.abortTrigger, isNull);
    api.requests.single.complete();
    await tester.pumpAndSettle();
    expect(controller.store.read<TopicDetail>(_site, 1), isNotNull);
    expect(api.requests, hasLength(1));
  });

  testWidgets(
    'moving rows aborts the previous request and loads the next after 40 ms',
    (tester) async {
      final (_, api) = await setup(tester);
      final mouse = await hover(tester, 1);
      await tester.pump(const Duration(milliseconds: 40));
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('topic-card-2'))),
      );
      await tester.pump(const Duration(milliseconds: 39));
      expect(api.requests.single.aborted, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.requests.map((r) => r.id), [1, 2]);
      api.requests.last.complete();
      await tester.pump();
    },
  );

  for (final action in [
    'remove list',
    'switch site',
    'navigate away',
    'background',
  ]) {
    testWidgets('$action cancels hover work', (tester) async {
      final (controller, api) = await setup(tester);
      await hover(tester, 1);
      await tester.pump(const Duration(milliseconds: 40));
      switch (action) {
        case 'remove list':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'switch site':
          controller.selectInstance(1);
        case 'navigate away':
          controller.pushContent(ContentRoute.preferences());
        case 'background':
          controller.setForeground(false);
      }
      await tester.pump();
      expect(api.requests.single.aborted, isTrue);
      expect(controller.store.read<TopicDetail>(_site, 1), isNull);
    });
  }

  testWidgets('a failed hover is silent and clicking retries', (tester) async {
    final (controller, api) = await setup(tester);
    await hover(tester, 1);
    await tester.pump(const Duration(milliseconds: 40));
    api.requests.single.response.completeError(StateError('offline'));
    await tester.pump();
    expect(controller.currentContent?.isTopic, isFalse);
    await tester.tap(find.byKey(const ValueKey('topic-card-1')));
    await tester.pump();
    expect(api.requests, hasLength(2));
    api.requests.last.complete();
    await tester.pumpAndSettle();
    expect(controller.store.read<TopicDetail>(_site, 1), isNotNull);
  });

  testWidgets('touch platforms do not speculate from a pointer', (
    tester,
  ) async {
    final (_, api) = await setup(tester, platform: TargetPlatform.iOS);
    await hover(tester, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.requests, isEmpty);
  });
}

class _Api extends FakeDiscourseApi {
  _Api() : super(feeds: {'/latest.json': _rows});
  final requests = <_Request>[];

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) {
    final request = _Request(id, postNumber, abortTrigger);
    requests.add(request);
    return request.response.future;
  }
}

class _Request {
  _Request(this.id, this.postNumber, this.abortTrigger) {
    unawaited(
      abortTrigger?.then((_) {
        aborted = true;
        if (!response.isCompleted) {
          response.completeError(StateError('aborted'));
        }
      }),
    );
  }
  final int id;
  final int? postNumber;
  final Future<void>? abortTrigger;
  final response = Completer<TopicPayload>();
  bool aborted = false;
  void complete() => response.complete(
    topicPayload(
      id: id,
      title: 'Topic $id',
      posts: [
        Post(
          id: id * 10,
          postNumber: postNumber ?? 1,
          username: 'user',
          cooked: '<p>Hello</p>',
        ),
      ],
    ),
  );
}

class _DelayedAuthenticator extends FakeAuthenticator {
  Completer<String?>? pending;

  @override
  Future<String?> apiKeyFor(String siteUrl) =>
      pending?.future ?? super.apiKeyFor(siteUrl);
}
