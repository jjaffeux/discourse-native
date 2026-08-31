import 'package:flutter/foundation.dart';

import 'json.dart';

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

  final int id;
  final String name;

  final String slug;
  final String? description;

  final bool pmOnly;

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
