import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final users = [
    for (var i = 1; i <= 6; i++)
      {
        'id': i,
        'username': 'user$i',
        if (i != 2) 'avatar_template': '/avatar/$i/{size}.png',
      },
  ];
  Topic topic(List<Map<String, Object>> posters, {bool muted = false}) =>
      TopicList.fromJson({
        'users': users,
        'topic_list': {
          'topics': [
            {
              'id': 1,
              'title': 'A topic',
              'slug': 'topic',
              'like_count': 19,
              if (muted) 'notification_level': 0,
              'posters': posters,
            },
          ],
        },
      }, 'https://example.com').topics.single;

  test('keeps five ordered identities, including users without pictures', () {
    final result = topic([
      for (var i = 1; i <= 6; i++)
        {
          'user_id': i,
          'description': i == 1 ? 'Original poster' : 'Frequent poster',
          if (i == 5) 'extras': 'latest',
        },
    ]);
    expect(result.posters.map((p) => p.username), [
      'user1',
      'user2',
      'user3',
      'user4',
      'user5',
    ]);
    expect(result.posters[1].avatarUrl, isNull);
    expect(result.posters.first.description, 'Original poster');
    expect(result.posters.last.latest, isTrue);
    expect(result.posters.last.single, isFalse);
    expect(result.likeCount, 19);
    expect(result.posterAvatars.length, 4);
  });

  test('starter who replies last remains first and is not duplicated', () {
    final result = topic([
      {'user_id': 1, 'extras': 'latest'},
      {'user_id': 2},
      {'user_id': 1},
    ]);
    expect(result.posters.length, 2);
    expect(result.posters.first.latest, isTrue);
  });

  test('single, muted, copying and sparse merges retain the summary', () {
    final result = topic([
      {'user_id': 1, 'extras': 'latest single'},
    ], muted: true);
    expect(result.posters.single.single, isTrue);
    expect(result.muted, isTrue);
    expect(result.copyWith(title: 'Updated').posters, result.posters);
    expect(result.withPlugins(result.plugins).posters, result.posters);
    expect(
      result.merge(const Topic(id: 1, title: 'Sparse', slug: 'sparse')).posters,
      result.posters,
    );
  });

  test('recommendations resolve nested users and poster roles', () {
    final result = Topic.fromRecommendationJson({
      'id': 1,
      'title': 'Suggested',
      'slug': 'suggested',
      'posters': [
        {
          'user': users.first,
          'description': 'Original poster',
          'extras': 'latest single',
        },
      ],
    }, 'https://example.com');
    expect(result.posters.single.username, 'user1');
    expect(
      result.posters.single.avatarUrl,
      'https://example.com/avatar/1/90.png',
    );
    expect(result.posters.single.single, isTrue);
  });
}
