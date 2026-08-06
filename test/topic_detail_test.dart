import 'package:discourse_native/src/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

Post post(int id, int number) =>
    Post(id: id, postNumber: number, username: 'sam', cooked: '<p>$id</p>');

TopicDetail detail({
  List<Post> posts = const [],
  List<int> stream = const [],
  int postsCount = 0,
  bool canCreatePost = false,
}) => TopicDetail(
  id: 7,
  title: 'A real topic',
  posts: posts,
  stream: stream,
  postsCount: postsCount,
  canCreatePost: canCreatePost,
);

void main() {
  group('canCreatePost', () {
    test('is read from the topic details', () {
      final topic = TopicDetail.fromJson(const {
        'id': 7,
        'title': 'A real topic',
        'details': {'can_create_post': true},
      }, 'https://meta.discourse.org');

      expect(topic.canCreatePost, isTrue);
    });

    test('is false when the payload has no details, as when signed out', () {
      final topic = TopicDetail.fromJson(const {
        'id': 7,
        'title': 'A real topic',
      }, 'https://meta.discourse.org');

      expect(topic.canCreatePost, isFalse);
    });
  });

  group('withNewPost', () {
    test('extends the stream and the count, which paging does not', () {
      final topic = detail(
        posts: [post(1, 1)],
        stream: [1],
        postsCount: 1,
      ).withNewPost(post(2, 2));

      expect(topic.stream, [1, 2]);
      expect(topic.postsCount, 2);
      expect(topic.posts.map((p) => p.id), [1, 2]);
      // Nothing left unfetched, so no spinner at the bottom.
      expect(topic.hasMore, isFalse);
    });

    test('keeps flags the reply does not change', () {
      final topic = detail(
        canCreatePost: true,
      ).withNewPost(post(2, 2));

      expect(topic.canCreatePost, isTrue);
    });

    test('counts a post once even if it arrives again', () {
      final topic = detail(posts: [post(1, 1)], stream: [1], postsCount: 1)
          .withNewPost(post(2, 2))
          .withNewPost(post(2, 2));

      expect(topic.stream, [1, 2]);
      expect(topic.postsCount, 2);
      expect(topic.posts, hasLength(2));
    });
  });

  group('withRefreshed', () {
    test('takes the refetched stream and count', () {
      final held = detail(posts: [post(1, 1)], stream: [1], postsCount: 1);
      final fresh = detail(
        posts: [post(1, 1), post(2, 2)],
        stream: [1, 2, 3],
        postsCount: 3,
        canCreatePost: true,
      );

      final merged = held.withRefreshed(fresh);

      expect(merged.stream, [1, 2, 3]);
      expect(merged.postsCount, 3);
      expect(merged.canCreatePost, isTrue);
      expect(merged.pendingIds, [3]);
    });

    test('keeps a post the refetch did not return', () {
      // The reply that was just made, at the end of a long topic. A fetch
      // answers with the first chunk of posts plus the whole stream, so post
      // 400 comes back as an id and nothing else — replacing outright would
      // take it off the screen the moment it appeared.
      final held = detail(
        posts: [post(1, 1), post(400, 400)],
        stream: [1, 400],
        postsCount: 400,
      );
      final fresh = detail(
        posts: [post(1, 1)],
        stream: [1, 400],
        postsCount: 400,
      );

      final merged = held.withRefreshed(fresh);

      expect(merged.posts.map((p) => p.id), [1, 400]);
    });

    test('orders by post number rather than by arrival', () {
      final held = detail(posts: [post(9, 9)], stream: [9]);
      final fresh = detail(posts: [post(1, 1), post(5, 5)], stream: [1, 5, 9]);

      expect(held.withRefreshed(fresh).posts.map((p) => p.postNumber), [
        1,
        5,
        9,
      ]);
    });
  });
}
