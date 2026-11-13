import 'package:flutter/foundation.dart';

import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../models/topic_tracking_state.dart';

/// A visible unread queue. The server page remains intact for pagination and
/// for topics that receive another reply after being read locally.
final class UnreadTopicFeed {
  TopicFeed? _source;
  TopicFeed? _visible;

  TopicFeed project(
    TopicFeed source, {
    required int? selectedTopicId,
    required bool Function(int topicId) isRead,
  }) {
    final topics = source.topicIds;
    List<int>? visibleIds;
    for (var index = 0; index < topics.length; index++) {
      final id = topics[index];
      if (id != selectedTopicId && isRead(id)) {
        visibleIds ??= topics.sublist(0, index);
      } else {
        visibleIds?.add(id);
      }
    }
    if (visibleIds == null) return source;
    if (identical(source, _source) &&
        listEquals(visibleIds, _visible?.topicIds)) {
      return _visible!;
    }
    _source = source;
    return _visible = source.withVisibleTopics(visibleIds);
  }

  static bool isRead({
    required Topic? topic,
    required TrackedTopicState? tracking,
    required int? localReadPostNumber,
  }) {
    final policy = topic?.readingPolicy;
    if (policy != null && !policy.usesPositionForCatchUp) {
      return topic!.listReadStateKnown &&
          topic.seen &&
          policy.explicitReadState == true;
    }
    final highest = _maximum(
      topic?.highestPostNumber,
      tracking?.highestPostNumber,
    );
    final read = _maximum(
      localReadPostNumber,
      _maximum(topic?.lastReadPostNumber, tracking?.lastReadPostNumber),
    );
    // Missing records or sparse payloads are not proof that a topic is read.
    return highest > 0 && read >= highest;
  }

  static int _maximum(int? a, int? b) => (a ?? 0) > (b ?? 0) ? a! : b ?? 0;
}
