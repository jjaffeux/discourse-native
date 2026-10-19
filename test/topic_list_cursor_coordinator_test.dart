import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_list_cursor_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Topic _topic(int id) => Topic(id: id, title: 'Topic $id', slug: 'topic-$id');

final class _TopicRequest {
  _TopicRequest(this.id);

  final int id;
  final Completer<Topic> result = Completer<Topic>();
}

final class _CursorApi extends FakeDiscourseApi {
  _CursorApi(List<Topic> topics)
    : super(feeds: {'/latest.json': topics, '/hot.json': const []});

  final List<_TopicRequest> requests = [];
  Completer<_TopicRequest>? nextRequest;

  @override
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) {
    final request = _TopicRequest(id);
    requests.add(request);
    nextRequest?.complete(request);
    nextRequest = null;
    return request.result.future;
  }
}

final class _CursorFixture {
  _CursorFixture._(this.shell, this.api, this.tab, this.feed);

  static Future<_CursorFixture> create({
    List<int> ids = const [1, 2, 3],
  }) async {
    final topics = [for (final id in ids) _topic(id)];
    final api = _CursorApi(topics);
    final shell = ShellController(
      instanceStore: FakeInstanceStore([instance('cursor.example')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    await shell.load();
    await shell.loadFeed('latest');
    final tab = shell.focusedTabContext;
    return _CursorFixture._(shell, api, tab, tab.currentFeed!);
  }

  final ShellController shell;
  final _CursorApi api;
  final ShellTabContext tab;
  final TopicFeed feed;
  final List<void Function()> frames = [];
  final List<TopicListCursor> saves = [];
  final List<int?> selected = [];
  final List<int> revealed = [];
  final List<int> opened = [];
  Completer<void>? nextFrameQueued;
  bool keyboardAvailable = true;
  late final coordinator = TopicListCursorCoordinator(
    tab: tab,
    feed: feed,
    keyboardAvailable: () => keyboardAvailable,
    afterFrame: (callback) {
      frames.add(callback);
      nextFrameQueued?.complete();
      nextFrameQueued = null;
    },
    onCursorChanged: saves.add,
    onKeyboardSelection: (topic) => selected.add(topic?.id),
    revealRow: revealed.add,
    openTopic: (topic) => opened.add(topic.id),
  );

  void frame() {
    final callbacks = List<void Function()>.of(frames);
    frames.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  void dispose() {
    coordinator.dispose();
    shell.dispose();
    for (final request in api.requests) {
      if (!request.result.isCompleted) {
        request.result.complete(_topic(request.id));
      }
    }
  }
}

void main() {
  setUp(() => expect(BindingBase.debugBindingType(), isNull));
  tearDown(() => expect(BindingBase.debugBindingType(), isNull));

  test('a second key waits for the reveal frame, then advances', () async {
    final fixture = await _CursorFixture.create();
    addTearDown(fixture.dispose);
    final cursor = fixture.coordinator;

    expect(cursor.move(1, firstVisibleRow: 0), isTrue);
    expect(fixture.saves.map((saved) => saved.topicId), [1]);
    expect(fixture.selected, [1]);
    expect(cursor.move(1, firstVisibleRow: 0), isTrue);
    expect(fixture.saves.map((saved) => saved.topicId), [1]);
    expect(fixture.revealed, isEmpty);

    fixture.frame();
    expect(fixture.revealed, [0]);
    expect(cursor.move(1, firstVisibleRow: 0), isTrue);
    expect(fixture.saves.map((saved) => saved.topicId), [1, 2]);
    expect(fixture.selected, [1, 2]);
    fixture.frame();
    expect(fixture.revealed, [0, 1]);
  });

  test('a failed fetch holds movement until its completion frame', () async {
    final fixture = await _CursorFixture.create();
    addTearDown(fixture.dispose);
    fixture.shell.store.remove<Topic>(fixture.tab.siteUrl!, 1);
    final started = fixture.api.nextRequest = Completer<_TopicRequest>();

    expect(fixture.coordinator.move(1, firstVisibleRow: 0), isTrue);
    final request = await started.future.timeout(const Duration(seconds: 5));
    expect(request.id, 1);
    expect(fixture.coordinator.move(1, firstVisibleRow: 0), isTrue);
    expect(fixture.api.requests, hasLength(1));
    final frameQueued = fixture.nextFrameQueued = Completer<void>();
    request.result.completeError(StateError('fetch failed'));
    await frameQueued.future.timeout(const Duration(seconds: 5));
    expect(fixture.saves.map((saved) => saved.topicId), [1]);
    expect(fixture.selected, [null]);
    expect(fixture.coordinator.move(1, firstVisibleRow: 0), isTrue);
    expect(fixture.api.requests, hasLength(1));

    fixture.frame();
    expect(fixture.revealed, [0]);
    expect(fixture.coordinator.move(1, firstVisibleRow: 0), isTrue);
    expect(fixture.saves.map((saved) => saved.topicId), [1, 2]);
  });

  test('an older frame cannot retire a newer movement', () async {
    final fixture = await _CursorFixture.create();
    addTearDown(fixture.dispose);

    fixture.coordinator.move(1, firstVisibleRow: 0);
    fixture.coordinator.opened(2, keyboard: false);
    fixture.coordinator.move(1, firstVisibleRow: 0);
    expect(fixture.selected, [1, 3]);

    fixture.frame();
    expect(fixture.revealed, [2]);
    fixture.coordinator.move(-1, firstVisibleRow: 0);
    expect(fixture.selected, [1, 3, 2]);
  });

  for (final change in ['opened', 'retired', 'route', 'account']) {
    test('queued reveal is discarded after $change', () async {
      final fixture = await _CursorFixture.create();
      addTearDown(fixture.dispose);
      fixture.coordinator.move(1, firstVisibleRow: 0);
      expect(fixture.selected, [1]);

      switch (change) {
        case 'opened':
          fixture.coordinator.opened(2, keyboard: false);
          expect(fixture.saves.last.topicId, 2);
        case 'retired':
          fixture.coordinator.retire();
        case 'route':
          fixture.shell.pushContent(
            ContentRoute.topic(topicId: 2, slug: 'topic-2', title: 'Topic 2'),
          );
        case 'account':
          fixture.shell.lifecycle.invalidate(fixture.tab.siteUrl!);
      }

      fixture.frame();
      expect(fixture.revealed, isEmpty);
    });
  }

  test('selection reads its captured source tab after focus changes', () async {
    final fixture = await _CursorFixture.create();
    addTearDown(fixture.dispose);
    final sourceId = fixture.tab.tabId;
    fixture.shell.createTab();
    fixture.shell.pushContent(ContentRoute.topicList(TopicListMode.popular));
    await fixture.shell.loadFeed('hot');
    expect(fixture.shell.activeTabId, isNot(sourceId));
    expect(fixture.shell.currentFeedId, 'hot');
    expect(fixture.shell.currentFeed?.topicIds, isEmpty);
    expect(fixture.tab.isCurrent, isTrue);
    expect(fixture.tab.currentFeed?.topicIds, [1, 2, 3]);

    expect(fixture.coordinator.move(1, firstVisibleRow: 1), isTrue);
    expect(fixture.saves.single.topicId, 2);
    expect(fixture.selected, [2]);
    fixture.frame();
    expect(fixture.revealed, [1]);
    expect(fixture.shell.activeTabId, isNot(sourceId));
  });

  test('incoming and hidden rows rebase cursor in save order', () async {
    final fixture = await _CursorFixture.create();
    addTearDown(fixture.dispose);
    final cursor = fixture.coordinator;
    cursor.remember(3, keyboard: true);
    expect(fixture.saves.single.index, 2);

    cursor.updateFeed(
      const TopicFeed(
        topicIds: [1, 2],
        totalRows: 3,
        loadingIncoming: true,
        loaded: true,
      ),
    );
    expect(fixture.saves.map((saved) => saved.index), [2]);
    cursor.updateFeed(
      const TopicFeed(topicIds: [7, 1, 2], totalRows: 4, loaded: true),
    );
    expect(fixture.saves.last, (topicId: 3, index: 3, keyboard: true));

    cursor.updateFeed(const TopicFeed(topicIds: [7, 1, 2, 3], loaded: true));
    cursor.updateFeed(
      const TopicFeed(
        topicIds: [7, 1, 2, 3],
        loaded: true,
      ).withVisibleTopics([7, 1, 3]),
    );
    expect(fixture.saves.last, (topicId: 3, index: 2, keyboard: true));
    expect(fixture.saves.map((saved) => saved.index), [2, 3, 2]);
  });

  for (final action in ['cancel', 'move', 'opened', 'retired', 'account']) {
    test('pending restore stays canceled after $action', () async {
      final fixture = await _CursorFixture.create();
      addTearDown(fixture.dispose);
      fixture.coordinator.remember(1, keyboard: true);
      fixture.shell.store.remove<Topic>(fixture.tab.siteUrl!, 1);
      final started = fixture.api.nextRequest = Completer<_TopicRequest>();
      expect(fixture.coordinator.openSelection(), isTrue);
      final request = await started.future.timeout(const Duration(seconds: 5));
      expect(request.id, 1);
      final restoration = fixture.tab.restoreFeedTopic('latest', 1);

      switch (action) {
        case 'cancel':
          fixture.coordinator.cancelSelectionRestore();
        case 'move':
          fixture.coordinator.move(1, firstVisibleRow: 0);
        case 'opened':
          fixture.coordinator.opened(2, keyboard: false);
        case 'retired':
          fixture.coordinator.retire();
        case 'account':
          fixture.shell.lifecycle.invalidate(fixture.tab.siteUrl!);
      }
      request.result.complete(_topic(1));
      await restoration.timeout(const Duration(seconds: 5));
      expect(fixture.opened, isEmpty);
    });
  }
}
