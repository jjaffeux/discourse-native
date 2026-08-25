import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String site = 'https://meta.discourse.org';

/// A public channel as `Chat::ChannelSerializer` writes one.
Map<String, dynamic> categoryChannel({
  int id = 9,
  String title = 'Bugs',
  String? unicodeTitle,
  String? slug = 'bugs',
  String? emoji,
  String? color = '0088CC',
  bool readRestricted = false,
  bool muted = false,
  bool starred = false,
  String? notificationLevel,
  int? lastReadMessageId,
  String? lastViewedAt,
  bool threading = false,
  String? status,
  bool userSilenced = false,
  bool canModerate = false,
  bool canDeleteSelf = false,
  bool canDeleteOthers = false,
  bool canManagePins = false,
  bool canFlag = false,
  int pinnedMessagesCount = 0,
  int membershipsCount = 0,
  bool canJoin = false,
  bool hasUnseenPins = false,
  String? lastViewedPinsAt,
}) => {
  'id': id,
  'title': title,
  'unicode_title': ?unicodeTitle,
  'slug': ?slug,
  'emoji': ?emoji,
  'chatable_type': 'Category',
  'chatable_id': 1,
  'chatable': {
    'id': 1,
    'name': 'Bug',
    'color': ?color,
    'read_restricted': readRestricted,
  },
  'threading_enabled': threading,
  'pinned_messages_count': pinnedMessagesCount,
  'memberships_count': membershipsCount,
  'status': ?status,
  'meta': {
    if (userSilenced) 'user_silenced': true,
    'can_moderate': canModerate,
    'can_delete_self': canDeleteSelf,
    'can_delete_others': canDeleteOthers,
    'can_manage_pins': canManagePins,
    'can_flag': canFlag,
    'can_join_chat_channel': canJoin,
  },
  'current_user_membership': {
    'following': true,
    'muted': muted,
    'starred': starred,
    'notification_level': ?notificationLevel,
    'last_read_message_id': ?lastReadMessageId,
    'last_viewed_at': ?lastViewedAt,
    'last_viewed_pins_at': ?lastViewedPinsAt,
    'has_unseen_pins': hasUnseenPins,
  },
};

/// A direct channel, whose `chatable` is people rather than a category.
Map<String, dynamic> directChannel({
  int id = 12,
  String title = 'hawk',
  bool group = false,
  List<Map<String, dynamic>>? users,
  int lastMessageId = 40,
  String? lastMessageAt,
  int? newMessagesLastId,
  int? channelMessageBusLastId,
  bool? starred,
}) => {
  'id': id,
  'title': title,
  'chatable_type': 'DirectMessage',
  'chatable_id': 3,
  'chatable': {
    'group': group,
    'users':
        users ??
        [
          {
            'id': 2,
            'username': 'hawk',
            'name': 'Hawk',
            'avatar_template': '/user_avatar/h/{size}.png',
          },
        ],
  },
  'last_message': {'id': lastMessageId, 'created_at': ?lastMessageAt},
  'meta': {
    'message_bus_last_ids': {
      'new_messages': ?newMessagesLastId,
      'channel_message_bus_last_id': ?channelMessageBusLastId,
    },
  },
  'current_user_membership': {
    'following': true,
    'muted': false,
    'starred': ?starred,
  },
};

Map<String, dynamic> payload({
  List<Map<String, dynamic>> public = const [],
  List<Map<String, dynamic>> direct = const [],
  Map<String, dynamic>? tracking,
  Map<String, dynamic>? unreadThreads,
  Map<String, dynamic>? presence,
  int? newChannelLastId,
  int? userTrackingLastId,
  int? userHasThreadsLastId,
  bool hasThreads = false,
}) => {
  'public_channels': public,
  'direct_message_channels': direct,
  'tracking': {
    'channel_tracking': tracking ?? const <String, dynamic>{},
    'thread_tracking': <String, dynamic>{},
  },
  'unread_thread_overview': unreadThreads ?? const <String, dynamic>{},
  'global_presence_channel_state': ?presence,
  'has_threads': hasThreads,
  'meta': {
    'message_bus_last_ids': {
      'new_channel': ?newChannelLastId,
      'user_tracking_state': ?userTrackingLastId,
      'user_has_threads': ?userHasThreadsLastId,
    },
  },
};

