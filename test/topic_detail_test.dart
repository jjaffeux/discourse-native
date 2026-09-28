import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

const site = 'https://meta.discourse.org';

Post post(
  int id,
  int number, {
  String? raw,
  String? cooked,
  int version = 1,
  DateTime? updatedAt,
}) => Post(
  id: id,
  postNumber: number,
  username: 'sam',
  cooked: cooked ?? '<p>$id</p>',
  raw: raw,
  version: version,
  updatedAt: updatedAt,
);

TopicDetail detail({
  List<int> stream = const [],
  Map<int, List<int>> gapsBefore = const {},
  Map<int, List<int>> gapsAfter = const {},
  int postsCount = 0,
  bool canCreatePost = false,
}) => TopicDetail(
  id: 7,
  title: 'A real topic',
  stream: stream,
  gapsBefore: gapsBefore,
  gapsAfter: gapsAfter,
  postsCount: postsCount,
  canCreatePost: canCreatePost,
);

TopicDetail megaDetail({
  required List<int> stream,
  required int lastPostId,
  int postsCount = 10000,
}) => TopicDetail(
  id: 7,
  title: 'A mega topic',
  stream: stream,
  isMegaTopic: true,
  lastPostId: lastPostId,
  postsCount: postsCount,
);

PluginData feature(String value) =>
    PluginData.none.withValue(_topicFeatureKey, _TopicFeature(value));

const _topicFeatureKey = PluginDataKey<_TopicFeature>(
  owner: 'test',
  name: 'topic-feature',
);

List<int> loaded(Store store, TopicDetail topic) => [
  for (final id in topic.stream)
    if (store.read<Post>(site, id) != null) id,
];

