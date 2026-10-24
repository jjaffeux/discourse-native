import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'chat_api.dart';
import 'chat_channel.dart';
import 'chat_stream_target.dart';
import 'chat_thread.dart';

final class ChatReadReceiptSnapshot {
  const ChatReadReceiptSnapshot({
    required this.lease,
    required this.channel,
    required this.thread,
    required this.isLocalMessage,
    required this.atPresent,
    required this.newestMessageId,
  });

  final PluginSiteLease lease;
  final ChatChannel? channel;
  final ChatThread? thread;
  final bool isLocalMessage;
  final bool atPresent;
  final int? newestMessageId;
}

sealed class ChatReadAdmission {
  const ChatReadAdmission(
    this.messageId,
    this.lease,
    this.alreadyRead,
    this.shouldDeliver,
  );

  final int messageId;
  final PluginSiteLease lease;
  final bool alreadyRead;
  final bool shouldDeliver;
}

final class ChatChannelRead extends ChatReadAdmission {
  const ChatChannelRead._(
    super.messageId,
    super.lease,
    super.alreadyRead,
    super.shouldDeliver,
    this.before,
    this.caughtUp,
  );

  final ChatChannel before;
  final bool caughtUp;

  ChatChannel? project(ChatChannel current, DateTime viewedAt) {
    final readThrough = alreadyRead
        ? current.membership.lastReadMessageId
        : messageId;
    if (readThrough == null) return null;
    var updated = current.withLastRead(readThrough, caughtUp: caughtUp);
    final previous = updated.membership.lastViewedAt;
    if (previous == null || viewedAt.isAfter(previous)) {
      updated = updated.withLastViewedAt(viewedAt);
    }
    return updated;
  }
}

final class ChatThreadRead extends ChatReadAdmission {
  const ChatThreadRead._(
    super.messageId,
    super.lease,
    super.alreadyRead,
    super.shouldDeliver,
  );

  ChatThread project(ChatThread current) {
    final membership = current.membership;
    if (membership == null ||
        (membership.lastReadMessageId ?? 0) >= messageId) {
      return current;
    }
    return current.copyWith(
      membership: membership.withLastReadMessageId(messageId),
    );
  }
}

/// Keeps undelivered cursors without retaining their conversation windows.
final class ChatReadReceiptRetries {
  final Map<
    (String, ChatStreamTarget),
    ({int messageId, PluginSiteLease lease})
  >
  _pending = {};

  int? pendingMessageId(String siteUrl, ChatStreamTarget target) {
    final key = (siteUrl, target);
    final pending = _pending[key];
    if (pending == null) return null;
    if (!pending.lease.isCurrent) {
      _pending.remove(key);
      return null;
    }
    return pending.messageId;
  }

  void _failed(
    String siteUrl,
    ChatStreamTarget target,
    ChatReadAdmission read,
  ) {
    final pending = pendingMessageId(siteUrl, target);
    if (pending == null || read.messageId >= pending) {
      _pending[(siteUrl, target)] = (
        messageId: read.messageId,
        lease: read.lease,
      );
    }
  }

  void _delivered(String siteUrl, ChatStreamTarget target, int messageId) {
    final pending = pendingMessageId(siteUrl, target);
    if (pending != null && pending <= messageId) {
      _pending.remove((siteUrl, target));
    }
  }

  void forget(String siteUrl) {
    _pending.removeWhere((key, _) => key.$1 == siteUrl);
  }

  void clear() => _pending.clear();
}

final class _ReadRun {}

/// Owns read admission, optimistic projection and delivery for one retained target.
final class ChatReadReceiptOwner {
  ChatReadReceiptOwner({
    required this.siteUrl,
    required this.target,
    required this._api,
    required this._requests,
    required this._retries,
    required this._clock,
    required this._isCurrent,
    required this._publish,
  });

  final String siteUrl;
  final ChatStreamTarget target;
  final ChatApi _api;
  final PluginRequestHost _requests;
  final ChatReadReceiptRetries _retries;
  final DateTime Function() _clock;
  final bool Function() _isCurrent;
  final void Function(ChatReadAdmission, DateTime) _publish;
  ChatReadAdmission? _queued;
  Future<void>? _task;
  _ReadRun? _run;
  int? _sendingMessageId;
  bool _retired = false;

