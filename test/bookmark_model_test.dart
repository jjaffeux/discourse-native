import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activity bookmark parsing', () {
    test('retains target, route, and reminder metadata', () {
      final bookmark = Bookmark.fromJson(const {
        'id': 8,
        'bookmarkable_id': 44,
        'bookmarkable_type': 'Post',
        'post_number': 3,
        'name': 'Read this',
        'title': 'A topic',
        'bookmarkable_url': 'https://forum.example/t/a-topic/7/3',
        'reminder_at': '2030-01-02T03:04:05Z',
        'auto_delete_preference': 1,
        'user': {'username': 'sam'},
      });

      expect(bookmark.bookmarkableId, 44);
      expect(bookmark.coreTargetType, BookmarkTargetType.post);
      expect(bookmark.postNumber, 3);
      expect(bookmark.path, '/t/a-topic/7/3');
      expect(
        bookmark.autoDeletePreference,
        BookmarkAutoDeletePreference.whenReminderSent,
      );
      expect(bookmark.author, 'sam');
    });

    test('reads the linked post number of a user-menu row', () {
      final bookmark = Bookmark.fromJson(const {
        'id': 8,
        'bookmarkable_id': 44,
        'bookmarkable_type': 'Post',
        'linked_post_number': 3,
        'bookmarkable_url': 'https://forum.example/t/a-topic/7/3',
      });

      expect(bookmark.postNumber, 3);
    });

    test('keeps absent and malformed metadata readable', () {
      final bookmark = Bookmark.fromJson(const {
        'id': 'not-an-id',
        'bookmarkable_id': <Object>[],
        'bookmarkable_type': 2,
        'reminder_at': 'not-a-date',
        'auto_delete_preference': 999,
        'user': 'not-an-object',
      });

      expect(bookmark.id, 0);
      expect(bookmark.bookmarkableId, isNull);
      expect(bookmark.bookmarkableType, isNull);
      expect(bookmark.reminderAt, isNull);
      expect(
        bookmark.autoDeletePreference,
        BookmarkAutoDeletePreference.clearReminder,
      );
      expect(Bookmark.fromJson(const {}).path, isNull);
    });
  });

  group('bookmark value semantics', () {
    test('include mutable state in copies and equality', () {
      const bookmark = Bookmark(
        id: 8,
        bookmarkableId: 44,
        bookmarkableType: 'Post',
        postNumber: 3,
        title: 'A topic',
        name: 'Read this',
        author: 'sam',
        path: '/t/a-topic/7/3',
        reminderAt: null,
        autoDeletePreference: BookmarkAutoDeletePreference.never,
      );

      expect(
        bookmark,
        const Bookmark(
          id: 8,
          bookmarkableId: 44,
          bookmarkableType: 'Post',
          postNumber: 3,
          title: 'A topic',
          name: 'Read this',
          author: 'sam',
          path: '/t/a-topic/7/3',
          autoDeletePreference: BookmarkAutoDeletePreference.never,
        ),
      );
      expect(bookmark.copyWith(clearName: true).name, isNull);
      expect(
        bookmark.copyWith(
          reminderAt: DateTime.utc(2030),
          autoDeletePreference: BookmarkAutoDeletePreference.whenReminderSent,
        ),
        isNot(bookmark),
      );
    });
  });

  group('post bookmark projection', () {
    test('includes the target and reminder policy', () {
      final post = Post.fromJson(const {
        'id': 44,
        'post_number': 3,
        'username': 'sam',
        'cooked': '<p>Hello</p>',
        'bookmarked': true,
        'bookmark_id': 8,
        'bookmark_name': 'Read this',
        'bookmark_reminder_at': '2030-01-02T03:04:05Z',
        'bookmark_auto_delete_preference': 2,
      }, 'https://forum.example');

      expect(post.bookmark?.id, 8);
      expect(post.bookmark?.bookmarkableId, 44);
      expect(post.bookmark?.postNumber, 3);
      expect(
        post.bookmark?.autoDeletePreference,
        BookmarkAutoDeletePreference.onOwnerReply,
      );
    });

    test('does not invent metadata for an incomplete bookmarked post', () {
      expect(
        Post.fromJson(const {
          'id': 44,
          'post_number': 3,
          'username': 'sam',
          'cooked': '<p>Hello</p>',
          'bookmarked': true,
        }, 'https://forum.example').bookmark,
        isNull,
      );
    });
  });

  group('topic bookmark state', () {
    test('derives the topic bookmark and sorted post bookmarks', () {
      final payload = TopicDetail.parse(const {
        'id': 7,
        'title': 'A topic',
        'post_stream': {'stream': <int>[], 'posts': <Object>[]},
        'bookmarks': [
          {
            'id': 3,
            'bookmarkable_id': 45,
            'bookmarkable_type': 'Post',
            'post_number': 4,
          },
          {'id': 1, 'bookmarkable_id': 7, 'bookmarkable_type': 'Topic'},
          {
            'id': 2,
            'bookmarkable_id': 44,
            'bookmarkable_type': 'Post',
            'post_number': 2,
          },
        ],
      }, 'https://forum.example');

      expect(payload.detail.topicBookmark?.id, 1);
      expect(payload.detail.postBookmarks.map((bookmark) => bookmark.id), [
        2,
        3,
      ]);
      expect(payload.detail.hasBookmarks, isTrue);
      expect(payload.detail.withoutBookmarks().hasBookmarks, isFalse);
    });

    test('is preserved and replaceable in topic copies', () {
      final topic = Topic.fromJson(
        const {
          'id': 7,
          'title': 'A topic',
          'slug': 'a-topic',
          'bookmarked': true,
        },
        const {},
        'https://forum.example',
      );
      expect(topic.bookmarked, isTrue);
      expect(topic.copyWith(bookmarked: false).bookmarked, isFalse);
    });
  });

  group('bookmark preferences', () {
    test('round-trips the user auto-delete preference through JSON', () {
      const user = DiscourseUser(
        username: 'reader',
        bookmarkAutoDeletePreference:
            BookmarkAutoDeletePreference.whenReminderSent,
      );
      expect(
        DiscourseUser.fromJson(user.toJson()).bookmarkAutoDeletePreference,
        BookmarkAutoDeletePreference.whenReminderSent,
      );
    });

    test('defaults an absent user auto-delete preference', () {
      expect(
        DiscourseUser.fromJson(const {
          'username': 'old-reader',
        }).bookmarkAutoDeletePreference,
        BookmarkAutoDeletePreference.clearReminder,
      );
    });

    test('round-trips the weekend reminder site setting', () {
      final config = SiteConfig.fromSettings(const {
        'suggest_weekends_in_date_pickers': false,
      });
      final restoredConfig = SiteConfig.fromJson(config.toJson());
      expect(config.suggestWeekendsInDatePickers, isFalse);
      expect(restoredConfig.suggestWeekendsInDatePickers, isFalse);
      expect(restoredConfig, config);
      expect(restoredConfig.hashCode, config.hashCode);
    });

    test('keeps the enabled default for a malformed weekend setting', () {
      expect(
        SiteConfig.fromSettings(const {
          'suggest_weekends_in_date_pickers': 'not-a-bool',
        }).suggestWeekendsInDatePickers,
        isTrue,
      );
    });
  });
}
