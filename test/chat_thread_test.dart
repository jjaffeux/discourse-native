import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_list_refresh.dart';
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
  group('wire parsing', () {
    test(
      'reads an account thread page with tracking and embedded channels',
      () {
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
      },
    );

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

    test('unknown thread notification levels safely read as normal', () {
      expect(
        ChatThreadNotificationLevel.fromJson(99),
        ChatThreadNotificationLevel.normal,
      );
    });
  });

  group('value semantics', () {
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

    test('store merge accepts an explicit zero tracking but keeps tracking a '
        'detail payload omits', () {
      ChatThreadPage page(Map<String, dynamic> tracking) =>
          ChatThreadPage.fromJson({
            'threads': [threadJson(detail: false)],
            'tracking': tracking,
          }, site);
      final store = Store()
        ..put(site, ChatThread.fromJson(threadJson(), site))
        ..putAll(
          site,
          page({
            '22': {'unread_count': 2, 'mention_count': 1},
          }).threads,
        );

      store.put(site, ChatThread.fromJson(threadJson(), site));
      final unread = store.read<ChatThread>(site, 22)!;
      expect(
        unread.tracking,
        const ChatTracking(unreadCount: 2, mentionCount: 1),
      );
      expect(
        unread.withDetail(ChatThread.fromJson(threadJson(), site)).tracking,
        unread.tracking,
      );

      // Core leaves a read thread out of the page's tracking map.
      store.putAll(site, page(const {}).threads);
      expect(store.read<ChatThread>(site, 22)?.tracking, ChatTracking.none);

      store.put(site, unread);
      store.put(site, unread.copyWith(tracking: ChatTracking.none));
      expect(store.read<ChatThread>(site, 22)?.tracking, ChatTracking.none);
    });

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
  });

  group('thread-list refresh', () {
    const tracked = ChatThreadMembership(
      threadId: 22,
      notificationLevel: ChatThreadNotificationLevel.tracking,
      lastReadMessageId: 17,
    );
    // Held when the request began.
    final start = ChatThread.fromJson(threadJson(detail: false), site).copyWith(
      membership: tracked,
      tracking: const ChatTracking(unreadCount: 2),
    );
    // Differs from [start] in level, read position and counts alike.
    final page = ChatThread.fromJson(threadJson(detail: false), site).copyWith(
      membership: const ChatThreadMembership(
        threadId: 22,
        notificationLevel: ChatThreadNotificationLevel.normal,
        lastReadMessageId: 30,
      ),
      tracking: ChatTracking.none,
    );

    ChatThread committed(ChatThread before, ChatThread after) {
      final store = Store()..put(site, after);
      final refresh = ChatThreadListRefresh()..recordChange(before, after);
      return store.put(site, refresh.reconcile(page, after));
    }

    test('keeps a local level but takes the page read state', () {
      final held = committed(
        start,
        start.copyWith(
          membership: tracked.withNotificationLevel(
            ChatThreadNotificationLevel.watching,
          ),
        ),
      );

      expect(
        held.membership?.notificationLevel,
        ChatThreadNotificationLevel.watching,
      );
      expect(held.membership?.lastReadMessageId, 30);
      expect(held.tracking, ChatTracking.none);
    });

    test('keeps a local read with its counts but takes the page level', () {
      final held = committed(
        start,
        start.copyWith(membership: tracked.withLastReadMessageId(40)),
      );

      expect(
        held.membership?.notificationLevel,
        ChatThreadNotificationLevel.normal,
      );
      expect(held.membership?.lastReadMessageId, 40);
      expect(held.tracking, const ChatTracking(unreadCount: 2));
    });

    test('keeps a membership that a refused first choice removed', () {
      final none = start.copyWith(clearMembership: true);
      final optimistic = none.copyWith(
        membership: const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.watching,
        ),
      );
      final refresh = ChatThreadListRefresh()
        ..recordChange(none, optimistic)
        ..recordChange(optimistic, none);
      final store = Store()..put(site, none);

      expect(store.put(site, refresh.reconcile(page, none)).membership, isNull);
    });
  });
}
