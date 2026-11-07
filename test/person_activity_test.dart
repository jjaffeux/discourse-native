import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const site = 'https://meta.example';
Map<String, Object> action(String user, int id, {int type = 5}) => {
  'action_type': type,
  'topic_id': id,
  'post_number': 2,
  'username': user,
  'title': '$user action $id',
  'excerpt': 'Post words',
  'created_at': '2026-11-07T08:30:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'person histories paginate independently through the real API and retain likes',
    () async {
      final calls = <(String, int)>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          final query = request.url.queryParameters;
          expect(query['filter'], '4,5,1');
          expect(request.headers['User-Api-Key'], 'key');
          final user = query['username']!;
          final offset = int.parse(query['offset']!);
          calls.add((user, offset));
          return http.Response(
            jsonEncode({
              'user_actions': offset == 0
                  ? [for (var i = 0; i < 30; i++) action(user, i + 1)]
                  : [action('alice', 30, type: 1)],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final owner = AccountActivityController(
        api: api,
        credentials: FakeApiCredentialReader()..keys[site] = 'key',
        lifecycle: SiteLifecycle(),
      );
      addTearDown(owner.dispose);
      final account = instance(
        'meta.example',
      ).copyWith(user: const DiscourseUser(username: 'reader'));
      await Future.wait([
        owner.loadUserActivity(account),
        owner.loadUserActivity(account, username: 'sam'),
      ]);
      await owner.loadUserActivity(account, username: 'sam', loadMore: true);
      expect(calls, containsAll([('reader', 0), ('sam', 0), ('sam', 30)]));
      expect(owner.userActivityFor(site).items.length, 30);
      final sam = owner.userActivityFor(site, username: 'SAM');
      expect(sam.items.length, 31);
      expect(sam.items.last.isLike, isTrue);
      expect(sam.items.last.username, 'alice');
      expect(sam.items.last.createdAt, DateTime.utc(2026, 11, 7, 8, 30));
      expect(sam.hasMore, isFalse);
      expect(sam.nextOffset, 31);
    },
  );

  test(
    'retiring an account rejects an in-flight other-person response',
    () async {
      final answer = Completer<http.Response>();
      final started = Completer<void>();
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) {
          requests++;
          if (requests > 1) {
            return Future.value(
              http.Response(
                jsonEncode({
                  'user_actions': [action('new-account', 8)],
                }),
                200,
              ),
            );
          }
          started.complete();
          return answer.future;
        }),
      );
      addTearDown(api.close);
      final lifecycle = SiteLifecycle();
      final owner = AccountActivityController(
        api: api,
        credentials: FakeApiCredentialReader()..keys[site] = 'key',
        lifecycle: lifecycle,
      );
      addTearDown(owner.dispose);
      final account = instance(
        'meta.example',
      ).copyWith(user: const DiscourseUser(username: 'reader'));
      final stale = owner.loadUserActivity(account, username: 'sam');
      await started.future;
      lifecycle.invalidate(site);
      owner.forget(site);
      await owner.loadUserActivity(account, username: 'sam');
      answer.complete(
        http.Response(
          jsonEncode({
            'user_actions': [action('old-account', 9)],
          }),
          200,
        ),
      );
      await stale;
      expect(
        owner.userActivityFor(site, username: 'sam').items.single.username,
        'new-account',
      );
      expect(owner.userActivityFor(site).items, isEmpty);
    },
  );
}
