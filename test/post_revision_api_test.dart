import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'loads the latest server-generated comparison with credentials',
    () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'post_id': 42,
              'current_revision': 3,
              'previous_revision': 2,
              'current_version': 3,
              'version_count': 3,
              'body_changes': {'inline': '<p>A diff</p>'},
            }),
            200,
          );
        }),
      );

      final revision = await api.postRevision(
        siteUrl: 'https://meta.discourse.org',
        postId: 42,
        apiKey: 'the-key',
        clientId: 'native-client',
      );

      expect(sent.method, 'GET');
      expect(sent.url.path, '/posts/42/revisions/latest.json');
      expect(sent.headers['User-Api-Key'], 'the-key');
      expect(sent.headers['User-Api-Client-Id'], 'native-client');
      expect(revision.postId, 42);
      expect(revision.previousRevision, 2);
      expect(revision.bodyChanges?.inline, '<p>A diff</p>');
    },
  );

  test('uses the opaque numbered revision returned by core', () async {
    late Uri seen;
    final api = DiscourseApi(
      client: MockClient((request) async {
        seen = request.url;
        return http.Response(
          jsonEncode({
            'post_id': 42,
            'current_revision': 7,
            'current_version': 4,
            'version_count': 5,
          }),
          200,
        );
      }),
    );

    await api.postRevision(
      siteUrl: 'https://meta.discourse.org',
      postId: 42,
      revision: 7,
    );

    expect(seen.path, '/posts/42/revisions/7.json');
  });
}
