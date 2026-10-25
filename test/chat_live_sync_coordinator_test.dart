import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/live_channels.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_live_sync_coordinator.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';

void main() {
  group('ChatLiveSyncCoordinator', () {
    test('attaches the complete snapshot from its canonical cursors', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();

      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);

      expect(tracker.lastId('/presence/chat/online'), 47);
      expect(tracker.lastId('/chat/new-channel'), 60);
      expect(tracker.lastId('/chat/channel-metadata'), 61);
      expect(tracker.lastId('/chat/channel-edits'), 62);
      expect(tracker.lastId('/chat/channel-status'), 63);
      expect(tracker.lastId('/chat/user-tracking-state/7'), 64);
      expect(tracker.lastId('/chat/bulk-user-tracking-state/7'), 64);
      expect(tracker.lastId('/chat/user-has-threads/7'), 65);
      expect(tracker.lastId('/chat/9/new-messages'), 51);
      expect(tracker.lastId('/chat/9/new-mentions'), 52);
      expect(tracker.lastId('/chat/9/kick'), 53);
    });

    test(
      'tracker replacement cancels once, resumes applied cursors, and rejects late events',
      () {
        final fixture = _Fixture();
        addTearDown(fixture.coordinator.dispose);
        final first = _LiveChannels();
        final replacement = _LiveChannels();
        fixture.coordinator.replace(_site, _snapshot());
        fixture.coordinator.attachTracker(_site, first);

        first.deliver(
          '/chat/9/new-messages',
          _newMessageEvent(101),
          messageId: 80,
        );
        expect(fixture.newMessages, ['101']);

        fixture.coordinator.attachTracker(_site, replacement);

        expect(
          first.registrations.every((entry) => entry.cancelCalls == 1),
          isTrue,
        );
        expect(replacement.lastId('/chat/9/new-messages'), 80);
        first.deliver(
          '/chat/9/new-messages',
          _newMessageEvent(102),
          messageId: 81,
        );
        replacement.deliver(
          '/chat/9/new-messages',
          _newMessageEvent(103),
          messageId: 82,
        );
        expect(fixture.newMessages, ['101', '103']);

        fixture.coordinator.forget(_site);
        fixture.coordinator.dispose();
        expect(
          first.registrations.every((entry) => entry.cancelCalls == 1),
          isTrue,
        );
        expect(
          replacement.registrations.every((entry) => entry.cancelCalls == 1),
          isTrue,
        );
      },
    );

    test('snapshot replacement retains a later applied cursor', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);
      final old = tracker.latest('/chat/9/new-messages');

      tracker.deliver(
        '/chat/9/new-messages',
        _newMessageEvent(101),
        messageId: 80,
      );
      fixture.coordinator.replace(_site, _snapshot(newMessagesCursor: 70));

      expect(old.cancelCalls, 1);
      expect(tracker.lastId('/chat/9/new-messages'), 80);
      old.deliver(_newMessageEvent(102), 81);
      expect(fixture.newMessages, ['101']);
    });

    test('a stale account generation rejects delivery until reattachment', () {
      final requests = _Requests();
      final fixture = _Fixture(requests: requests);
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);
      final stale = tracker.latest('/chat/9/new-messages');

      requests.rotate();
      stale.deliver(_newMessageEvent(101), 70);
      fixture.coordinator.attachTracker(_site, tracker);

      expect(stale.cancelCalls, 1);
      tracker.latest('/chat/9/new-messages').deliver(_newMessageEvent(102), 71);
      expect(fixture.newMessages, ['102']);
    });

    test('muting stops only the new-messages stream, and unmuting restarts '
        'it from the fresh cursor it is given', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(
        _site,
        ChatChannels(
          public: [
            _channel.withMembership(
              const ChatMembership(following: true, muted: true),
            ),
          ],
          newMessageBusLastIds: const {9: 51},
          newMentionMessageBusLastIds: const {9: 52},
          kickMessageBusLastIds: const {9: 53},
        ),
      );
      fixture.coordinator.attachTracker(_site, tracker);

      expect(tracker.registrationsFor('/chat/9/new-messages'), isEmpty);
      expect(fixture.coordinator.ownsChannelMessages(_site, 9), isFalse);
      expect(tracker.lastId('/chat/9/new-mentions'), 52);
      expect(tracker.lastId('/chat/9/kick'), 53);

      fixture.coordinator.unmuteChannel(
        _site,
        const ChatChannel(
          id: 9,
          title: 'Bugs',
          kind: ChatChannelKind.category,
          membership: ChatMembership(following: true),
          messageBus: ChatChannelMessageBusState(newMessages: 90),
        ),
      );
      final resumed = tracker.latest('/chat/9/new-messages');
      expect(resumed.lastId, 90);
      expect(tracker.registrationsFor('/chat/9/new-mentions'), hasLength(1));

      fixture.coordinator.muteChannel(_site, 9);

      expect(resumed.cancelCalls, 1);
      expect(fixture.coordinator.ownsChannelMessages(_site, 9), isFalse);
      expect(tracker.latest('/chat/9/new-mentions').cancelCalls, 0);
      expect(tracker.latest('/chat/9/kick').cancelCalls, 0);
      resumed.deliver(_newMessageEvent(101), 91);
      expect(fixture.newMessages, isEmpty);
    });

    test('overlapping view tokens share and release one root subscription', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);

      final first = fixture.coordinator.beginViewingChannel(_site, 9);
      final second = fixture.coordinator.beginViewingChannel(_site, 9);
      final root = tracker.latest('/chat/9');
      expect(tracker.registrationsFor('/chat/9'), hasLength(1));

      fixture.coordinator.endViewingChannel(_site, 9, first);
      expect(root.cancelCalls, 0);
      fixture.coordinator.endViewingChannel(_site, 9, second);
      expect(root.cancelCalls, 1);
    });

    test('overlapping channel and thread views retain their shared root', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);
      const target = ChatThreadTarget(channelId: 9, threadId: 22);

      final channelToken = fixture.coordinator.beginViewingChannel(_site, 9);
      final threadToken = fixture.coordinator.beginViewingThread(_site, target);
      final root = tracker.latest('/chat/9');
      final thread = tracker.latest('/chat/9/thread/22');

      expect(tracker.registrationsFor('/chat/9'), hasLength(1));
      expect(thread.lastId, 77);
      fixture.coordinator.endViewingChannel(_site, 9, channelToken);
      expect(root.cancelCalls, 0);
      fixture.coordinator.endViewingThread(_site, target, threadToken);
      expect(root.cancelCalls, 1);
      expect(thread.cancelCalls, 1);
    });

    for (final threadStream in [false, true]) {
      final stream = threadStream ? '/chat/9/thread/22' : '/chat/9';
      final target = threadStream ? _threadTarget : const ChatChannelTarget(9);
      for (final type in ['sent', 'processed', 'edit', 'refresh', 'restore']) {
        test('$stream applies $type with its staged reconciliation order', () {
          final fixture = _Fixture();
          final tracker = _viewStreams(fixture);
          final event = _messageEvent(type, threadId: threadStream ? 22 : null)
            ..['staged_id'] = 'draft-1';

          tracker.deliver(stream, event, messageId: 100);

          expect(fixture.effects, [
            ['put', 101, true],
            if (threadStream && type == 'restore') ['bump', 101],
            if (type == 'sent') ['admit', target, 101],
            ['reconcile', target, event],
            if (!threadStream && type == 'restore') ...[
              ['bump', 101],
              ['originalDeleted', 9, 101, null, true],
            ],
          ]);
          expect(fixture.liveMessages.single.channelId, 9);
          expect(
            fixture.liveMessages.single.threadId,
            threadStream ? 22 : null,
          );
          expect(fixture.liveMessages.single.cooked, '<p>101</p>');
          expect(
            identical(
              fixture.effects
                  .firstWhere((effect) => effect.first == 'reconcile')
                  .last,
              event,
            ),
            isTrue,
          );
        });
      }

      test(
        '$stream admits sent only when absent and ignores non-string staged ids',
        () {
          final fixture = _Fixture()..containsMessage = true;
          final tracker = _viewStreams(fixture);
          for (final type in [
            'sent',
            'processed',
            'edit',
            'refresh',
            'restore',
          ]) {
            fixture.effects.clear();
            tracker.deliver(
              stream,
              _messageEvent(type, threadId: threadStream ? 22 : null)
                ..['staged_id'] = 123,
              messageId: 100,
            );
            expect(fixture.effects, [
              ['put', 101, true],
              if (type == 'restore') ...[
                ['bump', 101],
                if (!threadStream) ['originalDeleted', 9, 101, null, true],
              ],
            ], reason: type);
          }
        },
      );

      test('$stream rejects malformed messages and unknown events', () {
        final fixture = _Fixture();
        final tracker = _viewStreams(fixture);
        final invalid = <Object?>[
          null,
          [],
          {'type': 'sent'},
          {'type': 'sent', 'chat_message': <Object?>[]},
          _messageEvent('sent', id: 0, threadId: threadStream ? 22 : null),
          _messageEvent('sent', id: -1, threadId: threadStream ? 22 : null),
          _messageEvent(
            'sent',
            channelId: 8,
            threadId: threadStream ? 22 : null,
          ),
          _messageEvent('unknown', threadId: threadStream ? 22 : null),
          if (threadStream) ...[
            _messageEvent('sent'),
            _messageEvent('sent', threadId: 23),
          ],
        ];
        for (final event in invalid) {
          tracker.deliver(stream, event, messageId: 100);
          expect(fixture.effects, isEmpty, reason: '$event');
        }
      });
    }

    test(
      'root replies require a matching preview while thread replies do not',
      () {
        final fixture = _Fixture();
        final tracker = _viewStreams(fixture);
        for (final preview in <Object?>[
          null,
          {'id': 23},
          {'id': 22},
        ]) {
          final event = _messageEvent('edit', threadId: 22);
          (event['chat_message'] as Map<String, dynamic>)['thread'] = preview;
          fixture.effects.clear();
          tracker.deliver('/chat/9', event, messageId: 100);
          expect(
            fixture.effects,
            preview is Map<String, dynamic> && preview['id'] == 22
                ? [
                    ['put', 101, true],
                  ]
                : isEmpty,
          );
          fixture.effects.clear();
          tracker.deliver('/chat/9/thread/22', event, messageId: 100);
          expect(fixture.effects, [
            ['put', 101, true],
          ]);
        }
      },
    );

    test(
      'only root handles thread creation and keeps its relaxed message id rule',
      () {
        final fixture = _Fixture();
        final tracker = _viewStreams(fixture);
        for (final id in [0, -1]) {
          final event = _messageEvent('thread_created', id: id, threadId: 23);
          (event['chat_message'] as Map<String, dynamic>)['thread'] = {
            'id': 22,
          };
          fixture.effects.clear();
          tracker.deliver('/chat/9', event, messageId: 100);
          expect(fixture.effects, [
            ['put', id, true],
          ]);
          fixture.effects.clear();
          tracker.deliver('/chat/9/thread/22', event, messageId: 100);
          expect(fixture.effects, isEmpty);
        }
        tracker.deliver(
          '/chat/9',
          _messageEvent('thread_created'),
          messageId: 100,
        );
        final wrongChannel = _messageEvent('thread_created', channelId: 8);
        (wrongChannel['chat_message'] as Map<String, dynamic>)['thread'] = {
          'id': 22,
        };
        tracker.deliver('/chat/9', wrongChannel, messageId: 100);
        expect(fixture.effects, isEmpty);
      },
    );

    test('thread suppresses every message update for its loaded original', () {
      final fixture = _Fixture();
      final tracker = _viewStreams(fixture);
      for (final type in ['sent', 'processed', 'edit', 'refresh', 'restore']) {
        tracker.deliver(
          '/chat/9/thread/22',
          _messageEvent(type, id: 90)..['staged_id'] = 'original',
          messageId: 100,
        );
      }
      expect(fixture.effects, isEmpty);
      tracker.deliver(
        '/chat/9',
        _messageEvent('restore', id: 90),
        messageId: 100,
      );
      expect(fixture.effects, [
        ['put', 90, true],
        ['bump', 90],
        ['originalDeleted', 9, 90, null, true],
      ]);
    });

    test(
      'root and thread retain mutation payloads, ownership and bulk skip ids',
      () {
        final fixture = _Fixture();
        final tracker = _viewStreams(fixture);
        for (final type in [
          'delete',
          'bulk_delete',
          'reaction',
          'pin',
          'unpin',
          'self_flagged',
          'flag',
        ]) {
          final event = <String, dynamic>{
            'type': type,
            'deleted_id': '101',
            'deleted_ids': [90, '101', 'invalid'],
            'chat_message_id': '101',
            'deleted_at': '2026-08-07T10:00:00.000Z',
          };
          final mutation = switch (type) {
            'pin' || 'unpin' => 'pin',
            _ => type,
          };
          for (final threadStream in [false, true]) {
            fixture.effects.clear();
            tracker.deliver(
              threadStream ? '/chat/9/thread/22' : '/chat/9',
              event,
              messageId: 100,
            );
            expect(fixture.effects.first, [
              mutation,
              event,
              if (['delete', 'bulk_delete', 'pin', 'unpin'].contains(type)) 9,
              if (['delete', 'bulk_delete'].contains(type))
                threadStream ? fixture.heldThread : null,
              if (type == 'bulk_delete') threadStream ? 90 : null,
            ]);
            expect(identical(fixture.effects.first[1], event), isTrue);
            expect(
              fixture.effects.skip(1),
              !threadStream && type == 'delete'
                  ? [
                      [
                        'originalDeleted',
                        9,
                        101,
                        DateTime.utc(2026, 8, 7, 10),
                        false,
                      ],
                    ]
                  : !threadStream && type == 'bulk_delete'
                  ? [
                      [
                        'originalDeleted',
                        9,
                        90,
                        DateTime.utc(2026, 8, 7, 10),
                        false,
                      ],
                      [
                        'originalDeleted',
                        9,
                        101,
                        DateTime.utc(2026, 8, 7, 10),
                        false,
                      ],
                    ]
                  : isEmpty,
            );
          }
          if (type != 'bulk_delete') {
            fixture.effects.clear();
            event['deleted_id'] = '90';
            event['chat_message_id'] = '90';
            tracker.deliver('/chat/9/thread/22', event, messageId: 100);
            expect(fixture.effects, isEmpty, reason: type);
            tracker.deliver('/chat/9', event, messageId: 100);
            expect(fixture.effects.first.first, mutation, reason: type);
          }
        }
      },
    );

    test('a mention counts only above the read cursor', () {
      final fixture = _Fixture()
        ..channel = _channel.withMembership(
          const ChatMembership(following: true, lastReadMessageId: 100),
        );
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);

      for (final messageId in [99, 100, 101]) {
        tracker.deliver('/chat/9/new-mentions', {
          'channel_id': 9,
          'message_id': messageId,
        }, messageId: messageId);
      }
      tracker.deliver('/chat/9/new-mentions', {
        'channel_id': 8,
        'message_id': 200,
      }, messageId: 102);

      expect(fixture.putChannels.map((c) => c.tracking.mentionCount), [1]);
    });

    test('a new message counts as unread only above the read cursor', () {
      final fixture = _Fixture()
        ..channel = _channel.withMembership(
          const ChatMembership(following: true, lastReadMessageId: 100),
        );
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);

      for (final messageId in [100, 101]) {
        tracker.deliver(
          '/chat/9/new-messages',
          _newMessageEvent(messageId),
          messageId: messageId,
        );
      }

      expect(fixture.putChannels.map((c) => c.tracking.unreadCount), [0, 1]);
    });

    test(
      'a thread reply counts by the reader\'s thread notification level',
      () {
        final fixture = _Fixture()
          ..channel = ChatChannel(
            id: 9,
            title: 'Bugs',
            kind: ChatChannelKind.category,
            membership: const ChatMembership(following: true),
            threadingEnabled: true,
            messageBus: _channel.messageBus,
          );
        addTearDown(fixture.coordinator.dispose);
        final tracker = _LiveChannels();
        fixture.coordinator.replace(_site, _snapshot());
        fixture.coordinator.attachTracker(_site, tracker);

        for (final level in [
          ChatThreadNotificationLevel.normal,
          ChatThreadNotificationLevel.tracking,
          ChatThreadNotificationLevel.watching,
        ]) {
          fixture.heldThread = _thread.copyWith(
            membership: ChatThreadMembership(
              threadId: 22,
              notificationLevel: level,
              lastReadMessageId: 50,
            ),
          );
          tracker.deliver('/chat/9/new-messages', {
            ..._newMessageEvent(101),
            'type': 'thread',
            'thread_id': 22,
          }, messageId: 80);
        }

        expect(
          fixture.putThreads.map(
            (thread) => (
              thread.tracking.unreadCount,
              thread.tracking.watchedThreadsUnreadCount,
            ),
          ),
          [(0, 0), (1, 0), (0, 1)],
        );
        expect(fixture.newMessages, isEmpty);
      },
    );

    test('a thread reply in an unthreaded channel is ignored', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);

      tracker.deliver('/chat/9/new-messages', {
        ..._newMessageEvent(101),
        'type': 'thread',
        'thread_id': 22,
      }, messageId: 80);

      expect(fixture.putChannels, isEmpty);
      expect(fixture.putThreads, isEmpty);
    });

    test('forgetting a site drops its delivered cursors', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);
      tracker.deliver(
        '/chat/9/new-messages',
        _newMessageEvent(101),
        messageId: 80,
      );

      fixture.coordinator.forget(_site);
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);

      expect(tracker.lastId('/chat/9/new-messages'), 51);
    });

    test('a kick removes only a channel the reader still holds', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);
      final kick = tracker.latest('/chat/9/kick');

      fixture.channel = null;
      kick.deliver({'channel_id': 9}, 54);
      expect(fixture.kicked, isEmpty);
      expect(kick.cancelCalls, 0);

      fixture.channel = _channel;
      kick.deliver({'channel_id': 8}, 55);
      expect(fixture.kicked, isEmpty);
      kick.deliver({'channel_id': 9}, 56);
      expect(fixture.kicked, [9]);
      expect(kick.cancelCalls, 1);
    });

    test('unmuting a stream it already owns keeps the delivered cursor', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);
      tracker.deliver(
        '/chat/9/new-messages',
        _newMessageEvent(101),
        messageId: 80,
      );

      fixture.coordinator.unmuteChannel(
        _site,
        const ChatChannel(
          id: 9,
          title: 'Bugs',
          kind: ChatChannelKind.category,
          membership: ChatMembership(following: true),
          messageBus: ChatChannelMessageBusState(newMessages: 90),
        ),
      );
      final replacement = _LiveChannels();
      fixture.coordinator.attachTracker(_site, replacement);

      expect(tracker.registrationsFor('/chat/9/new-messages'), hasLength(1));
      expect(replacement.lastId('/chat/9/new-messages'), 80);
    });

    test('contiguous presence ids apply their diffs', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);
      final online = fixture.coordinator.onlineUserIdsListenable(_site);

      tracker.deliver('/presence/chat/online', {
        'entering_users': [
          {'id': 5, 'username': 'e'},
        ],
      }, messageId: 48);
      tracker.deliver('/presence/chat/online', {
        'leaving_user_ids': [2],
      }, messageId: 49);

      expect(online.value, {5});
      expect(fixture.resyncs, isEmpty);
    });

    test('a presence id gap asks for one snapshot instead of applying its '
        'diffs', () {
      final fixture = _Fixture();
      addTearDown(fixture.coordinator.dispose);
      final tracker = _LiveChannels();
      fixture.coordinator.replace(_site, _snapshot());
      fixture.coordinator.attachTracker(_site, tracker);
      final online = fixture.coordinator.onlineUserIdsListenable(_site);

      // The snapshot read to 47; the site trimmed 48..147 from its backlog,
      // among them user 2 leaving, so the resumed poll starts at 148.
      tracker.deliver('/presence/chat/online', {
        'entering_users': [
          {'id': 5, 'username': 'e'},
        ],
      }, messageId: 148);
      tracker.deliver('/presence/chat/online', {
        'entering_users': [
          {'id': 6, 'username': 'f'},
        ],
      }, messageId: 149);
      tracker.deliver('/presence/chat/online', {
        'leaving_user_ids': [5],
      }, messageId: 150);

      expect(online.value, {2});
      expect(fixture.coordinator.isOnline(_site, 5), isFalse);
      expect(fixture.resyncs, [_site]);

      fixture.coordinator.replace(
        _site,
        const ChatChannels(
          public: [_channel],
          presence: ChatPresence(userIds: {6}, lastMessageId: 150),
        ),
      );
      expect(online.value, {6});
      expect(tracker.lastId('/presence/chat/online'), 150);

      tracker.deliver('/presence/chat/online', {
        'entering_users': [
          {'id': 7, 'username': 'g'},
        ],
      }, messageId: 151);
      expect(online.value, {6, 7});
      expect(fixture.resyncs, [_site]);
    });
  });
}

