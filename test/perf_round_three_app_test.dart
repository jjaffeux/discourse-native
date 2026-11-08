import 'dart:collection';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/perf_round_three_app_workloads.dart';
import 'support/fakes.dart';

const baseline = bool.fromEnvironment('PERF_BASELINE');

Future<({ShellController shell, TopicTrackingState state})>
categoryFixture() async {
  final state = TopicTrackingState([
    for (var i = 1; i <= 300; i++)
      TrackedTopicState(
        topicId: i,
        categoryId: i % 10,
        highestPostNumber: 4,
        lastReadPostNumber: 1,
        notificationLevel: 2,
      ),
  ]);
  final site = instance(
    'meta.discourse.org',
  ).copyWith(user: const DiscourseUser(id: 7, username: 'reader'));
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(id: 1, name: 'General', color: '111111'),
      ],
      trackingState: state,
    ),
    authenticator: FakeAuthenticator()..keys[site.url] = 'test-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.loadCategories(site.url);
  for (
    var i = 0;
    i < 30 && shell.categoryUnreadTopicCountsFor(site.url) == null;
    i++
  ) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(shell.categoryUnreadTopicCountsFor(site.url), isNotNull);
  return (shell: shell, state: state);
}

void main() {
  test('category reads reuse one settled immutable snapshot', () async {
    final fixture = await categoryFixture();
    final snapshots = HashSet<Map<int, int>>.identity();
    for (var i = 0; i < 100; i++) {
      final counts = fixture.shell.categoryUnreadTopicCountsFor(
        roundThreeSite,
      )!;
      expect(counts, {
        for (var category = 0; category < 10; category++) category: 30,
      });
      snapshots.add(counts);
    }
    // ignore: avoid_print
    print('PERF_R3 category_count_snapshots=${snapshots.length}');
    if (!baseline) expect(snapshots, hasLength(1));
  });

  test(
    'category snapshots follow direct model mutations and retain old values',
    () async {
      final fixture = await categoryFixture();
      final shell = fixture.shell;
      final state = fixture.state;
      Map<int, int> counts() =>
          shell.categoryUnreadTopicCountsFor(roundThreeSite)!;
      final before = counts();
      state.markRead(1, 4);
      expect(counts()[1], 29);
      expect(before[1], 30);
      state.markLastPostUnread(1, 1);
      expect(counts()[1], 30);
      state.applyMessage({
        'topic_id': 1,
        'message_type': 'notification_level_change',
        'payload': {'notification_level': 0},
      });
      expect(counts()[1], 29);
      state.applyMessage({
        'topic_id': 1,
        'message_type': 'notification_level_change',
        'payload': {'notification_level': 2},
      });
      expect(counts()[1], 30);
      state.applyMessage({
        'topic_id': 1,
        'message_type': 'unread',
        'payload': {
          'category_id': 2,
          'highest_post_number': 4,
          'last_read_post_number': 1,
        },
      });
      expect(counts()[1], 29);
      expect(counts()[2], 31);
      state.applyMessage({'topic_id': 1, 'message_type': 'delete'});
      expect(counts()[2], 30);
      state.applyMessage({
        'message_type': 'dismiss_new_posts',
        'payload': {
          'topic_ids': [2, 12],
        },
      });
      expect(counts()[2], 28);
      state.markLastPostUnread(2, 1);
      state.markLastPostUnread(12, 1);
      expect(counts()[2], 30);
      state.applyMessage({'topic_id': 1, 'message_type': 'recover'});
      expect(counts()[2], 31);
      state.applyMessage({'topic_id': 1, 'message_type': 'destroy'});
      expect(counts()[2], 30);
      expect(before[1], 30);
      if (!baseline) expect(() => counts()[1] = 0, throwsUnsupportedError);
    },
  );

  test('chat typing extracts each retained immutable message once', () async {
    final fixture = await roundThreeChatFixture(messages: 0);
    addTearDown(fixture.chat.dispose);
    final messages = [for (var i = 0; i < 30; i++) CountedChatMessage(i + 1)];
    fixture.store.putAll(roundThreeSite, messages);
    for (var i = 0; i < 10; i++) {
      fixture.chat.inboxFilters.setSidebarQuery(
        roundThreeSite,
        i.isEven ? 'keyboard' : 'focus',
      );
      expect(
        fixture.chat.sidebarConversations(roundThreeSite).map((c) => c.id),
        [1],
      );
    }
    final reads = messages.fold(0, (sum, message) => sum + message.cookedReads);
    // ignore: avoid_print
    print('PERF_R3 chat_cooked_reads=$reads');
    if (!baseline) expect(reads, 30);
    fixture.store.put(
      roundThreeSite,
      const ChatMessage(
        id: 1,
        channelId: 1,
        cooked: '<p>Replacement 🐬</p>',
        author: ChatMessageAuthor(id: 1, username: 'reader'),
      ),
    );
    fixture.chat.inboxFilters.setSidebarQuery(roundThreeSite, 'replacement');
    expect(fixture.chat.sidebarConversations(roundThreeSite).map((c) => c.id), [
      1,
    ]);
    fixture.chat.inboxFilters.setSidebarQuery(roundThreeSite, 'keyboard');
    expect(fixture.chat.sidebarConversations(roundThreeSite).map((c) => c.id), [
      1,
    ]);
  });
  test(
    'chat extraction stays lazy for blank, deleted and excluded messages',
    () async {
      final fixture = await roundThreeChatFixture(messages: 0);
      addTearDown(fixture.chat.dispose);
      final empty = CountedChatMessage(1, cooked: '');
      final excluded = CountedChatMessage(2, channelId: 999);
      final deleted = CountedChatMessage(3, deletedAt: DateTime.utc(2026));
      fixture.store.putAll(roundThreeSite, [empty, excluded, deleted]);
      fixture.chat.inboxFilters.setSidebarQuery(roundThreeSite, ' \t ');
      expect(fixture.chat.sidebarConversations(roundThreeSite), hasLength(10));
      expect(empty.cookedReads + excluded.cookedReads + deleted.cookedReads, 0);
      for (var i = 0; i < 10; i++) {
        fixture.chat.inboxFilters.setSidebarQuery(roundThreeSite, 'channel');
        expect(
          fixture.chat.sidebarConversations(roundThreeSite),
          hasLength(10),
        );
      }
      expect(excluded.cookedReads, 0);
      expect(deleted.cookedReads, 0);
      if (!baseline) expect(empty.cookedReads, 1);
    },
  );
}

class CountedChatMessage extends ChatMessage {
  CountedChatMessage(
    int id, {
    String cooked = '<p>Keyboard &amp; focus</p>',
    int channelId = 1,
    DateTime? deletedAt,
  }) : super(
         id: id,
         channelId: channelId,
         cooked: cooked,
         deletedAt: deletedAt,
         author: const ChatMessageAuthor(id: 1, username: 'reader'),
       );
  final _reads = _ReadCount();
  int get cookedReads => _reads.value;
  @override
  String get cooked {
    _reads.value++;
    return super.cooked;
  }
}

class _ReadCount {
  var value = 0;
}
