import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://one.example';
const _reader = DiscourseUser(id: 7, username: 'reader');
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
    bool signedIn = false,
    FakeAuthenticator? authenticator,
    double inset = 0,
    List<Topic> rows = _rows,
  }) async {
    final api = _Api(rows);
    final forum = instance('one.example');
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        if (signedIn) forum.copyWith(user: _reader) else forum,
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
                  : Padding(
                      padding: EdgeInsets.only(left: inset),
                      child: TopicListView(feed: controller.currentFeed!),
                    ),
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

  Future<TestGesture> approach(WidgetTester tester) async {
    final rect = tester.getRect(find.byKey(const ValueKey('topic-card-1')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(rect.left - 120, rect.center.dy));
    addTearDown(mouse.removePointer);
    for (final distance in [100.0, 80.0, 60.0]) {
      await mouse.moveTo(Offset(rect.left - distance, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    return mouse;
  }

  testWidgets('trajectory starts before entry and survives hover then click', (
    tester,
  ) async {
    final (controller, api) = await setup(tester, inset: 200);
    final mouse = await approach(tester);
    expect(api.requests, hasLength(1));
    expect(api.requests.single.postNumber, 5);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('topic-card-1'))),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(api.requests, hasLength(1));
    expect(api.requests.single.aborted, isFalse);
    await tester.tap(find.byKey(const ValueKey('topic-card-1')));
    await tester.pump();
    expect(api.requests, hasLength(1));
    expect(api.requests.single.aborted, isFalse);
    api.requests.single.complete();
    await tester.pumpAndSettle();
    expect(controller.store.read<TopicDetail>(_site, 1), isNotNull);
  });

  testWidgets('pointer bursts require confirmation on separate frames', (
    tester,
  ) async {
    final (_, api) = await setup(tester, inset: 200);
    final rect = tester.getRect(find.byKey(const ValueKey('topic-card-1')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(rect.left - 140, rect.center.dy));
    addTearDown(mouse.removePointer);
    for (final distance in [130.0, 120.0, 110.0, 100.0]) {
      await mouse.moveTo(Offset(rect.left - distance, rect.center.dy));
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(api.requests, isEmpty);
    await mouse.moveTo(Offset(rect.left - 80, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 16));
    expect(api.requests, isEmpty);
    await mouse.moveTo(Offset(rect.left - 60, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 16));
    expect(api.requests, hasLength(1));
  });

  testWidgets('an overlay covering the predicted row prevents prefetch', (
    tester,
  ) async {
    final (_, api) = await setup(tester, inset: 200);
    final overlay = Overlay.of(tester.element(find.byType(TopicListView)));
    final cover = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: AbsorbPointer(child: ColoredBox(color: Colors.black)),
      ),
    );
    overlay.insert(cover);
    addTearDown(() {
      cover.remove();
      cover.dispose();
    });
    await tester.pump();
    await approach(tester);
    expect(api.requests, isEmpty);
  });

  testWidgets(
    'completed prediction is reused on return after its interest expires',
    (tester) async {
      final (_, api) = await setup(tester, inset: 200);
      final mouse = await approach(tester);
      api.requests.single.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('topic-card-1'))),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.byKey(const ValueKey('topic-card-1')));
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(1));
    },
  );

  testWidgets('stopping short expires the predicted request', (tester) async {
    final (_, api) = await setup(tester, inset: 200);
    await approach(tester);
    expect(api.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 121));
    expect(api.requests.single.aborted, isTrue);
  });

  testWidgets('turning away cancels a predicted request', (tester) async {
    final (_, api) = await setup(tester, inset: 200);
    final mouse = await approach(tester);
    await mouse.moveTo(const Offset(40, 500));
    await tester.pump(const Duration(milliseconds: 16));
    expect(api.requests.single.aborted, isTrue);
  });

  testWidgets(
    'keyboard dwell fetches only the selected topic and Enter adopts it',
    (tester) async {
      final (controller, api) = await setup(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 39));
      expect(api.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.requests, hasLength(1));
      expect(api.requests.single.id, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(api.requests, hasLength(1));
      expect(api.requests.single.aborted, isFalse);
      api.requests.single.complete();
      await tester.pumpAndSettle();
      expect(controller.store.read<TopicDetail>(_site, 2), isNotNull);
    },
  );

  testWidgets('leaving keyboard focus cancels speculation', (tester) async {
    final (_, api) = await setup(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(api.requests, hasLength(1));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(api.requests.single.aborted, isTrue);
  });

  testWidgets('scroll cancels prediction and suppresses hover until it stops', (
    tester,
  ) async {
    final (_, api) = await setup(
      tester,
      inset: 200,
      rows: [
        ..._rows,
        for (var i = 3; i < 30; i++)
          Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
      ],
    );
    final mouse = await approach(tester);
    expect(api.requests, hasLength(1));
    final scroll = tester.startGesture(const Offset(600, 400));
    final drag = await scroll;
    await drag.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(api.requests.single.aborted, isTrue);
    await mouse.moveTo(const Offset(400, 180));
    await tester.pump(const Duration(milliseconds: 80));
    expect(api.requests, hasLength(1));
    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'removing the list releases a prediction and its pointer listener',
    (tester) async {
      final (_, api) = await setup(tester, inset: 200);
      final mouse = await approach(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(api.requests.single.aborted, isTrue);
      await mouse.moveTo(const Offset(300, 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('touch platforms ignore keyboard and trajectory speculation', (
    tester,
  ) async {
    final (_, api) = await setup(
      tester,
      platform: TargetPlatform.iOS,
      inset: 200,
    );
    await approach(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.requests, isEmpty);
  });

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
    // Only a signed-in forum reads its stored key, so the lookup can block.
    final auth = _DelayedAuthenticator()..keys[_site] = 'api-key';
    final (_, api) = await setup(tester, signedIn: true, authenticator: auth);
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
  _Api(List<Topic> rows) : super(feeds: {'/latest.json': rows});
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