const _threadTarget = ChatThreadTarget(channelId: 9, threadId: 22);

_LiveChannels _viewStreams(_Fixture fixture) {
  addTearDown(fixture.coordinator.dispose);
  final tracker = _LiveChannels();
  fixture.coordinator.replace(_site, _snapshot());
  fixture.coordinator.attachTracker(_site, tracker);
  fixture.coordinator.beginViewingThread(_site, _threadTarget);
  return tracker;
}

Map<String, dynamic> _messageEvent(
  String type, {
  int id = 101,
  int channelId = 9,
  int? threadId,
}) => {
  'type': type,
  'chat_message': {
    'id': id,
    'chat_channel_id': channelId,
    'thread_id': threadId,
    'cooked': '<p>$id</p>',
  },
};

const _channel = ChatChannel(
  id: 9,
  title: 'Bugs',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
  messageBus: ChatChannelMessageBusState(
    channel: 50,
    newMessages: 41,
    newMentions: 42,
    kick: 43,
  ),
);

const _thread = ChatThread(
  id: 22,
  channelId: 9,
  status: 'open',
  replyCount: 2,
  messageBusLastId: 77,
);

ChatChannels _snapshot({int newMessagesCursor = 51}) => ChatChannels(
  public: const [_channel],
  presence: const ChatPresence(userIds: {2}, lastMessageId: 47),
  newMessageBusLastIds: {9: newMessagesCursor},
  newMentionMessageBusLastIds: const {9: 52},
  kickMessageBusLastIds: const {9: 53},
  channelMessageBusLastIds: const {9: 54},
  newChannelBusLastId: 60,
  channelMetadataBusLastId: 61,
  channelEditsBusLastId: 62,
  channelStatusBusLastId: 63,
  userTrackingBusLastId: 64,
  userHasThreadsBusLastId: 65,
);