void main() {
  group('wire parsing', () {
    test('preserves plain topic previews across model updates', () {
      final topic = Topic.fromJson(
        const {
          'id': 7,
          'title': 'A topic',
          'slug': 'a-topic',
          'excerpt': '<p>Clear <strong>topics</strong> &amp; replies</p>',
          'last_poster_username': 'sam',
        },
        const {},
        site,
      );
      expect(topic.excerpt, 'Clear topics & replies');
      expect(topic.lastPosterUsername, 'sam');
      final updated = topic
          .copyWith(title: 'Renamed')
          .withPlugins(feature('test'));
      expect(updated.excerpt, topic.excerpt);
      expect(updated.lastPosterUsername, topic.lastPosterUsername);
    });

    test('splits the payload into the topic and its posts', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
        'posts_count': 3,
        'post_stream': {
          'posts': [
            {
              'id': 1,
              'post_number': 1,
              'username': 'sam',
              'cooked': '<p>a</p>',
            },
          ],
          'stream': [1, 2, 3],
        },
      }, site);

      expect(payload.detail.stream, [1, 2, 3]);
      expect(payload.detail.postsCount, 3);
      expect(payload.detail.isMegaTopic, isFalse);
      expect(payload.posts.map((p) => p.id), [1]);
    });

    test('a mega topic holds the posts it was sent as its stream', () {
      // Past TopicView::MEGA_TOPIC_POSTS_COUNT, PostStreamSerializerMixin
      // sends no stream of ids: only a page of posts and the last post's id.
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A mega topic',
        'posts_count': 12000,
        'highest_post_number': 12040,
        'post_stream': {
          'isMegaTopic': true,
          'lastId': 90000,
          'posts': [
            {
              'id': 501,
              'post_number': 1,
              'username': 'sam',
              'cooked': '<p>a</p>',
            },
            {
              'id': 502,
              'post_number': 2,
              'username': 'sam',
              'cooked': '<p>b</p>',
            },
            {
              'id': 504,
              'post_number': 4,
              'username': 'sam',
              'cooked': '<p>d</p>',
            },
          ],
        },
      }, site);

      expect(payload.detail.isMegaTopic, isTrue);
      expect(payload.detail.stream, [501, 502, 504]);
      expect(payload.detail.lastPostId, 90000);
      expect(payload.detail.highestPostNumber, 12040);
      expect(payload.detail.postsCount, 12000);
      expect(payload.posts.map((post) => post.id), [501, 502, 504]);
    });

    test('bounds eager posts while retaining the complete paging stream', () {
      final allIds = [
        for (var id = 1; id <= TopicDetail.maximumInitialPosts + 2; id++) id,
      ];
      final payload = TopicDetail.parse({
        'id': 7,
        'title': 'A busy topic',
        'posts_count': allIds.length,
        'post_stream': {
          'posts': [
            'malformed',
            for (final id in allIds)
              {
                'id': id,
                'post_number': id,
                'username': 'sam',
                'cooked': '<p>$id</p>',
              },
          ],
          'stream': allIds,
        },
      }, site);

      expect(payload.detail.stream, allIds);
      expect(payload.posts, hasLength(TopicDetail.maximumInitialPosts));
      expect(payload.posts.map((post) => post.id), [
        for (var id = 1; id <= TopicDetail.maximumInitialPosts; id++) id,
      ]);
      expect(payload.detail.stream.skip(payload.posts.length), [21, 22]);
      expect(() => payload.posts.clear(), throwsUnsupportedError);
    });

    test('reads canCreatePost from the topic details', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
        'details': {'can_create_post': true},
      }, site);

      expect(payload.detail.canCreatePost, isTrue);
    });

    test('retains personalized topic flag actions and consumes one', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A flaggable topic',
        'details': {'can_flag_topic': true},
        'actions_summary': [
          {'id': 4, 'can_act': true},
          {'id': 8, 'count': 2, 'can_act': true},
        ],
      }, site);

      expect(payload.detail.canFlagWith(4), isTrue);
      expect(payload.detail.canFlagWith(8), isTrue);
      final flagged = payload.detail.withTopicFlag(8);
      expect(flagged.canFlagWith(4), isFalse);
      expect(flagged.canFlagWith(8), isFalse);
      expect(flagged.topicActions.last.count, 3);
      expect(flagged.topicActions.last.acted, isTrue);
    });

    test('reads the guardian reply-as-new-topic capability', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
        'details': {'can_reply_as_new_topic': true},
      }, site);

      expect(payload.detail.canReplyAsNewTopic, isTrue);
    });

    test('reads and preserves the selected-post guardian capabilities', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A moderated topic',
        'details': {'can_move_posts': true, 'can_split_merge_topic': true},
      }, site);

      expect(payload.detail.canMovePosts, isTrue);
      expect(payload.detail.canSplitMergeTopic, isTrue);
      expect(payload.detail.copyWith(closed: true).canMovePosts, isTrue);
      expect(
        payload.detail.withPlugins(PluginData.none).canSplitMergeTopic,
        isTrue,
      );
    });

    test('reads the topic map summary and details', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A mapped topic',
        'posts_count': 12,
        'reply_count': 11,
        'views': 218,
        'like_count': 9,
        'participant_count': 6,
        'word_count': 2500,
        'has_summary': true,
        'is_nested_view': true,
        'details': {
          'participants': [
            {
              'id': 3,
              'username': 'sam',
              'name': 'Sam',
              'avatar_template': '/letter/s/{size}.png',
              'post_count': 4,
            },
          ],
          'links': [
            {
              'url': 'https://discourse.org',
              'title': 'Discourse',
              'root_domain': 'discourse.org',
              'clicks': 7,
            },
          ],
        },
      }, site);

      final topic = payload.detail;
      expect(topic.postsCount, 12);
      expect(topic.replyCount, 11);
      expect(topic.views, 218);
      expect(topic.likeCount, 9);
      expect(topic.participantCount, 6);
      expect(topic.wordCount, 2500);
      expect(topic.hasSummary, isTrue);
      expect(topic.isNestedView, isTrue);
      expect(topic.participants.single.username, 'sam');
      expect(topic.participants.single.avatarUrl, '$site/letter/s/90.png');
      expect(topic.participants.single.postCount, 4);
      expect(topic.links.single.label, 'Discourse');
      expect(topic.links.single.clicks, 7);
    });

    test('keeps click counts and only visible internal post linkbacks', () {
      final parsed = Post.fromJson(const {
        'id': 1,
        'post_number': 1,
        'username': 'sam',
        'cooked': '<p>Opening</p>',
        'link_counts': [
          {
            'url': '/t/source/9',
            'title': 'Source topic',
            'internal': true,
            'reflection': true,
            'clicks': 2,
          },
          {
            'url': 'https://example.com',
            'title': 'Outbound',
            'internal': false,
            'reflection': false,
            'clicks': 9,
          },
          {'url': '/t/untitled/10', 'internal': true, 'reflection': true},
        ],
      }, site);

      expect(parsed.linkCounts, [
        const PostLinkCount(url: '/t/source/9', clicks: 2, internal: true),
        const PostLinkCount(url: 'https://example.com', clicks: 9),
      ]);
      expect(parsed.inboundLinks, [
        const PostInboundLink(
          url: '/t/source/9',
          title: 'Source topic',
          clicks: 2,
        ),
      ]);
    });

    test('retains server-provided hidden post gaps', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A filtered topic',
        'post_stream': {
          'stream': [1, 11],
          'gaps': {
            'before': {
              '11': [2, '3', 'not-an-id', -1, 2],
            },
            'after': {
              '11': [12, 13],
              'not-an-anchor': [99],
            },
          },
        },
      }, site);

      expect(payload.detail.gapsBefore, {
        11: [2, 3],
      });
      expect(payload.detail.gapsAfter, {
        11: [12, 13],
      });
      expect(
        () => payload.detail.gapsBefore[11]!.add(4),
        throwsUnsupportedError,
      );
      expect(
        () => payload.detail.gapsBefore[12] = const [4],
        throwsUnsupportedError,
      );
    });

    test('reads the personalized topic notification level from details', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
        'details': {'notification_level': 3},
      }, site);

      expect(payload.detail.notificationLevel, TopicNotificationLevel.watching);
    });

    test('reads status values and their guardian capabilities', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A moderated topic',
        'closed': true,
        'archived': true,
        'visible': false,
        'details': {
          'can_close_topic': true,
          'can_archive_topic': true,
          'can_toggle_topic_visibility': true,
        },
      }, site);

      expect(payload.detail.closed, isTrue);
      expect(payload.detail.archived, isTrue);
      expect(payload.detail.visible, isFalse);
      expect(payload.detail.hasStatusActions, isTrue);
      expect(
        payload.detail.canChangeStatus(TopicStatusProperty.closed),
        isTrue,
      );
      expect(
        payload.detail.withStatus(TopicStatusProperty.visible, true).visible,
        isTrue,
      );
    });

    test('reads and projects topic delete and recovery capabilities', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A deleted topic',
        'deleted_at': '2026-08-25T12:00:00.000Z',
        'details': {'can_delete': false, 'can_recover': true},
      }, site);

      expect(payload.detail.deletedAt, DateTime.utc(2026, 8, 25, 12));
      expect(payload.detail.canDeleteTopic, isFalse);
      expect(payload.detail.canRecoverTopic, isTrue);
      expect(payload.detail.hasStatusActions, isTrue);

      final recovered = payload.detail.afterRecovery();
      expect(recovered.deletedAt, isNull);
      expect(recovered.canDeleteTopic, isTrue);
      expect(recovered.canRecoverTopic, isFalse);
    });

    // PostDestroyer (lib/post_destroyer.rb): perform_delete trashes the topic
    // for a moderator, mark_for_deletion closes it for its author, and
    // user_recovered reopens it.
    test('projects what PostDestroyer does to a deleted topic', () {
      final at = DateTime.utc(2026, 8, 25, 13);
      TopicDetail topic({required bool moderator}) => TopicDetail.parse({
        'id': 7,
        'title': 'A topic',
        'details': {'can_delete': true, 'can_close_topic': moderator},
      }, site).detail;

      final trashed = topic(moderator: true).afterDeletion(at);
      expect(trashed.deletedAt, at);
      expect(trashed.closed, isFalse);
      expect(trashed.canDeleteTopic, isFalse);
      expect(trashed.canRecoverTopic, isTrue);

      final withdrawn = topic(moderator: false).afterDeletion(at);
      expect(withdrawn.deletedAt, isNull);
      expect(withdrawn.closed, isTrue);
      expect(withdrawn.canDeleteTopic, isTrue);
      expect(withdrawn.canRecoverTopic, isTrue);

      final reopened = withdrawn.afterRecovery();
      expect(reopened.closed, isFalse);
      expect(reopened.canRecoverTopic, isFalse);

      final stillClosed = trashed.copyWith(closed: true).afterRecovery();
      expect(stillClosed.deletedAt, isNull);
      expect(stillClosed.closed, isTrue);

      final ordinary = topic(moderator: false).copyWith(closed: true);
      expect(ordinary.afterRecovery(), same(ordinary));
    });

    test('reads and updates the current account pin preference', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A pinned topic',
        'pinned': true,
        'unpinned': false,
        'pinned_globally': true,
      }, site);

      expect(payload.detail.pinned, isTrue);
      expect(payload.detail.unpinned, isFalse);
      expect(payload.detail.pinnedGlobally, isTrue);
      expect(payload.detail.hasPinPreference, isTrue);

      final dismissed = payload.detail.withPinPreference(false);
      expect(dismissed.pinned, isFalse);
      expect(dismissed.unpinned, isTrue);
      expect(dismissed.pinnedGlobally, isTrue);
      expect(dismissed.withPinPreference(true).pinned, isTrue);
    });

    test('an ordinary topic does not invent a pin preference', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'An ordinary topic',
      }, site);

      expect(payload.detail.hasPinPreference, isFalse);
    });

    test('unknown topic notification levels safely read as normal', () {
      expect(
        TopicNotificationLevel.fromJson(99),
        TopicNotificationLevel.normal,
      );
    });

    test('withholds topic creation when the payload has no details', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
      }, site);

      expect(payload.detail.canCreatePost, isFalse);
    });

    test('core reads suggestions and ignores uninstalled sources', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
        'suggested_topics': [
          {
            'id': 8,
            'title': 'Suggested one',
            'slug': 'suggested-one',
            'reply_count': 3,
            'views': 42,
            'posters': [
              {
                'user': {'id': 1, 'avatar_template': '/letter/s/{size}.png'},
              },
            ],
          },
        ],
        'related_topics': [
          {'id': 9, 'title': 'Related one', 'slug': 'related-one'},
        ],
      }, site);

      final recommendations = payload.detail.recommendations!;
      expect(recommendations.sources.map((source) => source.id), [
        coreSuggestedTopicRecommendationSourceId,
      ]);
      final suggested = recommendations.sources.single.topics;
      expect(suggested.single.title, 'Suggested one');
      expect(suggested.single.replyCount, 3);
      expect(suggested.single.views, 42);
      expect(suggested.single.posterAvatars, ['$site/letter/s/90.png']);
      expect(
        recommendations.source(discourseAiRelatedTopicRecommendationSourceId),
        isNull,
      );
      expect(() => suggested.clear(), throwsUnsupportedError);
    });

    test('an installed plugin parses its recommendation source', () {
      final payload = TopicDetail.parse(
        const {
          'id': 7,
          'title': 'A real topic',
          'suggested_topics': [
            {'id': 8, 'title': 'Suggested one', 'slug': 'suggested-one'},
          ],
          'related_topics': [
            {'id': 9, 'title': 'Related one', 'slug': 'related-one'},
          ],
        },
        site,
        extensions: const PluginRegistry([AiSummaryPlugin()]),
        recommendationSources: const PluginRegistry([AiSummaryPlugin()]),
      );

      final recommendations = payload.detail.recommendations!;
      expect(recommendations.sources.map((source) => source.id), [
        coreSuggestedTopicRecommendationSourceId,
        discourseAiRelatedTopicRecommendationSourceId,
      ]);
      expect(
        recommendations
            .source(discourseAiRelatedTopicRecommendationSourceId)!
            .topics
            .single
            .title,
        'Related one',
      );
    });

    test('distinguishes a partial response from an empty final response', () {
      final partial = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
      }, site);
      final finalPage = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
        'suggested_topics': <Object>[],
      }, site);

      expect(partial.detail.recommendations, isNull);
      expect(finalPage.detail.recommendations, isNotNull);
      expect(finalPage.detail.recommendations!.isNotEmpty, isFalse);
    });
  });

  group('adding a post', () {
    test('extends the stream and the count, which paging does not', () {
      final topic = detail(stream: [1], postsCount: 1).withPostId(2);

      expect(topic.stream, [1, 2]);
      expect(topic.postsCount, 2);
    });

    test('keeps flags the reply does not change', () {
      expect(detail(canCreatePost: true).withPostId(2).canCreatePost, isTrue);
    });

    test('counts a post once even if it arrives again', () {
      final topic = detail(
        stream: [1],
        postsCount: 1,
      ).withPostId(2).withPostId(2);

      expect(topic.stream, [1, 2]);
      expect(topic.postsCount, 2);
    });

    test('joins a mega topic run only where the run reaches its end', () {
      final atEnd = megaDetail(
        stream: [8, 9],
        lastPostId: 9,
        postsCount: 10000,
      ).withPostId(10);

      expect(atEnd.stream, [8, 9, 10]);
      expect(atEnd.lastPostId, 10);
      expect(atEnd.postsCount, 10001);

      // The reply belongs after thousands of posts the reader has not paged
      // through, which is where paging reaches it.
      final further = megaDetail(
        stream: [1, 2],
        lastPostId: 9,
        postsCount: 10000,
      ).withPostId(10);

      expect(further.stream, [1, 2]);
      expect(further.lastPostId, 10);
      expect(further.postsCount, 10001);
    });

    test('leaves a mega topic alone for a post older than its last', () {
      // A re-read after a write to a post the reader has since left.
      final held = megaDetail(stream: [8, 9], lastPostId: 9);

      expect(held.withPostId(3), same(held));
    });
  });

  group('paging a mega topic by post number', () {
    test('a newer page follows the run it was read after', () {
      final paged = megaDetail(
        stream: [1, 2],
        lastPostId: 9,
      ).withMegaTopicPage(anchorPostId: 2, newer: true, postIds: [3, 4]);

      expect(paged.stream, [1, 2, 3, 4]);
      expect(paged.lastPostId, 9);
    });

    test('an earlier page precedes the run it was read before', () {
      final paged = megaDetail(
        stream: [5, 6],
        lastPostId: 9,
      ).withMegaTopicPage(anchorPostId: 5, newer: false, postIds: [3, 4]);

      expect(paged.stream, [3, 4, 5, 6]);
    });

    test('a page read from an end the run has left joins nothing', () {
      // A jump moved the reader's run while the page was out.
      final held = megaDetail(stream: [700, 701], lastPostId: 900);

      expect(
        held.withMegaTopicPage(anchorPostId: 2, newer: true, postIds: [3, 4]),
        same(held),
      );
      expect(
        held.withMegaTopicPage(anchorPostId: 2, newer: false, postIds: [1]),
        same(held),
      );
    });

    test('an empty newer page ends the run the reader holds', () {
      // The last post was deleted since the topic was read.
      final held = megaDetail(stream: [7, 8], lastPostId: 9);

      final ended = held.withMegaTopicPage(
        anchorPostId: 8,
        newer: true,
        postIds: const [],
        lastPostIdAtDispatch: 9,
      );

      expect(ended.stream, [7, 8]);
      expect(ended.lastPostId, 8);
    });

    test('an empty newer page answered before a new last post ends '
        'nothing', () {
      // A reload named reply 10 while the page was out; the page predates it.
      final held = megaDetail(stream: [7, 8], lastPostId: 10);

      expect(
        held.withMegaTopicPage(
          anchorPostId: 8,
          newer: true,
          postIds: const [],
          lastPostIdAtDispatch: 9,
        ),
        same(held),
      );
    });
  });

  group('removing a post', () {
    test('takes the post out of the stream and off the count', () {
      final without = detail(stream: [1, 2], postsCount: 2).withoutPostId(2);

      expect(without.stream, [1]);
      expect(without.postsCount, 1);
    });

    test('leaves a post it knows nothing about alone', () {
      final held = detail(stream: [1], postsCount: 1);

      expect(held.withoutPostId(99), same(held));
    });
  });

  group('revealing a hidden post gap', () {
    test('inserts a bounded leading chunk and retains its remainder', () {
      final hidden = [for (var id = 2; id <= 41; id++) id];
      final topic =
          detail(
            stream: const [1, 42],
            gapsBefore: {42: hidden},
            postsCount: 42,
          ).withExpandedGap(
            anchorPostId: 42,
            before: true,
            consumedIds: hidden.take(20).toList(),
            revealedIds: hidden.take(20).toList(),
          );

      expect(topic.stream, [1, ...hidden.take(20), 42]);
      expect(topic.gapsBefore[42], hidden.skip(20));
      expect(topic.postsCount, 42);
    });

    test('moves a trailing remainder after the revealed chunk', () {
      final topic =
          detail(
            stream: const [1],
            gapsAfter: const {
              1: [2, 3, 4],
            },
          ).withExpandedGap(
            anchorPostId: 1,
            before: false,
            consumedIds: const [2, 3],
            revealedIds: const [2, 3],
          );

      expect(topic.stream, [1, 2, 3]);
      expect(topic.gapsAfter, {
        3: [4],
      });
    });

    test('does not leave a missing response as an ordinary paging hole', () {
      final topic =
          detail(
            stream: const [1, 4],
            gapsBefore: const {
              4: [2, 3],
            },
          ).withExpandedGap(
            anchorPostId: 4,
            before: true,
            consumedIds: const [2, 3],
            revealedIds: const [3],
          );

      expect(topic.stream, [1, 3, 4]);
      expect(topic.gapsBefore, isEmpty);
    });
  });

  group('merging a refetched topic', () {
    test('takes the refetched stream and count', () {
      final merged = detail(
        stream: [1],
        postsCount: 1,
      ).merge(detail(stream: [1, 2, 3], postsCount: 3, canCreatePost: true));

      expect(merged.stream, [1, 2, 3]);
      expect(merged.postsCount, 3);
      expect(merged.canCreatePost, isTrue);
    });

    test('keeps an ID the refetch has not caught up with', () {
      // The reply made a moment ago, at the end of a long topic. A refetch can
      // answer from before it landed; taking that literally would make the post
      // vanish the instant it appeared.
      final merged = detail(
        stream: [1, 400],
        postsCount: 400,
      ).merge(detail(stream: [1], postsCount: 399));

      expect(merged.stream, [1, 400]);
    });

    test('drops an ID the refetch leaves out between posts it returned', () {
      // The site no longer serves post 2 to this reader. Kept, it would move
      // behind post 3 and hold the topic open with a post no read can fill.
      final merged = detail(
        stream: [1, 2, 3, 400],
        postsCount: 400,
      ).merge(detail(stream: [1, 3], postsCount: 398));

      expect(merged.stream, [1, 3, 400]);
      expect(merged.postsCount, 399);
    });

    test('keeps recommendations when a partial refetch omits them', () {
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
            topics: [Topic(id: 8, title: 'Suggested', slug: 'suggested')],
          ),
        ],
      );
      const held = TopicDetail(
        id: 7,
        title: 'A real topic',
        stream: [1],
        recommendations: recommendations,
      );

      expect(held.merge(detail(stream: [1])).recommendations, recommendations);
    });

    test('does not append an expanded gap at the end on refetch', () {
      final held = detail(stream: const [1, 2, 3, 4], postsCount: 4);
      final incoming = detail(
        stream: const [1, 4],
        gapsBefore: const {
          4: [2, 3],
        },
        postsCount: 4,
      );

      final merged = held.merge(incoming);

      expect(merged.stream, [1, 4]);
      expect(merged.gapsBefore[4], [2, 3]);
    });

    test('a mega topic joins a read that overlaps the run it holds', () {
      final held = megaDetail(stream: [1, 2, 3, 4, 5, 6], lastPostId: 90);

      expect(
        held.merge(megaDetail(stream: [4, 5, 6, 7, 8], lastPostId: 91)).stream,
        [1, 2, 3, 4, 5, 6, 7, 8],
      );
      final reread = held.merge(
        megaDetail(stream: [1, 3], lastPostId: 91, postsCount: 10400),
      );
      // Post 2 is gone from between posts the read returned; the posts after
      // the read's page are still the reader's.
      expect(reread.stream, [1, 3, 4, 5, 6]);
      expect(reread.lastPostId, 91);
      expect(reread.postsCount, 10400);
    });

    test('a mega topic keeps its run over a read of another part of it', () {
      // The opening page a live reload reads, while the reader is further in.
      final held = megaDetail(stream: [5000, 5001], lastPostId: 90);

      final merged = held.merge(
        megaDetail(stream: [1, 2], lastPostId: 91, postsCount: 10401),
      );

      expect(merged.stream, [5000, 5001]);
      expect(merged.lastPostId, 91);
      expect(merged.postsCount, 10401);
    });

    test('takes the incoming optional-feature snapshot', () {
      final held = detail(stream: [1]).withPlugins(feature('held'));
      final incoming = detail(stream: [1]).withPlugins(feature('incoming'));

      expect(
        held.merge(incoming).plugins.get(_topicFeatureKey)?.value,
        'incoming',
      );
    });
  });

  group('topic plugin data', () {
    test('survives ordinary copies and can be explicitly cleared', () {
      final plugins = feature('assigned');
      final row = Topic(
        id: 7,
        title: 'A topic',
        slug: 'a-topic',
        plugins: plugins,
      );
      final detailWithFeature = detail().withPlugins(plugins);

      expect(row.copyWith(title: 'Renamed').plugins, plugins);
      expect(detailWithFeature.copyWith(title: 'Renamed').plugins, plugins);
      expect(row.withPlugins(PluginData.none).plugins, PluginData.none);
      expect(
        detailWithFeature.withPlugins(PluginData.none).plugins,
        PluginData.none,
      );
    });

    test('participates in topic and detail value semantics', () {
      final plugins = feature('assigned');
      final row = Topic(
        id: 7,
        title: 'A topic',
        slug: 'a-topic',
        plugins: plugins,
      );
      final withFeature = detail().withPlugins(plugins);

      expect(row, isNot(row.withPlugins(PluginData.none)));
      expect(withFeature, isNot(detail()));
    });
  });

  group('store integration', () {
    test('a post fetched twice is one record, and one notification', () {
      final store = Store();
      final ref = store.ref<Post>(site, 1);
      var notifications = 0;
      ref.addListener(() => notifications++);

      store.put(site, post(1, 1));
      store.put(site, post(1, 1));

      expect(notifications, 1);
      expect(ref.value?.id, 1);
      expect(store.length, 1);
    });

    test('a changed post replaces the record and tells its watcher', () {
      final store = Store();
      final first = store.put(site, post(1, 1));
      final ref = store.ref<Post>(site, 1);
      var notifications = 0;
      ref.addListener(() => notifications++);

      final changed = store.put(site, post(1, 1, raw: 'new source'));

      expect(changed, isNot(same(first)));
      expect(changed.raw, 'new source');
      expect(notifications, 1);
    });

    test('a re-read of the same revision keeps markdown already in hand', () {
      // `raw` is only sent when it was asked for, so a null in a later copy
      // means "not requested" rather than "no longer has one".
      final store = Store();
      final edited = DateTime.utc(2026, 1, 1, 12);
      store.put(
        site,
        post(1, 1, raw: 'the source', version: 2, updatedAt: edited),
      );
      store.put(site, post(1, 1, version: 2, updatedAt: edited));

      expect(store.read<Post>(site, 1)?.raw, 'the source');
    });

    test('a re-read of a newer revision drops markdown from the older one', () {
      final store = Store();
      store.put(
        site,
        post(
          1,
          1,
          raw: 'the source',
          version: 1,
          updatedAt: DateTime.utc(2026, 1, 1, 12),
        ),
      );
      store.put(
        site,
        post(
          1,
          1,
          cooked: '<p>moderated</p>',
          version: 2,
          updatedAt: DateTime.utc(2026, 1, 1, 13),
        ),
      );

      final held = store.read<Post>(site, 1)!;
      expect(held.cooked, '<p>moderated</p>');
      expect(held.raw, isNull);
    });

    test(
      'a re-read after an edit inside the grace period drops markdown too',
      () {
        // Discourse folds an edit made inside the grace period into the current
        // version, so only `updated_at` says the source changed.
        final store = Store();
        store.put(
          site,
          post(
            1,
            1,
            raw: 'the source',
            updatedAt: DateTime.utc(2026, 1, 1, 12),
          ),
        );
        store.put(
          site,
          post(
            1,
            1,
            cooked: '<p>typo fixed</p>',
            updatedAt: DateTime.utc(2026, 1, 1, 12, 3),
          ),
        );

        expect(store.read<Post>(site, 1)?.raw, isNull);
      },
    );

    test('what the topic draws is the stream, minus what has not arrived', () {
      final store = Store();
      final topic = detail(stream: [1, 2, 3], postsCount: 3);
      store.putAll(site, [post(1, 1), post(3, 3)]);

      expect(loaded(store, topic), [1, 3]);
    });

    test('a removed post stops being drawn and tells its watchers', () {
      final store = Store();
      store.put(site, post(1, 1));
      final ref = store.ref<Post>(site, 1);
      var notifications = 0;
      ref.addListener(() => notifications++);

      store.remove<Post>(site, 1);

      expect(notifications, 1);
      expect(ref.value, isNull);
    });

    test('the same ID on two sites is two records', () {
      final store = Store();
      store.put(site, post(1, 1, raw: 'here'));
      store.put('https://other.example', post(1, 1, raw: 'there'));

      expect(store.read<Post>(site, 1)?.raw, 'here');
      expect(store.read<Post>('https://other.example', 1)?.raw, 'there');
    });

    test('disconnecting a site empties what was watching it', () {
      final store = Store();
      store.put(site, post(1, 1));
      final ref = store.ref<Post>(site, 1);

      store.forget(site);

      expect(ref.value, isNull);
      expect(store.length, 0);
    });

    test('update leaves a record it does not hold alone', () {
      final store = Store();

      store.update<Post>(site, 99, (held) => held.withRaw('invented'));

      expect(store.read<Post>(site, 99), isNull);
    });
  });
}

class _TopicFeature {
  const _TopicFeature(this.value);

  final String value;
}
