import 'dart:convert';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _child = TopicCategory(
  id: 10,
  name: 'Child',
  color: '123456',
  parentCategoryId: 20,
  readRestricted: true,
);
const _parent = TopicCategory(id: 20, name: 'Parent', color: '654321');

final class _VisibleApi extends FakeDiscourseApi {
  _VisibleApi(this.scenario, this.now)
    : super(
        feeds: {
          '/latest.json': [
            for (var id = 1; id <= 30; id++)
              Topic(
                id: id,
                title: 'Visible topic $id',
                slug: 'topic-$id',
                categoryId: 10,
              ),
          ],
        },
        feedCategoriesByPath: {
          '/latest.json': scenario == 'warm'
              ? [_child, _parent]
              : scenario == 'parent-miss'
              ? [_child]
              : [],
        },
      );

  final String scenario;
  final DateTime Function() now;
  DateTime? responseAt;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    final result = await super.topicList(siteUrl: siteUrl, path: path);
    responseAt = now();
    return result;
  }

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    categoryIdsRequested.add(ids.toList());
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (scenario == 'failure') throw StateError('Modeled category failure');
    return [
      for (final category in [_child, _parent])
        if (ids.contains(category.id)) category,
    ];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  for (final scenario in [
    'category-parent-miss',
    'parent-miss',
    'failure',
    'warm',
  ]) {
    testWidgets('response to painted rows with $scenario', (tester) async {
      const variant = String.fromEnvironment(
        'METADATA_VARIANT',
        defaultValue: 'candidate',
      );
      final api = _VisibleApi(scenario, () => tester.binding.clock.now());
      int? visibleUs;
      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org')],
        api: api,
        beforeSettle: () async {
          final row = find.byKey(const ValueKey('topic-card-1'));
          for (var frame = 0; frame < 100; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (row.evaluate().isEmpty) continue;
            final bounds = tester.getRect(row);
            expect(bounds.width, greaterThan(0));
            expect(bounds.height, greaterThan(0));
            expect(bounds.overlaps(Offset.zero & desktop), isTrue);
            visibleUs = tester.binding.clock
                .now()
                .difference(api.responseAt!)
                .inMicroseconds;
            break;
          }
          expect(visibleUs, isNotNull);
        },
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      final shell = ShellScope.read(
        tester.element(find.byType(TopicListView).first),
      );
      final feed = shell.currentFeed!;
      expect(feed.topicIds, [for (var id = 1; id <= 30; id++) id]);
      expect(feed.error, isNull);
      for (final id in feed.topicIds) {
        expect(shell.store.read<Topic>(_site, id)?.title, 'Visible topic $id');
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
      if (scenario != 'failure') {
        expect(
          shell.topicCategoryPathLabel(_child, siteUrl: _site),
          'Parent › Child',
        );
      }
      expect(tester.takeException(), isNull);
      debugPrint(
        'FEED_VISIBLE_SAMPLE ${jsonEncode({'variant': variant, 'scenario': scenario, 'responseToVisibleUs': visibleUs, 'frameStepUs': 16000, 'rowsConsumed': feed.topicIds.length, 'categoryRequests': api.categoryIdsRequested})}',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
