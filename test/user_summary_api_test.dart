import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'requests the authenticated summary endpoint and joins wire refs',
    () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode(_payload), 200);
        }),
      );
      addTearDown(api.close);

      final summary = await api.userSummary(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        clientId: 'native-client',
        username: 'Renée Reader',
      );

      expect(
        sent.url.toString(),
        'https://forum.example/u/Ren%C3%A9e%20Reader/summary.json',
      );
      expect(sent.method, 'GET');
      expect(sent.headers['User-Api-Key'], 'secret');
      expect(sent.headers['User-Api-Client-Id'], 'native-client');
      expect(summary.canSeeSummaryStats, isTrue);
      expect(summary.canSeeUserActions, isTrue);
      expect(summary.topics.single.title, 'A & B');
      expect(summary.replies.single.topic, same(summary.topics.single));
      expect(summary.links.single.topic.id, 42);
      expect(summary.badges.single.name, 'Helpful');
      expect(summary.badges.single.description, 'A kind answer');
      expect(summary.badges.single.imageUrl, '/uploads/helpful.png');
    },
  );

  test('bounds collections, skips broken references, and clamps counts', () {
    final payload = <String, dynamic>{
      'topics': [
        for (var id = 1; id <= 30; id++)
          {'id': id, 'title': 'Topic $id', 'slug': 'topic-$id'},
      ],
      'badges': [
        for (var id = 1; id <= 10; id++) {'id': id, 'name': 'Badge $id'},
      ],
      'user_summary': {
        'likes_given': -9,
        'topic_ids': [999, for (var id = 1; id <= 10; id++) id],
        'replies': [
          {'topic_id': 999, 'post_number': 2},
          for (var id = 1; id <= 10; id++)
            {'topic_id': id, 'post_number': id, 'like_count': -id},
        ],
        'badges': [
          for (var id = 1; id <= 10; id++) {'badge_id': id, 'count': id},
        ],
      },
    };

    final summary = UserSummary.fromJson(payload, 'https://forum.example');

    expect(summary.likesGiven, 0);
    // The server limit is enforced before reference resolution, so malformed
    // leading rows cannot make an oversized client-side page.
    expect(summary.topics.map((topic) => topic.id), [1, 2, 3, 4, 5]);
    expect(summary.replies.map((reply) => reply.topic.id), [1, 2, 3, 4, 5]);
    expect(summary.replies.every((reply) => reply.likeCount == 0), isTrue);
    expect(summary.badges, hasLength(UserSummary.maximumResults));
  });

  test('treats a malformed optional envelope as an empty summary', () {
    final summary = UserSummary.fromJson(const {
      'topics': 'not-a-list',
      'badges': [false, null],
      'user_summary': {
        'topic_ids': {'bad': 'shape'},
        'replies': [
          null,
          false,
          {'topic_id': 'bad'},
        ],
        'links': 12,
        'most_liked_users': [
          false,
          {'username': '  '},
        ],
      },
    }, 'https://forum.example');

    expect(summary.topics, isEmpty);
    expect(summary.replies, isEmpty);
    expect(summary.links, isEmpty);
    expect(summary.mostLikedUsers, isEmpty);
    expect(summary.showRecentTimeRead, isFalse);
  });
}

const _payload = <String, dynamic>{
  'topics': [
    {
      'id': 42,
      'title': 'A & B',
      'fancy_title': 'A &amp; B',
      'slug': 'a-and-b',
      'category_id': 7,
      'like_count': 8,
      'created_at': '2026-08-01T10:00:00.000Z',
    },
  ],
  'badges': [
    {
      'id': 5,
      'name': 'Helpful',
      'description': '<strong>A kind answer</strong>',
      'icon': 'heart',
      'image_url': '/uploads/helpful.png',
    },
  ],
  'user_summary': {
    'can_see_summary_stats': true,
    'can_see_user_actions': true,
    'likes_given': 3,
    'topic_ids': [42],
    'replies': [
      {
        'topic_id': 42,
        'post_number': 4,
        'like_count': 2,
        'created_at': '2026-08-02T10:00:00.000Z',
      },
    ],
    'links': [
      {
        'topic_id': 42,
        'post_number': 4,
        'url': 'https://example.com/article',
        'title': 'Article',
        'clicks': 11,
      },
    ],
    'badges': [
      {'badge_id': 5, 'count': 2},
    ],
  },
};
