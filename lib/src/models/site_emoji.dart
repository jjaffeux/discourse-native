import 'package:flutter/foundation.dart';

/// The skin-tone variants Discourse accepts in an emoji shortcode.
///
/// Discourse's neutral artwork has no suffix. The five selectable variants
/// deliberately start at `t2`; `t1` is an internal web-picker sentinel and is
/// never written into cooked content.
enum EmojiSkinTone {
  neutral(null),
  t2(2),
  t3(3),
  t4(4),
  t5(5),
  t6(6);

  const EmojiSkinTone(this.number);

  final int? number;

  String get code => number == null ? 'neutral' : 't$number';

  String get shortcodeSuffix => number == null ? '' : ':t$number';

  static EmojiSkinTone fromCode(Object? value) => switch (value) {
    't2' || 2 => t2,
    't3' || 3 => t3,
    't4' || 4 => t4,
    't5' || 5 => t5,
    't6' || 6 => t6,
    _ => neutral,
  };
}

/// One emoji a site allows, by the name someone types between colons.
///
/// The [url] is kept rather than rebuilt through `SiteConfig.emojiUrl`: it is
/// the site's own answer for that exact name, custom uploads included, and it
/// therefore cannot disagree with the site about which file a name maps to.
@immutable
class SiteEmoji {
  const SiteEmoji({
    required this.name,
    required this.url,
    this.tonable = false,
  });

  final String name;
  final String url;
  final bool tonable;

  /// The bare shortcode value written between the surrounding colons.
  String codeFor(EmojiSkinTone tone) =>
      !tonable || tone == EmojiSkinTone.neutral
      ? name
      : '$name${tone.shortcodeSuffix}';

  /// Artwork for [tone], retaining the endpoint's host, query and fragment.
  ///
  /// Discourse stores a toned built-in next to its neutral image: for example,
  /// `wave.png?v=12` becomes `wave/3.png?v=12`. Custom emoji report
  /// [tonable] as false and therefore always keep their exact upload URL.
  String urlFor(EmojiSkinTone tone) {
    final toneNumber = tone.number;
    if (!tonable || toneNumber == null) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.path.isEmpty) return url;
    final path = uri.path;
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    final tonedPath = dot > slash
        ? '${path.substring(0, dot)}/$toneNumber${path.substring(dot)}'
        : '${path.endsWith('/') ? path.substring(0, path.length - 1) : path}/$toneNumber';
    return uri.replace(path: tonedPath).toString();
  }

  /// How well [query] matches, lowest first, or null for no match at all.
  ///
  /// Kept as the canonical-name portion of picker search. Alias ranking is
  /// catalog state and therefore belongs to `SitePresentationController`.
  int? rank(String query) {
    if (name == query) return 0;
    if (name.startsWith(query)) return 1;
    if (name.contains(query)) return 2;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SiteEmoji &&
          other.name == name &&
          other.url == url &&
          other.tonable == tonable);

  @override
  int get hashCode => Object.hash(name, url, tonable);
}

/// One server-defined picker group, retaining its opaque identifier.
@immutable
final class SiteEmojiGroup {
  factory SiteEmojiGroup({
    required String id,
    required Iterable<SiteEmoji> emojis,
  }) => SiteEmojiGroup._(id, List<SiteEmoji>.unmodifiable(emojis));

  const SiteEmojiGroup._(this.id, this.emojis);

  final String id;
  final List<SiteEmoji> emojis;

  bool get isEmpty => emojis.isEmpty;
  bool get isNotEmpty => emojis.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SiteEmojiGroup &&
          other.id == id &&
          listEquals(other.emojis, emojis));

  @override
  int get hashCode => Object.hash(id, Object.hashAll(emojis));
}

/// The complete picker catalog in the exact group order the site supplied.
@immutable
final class SiteEmojiCatalog {
  factory SiteEmojiCatalog({required Iterable<SiteEmojiGroup> groups}) {
    final immutableGroups = List<SiteEmojiGroup>.unmodifiable(groups);
    final all = List<SiteEmoji>.unmodifiable(
      immutableGroups.expand((group) => group.emojis),
    );
    final byName = <String, SiteEmoji>{};
    for (final emoji in all) {
      // Malformed duplicate rows must not silently replace the first artwork
      // the server placed in its authoritative group order.
      byName.putIfAbsent(emoji.name, () => emoji);
    }
    return SiteEmojiCatalog._(
      immutableGroups,
      all,
      Map<String, SiteEmoji>.unmodifiable(byName),
      List<SiteEmoji>.unmodifiable(
        byName.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
      ),
    );
  }

  const SiteEmojiCatalog._(
    this.groups,
    this.all,
    this.byName,
    this.alphabetical,
  );

  static final empty = SiteEmojiCatalog(groups: const []);

  final List<SiteEmojiGroup> groups;
  final List<SiteEmoji> all;
  final Map<String, SiteEmoji> byName;

  /// Every distinct emoji in name order.
  ///
  /// Picker search reads the whole site's artwork in this order on each
  /// keystroke and the order never changes, so it is derived once here with
  /// the catalog's other index rather than sorted again per query. Duplicate
  /// names collapse exactly as [byName] collapses them, so a malformed second
  /// row cannot displace the artwork the site listed first.
  final List<SiteEmoji> alphabetical;

  bool get isEmpty => all.isEmpty;
  bool get isNotEmpty => all.isNotEmpty;

  SiteEmoji? emojiNamed(String name) => byName[name];

  SiteEmojiGroup? groupNamed(String id) {
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SiteEmojiCatalog && listEquals(other.groups, groups));

  @override
  int get hashCode => Object.hashAll(groups);
}