Map<String, dynamic> counts({
  int unread = 0,
  int mentions = 0,
  int watchedThreads = 0,
}) => {
  'unread_count': unread,
  'mention_count': mentions,
  'watched_threads_unread_count': watchedThreads,
};

ChatChannel channelFrom(Map<String, dynamic> json) =>
    ChatChannel.fromJson(json, site);

void main() {
  group('reading a channel', () {
    test(
      'takes the title the site computed rather than naming anyone again',
      () {
        // The multi-user title is the server's job: it has already dropped the
        // reader, sorted the rest by the site's own naming rules and truncated
        // past seven. Recomputing it here could only disagree.
        final channel = channelFrom(
          directChannel(
            title: 'hawk, kris and 3 others',
            group: true,
            users: const [
              {'id': 2, 'username': 'hawk'},
              {'id': 3, 'username': 'kris'},
            ],
          ),
        );

        expect(channel.title, 'hawk, kris and 3 others');
      },
    );

    test('prefers the unicode title, because that is text a Text can draw', () {
      final channel = channelFrom(
        categoryChannel(title: 'Ship it :tada:', unicodeTitle: 'Ship it 🎉'),
      );

      expect(channel.title, 'Ship it 🎉');
    });

    test(
      'falls back to the plain title where the site sent no unicode one',
      () {
        expect(channelFrom(categoryChannel(title: 'Bugs')).title, 'Bugs');
      },
    );

    test('reads a category colour without the hash the site leaves off', () {
      // `0088CC`, not `#0088CC` — Discourse writes bare hex because the value
      // lands in a stylesheet where the hash is added back.
      final channel = channelFrom(categoryChannel(color: '0088CC'));

      expect(channel.categoryColor, const Color(0xFF0088CC));
    });

    test('retains the category identity behind a public channel', () {
      final channel = channelFrom(categoryChannel());

      expect(channel.chatableId, 1);
      expect(channel.categoryName, 'Bug');
      expect(channel.withStarred(true).chatableId, 1);
      expect(channel.withStarred(true).categoryName, 'Bug');
      expect(channel.withLastRead(4, caughtUp: true).chatableId, 1);
    });

    test('retains Browse Channels membership metadata through copies', () {
      final channel = channelFrom(
        categoryChannel(membershipsCount: 42, canJoin: true),
      );

      expect(channel.membershipsCount, 42);
      expect(channel.canJoin, isTrue);
      expect(channel.withStarred(true).membershipsCount, 42);
      expect(channel.withLastRead(4, caughtUp: true).canJoin, isTrue);
      expect(
        channel
            .withMembership(
              const ChatMembership(following: true),
              membershipsCount: 43,
            )
            .membershipsCount,
        43,
      );
    });

    test('reads a bounded Browse Channels page and its continuation', () {
      final page = ChatChannelBrowsePage.fromJson(
        {
          'channels': [
            categoryChannel(id: 9, title: 'Bugs'),
            categoryChannel(id: 10, title: 'Support'),
          ],
          'meta': const {'load_more_url': '/chat/api/channels?offset=2'},
        },
        site,
        limit: 2,
      );

      expect(page.channels.map((channel) => channel.title), [
        'Bugs',
        'Support',
      ]);
      expect(page.hasMore, isTrue);
    });

    test('reads no colour at all from something that is not one', () {
      expect(channelFrom(categoryChannel(color: 'nope')).categoryColor, isNull);
    });

    test('status and account silence gate message creation', () {
      final open = channelFrom(categoryChannel());
      final closed = channelFrom(categoryChannel(status: 'closed'));
      final readOnly = channelFrom(categoryChannel(status: 'read_only'));
      final archived = channelFrom(categoryChannel(status: 'archived'));
      final silenced = channelFrom(categoryChannel(userSilenced: true));

      expect(open.canModifyMessages(isStaff: false), isTrue);
      expect(closed.canModifyMessages(isStaff: false), isFalse);
      expect(closed.canModifyMessages(isStaff: true), isTrue);
      expect(readOnly.canModifyMessages(isStaff: true), isFalse);
      expect(archived.canModifyMessages(isStaff: true), isFalse);
      expect(silenced.canModifyMessages(isStaff: true), isFalse);
    });

    test('retains the server’s message moderation permissions', () {
      final channel = channelFrom(
        categoryChannel(
          canModerate: true,
          canDeleteSelf: true,
          canDeleteOthers: true,
          canManagePins: true,
          canFlag: true,
        ),
      );

      expect(channel.canModerate, isTrue);
      expect(channel.canDeleteSelf, isTrue);
      expect(channel.canDeleteOthers, isTrue);
      expect(channel.canManagePins, isTrue);
      expect(channel.canFlag, isTrue);
    });

    test('retains pin count and the reader’s unseen-pin state', () {
      final channel = channelFrom(
        categoryChannel(
          pinnedMessagesCount: 3,
          hasUnseenPins: true,
          lastViewedPinsAt: '2026-08-25T09:00:00.000Z',
        ),
      );

      expect(channel.hasPinnedMessages, isTrue);
      expect(channel.pinnedMessagesCount, 3);
      expect(channel.membership.hasUnseenPins, isTrue);
      expect(channel.membership.lastViewedPinsAt, DateTime.utc(2026, 8, 25, 9));
      expect(
        channel
            .withPinsViewed(DateTime.utc(2026, 8, 25, 10))
            .membership
            .hasUnseenPins,
        isFalse,
      );
    });

    test(
      'gives a direct channel no colour, having no category to borrow one from',
      () {
        expect(channelFrom(directChannel()).categoryColor, isNull);
      },
    );

    test('reads a direct channel as the people in it, the reader excluded', () {
      final channel = channelFrom(directChannel());

      expect(channel.isDirectMessage, isTrue);
      expect(channel.users.single.username, 'hawk');
      expect(channel.users.single.displayName, 'Hawk');
      expect(channel.users.single.avatarUrl, '$site/user_avatar/h/90.png');
    });

    test('says nothing about an emoji a channel does not have', () {
      // The key is dropped rather than nulled, so absence is the answer.
      expect(channelFrom(categoryChannel()).emoji, isNull);
      expect(channelFrom(categoryChannel(emoji: 'bug')).emoji, 'bug');
    });

    test('reads a chatable type it has never heard of as neither kind', () {
      final channel = channelFrom({
        'id': 1,
        'title': 'Site',
        'chatable_type': 'Site',
      });

      expect(channel.kind, ChatChannelKind.other);
      expect(channel.isDirectMessage, isFalse);
      expect(channel.isCategoryChannel, isFalse);
    });

    test('remembers where the reader left off, for the unread divider', () {
      final channel = channelFrom(categoryChannel(lastReadMessageId: 42));

      expect(channel.membership.lastReadMessageId, 42);
    });

    test('reads the reader’s starred channel preference', () {
      expect(
        channelFrom(categoryChannel(starred: true)).membership.starred,
        isTrue,
      );
      // Older Discourse versions do not serialize this key.
      expect(channelFrom(directChannel()).membership.starred, isFalse);
    });

    test('reads the reader’s channel push-notification preference', () {
      expect(
        channelFrom(
          categoryChannel(notificationLevel: 'always'),
        ).membership.notificationLevel,
        ChatChannelNotificationLevel.always,
      );
      expect(
        channelFrom(
          categoryChannel(notificationLevel: 'never'),
        ).membership.notificationLevel,
        ChatChannelNotificationLevel.never,
      );
      // Older sites and unfamiliar values use core's ordinary mentions mode.
      expect(
        channelFrom(categoryChannel()).membership.notificationLevel,
        ChatChannelNotificationLevel.mention,
      );
      expect(
        channelFrom(
          categoryChannel(notificationLevel: 'future-level'),
        ).membership.notificationLevel,
        ChatChannelNotificationLevel.mention,
      );
    });

    test('treats a non-boolean starred value as not starred', () {
      final json = directChannel();
      json['current_user_membership'] = <String, dynamic>{
        'following': true,
        'muted': false,
        'starred': 1,
      };
      expect(channelFrom(json).membership.starred, isFalse);
    });

    test('includes the starred preference in channel identity', () {
      expect(
        channelFrom(categoryChannel(starred: true)),
        isNot(channelFrom(categoryChannel())),
      );
    });

    test('keeps a channel starred when its last-read position moves', () {
      final channel = channelFrom(categoryChannel(starred: true));

      expect(
        channel.withLastRead(42, caughtUp: true).membership.starred,
        isTrue,
      );
    });

    test('updates only the reader’s starred membership preference', () {
      final channel = channelFrom(categoryChannel(starred: false));
      final starred = channel.withStarred(true);

      expect(starred.membership.starred, isTrue);
      expect(starred.membership.following, channel.membership.following);
      expect(starred.membership.muted, channel.membership.muted);
      expect(starred.title, channel.title);
      expect(starred.withStarred(false), channel);
    });

    test('changes notification fields without dropping membership state', () {
      final channel = channelFrom(
        categoryChannel(
          muted: true,
          starred: true,
          notificationLevel: 'never',
          lastReadMessageId: 42,
        ),
      );
      final changed = channel.withMembership(
        channel.membership.withNotifications(
          muted: false,
          notificationLevel: ChatChannelNotificationLevel.always,
        ),
      );

      expect(changed.membership.muted, isFalse);
      expect(
        changed.membership.notificationLevel,
        ChatChannelNotificationLevel.always,
      );
      expect(changed.membership.starred, isTrue);
      expect(changed.membership.lastReadMessageId, 42);
      expect(changed.title, channel.title);
      expect(
        changed.withLastRead(43, caughtUp: false).membership.notificationLevel,
        ChatChannelNotificationLevel.always,
      );
    });

    test('reads a channel with no membership row as following nothing', () {
      final channel = channelFrom({'id': 1, 'title': 'x'});

      expect(channel.membership, ChatMembership.none);
      expect(channel.membership.following, isFalse);
    });
  });

  group('the face on a row', () {
    test('is the other person in a one-to-one conversation', () {
      final channel = channelFrom(directChannel());

      expect(channel.avatarUrl, isNotNull);
      expect(channel.users.single.username, 'hawk');
    });

    test('is nobody once there is more than one of them', () {
      // No single face to choose, and Discourse does not stack them either.
      final channel = channelFrom(
        directChannel(
          group: true,
          users: const [
            {'id': 2, 'username': 'hawk', 'avatar_template': '/a/{size}.png'},
            {'id': 3, 'username': 'kris', 'avatar_template': '/b/{size}.png'},
          ],
        ),
      );

      expect(channel.avatarUrl, isNull);
    });

    test('resolves only the first two users needed for a group row', () {
      final channel = channelFrom(
        directChannel(
          group: true,
          users: const [
            {'id': 2, 'username': 'hawk', 'avatar_template': '/a/{size}.png'},
            {'id': 3, 'username': 'kris', 'avatar_template': '/b/{size}.png'},
            {'id': 4, 'username': 'sam', 'avatar_template': '/c/{size}.png'},
          ],
        ),
      );

      expect(ChatChannel.maximumResolvedUsers, 2);
      expect(channel.users.map((user) => user.username), ['hawk', 'kris']);
      expect(
        () => channel.users.add(const ChatUser(id: 5, username: 'pat')),
        throwsUnsupportedError,
      );
      expect(channel.avatarUrl, isNull);
    });

    test('is nobody on a channel, which is a place rather than a person', () {
      expect(channelFrom(categoryChannel()).avatarUrl, isNull);
    });
  });

  group('reading the whole payload', () {
    test('reads the public and the direct lists apart', () {
      final channels = ChatChannel.parse(
        payload(public: [categoryChannel()], direct: [directChannel()]),
        site,
      );

      expect(channels.public.single.id, 9);
      expect(channels.direct.single.id, 12);
    });

    test('folds in the tracking counts, which arrive keyed by a string id', () {
      // `Chat::TrackingStateReport` is a Ruby hash keyed by integer, and JSON
      // object keys are strings — so channel 9 is looked up as '9'. Reading it
      // as an int finds nothing and reports "all read", which is a quiet enough
      // wrong to be worth its own test.
      final channels = ChatChannel.parse(
        payload(
          public: [categoryChannel()],
          tracking: {'9': counts(unread: 3, mentions: 1)},
        ),
        site,
      );

      expect(channels.public.single.tracking.unreadCount, 3);
      expect(channels.public.single.tracking.mentionCount, 1);
    });

    test('counts the unread threads reported separately for each channel', () {
      final channels = ChatChannel.parse(
        payload(
          public: [
            categoryChannel(
              threading: true,
              lastViewedAt: '2026-08-08T10:30:00.000Z',
            ),
          ],
          unreadThreads: {
            '9': {
              '31': '2026-08-08T10:00:00.000Z',
              '32': '2026-08-08T11:00:00.000Z',
            },
          },
        ),
        site,
      );

      expect(channels.public.single.unreadThreadCount, 2);
      expect(channels.public.single.unreadThreadsCountSinceLastViewed, 1);
      expect(
        channels.public.single.lastUnreadThreadAt,
        DateTime.utc(2026, 8, 8, 10),
      );
    });

    test(
      'reads a channel the report skipped as three zeroes, as the site does',
      () {
        final channels = ChatChannel.parse(
          payload(public: [categoryChannel()], tracking: const {}),
          site,
        );

        expect(channels.public.single.tracking, ChatTracking.none);
      },
    );

    test(
      'orders the public channels by slug, which is what the sidebar shows',
      () {
        // The site orders these by lower(name), and a channel's name and slug
        // differ often enough that the two disagree.
        final channels = ChatChannel.parse(
          payload(
            public: [
              categoryChannel(id: 1, title: 'Announcements', slug: 'zebra'),
              categoryChannel(id: 2, title: 'Zoology', slug: 'alpha'),
            ],
          ),
          site,
        );

        expect(channels.public.map((c) => c.id), [2, 1]);
      },
    );

    test('leaves the direct messages in the order the site sent them', () {
      // Already newest-conversation-first server side; re-sorting here could
      // only lose that, since nothing in this step recomputes it.
      final channels = ChatChannel.parse(
        payload(
          direct: [
            directChannel(id: 5, title: 'b'),
            directChannel(id: 6, title: 'a'),
          ],
        ),
        site,
      );

      expect(channels.direct.map((c) => c.id), [5, 6]);
    });

    test('bounds both endpoint buckets before resolving channel state', () {
      final channels = ChatChannel.parse(
        payload(
          public: [
            for (var id = 1; id <= ChatChannel.maximumPublicChannels; id++)
              categoryChannel(
                id: id,
                title: 'Public $id',
                slug: 'public-${id.toString().padLeft(3, '0')}',
              ),
            categoryChannel(id: 999, title: 'Excluded', slug: 'a-excluded'),
          ],
          direct: [
            for (
              var id = 1001;
              id <= 1000 + ChatChannel.maximumDirectMessageChannels;
              id++
            )
              directChannel(id: id, title: 'Direct $id'),
            directChannel(id: 2000, title: 'Excluded', newMessagesLastId: 2000),
          ],
        ),
        site,
      );

      expect(channels.public, hasLength(ChatChannel.maximumPublicChannels));
      expect(channels.public.first.id, 1);
      expect(channels.public.last.id, ChatChannel.maximumPublicChannels);
      expect(
        channels.direct.map((channel) => channel.id),
        List.generate(
          ChatChannel.maximumDirectMessageChannels,
          (index) => 1001 + index,
        ),
      );
      expect(channels.newMessageBusLastIds, isNot(containsPair(999, null)));
      expect(channels.newMessageBusLastIds, isNot(containsPair(2000, 2000)));
      expect(
        () => channels.public.add(channelFrom(categoryChannel(id: 1000))),
        throwsUnsupportedError,
      );
      expect(
        () => channels.direct.add(channelFrom(directChannel(id: 2001))),
        throwsUnsupportedError,
      );
    });

    test('keeps the last message and live cursor beside each channel', () {
      final channels = ChatChannel.parse(
        payload(
          direct: [
            directChannel(
              lastMessageId: 51,
              lastMessageAt: '2026-08-08T12:00:00.000Z',
              newMessagesLastId: 73,
              channelMessageBusLastId: 74,
            ),
          ],
        ),
        site,
      );

      expect(channels.direct.single.lastMessageId, 51);
      expect(channels.newMessageBusLastIds, {12: 73});
      expect(channels.channelMessageBusLastIds, {12: 74});
    });

    test('keeps the global chat cursors from the same snapshot', () {
      final channels = ChatChannel.parse(
        payload(
          newChannelLastId: 80,
          userTrackingLastId: 81,
          userHasThreadsLastId: 82,
          hasThreads: true,
        ),
        site,
      );

      expect(channels.newChannelBusLastId, 80);
      expect(channels.userTrackingBusLastId, 81);
      expect(channels.userHasThreadsBusLastId, 82);
      expect(channels.hasThreads, isTrue);
    });

    test('reads an empty payload as no channels rather than as a failure', () {
      final channels = ChatChannel.parse(payload(), site);

      expect(channels.public, isEmpty);
      expect(channels.direct, isEmpty);
    });

    test('reads the online users and cursor from global chat presence', () {
      final channels = ChatChannel.parse(
        payload(
          presence: {
            'count': 2,
            'last_message_id': 47,
            'users': [
              {'id': 2, 'username': 'hawk'},
              {'id': 3, 'username': 'kris'},
            ],
          },
        ),
        site,
      );

      expect(channels.presence.userIds, {2, 3});
      expect(channels.presence.lastMessageId, 47);
    });

    test('applies presence joins and leaves by user id', () {
      const held = ChatPresence(userIds: {2, 3}, lastMessageId: 47);

      final updated = held.withMessage({
        'entering_users': [
          {'id': 4, 'username': 'sam'},
        ],
        'leaving_user_ids': [2],
      });

      expect(updated.userIds, {3, 4});
      expect(updated.lastMessageId, 47);
    });
  });

  group('what a row says about unread', () {
    ChatChannel withCounts(
      Map<String, dynamic> json, {
      int unread = 0,
      int mentions = 0,
      int watchedThreads = 0,
    }) => ChatChannel.fromJson(
      json,
      site,
      tracking: ChatTracking(
        unreadCount: unread,
        mentionCount: mentions,
        watchedThreadsUnreadCount: watchedThreads,
      ),
    );

    test('says nothing when there is nothing unread', () {
      expect(withCounts(categoryChannel()).badge.isVisible, isFalse);
    });

    test(
      'is quiet for an unread public channel, which is not addressed to you',
      () {
        final badge = withCounts(categoryChannel(), unread: 4).badge;

        expect(badge.dot, isTrue);
        expect(badge.urgent, isFalse);
      },
    );

    test('is urgent for a mention, which is', () {
      final badge = withCounts(categoryChannel(), unread: 4, mentions: 1).badge;

      expect(badge.urgent, isTrue);
    });

    test(
      'is urgent for an unread direct message, addressed to you by construction',
      () {
        final badge = withCounts(directChannel(), unread: 1).badge;

        expect(badge.dot, isTrue);
        expect(badge.urgent, isTrue);
      },
    );

    test('is urgent for an unread watched thread', () {
      expect(
        withCounts(categoryChannel(), watchedThreads: 1).badge.urgent,
        isTrue,
      );
    });

    test('hides thread activity from before the channel was viewed', () {
      final channel = ChatChannel.parse(
        payload(
          public: [
            categoryChannel(
              threading: true,
              lastViewedAt: '2026-08-08T11:00:00.000Z',
            ),
          ],
          unreadThreads: {
            '9': {'31': '2026-08-08T10:00:00.000Z'},
          },
        ),
        site,
      ).public.single;

      expect(channel.unreadThreadCount, 1);
      expect(channel.unreadThreadsCountSinceLastViewed, 0);
      expect(channel.badge.isVisible, isFalse);
    });

    test(
      'says nothing at all for a muted channel, which is what muting means',
      () {
        final channel = ChatChannel.parse(
          payload(
            public: [categoryChannel(muted: true)],
            tracking: {'9': counts(unread: 9, mentions: 2)},
          ),
          site,
        ).public.single;

        expect(channel.badge.isVisible, isFalse);
      },
    );

    test('draws a dot rather than a number, whatever the count', () {
      expect(withCounts(categoryChannel(), unread: 99).badge.count, 0);
    });
  });

  test(
    'a settings response preserves tracking the route does not serialize',
    () {
      final unreadAt = DateTime.utc(2026, 8, 25, 10);
      final lastMessageAt = DateTime.utc(2026, 8, 25, 9);
      final held = ChatChannel(
        id: 9,
        title: 'Bugs',
        kind: ChatChannelKind.category,
        slug: 'bugs',
        description: 'Old description',
        membership: const ChatMembership(
          following: true,
          starred: true,
          lastReadMessageId: 40,
        ),
        tracking: const ChatTracking(unreadCount: 3, mentionCount: 1),
        unreadThreadOverview: {77: unreadAt},
        threadingEnabled: true,
        lastMessageId: 50,
        lastMessageAt: lastMessageAt,
      );
      const incoming = ChatChannel(
        id: 9,
        title: 'Bug reports',
        kind: ChatChannelKind.category,
        slug: 'bug-reports',
        description: 'New description',
        membership: ChatMembership(following: true),
        threadingEnabled: true,
      );

      final updated = held.withServerSettings(incoming);

      expect(updated.title, 'Bug reports');
      expect(updated.slug, 'bug-reports');
      expect(updated.description, 'New description');
      expect(updated.tracking, held.tracking);
      expect(updated.unreadThreadOverview, {77: unreadAt});
      expect(updated.lastMessageId, 50);
      expect(updated.lastMessageAt, lastMessageAt);
    },
  );

  group('route ids', () {
    test(
      'round-trips a channel id through the id its sidebar entry carries',
      () {
        expect(ChatChannel.channelIdIn(ChatChannel.routeId(42)), 42);
      },
    );

    test('claims no route it did not write', () {
      expect(ChatChannel.channelIdIn('latest'), isNull);
      expect(ChatChannel.channelIdIn('topic-42'), isNull);
      expect(ChatChannel.channelIdIn('messages'), isNull);
    });

    test(
      'claims nothing from a route that only starts like one of its own',
      () {
        expect(ChatChannel.channelIdIn('chat-c-'), isNull);
        expect(ChatChannel.channelIdIn('chat-c-abc'), isNull);
      },
    );
  });
}
