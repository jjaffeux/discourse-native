import 'contracts.dart';

/// Bounded immutable cached enrichment. This is a selected snapshot, never a
/// resolver or service; absent entries stay readable. Ingestion requires a host
/// account/generation lease just like upload metadata.
final class CookingCachedMetadata {
  CookingCachedMetadata({
    Map<String, CookingMention> mentions = const {},
    Map<String, String> avatars = const {},
    Map<String, String> primaryGroups = const {},
    Map<String, String> oneboxes = const {},
    Map<String, CookingInlineOnebox> inlineOneboxes = const {},
    Map<String, CookingTopic> topics = const {},
    Map<String, CookingMedia> media = const {},
    Map<String, String> emojiTranslations = const {},
    Map<String, String> unicodeEmoji = const {},
    List<String> emojiDenyList = const [],
    List<String> allowedMediaOrigins = const [],
    Map<String, List<String>> hashtagPriorities = const {},
    Map<String, String> hashtagIcons = const {},
    List<CookingCensor> censoredRegexp = const [],
    Map<String, CookingWatchedWord> watchedWordsReplace = const {},
    Map<String, CookingWatchedWord> watchedWordsLink = const {},
  }) : snapshot = CookingSnapshot(
         siteId: '',
         accountId: '',
         mentions: {
           for (final entry in mentions.entries)
             entry.key.toLowerCase(): entry.value.toJson(),
         },
         avatars: avatars,
         primaryGroups: primaryGroups,
         oneboxes: oneboxes,
         inlineOneboxes: {
           for (final entry in inlineOneboxes.entries)
             entry.key: entry.value.toJson(),
         },
         topics: {
           for (final entry in topics.entries) entry.key: entry.value.toJson(),
         },
         media: {
           for (final entry in media.entries) entry.key: entry.value.toJson(),
         },
         customEmojiTranslation: emojiTranslations,
         unicodeEmoji: unicodeEmoji,
         emojiDenyList: emojiDenyList,
         allowedMediaOrigins: allowedMediaOrigins,
         hashtagPriorities: hashtagPriorities,
         hashtagIcons: hashtagIcons,
         censoredRegexp: [for (final value in censoredRegexp) value.toJson()],
         watchedWordsReplace: {
           for (final entry in watchedWordsReplace.entries)
             entry.key: entry.value.toJson(),
         },
         watchedWordsLink: {
           for (final entry in watchedWordsLink.entries)
             entry.key: entry.value.toJson(),
         },
       );
  final CookingSnapshot snapshot;
}

/// Kind/eligibility must come from authoritative cached data, never inferred
/// from a boolean mention-existence cache. Final URI policy still applies.
final class CookingMention {
  const CookingMention({
    required this.username,
    required this.href,
    required this.kind,
  });
  final String username, href;
  final CookingMentionKind kind;
  Map<String, Object?> toJson() => {
    'username': username,
    'href': href,
    'kind': switch (kind) {
      CookingMentionKind.user => 'user',
      CookingMentionKind.group => 'group',
      CookingMentionKind.notifiableGroup => 'group-mentionable',
    },
  };
}

enum CookingMentionKind { user, group, notifiableGroup }

final class CookingTopic {
  const CookingTopic({required this.title, required this.href});
  final String title, href;
  Map<String, Object?> toJson() => {'title': title, 'href': href};
}

final class CookingMedia {
  const CookingMedia({
    required this.thumbnailUrl,
    required this.videoBase62Sha1,
  });
  final String thumbnailUrl, videoBase62Sha1;
  Map<String, Object?> toJson() => {
    'thumbnailUrl': thumbnailUrl,
    'videoBase62Sha1': videoBase62Sha1,
  };
}

final class CookingCensor {
  const CookingCensor(this.pattern, {this.caseSensitive = false});
  final String pattern;
  final bool caseSensitive;
  Map<String, Object?> toJson() => {
    pattern: {'case_sensitive': caseSensitive},
  };
}

final class CookingWatchedWord {
  const CookingWatchedWord({
    required this.pattern,
    required this.replacement,
    this.caseSensitive = false,
    this.html = false,
  });
  final String pattern, replacement;
  final bool caseSensitive, html;
  Map<String, Object?> toJson() => {
    'regexp': pattern,
    'replacement': replacement,
    'case_sensitive': caseSensitive,
    'html': html,
  };
}

final class CookingInlineOnebox {
  const CookingInlineOnebox({required this.title, this.cssClass = ''});
  final String title, cssClass;
  Map<String, Object?> toJson() => {'title': title, 'css_class': cssClass};
}
