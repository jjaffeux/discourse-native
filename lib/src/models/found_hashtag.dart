import 'package:flutter/foundation.dart';

import 'json.dart';

@immutable
class FoundHashtag {
  const FoundHashtag({
    required this.type,
    required this.ref,
    required this.slug,
    required this.text,
    required this.id,
    this.relativeUrl = '',
    this.description,
    this.secondaryText,
    this.styleType = 'square',
    this.icon,
    this.emoji,
    this.colors = const [],
  });

  static const int maximumColors = 2;

  static FoundHashtag? fromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    final type = rawType is String && rawType.trim().isNotEmpty
        ? rawType
        : null;
    final ref = jsonText(json['ref']) ?? jsonText(json['slug']);
    if (type == null || ref == null) return null;

    return FoundHashtag(
      type: type,
      ref: ref,
      slug: jsonText(json['slug']) ?? ref,
      text: jsonText(json['text']) ?? ref,
      id: jsonInt(json['id']),
      relativeUrl: jsonText(json['relative_url']) ?? '',
      description: jsonText(json['description']),
      // Usually tags, and the reason it is a string rather than a count: the
      // site has already formatted it (`x0`), and reformatting it here would be
      // guessing at a convention we do not own.
      secondaryText: jsonText(json['secondary_text']),
      styleType: jsonText(json['style_type']) ?? 'square',
      icon: jsonText(json['icon']),
      emoji: jsonText(json['emoji']),
      colors: List.unmodifiable(
        jsonArray(json['colors'])
            .whereType<String>()
            .where((color) => color.isNotEmpty)
            .take(maximumColors),
      ),
    );
  }

  final String type;

  final String ref;

  final String slug;

  final String text;

  final int id;
  final String relativeUrl;
  final String? description;
  final String? secondaryText;

  final String styleType;

  final String? icon;
  final String? emoji;

  final List<String> colors;

  static int _value(String color) =>
      int.tryParse('FF$color', radix: 16) ?? 0xFF888888;

  List<int> get colorValues => [for (final color in colors) _value(color)];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoundHashtag &&
          other.type == type &&
          other.ref == ref &&
          other.id == id);

  @override
  int get hashCode => Object.hash(type, ref, id);
}
