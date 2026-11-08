import 'dart:math';

import 'package:discourse_native/src/models/account_feed_window.dart';
import 'package:discourse_native/src/models/draft_feed.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_activity_feed.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_ballot_draft.dart';

Map<String, int> measureRoundThreeModelPerformance() {
  final times = <String, int>{};
  void measure(String name, int iterations, void Function() action) {
    for (var i = 0; i < 10; i++) {
      action();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      action();
    }
    times[name] = watch.elapsedMicroseconds;
  }

  final now = DateTime.utc(2026);
  for (final count in [5, 100]) {
    final channels = [
      for (var i = 0; i < count; i++)
        ChatChannel(
          id: i,
          title: 'Room $i',
          kind: ChatChannelKind.category,
          slug: 'engineering-discussion-${i.toString().padLeft(4, '0')}',
        ),
    ]..shuffle(Random(781));
    measure('channel_alphabetical_$count', 10000, () {
      final sorted = projectChatChannelList(
        channels,
        filter: ChatChannelListFilter.all,
        sort: ChatChannelListSort.alphabetical,
        section: ChatChannelListSection.channels,
        now: now,
      );
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].id != i) throw StateError('Channel ordering changed');
      }
    });
  }
  for (final count in [30, 300]) {
    final source = modelActivityFeed(count);
    final page = UserActivityPage(
      items: [modelActivity(count)],
      categories: source.categoriesById.values.toList(),
      rawItemCount: 1,
    );
    final expected = source.estimatedRetainedBytes;
    measure('activity_category_estimation_$count', 2000, () {
      final updated = source.withPage(page, limit: 30, replace: false);
      final first = count < 300 ? 0 : 30;
      if (updated.items.length != count + 1 - first) {
        throw StateError('Activity append count changed');
      }
      for (var i = 0; i < updated.items.length; i++) {
        if (updated.items[i].topicId != first + i) {
          throw StateError('Activity retention order changed');
        }
      }
      if (updated.items.last.topicId != count ||
          updated.estimatedRetainedBytes < expected ~/ 2) {
        throw StateError('Activity retention changed');
      }
    });
  }
  final packets = [
    for (var page = 0; page < 9; page++)
      AccountFeedPacket<UserDraft>(
        start: page * 30,
        end: (page + 1) * 30,
        items: [
          for (var i = page * 30; i < (page + 1) * 30; i++)
            UserDraft(key: 'topic_$i', sequence: 1, data: null),
        ],
      ),
  ];
  final window = AccountFeedWindow<UserDraft>(packets: packets);
  final feed = DraftFeed(
    drafts: window.items,
    loaded: true,
    nextOffset: 270,
    totalCount: 270,
    window: window,
  );
  for (final (name, key, removed) in [
    ('first', 'topic_0', true),
    ('last', 'topic_269', true),
    ('missing', 'topic_999', false),
  ]) {
    measure('draft_delete_$name', 10000, () {
      final updated = feed.without(key);
      if (updated.drafts.length != (removed ? 269 : 270) ||
          updated.nextOffset != (removed ? 269 : 270) ||
          updated.drafts.any((row) => row.key == key)) {
        throw StateError('Draft deletion changed');
      }
    });
  }
  for (final count in [3, 100]) {
    final poll = Poll(
      name: 'poll',
      options: [
        for (var i = 0; i < count; i++) PollOption(id: '$i', html: 'Option $i'),
      ],
    );
    final draft = PollBallotDraft(poll);
    measure('poll_same_reconcile_$count', 100000, () {
      final result = draft.reconcile(poll);
      if (result.selection.isNotEmpty || result.submission != null) {
        throw StateError('Poll reconciliation changed');
      }
    });
    final next = Poll(
      name: 'poll',
      options: [
        for (var i = 0; i < count; i++)
          PollOption(id: '$i', html: 'Updated option $i'),
      ],
    );
    measure('poll_changed_reconcile_$count', 10000, () {
      final result = draft.reconcile(next);
      if (result.selection.isNotEmpty || result.submission != null) {
        throw StateError('Changed poll reconciliation changed');
      }
    });
  }
  return times;
}

UserActivityItem modelActivity(int id) => UserActivityItem(
  actionType: 4,
  topicId: id,
  postNumber: 1,
  title: 'Topic $id',
  slug: 'topic-$id',
  username: 'reader',
  excerpt: 'A short activity excerpt',
  categoryId: 1,
);

UserActivityFeed modelActivityFeed(int count, {TopicCategory? category}) {
  final packets = [
    for (var page = 0; page < count ~/ 30; page++)
      AccountFeedPacket<UserActivityItem>(
        start: page * 30,
        end: (page + 1) * 30,
        items: [
          for (var i = page * 30; i < (page + 1) * 30; i++) modelActivity(i),
        ],
      ),
  ];
  final window = AccountFeedWindow<UserActivityItem>(packets: packets);
  return UserActivityFeed(
    items: window.items,
    nextOffset: count,
    window: window,
    categoriesById: {
      1:
          category ??
          const TopicCategory(
            id: 1,
            name: 'Engineering discussion',
            color: '336699',
          ),
    },
  );
}
