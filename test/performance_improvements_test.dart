import 'dart:collection';
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
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const baseline = bool.fromEnvironment('PERF_BASELINE');

void main() {
  test('hidden row maps match a dense reference for arbitrary removals', () {
    final random = Random(51);
    for (var trial = 0; trial < 100; trial++) {
      final source = List.generate(300, (i) => i);
      final kept = source.where((_) => random.nextBool()).toList();
      final feed = TopicFeed(topicIds: source).withVisibleTopics(kept);
      expect(feed.rowCount, kept.length);
      for (var row = 0; row < kept.length; row++) {
        expect(feed.sourceRowFor(row), kept[row]);
        expect(feed.visibleRowForSource(kept[row]), row);
        expect(feed.topicIdAt(row), kept[row]);
      }
      final keptAgain = kept.where((_) => random.nextBool()).toList();
      final next = feed.withVisibleTopics(keptAgain);
      for (var row = 0; row < keptAgain.length; row++) {
        expect(next.sourceRowFor(row), keptAgain[row]);
        expect(next.visibleRowForSource(keptAgain[row]), row);
      }
    }
    final hidden = _ReadList(List.generate(9000, (i) => i));
    final feed = TopicFeed(
      topicIds: const [1],
      totalRows: 9001,
      hiddenRows: hidden,
    );
    expect(feed.sourceRowFor(0), 9000);
    expect(feed.visibleRowForSource(9000), 0);
    if (!baseline) expect(hidden.reads, lessThanOrEqualTo(28));
    // ignore: avoid_print
    print('WORK hidden_row_reads=${hidden.reads}');
    // The default feed retains at most 300 topic IDs: cover that bound too.
    final boundedHidden = _ReadList(List.generate(270, (i) => i));
    final boundedFeed = TopicFeed(
      topicIds: const [1],
      totalRows: 300,
      hiddenRows: boundedHidden,
    );
    expect(boundedFeed.sourceRowFor(0), 270);
    expect(boundedFeed.visibleRowForSource(270), 0);
    if (!baseline) expect(boundedHidden.reads, lessThanOrEqualTo(18));
    // ignore: avoid_print
    print('WORK bounded_hidden_row_reads=${boundedHidden.reads}');
  });

  test(
    'hierarchical filter child detection walks categories linearly',
    () async {
      final counts = _CategoryReads();
      final categories = [
        for (var i = 0; i < 1000; i++) _CountedCategory(i, counts),
      ];
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
      final rows = await engine.suggestions('category:');
      expect(rows, hasLength(1000));
      expect(rows.every((row) => !row.hasChildren), isTrue);
      if (!baseline) expect(counts.parents, lessThanOrEqualTo(4000));
      // ignore: avoid_print
      print('WORK filter_parent_reads=${counts.parents}');
    },
  );

  test('hashtag matching agrees with the qualified-ref wire rules', () {
    const names = [
      'tag',
      'Tag',
      'TAG',
      '🐬',
      '',
      'tag::tag',
      'tag::category',
      'tag::::tag',
      'tag::tag::tag',
      ':::tag',
      '::tag',
      'tag::',
      '::',
    ];
    for (final type in ['tag', 'category', '', ':tag']) {
      for (final canonical in names) {
        final candidate = FoundHashtag(
          type: type,
          ref: canonical,
          slug: canonical,
          text: canonical,
          id: 1,
        );
        for (final requested in names) {
          final asked = requested.split('::');
          final held = canonical.split('::');
          final expected =
              asked.length <= 2 &&
              held.length <= 2 &&
              (asked.length < 2 || asked.last == type) &&
              (held.length < 2 || (held.last == type && asked.length == 2)) &&
              asked.first.toLowerCase() == held.first.toLowerCase();
          expect(
            candidate.matchesRef(requested),
            expected,
            reason: '$type $canonical $requested',
          );
        }
      }
    }
  });

  test('badge summaries are stable immutable snapshots', () {
    final source = [
      const DiscourseBadge(id: 1, name: 'One', hasBadge: true),
      const DiscourseBadge(id: 2, name: 'Two', hasBadge: false),
      const DiscourseBadge(id: 3, name: 'Three'),
    ];
    final groups = [BadgeGroup(id: 1, name: 'Group', badges: source)];
    final catalog = BadgeCatalog(groups);
    source.clear();
    groups.clear();
    for (var i = 0; i < 100; i++) {
      expect(catalog.total, 3);
      expect(catalog.earned, 1);
      expect(catalog.hasPersonalState, isTrue);
    }
    expect(BadgeCatalog(const []).total, 0);
    expect(BadgeCatalog(const []).hasPersonalState, isFalse);
  });

  test('plain excerpt fast path agrees with HTML tokenizer', () {
    final random = Random(12);
    const alphabet = [
      'a',
      'Z',
      ' ',
      '\t',
      '\n',
      '\f',
      '\v',
      '\u00a0',
      '🐬',
      'é',
      '中',
      '>',
      '"',
    ];
    for (var i = 0; i < 500; i++) {
      final source = List.generate(
        100,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
      final expected = jsonText(
        html.parseFragment(source.trim()).text?.replaceAll(RegExp(r'\s+'), ' '),
      );
      expect(jsonHtmlText(source), expected);
    }
    for (final source in ['a\r\nb', 'a\u0000b', 'a &amp; b', '<p>A<br>B</p>']) {
      expect(
        jsonHtmlText(source),
        source == '<p>A<br>B</p>'
            ? 'A B'
            : jsonText(
                html
                    .parseFragment(source)
                    .text
                    ?.replaceAll(RegExp(r'\s+'), ' '),
              ),
      );
    }
    expect(
      jsonHtmlText('<img class="emoji" alt=":wave:" src="/wave.png">'),
      ':wave:',
    );
  });

  test(
    'page appends retain unchanged packets and replace overlapping rows',
    () {
      final source = [1, 2];
      final packet = AccountFeedPacket(start: 0, end: 1, items: source);
      final window = AccountFeedWindow(packets: [packet]);
      final next = window.withPage(
        incoming: [3],
        start: 1,
        end: 2,
        prepend: false,
        identity: (id) => id,
        merge: (_, id) => id,
        estimate: (_) => 64,
      );
      source.clear();
      expect(next.items, [1, 2, 3]);
      expect(next.packets.first, same(packet));
      expect(() => next.packets.first.items.clear(), throwsUnsupportedError);
      final overlapping = window.withPage(
        incoming: [2],
        start: 1,
        end: 2,
        prepend: false,
        identity: (id) => id,
        merge: (_, id) => id + 10,
        estimate: (_) => 64,
      );
      expect(overlapping.items, [1, 12]);
      expect(window.items, [1, 2]);
      expect(overlapping.packets.first, isNot(same(packet)));
      final packets = [
        for (var page = 0; page < 9; page++)
          AccountFeedPacket(
            start: page,
            end: page + 1,
            items: List.generate(30, (i) => page * 30 + i),
          ),
      ];
      final appended = AccountFeedWindow(packets: packets).withPage(
        incoming: [270, 271],
        start: 9,
        end: 10,
        prepend: false,
        identity: (id) => id,
        merge: (_, id) => id,
        estimate: (_) => 64,
      );
      for (var i = 0; i < packets.length; i++) {
        expect(appended.packets[i], same(packets[i]));
        expect(appended.packets[i].items, same(packets[i].items));
      }
    },
  );

  test('account feed eviction reuses byte estimates for unchanged rows', () {
    final window = AccountFeedWindow<int>(
      packets: [
        for (var i = 0; i < 10; i++)
          AccountFeedPacket(start: i, end: i + 1, items: [i]),
      ],
    );
    final estimates = <int, int>{};
    var identityReads = 0;
    final updated = window.withPage(
      incoming: [0, 10],
      start: 10,
      end: 12,
      prepend: false,
      identity: (id) {
        identityReads++;
        return id;
      },
      merge: (_, id) => id,
      estimate: (id) {
        estimates.update(id, (count) => count + 1, ifAbsent: () => 1);
        return id == 10 ? AccountFeedWindow.maximumEstimatedBytes : 1;
      },
    );
    expect(updated.start, 10);
    expect(updated.end, 12);
    expect(updated.items, [0, 10]);
    expect(identityReads, 12);
    expect(estimates, {for (var id = 0; id <= 10; id++) id: 1});
  });

  test('empty account feed pages advance without reading row identities', () {
    final window = AccountFeedWindow<int>(
      packets: [
        for (var i = 0; i < 10; i++)
          AccountFeedPacket(start: i, end: i + 1, items: [i]),
      ],
    );
    var reads = 0;
    final updated = window.withPage(
      incoming: const [],
      start: 10,
      end: 13,
      prepend: false,
      identity: (id) {
        reads++;
        return id;
      },
      merge: (_, id) => id,
      estimate: (_) => 1,
    );
    expect((updated.start, updated.end), (1, 13));
    expect(updated.items, [for (var i = 1; i < 10; i++) i]);
    expect(reads, 0);
  });

  test('tag intersection visits the rarest bucket regardless of tag order', () {
    final reads = _SetReads();
    final tracking = TopicTrackingState([
      for (var i = 0; i < 5000; i++)
        TrackedTopicState(
          topicId: i + 1,
          tagIds: _ReadSet({1, if (i == 0) 2}, reads),
          createdInNewPeriod: true,
        ),
    ]);
    tracking.newActivityCountsFor(tagIds: {1});
    reads.intersections = 0;
    expect(tracking.newActivityCountsFor(tagIds: {1, 2}).newTopics, 1);
    if (!baseline) expect(reads.intersections, 1);
    // ignore: avoid_print
    print('WORK tag_intersection_reads=${reads.intersections}');
    expect(tracking.newActivityCountsFor(tagIds: {2, 1}).newTopics, 1);
    expect(tracking.newActivityCountsFor(tagIds: {1, 999}).newTopics, 0);
    tracking.markRead(1, 1);
    expect(tracking.newActivityCountsFor(tagIds: {1, 2}).newTopics, 0);
  });

  test('sidebar name sort normalizes each input once', () {
    final reads = _CategoryReads();
    final categories = [
      for (var i = 0; i < 1000; i++) _CountedCategory(i, reads),
    ]..shuffle(Random(42));
    final sorted = orderedSidebarCategories(
      categories,
      fixedCategoryPositions: false,
    );
    final nameReads = reads.names;
    expect(sorted, hasLength(1000));
    if (!baseline) expect(nameReads, 1000);
    // ignore: avoid_print
    print('WORK sidebar_name_reads=$nameReads');
  });

  test('sidebar name sort keeps case ties and duplicate IDs ordered', () {
    final categories = [
      for (final (id, name) in [
        (1, 'beta'),
        (2, 'Alpha'),
        (3, 'alpha'),
        (1, 'Zulu'),
      ])
        TopicCategory(id: id, name: name, color: '123456'),
    ];
    expect(
      orderedSidebarCategories(
        categories,
        fixedCategoryPositions: false,
      ).map((c) => c.name),
      ['Alpha', 'alpha', 'beta'],
    );
    expect(
      orderedSidebarCategories(
        categories.take(3).toList(),
        fixedCategoryPositions: true,
      ).map((c) => c.id),
      [1, 2, 3],
    );
  });

  test('lazy code discovery preserves emoji and code boundaries', () {
    for (final (source, codes) in <(String, List<String>)>[
      ('plain `code` and more', []),
      ('`literal :smile:` :wave:', [':wave:']),
      ('word:smile: :wave:', [':wave:']),
      ('```\n:smile:\n``` :wave:', [':wave:']),
      ('\\`:smile: :wave:', [':smile:', ':wave:']),
      ('``a ` :smile:`` :wave:', [':wave:']),
    ]) {
      expect(siteEmojiShortcodeMatches(source).map((match) => match[0]), codes);
    }
  });

  test('gap reveal reads resident stream a bounded number of times', () {
    final stream = _ReadList(List.generate(10000, (i) => i));
    final gap = List.generate(20, (i) => 10000 + i);
    final topic = TopicDetail(
      id: 1,
      title: 'Topic',
      stream: stream,
      gapsAfter: {9999: gap},
    );
    final next = topic.withExpandedGap(
      anchorPostId: 9999,
      before: false,
      consumedIds: gap,
      revealedIds: [...gap, 10000, 1, 77777],
    );
    expect(next.stream, [...List.generate(10000, (i) => i), ...gap]);
    expect(next.gapsAfter, isEmpty);
    if (!baseline) expect(stream.reads, lessThanOrEqualTo(40000));
    // ignore: avoid_print
    print('WORK gap_stream_reads=${stream.reads}');
  });
}

class _ReadList extends ListBase<int> {
  _ReadList(this.source);
  final List<int> source;
  int reads = 0;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  int operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}

class _CategoryReads {
  int parents = 0;
  int names = 0;
}

class _CountedCategory extends TopicCategory {
  const _CountedCategory(int id, this.reads)
    : super(id: id, name: 'Category $id', color: '123456');
  final _CategoryReads reads;
  @override
  String get name {
    reads.names++;
    return super.name;
  }

  @override
  int? get parentCategoryId {
    reads.parents++;
    return null;
  }
}

class _SetReads {
  int intersections = 0;
}

class _ReadSet extends SetBase<int> {
  _ReadSet(this.source, this.reads);
  final Set<int> source;
  final _SetReads reads;
  @override
  bool containsAll(Iterable<Object?> other) {
    reads.intersections++;
    return super.containsAll(other);
  }

  @override
  bool contains(Object? value) => source.contains(value);
  @override
  int? lookup(Object? value) => source.lookup(value);
  @override
  Iterator<int> get iterator => source.iterator;
  @override
  int get length => source.length;
  @override
  Set<int> toSet() => source.toSet();
  @override
  bool add(int value) => throw UnsupportedError('read only');
  @override
  bool remove(Object? value) => throw UnsupportedError('read only');
}
