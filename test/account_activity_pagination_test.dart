import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _nonObjectRows = <Object?>[null, 'malformed', [], 42, true];
const _unusableRows = <Object?>[
  ..._nonObjectRows,
  {},
  {
    'action_type': 99,
    'topic_id': 50,
    'post_number': 1,
    'title': 'Unsupported action',
  },
  {'action_type': 5, 'topic_id': 51, 'post_number': 0, 'title': 'Broken reply'},
];

Map<String, Object?> _activityRow(int topicId, {String? title}) => {
  'action_type': 4,
  'topic_id': topicId,
  'post_number': 1,
  'title': title ?? 'Topic $topicId',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('activity pagination through the account API', () {
    for (final scenario in [
      (
        name: 'one non-object slot',
        rows: <Object?>[null, for (var id = 1; id < 30; id++) _activityRow(id)],
        topicIds: [for (var id = 1; id < 30; id++) id],
      ),
      (
        name: 'mixed malformed and duplicate rows',
        rows: <Object?>[
          ..._unusableRows,
          ...List.filled(30 - _unusableRows.length, _activityRow(1)),
        ],
        topicIds: [1],
      ),
      (
        name: 'only non-object rows',
        rows: List<Object?>.generate(
          30,
          (index) => _nonObjectRows[index % _nonObjectRows.length],
        ),
        topicIds: <int>[],
      ),
      (
        name: 'all unusable rows',
        rows: List<Object?>.generate(
          30,
          (index) => _unusableRows[index % _unusableRows.length],
        ),
        topicIds: <int>[],
      ),
      (
        name: 'objects beyond the raw page cap',
        rows: <Object?>[
          null,
          for (var id = 1; id <= 30; id++) _activityRow(id),
        ],
        topicIds: [for (var id = 1; id < 30; id++) id],
      ),
    ]) {
      test('loads the next page after ${scenario.name}', () async {
        final requestedOffsets = <int>[];
        final controller = _controller({
          0: scenario.rows,
          30: [_activityRow(1, title: 'Updated topic'), _activityRow(100)],
        }, requestedOffsets);
        final connected = instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));

        await controller.loadUserActivity(connected);
        var feed = controller.userActivityFor(_siteUrl);

        expect(feed.error, isNull);
        expect(feed.nextOffset, 30);
        expect(feed.hasMore, isTrue);
        expect(feed.items.map((item) => item.topicId), scenario.topicIds);

        await controller.loadUserActivity(connected, loadMore: true);
        feed = controller.userActivityFor(_siteUrl);

        expect(feed.error, isNull);
        expect(feed.nextOffset, 32);
        expect(feed.hasMore, isFalse);
        expect(feed.items.map((item) => item.topicId), [
          ...{...scenario.topicIds, 1, 100},
        ]);
        expect(feed.items.first.title, 'Updated topic');
        expect(requestedOffsets, [0, 30]);

        await controller.loadUserActivity(connected, loadMore: true);
        expect(requestedOffsets, [0, 30]);
      });
    }

    test('stops after a short page including non-object slots', () async {
      final requestedOffsets = <int>[];
      final controller = _controller({
        0: [..._unusableRows, _activityRow(1), _activityRow(1)],
      }, requestedOffsets);
      final connected = instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'sam'));

      await controller.loadUserActivity(connected);
      final feed = controller.userActivityFor(_siteUrl);

      expect(feed.error, isNull);
      expect(feed.nextOffset, 10);
      expect(feed.hasMore, isFalse);
      expect(feed.items.single.topicId, 1);

      await controller.loadUserActivity(connected, loadMore: true);
      expect(requestedOffsets, [0]);
    });
  });
}

AccountActivityController _controller(
  Map<int, List<Object?>> pages,
  List<int> requestedOffsets,
) {
  final api = DiscourseApi(
    client: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/user_actions.json');
      expect(request.url.queryParameters['username'], 'sam');
      expect(request.url.queryParameters['filter'], '4,5');
      expect(request.url.queryParameters['limit'], '30');
      expect(request.headers['User-Api-Key'], 'key');
      final offset = int.parse(request.url.queryParameters['offset']!);
      requestedOffsets.add(offset);
      expect(pages, contains(offset));
      return http.Response(jsonEncode({'user_actions': pages[offset]}), 200);
    }),
  );
  addTearDown(api.close);
  final controller = AccountActivityController(
    api: api,
    credentials: FakeApiCredentialReader()..keys[_siteUrl] = 'key',
    lifecycle: SiteLifecycle(),
  );
  addTearDown(controller.dispose);
  return controller;
}
