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
  const ChatReadAdmission(this.messageId, this.lease, this.alreadyRead);

  final int messageId;
  final PluginSiteLease lease;
  final bool alreadyRead;
}

final class ChatChannelRead extends ChatReadAdmission {
  const ChatChannelRead._(
    super.messageId,
    super.lease,
    super.alreadyRead,
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
  const ChatThreadRead._(super.messageId, super.lease, super.alreadyRead);

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

final class _ReadRun {}

/// Owns read admission, optimistic projection and delivery for one retained target.
final class ChatReadReceiptOwner {
  ChatReadReceiptOwner({
    required this.siteUrl,
    required this.target,
    required this._api,
    required this._requests,
    required this._clock,
    required this._isCurrent,
    required this._publish,
  });

  final String siteUrl;
  final ChatStreamTarget target;
  final ChatApi _api;
  final PluginRequestHost _requests;
  final DateTime Function() _clock;
  final bool Function() _isCurrent;
  final void Function(ChatReadAdmission, DateTime) _publish;
  ChatReadAdmission? _queued;
  Future<void>? _task;
  _ReadRun? _run;
  bool _retired = false;

  bool get preventsEviction => _queued != null || _task != null || _run != null;

  bool get _current => !_retired && _isCurrent();

  static ChatReadAdmission? admit(
    ChatStreamTarget target,
    int messageId,
    ChatReadReceiptSnapshot snapshot,
  ) {
    if (messageId <= 0 || snapshot.isLocalMessage) return null;
    if (target.threadId != null) {
      final membership = snapshot.thread?.membership;
      if (membership == null) return null;
      if ((membership.lastReadMessageId ?? 0) >= messageId) return null;
      return ChatThreadRead._(messageId, snapshot.lease, false);
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
    if (alreadyRead && !staleCounts) return null;
    return ChatChannelRead._(
      messageId,
      snapshot.lease,
      alreadyRead,
      channel,
      caughtUp,
    );
  }

  Future<void> markRead(ChatReadAdmission admission) {
    _publish(admission, _clock().toUtc());
    if (admission.alreadyRead || !_current || !admission.lease.isCurrent) {
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
  }

  Future<void> _drain(_ReadRun run) async {
    bool ownsRequest() => _current && identical(_run, run);
    while (true) {
      if (!ownsRequest()) return;
      final receipt = _queued;
      _queued = null;
      if (receipt == null) {
        _run = null;
        _task = null;
        return;
      }
      try {
        final credentials = await _requests.credentialsFor(siteUrl);
        final apiKey = credentials.apiKey;
        if (!receipt.lease.isCurrent || !ownsRequest()) continue;
        if (apiKey == null) continue;
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
      } catch (_) {}
    }
  }
}
