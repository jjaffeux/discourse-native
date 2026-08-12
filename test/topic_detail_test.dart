import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

const site = 'https://meta.discourse.org';

Post post(int id, int number, {String? raw}) => Post(
  id: id,
  postNumber: number,
  username: 'sam',
  cooked: '<p>$id</p>',
  raw: raw,
);

TopicDetail detail({
  List<int> stream = const [],
  int postsCount = 0,
  bool canCreatePost = false,
}) => TopicDetail(
  id: 7,
  title: 'A real topic',
  stream: stream,
  postsCount: postsCount,
  canCreatePost: canCreatePost,
);

PluginData feature(String value) =>
    PluginData.none.withValue(_TopicFeature(value));

/// The post ids a view would draw: the stream, minus what has not arrived.
List<int> loaded(Store store, TopicDetail topic) => [
  for (final id in topic.stream)
    if (store.read<Post>(site, id) != null) id,
];

void main() {
  group('parse', () {
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
      // The posts come out separately, to be stored under their own ids.
      expect(payload.posts.map((p) => p.id), [1]);
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

    test('is false when the payload has no details, as when signed out', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A real topic',
      }, site);

      expect(payload.detail.canCreatePost, isFalse);
    });

    test('reads core suggestions and discourse-ai related topics', () {
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
      expect(recommendations.suggested.single.title, 'Suggested one');
      expect(recommendations.suggested.single.replyCount, 3);
      expect(recommendations.suggested.single.views, 42);
      expect(recommendations.suggested.single.posterAvatars, [
        '$site/letter/s/90.png',
      ]);
      expect(recommendations.related.single.title, 'Related one');
      expect(() => recommendations.suggested.clear(), throwsUnsupportedError);
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

  group('withPostId', () {
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
  });

  group('withoutPostId', () {
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

  group('merge', () {
    test('takes the refetched stream and count', () {
      final merged = detail(
        stream: [1],
        postsCount: 1,
      ).merge(detail(stream: [1, 2, 3], postsCount: 3, canCreatePost: true));

      expect(merged.stream, [1, 2, 3]);
      expect(merged.postsCount, 3);
      expect(merged.canCreatePost, isTrue);
    });

    test('keeps an id the refetch has not caught up with', () {
      // The reply made a moment ago, at the end of a long topic. A refetch can
      // answer from before it landed; taking that literally would make the post
      // vanish the instant it appeared.
      final merged = detail(
        stream: [1, 400],
        postsCount: 400,
      ).merge(detail(stream: [1], postsCount: 399));

      expect(merged.stream, [1, 400]);
    });

    test('keeps recommendations when a partial refetch omits them', () {
      const recommendations = TopicRecommendations(
        suggested: [Topic(id: 8, title: 'Suggested', slug: 'suggested')],
      );
      final held = TopicDetail(
        id: 7,
        title: 'A real topic',
        stream: const [1],
        recommendations: recommendations,
      );

      expect(held.merge(detail(stream: [1])).recommendations, recommendations);
    });

    test('takes the incoming optional-feature snapshot', () {
      final held = detail(stream: [1]).withPlugins(feature('held'));
      final incoming = detail(stream: [1]).withPlugins(feature('incoming'));

      expect(
        held.merge(incoming).plugins.get<_TopicFeature>()?.value,
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

  group('in the store', () {
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

    test('a re-read does not take back markdown already in hand', () {
      // `raw` is only sent when it was asked for, so a null in a later copy
      // means "not requested" rather than "no longer has one".
      final store = Store();
      store.put(site, post(1, 1, raw: 'the source'));
      store.put(site, post(1, 1));

      expect(store.read<Post>(site, 1)?.raw, 'the source');
    });

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

    test('the same id on two sites is two records', () {
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