Map<String, dynamic> _newMessageEvent(int messageId) => {
  'type': 'channel',
  'channel_id': 9,
  'message': {
    'id': messageId,
    'chat_channel_id': 9,
    'created_at': '2026-08-08T10:00:00.000Z',
    'cooked': '<p>$messageId</p>',
    'user': {'id': 2, 'username': 'author'},
  },
};

final class _Fixture {
  _Fixture({_Requests? requests}) : requests = requests ?? _Requests() {
    coordinator = ChatLiveSyncCoordinator(
      requests: this.requests,
      host: ChatLiveSyncHost(
        isDisposed: () => false,
        clock: () => DateTime.utc(2026, 8, 8),
        currentUserFor: (_) =>
            const DiscourseUser(id: 7, username: 'reader', staff: false),
        channelFor: (_, channelId) => channelId == 9 ? channel : null,
        messageFor: (_, _) => null,
        threadFor: (_, threadId) => threadId == 22 ? heldThread : null,
        hasThreads: (_) => hasThreads,
        putChannel: (_, channel) => putChannels.add(channel),
        didReceiveTrackingState: (_, _) {},
        didReceiveChannelEdit: (_, _) {},
        didReceiveChannelStatus: (_, _) {},
        putMessage: (_, _) {},
        putLiveMessage: (_, message, preserve) {
          liveMessages.add(message);
          effects.add(['put', message.id, preserve]);
        },
        putThread: (_, thread) => putThreads.add(thread),
        publishNotificationChange: (_, _, _) {},
        notifyCanonicalChange: () {},
        removeKickedChannelState: (_, channelId) => kicked.add(channelId),
        isChannelListed: (_, _) => false,
        resolvePartialChannel: (_, _) {},
        insertListedChannel: (_, _) {},
        advanceLastViewedAt: (_, _) {},
        beginChannelFollow: (_, _) => Object(),
        ownsChannelFollow: (_, _, _) => true,
        endChannelFollow: (_, _, _) {},
        followChannel: (_, _, _, _) async =>
            const ChatMembership(following: true),
        revealThreads: (_) => hasThreads = true,
        admitActivityMessage: (_, _, message) {
          newMessages.add('${message.id}');
        },
        streamContainsMessage: (_, _, _) => containsMessage,
        admitLiveMessage: (_, target, message) =>
            effects.add(['admit', target, message.id]),
        bumpStreamsHolding: (_, id) => effects.add(['bump', id]),
        setLoadedThreadOriginalDeleted: (_, channelId, id, deletedAt, clear) =>
            effects.add(['originalDeleted', channelId, id, deletedAt, clear]),
        scheduleThreadDetailRefresh: (_, _) {},
        applyDeleteMutation: (_, data, channelId, thread) =>
            effects.add(['delete', data, channelId, thread]),
        applyBulkDeleteMutation: (_, data, channelId, thread, skip) =>
            effects.add(['bulk_delete', data, channelId, thread, skip]),
        applyReactionMutation: (_, data) => effects.add(['reaction', data]),
        applyPinMutation: (_, data, channelId) =>
            effects.add(['pin', data, channelId]),
        applySelfFlagMutation: (_, data) => effects.add(['self_flagged', data]),
        applyFlagMutation: (_, data) => effects.add(['flag', data]),
        showStreamNotice: (_, _, _) {},
        reconcileSentEvent: (_, target, data) =>
            effects.add(['reconcile', target, data]),
        attachReconciliationTracker: (_, _) {},
        cancelReconciliationChannel: (_, _) {},
        forgetReconciliation: (_) {},
        disposeReconciliation: () {},
        resyncChannels: resyncs.add,
      ),
    );
  }

