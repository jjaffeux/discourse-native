import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/review_api.dart';
import 'package:discourse_native/src/models/reviewable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/review_fixture.dart';

const site = 'https://forum.example/discuss';

void main() {
  group('list payload', () {
    final page = ReviewablePage.fromJson(reviewListFixture());
    Reviewable item(int id) => page.items.firstWhere((item) => item.id == id);

    test('rows resolve the records side-loaded beside them', () {
      final flagged = item(77);
      expect(flagged.kind, ReviewableKind.flaggedPost);
      expect(flagged.status, ReviewableStatus.pending);
      expect(flagged.version, 2);
      expect(flagged.topicTitle, 'Dock lines');
      expect(flagged.targetCreatedBy?.username, 'spammer');
      expect(flagged.createdBy?.username, 'flagger');
      expect(flagged.cooked, '<p>Buy cheap rope here</p>');
      expect(flagged.scores.map((score) => score.title), [
        'Spam',
        'Inappropriate',
      ]);
      expect(flagged.scores.first.user?.username, 'flagger');
      expect(flagged.scores.last.status, ReviewableScoreStatus.agreed);
      expect(flagged.bundles.map((bundle) => bundle.label), ['Yes', 'No']);
      expect(flagged.actions.map((action) => action.serverAction), [
        'agree_and_keep',
        'delete_and_agree',
        'agree_and_suspend',
        'agree_and_edit',
        'delete_user',
        'disagree',
      ]);
    });

    test('queued posts and accounts read their payload', () {
      final queued = item(78);
      expect(queued.kind, ReviewableKind.queuedPost);
      expect(queued.title, 'Hello harbour');
      expect(queued.raw, 'First post body');
      expect(queued.scores.single.reasonHtml, '<p>New users need approval</p>');

      final account = item(79);
      expect(account.kind, ReviewableKind.user);
      expect(account.accountUsername, 'newbie');
      expect(account.accountEmail, 'newbie@example.com');
    });

    test('a type this app does not draw keeps its row', () {
      final chat = item(80);
      expect(chat.kind, ReviewableKind.other);
      expect(chat.type, 'Chat::ReviewableMessage');
      expect(chat.cooked, '<p>chat text</p>');
      expect(chat.actions, isEmpty);
    });

    test('paging follows the offset the site names', () {
      expect(page.nextOffset, 10);
      expect(page.total, 14);
      expect(page.unseenCount, 1);
      expect(page.types, contains('Chat::ReviewableMessage'));
      expect(
        ReviewablePage.fromJson(reviewListFixture(more: false)).nextOffset,
        isNull,
      );
    });

    test('a next page that would not advance falls back to the row count', () {
      final json = reviewListFixture();
      (json['meta'] as Map)['load_more_reviewables'] = '/review?offset=0';
      expect(ReviewablePage.fromJson(json, offset: 10).nextOffset, 14);
      (json['meta'] as Map)['load_more_reviewables'] = '/review';
      expect(ReviewablePage.fromJson(json, offset: 10).nextOffset, 14);
      for (final malformed in ['/review?offset=%FF', '/review?%FF=1', '%']) {
        (json['meta'] as Map)['load_more_reviewables'] = malformed;
        expect(
          ReviewablePage.fromJson(json, offset: 10).nextOffset,
          14,
          reason: malformed,
        );
      }
      json['reviewables'] = <Object>[];
      expect(ReviewablePage.fromJson(json, offset: 10).nextOffset, isNull);
    });
  });

  group('action routing', () {
    final actions = {
      for (final action in ReviewablePage.fromJson(
        reviewListFixture(),
      ).items.expand((item) => item.actions))
        action.id: action,
    };

    test('each action is sent, confirmed, or handed to the site', () {
      expect(
        {for (final entry in actions.entries) entry.key: entry.value.route},
        {
          '77-post-agree_and_keep': ReviewableActionRoute.perform,
          '77-post-delete_and_agree': ReviewableActionRoute.confirmDestructive,
          '77-post-agree_and_suspend': ReviewableActionRoute.browser,
          '77-post-agree_and_edit': ReviewableActionRoute.browser,
          '77-post-delete_user': ReviewableActionRoute.confirmDestructive,
          '77-post-disagree': ReviewableActionRoute.perform,
          '78-approve_post': ReviewableActionRoute.perform,
          '78-reject_post': ReviewableActionRoute.perform,
          '78-revise_and_reject_post': ReviewableActionRoute.browser,
          '79-user-approve_user': ReviewableActionRoute.perform,
          '79-user-delete_user': ReviewableActionRoute.browser,
        },
      );
    });

    test('the site\'s own question is asked for a harmless action', () {
      final action = ReviewableAction.tryParse({
        'id': '78-approve_post_closed',
        'server_action': 'approve_post_closed',
        'label': 'Approve',
        'confirm_message': 'This topic is closed. Create the post anyway?',
      })!;
      expect(action.route, ReviewableActionRoute.confirm);
    });

    test('classification is only owed where the site offers choices', () {
      final json = reviewListFixture()
        ..['extras'] = {
          'dsa_classification': {
            'community_rules': [
              {'id': 1, 'name': 'Rule'},
            ],
          },
        };
      final classified = ReviewablePage.fromJson(json).items.first.actions
          .firstWhere((action) => action.serverAction == 'delete_and_agree');
      expect(classified.route, ReviewableActionRoute.browser);
    });

    test('an action the perform route could not carry is not offered', () {
      for (final name in ['Agree', 'agree-and-keep', '../settings']) {
        expect(
          ReviewableAction.tryParse({'id': '1-x', 'server_action': name}),
          isNull,
          reason: name,
        );
      }
    });
  });

  test('detail and perform payloads', () {
    final item = reviewableFromDetailJson(reviewDetailFixture(77, version: 5))!;
    expect(item.id, 77);
    expect(item.version, 5);
    expect(item.scores, hasLength(2));
    expect(reviewableFromDetailJson(const {}), isNull);

    final result = ReviewablePerformResult.fromJson(
      reviewPerformFixture(77, updates: {78: 2}),
    );
    expect(result.success, isTrue);
    expect(result.version, 3);
    expect(result.removedIds, {77});
    expect(result.statuses, {78: ReviewableStatus.rejected});
    expect(result.unseenCount, 0);
  });

  group('requests', () {
    late List<http.Request> requests;
    late DiscourseApi raw;
    late DiscourseReviewApi api;
    var answer = http.Response('{}', 200);

    setUp(() {
      requests = [];
      answer = http.Response('{}', 200);
      raw = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return answer;
        }),
      );
      api = DiscourseReviewApi(raw);
    });
    tearDown(() => raw.close());

    test('the list sends only the filters that were chosen', () async {
      await api.list(
        siteUrl: site,
        apiKey: 'key',
        clientId: '',
        filters: const ReviewFilters(),
      );
      expect(requests.single.url.path, '/discuss/review.json');
      expect(requests.single.url.queryParameters, {'status': 'pending'});

      await api.list(
        siteUrl: site,
        apiKey: 'key',
        clientId: '',
        filters: const ReviewFilters(
          status: ReviewStatusFilter.reviewed,
          type: 'ReviewableUser',
          priority: ReviewPriorityFilter.high,
          categoryId: 5,
          username: ' sam ',
          sortOrder: ReviewSortOrder.newest,
        ),
        offset: 20,
      );
      expect(requests.last.url.queryParameters, {
        'status': 'reviewed',
        'type': 'ReviewableUser',
        'priority': 'high',
        'category_id': '5',
        'username': 'sam',
        'sort_order': 'created_at',
        'offset': '20',
      });
    });

    test('perform names the server action and the version it read', () async {
      answer = http.Response(jsonEncode(reviewPerformFixture(77)), 200);
      final result = await api.perform(
        siteUrl: site,
        apiKey: 'key',
        clientId: '',
        id: 77,
        action: 'agree_and_keep',
        version: 2,
      );
      final request = requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, '/discuss/review/77/perform/agree_and_keep');
      expect(request.url.queryParameters, {'version': '2'});
      expect(result.removedIds, {77});
    });

    test(
      'a version conflict is a conflict, with the site\'s wording',
      () async {
        answer = http.Response(
          jsonEncode({
            'errors': ['There was an update conflict.'],
          }),
          409,
        );
        await expectLater(
          api.perform(
            siteUrl: site,
            apiKey: 'key',
            clientId: '',
            id: 77,
            action: 'agree_and_keep',
            version: 2,
          ),
          throwsA(
            isA<WriteException>()
                .having((e) => e.failure, 'failure', WriteFailure.conflict)
                .having((e) => e.errors, 'errors', [
                  'There was an update conflict.',
                ]),
          ),
        );
        expect(requests, hasLength(1));
      },
    );

    test('nothing is sent for an action or id the route cannot hold', () {
      for (final action in ['Agree', 'a/b', '']) {
        expect(
          () => api.perform(
            siteUrl: site,
            apiKey: 'key',
            clientId: '',
            id: 77,
            action: action,
            version: 0,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => api.item(siteUrl: site, apiKey: 'key', clientId: '', id: 0),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
    });
  });
}
