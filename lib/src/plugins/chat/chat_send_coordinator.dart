// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../data/discourse_api_contracts.dart'
    show WriteException, WriteFailure;
import '../../diagnostics/diagnostics_controller.dart';
import '../../models/discourse_user.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/live_channels.dart';
import 'chat_api.dart';
import 'chat_message.dart';
import 'chat_preview.dart';
import 'chat_stream_target.dart';

typedef ChatSendCoordinatorFactory =
    ChatSendCoordinator Function(ChatSendCoordinatorHost host);

/// The projection seam between send orchestration and chat timeline state.
///
/// Keeping these operations as callbacks lets the coordinator own queue and
/// request lifecycles without gaining broad access to [ChatController]'s store.
@immutable
final class ChatSendCoordinatorHost {
  const ChatSendCoordinatorHost({
    required this.isDisposed,
    required this.canSend,
    required this.currentUserFor,
    required this.projectPreview,
    required this.stage,
    required this.markSent,
    required this.markFailed,
    required this.onSent,
    required this.hasUnsettledMessages,
    required this.reconcileSentEvent,
    required this.report,
  });

  final bool Function() isDisposed;
  final bool Function(String siteUrl, ChatStreamTarget target) canSend;
  final DiscourseUser? Function(String siteUrl) currentUserFor;
  final ChatPreviewResult Function(String siteUrl, OutgoingChatMessage message)
  projectPreview;
  final void Function(
    String siteUrl,
    ChatStreamTarget target,
    ChatMessage message,
  )
  stage;
  final void Function(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
    int? serverId,
  )
  markSent;
  final bool Function(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
    WriteException failure,
  )
  markFailed;
  final void Function(String siteUrl, ChatStreamTarget target) onSent;
  final bool Function(String siteUrl, ChatStreamTarget target)
  hasUnsettledMessages;
  final void Function(
    String siteUrl,
    ChatStreamTarget target,
    String stagedId,
    Object? payload,
  )
  reconcileSentEvent;
  final void Function(
    Object error,
    StackTrace stackTrace,
    String operation,
    DiagnosticSeverity severity,
  )
  report;
}

/// Owns optimistic chat send staging and each stream's serialized send lane.
abstract interface class ChatSendCoordinator {
  ChatSendHandle? sendMessage(
    String siteUrl,
    ChatStreamTarget target,
    OutgoingChatMessage message,
  );

  void attachTracker(String siteUrl, PluginLiveChannelHandle channels);

  void reconcileSentEvent(
    String siteUrl,
    ChatStreamTarget target,
    Object? data,
  );

  void releaseReconciliationIfSettled(String siteUrl, ChatStreamTarget target);

  void cancelChannel(String siteUrl, int channelId);

  void forget(String siteUrl);

  void dispose();
}

/// Default per-stream FIFO implementation used by [ChatController].
final class DefaultChatSendCoordinator implements ChatSendCoordinator {
  DefaultChatSendCoordinator({
    required ChatApi api,
    required PluginRequestHost requests,
    required ChatSendCoordinatorHost host,
    DateTime Function()? clock,
  }) : _api = api,
       _requests = requests,
       _host = host,
       _clock = clock ?? DateTime.now;

  final ChatApi _api;
  final PluginRequestHost _requests;
  final ChatSendCoordinatorHost _host;
  final DateTime Function() _clock;

  final Map<String, _ChatSendQueue> _queues = {};
  final Map<String, PluginLiveChannelHandle> _trackers = {};
  final Map<String, PluginLiveChannelSubscription> _subscriptions = {};
  final Set<({String siteUrl, ChatStreamTarget target})>
  _reconciliationTargets = {};
  int _nextLocalMessageId = -1;
  int _nextStagedSequence = 0;
  bool _disposed = false;

  static String _targetKey(String siteUrl, ChatStreamTarget target) =>
      '$siteUrl~${target.storageKey}';

  @override
  ChatSendHandle? sendMessage(
    String siteUrl,
    ChatStreamTarget target,
    OutgoingChatMessage message,
  ) {
    if (_disposed ||
        (message.raw.trim().isEmpty && message.uploads.isEmpty) ||
        !_host.canSend(siteUrl, target)) {
      return null;
    }

    final createdAt = _clock().toUtc();
    final stagedId =
        'native-${createdAt.microsecondsSinceEpoch}-${_nextStagedSequence++}';
    final user = _host.currentUserFor(siteUrl);
    final local = ChatMessage.optimistic(
      id: _nextLocalMessageId--,
      channelId: target.channelId,
      threadId: target.threadId,
      raw: message.raw,
      stagedId: stagedId,
      preview: _host.projectPreview(siteUrl, message),
      author: ChatMessageAuthor(
        id: user?.id ?? 0,
        username: user?.username ?? '',
        name: user?.name,
        avatarUrl: user?.avatarUrl,
        isStaff: user?.staff ?? false,
      ),
      createdAt: createdAt,
      uploads: [
        for (final upload in message.uploads)
          ChatUpload.fromComposerUpload(upload),
      ],
    );
    _host.stage(siteUrl, target, local);
    _retainReconciliation(siteUrl, target);

    final settlement = Completer<ChatSendResult>();
    final handle = ChatSendHandle.internal(
      localId: local.id,
      stagedId: stagedId,
      settled: settlement.future,
    );
    final key = _targetKey(siteUrl, target);
    final queue = _queues.putIfAbsent(
      key,
      () => _ChatSendQueue(siteUrl: siteUrl, target: target, key: key),
    );
    queue.pending.add(
      _QueuedChatSend(
        local: local,
        uploadIds: List.unmodifiable([
          for (final upload in message.uploads) upload.id,
        ]),
        settlement: settlement,
        lease: _requests.capture(siteUrl),
      ),
    );
    _schedule(queue);
    return handle;
  }

