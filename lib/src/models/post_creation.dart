import 'package:flutter/foundation.dart';

import '../plugin_api/plugin_data.dart';
import 'json.dart';
import 'post.dart';

enum PostOutcome { created, enqueued }

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

  final Post? post;

  final int? draftSequence;

  final String? message;

  final int? topicId;
  final String? topicSlug;
  final String? topicTitle;

  bool get isEnqueued => outcome == PostOutcome.enqueued;
}
