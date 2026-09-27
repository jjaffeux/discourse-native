import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_indicators.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader', unifiedNewEnabled: true);
const _messenger = DiscourseUser(
  id: 7,
  username: 'reader',
  canSendPrivateMessages: true,
  groups: ['team'],
  messageGroupNames: ['team'],
);

void main() {
  for (final mode in [
    TopicListMode.newActivity,
    TopicListMode.newTopics,
    TopicListMode.newReplies,
  ]) {
    testWidgets('${mode.name} dismisses once and refreshes the source', (
      tester,
    ) async {
      final (shell, api, _) = await _setup(tester, mode: mode);
      final gate = Completer<void>();
      api.dismissNewGate = gate;
      api.dismissedNewIds = [1, 2, 3];
      final button = find.byKey(const ValueKey('dismiss-new-topics'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      await shell.dismissNewTopics();
      expect(api.dismissNewCalls, hasLength(1));
      expect(
        api.dismissNewCalls.single.topics,
        mode != TopicListMode.newReplies,
      );
      expect(api.dismissNewCalls.single.posts, mode != TopicListMode.newTopics);
      expect(api.dismissNewCalls.single.topicIds, isNull);
      expect(shell.dismissingNewTopics, isTrue);
      api.feeds[mode.feedPath!] = [];
      gate.complete();
      await tester.pumpAndSettle();
      expect(shell.currentFeed!.topicIds, isEmpty);
      expect(shell.dismissingNewTopics, isFalse);
      expect(button, findsNothing);
      if (mode != TopicListMode.newTopics) expect(shell.newReplyCount, 0);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('failed dismissal preserves rows and can be retried', (
    tester,
  ) async {
    final (shell, api, _) = await _setup(
      tester,
      mode: TopicListMode.newActivity,
    );
    api.dismissNewFailure = StateError('offline');
    expect(await shell.dismissNewTopics(), contains('Could not dismiss'));
    expect(shell.currentFeed!.topicIds, [1, 2, 3]);
    expect(shell.dismissingNewTopics, isFalse);
    api.dismissNewFailure = null;
    expect(await shell.dismissNewTopics(), isNull);
    expect(api.dismissNewCalls, hasLength(2));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('late dismissal stays with its source after navigation', (
    tester,
  ) async {
    final (shell, api, _) = await _setup(
      tester,
      mode: TopicListMode.newActivity,
    );
    final gate = Completer<void>();
    api.dismissNewGate = gate;
    final request = shell.dismissNewTopics();
    await tester.pump();
    await shell.selectTopicListMode(TopicListMode.latest);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dismiss-new-topics')), findsNothing);
    api.feeds['/new.json'] = [];
    gate.complete();
    await request;
    expect(shell.currentTopicListMode, TopicListMode.latest);
    expect(shell.currentFeed!.topicIds, [1, 2, 3]);
    expect(shell.topicFeeds.feedFor(_site, 'new')!.topicIds, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('retired account ignores a late dismissal response', (
    tester,
  ) async {
    final (shell, api, _) = await _setup(
      tester,
      mode: TopicListMode.newActivity,
    );
    final gate = Completer<void>();
    api.dismissNewGate = gate;
    api.dismissedNewIds = [1, 2, 3];
    final request = shell.dismissNewTopics();
    await tester.pump();
    final reads = api.feedPaths.length;
    shell.lifecycle.invalidate(_site);
    gate.complete();
    await request;
    expect(api.feedPaths, hasLength(reads));
    expect(shell.currentFeed!.topicIds, [1, 2, 3]);
    expect(shell.newReplyCount, 3);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  for (final mode in [TopicListMode.unread, TopicListMode.newReplies]) {
    testWidgets('${mode.name} removes fully read topics after moving on', (
      tester,
    ) async {
      final (shell, api, rows) = await _setup(tester, mode: mode, count: 3);
      expect(shell.newReplyCount, 3);
      await _openBeside(tester, _card(1));
      await shell.markTopicRead(_site, 1, 10, caughtUp: true);
      await tester.pumpAndSettle();
      expect(_card(1), findsOneWidget);
      expect(tester.widget<DItem>(_card(1)).selected, isTrue);
      expect(shell.newReplyCount, 2);
      expect(shell.topicListNewCounts.replies, 2);
      expect(shell.currentFeed!.topicIds, [1, 2, 3]);

      await _openBeside(tester, _card(2));
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
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  for (final group in [null, 'team']) {
    final folder = ContentRoute.messages(
      groupName: group,
      mode: MessageListMode.unread,
    );
    final name = group == null ? 'personal' : 'group';

    testWidgets('$name Unread messages remove read ones after moving on', (
      tester,
    ) async {
      final (shell, api, _) = await _setup(tester, folder: folder, count: 2);
      await _openBeside(tester, _card(1));
      await shell.markTopicRead(_site, 1, 10, caughtUp: true);
      await tester.pumpAndSettle();
      expect(_card(1), findsOneWidget);
      expect(tester.widget<DItem>(_card(1)).selected, isTrue);

      await _openBeside(tester, _card(2));
      expect(_card(1), findsNothing);
      expect(tester.widget<DItem>(_card(2)).selected, isTrue);
      expect(shell.currentFeed!.topicIds, [2]);
      expect(shell.topicFeeds.feedFor(_site, folder.id)!.topicIds, [1, 2]);

      await shell.markTopicRead(_site, 2, 10, caughtUp: true);
      shell.closeTopicListReader();
      await tester.pumpAndSettle();
      expect(_card(2), findsNothing);
      expect(find.text("You're all caught up."), findsOneWidget);
      expect(
        api.feedPaths.where((path) => path == _folderPath(folder)),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('$name Unread messages list a read one again after a reply', (
      tester,
    ) async {
      final (shell, api, rows) = await _setup(tester, folder: folder, count: 2);
      await shell.markTopicRead(_site, 1, 10, caughtUp: true);
      await tester.pumpAndSettle();
      expect(_card(1), findsNothing);

      // Core's inbox lists read messages too.
      shell.selectMessageListMode(MessageListMode.inbox);
      await tester.pumpAndSettle();
      expect(shell.currentFeed!.topicIds, [1, 2]);
      expect(_card(1), findsOneWidget);
      shell.selectMessageListMode(MessageListMode.unread);
      await tester.pumpAndSettle();
      expect(_card(1), findsNothing);

      // A response older than the read must not bring the message back.
      await shell.loadFeed(folder.id, force: true);
      await tester.pumpAndSettle();
      expect(_card(1), findsNothing);

      api.feeds[_folderPath(folder)] = [
        _row(1, message: true, highestPostNumber: 11, lastReadPostNumber: 10),
        rows[1],
      ];
      await shell.loadFeed(folder.id, force: true);
      await tester.pumpAndSettle();
      expect(shell.currentFeed!.topicIds, [1, 2]);
      expect(_card(1), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }

  testWidgets('last read topic stays open until the reader closes', (
    tester,
  ) async {
    final (shell, _, _) = await _setup(tester, count: 1);
    await _openBeside(tester, _card(1));
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a reply arriving before departure keeps the topic listed', (
    tester,
  ) async {
    final (shell, _, rows) = await _setup(tester, count: 3);
    await _openBeside(tester, _card(1));
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'a new reply restores a removed topic without changing the reader',
    (tester) async {
      final (shell, _, rows) = await _setup(tester, count: 3);
      await _openBeside(tester, _card(1));
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
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
      await _setup(tester, count: 3);
      await _openBeside(tester, _card(2));
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
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('dismissing New clears the markers of a cached Latest list', (
    tester,
  ) async {
    final (shell, api, _) = await _setup(
      tester,
      mode: TopicListMode.newActivity,
      newIds: {3},
    );
    api.dismissedNewIds = [1, 2, 3];
    api.feeds['/new.json'] = [];
    expect(await shell.dismissNewTopics(), isNull);
    await shell.selectTopicListMode(TopicListMode.latest);
    await tester.pumpAndSettle();
    // Latest is served from its cached page, so only the shared records can
    // carry the dismissal onto it.
    expect(api.feedPaths.where((path) => path == '/latest.json'), hasLength(1));
    _expectDismissed(shell, [1, 2, 3]);
    final dismissedNew = shell.store.read<Topic>(_site, 3)!;
    expect(dismissedNew.lastReadPostNumber, isNull);
    expect(dismissedNew.visited, isFalse);
    expect(shell.store.read<Topic>(_site, 1)!.lastReadPostNumber, 10);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a dismissal from another device clears loaded rows', (
    tester,
  ) async {
    final (shell, _, _) = await _setup(
      tester,
      mode: TopicListMode.latest,
      newIds: {3},
    );
    expect(find.byType(TopicUnreadBadge), findsNWidgets(2));
    expect(find.byType(TopicStateDot), findsOneWidget);
    final tracker = FakeSiteTracker.built.single;
    tracker.deliverTopicTracking(const {
      'message_type': 'dismiss_new',
      'payload': {
        'topic_ids': [3],
      },
    });
    tracker.deliverTopicTracking(const {
      'message_type': 'dismiss_new_posts',
      'payload': {
        'topic_ids': [1, 2, 3],
      },
    });
    await tester.pumpAndSettle();
    _expectDismissed(shell, [1, 2, 3]);
    // Core moves only an existing read position when dismissing new posts.
    expect(shell.store.read<Topic>(_site, 3)!.lastReadPostNumber, isNull);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('stale refresh does not restore dismissed markers', (
    tester,
  ) async {
    final (shell, api, _) = await _setup(
      tester,
      mode: TopicListMode.latest,
      newIds: {3},
    );
    final gate = Completer<void>();
    api.feedGates['/latest.json'] = gate;
    final refresh = shell.loadFeed(TopicListMode.latest.routeId, force: true);
    await tester.pump();
    final tracker = FakeSiteTracker.built.single;
    tracker.deliverTopicTracking(const {
      'message_type': 'dismiss_new',
      'payload': {
        'topic_ids': [3],
      },
    });
    tracker.deliverTopicTracking(const {
      'message_type': 'dismiss_new_posts',
      'payload': {
        'topic_ids': [1, 2],
      },
    });
    gate.complete();
    await refresh;
    await tester.pumpAndSettle();
    _expectDismissed(shell, [1, 2, 3]);

    // A reply since the dismissal counts once a list reports it, while the
    // other rows' pre-dismissal shapes stay cleared.
    api.feeds['/latest.json'] = [
      _row(1, highestPostNumber: 11, lastReadPostNumber: 10),
      _row(2),
      _row(3, isNew: true),
    ];
    await shell.loadFeed(TopicListMode.latest.routeId, force: true);
    await tester.pumpAndSettle();
    expect(shell.store.read<Topic>(_site, 1)!.unreadCount, 1);
    expect(
      find.descendant(of: _card(1), matching: find.byType(TopicUnreadBadge)),
      findsOneWidget,
    );
    _expectDismissed(shell, [2, 3]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'removal keeps a scrolled selection in place and keyboard order follows IDs',
    (tester) async {
      final (shell, _, rows) = await _setup(tester, count: 30);
      shell.openLinkInPanel(
        '/t/${rows[9].slug}/${rows[9].id}',
        title: rows[9].title,
        panel: ForumPanel.secondary,
      );
      await tester.pumpAndSettle();
      final list = tester.widget<SuperListView>(
        find.descendant(
          of: find.byType(TopicListView),
          matching: find.byType(SuperListView),
        ),
      );
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
      await _openBeside(tester, _card(11));
      expect(_card(10), findsNothing);
      expect(tester.getTopLeft(_card(11)).dy, closeTo(before, 1));
      expect(tester.widget<DItem>(_card(11)).selected, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(tester.widget<DItem>(_card(12)).selected, isTrue);
      // The list cursor opens its topic in the list's own panel.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 12);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

Finder _card(int id) => find.byKey(ValueKey('topic-card-$id'));

void _expectDismissed(ShellController shell, List<int> ids) {
  for (final id in ids) {
    final topic = shell.store.read<Topic>(_site, id)!;
    expect(topic.showUnreadCount, isFalse, reason: 'topic $id count');
    expect(topic.showNewTopicDot, isFalse, reason: 'topic $id dot');
    expect(_card(id), findsOneWidget);
    for (final marker in [TopicUnreadBadge, TopicStateDot]) {
      expect(
        find.descendant(of: _card(id), matching: find.byType(marker)),
        findsNothing,
        reason: 'topic $id $marker',
      );
    }
  }
}

// Desktop panels keep a list beside its reader only when the reader opens in
// the secondary panel; a plain click reads in the list's own tab, and a
// shift-click is the pointer's way to read beside the list.
Future<void> _openBeside(WidgetTester tester, Finder row) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  await tester.tap(row, warnIfMissed: false);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

/// Opens [folder]'s message list instead of [mode]'s topic list. Core keeps
/// messages out of topic tracking state, so their rows carry the only counts.
Future<(ShellController, FakeDiscourseApi, List<Topic>)> _setup(
  WidgetTester tester, {
  TopicListMode mode = TopicListMode.unread,
  ContentRoute? folder,
  int count = 3,
  Set<int> newIds = const {},
  Size size = desktop,
  Completer<void>? nextPageGate,
}) async {
  final rows = [
    for (var id = 1; id <= count; id++)
      _row(id, isNew: newIds.contains(id), message: folder != null),
  ];
  final tracking = TopicTrackingState([
    if (folder == null)
      for (final row in rows)
        newIds.contains(row.id)
            ? TrackedTopicState(
                topicId: row.id,
                highestPostNumber: 10,
                createdInNewPeriod: true,
              )
            : TrackedTopicState(
                topicId: row.id,
                highestPostNumber: 10,
                lastReadPostNumber: 4,
                notificationLevel: 2,
              ),
  ]);
  final user = folder == null ? _user : _messenger;
  final feedPath = folder == null
      ? mode.feedPath ?? '/latest.json'
      : _folderPath(folder);
  final api = FakeDiscourseApi(
    user: user,
    trackingState: tracking,
    feeds: {
      '/latest.json': rows,
      if (folder != null)
        _folderPath(ContentRoute.messages(groupName: folder.messageGroupName)):
            rows,
      feedPath: rows,
      if (nextPageGate != null) '/unread.json?page=1': [_row(count + 1)],
    },
    nextPages: {if (nextPageGate != null) feedPath: '/unread.json?page=1'},
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
            privateMessage: folder != null,
          ),
          posts: [],
        ),
    },
  );
  await pumpShell(
    tester,
    size,
    instances: [instance('meta.discourse.org').copyWith(user: user)],
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'reader-key',
  );
  final shell = tester.widget<ShellScope>(find.byType(ShellScope)).notifier!;
  if (folder == null) {
    await shell.selectTopicListMode(mode);
  } else {
    shell.selectDestination(
      const SidebarDestination(
        id: 'messages',
        label: 'Messages',
        icon: DIcons.inbox,
      ),
    );
    await tester.pumpAndSettle();
    shell.selectMessageInbox(folder.messageGroupName);
    shell.selectMessageListMode(folder.messageListMode);
    expect(shell.currentFeedId, folder.id);
  }
  if (nextPageGate == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return (shell, api, rows);
}

String _folderPath(ContentRoute folder) => folder.messageListMode.feedPathFor(
  _messenger.username,
  groupName: folder.messageGroupName,
);

/// A new row is one core serializes as never read: unseen, with no position.
Topic _row(
  int id, {
  bool isNew = false,
  bool message = false,
  int highestPostNumber = 10,
  int lastReadPostNumber = 4,
}) => Topic(
  id: id,
  title: id.isEven
      ? 'Topic $id with a longer title that wraps onto another line'
      : 'Topic $id',
  slug: 'topic-$id',
  excerpt: id.isEven
      ? 'A variable-height topic with some extra context.'
      : null,
  postsCount: highestPostNumber,
  highestPostNumber: highestPostNumber,
  lastReadPostNumber: isNew ? null : lastReadPostNumber,
  unreadPosts: isNew ? 0 : highestPostNumber - lastReadPostNumber,
  newPosts: isNew ? 0 : highestPostNumber - lastReadPostNumber,
  seen: !isNew,
  privateMessage: message,
);
