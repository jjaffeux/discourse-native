import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/live_channels.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_send_coordinator.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  group('DefaultChatSendCoordinator', () {
    test('stages synchronously and pumps each stream in FIFO order', () async {
      final sendGate = Completer<void>();
      final api = FakeDiscourseApi(
        chatSendGate: sendGate,
        chatSentMessageId: 42,
      );
      final requests = _Requests();
      final projection = _Projection();
      final coordinator = DefaultChatSendCoordinator(
        api: api,
        requests: requests,
        host: projection.host,
        clock: () => DateTime.utc(2026, 5, 5, 10, 2),
      );
      addTearDown(coordinator.dispose);

      final first = coordinator.sendMessage(
        _site,
        const ChatChannelTarget(9),
        OutgoingChatMessage.text('first'),
      )!;
      final second = coordinator.sendMessage(
        _site,
        const ChatChannelTarget(9),
        OutgoingChatMessage.text('second'),
      )!;

      expect(projection.staged.map((message) => message.optimisticRaw), [
        'first',
        'second',
      ]);
      expect(projection.staged.map((message) => message.id), [-1, -2]);
      expect(first.stagedId, 'native-1777975320000000-0');
      expect(second.stagedId, 'native-1777975320000000-1');
      expect(api.chatMessagesSent, isEmpty);

      await Future<void>.delayed(Duration.zero);
      expect(api.chatMessagesSent.map((call) => call.message), ['first']);

      sendGate.complete();
      expect(await first.settled, ChatSendResult.sent);
      expect(await second.settled, ChatSendResult.sent);
      expect(api.chatMessagesSent.map((call) => call.message), [
        'first',
        'second',
      ]);
      expect(projection.sent.map((completion) => completion.stagedId), [
        first.stagedId,
        second.stagedId,
      ]);
    });

    test('pumps different stream queues concurrently', () async {
      final sendGate = Completer<void>();
      final api = FakeDiscourseApi(chatSendGate: sendGate);
      final projection = _Projection();
      final coordinator = DefaultChatSendCoordinator(
        api: api,
        requests: _Requests(),
        host: projection.host,
      );
      addTearDown(coordinator.dispose);

      final first = coordinator.sendMessage(
        _site,
        const ChatChannelTarget(9),
        OutgoingChatMessage.text('nine'),
      )!;
      final second = coordinator.sendMessage(
        _site,
        const ChatChannelTarget(10),
        OutgoingChatMessage.text('ten'),
      )!;
      await Future<void>.delayed(Duration.zero);

      expect(api.chatMessagesSent.map((call) => call.channelId).toSet(), {
        9,
        10,
      });

      sendGate.complete();
      expect(await first.settled, ChatSendResult.sent);
      expect(await second.settled, ChatSendResult.sent);
    });

    test('captures topic context with each queued send', () async {
      final sendGate = Completer<void>();
      final api = FakeDiscourseApi(chatSendGate: sendGate);
      final projection = _Projection()
        ..messageContext = (topicId: 31, postIds: [101, 102, 103]);
      final coordinator = DefaultChatSendCoordinator(
        api: api,
        requests: _Requests(),
        host: projection.host,
      );
      addTearDown(coordinator.dispose);

      final first = coordinator.sendMessage(
        _site,
        const ChatChannelTarget(9),
        OutgoingChatMessage.text('first'),
      )!;
      projection.messageContext = (topicId: 32, postIds: [201, 202]);
      final second = coordinator.sendMessage(
        _site,
        const ChatChannelTarget(9),
        OutgoingChatMessage.text('second'),
      )!;

      await Future<void>.delayed(Duration.zero);
      sendGate.complete();
      expect(await first.settled, ChatSendResult.sent);
      expect(await second.settled, ChatSendResult.sent);
      expect(api.chatMessagesSent.map((call) => call.contextTopicId), [31, 32]);
      expect(api.chatMessagesSent.map((call) => call.contextPostIds), [
        [101, 102, 103],
        [201, 202],
      ]);
    });

    test(
      'forget cancels the active credential wait and queued sends',
      () async {
        final credentialGate = Completer<void>();
        final requests = _Requests(credentialsGate: credentialGate);
        final api = FakeDiscourseApi();
        final coordinator = DefaultChatSendCoordinator(
          api: api,
          requests: requests,
          host: _Projection().host,
        );
        addTearDown(coordinator.dispose);

        final first = coordinator.sendMessage(
          _site,
          const ChatChannelTarget(9),
          OutgoingChatMessage.text('first'),
        )!;
        final second = coordinator.sendMessage(
          _site,
          const ChatChannelTarget(9),
          OutgoingChatMessage.text('second'),
        )!;
        await requests.credentialsStarted.future;

        coordinator.forget(_site);

        expect(await first.settled, ChatSendResult.cancelled);
        expect(await second.settled, ChatSendResult.cancelled);
        credentialGate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(api.chatMessagesSent, isEmpty);
      },
    );

    test(
      'correlates sent events and releases the temporary listener',
      () async {
        final api = FakeDiscourseApi(chatSentMessageId: 42);
        final projection = _Projection();
        final tracker = _LiveChannels();
        final coordinator = DefaultChatSendCoordinator(
          api: api,
          requests: _Requests(),
          host: projection.host,
        );
        addTearDown(coordinator.dispose);
        coordinator.attachTracker(_site, tracker);

        final sending = coordinator.sendMessage(
          _site,
          const ChatChannelTarget(9),
          OutgoingChatMessage.text('hello'),
        )!;
        final payload = <String, dynamic>{'id': 42};

        tracker.deliver('/chat/9', {
          'type': 'sent',
          'staged_id': sending.stagedId,
          'chat_message': payload,
        });

        expect(projection.reconciled, [
          (stagedId: sending.stagedId, payload: payload),
        ]);
        expect(tracker.hasListener('/chat/9'), isFalse);
        expect(await sending.settled, ChatSendResult.sent);
      },
    );
  });
}

