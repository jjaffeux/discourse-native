import 'package:flutter/foundation.dart';

import 'json.dart';

/// One tag attached to a topic or selected in the topic composer.
@immutable
class TopicTag {
  const TopicTag({
    required this.name,
    this.id,
    this.slug,
    this.count = 0,
    this.disabled = false,
    this.disabledReason,
  });

  static TopicTag? parse(Object? value) {
    if (value is String) {
      final name = jsonText(value);
      return name == null ? null : TopicTag(name: name);
    }
    if (value is! Map<String, dynamic>) return null;

    final name = jsonText(value['name']);
    if (name == null) return null;
    return TopicTag(
      id: jsonIntOrNull(value['id']),
      name: name,
      slug: jsonText(value['slug']),
      count: jsonInt(value['count']),
      disabled: value['disabled'] == true,
      disabledReason: jsonText(value['title']),
    );
  }

  final int? id;
  final String name;
  final String? slug;
  final int count;
  final bool disabled;
  final String? disabledReason;

  Map<String, dynamic> toJson() => {'id': ?id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is TopicTag &&
      other.id == id &&
      other.name == name &&
      other.slug == slug &&
      other.count == count &&
      other.disabled == disabled &&
      other.disabledReason == disabledReason;

  @override
  int get hashCode =>
      Object.hash(id, name, slug, count, disabled, disabledReason);
}
