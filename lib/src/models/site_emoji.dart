import 'package:flutter/foundation.dart';

/// One emoji a site allows, by the name someone types between colons.
///
/// The [url] is kept rather than rebuilt through `SiteConfig.emojiUrl`: it is
/// the site's own answer for that exact name, custom uploads included, and it
/// therefore cannot disagree with the site about which file a name maps to.
@immutable
class SiteEmoji {
  const SiteEmoji({required this.name, required this.url});

  final String name;
  final String url;

  /// How well [query] matches, lowest first, or null for no match at all.
  ///
  /// Exact beats prefix beats anywhere, then the shorter name — someone typing
  /// `:sm` wants `smile` above `smiling_face_with_three_hearts`, and typing the
  /// whole of `:grin` wants `grin` above `grinning`.
  int? rank(String query) {
    if (name == query) return 0;
    if (name.startsWith(query)) return 1;
    if (name.contains(query)) return 2;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SiteEmoji && other.name == name && other.url == url);

  @override
  int get hashCode => Object.hash(name, url);
}
