import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/counting_thread_overview.dart';

final _now = DateTime.utc(2026, 9, 16, 12);

ChatChannel _channel(
  int id,
  String name, {
  int days = 1,
  bool muted = false,
  bool dm = false,
  int unread = 0,
  int mentions = 0,
  int watched = 0,
  DateTime? threadAt,
  bool hasMessage = true,
}) => ChatChannel(
  id: id,
  title: name,
  slug: name,
  kind: dm ? ChatChannelKind.directMessage : ChatChannelKind.category,
  membership: ChatMembership(
    following: true,
    muted: muted,
    lastViewedAt: _now.subtract(const Duration(days: 2)),
  ),
  tracking: ChatTracking(
    unreadCount: unread,
    mentionCount: mentions,
    watchedThreadsUnreadCount: watched,
  ),
  threadingEnabled: threadAt != null,
  unreadThreadOverview: threadAt == null ? const {} : {1: threadAt},
  lastMessageId: hasMessage ? id : null,
  lastMessageAt: _now.subtract(Duration(days: days)),
);

void main() {
  test('priority projection visits each thread at most once per call', () {
    final overview = CountingThreadOverview({
      for (var i = 0; i < 32; i++) i: _now,
    });
    final channels = [
      for (var i = 0; i < 64; i++)
        ChatChannel(
          id: i,
          title: 'Channel $i',
          kind: ChatChannelKind.category,
          membership: ChatMembership(lastViewedAt: _now),
          threadingEnabled: true,
          unreadThreadOverview: overview,
          lastMessageId: i + 1,
          lastMessageAt: _now.subtract(Duration(minutes: (i * 17) % 64)),
        ),
    ];
    List<ChatChannel> project() => projectChatChannelList(
      channels,
      filter: ChatChannelListFilter.unread,
      sort: ChatChannelListSort.priority,
      section: ChatChannelListSection.channels,
      now: _now,
    );
    expect(project(), hasLength(64));
    expect(overview.visits, lessThanOrEqualTo(64 * 32));
    // The memo belongs to one projection, never to a retained channel or site.
    overview.clear();
    expect(project(), isEmpty);
  });

  final channels = [
    _channel(1, 'alpha', days: 31),
    _channel(2, 'beta', unread: 1, days: 3),
    _channel(3, 'gamma', mentions: 1, days: 2),
    _channel(4, 'delta', watched: 1, days: 4),
    _channel(5, 'epsilon', muted: true, mentions: 9),
    _channel(6, 'zeta', threadAt: _now),
    _channel(7, 'eta', dm: true, unread: 8, days: 5),
    _channel(8, 'theta', hasMessage: false),
  ];
  final expected = <ChatChannelListFilter, List<List<int>>>{
    ChatChannelListFilter.all: [
      [1, 2, 4, 5, 7, 3, 8, 6],
      [5, 6, 3, 2, 4, 7, 1, 8],
      [3, 4, 6, 2, 7, 5, 1, 8],
    ],
    ChatChannelListFilter.active: [
      [2, 4, 5, 7, 3, 6],
      [5, 6, 3, 2, 4, 7],
      [3, 4, 6, 2, 7, 5],
    ],
    ChatChannelListFilter.unread: [
      [2, 4, 7, 3, 6],
      [6, 3, 2, 4, 7],
      [3, 4, 6, 2, 7],
    ],
    ChatChannelListFilter.mentions: [
      [4, 3],
      [3, 4],
      [3, 4],
    ],
  };
  for (final filter in ChatChannelListFilter.values) {
    for (final sort in ChatChannelListSort.values) {
      test(
        '${filter.wireValue} with ${sort.wireValue} uses core activity semantics',
        () {
          expect(
            projectChatChannelList(
              channels,
              filter: filter,
              sort: sort,
              section: ChatChannelListSection.channels,
              now: _now,
            ).map((c) => c.id),
            expected[filter]![sort.index],
          );
        },
      );
    }
  }

  test(
    'active cutoff includes exactly 30 days and rejects missing message identity',
    () {
      final cutoff = _now.subtract(const Duration(days: 30));
      final boundary = [
        _channel(1, 'boundary', days: 30),
        _channel(2, 'before', days: 30),
        _channel(3, 'missing', hasMessage: false),
      ];
      expect(
        projectChatChannelList(
          boundary,
          filter: ChatChannelListFilter.active,
          sort: ChatChannelListSort.alphabetical,
          section: ChatChannelListSection.channels,
          now: cutoff.add(const Duration(days: 30)),
        ).map((c) => c.id),
        [2, 1],
      );
      expect(
        projectChatChannelList(
          boundary,
          filter: ChatChannelListFilter.active,
          sort: ChatChannelListSort.alphabetical,
          section: ChatChannelListSection.channels,
          now: _now.add(const Duration(microseconds: 1)),
        ),
        isEmpty,
      );
    },
  );

  test(
    'viewed threads do not match unread and timestamps alone do not match active',
    () {
      expect(
        projectChatChannelList(
          [
            _channel(
              1,
              'old thread',
              threadAt: _now.subtract(const Duration(days: 3)),
            ),
            _channel(2, 'no message', hasMessage: false),
          ],
          filter: ChatChannelListFilter.unread,
          sort: ChatChannelListSort.priority,
          section: ChatChannelListSection.channels,
          now: _now,
        ),
        isEmpty,
      );
    },
  );

  test(
    'thread overviews respect threading and the inclusive viewed boundary',
    () {
      final channels = [
        ChatChannel(
          id: 1,
          title: 'Threading disabled',
          slug: 'threading-disabled',
          kind: ChatChannelKind.category,
          membership: ChatMembership(following: true, lastViewedAt: _now),
          unreadThreadOverview: {1: _now},
          lastMessageId: 1,
          lastMessageAt: _now,
        ),
        _channel(2, 'threading-enabled', threadAt: _now),
        ChatChannel(
          id: 3,
          title: 'At last viewed time',
          slug: 'at-last-viewed-time',
          kind: ChatChannelKind.category,
          membership: ChatMembership(following: true, lastViewedAt: _now),
          threadingEnabled: true,
          unreadThreadOverview: {1: _now},
        ),
      ];
      expect(
        projectChatChannelList(
          channels,
          filter: ChatChannelListFilter.unread,
          sort: ChatChannelListSort.priority,
          section: ChatChannelListSection.channels,
          now: _now,
        ).map((channel) => channel.id),
        [2, 3],
      );
      expect(
        projectChatChannelList(
          channels,
          filter: ChatChannelListFilter.all,
          sort: ChatChannelListSort.priority,
          section: ChatChannelListSection.channels,
          now: _now,
        ).map((channel) => channel.id),
        [2, 3, 1],
      );
    },
  );

  test(
    'starred alphabetical groups public then DMs while other sorts cross types',
    () {
      final starred = [
        _channel(3, 'same', days: 2),
        _channel(2, 'same', days: 2),
        _channel(1, 'aardvark', dm: true, mentions: 1),
      ];
      for (final sort in ChatChannelListSort.values) {
        expect(
          projectChatChannelList(
            starred,
            filter: ChatChannelListFilter.all,
            sort: sort,
            section: ChatChannelListSection.starred,
            now: _now,
          ).map((c) => c.id),
          sort == ChatChannelListSort.alphabetical ? [2, 3, 1] : [1, 2, 3],
          reason: sort.name,
        );
      }
    },
  );

  test(
    'sidebar replaces the last limited DM with the active channel; drawer slices',
    () {
      final dms = [
        for (var i = 1; i <= 55; i++)
          _channel(i, '$i'.padLeft(2, '0'), dm: true),
      ];
      for (final retain in [true, false]) {
        expect(
          projectChatChannelList(
            dms,
            filter: ChatChannelListFilter.all,
            sort: ChatChannelListSort.alphabetical,
            section: ChatChannelListSection.directMessages,
            now: _now,
            activeChannelId: 55,
            limit: 50,
            retainActiveAtLimit: retain,
          ).map((c) => c.id),
          [for (var i = 1; i < 50; i++) i, retain ? 55 : 50],
        );
      }
      expect(
        projectChatChannelList(
          dms,
          filter: ChatChannelListFilter.mentions,
          sort: ChatChannelListSort.priority,
          section: ChatChannelListSection.directMessages,
          now: _now,
          activeChannelId: 55,
          limit: 50,
          retainActiveAtLimit: true,
        ).map((c) => c.id),
        [55],
      );
    },
  );

  test(
    'every filter retains an active muted channel; empty input stays empty',
    () {
      for (final filter in ChatChannelListFilter.values) {
        for (final source in [
          <ChatChannel>[],
          [_channel(1, 'muted', days: 60, muted: true)],
        ]) {
          expect(
            projectChatChannelList(
              source,
              filter: filter,
              sort: ChatChannelListSort.priority,
              section: ChatChannelListSection.channels,
              now: _now,
              activeChannelId: 1,
            ).map((c) => c.id),
            source.isEmpty ? <int>[] : [1],
            reason: filter.name,
          );
        }
      }
    },
  );
}
