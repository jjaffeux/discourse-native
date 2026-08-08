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
  int? lastReadMessageId,
  bool threading = false,
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
  'current_user_membership': {
    'following': true,
    'muted': muted,
    'last_read_message_id': ?lastReadMessageId,
  },
};

/// A direct channel, whose `chatable` is people rather than a category.
Map<String, dynamic> directChannel({
  int id = 12,
  String title = 'hawk',
  bool group = false,
  List<Map<String, dynamic>>? users,
  String? lastMessageAt,
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
  'last_message': {'id': 40, 'created_at': ?lastMessageAt},
  'current_user_membership': {'following': true, 'muted': false},
};

Map<String, dynamic> payload({
  List<Map<String, dynamic>> public = const [],
  List<Map<String, dynamic>> direct = const [],
  Map<String, dynamic>? tracking,
}) => {
  'public_channels': public,
  'direct_message_channels': direct,
  'tracking': {
    'channel_tracking': tracking ?? const <String, dynamic>{},
    'thread_tracking': <String, dynamic>{},
  },
  'meta': {'message_bus_last_ids': <String, dynamic>{}},
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

    test('reads no colour at all from something that is not one', () {
      expect(channelFrom(categoryChannel(color: 'nope')).categoryColor, isNull);
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

    test('reads a channel with no membership row as following nothing', () {
      final channel = channelFrom({'id': 1, 'title': 'x'});

      expect(channel.membership, ChatMembership.none);
      expect(channel.membership.following, isFalse);
    });
  });

  group('the face on a row', () {
    test('is the other person in a one-to-one conversation', () {
      expect(channelFrom(directChannel()).avatarUrl, isNotNull);
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

    test('reads an empty payload as no channels rather than as a failure', () {
      final channels = ChatChannel.parse(payload(), site);

      expect(channels.public, isEmpty);
      expect(channels.direct, isEmpty);
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
