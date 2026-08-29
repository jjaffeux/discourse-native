import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_card.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';

const siteUrl = 'https://meta.discourse.org';

void main() {
  test('whole-topic edit permission includes tag editing', () {
    TopicDetail detail(Map<String, Object?> permissions) => TopicDetail.parse({
      'id': 7,
      'title': 'A topic',
      'post_stream': {
        'stream': <int>[],
        'posts': <Object?>[],
      },
      'details': permissions,
    }, siteUrl).detail;

    final editor = detail({'can_edit': true});
    expect(editor.canEdit, isTrue);
    expect(editor.canEditTags, isTrue);

    final tagEditor = detail({'can_edit_tags': true});
    expect(tagEditor.canEdit, isFalse);
    expect(tagEditor.canEditTags, isTrue);

    expect(detail(const {}).canEditTags, isFalse);
  });

  test('user cards retain plugin-owned serializer records', () {
    final enabled = UserCard.fromJson(
      const {'username': 'sam', 'can_chat_user': true},
      siteUrl,
      extensions: pluginRegistry,
    );
    final absent = UserCard.fromJson(
      const {'username': 'lee'},
      siteUrl,
      extensions: pluginRegistry,
    );

    expect(enabled.plugins.get(chatUserCardKey)?.canChat, isTrue);
    expect(absent.plugins.get(chatUserCardKey), isNull);
  });

  group('malformed nested payloads', () {
    test('topic lists skip malformed records and default malformed fields', () {
      final list = TopicList.fromJson(const {
        'users': [
          null,
          {'id': 3, 'avatar_template': 42},
        ],
        'topic_list': {
          'topics': [
            false,
            {
              'id': 7,
              'title': 'A topic',
              'slug': 42,
              'tags': [
                null,
                false,
                3,
                {'id': 1, 'name': 42},
                '   ',
              ],
              'posters': [
                'not an object',
                {'user_id': 3},
              ],
            },
          ],
          'more_topics_url': 42,
        },
      }, siteUrl);

      expect(list.topics, hasLength(1));
      expect(list.topics.single.slug, '');
      expect(list.topics.single.tags, isEmpty);
      expect(list.topics.single.posterAvatars, isEmpty);
      expect(list.moreTopicsUrl, isNull);
    });

    test('topic list pagination accepts only bounded root-relative paths', () {
      String? page(String? cursor) =>
          TopicList(topics: const [], moreTopicsUrl: cursor).nextPagePath;

      expect(page('/latest?page=2'), '/latest.json?page=2');
      expect(page('/latest.json?page=2'), '/latest.json?page=2');

      for (final cursor in [
        'latest?page=2',
        'https://other.example/latest?page=2',
        '//other.example/latest?page=2',
        '/latest?page=2#posts',
        'http://[malformed',
        '/latest?${'x' * 2048}',
      ]) {
        expect(
          page(cursor),
          isNull,
          reason: cursor.length <= 20 ? cursor : cursor.substring(0, 20),
        );
      }
    });

    test('topic list parsing is bounded to one legal server page', () {
      final rawTopics = <Object?>[
        for (var id = 1; id <= TopicList.maximumPageSize + 1; id += 1)
          {'id': id, 'title': 'Topic $id'},
      ];
      rawTopics[4] = false;

      final list = TopicList.fromJson({
        'topic_list': {'topics': rawTopics},
      }, siteUrl);

      expect(list.topics, hasLength(TopicList.maximumPageSize - 1));
      expect(list.topics.first.id, 1);
      expect(list.topics.last.id, TopicList.maximumPageSize);
      expect(list.topics.map((topic) => topic.id), isNot(contains(101)));
      expect(() => list.topics.add(list.topics.first), throwsUnsupportedError);
    });

    test(
      'topic-list avatar resolution is bounded to its legal poster table',
      () {
        final list = TopicList.fromJson({
          'users': [
            for (var id = 1; id <= TopicList.maximumUsersPerPage + 1; id += 1)
              {'id': id, 'avatar_template': '/avatars/$id/{size}.png'},
          ],
          'topic_list': const {
            'topics': [
              {
                'id': 7,
                'posters': [
                  {'user_id': TopicList.maximumUsersPerPage},
                  {'user_id': TopicList.maximumUsersPerPage + 1},
                ],
              },
            ],
          },
        }, siteUrl);

        expect(list.topics.single.posterAvatars, [
          '$siteUrl/avatars/${TopicList.maximumUsersPerPage}/90.png',
        ]);
      },
    );

    test('topic details skip malformed posts and stream ids', () {
      final payload = TopicDetail.parse({
        'id': 7,
        'details': 'not an object',
        'post_stream': {
          'stream': [1, '2', 'not an id', double.nan],
          'posts': [
            false,
            {
              'id': 1,
              'username': 42,
              'cooked': true,
              'actions_summary': 'not a list',
            },
          ],
        },
      }, siteUrl);

      expect(payload.detail.stream, [1, 2]);
      expect(payload.detail.canCreatePost, isFalse);
      expect(payload.posts, hasLength(1));
      expect(payload.posts.single.username, '');
      expect(payload.posts.single.cooked, '');
    });

    test('topic lists expose the same first-unread position as Discourse', () {
      Topic parsed({int? lastRead, required int highest}) =>
          TopicList.fromJson({
            'topic_list': {
              'topics': [
                {
                  'id': 7,
                  'last_read_post_number': lastRead,
                  'highest_post_number': highest,
                },
              ],
            },
          }, siteUrl).topics.single;

      expect(parsed(lastRead: 5, highest: 10).lastUnreadPostNumber, 6);
      expect(parsed(lastRead: 10, highest: 10).lastUnreadPostNumber, 10);
      expect(parsed(lastRead: null, highest: 10).lastUnreadPostNumber, 1);
    });

    test('topic lists preserve core topic-row state semantics', () {
      final topics = TopicList.fromJson(const {
        'topic_list': {
          'topics': [
            {
              'id': 7,
              'unread_posts': 3,
              'new_posts': 3,
              'unseen': true,
              'last_read_post_number': 2,
              'highest_post_number': 5,
            },
            {
              'id': 8,
              'is_nested_view': true,
              'has_new_replies': true,
              'unread_posts': 4,
              'unseen': true,
              'last_read_post_number': 5,
              'highest_post_number': 5,
            },
          ],
        },
      }, siteUrl).topics;

      final flat = topics.first;
      expect(flat.unreadCount, 3, reason: 'mirrored fields are not added');
      expect(flat.visited, isFalse);
      expect(flat.showUnreadCount, isTrue);
      expect(flat.showNewTopicDot, isTrue);
      expect(flat.showNewRepliesDot, isFalse);

      final nested = topics.last;
      expect(nested.visited, isTrue);
      expect(nested.showUnreadCount, isFalse);
      expect(nested.showNewTopicDot, isFalse);
      expect(nested.showNewRepliesDot, isTrue);
      expect(nested.lastUnreadPostNumber, isNull);
    });

    test('topic parsers retain only the first three resolved posters', () {
      final ordinary = Topic.fromJson(
        {
          'id': 7,
          'posters': [
            'not an object',
            const {'user_id': 999},
            for (var id = 1; id <= 5; id++) {'user_id': id},
          ],
        },
        {for (var id = 1; id <= 5; id++) id: 'avatar-$id'},
        siteUrl,
      );
      final recommendation = Topic.fromRecommendationJson({
        'id': 8,
        'posters': [
          const {'user': 'not an object'},
          const {
            'user': {'id': 999},
          },
          for (var id = 1; id <= 5; id++)
            {
              'user': {'id': id, 'avatar_template': '/avatar-$id/{size}.png'},
            },
        ],
      }, siteUrl);

      expect(ordinary.posterAvatars, ['avatar-1', 'avatar-2', 'avatar-3']);
      expect(recommendation.posterAvatars, [
        '$siteUrl/avatar-1/90.png',
        '$siteUrl/avatar-2/90.png',
        '$siteUrl/avatar-3/90.png',
      ]);
      expect(
        () => ordinary.posterAvatars.add('avatar-4'),
        throwsUnsupportedError,
      );
      expect(
        () => recommendation.posterAvatars.add('avatar-4'),
        throwsUnsupportedError,
      );
    });

    test('free-form notification and bookmark data default safely', () {
      final notification = DiscourseNotification.fromJson(const {
        'id': 1,
        'slug': 42,
        'data': ['not an object'],
      });
      final bookmark = Bookmark.fromJson(const {
        'id': 2,
        'user': ['not an object'],
      });
      final totals = NotificationTotals.fromJson(const {
        'topic_tracking': ['not an object'],
        'username': 42,
      });
      final channels = ChatChannel.parse({
        'tracking': ['not an object'],
        'public_channels': [
          false,
          {
            'id': 3,
            'title': 'Support',
            'chatable': ['not an object'],
            'current_user_membership': 'not an object',
            'last_message': 'not an object',
          },
        ],
      }, siteUrl);

      expect(notification.slug, '');
      expect(notification.typeId, const NotificationTypeId(0));
      expect(notification.data, isEmpty);
      expect(bookmark.author, isNull);
      expect(totals.topicTrackingUnread, 0);
      expect(totals.username, isNull);
      expect(channels.public.single.title, 'Support');
      expect(channels.public.single.membership, ChatMembership.none);
    });
  });

  group('immutable parsed collections', () {
    test('model collections cannot be changed through their public fields', () {
      final topics = TopicList.fromJson(const {
        'topic_list': {
          'topics': [
            {
              'id': 1,
              'tags': [
                {'id': 4, 'name': 'feature', 'slug': 'feature'},
                'legacy',
              ],
            },
          ],
        },
      }, siteUrl);
      final detail = TopicDetail.parse(const {
        'post_stream': {
          'stream': [1],
          'posts': <Object?>[],
        },
      }, siteUrl).detail;
      final config = SiteConfig.fromJson(const {
        'offeredReactions': ['heart'],
      }, extensions: pluginRegistry);
      final reactions = config.plugins.get(reactionsSettingsDataKey)!;
      final hashtag = FoundHashtag.fromJson(const {
        'type': 'category',
        'ref': 'support',
        'colors': ['0088CC'],
      })!;
      final likers = PostLikers.parse(
        const {
          'post_action_users': [
            {'id': 1, 'username': 'sam'},
          ],
        },
        postId: 1,
        siteUrl: siteUrl,
      );
      final reactors = PostReactors.parse(
        const {
          'users': [
            {'id': 1, 'username': 'sam', 'reaction': 'heart'},
          ],
        },
        postId: 1,
        siteUrl: siteUrl,
      );
      final channels = ChatChannel.parse(const {
        'public_channels': [
          {'id': 3, 'title': 'Support'},
        ],
      }, siteUrl);

      expect(() => topics.topics.clear(), throwsUnsupportedError);
      expect(topics.topics.single.tags, const [
        TopicTag(id: 4, name: 'feature', slug: 'feature'),
        TopicTag(name: 'legacy'),
      ]);
      expect(
        () => topics.topics.single.tags.add(const TopicTag(name: 'another')),
        throwsUnsupportedError,
      );
      expect(
        () => topics.topics.single.posterAvatars.add('avatar'),
        throwsUnsupportedError,
      );
      expect(() => detail.stream.add(2), throwsUnsupportedError);
      expect(
        () => reactions.offeredReactions.add('clap'),
        throwsUnsupportedError,
      );
      expect(() => hashtag.colors.add('FFFFFF'), throwsUnsupportedError);
      expect(() => likers.likers.clear(), throwsUnsupportedError);
      expect(() => reactors.reactors.clear(), throwsUnsupportedError);
      expect(() => channels.public.clear(), throwsUnsupportedError);
    });
  });

  test('bounds a nonconforming likes response to one requested page', () {
    final likers = PostLikers.parse(
      {
        'post_action_users': [
          for (var index = 0; index < PostLikers.maximumPageSize + 5; index++)
            {'id': index + 1, 'username': 'user-$index'},
        ],
      },
      postId: 7,
      siteUrl: siteUrl,
    );

    expect(likers.likers, hasLength(PostLikers.maximumPageSize));
    expect(likers.likers.first.username, 'user-0');
    expect(
      likers.likers.last.username,
      'user-${PostLikers.maximumPageSize - 1}',
    );
  });

  test('retains only a category hashtag parent and child color', () {
    final hashtag = FoundHashtag.fromJson({
      'type': 'category',
      'ref': 'parent:child',
      'colors': [
        null,
        7,
        '',
        '112233',
        'AABBCC',
        for (var index = 0; index < 20; index++) '00000$index',
      ],
    })!;

    expect(hashtag.colors, ['112233', 'AABBCC']);
    expect(hashtag.colorValues, [0xFF112233, 0xFFAABBCC]);
    expect(() => hashtag.colors.add('FFFFFF'), throwsUnsupportedError);
  });

  test('retains an unknown hashtag wire type without normalizing it', () {
    final hashtag = FoundHashtag.fromJson(const {
      'type': ' future-kind ',
      'ref': 'roadmap',
    });

    expect(hashtag, isNotNull);
    expect(hashtag!.type, ' future-kind ');
  });

  group('Store value semantics', () {
    test('unchanged topics and details retain their stored records', () {
      final store = Store();
      final topicRef = store.ref<Topic>(siteUrl, 7);
      final detailRef = store.ref<TopicDetail>(siteUrl, 7);
      var notifications = 0;
      topicRef.addListener(() => notifications++);
      detailRef.addListener(() => notifications++);

      final firstTopic = store.put(
        siteUrl,
        const Topic(
          id: 7,
          title: 'A topic',
          slug: 'a-topic',
          tags: [TopicTag(id: 4, name: 'feature', slug: 'feature')],
        ),
      );
      final firstDetail = store.put(
        siteUrl,
        const TopicDetail(id: 7, title: 'A topic', stream: [1, 2]),
      );
      final secondTopic = store.put(
        siteUrl,
        const Topic(
          id: 7,
          title: 'A topic',
          slug: 'a-topic',
          tags: [TopicTag(id: 4, name: 'feature', slug: 'feature')],
        ),
      );
      final secondDetail = store.put(
        siteUrl,
        const TopicDetail(id: 7, title: 'A topic', stream: [1, 2]),
      );

      expect(secondTopic, same(firstTopic));
      expect(secondDetail, same(firstDetail));
      expect(notifications, 2);
    });

    test('marking a topic read preserves its tags', () {
      const topic = Topic(
        id: 7,
        title: 'A topic',
        slug: 'a-topic',
        unreadPosts: 2,
        tags: [TopicTag(id: 4, name: 'feature', slug: 'feature')],
      );

      final read = topic.copyWith(markRead: true);

      expect(read.hasUnread, isFalse);
      expect(read.tags, topic.tags);
    });

    test('marking a nested topic read clears its new-replies signal', () {
      const topic = Topic(
        id: 7,
        title: 'A topic',
        slug: 'a-topic',
        isNestedView: true,
        hasNewReplies: true,
        highestPostNumber: 2,
      );

      final read = topic.copyWith(markRead: true);

      expect(read.hasNewReplies, isFalse);
      expect(read.showNewRepliesDot, isFalse);
      expect(read.visited, isTrue);
    });

    test('unchanged user and reaction lists do not wake their watchers', () {
      final store = Store();
      final user = UserCard.fromJson(const {'username': 'sam'}, siteUrl);
      final likers = PostLikers.parse(
        const {
          'post_action_users': [
            {'id': 1, 'username': 'sam'},
          ],
        },
        postId: 7,
        siteUrl: siteUrl,
      );
      final reactors = PostReactors.parse(
        const {
          'users': [
            {'id': 1, 'username': 'sam', 'reaction': 'heart'},
          ],
        },
        postId: 7,
        siteUrl: siteUrl,
      );

      store.put(siteUrl, user);
      store.put(siteUrl, likers);
      store.put(siteUrl, reactors);
      var notifications = 0;
      store.ref<UserCard>(siteUrl, 'sam').addListener(() => notifications++);
      store.ref<PostLikers>(siteUrl, 7).addListener(() => notifications++);
      store
          .ref<PostReactors>(siteUrl, PostReactors.key(7, null))
          .addListener(() => notifications++);

      expect(
        store.put(
          siteUrl,
          UserCard.fromJson(const {'username': 'sam'}, siteUrl),
        ),
        same(user),
      );
      expect(
        store.put(
          siteUrl,
          PostLikers.parse(
            const {
              'post_action_users': [
                {'id': 1, 'username': 'sam'},
              ],
            },
            postId: 7,
            siteUrl: siteUrl,
          ),
        ),
        same(likers),
      );
      expect(
        store.put(
          siteUrl,
          PostReactors.parse(
            const {
              'users': [
                {'id': 1, 'username': 'sam', 'reaction': 'heart'},
              ],
            },
            postId: 7,
            siteUrl: siteUrl,
          ),
        ),
        same(reactors),
      );
      expect(notifications, 0);
    });

    test('unchanged chat channels retain the sidebar row record', () {
      final store = Store();
      ChatChannel channel() => ChatChannel.fromJson(
        const {
          'id': 3,
          'title': 'Support',
          'chatable_type': 'Category',
          'chatable': {'color': '0088CC'},
          'current_user_membership': {
            'following': true,
            'last_read_message_id': 7,
          },
        },
        siteUrl,
        tracking: const ChatTracking(unreadCount: 2),
      );

      final first = store.put(siteUrl, channel());
      final ref = store.ref<ChatChannel>(siteUrl, 3);
      var notifications = 0;
      ref.addListener(() => notifications++);

      final second = store.put(siteUrl, channel());

      expect(second, same(first));
      expect(notifications, 0);
    });
  });
}
