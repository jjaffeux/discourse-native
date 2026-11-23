import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/counting_thread_overview.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  test(
    'chats are found by name first, then by one thing said that has every word',
    () async {
      final subject = await _fixture(
        public: const [
          ChatChannel(
            id: 1,
            title: 'Design studio',
            kind: ChatChannelKind.category,
            lastMessageId: 9,
            lastMessagePreview: 'Release planning',
            lastMessageUsername: 'mira',
            lastMessageUserId: 6,
          ),
          ChatChannel(
            id: 2,
            title: 'Engineering',
            kind: ChatChannelKind.category,
            tracking: ChatTracking(unreadCount: 2),
          ),
        ],
        direct: const [
          ChatChannel(
            id: 3,
            title: 'Alice and Bob',
            kind: ChatChannelKind.directMessage,
            isGroup: true,
            membership: ChatMembership(starred: true),
          ),
        ],
      );
      final chat = subject.chat;
      subject.store.putAll(_site, [
        const ChatMessage(
          id: 8,
          channelId: 1,
          cooked: '<p>Review the design sketches</p>',
          author: ChatMessageAuthor(id: 6, username: 'mira'),
        ),
        const ChatMessage(
          id: 10,
          channelId: 1,
          cooked: '<p>Keyboard &amp; focus</p>',
          author: ChatMessageAuthor(
            id: 4,
            username: 'david',
            name: 'David Smith',
          ),
        ),
        const ChatMessage(
          id: 11,
          channelId: 1,
          threadId: 77,
          cooked: '<p>Thread starter</p>',
          author: ChatMessageAuthor(id: 5, username: 'sam'),
          thread: ChatThreadPreview(threadId: 77, replyCount: 1),
        ),
        const ChatMessage(
          id: 12,
          channelId: 2,
          cooked: '<p>The design tokens landed</p>',
          author: ChatMessageAuthor(id: 5, username: 'sam'),
        ),
        const ChatMessage(
          id: 13,
          channelId: 2,
          cooked: '<p>Older design note</p>',
          deletedAt: null,
          author: ChatMessageAuthor(id: 4, username: 'david'),
        ),
        const ChatMessage(
          id: -1,
          channelId: 3,
          cooked: '',
          raw: 'Local draft send',
          author: ChatMessageAuthor(id: 7, username: 'reader'),
        ),
      ]);
      List<int> found(String query) => chat
          .findConversations(_site, query)
          .channels
          .map((c) => c.id)
          .toList();
      for (final (query, ids) in [
        ('  DESIGN   studio ', [1]),
        ('keyboard smith', [1]),
        ('thread sam', [1]),
        ('draft reader', [3]),
        ('release MIRA', [1]),
        // Every word has to be in the name, or in one thing said.
        ('design keyboard', <int>[]),
        ('engineering mira', <int>[]),
        ('missing', <int>[]),
        (' \t ', [3, 1, 2]),
      ]) {
        expect(found(query), ids, reason: query);
      }
      // By name first, then by what was said, what is unread leading those.
      expect(found('design'), [1, 2]);
      expect(found('sam'), [2, 1]);
      final results = chat.findConversations(_site, 'design');
      expect(results.lines[1]!.text, 'Review the design sketches');
      expect(chat.findConversations(_site, 'design studio').lines, isEmpty);
      expect(results.lines[2]!.text, 'Older design note');
      expect(results.lines[2]!.authorName, 'david');
      expect(results.lines[2]!.query, 'design');
      final mira = chat.findConversations(_site, 'mira').lines[1]!;
      expect(mira.text, 'Release planning');
      expect(mira.authorId, 6);
      expect(
        chat.findConversations(_site, 'draft').lines[3]!.text,
        'Local draft send',
        reason: 'An unsent message is the latest said',
      );

      chat.inboxFilters.setSidebarQuery(_site, 'design');
      expect(chat.inboxFilters.queryFor(ChatInboxPlace.side, _site), 'design');
      expect(chat.inboxFilters.queryFor(ChatInboxPlace.page, _site), isEmpty);
      chat.inboxFilters.update(
        _site,
        const ChatInboxFilter(kind: ChatInboxKind.directMessages),
      );
      expect(found('design'), isEmpty);
      expect(
        chat.inboxFilters.sidebarQueryFor('https://another.invalid'),
        isEmpty,
      );
      chat.inboxFilters.forget(_site);
      expect(chat.inboxFilters.sidebarQueryFor(_site), isEmpty);
      expect(chat.inboxFilters.filterFor(_site), const ChatInboxFilter());
    },
  );

  test(
    'By type extracts starred channels and DMs once; Newest leads with starred',
    () {
      const channels = [
        ChatChannel(
          id: 1,
          title: 'Newest DM',
          kind: ChatChannelKind.directMessage,
          membership: ChatMembership(starred: true),
        ),
        ChatChannel(id: 2, title: 'Public', kind: ChatChannelKind.category),
        ChatChannel(
          id: 3,
          title: 'Starred public',
          kind: ChatChannelKind.category,
          membership: ChatMembership(starred: true),
        ),
        ChatChannel(
          id: 4,
          title: 'Older DM',
          kind: ChatChannelKind.directMessage,
        ),
      ];
      final grouped = chatInboxSections(channels, ChatInboxSort.byType);
      expect(grouped.map((s) => s.kind), [
        ChatInboxSectionKind.starred,
        ChatInboxSectionKind.directMessages,
        ChatInboxSectionKind.channels,
      ]);
      expect(grouped.map((s) => s.channels.map((c) => c.id).toList()), [
        [1, 3],
        [4],
        [2],
      ]);
      final newest = chatInboxSections(channels, ChatInboxSort.newest);
      expect(newest.single.kind, ChatInboxSectionKind.allChats);
      expect(newest.single.channels.map((c) => c.id), [1, 3, 2, 4]);
      expect(
        chatInboxSections([
          channels.first,
        ], ChatInboxSort.byType).map((s) => s.kind),
        [ChatInboxSectionKind.starred],
      );
      for (final sort in ChatInboxSort.values) {
        expect(chatInboxSections([], sort), isEmpty);
      }
    },
  );

  test(
    'section folding retains the active row and counts only hidden rows',
    () {
      const rows = [1, 2, 3, 4, 5, 6, 7];
      final folded = ChatInboxSectionSlice(
        rows,
        expanded: false,
        alone: false,
        keep: (id) => id == 7,
      );
      expect(folded.visible, [1, 2, 3, 4, 7]);
      expect(folded.hidden, 2);
      expect(folded.canFold, isTrue);
      final expanded = ChatInboxSectionSlice(
        rows,
        expanded: true,
        alone: false,
      );
      expect(expanded.visible, rows);
      expect(expanded.hidden, 0);
      expect(expanded.canFold, isTrue);
      final lone = ChatInboxSectionSlice(rows, expanded: false, alone: true);
      expect(lone.visible, rows);
      expect(lone.canFold, isFalse);
      final five = ChatInboxSectionSlice(
        [1, 2, 3, 4, 5],
        expanded: false,
        alone: false,
      );
      expect(five.visible, [1, 2, 3, 4, 5]);
      expect(five.canFold, isFalse);
      final six = ChatInboxSectionSlice(
        [1, 2, 3, 4, 5, 6],
        expanded: false,
        alone: false,
      );
      expect(six.visible, [1, 2, 3, 4]);
      expect(six.hidden, 2);
    },
  );

  test('every group leads with what is new and closes with what is muted', () {
    ChatChannel chat(
      int id, {
      bool direct = false,
      int unread = 0,
      int mentions = 0,
      bool muted = false,
      bool starred = false,
    }) => ChatChannel(
      id: id,
      title: 'Chat $id',
      kind: direct ? ChatChannelKind.directMessage : ChatChannelKind.category,
      tracking: ChatTracking(unreadCount: unread, mentionCount: mentions),
      membership: ChatMembership(muted: muted, starred: starred),
    );
    // Listed the most recent first, as the inbox projection hands them over.
    final channels = [
      chat(1),
      chat(2, muted: true, mentions: 2),
      chat(3, unread: 4),
      chat(4, direct: true),
      chat(5, direct: true, unread: 1),
      chat(6, starred: true),
      chat(7, starred: true, unread: 2),
      chat(8, mentions: 1),
      chat(9, direct: true, muted: true),
    ];
    final grouped = chatInboxSections(channels, ChatInboxSort.byType);
    expect(grouped.map((s) => s.channels.map((c) => c.id).toList()), [
      [7, 6],
      [5, 4, 9],
      [3, 8, 1, 2],
    ]);
    expect(
      chatInboxSections(
        channels,
        ChatInboxSort.newest,
      ).single.channels.map((c) => c.id),
      [7, 3, 5, 8, 6, 1, 4, 2, 9],
    );
    expect(chatInboxOrder(channels, ChatInboxSort.byType), [
      7,
      6,
      5,
      4,
      9,
      3,
      8,
      1,
      2,
    ]);
    expect(chatInboxUnreadCount(channels[1]), 2);
    expect(chatInboxIsNew(channels[1]), isFalse);
    expect(chatInboxIsNew(channels[7]), isTrue);
  });

  test('a group shows its unread up to ten before it folds', () {
    final rows = [for (var i = 1; i <= 16; i++) i];
    ChatInboxSectionSlice<int> slice(int unread, {int length = 16}) =>
        ChatInboxSectionSlice(
          rows.take(length).toList(),
          expanded: false,
          alone: false,
          isNew: (row) => row <= unread,
        );
    expect(slice(0).visible, [1, 2, 3, 4]);
    expect(slice(0).hiddenUnread, 0);
    expect(slice(6).visible, [1, 2, 3, 4, 5, 6]);
    expect(slice(6).hidden, 10);
    expect(slice(6).hiddenUnread, 0);
    expect(slice(13).visible, rows.take(10));
    expect(slice(13).hidden, 6);
    expect(slice(13).hiddenUnread, 3);
    expect(slice(6, length: 7).canFold, isFalse);
    expect(slice(6, length: 7).visible, hasLength(7));
    expect(slice(6, length: 8).visible, hasLength(6));
    final held = ChatInboxSectionSlice(
      rows,
      expanded: false,
      alone: false,
      keep: (row) => row == 3,
      isNew: (row) => row <= 2,
    );
    expect(held.visible, [1, 2, 3, 4]);
  });

  group('chatInboxConversations', () {
    test(
      'preserves activity, title and ID order across inbox filters',
      () async {
        var settings = const ChatSettings();
        final subject = await _fixture(
          public: [
            ChatChannel(
              id: 7,
              title: 'Zeta',
              kind: ChatChannelKind.category,
              lastMessageId: 70,
              lastMessageAt: DateTime.utc(2026, 10, 17),
            ),
            const ChatChannel(
              id: 6,
              title: 'ALPHA',
              kind: ChatChannelKind.category,
            ),
            ChatChannel(
              id: 4,
              title: 'Beta',
              kind: ChatChannelKind.category,
              lastMessageId: 0,
              lastMessageAt: DateTime.utc(2026, 10, 20),
            ),
            const ChatChannel(
              id: 3,
              title: 'Alpha',
              kind: ChatChannelKind.category,
            ),
          ],
          direct: [
            ChatChannel(
              id: 2,
              title: 'Recent DM',
              kind: ChatChannelKind.directMessage,
              lastMessageId: 20,
              lastMessageAt: DateTime.utc(2026, 10, 18),
            ),
            ChatChannel(
              id: 1,
              title: 'Threaded',
              kind: ChatChannelKind.directMessage,
              unreadThreadOverview: {10: DateTime.utc(2026, 10, 19)},
            ),
            const ChatChannel(
              id: 8,
              title: 'alpha',
              kind: ChatChannelKind.directMessage,
            ),
          ],
          siteConfigFor: (_) => SiteConfig(
            plugins: PluginData.none.withValue(chatSettingsDataKey, settings),
          ),
        );

        for (final entry in {
          ChatInboxKind.all: [2, 7, 3, 6, 8, 4, 1],
          ChatInboxKind.channels: [7, 3, 6, 4],
          ChatInboxKind.directMessages: [2, 8, 1],
          ChatInboxKind.voiceRooms: <int>[],
        }.entries) {
          expect(
            chatInboxConversations(
              subject.chat,
              _site,
              ChatInboxFilter(kind: entry.key),
            ).map((channel) => channel.id),
            entry.value,
          );
        }

        settings = const ChatSettings(publicChannelsEnabled: false);
        expect(
          chatInboxConversations(
            subject.chat,
            _site,
            const ChatInboxFilter(),
          ).map((channel) => channel.id),
          [2, 8, 1],
        );
        expect(
          chatInboxConversations(
            subject.chat,
            _site,
            const ChatInboxFilter(kind: ChatInboxKind.channels),
          ),
          isEmpty,
        );
      },
    );

    test('keeps a singleton fresh without reading activity', () async {
      final overview = CountingThreadOverview({10: DateTime.utc(2026, 10, 19)});
      final channel = ChatChannel(
        id: 1,
        title: 'Only channel',
        kind: ChatChannelKind.category,
        unreadThreadOverview: overview,
      );
      final subject = await _fixture(public: [channel], direct: []);
      overview.visits = 0;

      final first = chatInboxConversations(
        subject.chat,
        _site,
        const ChatInboxFilter(),
      );
      expect(first.single, same(channel));
      expect(overview.visits, 0);
      first.clear();
      expect(
        chatInboxConversations(
          subject.chat,
          _site,
          const ChatInboxFilter(),
        ).single,
        same(channel),
      );
      expect(overview.visits, 0);
    });

    test('orders channel messages without scanning thread activity', () async {
      final overviews = [
        for (var i = 0; i < 8; i++)
          CountingThreadOverview({
            for (var thread = 0; thread < 3; thread++)
              thread: i.isEven
                  ? DateTime.utc(2026, 10, 2, 0, i, thread)
                  : DateTime.utc(2026, 9, 30, 0, i, thread),
          }),
      ];
      final channels = [
        for (var i = 0; i < overviews.length; i++)
          ChatChannel(
            id: i + 1,
            title: 'Channel $i',
            kind: i.isEven
                ? ChatChannelKind.category
                : ChatChannelKind.directMessage,
            membership: ChatMembership(
              following: true,
              lastViewedAt: DateTime.utc(2026, 10, 1),
            ),
            lastMessageId: i + 1,
            lastMessageAt: DateTime.utc(2026, 10, 1, 0, i),
            unreadThreadOverview: overviews[i],
          ),
      ];
      final subject = await _fixture(
        public: channels.where((channel) => !channel.isDirectMessage).toList(),
        direct: channels.where((channel) => channel.isDirectMessage).toList(),
      );

      for (final overview in overviews) {
        overview.visits = 0;
      }
      expect(
        chatInboxConversations(
          subject.chat,
          _site,
          const ChatInboxFilter(),
        ).map((channel) => channel.id),
        [8, 7, 6, 5, 4, 3, 2, 1],
      );
      for (var i = 0; i < overviews.length; i++) {
        expect(overviews[i].visits, 0, reason: 'Channel ${i + 1}');
      }
    });

    test(
      'thread changes keep order and message updates replace rows',
      () async {
        final overview = {10: DateTime.utc(2026, 10, 1)};
        final older = ChatChannel(
          id: 1,
          title: 'Older',
          kind: ChatChannelKind.category,
          membership: ChatMembership(lastViewedAt: DateTime.utc(2026, 10, 4)),
          lastMessageId: 10,
          lastMessageAt: DateTime.utc(2026, 10, 2),
          unreadThreadOverview: overview,
        );
        final newer = ChatChannel(
          id: 2,
          title: 'Newer',
          kind: ChatChannelKind.directMessage,
          lastMessageId: 20,
          lastMessageAt: DateTime.utc(2026, 10, 3),
        );
        final subject = await _fixture(public: [older], direct: [newer]);
        const all = ChatInboxFilter();
        final first = chatInboxConversations(subject.chat, _site, all);
        expect(first, [newer, older]);
        first.clear();
        expect(chatInboxConversations(subject.chat, _site, all), [
          newer,
          older,
        ]);

        overview[10] = DateTime.utc(2026, 10, 5);
        final afterThread = chatInboxConversations(subject.chat, _site, all);
        expect(afterThread, [newer, older]);

        final edited = older.withLastMessagePreview('Edited preview');
        subject.store.put(_site, edited);
        final afterPreview = chatInboxConversations(subject.chat, _site, all);
        expect(afterPreview.last, same(edited));
        expect(afterPreview.last.lastMessagePreview, 'Edited preview');

        subject.store.put(
          _site,
          edited.withTrackingState(
            tracking: ChatTracking.none,
            unreadThreadOverview: {},
          ),
        );
        final newlyUnread = newer.withTrackingState(
          tracking: const ChatTracking(unreadCount: 1),
        );
        subject.store.put(_site, newlyUnread);
        expect(
          chatInboxConversations(
            subject.chat,
            _site,
            all,
          ).map((channel) => channel.id),
          [2, 1],
        );
      },
    );
  });

  group('chatInboxActivityAt', () {
    for (final kind in ['Category', 'DirectMessage']) {
      for (final messageId in [null, 0]) {
        test('ignores a $kind placeholder with message ID $messageId', () {
          final channel = ChatChannel.fromJson({
            'id': 9,
            'title': 'Empty conversation',
            'chatable_type': kind,
            'last_message': {
              'id': messageId,
              'created_at': '2026-09-27T09:28:00.000Z',
            },
          }, _site);

          expect(chatInboxActivityAt(channel), isNull);
        });
      }
    }

    test('uses the timestamp of a real message', () {
      final channel = ChatChannel.fromJson(const {
        'id': 9,
        'title': 'General',
        'chatable_type': 'Category',
        'last_message': {'id': 50, 'created_at': '2026-09-27T09:13:00.000Z'},
      }, _site);

      expect(chatInboxActivityAt(channel), DateTime.utc(2026, 9, 27, 9, 13));
    });

    test('does not invent activity when the timestamp is missing', () {
      const channel = ChatChannel(
        id: 9,
        title: 'General',
        kind: ChatChannelKind.category,
        lastMessageId: 50,
      );

      expect(chatInboxActivityAt(channel), isNull);
    });

    test('does not give a conversation without a message a time', () {
      final threadAt = DateTime.utc(2026, 9, 26);
      final channel = ChatChannel(
        id: 9,
        title: 'General',
        kind: ChatChannelKind.category,
        lastMessageAt: DateTime.utc(2026, 9, 27),
        unreadThreadOverview: {10: threadAt},
      );

      expect(chatInboxActivityAt(channel), isNull);
    });

    test('a newer thread reply leaves the channel message time intact', () {
      final messageAt = DateTime.utc(2026, 9, 26);
      final channel = ChatChannel(
        id: 9,
        title: 'General',
        kind: ChatChannelKind.category,
        lastMessageId: 50,
        lastMessageAt: messageAt,
        unreadThreadOverview: {10: DateTime.utc(2026, 9, 27)},
      );
      expect(chatInboxActivityAt(channel), messageAt);
    });
  });
}

Future<({ChatController chat, Store store})> _fixture({
  required List<ChatChannel> public,
  required List<ChatChannel> direct,
  SiteConfig Function(String)? siteConfigFor,
}) async {
  final store = Store();
  final chat = ChatController(
    api: FakeDiscourseApi(
      chatChannelsBySite: {_site: ChatChannels(public: public, direct: direct)},
    ),
    requests: FakePluginRequestHost(
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
    ),
    siteConfigFor: siteConfigFor,
    store: store,
  );
  addTearDown(chat.dispose);
  await chat.loadChannels(_site);
  return (chat: chat, store: store);
}
