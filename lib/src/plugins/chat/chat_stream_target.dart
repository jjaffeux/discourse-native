import 'package:flutter/foundation.dart';

/// Channel and thread timelines must not share ordering or live state.
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
