import 'package:flutter/foundation.dart';

/// The identity of one independently pageable chat timeline.
///
/// Channel and thread messages share most transport and viewport behaviour,
/// but they must never share ordering, optimistic sends, read receipts, or
/// live subscriptions. Keeping that distinction in the type makes it hard to
/// accidentally append a thread reply to its parent channel.
@immutable
sealed class ChatStreamTarget {
  const ChatStreamTarget({required this.channelId});

  final int channelId;

  int? get threadId;

  bool get isThread => threadId != null;

  String get storageKey;
}

@immutable
final class ChatChannelTarget extends ChatStreamTarget {
  const ChatChannelTarget(int channelId) : super(channelId: channelId);

  @override
  int? get threadId => null;

  @override
  String get storageKey => 'channel-$channelId';

  @override
  bool operator ==(Object other) =>
      other is ChatChannelTarget && other.channelId == channelId;

  @override
  int get hashCode => Object.hash(ChatChannelTarget, channelId);
}

@immutable
final class ChatThreadTarget extends ChatStreamTarget {
  const ChatThreadTarget({required super.channelId, required this.threadId});

  @override
  final int threadId;

  @override
  String get storageKey => 'channel-$channelId-thread-$threadId';

  @override
  bool operator ==(Object other) =>
      other is ChatThreadTarget &&
      other.channelId == channelId &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(ChatThreadTarget, channelId, threadId);
}