  void _schedule(_ChatSendQueue queue) {
    if (queue.scheduled || queue.cancelled) return;
    queue.scheduled = true;
    scheduleMicrotask(() {
      queue.scheduled = false;
      _pump(queue);
    });
  }

  void _pump(_ChatSendQueue queue) {
    if (queue.active != null || queue.cancelled) return;
    if (!identical(_queues[queue.key], queue) ||
        _disposed ||
        _host.isDisposed()) {
      _cancel(queue);
      return;
    }
    if (queue.pending.isEmpty) {
      _queues.remove(queue.key);
      return;
    }

    final item = queue.pending.removeFirst();
    queue.active = item;
    unawaited(
      _guardSend(queue, item).whenComplete(() {
        if (identical(queue.active, item)) queue.active = null;
        _schedule(queue);
      }),
    );
  }

  Future<void> _guardSend(_ChatSendQueue queue, _QueuedChatSend item) async {
    try {
      await _send(queue, item);
    } catch (error, stackTrace) {
      item.complete(
        _owns(queue, item) ? ChatSendResult.failed : ChatSendResult.cancelled,
      );
      try {
        _host.report(
          error,
          stackTrace,
          'chat.sendMessage',
          DiagnosticSeverity.error,
        );
      } catch (_) {
        // A broken diagnostic sink must not prevent settlement or queue progress.
      }
    }
  }

  bool _owns(_ChatSendQueue queue, _QueuedChatSend item) =>
      !queue.cancelled &&
      identical(_queues[queue.key], queue) &&
      identical(queue.active, item);

  bool _requestIsCurrent(
    PluginSiteLease lease,
    _ChatSendQueue queue,
    _QueuedChatSend item,
  ) =>
      !_disposed &&
      !_host.isDisposed() &&
      lease.isCurrent &&
      _owns(queue, item);

