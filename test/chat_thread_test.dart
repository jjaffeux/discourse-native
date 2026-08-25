import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

const site = 'https://meta.discourse.org';

Map<String, dynamic> threadJson({bool detail = true}) => {
  'id': 22,
  'channel_id': 9,
  'status': 'open',
  'title': 'Deploy plan',
  'reply_count': 4,
  'last_message_id': 108,
  'force': false,
  'meta': {
    'message_bus_last_ids': {'thread_message_bus_last_id': 456},
  },
  if (detail) ...{
    'current_user_membership': {
      'thread_id': 22,
      'notification_level': 3,
      'last_read_message_id': 105,
      'thread_title_prompt_seen': true,
    },
    'original_message': {
      'id': 100,
      'chat_channel_id': 9,
      'message': '**Deploy?**',
      'cooked': '<p><strong>Deploy?</strong></p>',
      'excerpt': 'Deploy?',
      'created_at': '2026-08-12T10:00:00Z',
      'user': {
        'id': 2,
        'username': 'sam',
        'avatar_template': '/sam/{size}.png',
      },
    },
    'preview': {
      'last_reply_id': 108,
      'last_reply_created_at': '2026-08-12T11:00:00Z',
      'last_reply_excerpt': 'Ship it',
      'last_reply_user': {'id': 3, 'username': 'lee'},
      'participant_count': 5,
      'participant_users': [
        {'id': 2, 'username': 'sam'},
        {'id': 3, 'username': 'lee'},
      ],
    },
  },
};

void main() {
  test('reads an account thread page with tracking and embedded channels', () {
    final payload = {
      'meta': {'load_more_url': '/chat/api/me/threads?limit=10&offset=10'},
      'tracking': {
        '22': {'unread_count': 3, 'mention_count': 1},
      },
      'threads': [
        {
          ...threadJson(),
          'channel': {
            'id': 9,
            'title': 'Support',
            'chatable_type': 'Category',
            'current_user_membership': {'following': true},
          },
        },
      ],
    };

    final page = ChatThreadPage.fromJson(payload, site);

    expect(page.hasMore, isTrue);
    expect(page.threads.single.id, 22);
    expect(page.threads.single.tracking.unreadCount, 3);
    expect(page.threads.single.tracking.mentionCount, 1);
    expect(page.channels.single.title, 'Support');
    expect(page.channels.single.membership.following, isTrue);
  });

  test('reads thread detail, membership, original message, and preview', () {
    final thread = ChatThread.fromJson(threadJson(), site);

    expect(thread.id, 22);
    expect(thread.channelId, 9);
    expect(thread.messageBusLastId, 456);
    expect(thread.lastMessageId, 108);
    expect(
      thread.membership?.notificationLevel,
      ChatThreadNotificationLevel.watching,
    );
    expect(thread.membership?.lastReadMessageId, 105);
    expect(thread.membership?.threadTitlePromptSeen, isTrue);
    expect(thread.originalMessage?.id, 100);
    expect(thread.originalMessage?.author.avatarUrl, '$site/sam/90.png');
    expect(thread.preview?.lastReplyId, 108);
    expect(thread.preview?.participantCount, 5);
    expect(thread.preview?.participantUsers, hasLength(2));
  });

  test('unknown notification levels safely read as normal', () {
    expect(
      ChatThreadNotificationLevel.fromJson(99),
      ChatThreadNotificationLevel.normal,
    );
  });

  test(
    'store merge keeps detail fields absent from a later partial thread',
    () {
      final store = Store();
      final detail = store.put(site, ChatThread.fromJson(threadJson(), site));
      final partial = ChatThread.fromJson(threadJson(detail: false), site);

      final held = store.put(site, partial);

      expect(held.membership, detail.membership);
      expect(held.originalMessage, detail.originalMessage);
      expect(held.preview, detail.preview);
      expect(store.read<ChatThread>(site, 22), same(held));
    },
  );

  test(
    'membership helpers update notification and read state independently',
    () {
      const membership = ChatThreadMembership(
        threadId: 22,
        notificationLevel: ChatThreadNotificationLevel.tracking,
        lastReadMessageId: 100,
      );

      expect(
        membership
            .withNotificationLevel(ChatThreadNotificationLevel.muted)
            .lastReadMessageId,
        100,
      );
      expect(
        membership.withLastReadMessageId(108).notificationLevel,
        ChatThreadNotificationLevel.tracking,
      );
    },
  );

  test('copyWith can explicitly remove a membership', () {
    final thread = ChatThread.fromJson(threadJson(), site);

    expect(thread.copyWith(clearMembership: true).membership, isNull);
  });
}
