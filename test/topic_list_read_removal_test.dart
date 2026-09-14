import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader', unifiedNewEnabled: true);

void main() {
  for (final mode in [TopicListMode.unread, TopicListMode.newReplies]) {
    testWidgets('${mode.name} removes fully read topics after moving on', (
      tester,
    ) async {
      final (shell, api, rows) = await _setup(tester, mode: mode, count: 3);
      expect(shell.newReplyCount, 3);
      shell.openTopicFromList(rows[0]);
      await tester.pumpAndSettle();
      await shell.markTopicRead(_site, 1, 10, caughtUp: true);
      await tester.pumpAndSettle();
      expect(_card(1), findsOneWidget);
      expect(tester.widget<DItem>(_card(1)).selected, isTrue);
      expect(shell.newReplyCount, 2);
      expect(shell.topicListNewCounts.replies, 2);
      expect(shell.currentFeed!.topicIds, [1, 2, 3]);

      await tester.tap(_card(2));
      await tester.pumpAndSettle();
      expect(_card(1), findsNothing);
      expect(tester.widget<DItem>(_card(2)).selected, isTrue);
      expect(shell.currentContent?.topicId, 2);
      expect(shell.currentFeed!.topicIds, [2, 3]);

      await shell.markTopicRead(_site, 2, 8, caughtUp: false);
      shell.openTopicFromList(rows[2]);
      await tester.pumpAndSettle();
      expect(_card(2), findsOneWidget);
      expect(shell.currentFeed!.topicIds, [2, 3]);
      expect(shell.topicFeeds.feedFor(_site, mode.routeId)!.topicIds, [
        1,
        2,
        3,
      ]);
      expect(
        api.feedPaths.where((path) => path == mode.feedPath),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('last read topic stays open until the reader closes', (
    tester,
  ) async {
    final (shell, _, rows) = await _setup(tester, count: 1);
    shell.openTopicFromList(rows.single);
    await tester.pumpAndSettle();
    await shell.markTopicRead(_site, 1, 10, caughtUp: true);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 1);
    expect(_card(1), findsOneWidget);
    expect(find.text("You're all caught up."), findsNothing);
    shell.closeTopicListReader();
    await tester.pumpAndSettle();
    expect(_card(1), findsNothing);
    expect(find.text("You're all caught up."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reply arriving before departure keeps the topic listed', (
    tester,
  ) async {
    final (shell, _, rows) = await _setup(tester, count: 3);
    shell.openTopicFromList(rows.first);
    await tester.pumpAndSettle();
    await shell.markTopicRead(_site, 1, 10, caughtUp: true);
    FakeSiteTracker.built.single.deliverTopicTracking(const {
      'topic_id': 1,
      'message_type': 'unread',
      'payload': {
        'highest_post_number': 11,
        'last_read_post_number': 4,
        'notification_level': 2,
      },
    });
    shell.openTopicFromList(rows[1]);
    await tester.pumpAndSettle();
    expect(shell.currentFeed!.topicIds, [1, 2, 3]);
    expect(_card(1), findsOneWidget);
    expect(shell.newReplyCount, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a new reply restores a removed topic without changing the reader',
    (tester) async {
      final (shell, _, rows) = await _setup(tester, count: 3);
      shell.openTopicFromList(rows.first);
      await tester.pumpAndSettle();
      await shell.markTopicRead(_site, 1, 10, caughtUp: true);
      shell.openTopicFromList(rows[1]);
      await tester.pumpAndSettle();
      expect(_card(1), findsNothing);
      FakeSiteTracker.built.single.deliverTopicTracking(const {
        'topic_id': 1,
        'message_type': 'unread',
        'payload': {'highest_post_number': 11, 'notification_level': 2},
      });
      await tester.pumpAndSettle();
      expect(_card(1), findsOneWidget);
      expect(shell.currentContent?.topicId, 2);
      expect(tester.widget<DItem>(_card(2)).selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('returning to the list on a phone removes the read topic', (
    tester,
  ) async {
    final (shell, _, rows) = await _setup(tester, count: 2, size: phone);
    shell.openTopicFromList(rows.first);
    await tester.pumpAndSettle();
    await shell.markTopicRead(_site, 1, 10, caughtUp: true);
    shell.closeTopicListReader();
    await tester.pumpAndSettle();
    expect(shell.currentFeed!.topicIds, [2]);
    expect(_card(1), findsNothing);
    expect(_card(2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'read messages clear inactive rows while preserving the selection',
    (tester) async {
      final (shell, _, rows) = await _setup(tester, count: 3);
      shell.openTopicFromList(rows[1]);
      await tester.pumpAndSettle();
      FakeSiteTracker.built.single.deliverTopicTracking(const {
        'topic_id': 1,
        'message_type': 'read',
        'payload': {'highest_post_number': 10, 'last_read_post_number': 10},
      });
      await tester.pumpAndSettle();
      expect(_card(1), findsNothing);
      expect(tester.widget<DItem>(_card(2)).selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale refresh does not restore read rows or their indicators', (
    tester,
  ) async {
    final (shell, _, rows) = await _setup(tester, count: 3);
    shell.openTopicFromList(rows[0]);
    await tester.pumpAndSettle();
    await shell.markTopicRead(_site, 1, 10, caughtUp: true);
    await shell.loadFeed(TopicListMode.unread.routeId, force: true);
    await tester.pumpAndSettle();
    expect(shell.store.read<Topic>(_site, 1)!.hasUnread, isFalse);
    shell.openTopicFromList(rows[1]);
    await tester.pumpAndSettle();
    expect(_card(1), findsNothing);
    await shell.selectTopicListMode(TopicListMode.latest);
    await tester.pumpAndSettle();
    expect(_card(1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removal keeps a scrolled selection in place and keyboard order follows IDs',
    (tester) async {
      final (shell, _, rows) = await _setup(tester, count: 30);
      shell.openTopicFromList(rows[9]);
      await tester.pumpAndSettle();
      final list = tester.widget<SuperListView>(find.byType(SuperListView));
      list.listController!.jumpToItem(
        index: 18,
        scrollController: list.controller!,
        alignment: 0,
      );
      await tester.pumpAndSettle();
      expect(_card(11).hitTestable(), findsOneWidget);
      final before = tester.getTopLeft(_card(11)).dy;
      await shell.markTopicRead(_site, 10, 10, caughtUp: true);
      await tester.pumpAndSettle();
      await tester.tap(_card(11));
      await tester.pumpAndSettle();
      expect(_card(10), findsNothing);
      expect(tester.getTopLeft(_card(11)).dy, closeTo(before, 1));
      expect(tester.widget<DItem>(_card(11)).selected, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 12);
      expect(tester.widget<DItem>(_card(12)).selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an empty filtered page loads the next page before showing caught up',
    (tester) async {
      final gate = Completer<void>();
      final (shell, api, _) = await _setup(
        tester,
        count: 1,
        nextPageGate: gate,
      );
      await shell.markTopicRead(_site, 1, 10, caughtUp: true);
      await tester.pump();
      await tester.pump();
      expect(find.text("You're all caught up."), findsNothing);
      expect(
        api.feedPaths.where((path) => path.contains('page=1')),
        hasLength(1),
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(_card(2), findsOneWidget);
      expect(shell.currentFeed!.topicIds, [2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an empty filtered page can retry a failed next page', (
    tester,
  ) async {
    final gate = Completer<void>();
    final (shell, api, _) = await _setup(tester, count: 1, nextPageGate: gate);
    await shell.markTopicRead(_site, 1, 10, caughtUp: true);
    await tester.pump();
    await tester.pump();
    gate.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(find.text("You're all caught up."), findsNothing);
    expect(
      find.text("Couldn't load more topics from meta.discourse.org."),
      findsOneWidget,
    );
    api.feedGates.remove('/unread.json?page=1');
    await tester.tap(find.byKey(const ValueKey('topic-feed-initial-retry')));
    await tester.pumpAndSettle();
    expect(_card(2), findsOneWidget);
    expect(api.feedPaths.where((path) => path == '/unread.json'), hasLength(1));
    expect(
      api.feedPaths.where((path) => path == '/unread.json?page=1'),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _card(int id) => find.byKey(ValueKey('topic-card-$id'));

Future<(ShellController, FakeDiscourseApi, List<Topic>)> _setup(
  WidgetTester tester, {
  TopicListMode mode = TopicListMode.unread,
  int count = 3,
  Size size = desktop,
  Completer<void>? nextPageGate,
}) async {
  final rows = [for (var id = 1; id <= count; id++) _row(id)];
  final tracking = TopicTrackingState([
    for (final row in rows)
      TrackedTopicState(
        topicId: row.id,
        highestPostNumber: 10,
        lastReadPostNumber: 4,
        notificationLevel: 2,
      ),
  ]);
  final api = FakeDiscourseApi(
    user: _user,
    trackingState: tracking,
    feeds: {
      '/latest.json': rows,
      mode.feedPath!: rows,
      if (nextPageGate != null) '/unread.json?page=1': [_row(count + 1)],
    },
    nextPages: {
      if (nextPageGate != null) mode.feedPath!: '/unread.json?page=1',
    },
    feedGates: {'/unread.json?page=1': ?nextPageGate},
    // An empty stream keeps this test's explicit reading observations in
    // control while exercising the real sidebar, reader route and selectors.
    topics: {
      for (final row in rows)
        row.id: (
          detail: TopicDetail(
            id: row.id,
            title: row.title,
            stream: const [],
            postsCount: 10,
          ),
          posts: [],
        ),
    },
  );
  await pumpShell(
    tester,
    size,
    instances: [instance('meta.discourse.org').copyWith(user: _user)],
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'reader-key',
  );
  final shell = tester.widget<ShellScope>(find.byType(ShellScope)).notifier!;
  await shell.selectTopicListMode(mode);
  if (nextPageGate == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return (shell, api, rows);
}

Topic _row(int id) => Topic(
  id: id,
  title: id.isEven
      ? 'Topic $id with a longer title that wraps onto another line'
      : 'Topic $id',
  slug: 'topic-$id',
  excerpt: id.isEven
      ? 'A variable-height topic with some extra context.'
      : null,
  postsCount: 10,
  highestPostNumber: 10,
  lastReadPostNumber: 4,
  unreadPosts: 6,
);
