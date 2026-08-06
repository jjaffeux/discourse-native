import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A reply in progress, in the shape Discourse stores drafts in.
///
/// The field names are the web composer's own (`models/composer.js`,
/// `_draft_serializer`) rather than anything of ours, so a reply started here
/// can be finished in a browser and the other way round. That interoperability
/// is the entire reason to use the draft API instead of only keeping a local
/// copy.
@immutable
class ComposerDraft {
  const ComposerDraft({
    required this.reply,
    this.replyToPostNumber,
    this.replyToUsername,
    this.typingTime = Duration.zero,
    this.composerTime = Duration.zero,
  });

  /// What the web composer calls replying to an existing topic.
  static const String replyAction = 'reply';

  factory ComposerDraft.fromJson(Map<String, dynamic> json) => ComposerDraft(
    reply: (json['reply'] ?? '') as String,
    replyToPostNumber: _int(json['reply_to_post_number']),
    replyToUsername: switch (json['reply_to_user']) {
      final Map<String, dynamic> user => user['username'] as String?,
      final String username => username,
      _ => null,
    },
    typingTime: Duration(milliseconds: _int(json['typingTime']) ?? 0),
    composerTime: Duration(milliseconds: _int(json['composerTime']) ?? 0),
  );

  /// Reads the blob Discourse stores.
  ///
  /// It is a JSON *string* rather than an object, both in the topic payload
  /// and in the draft API, and anything that cannot be read is treated as no
  /// draft at all — an unreadable one is not worth failing an open over.
  static ComposerDraft? decode(Object? data) {
    if (data is! String || data.isEmpty) return null;
    try {
      final draft = ComposerDraft.fromJson(
        jsonDecode(data) as Map<String, dynamic>,
      );
      return draft.reply.trim().isEmpty ? null : draft;
    } catch (_) {
      return null;
    }
  }

  static int? _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  final String reply;
  final int? replyToPostNumber;
  final String? replyToUsername;

  /// Time spent typing, which is what the fast-typer check measures.
  final Duration typingTime;

  /// Wall clock since the composer opened.
  final Duration composerTime;

  Map<String, dynamic> toJson() => {
    'reply': reply,
    'action': replyAction,
    'archetypeId': 'regular',
    'reply_to_post_number': replyToPostNumber,
    'reply_to_user': replyToUsername == null
        ? null
        : {'username': replyToUsername},
    'typingTime': typingTime.inMilliseconds,
    'composerTime': composerTime.inMilliseconds,
  };

  String encode() => jsonEncode(toJson());
}
