import 'dart:convert';

import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape `/site/settings.json` answers with, trimmed to what is read.
Map<String, dynamic> settings({
  String? emojiSet = 'twitter',
  String externalEmojiUrl = '',
  bool? reactionsEnabled,
  String? reactionForLike,
  String? enabledReactions,
  bool? allowAnyEmoji,
  bool? desaturated,
}) => {
  'emoji_set': ?emojiSet,
  'external_emoji_url': externalEmojiUrl,
  'discourse_reactions_enabled': ?reactionsEnabled,
  'discourse_reactions_reaction_for_like': ?reactionForLike,
  'discourse_reactions_enabled_reactions': ?enabledReactions,
  'discourse_reactions_allow_any_emoji': ?allowAnyEmoji,
  'discourse_reactions_desaturated_reaction_panel': ?desaturated,
};

void main() {
  group('fromSettings', () {
    test('reads the emoji set the site draws with', () {
      expect(
        SiteConfig.fromSettings(settings(emojiSet: 'google')).emojiSet,
        'google',
      );
    });

    test('falls back to core defaults for everything absent', () {
      // A site too old to have a setting, or one that answered with a payload
      // this build does not recognise, is drawn as plain core rather than as
      // broken.
      const unknown = SiteConfig.unknown();
      expect(SiteConfig.fromSettings(const {}), unknown);
      expect(unknown.emojiSet, 'twitter');
      expect(unknown.mainReaction, isNull);
      expect(unknown.offeredReactions, isEmpty);
    });

    test('treats an empty external emoji url as no external emoji url', () {
      // Discourse writes "" rather than null for an unset string setting.
      expect(SiteConfig.fromSettings(settings()).externalEmojiUrl, isNull);
    });

    test('drops a trailing slash from the external emoji url', () {
      expect(
        SiteConfig.fromSettings(
          settings(externalEmojiUrl: 'https://cdn.example/emoji/'),
        ).externalEmojiUrl,
        'https://cdn.example/emoji',
      );
    });

    test('splits the offered reactions on the pipe the setting uses', () {
      final config = SiteConfig.fromSettings(
        settings(
          reactionsEnabled: true,
          reactionForLike: 'heart',
          enabledReactions: '+1|laughing|clap',
        ),
      );

      expect(config.offeredReactions, ['heart', '+1', 'laughing', 'clap']);
    });

    test('does not offer the main reaction twice', () {
      final config = SiteConfig.fromSettings(
        settings(
          reactionsEnabled: true,
          reactionForLike: 'clap',
          enabledReactions: '+1|clap',
        ),
      );

      expect(config.offeredReactions, ['+1', 'clap']);
    });

    test('reads nothing about reactions from a site that has them off', () {
      // The settings are registered whether or not the plugin is enabled, so
      // they are in the payload either way. Reading them regardless would offer
      // a picker on a site that has switched reactions off.
      final config = SiteConfig.fromSettings(
        settings(
          reactionsEnabled: false,
          reactionForLike: 'heart',
          enabledReactions: '+1|clap',
          allowAnyEmoji: true,
          desaturated: true,
        ),
      );

      expect(config.mainReaction, isNull);
      expect(config.offeredReactions, isEmpty);
      expect(config.allowAnyEmoji, isFalse);
      expect(config.desaturatedReactionPanel, isFalse);
    });

    test('says nothing about the main reaction rather than guessing it', () {
      // `heart` is not in the default enabled list, and the setting is enum
      // constrained to what a site allows — so a guess earns a 422 whose body
      // says only "Sorry, an error has occurred."
      final config = SiteConfig.fromSettings(
        settings(reactionsEnabled: true, enabledReactions: '+1|clap'),
      );

      expect(config.mainReaction, isNull);
    });
  });

  group('emojiUrl', () {
    const site = 'https://meta.discourse.org';

    test('points at the set the site draws with', () {
      expect(
        SiteConfig.fromSettings(
          settings(emojiSet: 'apple'),
        ).emojiUrl('heart', siteUrl: site),
        'https://meta.discourse.org/images/emoji/apple/heart.png',
      );
    });

    test('uses the external host where the site has one', () {
      expect(
        SiteConfig.fromSettings(
          settings(externalEmojiUrl: 'https://cdn.example/emoji'),
        ).emojiUrl('heart', siteUrl: site),
        'https://cdn.example/emoji/twitter/heart.png',
      );
    });

    test('turns a skin tone into the path segment Discourse uses', () {
      // `Emoji.url_for` writes `:t3` as `/3`.
      const config = SiteConfig.unknown();
      expect(
        config.emojiUrl('wave:t3', siteUrl: site),
        '$site/images/emoji/twitter/wave/3.png',
      );
      expect(
        config.emojiUrl(':wave:t3:', siteUrl: site),
        '$site/images/emoji/twitter/wave/3.png',
      );
    });

    test('leaves a name that is not toned alone', () {
      expect(
        const SiteConfig.unknown().emojiUrl('+1', siteUrl: site),
        '$site/images/emoji/twitter/+1.png',
      );
    });
  });

  group('storage', () {
    final full = SiteConfig.fromSettings(
      settings(
        emojiSet: 'google',
        externalEmojiUrl: 'https://cdn.example/emoji',
        reactionsEnabled: true,
        reactionForLike: 'heart',
        enabledReactions: '+1|clap',
        allowAnyEmoji: true,
        desaturated: true,
      ),
    );

    test('survives a round trip through preferences', () {
      final decoded = SiteConfig.fromJson(
        jsonDecode(jsonEncode(full.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, full);
    });

    test('reads a stored copy that predates a field', () {
      // Nothing here may be required: InstanceStore answers a decode failure by
      // forgetting every site the user had.
      expect(SiteConfig.fromJson(const {}), const SiteConfig.unknown());
    });

    test('compares by value, so an unchanged answer is not rewritten', () {
      // Without this the persist-if-changed guard is identity comparison, and
      // preferences get rewritten on every launch.
      expect(
        SiteConfig.fromJson(full.toJson()) == full,
        isTrue,
        reason: 'a decoded copy must equal what it was encoded from',
      );
      expect(full == const SiteConfig.unknown(), isFalse);
    });
  });
}
