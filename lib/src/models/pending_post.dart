import 'package:flutter/foundation.dart';

import 'json.dart';

/// One of the reader's posts waiting in the review queue, as
/// `PendingPostSerializer` answers `/posts/:username/pending.json`. Title and
/// raw are the queued payload exactly as the composer sent them.
@immutable
class PendingPost {
  const PendingPost({required this.id, this.title, this.raw, this.topicId});

  /// A row without its reviewable id cannot be told apart from another queued
  /// copy of the same text, so it is dropped.
  static PendingPost? fromJson(Map<String, dynamic> json) {
    final id = jsonIntOrNull(json['id']);
    if (id == null || id < 1) return null;
    return PendingPost(
      id: id,
      title: jsonText(json['title']),
      raw: jsonText(json['raw_text']),
      topicId: jsonIntOrNull(json['topic_id']),
    );
  }

  /// The reviewable's id, which every later enqueue exceeds.
  final int id;
  final String? title;
  final String? raw;

  /// The topic a queued reply answers; a queued new topic has none.
  final int? topicId;
}
