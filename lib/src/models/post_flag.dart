import 'package:flutter/foundation.dart';

import 'json.dart';

/// One flag reason advertised by Discourse in `/site.json`.
///
/// Names and descriptions are already localized by the site. Permissions do
/// not live here: the matching row in a post's `actions_summary` is the
/// authoritative answer for the current reader and post.
@immutable
final class PostFlagType {
  const PostFlagType({
    required this.id,
    required this.nameKey,
    required this.name,
    required this.description,
    this.shortDescription = '',
    this.requireMessage = false,
    this.enabled = true,
    this.appliesTo = const [],
    this.system = false,
  });

  /// The fixed maximum used by Discourse's web flag composer.
  static const int maximumMessageLength = 500;

  static PostFlagType? tryParse(Map<String, dynamic> json) {
    if (json['is_flag'] != true) return null;
    final id = jsonIntOrNull(json['id']);
    final nameKey = jsonText(json['name_key']);
    final name = jsonText(json['name']);
    if (id == null || id <= 0 || nameKey == null || name == null) return null;

    return PostFlagType(
      id: id,
      nameKey: nameKey,
      name: name,
      description: jsonText(json['description']) ?? '',
      shortDescription: jsonText(json['short_description']) ?? '',
      requireMessage: json['require_message'] == true,
      enabled: json['enabled'] != false,
      appliesTo: List.unmodifiable(
        jsonArray(json['applies_to']).map(jsonText).whereType<String>(),
      ),
      system: json['system'] == true,
    );
  }

  final int id;
  final String nameKey;
  final String name;
  final String description;
  final String shortDescription;
  final bool requireMessage;
  final bool enabled;
  final List<String> appliesTo;
  final bool system;

  bool get appliesToPost => appliesTo.contains('Post');
  bool get appliesToTopic => appliesTo.contains('Topic');
  bool get appliesToChatMessage => appliesTo.contains('Chat::Message');
  bool get isIllegal => nameKey == 'illegal';

  @override
  bool operator ==(Object other) =>
      other is PostFlagType &&
      other.id == id &&
      other.nameKey == nameKey &&
      other.name == name &&
      other.description == description &&
      other.shortDescription == shortDescription &&
      other.requireMessage == requireMessage &&
      other.enabled == enabled &&
      listEquals(other.appliesTo, appliesTo) &&
      other.system == system;

  @override
  int get hashCode => Object.hash(
    id,
    nameKey,
    name,
    description,
    shortDescription,
    requireMessage,
    enabled,
    Object.hashAll(appliesTo),
    system,
  );
}

/// The flag portion of a site's post-action catalog.
///
/// A non-null empty catalog is meaningful: the site answered successfully and
/// has no post flags. Callers use null separately for metadata that was never
/// requested or failed to load.
@immutable
final class SitePostActionCatalog {
  const SitePostActionCatalog({
    this.postFlags = const [],
    this.topicFlags = const [],
  });

  factory SitePostActionCatalog.fromJson(Map<String, dynamic> json) =>
      SitePostActionCatalog(
        postFlags: List.unmodifiable([
          for (final item in jsonObjects(json['post_action_types']))
            ?PostFlagType.tryParse(item),
        ]),
        topicFlags: List.unmodifiable([
          for (final item in jsonObjects(json['topic_flag_types']))
            ?PostFlagType.tryParse(item),
        ]),
      );

  final List<PostFlagType> postFlags;
  final List<PostFlagType> topicFlags;

  @override
  bool operator ==(Object other) =>
      other is SitePostActionCatalog &&
      listEquals(other.postFlags, postFlags) &&
      listEquals(other.topicFlags, topicFlags);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(postFlags), Object.hashAll(topicFlags));
}

/// One personalized row from a post's `actions_summary`.
@immutable
final class PostActionSummary {
  const PostActionSummary({
    required this.id,
    this.count = 0,
    this.acted = false,
    this.canAct = false,
    this.canUndo = false,
  });

  factory PostActionSummary.fromJson(Map<String, dynamic> json) =>
      PostActionSummary(
        id: jsonInt(json['id']),
        count: jsonInt(json['count']),
        acted: json['acted'] == true,
        canAct: json['can_act'] == true,
        canUndo: json['can_undo'] == true,
      );

  final int id;
  final int count;
  final bool acted;
  final bool canAct;
  final bool canUndo;

  @override
  bool operator ==(Object other) =>
      other is PostActionSummary &&
      other.id == id &&
      other.count == count &&
      other.acted == acted &&
      other.canAct == canAct &&
      other.canUndo == canUndo;

  @override
  int get hashCode => Object.hash(id, count, acted, canAct, canUndo);
}
