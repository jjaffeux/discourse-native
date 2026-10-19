// ignore_for_file: prefer_initializing_formals

import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import '../../models/composer_draft.dart';
import '../../models/composer_upload.dart';
import '../../models/topic_tag.dart';
import '../../plugin_api/emoji_usage.dart';

enum ComposerMode {
  reply,
  newTopic,
  privateMessage,
  postEdit,
  topicEdit,
  categoryEdit,
  tagsEdit,
  plugin,
}

@immutable
final class ComposerTargetKind {
  const ComposerTargetKind({required this.owner, required this.name});

  final PluginId owner;
  final String name;

  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is ComposerTargetKind && other.owner == owner && other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => id;
}

enum ComposerUploadDisposition { insertMarkdown, retainAttachment }

@immutable
final class ComposerValidationContext {
  const ComposerValidationContext({
    required this.raw,
    required this.completedUploadCount,
  });

  final String raw;
  final int completedUploadCount;
}

typedef ComposerTargetValidator =
    bool Function(ComposerValidationContext context);

@immutable
final class ComposerTargetPolicy {
  const ComposerTargetPolicy({
    required this.kind,
    required this.draftKey,
    required this.uploadType,
    required this.uploadDisposition,
    required this.uploadsEnabled,
    required this.supportsEditing,
    required this.validate,
    required this.emojiUsageContext,
    this.mentionTopicId,
  });

  final ComposerTargetKind kind;
  final String draftKey;
  final ComposerUploadType uploadType;
  final ComposerUploadDisposition uploadDisposition;
  final bool uploadsEnabled;
  final bool supportsEditing;
  final EmojiUsageContext emojiUsageContext;
  final int? mentionTopicId;
  final ComposerTargetValidator validate;
}

@immutable
final class ComposerTargetRequest {
  const ComposerTargetRequest({
    required this.kind,
    required this.siteUrl,
    required this.title,
    this.data = const {},
  });

  final ComposerTargetKind kind;
  final String siteUrl;
  final String title;
  final Map<String, Object?> data;
}

@immutable
sealed class ComposerTarget {
  const ComposerTarget._({
    required this.siteUrl,
    required this.topicTitle,
    this.tabId,
  });

  final String siteUrl;
  final String topicTitle;

  /// The initiating tab, retained as source metadata rather than ownership.
  final String? tabId;

  ComposerMode get mode => switch (this) {
    ReplyComposerTarget() => ComposerMode.reply,
    NewTopicComposerTarget() => ComposerMode.newTopic,
    PrivateMessageComposerTarget() => ComposerMode.privateMessage,
    PostEditComposerTarget() => ComposerMode.postEdit,
    TopicEditComposerTarget() => ComposerMode.topicEdit,
    CategoryEditComposerTarget() => ComposerMode.categoryEdit,
    TagsEditComposerTarget() => ComposerMode.tagsEdit,
    PluginComposerTarget() => ComposerMode.plugin,
  };

  String get draftKey;
  bool get isEdit => this is EditComposerTarget;
  bool get isNewTopic => this is NewTopicComposerTarget;
  bool get isPrivateMessage => this is PrivateMessageComposerTarget;
  bool get createsTopic => this is TopicCreationComposerTarget;
  bool get editsTopicMetadata => this is TopicEditComposerTarget;
  bool get isCategoryEdit => this is CategoryEditComposerTarget;
  bool get isTagsEdit => this is TagsEditComposerTarget;
  bool get isTaxonomyEdit => isCategoryEdit || isTagsEdit;
  bool get isPlugin => this is PluginComposerTarget;

  int? get initialCategoryId => null;
  List<TopicTag> get initialTags => const [];
  String? get originFeedId => null;
  int? get originTopicId => null;
  String? get targetRecipients => null;
  int? get replyToPostNumber => null;
  String? get replyToUsername => null;
  bool get replyingToWhisper => false;

  /// Existing-topic privacy is independent of creating a new message.
  bool get privateMessageTopic => false;

  int? get mentionTopicId => switch (this) {
    ExistingTopicComposerTarget(:final topicId) => topicId,
    PluginComposerTarget(:final policy) => policy.mentionTopicId,
    TopicCreationComposerTarget() => null,
  };
}

sealed class ExistingTopicComposerTarget extends ComposerTarget {
  const ExistingTopicComposerTarget._({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required this.topicId,
    required this.slug,
    required this.privateMessageTopic,
  }) : super._();

  final int topicId;
  final String slug;
  @override
  final bool privateMessageTopic;

  @override
  String get draftKey => 'topic_$topicId';
}

final class ReplyComposerTarget extends ExistingTopicComposerTarget {
  const ReplyComposerTarget({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required super.topicId,
    required super.slug,
    required super.privateMessageTopic,
    this.replyToPostNumber,
    this.replyToUsername,
    this.replyingToWhisper = false,
    String? draftKey,
  }) : _draftKey = draftKey,
       super._();

