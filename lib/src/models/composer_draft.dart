import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'json.dart';
import 'topic_tag.dart';

@immutable
class ComposerDraft {
  const ComposerDraft({
    required this.reply,
    this.action = replyAction,
    this.title,
    this.categoryId,
    this.tags = const [],
    this.archetypeId = regularArchetype,
    this.recipients,
    this.replyToPostNumber,
    this.replyToUsername,
    this.whisper = false,
    this.typingTime = Duration.zero,
    this.composerTime = Duration.zero,
  });

  static const String replyAction = 'reply';
  static const String createTopicAction = 'createTopic';
  static const String privateMessageAction = 'privateMessage';
  static const String newTopicDraftKey = 'new_topic';
  static const String newPrivateMessageDraftKey = 'new_private_message';
  static const String regularArchetype = 'regular';
  static const String privateMessageArchetype = 'private_message';

  static const int maximumEncodedCharacters = 150000;

  factory ComposerDraft.fromJson(Map<String, dynamic> json) => ComposerDraft(
    reply: jsonString(json['reply']),
    action: jsonText(json['action']) ?? replyAction,
    title: jsonText(json['title']),
    categoryId: jsonIntOrNull(json['categoryId']),
    tags: List.unmodifiable(
      jsonArray(json['tags']).map(TopicTag.parse).whereType<TopicTag>(),
    ),
    archetypeId:
        jsonText(json['archetypeId']) ?? ComposerDraft.regularArchetype,
    recipients: jsonText(json['recipients']),
    replyToPostNumber: jsonIntOrNull(json['reply_to_post_number']),
    replyToUsername: switch (json['reply_to_user']) {
      final Map<String, dynamic> user => jsonText(user['username']),
      final String username => jsonText(username),
      _ => null,
    },
    whisper: json['whisper'] == true,
    typingTime: Duration(milliseconds: jsonInt(json['typingTime'])),
    composerTime: Duration(milliseconds: jsonInt(json['composerTime'])),
  );

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
  final String archetypeId;
  final String? recipients;
  final int? replyToPostNumber;
  final String? replyToUsername;
  final bool whisper;

  final Duration typingTime;

  final Duration composerTime;

  Map<String, dynamic> toJson() => {
    'reply': reply,
    'action': action,
    'title': ?title,
    'categoryId': ?categoryId,
    'tags': [for (final tag in tags) tag.toJson()],
    'archetypeId': archetypeId,
    'recipients': ?recipients,
    'reply_to_post_number': replyToPostNumber,
    'reply_to_user': replyToUsername == null
        ? null
        : {'username': replyToUsername},
    'whisper': whisper,
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
          other.archetypeId == archetypeId &&
          other.recipients == recipients &&
          other.replyToPostNumber == replyToPostNumber &&
          other.replyToUsername == replyToUsername &&
          other.whisper == whisper &&
          other.typingTime == typingTime &&
          other.composerTime == composerTime;

  @override
  int get hashCode => Object.hash(
    reply,
    action,
    title,
    categoryId,
    Object.hashAll(tags),
    archetypeId,
    recipients,
    replyToPostNumber,
    replyToUsername,
    whisper,
    typingTime,
    composerTime,
  );
}