  Future<void> _send(_ChatSendQueue queue, _QueuedChatSend item) async {
    final siteUrl = queue.siteUrl;
    final target = queue.target;
    final local = item.local;

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!_requestIsCurrent(item.lease, queue, item)) {
        item.complete(ChatSendResult.cancelled);
        return;
      }
      if (apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final clientId = requestCredentials.clientId;
      if (!_requestIsCurrent(item.lease, queue, item)) {
        item.complete(ChatSendResult.cancelled);
        return;
      }
      if (!_host.canSend(siteUrl, target)) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final serverId = await _api.sendChatMessage(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        channelId: target.channelId,
        threadId: target.threadId,
        message: local.optimisticRaw!,
        uploadIds: item.uploadIds,
        stagedId: local.stagedId,
        clientCreatedAt: local.createdAt,
      );
      if (!_requestIsCurrent(item.lease, queue, item)) {
        item.complete(ChatSendResult.cancelled);
        return;
      }
      item.lease.commit(
        () => _host.markSent(siteUrl, target, local.stagedId!, serverId),
      );
      _host.onSent(siteUrl, target);
      item.complete(ChatSendResult.sent);
    } catch (error, stackTrace) {
      if (_requestIsCurrent(item.lease, queue, item)) {
        final failure = error is WriteException
            ? error
            : const WriteException(WriteFailure.unreachable);
        var canonicalAlreadyArrived = false;
        item.lease.commit(() {
          canonicalAlreadyArrived = _host.markFailed(
            siteUrl,
            target,
            local.stagedId!,
            failure,
          );
        });
        item.lease.commit(
          () => releaseReconciliationIfSettled(siteUrl, target),
        );
        _host.report(
          error,
          stackTrace,
          'chat.sendMessage',
          DiagnosticSeverity.error,
        );
        item.complete(
          canonicalAlreadyArrived ? ChatSendResult.sent : ChatSendResult.failed,
        );
      } else {
        item.complete(ChatSendResult.cancelled);
      }
    }
  }

  @override
  void attachTracker(String siteUrl, PluginLiveChannelHandle channels) {
    if (_disposed) return;
    if (!identical(_trackers[siteUrl], channels)) {
      _cancelSubscriptions(siteUrl, forgetTargets: false);
    }
    _trackers[siteUrl] = channels;
    for (final target in _reconciliationTargets) {
      if (target.siteUrl == siteUrl) {
        _ensureSubscription(target.siteUrl, target.target);
      }
    }
  }

  void _retainReconciliation(String siteUrl, ChatStreamTarget target) {
    _reconciliationTargets.add((siteUrl: siteUrl, target: target));
    _ensureSubscription(siteUrl, target);
  }

  void _ensureSubscription(String siteUrl, ChatStreamTarget target) {
    final key = _targetKey(siteUrl, target);
    if (_subscriptions.containsKey(key)) return;
    final tracker = _trackers[siteUrl];
    if (tracker == null) return;

    try {
      _subscriptions[key] = tracker.subscribe(
        target.threadId == null
            ? '/chat/${target.channelId}'
            : '/chat/${target.channelId}/thread/${target.threadId}',
        (data, _) => reconcileSentEvent(siteUrl, target, data),
      );
    } catch (error, stackTrace) {
      _host.report(
        error,
        stackTrace,
        'chat.sendMessage.subscribe',
        DiagnosticSeverity.warning,
      );
      // POST marks the row sent; a later ordinary fetch supplies canonical data.
    }
  }

  @override
  void reconcileSentEvent(
    String siteUrl,
    ChatStreamTarget target,
    Object? data,
  ) {
    if (data is! Map<String, dynamic>) return;
    if (data['type'] != 'sent' || data['staged_id'] is! String) return;
    _host.reconcileSentEvent(
      siteUrl,
      target,
      data['staged_id'] as String,
      data['chat_message'],
    );
    releaseReconciliationIfSettled(siteUrl, target);
  }

  @override
  void releaseReconciliationIfSettled(String siteUrl, ChatStreamTarget target) {
    if (_host.hasUnsettledMessages(siteUrl, target)) return;

    final key = _targetKey(siteUrl, target);
    _reconciliationTargets.remove((siteUrl: siteUrl, target: target));
    _cancelSubscription(
      _subscriptions.remove(key),
      'chat.sendMessage.unsubscribe',
    );
  }

  @override
  void cancelChannel(String siteUrl, int channelId) {
    _cancelQueues(
      (queue) =>
          queue.siteUrl == siteUrl && queue.target.channelId == channelId,
    );
    final targets = _reconciliationTargets
        .where(
          (target) =>
              target.siteUrl == siteUrl && target.target.channelId == channelId,
        )
        .toList(growable: false);
    for (final target in targets) {
      _reconciliationTargets.remove(target);
      _cancelSubscription(
        _subscriptions.remove(_targetKey(siteUrl, target.target)),
        'chat.kick.unsubscribe',
      );
    }
  }

  @override
  void forget(String siteUrl) {
    _cancelQueues((queue) => queue.siteUrl == siteUrl);
    _cancelSubscriptions(siteUrl);
    _trackers.remove(siteUrl);
  }

  void _cancelQueues(bool Function(_ChatSendQueue queue) shouldCancel) {
    final queues = _queues.values.where(shouldCancel).toList(growable: false);
    for (final queue in queues) {
      _queues.remove(queue.key);
      _cancel(queue);
    }
  }

  void _cancel(_ChatSendQueue queue) {
    if (queue.cancelled) return;
    queue.cancelled = true;
    queue.active?.complete(ChatSendResult.cancelled);
    while (queue.pending.isNotEmpty) {
      queue.pending.removeFirst().complete(ChatSendResult.cancelled);
    }
  }

  void _cancelSubscriptions(String siteUrl, {bool forgetTargets = true}) {
    final cancelled = <PluginLiveChannelSubscription>[];
    _subscriptions.removeWhere((key, subscription) {
      if (!key.startsWith('$siteUrl~')) return false;
      cancelled.add(subscription);
      return true;
    });
    if (forgetTargets) {
      _reconciliationTargets.removeWhere((target) => target.siteUrl == siteUrl);
    }
    for (final subscription in cancelled) {
      _cancelSubscription(subscription, 'chat.sendMessage.unsubscribe');
    }
  }

  void _cancelSubscription(
    PluginLiveChannelSubscription? subscription,
    String operation,
  ) {
    if (subscription == null) return;
    try {
      subscription.cancel();
    } catch (error, stackTrace) {
      _host.report(error, stackTrace, operation, DiagnosticSeverity.warning);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelQueues((_) => true);
    for (final subscription in _subscriptions.values) {
      try {
        subscription.cancel();
      } catch (_) {
        // Tracker teardown is best-effort; coordinator state must still clear.
      }
    }
    _subscriptions.clear();
    _reconciliationTargets.clear();
    _trackers.clear();
  }
}

final class _ChatSendQueue {
  _ChatSendQueue({
    required this.siteUrl,
    required this.target,
    required this.key,
  });

  final String siteUrl;
  final ChatStreamTarget target;
  final String key;
  final ListQueue<_QueuedChatSend> pending = ListQueue<_QueuedChatSend>();
  _QueuedChatSend? active;
  bool scheduled = false;
  bool cancelled = false;
}

final class _QueuedChatSend {
  _QueuedChatSend({
    required this.local,
    required this.uploadIds,
    required this.settlement,
    required this.lease,
  });

  final ChatMessage local;
  final List<int> uploadIds;
  final Completer<ChatSendResult> settlement;
  final PluginSiteLease lease;

  void complete(ChatSendResult result) {
    if (!settlement.isCompleted) settlement.complete(result);
  }
}
