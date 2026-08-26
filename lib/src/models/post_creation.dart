import 'package:flutter/foundation.dart';

import '../plugin_api/plugin_data.dart';
import 'json.dart';
import 'post.dart';

/// What the site did with a post it accepted.
///
/// Accepted is not the same as posted. A site with review enabled answers a
/// successful create with HTTP 200, `action: enqueued` and no post at all —
/// appending that to the stream would show the author a reply nobody else
/// can see.
enum PostOutcome {
  /// Live in the topic. [PostCreation.post] is the real thing.
  created,

  /// Held for review. There is no post to show yet.
  enqueued,
}

/// The answer to a successful `POST /posts.json`.
@immutable
class PostCreation {
  const PostCreation({
    required this.outcome,
    this.post,
    this.draftSequence,
    this.message,
    this.topicId,
    this.topicSlug,
    this.topicTitle,
  });

  factory PostCreation.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    // `nested_post` asks for the envelope, which is the only shape that carries
    // `action`. A site that answers with the bare post instead has published
    // it — the envelope is only ever dropped when there is nothing to report.
    final nested = switch (json['post']) {
      final Map<String, dynamic> post => post,
      _ => null,
    };
    final post = nested ?? (json.containsKey('id') ? json : null);

    return PostCreation(
      outcome: json['action'] == 'enqueued'
          ? PostOutcome.enqueued
          : PostOutcome.created,
      post: post == null
          ? null
          : Post.fromJson(post, siteUrl, extensions: extensions),
      // Hung off the post rather than off the envelope. Creating a post has
      // already bumped the sequence and deleted the draft, so a client that
      // keeps the one it had gets a 409 on its next draft save.
      draftSequence: jsonIntOrNull(post?['draft_sequence']),
      message: jsonText(json['message']),
      topicId:
          jsonIntOrNull(post?['topic_id']) ?? jsonIntOrNull(json['topic_id']),
      topicSlug: jsonText(post?['topic_slug']) ?? jsonText(json['topic_slug']),
      topicTitle:
          jsonText(post?['topic_title']) ?? jsonText(json['topic_title']),
    );
  }

  final PostOutcome outcome;

  /// The created post, or null when it was [PostOutcome.enqueued].
  final Post? post;

  /// The sequence to save the next draft against, when the site sent one.
  final int? draftSequence;

  /// Something the site wants the author to read — why it was queued, usually.
  final String? message;

  /// Canonical topic identity included when this was a topic creation.
  final int? topicId;
  final String? topicSlug;
  final String? topicTitle;

  bool get isEnqueued => outcome == PostOutcome.enqueued;
}
