import 'package:discourse_native/src/models/notification.dart';
import 'package:flutter_test/flutter_test.dart';

/// One notification off the wire, with only the keys a case cares about.
DiscourseNotification parse(
  NotificationKind kind, {
  int? topicId,
  String? slug,
  int? postNumber,
  Map<String, dynamic> data = const {},
}) {
  return DiscourseNotification.fromJson({
    'id': 1,
    'notification_type': kind.id,
    'read': false,
    'topic_id': topicId,
    'slug': slug,
    'post_number': postNumber,
    'data': data,
  });
}

void main() {
  group('where a notification points', () {
    test('at the post it is about', () {
      expect(
        parse(
          NotificationKind.replied,
          topicId: 12,
          slug: 'better-image-handling',
          postNumber: 4,
        ).path,
        '/t/better-image-handling/12/4',
      );
    });

    test('at the topic, when it is about the first post', () {
      // Discourse leaves the number off post one, and stands `topic` in for a
      // slug it does not have.
      expect(
        parse(
          NotificationKind.liked,
          topicId: 12,
          slug: 'a-topic',
          postNumber: 1,
        ).path,
        '/t/a-topic/12',
      );
      expect(parse(NotificationKind.liked, topicId: 12).path, '/t/topic/12');
    });

    test('at the badge that was granted', () {
      expect(
        parse(
          NotificationKind.grantedBadge,
          data: const {
            'badge_id': 24,
            'badge_slug': 'nice-reply',
            'badge_name': 'Nice Reply',
            'username': 'JoffreyJ',
          },
        ).path,
        '/badges/24/nice-reply?username=joffreyj',
      );
    });

    test('at a badge whose payload carries no slug', () {
      expect(
        parse(
          NotificationKind.grantedBadge,
          data: const {'badge_id': 24, 'badge_name': 'Nice Reply!'},
        ).path,
        '/badges/24/nice-reply-',
      );
    });

    test('fallback badge slugs preserve the ASCII replacement grammar', () {
      expect(
        parse(
          NotificationKind.grantedBadge,
          data: const {'badge_id': 24, 'badge_name': ' Nice__Réply!! 2 '},
        ).path,
        '/badges/24/-nice__r-ply-2-',
      );
    });

    test('fallback badge slugs collapse an oversized malformed run', () {
      final name = '${'!' * 100000}Nice${'?' * 100000}';

      expect(
        parse(
          NotificationKind.grantedBadge,
          data: {'badge_id': 24, 'badge_name': name},
        ).path,
        '/badges/24/-nice-',
      );
    });

    test('at the group, the inbox or the dashboard', () {
      expect(
        parse(
          NotificationKind.membershipRequestAccepted,
          data: const {'group_name': 'support'},
        ).path,
        '/g/support',
      );
      expect(
        parse(
          NotificationKind.groupMessageSummary,
          data: const {
            'username': 'joffreyj',
            'group_name': 'support',
            'inbox_count': 3,
          },
        ).path,
        '/u/joffreyj/messages/group/support',
      );
      expect(parse(NotificationKind.adminProblems).path, '/admin');
      expect(parse(NotificationKind.newFeatures).path, '/admin/whats-new');
    });

    test("at the signed-in user's own page, without knowing who that is", () {
      // `/my/...` is Discourse's own redirect for exactly this: the payload
      // never says whose notifications these are.
      expect(
        parse(
          NotificationKind.likedConsolidated,
          data: const {'username': 'david', 'count': 5},
        ).path,
        '/my/notifications/likes-received?acting_username=david',
      );
    });

    test('at a chat message', () {
      expect(
        parse(
          NotificationKind.chatMention,
          data: const {'chat_channel_id': 9, 'chat_message_id': 44},
        ).path,
        '/chat/c/-/9/44',
      );
    });

    test('at the thread, and at its reply only when the kind requires it', () {
      const data = {
        'chat_channel_id': 9,
        'chat_thread_id': 3,
        'chat_message_id': 44,
      };

      expect(
        parse(NotificationKind.chatMention, data: data).path,
        '/chat/c/-/9/t/3',
      );
      expect(
        parse(NotificationKind.chatWatchedThread, data: data).path,
        '/chat/c/-/9/t/3/44',
      );
    });

    test('a quoted chat message follows the topic post quoting it', () {
      expect(
        parse(
          NotificationKind.chatQuoted,
          topicId: 12,
          slug: 'chat-transcript',
          postNumber: 4,
          // Chat metadata must not take precedence over the post containing
          // the quote.
          data: const {'chat_channel_id': 9, 'chat_message_id': 44},
        ).path,
        '/t/chat-transcript/12/4',
      );
    });

    test('at what a reminder was set on, when it is not a post', () {
      expect(
        parse(
          NotificationKind.bookmarkReminder,
          data: const {'bookmarkable_url': '/chat/c/-/9/44'},
        ).path,
        '/chat/c/-/9/44',
      );
    });

    test('at the group inbox a message arrived in', () {
      expect(
        parse(
          NotificationKind.privateMessage,
          data: const {
            'group_id': 4,
            'group_name': 'support',
            'username': 'joffreyj',
          },
        ).path,
        // The inbox lives under `/messages/group/…` — the same shape the
        // `groupMessageSummary` case builds, and the one Discourse's own
        // router matches.
        '/u/joffreyj/messages/group/support',
      );
    });

    test('at nothing, when the payload gave us nothing to go on', () {
      expect(parse(NotificationKind.grantedBadge).path, isNull);
      expect(parse(NotificationKind.unknown).path, isNull);
    });
  });

  group('who acted on a notification', () {
    test('reads the actor aliases emitted by Chat', () {
      expect(
        parse(
          NotificationKind.chatMention,
          data: const {'mentioned_by_username': 'sam'},
        ).actor,
        'sam',
      );
      expect(
        parse(
          NotificationKind.chatInvitation,
          data: const {'invited_by_username': 'david'},
        ).actor,
        'david',
      );
    });
  });
}
