import 'package:discourse_native/src/models/emoji_usage.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/perf_round_three_service_workloads.dart';

const _baseline = bool.fromEnvironment('PERF_BASELINE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'retained feed prepends keep dense row positions with and without overlaps',
    () async {
      for (final (count, overlap) in [(30, true), (300, true), (300, false)]) {
        final fixture = RoundThreeFeedFixture(count, overlap: overlap);
        try {
          await fixture.prepare();
          for (var page = 0; page < 20; page++) {
            await fixture.checkIncoming();
          }
        } finally {
          fixture.controller.dispose();
        }
      }
    },
  );

  test(
    'page publication retains removals made during a load or publication',
    () async {
      for (final gap in [false, true]) {
        for (final synchronous in [false, true]) {
          await RoundThreeTopicPageFixture(
            gap: gap,
            removals: 20,
            removeOnPublish: synchronous,
          ).check();
        }
      }
    },
  );

  test('returned posts removed during network wait remain excluded', () async {
    for (final gap in [false, true]) {
      await RoundThreeTopicPageFixture(
        gap: gap,
        removals: 20,
        removeDuringWait: true,
      ).check();
    }
  });

  test('emoji queries read each catalog name at most once', () async {
    final counts = _NameReads();
    final catalog = SiteEmojiCatalog(
      groups: [
        SiteEmojiGroup(
          id: 'counted',
          emojis: [
            for (var i = 0; i < 4000; i++) _CountedEmoji('emoji_$i', counts),
          ],
        ),
      ],
    );
    final controller = EmojiPickerController(
      siteUrl: 'https://emoji.example',
      context: CoreEmojiUsageContexts.topic,
      store: const RoundThreeEmojiPreferences(),
      loadCatalog: ({refresh = false}) async => catalog,
      loadSearchAliases: ({refresh = false}) async => const {},
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.updateQuery('warm-up');
    await RoundThreeEmojiFixture(1).settleAliases(controller);
    counts.reads = 0;
    controller.updateQuery('not-present');
    expect(controller.searchResults, isEmpty);
    if (!_baseline) expect(counts.reads, lessThanOrEqualTo(4000));
    // ignore: avoid_print
    print('WORK emoji_search_name_reads=${counts.reads}');
  });

  test(
    'emoji query tiers retain priority, cap and catalog replacement',
    () async {
      var fixture = RoundThreeEmojiFixture(4000);
      final controller = EmojiPickerController(
        siteUrl: 'https://emoji.example',
        context: CoreEmojiUsageContexts.topic,
        store: const RoundThreeEmojiPreferences(),
        loadCatalog: ({refresh = false}) async => fixture.catalog,
        loadSearchAliases: ({refresh = false}) async => fixture.aliases,
        searchDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await fixture.prepare(controller);
      fixture.checkQueries(controller);
      fixture = RoundThreeEmojiFixture(20, prefix: 'replacement');
      await controller.retry();
      await fixture.settleAliases(controller);
      fixture.checkQueries(controller);
    },
  );

  test(
    'destination bookmark loads retain account boundaries and first order',
    () async {
      for (final count in [1, 20, 500]) {
        final fixture = RoundThreeBookmarkFixture(count);
        await fixture.checkLoad();
        await fixture.checkLoad();
        final entries = fixture.store.entriesFor(
          RoundThreeBookmarkFixture.site,
          'reader',
        );
        expect(entries, hasLength(count));
        expect(() => entries.clear(), throwsUnsupportedError);
      }
    },
  );

  test('round three service workloads consume checked results', () async {
    final values = await measureRoundThreeServicePerformance();
    expect(values.values, everyElement(greaterThan(0)));
    // ignore: avoid_print
    print('ROUND_THREE_SERVICE_TIMES $values');
  });
}

final class _NameReads {
  var reads = 0;
}

class _CountedEmoji extends SiteEmoji {
  const _CountedEmoji(String name, this.counts)
    : super(name: name, url: '/emoji.png');
  final _NameReads counts;
  @override
  String get name {
    counts.reads++;
    return super.name;
  }
}
