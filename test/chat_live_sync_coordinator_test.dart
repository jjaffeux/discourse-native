import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/live_channels.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_live_sync_coordinator.dart';
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
  });
}

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
        channelFor: (_, channelId) => channelId == 9 ? _channel : null,
        messageFor: (_, _) => null,
        threadFor: (_, threadId) => threadId == 22 ? _thread : null,
        hasThreads: (_) => hasThreads,
        putChannel: (_, _) {},
        putMessage: (_, _) {},
        putLiveMessage: (_, _, _) {},
        putThread: (_, _) {},
        publishNotificationChange: (_, _, _) {},
        notifyCanonicalChange: () {},
        removeKickedChannelState: (_, _) {},
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
        streamContainsMessage: (_, _, _) => false,
        admitLiveMessage: (_, _, _) {},
        bumpStreamsHolding: (_, _) {},
        setLoadedThreadOriginalDeleted: (_, _, _, _, _) {},
        scheduleThreadDetailRefresh: (_, _) {},
        applyDeleteMutation: (_, _, _, _) {},
        applyBulkDeleteMutation: (_, _, _, _, _) {},
        applyReactionMutation: (_, _) {},
        applyPinMutation: (_, _, _) {},
        applySelfFlagMutation: (_, _) {},
        applyFlagMutation: (_, _) {},
        showStreamNotice: (_, _, _) {},
        reconcileSentEvent: (_, _, _) {},
        attachReconciliationTracker: (_, _) {},
        cancelReconciliationChannel: (_, _) {},
        forgetReconciliation: (_) {},
        disposeReconciliation: () {},
        report: (_, _, _, _) {},
      ),
    );
  }

  final _Requests requests;
  late final ChatLiveSyncCoordinator coordinator;
  final List<String> newMessages = [];
  bool hasThreads = false;
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
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async =>
      (apiKey: 'key', failure: null);
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
