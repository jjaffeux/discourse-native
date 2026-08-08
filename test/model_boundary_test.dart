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
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:flutter_test/flutter_test.dart';

const siteUrl = 'https://meta.discourse.org';

void main() {
  group('malformed nested payloads', () {
    test('topic lists skip malformed records and default malformed fields', () {
      final list = TopicList.fromJson({
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
      expect(list.topics.single.posterAvatars, isEmpty);
      expect(list.moreTopicsUrl, isNull);
    });

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

    test('free-form notification and bookmark data default safely', () {
      final notification = DiscourseNotification.fromJson({
        'id': 1,
        'slug': 42,
        'data': ['not an object'],
      });
      final bookmark = Bookmark.fromJson({
        'id': 2,
        'user': ['not an object'],
      });
      final totals = NotificationTotals.fromJson({
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
      expect(notification.actor, isNull);
      expect(notification.path, isNull);
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
            {'id': 1},
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
      });
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
      expect(
        () => topics.topics.single.posterAvatars.add('avatar'),
        throwsUnsupportedError,
      );
      expect(() => detail.stream.add(2), throwsUnsupportedError);
      expect(() => config.offeredReactions.add('clap'), throwsUnsupportedError);
      expect(() => hashtag.colors.add('FFFFFF'), throwsUnsupportedError);
      expect(() => likers.likers.clear(), throwsUnsupportedError);
      expect(() => reactors.reactors.clear(), throwsUnsupportedError);
      expect(() => channels.public.clear(), throwsUnsupportedError);
    });
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
        const Topic(id: 7, title: 'A topic', slug: 'a-topic'),
      );
      final firstDetail = store.put(
        siteUrl,
        const TopicDetail(id: 7, title: 'A topic', stream: [1, 2]),
      );
      final secondTopic = store.put(
        siteUrl,
        const Topic(id: 7, title: 'A topic', slug: 'a-topic'),
      );
      final secondDetail = store.put(
        siteUrl,
        const TopicDetail(id: 7, title: 'A topic', stream: [1, 2]),
      );

      expect(secondTopic, same(firstTopic));
      expect(secondDetail, same(firstDetail));
      expect(notifications, 2);
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
