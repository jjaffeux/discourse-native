import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'hydrates a private topic by ID with credentials and its site prefix',
    () async {
      final requests = <http.Request>[];
      final api = DiscourseApi(
        models: const DiscourseModelCodec(
          extensions: PluginRegistry([AssignPlugin()]),
        ),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'id': 12,
              'title': 'Current title',
              'slug': 'current-title',
              'category_id': 7,
              'archetype': 'private_message',
              'last_read_post_number': 3,
              'highest_post_number': 8,
              'posts_count': 8,
              'assigned_to_user': {'id': 11, 'username': 'assigned'},
              'last_posted_at': '2026-10-16T10:30:00Z',
              'details': {
                'notification_level': 0,
                'created_by': {
                  'id': 7,
                  'username': 'creator',
                  'avatar_template': '/creator/{size}.png',
                },
                'last_poster': {
                  'id': 9,
                  'username': 'latest',
                  'avatar_template': '/latest/{size}.png',
                },
                'participants': [
                  for (var id = 1; id <= 30; id++)
                    {
                      'id': id,
                      'username': 'user-$id',
                      'avatar_template': '/user-$id/{size}.png',
                    },
                ],
              },
              'post_stream': {'stream': 'unused', 'posts': 'unused'},
            }),
            200,
          );
        }),
      );
      final topic = await api.topicSummary(
        siteUrl: 'https://forum.example/community',
        id: 12,
        apiKey: 'key',
        clientId: 'client',
      );
      expect(
        requests.single.url,
        Uri.parse('https://forum.example/community/t/12.json'),
      );
      expect(requests.single.headers['user-api-key'], 'key');
      expect(requests.single.headers['user-api-client-id'], 'client');
      expect(topic.id, 12);
      expect(topic.slug, 'current-title');
      expect(topic.privateMessage, isTrue);
      expect(topic.categoryId, 7);
      expect(topic.lastReadPostNumber, 3);
      expect(topic.highestPostNumber, 8);
      expect(topic.bumpedAt, DateTime.utc(2026, 10, 16, 10, 30));
      expect(topic.lastPosterUsername, 'latest');
      expect(topic.lastPosterAvatarUrl, 'https://forum.example/latest/90.png');
      expect(topic.posterAvatars, hasLength(5));
      expect(topic.posterAvatars.first, 'https://forum.example/creator/90.png');
      expect(topic.posters.singleWhere((poster) => poster.latest).userId, 9);
      expect(topic.muted, isTrue);
      expect(
        topic.plugins.get(assignmentsDataKey)?.direct?.assignee,
        const AssignmentAssignee.user(id: 11, username: 'assigned'),
      );
    },
  );

  test('rejects an unrelated topic response before cache hydration', () async {
    final api = DiscourseApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'id': 13, 'title': 'Wrong topic', 'slug': 'wrong'}),
          200,
        ),
      ),
    );
    await expectLater(
      api.topicSummary(siteUrl: 'https://forum.example', id: 12),
      throwsFormatException,
    );
  });

  for (final level in [0, 1, 2, 3]) {
    test('hydrates unread counts using notification level $level', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'id': 12,
              'title': 'Topic',
              'slug': 'topic',
              'last_read_post_number': 3,
              'highest_post_number': 8,
              'details': {'notification_level': level},
            }),
            200,
          ),
        ),
      );
      final topic = await api.topicSummary(
        siteUrl: 'https://forum.example',
        id: 12,
      );
      expect(topic.unreadPosts, level >= 2 ? 5 : 0);
      expect(topic.newPosts, level >= 2 ? 5 : 0);
    });
  }

  for (final lastRead in [null, 10]) {
    test('does not infer unread posts when last read is $lastRead', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'id': 12,
              'title': 'Topic',
              'slug': 'topic',
              'last_read_post_number': ?lastRead,
              'highest_post_number': 8,
              'details': {'notification_level': 2},
            }),
            200,
          ),
        ),
      );
      final topic = await api.topicSummary(
        siteUrl: 'https://forum.example',
        id: 12,
      );
      expect(topic.unreadPosts, 0);
      expect(topic.newPosts, 0);
    });
  }

  test(
    'preserves the transport permission failure for inaccessible topics',
    () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'errors': ['Access denied'],
              'error_type': 'invalid_access',
            }),
            403,
          ),
        ),
      );
      await expectLater(
        api.topicSummary(
          siteUrl: 'https://forum.example',
          id: 12,
          apiKey: 'key',
        ),
        throwsA(
          isA<SiteLookupException>().having(
            (error) => error.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    },
  );

  test('rejects invalid topic IDs without issuing a request', () async {
    var requests = 0;
    final api = DiscourseApi(
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      api.topicSummary(siteUrl: 'https://forum.example', id: 0),
      throwsArgumentError,
    );
    expect(requests, 0);
  });
}
