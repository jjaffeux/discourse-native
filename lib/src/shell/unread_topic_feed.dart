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
    final ids = [
      for (final id in source.topicIds)
        if (id == selectedTopicId || !isRead(id)) id,
    ];
    if (ids.length == source.topicIds.length) return source;
    if (identical(source, _source) && listEquals(ids, _visible?.topicIds)) {
      return _visible!;
    }
    _source = source;
    return _visible = source.copyWith(topicIds: ids);
  }

  static bool isRead({
    required Topic? topic,
    required TrackedTopicState? tracking,
    required int? localReadPostNumber,
  }) {
    // Nested conversations use reply flags, not flat post-stream positions.
    if (topic?.isNestedView == true) {
      return topic!.seen && !topic.hasNewReplies;
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
