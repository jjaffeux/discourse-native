import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:flutter_test/flutter_test.dart';

const site = 'https://meta.discourse.org';

/// A post payload with whatever `actions_summary` a test is describing.
Post parse(List<Map<String, Object?>>? summary) => Post.fromJson({
  'id': 1,
  'post_number': 1,
  'username': 'sam',
  'cooked': '<p>a</p>',
  'actions_summary': ?summary,
}, site);

void main() {
  group('actions_summary', () {
    test('reads the like row independently of the flags around it', () {
      final post = parse([
        {'id': 6, 'can_act': true},
        {'id': 2, 'count': 3, 'can_act': true},
        {'id': 7, 'can_act': true},
      ]);

      expect(post.likeCount, 3);
      expect(post.canLike, isTrue);
      expect(post.liked, isFalse);
      expect(post.canUnlike, isFalse);
      expect(post.canToggleLike, isTrue);
    });

    test('a like of your own comes back as one you can take away', () {
      final post = parse([
        {'id': 2, 'count': 1, 'acted': true, 'can_undo': true},
      ]);

      expect(post.likeCount, 1);
      expect(post.liked, isTrue);
      expect(post.canUnlike, isTrue);
      // Liking again is not a thing, so the site does not offer it.
      expect(post.canLike, isFalse);
      expect(post.canToggleLike, isTrue);
    });

    test('a like past the undo window is drawn but cannot be taken back', () {
      final post = parse([
        {'id': 2, 'count': 1, 'acted': true},
      ]);

      expect(post.liked, isTrue);
      expect(post.canToggleLike, isFalse);
    });

    test('a missing count is zero, which is why it is missing', () {
      // Discourse drops the key rather than sending 0 — the row is only there
      // at all because this reader may act on it.
      final post = parse([
        {'id': 2, 'can_act': true},
      ]);

      expect(post.likeCount, 0);
      expect(post.canLike, isTrue);
    });

    test('no like row means nothing to draw and nothing to do', () {
      // What a post of your own looks like, and what everyone looks like when
      // read signed out.
      expect(parse([]).canToggleLike, isFalse);
      expect(parse([]).likeCount, 0);
      expect(parse(null).canToggleLike, isFalse);
    });
  });

  group('withLike', () {
    const post = Post(
      id: 1,
      postNumber: 1,
      username: 'sam',
      cooked: '<p>a</p>',
      likeCount: 2,
      canLike: true,
    );

    test('adds the like and the permission to undo it', () {
      final liked = post.withLike(true);

      expect(liked.likeCount, 3);
      expect(liked.liked, isTrue);
      expect(liked.canLike, isFalse);
      expect(liked.canUnlike, isTrue);
      expect(liked.canToggleLike, isTrue);
    });

    test('removes the like and restores permission to like', () {
      final unliked = post.withLike(true).withLike(false);

      expect(unliked.likeCount, 2);
      expect(unliked.liked, isFalse);
      expect(unliked.canLike, isTrue);
      expect(unliked.canUnlike, isFalse);
    });

    test('never counts below zero, however stale the number was', () {
      const stale = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>a</p>',
        liked: true,
        canUnlike: true,
      );

      expect(stale.withLike(false).likeCount, 0);
    });

    test('keeps the markdown, which is not the site\'s to re-send', () {
      const withRaw = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>a</p>',
        canLike: true,
        raw: 'a',
      );

      expect(withRaw.withLike(true).raw, 'a');
    });
  });

  group('PostLikers', () {
    test('reads the accounts, absolute avatars and all', () {
      final likers = PostLikers.parse(
        const {
          'post_action_users': [
            {
              'id': 3,
              'username': 'sam',
              'name': 'Sam Saffron',
              'avatar_template': '/user_avatar/meta/sam/{size}/1_2.png',
            },
            {'id': 4, 'username': 'codinghorror'},
          ],
        },
        postId: 1,
        siteUrl: site,
      );

      expect(likers.postId, 1);
      expect(likers.likers.map((l) => l.username), ['sam', 'codinghorror']);
      expect(likers.likers.first.displayName, 'Sam Saffron');
      expect(
        likers.likers.first.avatarUrl,
        '$site/user_avatar/meta/sam/90/1_2.png',
      );
      // No `name` on a site with enable_names off, so the username is the name.
      expect(likers.likers.last.displayName, 'codinghorror');
      expect(likers.likers.last.avatarUrl, isNull);
    });

    test('an empty answer is a list nobody is on, not a failure', () {
      final likers = PostLikers.parse(const {}, postId: 1, siteUrl: site);
      expect(likers.likers, isEmpty);
    });
  });
}
