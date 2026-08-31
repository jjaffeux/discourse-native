import 'package:flutter/foundation.dart';

import 'composer_draft.dart';
import 'json.dart';

@immutable
class UserDraft {
  static const resenhaTranscriptDraftKeyPrefix = 'new_topic_resenha_';

  const UserDraft({
    required this.key,
    required this.sequence,
    required this.data,
    this.createdAt,
    this.topicId,
    this.title,
    this.slug,
    this.categoryId,
    this.archetype,
  }) : _excerpt = null;

  UserDraft._parsed({
    required this.key,
    required this.sequence,
    required this.data,
    this.createdAt,
    this.topicId,
    this.title,
    this.slug,
    this.categoryId,
    this.archetype,
  }) : _excerpt = _normalizeExcerpt(data?.reply ?? '');

  factory UserDraft.fromJson(Map<String, dynamic> json) {
    final data = switch (json['data']) {
      final String value => ComposerDraft.decode(value),
      final Map<String, dynamic> value => ComposerDraft.fromJson(value),
      _ => null,
    };
    return UserDraft._parsed(
      key: jsonString(json['draft_key']),
      sequence: jsonInt(json['sequence']),
      data: data,
      createdAt: jsonDate(json['created_at']),
      topicId: jsonIntOrNull(json['topic_id']),
      title: jsonText(json['title']),
      slug: jsonText(json['slug']),
      categoryId: jsonIntOrNull(json['category_id']),
      archetype: jsonText(json['archetype']),
    );
  }

  final String key;
  final int sequence;
  final ComposerDraft? data;
  final DateTime? createdAt;
  final int? topicId;
  final String? title;
  final String? slug;
  final int? categoryId;
  final String? archetype;
  final String? _excerpt;

  static final RegExp _whitespace = RegExp(r'\s+');

  int? get displayCategoryId => categoryId ?? data?.categoryId;

  bool get isNewTopic => key.startsWith(ComposerDraft.newTopicDraftKey);

  bool get isResenhaTranscript =>
      key.startsWith(resenhaTranscriptDraftKeyPrefix);

  bool get isPrivateMessage =>
      key.startsWith('new_private_message') || archetype == 'private_message';

  bool get isEdit =>
      key.startsWith('edit_topic') ||
      (data?.action.startsWith('edit') ?? false);

  bool get canResume =>
      data != null &&
      (isNewTopic ||
          (!isEdit &&
              !key.startsWith('new_private_message') &&
              topicId != null));

  String get displayTitle =>
      (isNewTopic ? data?.title : title) ??
      title ??
      data?.title ??
      'Untitled draft';

  String get kindLabel {
    if (key.startsWith('new_private_message')) {
      return 'New personal message draft';
    }
    if (isResenhaTranscript) return 'Call transcript draft';
    if (isNewTopic) return 'New topic draft';
    if (isEdit) return 'Edit topic draft';
    if (isPrivateMessage) return 'Personal message draft';
    return 'Reply draft';
  }

  String get excerpt => _excerpt ?? _normalizeExcerpt(data?.reply ?? '');

  static String _normalizeExcerpt(String source) =>
      source.trim().replaceAll(_whitespace, ' ');
}
