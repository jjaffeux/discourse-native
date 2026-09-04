import 'dart:async';
import 'dart:ui' as ui;

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/shell/list_boundary_shortcuts.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

void main() {
  final sites = [instance('one.example'), instance('two.example')];

  testWidgets('first load uses a faithful topic-list skeleton', (tester) async {
    final api = _ControlledPagingApi();
    final controller = await _controlledShell(api, sites.first);
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_LiveTestList(controller: controller));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('topic-list-loading-skeleton')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('topic-list-loading-skeleton-content')),
            )
            .height,
        greaterThanOrEqualTo(
          tester
              .getSize(
                find.byKey(const ValueKey('topic-list-loading-skeleton')),
              )
              .height,
        ),
      );
      final skeletonRows = find.descendant(
        of: find.byKey(const ValueKey('topic-list-loading-skeleton')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints.minHeight == TopicListRow.minimumHeight,
        ),
      );
      expect(skeletonRows, findsWidgets);
      expect(
        tester.getSize(skeletonRows.first).height,
        greaterThanOrEqualTo(TopicListRow.minimumHeight),
      );
      expect(find.bySemanticsLabel('Loading topics'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);

      api.requests.single.response.complete(_page(1));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('topic-list-loading-skeleton')),
        findsNothing,
      );
      expect(find.text('Topic 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-list-ledger-header')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('topic-ledger-state-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-ledger-topic-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('topic-ledger-participants-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('topic-ledger-activity-1')),
        findsOneWidget,
      );
      final compactTitle = tester.widget<TopicTitle>(
        find.byType(TopicTitle).first,
      );
      expect(compactTitle.maxLines, 1);
      expect(compactTitle.overflow, TextOverflow.ellipsis);
      final topicRow = find.descendant(
        of: find.byType(TopicListView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints.minHeight == TopicListRow.minimumHeight,
        ),
      );
      expect(tester.getSize(topicRow.first).height, TopicListRow.minimumHeight);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('narrow rows fold participants and activity into metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const ui.Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final topic = Topic(
      id: 7,
      title: 'A compact topic',
      slug: 'a-compact-topic',
      replyCount: 2,
      views: 14,
      bumpedAt: DateTime(2026, 9, 4),
      posterAvatars: const [''],
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([sites.first]),
      api: FakeDiscourseApi(
        feeds: {
          '/latest.json': [topic],
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store.put(sites.first.url, topic);

    await tester.pumpWidget(
      _TestList(
        controller: controller,
        feed: const TopicFeed(topicIds: [7], loaded: true),
      ),
    );
    await tester.pumpAndSettle();

    final topicColumn = find.byKey(const ValueKey('topic-ledger-topic-7'));
    expect(topicColumn, findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-ledger-participants-7')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('topic-ledger-activity-7')), findsNothing);
    expect(
      find.descendant(of: topicColumn, matching: find.dIcon(DIcons.user)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topicColumn, matching: find.dIcon(DIcons.reply)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topicColumn, matching: find.dIcon(DIcons.farEye)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed first load retries once from the empty state', (
    tester,
  ) async {
    final api = _ControlledPagingApi();
    final controller = await _controlledShell(api, sites.first);
    addTearDown(controller.dispose);

    api.requests.single.response.completeError(
      SiteLookupException(SiteLookupFailure.unreachable, sites.first.url),
    );
    await tester.pump();
    await tester.pumpWidget(_LiveTestList(controller: controller));
    await tester.pump();

    expect(find.text("Couldn't reach one.example."), findsOneWidget);
    final retry = find.byKey(const ValueKey('topic-feed-initial-retry'));
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.tap(retry);
    await tester.pump();
    expect(api.requests, hasLength(2));

    await tester.pump();
    expect(
      find.byKey(const ValueKey('topic-list-loading-skeleton')),
      findsOneWidget,
    );
    expect(retry, findsNothing);

    api.requests.last.response.complete(_page(1));
    await tester.pumpAndSettle();

    expect(find.text('Topic 1'), findsOneWidget);
    expect(api.requests, hasLength(2));
  });

  testWidgets('stale rows expose refresh and page retry states', (
    tester,
  ) async {
    final api = _ControlledPagingApi();
    final controller = await _controlledShell(api, sites.first);
    addTearDown(controller.dispose);

    api.requests.single.response.complete(_page(1));
    await tester.pump();
    await tester.pumpWidget(_LiveTestList(controller: controller));
    await tester.pump();

    final beforeRefresh = api.requests.length;
    final refresh = controller.loadFeed('latest', force: true);
    await tester.pump();
    expect(api.requests, hasLength(beforeRefresh + 1));

    expect(find.text('Topic 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-feed-refresh-progress')),
      findsOneWidget,
    );

    api.requests.last.response.completeError(Exception('offline'));
    await refresh;
    await tester.pump();

    expect(find.text('Topic 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-feed-refresh-error')),
      findsOneWidget,
    );

    final refreshRetry = find.descendant(
      of: find.byKey(const ValueKey('topic-feed-refresh-error')),
      matching: find.byKey(const ValueKey('topic-feed-error-retry')),
    );
    final beforeRefreshRetry = api.requests.length;
    await tester.tap(refreshRetry);
    await tester.tap(refreshRetry);
    await tester.pump();
    expect(api.requests, hasLength(beforeRefreshRetry + 1));
    api.requests.last.response.complete(
      _page(2, moreTopicsUrl: '/latest?page=1'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(api.requests, hasLength(beforeRefreshRetry + 2));

    api.requests.last.response.completeError(Exception('offline'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Topic 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-feed-load-more-error')),
      findsOneWidget,
    );

    final pageRetry = find.descendant(
      of: find.byKey(const ValueKey('topic-feed-load-more-error')),
      matching: find.byKey(const ValueKey('topic-feed-error-retry')),
    );
    final beforePageRetry = api.requests.length;
    await tester.tap(pageRetry);
    await tester.tap(pageRetry);
    await tester.pump();
    expect(api.requests, hasLength(beforePageRetry + 1));

    api.requests.last.response.complete(_page(3));
    await tester.pump();
    await tester.pump();

    expect(find.text('Topic 2'), findsOneWidget);
    expect(find.text('Topic 3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-feed-load-more-error')),
      findsNothing,
    );
  });

  testWidgets('the same destination has an independent position per site', (
    tester,
  ) async {
    final topics = _topics(1, 40);
    final controller = ShellController(
      instanceStore: FakeInstanceStore(sites),
      api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..putAll(sites[0].url, topics)
      ..putAll(sites[1].url, topics);
    final feed = TopicFeed(
      topicIds: [for (final topic in topics) topic.id],
      loaded: true,
    );

    await tester.pumpWidget(_TestList(controller: controller, feed: feed));
    await tester.pumpAndSettle();

    final first = tester.widget<SuperListView>(find.byType(SuperListView));
    await tester.drag(find.byType(SuperListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(first.controller!.offset, greaterThan(0));

    controller.selectInstance(1);
    await tester.pump();

    final second = tester.widget<SuperListView>(find.byType(SuperListView));
    expect(second.controller, isNot(same(first.controller)));
    expect(second.controller!.offset, 0);
  });

  testWidgets('desktop rows use a scrollable full-width viewport', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.binding.setSurfaceSize(const Size(1200, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final topics = _topics(1, 40);
      final controller = ShellController(
        instanceStore: FakeInstanceStore([sites.first]),
        api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.store.putAll(sites.first.url, topics);
      final feed = TopicFeed(
        topicIds: [for (final topic in topics) topic.id],
        loaded: true,
      );

      await tester.pumpWidget(_TestList(controller: controller, feed: feed));
      await tester.pumpAndSettle();

      final viewport = find.byType(SuperListView);
      final list = tester.widget<SuperListView>(viewport);
      final firstRow = find.byKey(const ValueKey(1));
      expect(tester.getSize(viewport).width, 1200);
      expect(tester.getSize(firstRow).width, 825);
      expect(tester.getTopLeft(firstRow).dx, 187.5);

      const gutterPoint = Offset(1100, 300);
      expect(tester.getRect(firstRow).contains(gutterPoint), isFalse);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: gutterPoint,
          scrollDelta: Offset(0, 400),
        ),
      );
      await tester.pumpAndSettle();

      expect(list.controller!.offset, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('a scrolled row cannot paint its hover into the header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final topics = _topics(1, 20);
    final controller = ShellController(
      instanceStore: FakeInstanceStore([sites.first]),
      api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store.putAll(sites.first.url, topics);
    final feed = TopicFeed(
      topicIds: [for (final topic in topics) topic.id],
      loaded: true,
    );
    const background = Color(0xFF123456);
    const captureKey = ValueKey('topic-list-hover-capture');

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: captureKey,
            child: Material(
              color: background,
              child: Column(
                children: [
                  const SizedBox(height: 80),
                  Expanded(child: TopicListView(feed: feed)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstRow = find.byKey(const ValueKey(1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(firstRow));
    await tester.pumpAndSettle();

    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    list.controller!.jumpTo(80);
    await tester.pump();
    await tester.pump();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final headerPixel = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        return await _pixelAt(image, 200, 40);
      } finally {
        image.dispose();
      }
    });
    expect(headerPixel, background);
  });

  testWidgets('a restored row is bounded by the currently loaded page', (
    tester,
  ) async {
    final topics = _topics(1, 1);
    final controller = ShellController(
      instanceStore: FakeInstanceStore([sites.first]),
      api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store.putAll(sites.first.url, topics);
    controller.saveFeedScrollRow('latest', 40);
    final feed = TopicFeed(topicIds: [topics.single.id], loaded: true);

    await tester.pumpWidget(_TestList(controller: controller, feed: feed));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Topic 1'), findsOneWidget);
  });

  testWidgets('keyboard navigation scrolls and jumps through the topic list', (
    tester,
  ) async {
    final topics = _topics(1, 40);
    final controller = ShellController(
      instanceStore: FakeInstanceStore([sites.first]),
      api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store.putAll(sites.first.url, topics);
    final feed = TopicFeed(
      topicIds: [for (final topic in topics) topic.id],
      loaded: true,
    );

    await tester.pumpWidget(_TestList(controller: controller, feed: feed));
    await tester.pumpAndSettle();

    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    final position = list.controller!.position;
    expect(position.maxScrollExtent, greaterThan(0));

    position.jumpTo(position.maxScrollExtent / 2);
    final middle = position.pixels;
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown), isTrue);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(middle));

    final afterDown = position.pixels;
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp), isTrue);
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(afterDown));

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.home), isTrue);
    await tester.pump();
    expect(position.pixels, position.minScrollExtent);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.end), isTrue);
    await tester.pump();
    await tester.pump();
    expect(position.pixels, position.maxScrollExtent);

    expect(await _sendMetaShortcut(tester, LogicalKeyboardKey.arrowUp), isTrue);
    await tester.pump();
    expect(position.pixels, position.minScrollExtent);

    expect(
      await _sendMetaShortcut(tester, LogicalKeyboardKey.arrowDown),
      isTrue,
    );
    await tester.pump();
    await tester.pump();
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('boundary shortcuts leave an editable field in control', (
    tester,
  ) async {
    final topics = _topics(1, 40);
    final controller = ShellController(
      instanceStore: FakeInstanceStore([sites.first]),
      api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    final fieldFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(fieldFocus.dispose);
    await controller.load();
    controller.store.putAll(sites.first.url, topics);
    final feed = TopicFeed(
      topicIds: [for (final topic in topics) topic.id],
      loaded: true,
    );

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: fieldFocus),
                Expanded(child: TopicListView(feed: feed)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    final position = list.controller!.position;
    position.jumpTo(position.maxScrollExtent / 2);
    fieldFocus.requestFocus();
    await tester.pump();

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(SuperListView)),
        scrollDelta: const Offset(0, 20),
      ),
    );
    await tester.pump();
    final afterPointerScroll = position.pixels;

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await _sendMetaShortcut(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(fieldFocus.hasPrimaryFocus, isTrue);
    expect(position.pixels, afterPointerScroll);
    expect(position.extentBefore, greaterThan(0));
    expect(position.extentAfter, greaterThan(0));
  });

  testWidgets('boundary shortcut fallback stays behind a modal route', (
    tester,
  ) async {
    var starts = 0;
    var ends = 0;
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListBoundaryShortcuts(
            initiallyActive: true,
            scrollController: scrollController,
            onStart: () => starts++,
            onEnd: () => ends++,
            child: ListView(
              controller: scrollController,
              children: const [SizedBox(height: 2000)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byType(ListBoundaryShortcuts));
    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (dialogContext) => AlertDialog(
          content: const Text('Boundary shortcut modal'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await _sendMetaShortcut(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(starts, 0);
    expect(ends, 0);
    expect(scrollController.offset, 0);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('a queued page request cannot cross a site switch', (
    tester,
  ) async {
    final api = _PagingApi();
    final controller = ShellController(
      instanceStore: FakeInstanceStore(sites),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pump();
    controller.selectInstance(1);
    await tester.pump();
    controller.selectInstance(0);
    await tester.pump();
    expect(controller.currentFeed?.hasMore, isTrue);
    expect(api.pageSites, isEmpty);

    var showList = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return showList
                    ? TopicListView(feed: controller.currentFeed!)
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.selectInstance(1);
      rebuild(() => showList = false);
    });
    rebuild(() => showList = true);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.pageSites, isNot(contains(sites[1].url)));
  });
}

final class _TestList extends StatelessWidget {
  const _TestList({required this.controller, required this.feed});

  final ShellController controller;
  final TopicFeed feed;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: TopicListView(feed: feed)),
    ),
  );
}

final class _LiveTestList extends StatelessWidget {
  const _LiveTestList({required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller.topicFeeds,
          builder: (context, _) => controller.currentFeed == null
              ? const SizedBox.shrink()
              : TopicListView(feed: controller.currentFeed!),
        ),
      ),
    ),
  );
}

final class _PendingTopicPage {
  _PendingTopicPage(this.path);

  final String path;
  final Completer<TopicList> response = Completer<TopicList>();
}

final class _ControlledPagingApi extends FakeDiscourseApi {
  final List<_PendingTopicPage> requests = [];
  Completer<void> _requestsChanged = Completer<void>();

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    final request = _PendingTopicPage(path);
    requests.add(request);
    _requestsChanged.complete();
    _requestsChanged = Completer<void>();
    return request.response.future;
  }

  Future<void> waitForRequests(int count) async {
    while (requests.length < count) {
      await _requestsChanged.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TestFailure(
          'Expected $count topic-page requests, but received '
          '${requests.length}.',
        ),
      );
    }
  }
}

Future<ShellController> _controlledShell(
  _ControlledPagingApi api,
  DiscourseInstance site,
) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  await api.waitForRequests(1);
  return controller;
}

TopicList _page(int id, {String? moreTopicsUrl}) => TopicList(
  topics: [Topic(id: id, title: 'Topic $id', slug: 'topic-$id')],
  moreTopicsUrl: moreTopicsUrl,
);

final class _PagingApi extends FakeDiscourseApi {
  final List<String> pageSites = [];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (path.contains('page=')) {
      pageSites.add(siteUrl);
      return TopicList(topics: _topics(10, 2));
    }
    return TopicList(topics: _topics(1, 3), moreTopicsUrl: '/latest?page=1');
  }
}

List<Topic> _topics(int first, int count) => [
  for (var id = first; id < first + count; id++)
    Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
];

Future<bool> _sendMetaShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  final handled = await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  return handled;
}

Future<Color> _pixelAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('Could not read rendered pixels.');
  final offset = (y * image.width + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}
