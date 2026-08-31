import 'package:flutter/foundation.dart';

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

  String codeFor(EmojiSkinTone tone) =>
      !tonable || tone == EmojiSkinTone.neutral
      ? name
      : '$name${tone.shortcodeSuffix}';

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