  final _Requests requests;
  late final ChatLiveSyncCoordinator coordinator;
  ChatChannel? channel = _channel;
  final List<int> kicked = [];
  final List<ChatThread> putThreads = [];
  final List<ChatChannel> putChannels = [];
  final List<String> newMessages = [];
  final List<String> resyncs = [];
  bool hasThreads = false;
  bool containsMessage = false;
  final List<List<Object?>> effects = [];
  final List<ChatMessage> liveMessages = [];
  ChatThread heldThread = _thread.copyWith(
    originalMessage: const ChatThreadOriginalMessage(
      id: 90,
      channelId: 9,
      author: ChatMessageAuthor(id: 2, username: 'author'),
    ),
  );
}

final class _Requests implements PluginRequestHost {
  int _generation = 0;

  void rotate() => _generation++;

  @override
  PluginSiteLease capture(String siteUrl) => _Lease(this, _generation);

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      const PluginRequestCredentials(apiKey: 'key', clientId: 'client');

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async => (
    credentials: const PluginRequestCredentials(apiKey: 'key', clientId: ''),
    failure: null,
  );
}

final class _Lease implements PluginSiteLease {
  const _Lease(this._requests, this._generation);

  final _Requests _requests;
  final int _generation;

  @override
  bool get isCurrent => _requests._generation == _generation;

  @override
  bool commit(void Function() mutation) {
    if (!isCurrent) return false;
    mutation();
    return true;
  }
}

final class _LiveChannels implements PluginLiveChannelHandle {
  final List<_Registration> registrations = [];

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    final registration = _Registration(channel, lastId, onMessage);
    registrations.add(registration);
    return registration;
  }

  List<_Registration> registrationsFor(String channel) => [
    for (final registration in registrations)
      if (registration.channel == channel) registration,
  ];

  _Registration latest(String channel) => registrationsFor(channel).last;

  int? lastId(String channel) => latest(channel).lastId;

  void deliver(String channel, Object? data, {required int messageId}) =>
      latest(channel).deliver(data, messageId);
}

final class _Registration implements PluginLiveChannelSubscription {
  _Registration(this.channel, this.lastId, this._onMessage);

  final String channel;
  final int? lastId;
  final void Function(Object? data, int messageId) _onMessage;
  int cancelCalls = 0;

  void deliver(Object? data, int messageId) => _onMessage(data, messageId);

  @override
  void cancel() => cancelCalls++;
}
