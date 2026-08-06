import 'package:flutter/foundation.dart';

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
  });

  factory PostCreation.fromJson(Map<String, dynamic> json, String siteUrl) {
    // `nested_post` asks for the envelope, which is the only shape that carries
    // `action`. A site that answers with the bare post instead has published
    // it — the envelope is only ever dropped when there is nothing to report.
    final nested = json['post'] as Map<String, dynamic>?;
    final post = nested ?? (json.containsKey('id') ? json : null);

    return PostCreation(
      outcome: json['action'] == 'enqueued'
          ? PostOutcome.enqueued
          : PostOutcome.created,
      post: post == null ? null : Post.fromJson(post, siteUrl),
      // Hung off the post rather than off the envelope. Creating a post has
      // already bumped the sequence and deleted the draft, so a client that
      // keeps the one it had gets a 409 on its next draft save.
      draftSequence: _int(post?['draft_sequence']),
      message: _nonEmpty(json['message']),
    );
  }

  static int? _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  static String? _nonEmpty(Object? value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  final PostOutcome outcome;

  /// The created post, or null when it was [PostOutcome.enqueued].
  final Post? post;

  /// The sequence to save the next draft against, when the site sent one.
  final int? draftSequence;

  /// Something the site wants the author to read — why it was queued, usually.
  final String? message;

  bool get isEnqueued => outcome == PostOutcome.enqueued;
}
