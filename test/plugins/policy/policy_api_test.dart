import 'dart:convert';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugins/policy/policies_api.dart';
import 'package:discourse_native/src/plugins/policy/policy_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const site = 'https://example.com/forum';
  test(
    'mutations use exact mounted routes, PUT JSON and credential headers',
    () async {
      final requests = <http.Request>[];
      final transport = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{"success":"OK"}', 200);
        }),
      );
      addTearDown(transport.close);
      final api = PolicyApi(transport);
      for (final action in PolicyAction.values) {
        await api.mutate(
          siteUrl: site,
          apiKey: 'key',
          clientId: 'client',
          postId: 42,
          action: action,
        );
      }
      expect(requests.map((r) => r.method), ['PUT', 'PUT']);
      expect(requests.map((r) => r.url.path), [
        '/forum/policy/accept.json',
        '/forum/policy/unaccept.json',
      ]);
      for (final request in requests) {
        expect(jsonDecode(request.body), {'post_id': 42});
        expect(request.headers['user-api-key'], 'key');
        expect(request.headers['user-api-client-id'], 'client');
      }
    },
  );
  test(
    'lists use exact offset queries and preserve raw row count including duplicates',
    () async {
      final requests = <http.Request>[];
      final transport = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'id': 9,
                  'username': 'alex',
                  'avatar_template': '/a/{size}.png',
                },
                {
                  'id': 9,
                  'username': 'alex',
                  'avatar_template': '/a/{size}.png',
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final api = PolicyApi(transport);
      for (final list in PolicyParticipantList.values) {
        final page = await api.participants(
          siteUrl: site,
          apiKey: 'key',
          clientId: 'client',
          postId: 42,
          list: list,
          offset: 25,
        );
        expect(page.receivedCount, 2);
        expect(page.users.map((u) => u.id), [9, 9]);
        expect(() => page.users.clear(), throwsUnsupportedError);
      }
      expect(requests.map((r) => r.url.path), [
        '/forum/policy/accepted.json',
        '/forum/policy/not-accepted.json',
      ]);
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.url.queryParameters, {'post_id': '42', 'offset': '25'});
        expect(request.headers['user-api-key'], 'key');
      }
    },
  );
  test(
    'read permission failures retain actual GET transport exception',
    () async {
      final transport = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            '{"errors":["Not authorized"],"error_type":"invalid_access"}',
            403,
          ),
        ),
      );
      addTearDown(transport.close);
      await expectLater(
        PolicyApi(transport).participants(
          siteUrl: site,
          apiKey: 'key',
          clientId: 'client',
          postId: 42,
          list: PolicyParticipantList.accepted,
          offset: 0,
        ),
        throwsA(
          isA<SiteLookupException>().having((e) => e.statusCode, 'status', 403),
        ),
      );
    },
  );
  test(
    'write refusal preserves localized server error and does not retry',
    () async {
      var writes = 0;
      final transport = DiscourseApi(
        client: MockClient((_) async {
          writes++;
          return http.Response(
            '{"errors":["User does not exist in group"]}',
            422,
          );
        }),
      );
      addTearDown(transport.close);
      await expectLater(
        PolicyApi(transport).mutate(
          siteUrl: site,
          apiKey: 'key',
          clientId: 'client',
          postId: 42,
          action: PolicyAction.accept,
        ),
        throwsA(
          isA<WriteException>()
              .having((e) => e.failure, 'failure', WriteFailure.validation)
              .having((e) => e.errors, 'server errors', [
                'User does not exist in group',
              ]),
        ),
      );
      expect(writes, 1);
    },
  );
  test(
    'malformed success and list payloads fail instead of granting state',
    () async {
      var payload = <String, Object?>{'success': true};
      var requests = 0;
      final transport = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(payload), 200);
        }),
      );
      addTearDown(transport.close);
      final api = PolicyApi(transport);
      await expectLater(
        api.mutate(
          siteUrl: site,
          apiKey: 'key',
          clientId: 'client',
          postId: 42,
          action: PolicyAction.accept,
        ),
        throwsA(isA<WriteException>()),
      );
      payload = {
        'users': [
          {'id': 4, 'username': 'alice'},
        ],
      };
      await expectLater(
        api.participants(
          siteUrl: site,
          apiKey: 'key',
          clientId: 'client',
          postId: 42,
          list: PolicyParticipantList.outstanding,
          offset: 0,
        ),
        throwsA(isA<WriteException>()),
      );
      expect(requests, 2);
    },
  );
  test('invalid post IDs and offsets never reach the transport', () async {
    var requests = 0;
    final transport = DiscourseApi(
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(transport.close);
    final api = PolicyApi(transport);
    await expectLater(
      api.mutate(
        siteUrl: site,
        apiKey: 'key',
        clientId: 'client',
        postId: 0,
        action: PolicyAction.revoke,
      ),
      throwsRangeError,
    );
    await expectLater(
      api.participants(
        siteUrl: site,
        apiKey: 'key',
        clientId: 'client',
        postId: 42,
        list: PolicyParticipantList.accepted,
        offset: -1,
      ),
      throwsRangeError,
    );
    expect(requests, 0);
  });
}
