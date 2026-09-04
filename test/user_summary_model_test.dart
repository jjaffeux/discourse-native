import 'package:discourse_native/src/models/user_summary.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';

Map<String, dynamic> _payload() => {
  'topics': [
    {
      'id': 11,
      'title': 'A plain & useful topic',
      'fancy_title': 'ignored &amp; title',
      'slug': 'useful-topic',
      'category_id': 3,
      'like_count': 8,
      'created_at': '2026-08-01T10:00:00.000Z',
    },
    {'id': 12, 'fancy_title': 'A &ldquo;reply&rdquo;', 'slug': 'a-reply'},
  ],
  'badges': [
    {
      'id': 5,
      'name': 'Helpful',
      'description': '<p>Helped <strong>people</strong></p>',
      'icon': 'heart',
    },
  ],
  'user_summary': {
    'can_see_summary_stats': true,
    'can_see_user_actions': true,
    'likes_given': 1,
    'likes_received': 2,
    'topics_entered': 3,
    'posts_read_count': 4,
    'days_visited': 5,
    'topic_count': 6,
    'post_count': 7,
    'time_read': 100000,
    'recent_time_read': 1000,
    'bookmark_count': 9,
    'topic_ids': [11],
    'replies': [
      {
        'topic_id': 12,
        'post_number': 4,
        'like_count': 3,
        'created_at': '2026-08-02T10:00:00.000Z',
      },
    ],
    'links': [
      {
        'topic_id': 11,
        'post_number': 2,
        'url': 'https://example.com/useful',
        'title': 'Useful',
        'clicks': 10,
      },
    ],
    'most_replied_to_users': [
      {
        'id': 21,
        'username': 'sam',
        'name': 'Sam',
        'count': 4,
        'avatar_template': '/user_avatar/sam/{size}.png',
      },
    ],
    'most_liked_by_users': <Object?>[],
    'most_liked_users': <Object?>[],
    'top_categories': [
      {
        'id': 3,
        'name': 'Support',
        'slug': 'support',
        'color': '08c',
        'style_type': 'icon',
        'icon': 'folder-open',
        'topic_count': 2,
        'post_count': 7,
      },
    ],
    'badges': [
      {'badge_id': 5, 'count': 2},
    ],
  },
};

void main() {
  test('joins the side-loaded summary contract into native records', () {
    final summary = UserSummary.fromJson(_payload(), _siteUrl);

    expect(summary.canSeeSummaryStats, isTrue);
    expect(summary.canSeeUserActions, isTrue);
    expect(summary.likesGiven, 1);
    expect(summary.likesReceived, 2);
    expect(summary.topicsEntered, 3);
    expect(summary.postsReadCount, 4);
    expect(summary.daysVisited, 5);
    expect(summary.topicCount, 6);
    expect(summary.postCount, 7);
    expect(summary.timeRead, 100000);
    expect(summary.recentTimeRead, 1000);
    expect(summary.showRecentTimeRead, isTrue);
    expect(summary.bookmarkCount, 9);

    expect(summary.topics.single.title, 'A plain & useful topic');
    expect(summary.replies.single.topic.title, 'A “reply”');
    expect(summary.replies.single.postNumber, 4);
    expect(summary.links.single.topic.id, 11);
    expect(summary.links.single.clicks, 10);
    expect(summary.mostRepliedToUsers.single.displayName, 'Sam');
    expect(
      summary.mostRepliedToUsers.single.avatarUrl,
      '$_siteUrl/user_avatar/sam/90.png',
    );
    expect(summary.topCategories.single.colorValue, 0xFF0088CC);
    expect(summary.topCategories.single.styleType, 'icon');
    expect(summary.topCategories.single.icon, 'folder-open');
    expect(summary.topCategories.single.emoji, isNull);
    expect(summary.badges.single.name, 'Helpful');
    expect(summary.badges.single.description, 'Helped people');
    expect(summary.badges.single.count, 2);

    expect(() => summary.topics.clear(), throwsUnsupportedError);
    expect(() => summary.replies.clear(), throwsUnsupportedError);
    expect(() => summary.links.clear(), throwsUnsupportedError);
    expect(() => summary.topCategories.clear(), throwsUnsupportedError);
    expect(() => summary.badges.clear(), throwsUnsupportedError);
  });

  test('skips dangling references and bounds every server-ranked list', () {
    final topics = [
      for (var id = 1; id <= UserSummary.maximumReferencedTopics + 2; id++)
        {'id': id, 'title': 'Topic $id', 'slug': 'topic-$id'},
    ];
    final summary = UserSummary.fromJson({
      'topics': topics,
      'user_summary': {
        'topic_ids': [
          for (var id = 1; id <= UserSummary.maximumResults + 2; id++) id,
        ],
        'replies': [
          const {'topic_id': 999, 'post_number': 1},
          for (var id = 1; id <= UserSummary.maximumResults + 2; id++)
            {'topic_id': id, 'post_number': id},
        ],
        'links': const [
          {'topic_id': 1, 'url': false},
          {'topic_id': 999, 'url': 'https://example.com'},
        ],
        'most_liked_users': [
          false,
          for (var id = 1; id <= UserSummary.maximumResults + 2; id++)
            {'id': id, 'username': 'user$id'},
        ],
      },
    }, _siteUrl);

    expect(summary.topics, hasLength(UserSummary.maximumResults));
    expect(summary.replies, hasLength(UserSummary.maximumResults - 1));
    expect(summary.links, isEmpty);
    expect(summary.mostLikedUsers, hasLength(UserSummary.maximumResults));
  });

  test('recent read time appears only when it adds information', () {
    expect(
      const UserSummary(timeRead: 30, recentTimeRead: 30).showRecentTimeRead,
      isFalse,
    );
    expect(
      const UserSummary(timeRead: 30, recentTimeRead: 0).showRecentTimeRead,
      isFalse,
    );
  });
}
