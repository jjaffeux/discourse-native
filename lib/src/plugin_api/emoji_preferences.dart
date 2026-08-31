import '../models/site_emoji.dart';
import 'emoji_usage.dart';

/// Omits persistence and hydration authority while preserving the shared,
/// forum-level skin-tone preference.
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