  @override
  final int? replyToPostNumber;
  @override
  final String? replyToUsername;
  @override
  final bool replyingToWhisper;
  final String? _draftKey;

  @override
  String get draftKey => _draftKey ?? super.draftKey;

  ReplyComposerTarget replyingTo(
    int? postNumber,
    String? username, {
    bool replyingToWhisper = false,
  }) => ReplyComposerTarget(
    siteUrl: siteUrl,
    topicTitle: topicTitle,
    tabId: tabId,
    topicId: topicId,
    slug: slug,
    privateMessageTopic: privateMessageTopic,
    replyToPostNumber: postNumber,
    replyToUsername: username,
    replyingToWhisper: replyingToWhisper,
    draftKey: _draftKey,
  );
}

sealed class EditComposerTarget extends ExistingTopicComposerTarget {
  const EditComposerTarget._({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required super.topicId,
    required super.slug,
    required super.privateMessageTopic,
  }) : super._();
}

sealed class PostEditingComposerTarget extends EditComposerTarget {
  const PostEditingComposerTarget._({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required super.topicId,
    required super.slug,
    required super.privateMessageTopic,
    required this.editingPostId,
    required this.editingPostNumber,
  }) : super._();

  final int editingPostId;
  final int editingPostNumber;
}

final class PostEditComposerTarget extends PostEditingComposerTarget {
  const PostEditComposerTarget({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required super.topicId,
    required super.slug,
    required super.privateMessageTopic,
    required super.editingPostId,
    required super.editingPostNumber,
  }) : super._();
}

final class TopicEditComposerTarget extends PostEditingComposerTarget {
  const TopicEditComposerTarget({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required super.topicId,
    required super.slug,
    required super.privateMessageTopic,
    required super.editingPostId,
    this.initialCategoryId,
    this.initialTags = const [],
  }) : super._(editingPostNumber: 1);

  @override
  final int? initialCategoryId;
  @override
  final List<TopicTag> initialTags;
}

sealed class TaxonomyEditComposerTarget extends EditComposerTarget {
  const TaxonomyEditComposerTarget._({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required super.topicId,
    required super.slug,
    required super.privateMessageTopic,
    this.initialCategoryId,
    this.initialTags = const [],
    this.firstPostId,
  }) : super._();

  @override
  final int? initialCategoryId;
  @override
  final List<TopicTag> initialTags;

  final int? firstPostId;
}

final class CategoryEditComposerTarget extends TaxonomyEditComposerTarget {
  const CategoryEditComposerTarget({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required super.topicId,
    required super.slug,
    required super.privateMessageTopic,
    super.initialCategoryId,
    super.initialTags,
    super.firstPostId,
  }) : super._();
}

final class TagsEditComposerTarget extends TaxonomyEditComposerTarget {
  const TagsEditComposerTarget({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    required super.topicId,
    required super.slug,
    required super.privateMessageTopic,
    super.initialCategoryId,
    super.initialTags,
    super.firstPostId,
  }) : super._();
}

sealed class TopicCreationComposerTarget extends ComposerTarget {
  const TopicCreationComposerTarget._({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    this.originFeedId,
    this.originTopicId,
    String? draftKey,
  }) : _draftKey = draftKey,
       super._();

  @override
  final String? originFeedId;
  @override
  final int? originTopicId;
  final String? _draftKey;

  @override
  String get draftKey =>
      _draftKey ??
      switch (this) {
        NewTopicComposerTarget() => ComposerDraft.newTopicDraftKey,
        PrivateMessageComposerTarget() =>
          ComposerDraft.newPrivateMessageDraftKey,
      };
}

final class NewTopicComposerTarget extends TopicCreationComposerTarget {
  const NewTopicComposerTarget({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    super.originFeedId,
    super.originTopicId,
    super.draftKey,
    this.initialCategoryId,
    this.initialTags = const [],
  }) : super._();

  @override
  final int? initialCategoryId;
  @override
  final List<TopicTag> initialTags;
}

final class PrivateMessageComposerTarget extends TopicCreationComposerTarget {
  const PrivateMessageComposerTarget({
    required super.siteUrl,
    required super.topicTitle,
    super.tabId,
    super.originFeedId,
    super.originTopicId,
    super.draftKey,
    required this.targetRecipients,
  }) : super._();

  @override
  final String targetRecipients;

  PrivateMessageComposerTarget withRecipients(String recipients) =>
      PrivateMessageComposerTarget(
        siteUrl: siteUrl,
        topicTitle: topicTitle,
        tabId: tabId,
        originFeedId: originFeedId,
        originTopicId: originTopicId,
        draftKey: _draftKey,
        targetRecipients: recipients,
      );
}

final class PluginComposerTarget extends ComposerTarget {
  const PluginComposerTarget({
    required super.siteUrl,
    required super.topicTitle,
    required this.policy,
    this.data = const {},
  }) : super._();

  final ComposerTargetPolicy policy;
  final Map<String, Object?> data;

  @override
  String get draftKey => policy.draftKey;
}