final class _Projection {
  final staged = <ChatMessage>[];
  final sent = <({String stagedId, int? serverId})>[];
  final reconciled = <({String stagedId, Object? payload})>[];
  final _unsettledTargets = <ChatStreamTarget>{};
  ChatMessageContext? messageContext;

  late final host = ChatSendCoordinatorHost(
    isDisposed: () => false,
    canSend: (_, _) => true,
    currentUserFor: (_) =>
        const DiscourseUser(id: 7, username: 'reader', staff: false),
    projectPreview: (_, message) =>
        SourceFallback(message.raw, ChatPreviewFallbackReason.internalFailure),
    stage: (_, target, message) {
      staged.add(message);
      _unsettledTargets.add(target);
    },
    markSent: (_, _, stagedId, serverId) {
      sent.add((stagedId: stagedId, serverId: serverId));
    },
    markFailed: (_, target, stagedId, failure) {
      _unsettledTargets.remove(target);
      return false;
    },
    onSent: (_, _) {},
    hasUnsettledMessages: (_, target) => _unsettledTargets.contains(target),
    reconcileSentEvent: (_, target, stagedId, payload) {
      reconciled.add((stagedId: stagedId, payload: payload));
      _unsettledTargets.remove(target);
    },
    messageContextFor: (_) => messageContext,
    report: (_, _, _, _) {},
  );
}

final class _Requests implements PluginRequestHost {
  _Requests({this.credentialsGate});

  final Completer<void>? credentialsGate;
  final credentialsStarted = Completer<void>();

  @override
  PluginSiteLease capture(String siteUrl) => const _Lease();

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    if (!credentialsStarted.isCompleted) credentialsStarted.complete();
    await credentialsGate?.future;
    return const PluginRequestCredentials(apiKey: 'key', clientId: 'client');
  }

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async =>
      (apiKey: 'key', failure: null);
}

final class _Lease implements PluginSiteLease {
  const _Lease();

  @override
  bool get isCurrent => true;

  @override
  bool commit(void Function() mutation) {
    mutation();
    return true;
  }
}

final class _LiveChannels implements PluginLiveChannelHandle {
  final _listeners =
      <String, List<void Function(Object? data, int messageId)>>{};

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    (_listeners[channel] ??= []).add(onMessage);
    return _LiveSubscription(() => _listeners[channel]?.remove(onMessage));
  }

  void deliver(String channel, Object? data) {
    for (final listener in List.of(
      _listeners[channel] ?? const <void Function(Object?, int)>[],
    )) {
      listener(data, 1);
    }
  }

  bool hasListener(String channel) => _listeners[channel]?.isNotEmpty ?? false;
}

final class _LiveSubscription implements PluginLiveChannelSubscription {
  _LiveSubscription(this._cancel);

  final void Function() _cancel;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}
