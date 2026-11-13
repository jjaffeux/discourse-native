import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/models/account_feed_window.dart';
import 'package:discourse_native/src/models/category_sidebar.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_message_filter.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_preferences.dart';
import 'package:flutter/foundation.dart';

void main() {
  final packets = [
    for (var page = 0; page < 2; page++)
      AccountFeedPacket(
        start: page * 30,
        end: (page + 1) * 30,
        items: List.generate(30, (i) => page * 30 + i),
      ),
  ];
  final windows = [
    for (final packet in packets) AccountFeedWindow(packets: [packet]),
  ];
  final now = DateTime.utc(2026);
  final filter = TopicTrackingMessageFilter(clock: () => now);
  const user = DiscourseUser(username: 'reader', mutedTagIds: [1, 2, 3, 4]);
  final cases =
      [
        ('always', [1, 2, 3, 4, 5], false),
        ('always', [6, 7, 8, 9], true),
        ('only_muted', [6, 1, 2, 3, 4], true),
        ('only_muted', [1, 2, 3, 4], false),
        ('only_muted', <int>[], true),
      ].indexed.map((entry) {
        final (i, (mode, tags, expected)) = entry;
        return (
          SiteConfig(removeMutedTagsFromLatest: mode),
          {
            'topic_id': i + 1,
            'message_type': 'new_topic',
            'payload': {
              'category_id': 3,
              'tags': [
                for (final id in tags) {'id': id},
              ],
            },
          },
          expected,
        );
      }).toList();
  final categories = [
    for (var group = 20; group >= 1; group--) ...[
      for (var child = 15; child >= 1; child--)
        TopicCategory(
          id: group * 100 + child,
          name: 'Child $child',
          color: 'ffff00',
          position: child,
          parentCategoryId: group * 100,
        ),
      TopicCategory(
        id: group * 100,
        name: 'Root $group',
        color: '00ffff',
        position: group,
      ),
    ],
  ];
  final expectedCategories = [
    for (var group = 1; group <= 20; group++) ...[
      group * 100,
      for (var child = 1; child <= 15; child++) group * 100 + child,
    ],
  ];
  final channels = [
    for (var i = 100; i >= 1; i--)
      ChatChannel(
        id: i,
        title: 'Channel $i',
        kind: ChatChannelKind.category,
        slug: 'NEWS-TOPIC-${i.toString().padLeft(3, '0')}',
        tracking: ChatTracking(
          mentionCount: i % 9 == 0 ? 1 : 0,
          unreadCount: i % 3 == 0 ? 1 : 0,
        ),
      ),
  ];
  final expectedChannels = [
    for (var i = 1; i <= 100; i++)
      if (i % 9 == 0) i,
    for (var i = 1; i <= 100; i++)
      if (i % 3 == 0 && i % 9 != 0) i,
    for (var i = 1; i <= 100; i++)
      if (i % 3 != 0) i,
  ];
  final results = {
    'account_feed_first_page_rows': _measure(
      50000,
      (i) => windows[i % 2].items,
      (i, result) => listEquals(result, packets[i % 2].items),
    ),
    'filter_muted_tags_on_live_arrival': _measure(35000, (i) {
      final (config, message, _) = cases[i % cases.length];
      return filter.accepts(message, user: user, config: config);
    }, (i, result) => result == cases[i % cases.length].$3),
    'category_tree_preorder': _measure(
      2500,
      (_) => orderedSidebarCategories(categories, fixedCategoryPositions: true),
      (_, result) => listEquals([
        for (final category in result) category.id,
      ], expectedCategories),
    ),
    'chat_channel_priority_order': _measure(
      2800,
      (_) => projectChatChannelList(
        channels,
        filter: ChatChannelListFilter.all,
        sort: ChatChannelListSort.priority,
        section: ChatChannelListSection.channels,
        now: now,
      ),
      (_, result) => listEquals([
        for (final channel in result) channel.id,
      ], expectedChannels),
    ),
  };
  stdout.writeln(jsonEncode(results));
  exit(0);
}

double _measure<T>(
  int iterations,
  T Function(int) run,
  bool Function(int, T) validate,
) {
  final results = List<T?>.filled(iterations, null);
  final samples = <double>[];
  for (var batch = 0; batch < 10; batch++) {
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      results[i] = run(i);
    }
    stopwatch.stop();
    for (var i = 0; i < iterations; i++) {
      if (!validate(i, results[i] as T)) throw StateError('Incorrect result');
    }
    if (batch >= 3) {
      samples.add(stopwatch.elapsedMicroseconds / iterations);
    }
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}
