import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _parent = TopicCategory(id: 20, name: 'Parent', color: '123456');
const _child = TopicCategory(
  id: 10,
  name: 'Child',
  color: '654321',
  parentCategoryId: 20,
  readRestricted: true,
);

final class _LatencyApi extends FakeDiscourseApi {
  _LatencyApi(this.scenario)
    : super(
        feeds: const {'/latest.json': []},
        categoryList: scenario == 'warm' ? const [_child, _parent] : const [],
      );

  final String scenario;
  bool armed = false;
  final responseClock = Stopwatch();
  final enriched = Completer<void>();
  final timeline = <Map<String, Object>>[];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (!armed) return super.topicList(siteUrl: siteUrl, path: path);
    feedPaths.add(path);
    responseClock.start();
    return TopicList(
      topics: [
        for (var id = 1; id <= 30; id++)
          Topic(id: id, title: 'Topic $id', slug: 'topic-$id', categoryId: 10),
      ],
      categories: scenario == 'parent-miss' ? const [_child] : const [],
    );
  }

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    final requested = ids.toList();
    categoryIdsRequested.add(requested);
    timeline.add({
      'ids': requested,
      'phase': 'start',
      'elapsedUs': responseClock.elapsedMicroseconds,
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
    timeline.add({
      'ids': requested,
      'phase': 'finish',
      'elapsedUs': responseClock.elapsedMicroseconds,
    });
    if (scenario == 'failure') {
      enriched.complete();
      throw StateError('Modeled category failure');
    }
    final found = [
      for (final category in [_child, _parent])
        if (requested.contains(category.id)) category,
    ];
    if (requested.contains(20)) enriched.complete();
    return found;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production feed response to published rows latency workload', () async {
    const variant = String.fromEnvironment(
      'METADATA_VARIANT',
      defaultValue: 'baseline',
    );
    for (final scenario in [
      'category-parent-miss',
      'parent-miss',
      'failure',
      'warm',
    ]) {
      for (
        var sample = 0;
        sample < const int.fromEnvironment('METADATA_SAMPLES', defaultValue: 5);
        sample++
      ) {
        final api = _LatencyApi(scenario);
        final shell = ShellController(
          instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
          ownsApi: false,
        );
        try {
          await shell.load();
          await pumpEventQueue();
          await shell.loadCategories(_site);
          final published = Completer<int>();
          shell.topicFeeds.addListener(() {
            final feed = shell.topicFeeds.feedFor(_site, 'latest');
            if (feed?.loaded == true &&
                feed!.topicIds.length == 30 &&
                !published.isCompleted) {
              published.complete(api.responseClock.elapsedMicroseconds);
            }
          });
          api.armed = true;
          await shell.loadFeed('latest', force: true);
          final elapsed = await published.future;
          if (scenario != 'warm') await api.enriched.future;
          await pumpEventQueue();
          final feed = shell.topicFeeds.feedFor(_site, 'latest')!;
          expect(feed.topicIds, [for (var id = 1; id <= 30; id++) id]);
          expect(feed.error, isNull);
          for (final id in feed.topicIds) {
            expect(shell.store.read<Topic>(_site, id)?.title, 'Topic $id');
          }
          final expectedRequests = switch (scenario) {
            'category-parent-miss' => [
              [10],
              [20],
            ],
            'parent-miss' => [
              [20],
            ],
            'failure' => [
              [10],
            ],
            _ => <List<int>>[],
          };
          expect(api.categoryIdsRequested, expectedRequests);
          expect(
            api.feedPaths.where((path) => path == '/latest.json'),
            hasLength(2),
          );
          if (scenario != 'failure') {
            expect(
              shell.topicCategoryPathLabel(
                shell.categoryFor(10, siteUrl: _site)!,
                siteUrl: _site,
              ),
              'Parent › Child',
            );
          }
          debugPrint(
            'FEED_METADATA_SAMPLE ${jsonEncode({'variant': variant, 'scenario': scenario, 'sample': sample, 'responseToPublishedUs': elapsed, 'rowsConsumed': feed.topicIds.length, 'categoryRequests': api.categoryIdsRequested, 'timeline': api.timeline, 'feedError': feed.error})}',
          );
        } finally {
          shell.dispose();
        }
      }
    }
  });
}
