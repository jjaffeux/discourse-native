import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/counting_thread_overview.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  test(
    'By type extracts starred channels and DMs once; Newest keeps activity order',
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
        ChatInboxSectionKind.channels,
        ChatInboxSectionKind.directMessages,
      ]);
      expect(grouped.map((s) => s.channels.map((c) => c.id).toList()), [
        [1, 3],
        [2],
        [4],
      ]);
      final newest = chatInboxSections(channels, ChatInboxSort.newest);
      expect(newest.single.kind, ChatInboxSectionKind.allChats);
      expect(newest.single.channels.map((c) => c.id), [1, 2, 3, 4]);
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
          ChatInboxKind.all: [1, 2, 7, 3, 6, 8, 4],
          ChatInboxKind.channels: [7, 3, 6, 4],
          ChatInboxKind.directMessages: [1, 2, 8],
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
          [1, 2, 8],
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

    test('bounds thread scans to filtering and one activity read', () async {
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

      for (final unreadOnly in [false, true]) {
        for (final overview in overviews) {
          overview.visits = 0;
        }
        expect(
          chatInboxConversations(
            subject.chat,
            _site,
            ChatInboxFilter(unreadOnly: unreadOnly),
          ).map((channel) => channel.id),
          unreadOnly ? [7, 5, 3, 1] : [7, 5, 3, 1, 8, 6, 4, 2],
        );
        for (var i = 0; i < overviews.length; i++) {
          expect(
            overviews[i].visits,
            3 * (unreadOnly && i.isEven ? 2 : 1),
            reason: 'Channel ${i + 1}, unreadOnly $unreadOnly',
          );
        }
      }
    });

    test(
      'fresh projections reflect mutable threads and replaced rows',
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
        const unread = ChatInboxFilter(unreadOnly: true);
        final first = chatInboxConversations(subject.chat, _site, all);
        expect(first, [newer, older]);
        expect(chatInboxConversations(subject.chat, _site, unread), isEmpty);
        first.clear();
        expect(chatInboxConversations(subject.chat, _site, all), [
          newer,
          older,
        ]);

        overview[10] = DateTime.utc(2026, 10, 5);
        final afterThread = chatInboxConversations(subject.chat, _site, all);
        expect(afterThread.map((channel) => channel.id), [1, 2]);
        expect(afterThread.first, same(older));
        expect(chatInboxConversations(subject.chat, _site, unread), [older]);

        final edited = older.withLastMessagePreview('Edited preview');
        subject.store.put(_site, edited);
        final afterPreview = chatInboxConversations(subject.chat, _site, all);
        expect(afterPreview.first, same(edited));
        expect(afterPreview.first.lastMessagePreview, 'Edited preview');

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
        expect(chatInboxConversations(subject.chat, _site, unread), [
          newlyUnread,
        ]);
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

    test('uses real thread activity instead of a placeholder timestamp', () {
      final threadAt = DateTime.utc(2026, 9, 26);
      final channel = ChatChannel(
        id: 9,
        title: 'General',
        kind: ChatChannelKind.category,
        lastMessageAt: DateTime.utc(2026, 9, 27),
        unreadThreadOverview: {10: threadAt},
      );

      expect(chatInboxActivityAt(channel), threadAt);
    });

    test('uses the newest message or unread thread timestamp', () {
      final latest = DateTime.utc(2026, 9, 27);
      final older = DateTime.utc(2026, 9, 26);
      for (final messageIsNewest in [false, true]) {
        final channel = ChatChannel(
          id: 9,
          title: 'General',
          kind: ChatChannelKind.category,
          lastMessageId: 50,
          lastMessageAt: messageIsNewest ? latest : older,
          unreadThreadOverview: {
            10: messageIsNewest ? older : latest,
            11: DateTime.utc(2026, 9, 25),
          },
        );

        expect(chatInboxActivityAt(channel), latest);
      }
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
