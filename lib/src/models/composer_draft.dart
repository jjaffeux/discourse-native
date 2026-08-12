import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'json.dart';
import 'topic_tag.dart';

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
    this.action = replyAction,
    this.title,
    this.categoryId,
    this.tags = const [],
    this.replyToPostNumber,
    this.replyToUsername,
    this.typingTime = Duration.zero,
    this.composerTime = Duration.zero,
  });

  /// What the web composer calls replying to an existing topic.
  static const String replyAction = 'reply';
  static const String createTopicAction = 'createTopic';
  static const String newTopicDraftKey = 'new_topic';

  /// Discourse rejects draft JSON above `SiteSetting.max_draft_length`, whose
  /// hidden maximum is 150,000 characters. Bound nonconforming stored/server
  /// values before asking the JSON parser to allocate for them.
  static const int maximumEncodedCharacters = 150000;

  factory ComposerDraft.fromJson(Map<String, dynamic> json) => ComposerDraft(
    reply: jsonString(json['reply']),
    action: jsonText(json['action']) ?? replyAction,
    title: jsonText(json['title']),
    categoryId: jsonIntOrNull(json['categoryId']),
    tags: List.unmodifiable(
      jsonArray(json['tags']).map(TopicTag.parse).whereType<TopicTag>(),
    ),
    replyToPostNumber: jsonIntOrNull(json['reply_to_post_number']),
    replyToUsername: switch (json['reply_to_user']) {
      final Map<String, dynamic> user => jsonText(user['username']),
      final String username => jsonText(username),
      _ => null,
    },
    typingTime: Duration(milliseconds: jsonInt(json['typingTime'])),
    composerTime: Duration(milliseconds: jsonInt(json['composerTime'])),
  );

  /// Reads the blob Discourse stores.
  ///
  /// It is a JSON *string* rather than an object, both in the topic payload
  /// and in the draft API, and anything that cannot be read is treated as no
  /// draft at all — an unreadable one is not worth failing an open over.
  static ComposerDraft? decode(Object? data) {
    if (data is! String || data.isEmpty || !_isWithinEncodedLimit(data)) {
      return null;
    }
    try {
      final draft = ComposerDraft.fromJson(
        jsonDecode(data) as Map<String, dynamic>,
      );
      return draft.reply.trim().isEmpty && (draft.title?.trim().isEmpty ?? true)
          ? null
          : draft;
    } catch (_) {
      return null;
    }
  }

  static bool _isWithinEncodedLimit(String data) {
    var characters = 0;
    for (var index = 0; index < data.length; index += 1) {
      characters += 1;
      if (characters > maximumEncodedCharacters) return false;

      final codeUnit = data.codeUnitAt(index);
      if (codeUnit >= 0xd800 && codeUnit <= 0xdbff && index + 1 < data.length) {
        final next = data.codeUnitAt(index + 1);
        if (next >= 0xdc00 && next <= 0xdfff) index += 1;
      }
    }
    return true;
  }

  final String reply;
  final String action;
  final String? title;
  final int? categoryId;
  final List<TopicTag> tags;
  final int? replyToPostNumber;
  final String? replyToUsername;

  /// Time spent typing, which is what the fast-typer check measures.
  final Duration typingTime;

  /// Wall clock since the composer opened.
  final Duration composerTime;

  Map<String, dynamic> toJson() => {
    'reply': reply,
    'action': action,
    'title': ?title,
    'categoryId': ?categoryId,
    'tags': [for (final tag in tags) tag.toJson()],
    'archetypeId': 'regular',
    'reply_to_post_number': replyToPostNumber,
    'reply_to_user': replyToUsername == null
        ? null
        : {'username': replyToUsername},
    'typingTime': typingTime.inMilliseconds,
    'composerTime': composerTime.inMilliseconds,
  };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComposerDraft &&
          other.reply == reply &&
          other.action == action &&
          other.title == title &&
          other.categoryId == categoryId &&
          listEquals(other.tags, tags) &&
          other.replyToPostNumber == replyToPostNumber &&
          other.replyToUsername == replyToUsername &&
          other.typingTime == typingTime &&
          other.composerTime == composerTime;

  @override
  int get hashCode => Object.hash(
    reply,
    action,
    title,
    categoryId,
    Object.hashAll(tags),
    replyToPostNumber,
    replyToUsername,
    typingTime,
    composerTime,
  );
}
