import 'package:flutter/foundation.dart';

/// The source determines which domains a topic payload can settle.
enum TopicRecordSource { list, detail, recommendation, partial }

@immutable
final class TopicRecordDecodeContext {
  const TopicRecordDecodeContext.list() : source = TopicRecordSource.list;
  const TopicRecordDecodeContext.detail() : source = TopicRecordSource.detail;
  const TopicRecordDecodeContext.recommendation()
    : source = TopicRecordSource.recommendation;
  const TopicRecordDecodeContext.partial() : source = TopicRecordSource.partial;

  final TopicRecordSource source;
}

/// A record can reconcile its own partial fields without exposing its schema.
abstract interface class TopicRecordValue {
  Object mergeTopicRecord(Object? held);
}

abstract interface class TopicReadingPolicyRecord {
  TopicReadingPolicy? get topicReadingPolicy;
  Object markTopicRead();
}

enum TopicActivityState { unknown, caughtUp, unread }

@immutable
sealed class TopicReadingPolicy {
  const TopicReadingPolicy();

  bool get allowsChronologicalResume;
  bool get usesPositionForCatchUp;
  bool get showsUnreadBoundary;
  bool get showsActivityDot;
  bool? get explicitReadState;

  bool showUnreadCount(int unreadCount);
  bool showNewTopicDot(bool seen);
  bool hasUnseenActivity({required bool seen, required int unreadCount});
}

final class ChronologicalTopicReadingPolicy extends TopicReadingPolicy {
  const ChronologicalTopicReadingPolicy();

  @override
  bool get allowsChronologicalResume => true;
  @override
  bool get usesPositionForCatchUp => true;
  @override
  bool get showsUnreadBoundary => true;
  @override
  bool get showsActivityDot => false;
  @override
  bool? get explicitReadState => null;
  @override
  bool showUnreadCount(int unreadCount) => unreadCount > 0;
  @override
  bool showNewTopicDot(bool seen) => !seen;
  @override
  bool hasUnseenActivity({required bool seen, required int unreadCount}) =>
      !seen || unreadCount > 0;

  @override
  bool operator ==(Object other) => other is ChronologicalTopicReadingPolicy;
  @override
  int get hashCode => runtimeType.hashCode;
}

/// Readers whose activity is supplied independently of chronological positions.
final class ActivityTopicReadingPolicy extends TopicReadingPolicy {
  const ActivityTopicReadingPolicy({required this.activity});

  final TopicActivityState activity;

  @override
  bool get allowsChronologicalResume => false;
  @override
  bool get usesPositionForCatchUp => false;
  @override
  bool get showsUnreadBoundary => false;
  @override
  bool get showsActivityDot => activity == TopicActivityState.unread;
  @override
  bool? get explicitReadState => switch (activity) {
    TopicActivityState.unknown => null,
    TopicActivityState.caughtUp => true,
    TopicActivityState.unread => false,
  };
  @override
  bool showUnreadCount(int unreadCount) => false;
  @override
  bool showNewTopicDot(bool seen) => false;
  @override
  bool hasUnseenActivity({required bool seen, required int unreadCount}) =>
      !seen || activity == TopicActivityState.unread;

  @override
  bool operator ==(Object other) =>
      other is ActivityTopicReadingPolicy && other.activity == activity;
  @override
  int get hashCode => Object.hash(runtimeType, activity);
}

/// Ranked readers retain server unread counts without positional inference.
final class NonchronologicalTopicReadingPolicy extends TopicReadingPolicy {
  const NonchronologicalTopicReadingPolicy({this.serverReadState});

  final bool? serverReadState;

  @override
  bool get allowsChronologicalResume => false;
  @override
  bool get usesPositionForCatchUp => false;
  @override
  bool get showsUnreadBoundary => false;
  @override
  bool get showsActivityDot => false;
  @override
  bool? get explicitReadState => serverReadState;
  @override
  bool showUnreadCount(int unreadCount) => unreadCount > 0;
  @override
  bool showNewTopicDot(bool seen) => !seen;
  @override
  bool hasUnseenActivity({required bool seen, required int unreadCount}) =>
      !seen || unreadCount > 0 || serverReadState == false;

  @override
  bool operator ==(Object other) =>
      other is NonchronologicalTopicReadingPolicy &&
      other.serverReadState == serverReadState;
  @override
  int get hashCode => Object.hash(runtimeType, serverReadState);
}
