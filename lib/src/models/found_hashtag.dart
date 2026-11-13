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

  List<int> get colorValues => [
    for (final color in colors) categoryColorValue(color),
  ];

  static FoundHashtag? resolveRef(
    String requestedRef, {
    required Iterable<FoundHashtag> candidates,
    required List<String> order,
    required Set<String> requestedRefs,
  }) {
    final bareName = requestedRef.contains('::')
        ? null
        : requestedRef.toLowerCase();
    for (final type in order) {
      if (bareName != null &&
          requestedRefs.any((ref) {
            final separator = ref.indexOf('::');
            return separator >= 0 &&
                ref.substring(separator + 2) == type &&
                ref.substring(0, separator).toLowerCase() == bareName;
          })) {
        continue;
      }
      for (final candidate in candidates) {
        if (candidate.type == type && candidate.matchesRef(requestedRef)) {
          return candidate;
        }
      }
    }
    return null;
  }

  bool matchesRef(String requestedRef) {
    final requestedAt = requestedRef.indexOf('::');
    final canonicalAt = ref.indexOf('::');
    if (requestedAt >= 0 &&
        (requestedRef.indexOf('::', requestedAt + 2) >= 0 ||
            requestedRef.substring(requestedAt + 2) != type)) {
      return false;
    }
    if (canonicalAt >= 0 &&
        (requestedAt < 0 ||
            ref.indexOf('::', canonicalAt + 2) >= 0 ||
            ref.substring(canonicalAt + 2) != type)) {
      return false;
    }
    final requestedName = requestedAt < 0
        ? requestedRef
        : requestedRef.substring(0, requestedAt);
    final canonicalName = canonicalAt < 0 ? ref : ref.substring(0, canonicalAt);
    return requestedName.toLowerCase() == canonicalName.toLowerCase();
  }

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
