import 'package:flutter/foundation.dart';

import 'composer_draft.dart';
import 'json.dart';

/// One server-side draft from `/drafts.json`.
///
/// [data] is the same portable composer payload used when a topic is opened.
/// The list endpoint also supplies enough topic metadata to name and resume a
/// draft without first rendering a topic-list row.
@immutable
class UserDraft {
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
  });

  factory UserDraft.fromJson(Map<String, dynamic> json) => UserDraft(
    key: jsonString(json['draft_key']),
    sequence: jsonInt(json['sequence']),
    data: switch (json['data']) {
      final String value => ComposerDraft.decode(value),
      final Map<String, dynamic> value => ComposerDraft.fromJson(value),
      _ => null,
    },
    createdAt: jsonDate(json['created_at']),
    topicId: jsonIntOrNull(json['topic_id']),
    title: jsonText(json['title']),
    slug: jsonText(json['slug']),
    categoryId: jsonIntOrNull(json['category_id']),
    archetype: jsonText(json['archetype']),
  );

  final String key;
  final int sequence;
  final ComposerDraft? data;
  final DateTime? createdAt;
  final int? topicId;
  final String? title;
  final String? slug;
  final int? categoryId;
  final String? archetype;

  /// The list endpoint names the category beside existing topics, while a
  /// new-topic draft keeps it inside the portable composer payload.
  int? get displayCategoryId => categoryId ?? data?.categoryId;

  bool get isNewTopic => key.startsWith(ComposerDraft.newTopicDraftKey);

  bool get isPrivateMessage =>
      key.startsWith('new_private_message') || archetype == 'private_message';

  bool get isEdit =>
      key.startsWith('edit_topic') ||
      (data?.action.startsWith('edit') ?? false);

  /// The composer modes this client can faithfully restore today.
  bool get canResume =>
      data != null &&
      ((key == ComposerDraft.newTopicDraftKey) ||
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
    if (isNewTopic) return 'New topic draft';
    if (isEdit) return 'Edit topic draft';
    if (isPrivateMessage) return 'Personal message draft';
    return 'Reply draft';
  }

  String get excerpt =>
      (data?.reply ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
}
