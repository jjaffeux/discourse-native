import 'package:flutter/foundation.dart';

import 'json.dart';

/// One tag offered by Discourse's built-in sidebar Tags section.
@immutable
final class SidebarTag {
  const SidebarTag({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.pmOnly = false,
    this.count = 0,
  });

  /// Reads a live tag record or a persisted [toJson] snapshot.
  ///
  /// A malformed optional field falls back independently. Records without a
  /// usable identity are omitted, because they cannot produce a stable sidebar
  /// destination or a canonical tag-list route.
  static SidebarTag? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final json = value;
    final id = jsonIntOrNull(json['id']);
    final name = jsonText(json['name']);
    if (id == null || id <= 0 || name == null) return null;

    final pmOnly = json['pm_only'] == true || json['pmOnly'] == true;
    final topicCount =
        jsonIntOrNull(json['count']) ?? jsonInt(json['topic_count']);
    final parsedCount = pmOnly
        ? jsonIntOrNull(json['pm_count']) ?? topicCount
        : topicCount;
    return SidebarTag(
      id: id,
      name: name,
      slug: jsonText(json['slug']) ?? name,
      description: jsonText(json['description']),
      pmOnly: pmOnly,
      count: parsedCount < 0 ? 0 : parsedCount,
    );
  }

  /// The stable identity Discourse includes in canonical tag routes.
  final int id;
  final String name;

  /// The route slug, falling back to [name] when the wire record omitted one.
  final String slug;
  final String? description;

  /// Whether the tag belongs to private messages rather than public topics.
  final bool pmOnly;

  /// The non-negative directory count supplied for topics or private messages.
  final int count;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    if (description != null) 'description': description,
    'pmOnly': pmOnly,
    'count': count,
  };

  @override
  bool operator ==(Object other) =>
      other is SidebarTag &&
      other.id == id &&
      other.name == name &&
      other.slug == slug &&
      other.description == description &&
      other.pmOnly == pmOnly &&
      other.count == count;

  @override
  int get hashCode => Object.hash(id, name, slug, description, pmOnly, count);
}
