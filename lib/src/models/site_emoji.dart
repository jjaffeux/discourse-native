import 'package:flutter/foundation.dart';

const siteEmojiNameCharacterClass =
    r'[\p{Alphabetic}\p{Mark}\p{Decimal_Number}_+\-]';

final siteEmojiShortcodePattern = RegExp(
  ':($siteEmojiNameCharacterClass+(?::t[1-6])?):',
  unicode: true,
);

final _emojiWordEnd = RegExp(
  r'[\p{Alphabetic}\p{Mark}\p{Decimal_Number}]$',
  unicode: true,
);
final _emojiLiteralCode = RegExp(r'(?<!`)(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)');

/// Shortcodes in plain presentation text share the composer's word boundary
/// and leave backtick-delimited code literal, including multiline fences.
Iterable<RegExpMatch> siteEmojiShortcodeMatches(String text) sync* {
  final code = _emojiLiteralCode.allMatches(text).iterator;
  var hasCode = code.moveNext();
  for (final match in siteEmojiShortcodePattern.allMatches(text)) {
    if (match.start > 0 &&
        _emojiWordEnd.hasMatch(
          text.substring((match.start - 2).clamp(0, match.start), match.start),
        )) {
      continue;
    }
    while (hasCode && code.current.end <= match.start) {
      hasCode = code.moveNext();
    }
    if (hasCode && code.current.start < match.end) continue;
    yield match;
  }
}

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
    this.animated = false,
  });

  final String name;
  final String url;
  final bool tonable;
  final bool animated;

  /// The animation shares the static asset's origin, subfolder and skin tone.
  /// Upload-backed custom emoji never match the standard emoji asset path.
  String? animatedUrlFor(EmojiSkinTone tone) {
    if (!animated) return null;
    final uri = Uri.tryParse(urlFor(tone));
    if (uri == null) return null;
    final match = RegExp(
      r'/images/emoji/[^/]+/(.+)\.[^/.]+$',
    ).firstMatch(uri.path);
    if (match == null) return null;
    final prefix = uri.path.substring(0, match.start);
    return uri
        .replace(path: '$prefix/images/emoji/noto_animated/${match[1]}.avif')
        .toString();
  }

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
          other.tonable == tonable &&
          other.animated == animated);

  @override
  int get hashCode => Object.hash(name, url, tonable, animated);
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

  String? animatedUrlFor(String code, {String? staticUrl}) {
    final toned = RegExp(r':t([1-6])$').firstMatch(code);
    final name = toned == null ? code : code.substring(0, toned.start);
    final tone = EmojiSkinTone.fromCode(
      toned?.group(1) == null ? null : int.parse(toned!.group(1)!),
    );
    final emoji =
        emojiNamed(name) ??
        (staticUrl == null
            ? null
            : all
                  .where((entry) => entry.urlFor(tone) == staticUrl)
                  .firstOrNull);
    return emoji?.animatedUrlFor(tone);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SiteEmojiCatalog && listEquals(other.groups, groups));

  @override
  int get hashCode => Object.hashAll(groups);
}
