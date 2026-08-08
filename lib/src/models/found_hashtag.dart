import 'package:flutter/foundation.dart';

import 'json.dart';

/// One category or tag the site offered for a `#hashtag`.
///
/// Deliberately not [Storable], for the reason [FoundUser] gives and one of its
/// own: a category and a tag can share an id, so there is no single key to file
/// these under — and [text] is `Parent > Child` where `TopicCategory.name` is
/// just `Child`, so putting one in the store would corrupt the badge a topic
/// row draws.
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

  static FoundHashtag? fromJson(Map<String, dynamic> json) {
    final type = jsonText(json['type']);
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
      // Tags only, and the reason it is a string rather than a count: the site
      // has already formatted it (`x0`), and reformatting it here would be
      // guessing at a convention we do not own.
      secondaryText: jsonText(json['secondary_text']),
      styleType: jsonText(json['style_type']) ?? 'square',
      icon: jsonText(json['icon']),
      emoji: jsonText(json['emoji']),
      colors: List.unmodifiable([
        for (final color in jsonArray(json['colors']))
          if (color is String && color.isNotEmpty) color,
      ]),
    );
  }

  /// `category` or `tag`. Left as the site's own string rather than an enum:
  /// plugins add their own — chat adds `channel` — and a payload this app has
  /// no opinion about should travel through it rather than be dropped.
  final String type;

  /// What accepting this writes into the post — `parent:child`, `foo::tag`.
  ///
  /// Not [slug]: a subcategory needs its parent to be found again, and a tag
  /// whose slug collides with a category's carries a `::tag` suffix to say
  /// which it meant.
  final String ref;

  final String slug;

  /// What the site calls it — `Parent > Child` for a subcategory.
  final String text;

  final int id;
  final String relativeUrl;
  final String? description;
  final String? secondaryText;

  /// `square`, `icon` or `emoji`.
  final String styleType;

  final String? icon;
  final String? emoji;

  /// Six hex digits each, no leading `#`, in `[parent, child]` order — one
  /// entry for a top-level category, two for a subcategory, none for a tag.
  final List<String> colors;

  static int _value(String color) =>
      int.tryParse('FF$color', radix: 16) ?? 0xFF888888;

  /// [colors] as ARGB ints, so nothing here has to reach for `dart:ui` — the
  /// bargain `TopicCategory.colorValue` already makes.
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
