import '../models/site_emoji.dart';
import 'emoji_usage.dart';

/// The preference operations an emoji picker is allowed to use.
///
/// The application store also owns persistence, hydration and diagnostics,
/// none of which plugin code needs. Keeping this interface at the picker
/// boundary lets a scoped host validate each context-bearing operation while
/// preserving the one shared, forum-level skin-tone preference.
abstract interface class EmojiPreferenceStore {
  Future<EmojiSkinTone> readSkinTone({required String siteUrl});

  Future<List<String>> favoriteEmojiCodes({
    required String siteUrl,
    required EmojiUsageContext context,
    required SiteEmojiCatalog catalog,
  });

  Future<void> writeSkinTone({
    required String siteUrl,
    required EmojiSkinTone tone,
  });

  Future<void> trackEmoji({
    required String siteUrl,
    required EmojiUsageContext context,
    required String emoji,
  });

  Future<void> clearHistory({
    required String siteUrl,
    required EmojiUsageContext context,
  });
}