  bool get preventsEviction => _queued != null || _task != null || _run != null;

  bool get _current => !_retired && _isCurrent();

  static ChatReadAdmission? admit(
    ChatStreamTarget target,
    int messageId,
    ChatReadReceiptSnapshot snapshot, {
    int? retryMessageId,
  }) {
    if (messageId <= 0 || snapshot.isLocalMessage) return null;
    final retry = retryMessageId != null && messageId >= retryMessageId;
    if (target.threadId != null) {
      final membership = snapshot.thread?.membership;
      if (membership == null) return null;
      final alreadyRead = (membership.lastReadMessageId ?? 0) >= messageId;
      if (alreadyRead && !retry) return null;
      return ChatThreadRead._(
        messageId,
        snapshot.lease,
        alreadyRead,
        !alreadyRead || retry,
      );
    }

    final channel = snapshot.channel;
    if (channel == null || !channel.membership.following) return null;
    final lastRead = channel.membership.lastReadMessageId;
    final alreadyRead = lastRead != null && lastRead >= messageId;
    // A channel's last message can be a reply absent from the root stream.
    final caughtUp =
        snapshot.atPresent && snapshot.newestMessageId == messageId;
    final staleCounts =
        caughtUp &&
        (channel.tracking.unreadCount > 0 || channel.tracking.mentionCount > 0);
    if (alreadyRead && !staleCounts && !retry) return null;
    return ChatChannelRead._(
      messageId,
      snapshot.lease,
      alreadyRead,
      !alreadyRead || retry,
      channel,
      caughtUp,
    );
  }

  Future<void> markRead(ChatReadAdmission admission) {
    if (!_current || !admission.lease.isCurrent) return Future.value();
    bool duplicate() {
      final pending = _queued?.messageId ?? _sendingMessageId;
      return pending != null && pending >= admission.messageId;
    }

    if (admission.shouldDeliver && duplicate()) return Future.value();
    _publish(admission, _clock().toUtc());
    if (!admission.shouldDeliver ||
        !_current ||
        !admission.lease.isCurrent ||
        duplicate()) {
      return Future.value();
    }
    _queued = admission;
    final running = _task;
    if (running != null) return running;
    final run = _ReadRun();
    _run = run;
    final task = _drain(run);
    _task = task;
    return task;
  }

  void retire() {
    _retired = true;
    _queued = null;
    _run = null;
    _task = null;
    _sendingMessageId = null;
  }

  Future<void> _drain(_ReadRun run) async {
    bool ownsRequest() => _current && identical(_run, run);
    while (true) {
      if (!ownsRequest()) return;
      final receipt = _queued;
      _queued = null;
      if (receipt == null) {
        _sendingMessageId = null;
        _run = null;
        _task = null;
        return;
      }
      _sendingMessageId = receipt.messageId;
      try {
        final credentials = await _requests.credentialsFor(siteUrl);
        final apiKey = credentials.apiKey;
        if (!receipt.lease.isCurrent || !ownsRequest()) continue;
        if (apiKey == null) {
          _retries._failed(siteUrl, target, receipt);
          continue;
        }
        final clientId = credentials.clientId;
        if (!receipt.lease.isCurrent || !ownsRequest()) continue;
        if (target.threadId == null) {
          await credentials.run(
            () => _api.markChatChannelRead(
              siteUrl: siteUrl,
              apiKey: apiKey,
              channelId: target.channelId,
              messageId: receipt.messageId,
              clientId: clientId,
            ),
          );
        } else {
          await credentials.run(
            () => _api.markChatThreadRead(
              siteUrl: siteUrl,
              apiKey: apiKey,
              channelId: target.channelId,
              threadId: target.threadId!,
              messageId: receipt.messageId,
              clientId: clientId,
            ),
          );
        }
        if (ownsRequest() && receipt.lease.isCurrent) {
          _retries._delivered(siteUrl, target, receipt.messageId);
        }
      } catch (_) {
        if (ownsRequest() && receipt.lease.isCurrent) {
          _retries._failed(siteUrl, target, receipt);
        }
      }
    }
  }
}
