import 'dart:math';

import 'package:discourse_native/src/models/account_feed_window.dart';
import 'package:discourse_native/src/models/badge.dart';
import 'package:discourse_native/src/models/category_sidebar.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/topic_filter_controller.dart';
import 'package:flutter/foundation.dart';

Future<Map<String, int>> measurePerformanceImprovements() async {
  final results = <String, int>{};
  void measure(String name, int iterations, void Function() action) {
    for (var i = 0; i < 10; i++) {
      action();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      action();
    }
    results[name] = watch.elapsedMicroseconds;
  }

  final feed = TopicFeed(
    topicIds: List.generate(10000, (i) => i),
  ).withVisibleTopics(List.generate(1000, (i) => i * 10));
  measure('unread_row_mapping', 100, () {
    for (var row = 0; row < 1000; row++) {
      final source = feed.sourceRowFor(row);
      if (source != row * 10 || feed.visibleRowForSource(source) != row) {
        throw StateError('row mapping changed');
      }
    }
  });

  final categories = List.generate(
    1000,
    (id) =>
        TopicCategory(id: id, name: 'Category ${1000 - id}', color: '123456'),
  );
  final engine = TopicFilterSuggestions(
    options: const [TopicFilterOption(name: 'category:', type: 'category')],
    categories: categories,
    hierarchicalCategories: true,
    categoryLookup: (_) async => [],
    tags: (_) async => [],
    tagGroups: (_) async => [],
    users: (_) async => [],
    groups: (_) async => [],
  );
  final filterWatch = Stopwatch()..start();
  for (var i = 0; i < 100; i++) {
    final values = await engine.suggestions('category:');
    if (values.length != 1000) throw StateError('category count');
    if (values.any((value) => value.hasChildren)) {
      throw StateError('category children');
    }
  }
  results['category_filter'] = filterWatch.elapsedMicroseconds;

  final hashtags = [
    for (var i = 0; i < 1000; i++)
      FoundHashtag(
        type: 'tag',
        ref: 'tag-$i',
        slug: 'tag-$i',
        text: 'Tag $i',
        id: i,
      ),
  ];
  measure('hashtag_ref_matching', 100, () {
    var matches = 0;
    for (final hashtag in hashtags) {
      if (hashtag.matchesRef('tag-999')) matches++;
    }
    if (matches != 1) throw StateError('hashtag matching');
  });

  final badges = BadgeCatalog([
    BadgeGroup(
      id: 1,
      name: 'Badges',
      badges: [
        for (var i = 0; i < 5000; i++)
          DiscourseBadge(id: i, name: 'Badge $i', hasBadge: i.isEven),
      ],
    ),
  ]);
  measure('badge_summary', 10000, () {
    if (badges.total != 5000 ||
        badges.earned != 2500 ||
        !badges.hasPersonalState) {
      throw StateError('badge summary changed');
    }
  });

  final plain = List.filled(
    30,
    'A plain excerpt with Unicode 🐬 and\tspaces.',
  ).join('\n');
  final normalized = plain.replaceAll(RegExp(r'\s+'), ' ');
  measure('plain_excerpt', 1000, () {
    if (jsonHtmlText(plain) != normalized) throw StateError('excerpt changed');
  });

  final window = AccountFeedWindow<int>(
    packets: [
      for (var page = 0; page < 9; page++)
        AccountFeedPacket(
          start: page,
          end: page + 1,
          items: List.generate(30, (i) => page * 30 + i),
        ),
    ],
  );
  measure('account_page_append', 1000, () {
    final next = window.withPage(
      incoming: [270, 271],
      start: 9,
      end: 10,
      prepend: false,
      identity: (id) => id,
      merge: (_, id) => id,
      estimate: (_) => 64,
    );
    if (next.items.length != 272 || next.items.last != 271) {
      throw StateError('append changed');
    }
  });

  final topics = [
    for (var i = 0; i < 5000; i++)
      TrackedTopicState(
        topicId: i + 1,
        tagIds: {1, if (i == 0) 2},
        createdInNewPeriod: true,
      ),
  ];
  measure('tag_intersection', 200, () {
    final tracking = TopicTrackingState(topics);
    tracking.newActivityCountsFor(tagIds: {1}); // Include lazy index build.
    final counts = tracking.newActivityCountsFor(tagIds: {1, 2});
    if (counts.newTopics != 1 || counts.newReplies != 0) {
      throw StateError('counts changed');
    }
  });

  final shuffled = [...categories]..shuffle(Random(42));
  final expectedIds = [...categories]..sort((a, b) => a.name.compareTo(b.name));
  measure('sidebar_category_sort', 100, () {
    final sorted = orderedSidebarCategories(
      shuffled,
      fixedCategoryPositions: false,
    );
    if (!listEquals(
      sorted.map((c) => c.id).toList(),
      expectedIds.map((c) => c.id).toList(),
    )) {
      throw StateError('sort changed');
    }
  });

  final code = List.filled(1000, '`code without an emoji`').join(' ');
  measure('emoji_free_text', 1000, () {
    if (siteEmojiShortcodeMatches(code).isNotEmpty) {
      throw StateError('spurious emoji');
    }
  });

  final stream = List.generate(10000, (i) => i);
  final gap = List.generate(20, (i) => 10000 + i);
  final detail = TopicDetail(
    id: 1,
    title: 'Topic',
    stream: stream,
    gapsAfter: {9999: gap},
  );
  measure('post_gap_expansion', 1000, () {
    final next = detail.withExpandedGap(
      anchorPostId: 9999,
      before: false,
      consumedIds: gap,
      revealedIds: gap,
    );
    if (next.stream.length != 10020 ||
        next.stream.last != 10019 ||
        next.gapsAfter.isNotEmpty) {
      throw StateError('gap changed');
    }
  });
  return results;
}
