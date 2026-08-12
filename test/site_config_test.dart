import 'dart:convert';

import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape `/site/settings.json` answers with, trimmed to what is read.
Map<String, dynamic> settings({
  bool? emojiEnabled,
  String? emojiSet = 'twitter',
  String externalEmojiUrl = '',
  bool? reactionsEnabled,
  String? reactionForLike,
  String? enabledReactions,
  bool? allowAnyEmoji,
  bool? desaturated,
  String? authorizedExtensions,
  String? authorizedExtensionsForStaff,
  int? simultaneousUploads,
  int? maxImageWidth,
  int? maxImageHeight,
  int? minSearchTermLength,
  bool? fixedCategoryPositions,
  bool? allowUncategorizedTopics,
  Object? defaultNavigationMenuCategories,
  bool? badgesEnabled,
  bool? allowUsernameInShareLinks,
  bool? enableAssignStatus,
  String? assignStatuses,
  bool? localDatesEnabled,
  String? localDateFormats,
  String? localDateTimezones,
  bool? gifsEnabled,
  String? gifFileDetail,
  bool? gifResultLimitEnabled,
  Object? gifMaxResults,
}) => {
  'enable_emoji': ?emojiEnabled,
  'emoji_set': ?emojiSet,
  'external_emoji_url': externalEmojiUrl,
  'discourse_reactions_enabled': ?reactionsEnabled,
  'discourse_reactions_reaction_for_like': ?reactionForLike,
  'discourse_reactions_enabled_reactions': ?enabledReactions,
  'discourse_reactions_allow_any_emoji': ?allowAnyEmoji,
  'discourse_reactions_desaturated_reaction_panel': ?desaturated,
  'authorized_extensions': ?authorizedExtensions,
  'authorized_extensions_for_staff': ?authorizedExtensionsForStaff,
  'simultaneous_uploads': ?simultaneousUploads,
  'max_image_width': ?maxImageWidth,
  'max_image_height': ?maxImageHeight,
  'min_search_term_length': ?minSearchTermLength,
  'fixed_category_positions': ?fixedCategoryPositions,
  'allow_uncategorized_topics': ?allowUncategorizedTopics,
  'default_navigation_menu_categories': ?defaultNavigationMenuCategories,
  'enable_badges': ?badgesEnabled,
  'allow_username_in_share_links': ?allowUsernameInShareLinks,
  'enable_assign_status': ?enableAssignStatus,
  'assign_statuses': ?assignStatuses,
  'discourse_local_dates_enabled': ?localDatesEnabled,
  'discourse_local_dates_default_formats': ?localDateFormats,
  'discourse_local_dates_default_timezones': ?localDateTimezones,
  'enable_gifs': ?gifsEnabled,
  'klipy_file_detail': ?gifFileDetail,
  'klipy_limit_infinite_search_results': ?gifResultLimitEnabled,
  'klipy_max_results_limit': ?gifMaxResults,
};

void main() {
  group('fromSettings', () {
    test('reads the emoji set the site draws with', () {
      expect(
        SiteConfig.fromSettings(settings(emojiSet: 'google')).emojiSet,
        'google',
      );
    });

    test('reads the emoji authoring gate and defaults it on', () {
      expect(SiteConfig.fromSettings(const {}).emojiEnabled, isTrue);
      expect(
        SiteConfig.fromSettings(settings(emojiEnabled: false)).emojiEnabled,
        isFalse,
      );
    });

    test('falls back to core defaults for everything absent', () {
      // A site too old to have a setting, or one that answered with a payload
      // this build does not recognise, is drawn as plain core rather than as
      // broken.
      const unknown = SiteConfig.unknown();
      expect(SiteConfig.fromSettings(const {}), unknown);
      expect(unknown.emojiSet, 'twitter');
      expect(unknown.emojiEnabled, isTrue);
      expect(unknown.mainReaction, isNull);
      expect(unknown.offeredReactions, isEmpty);
      expect(unknown.minSearchTermLength, 3);
      expect(unknown.gifsEnabled, isFalse);
      expect(unknown.gifFileDetail, SiteConfig.defaultGifFileDetail);
      expect(unknown.gifResultLimitEnabled, isFalse);
      expect(unknown.gifMaxResults, SiteConfig.defaultGifMaxResults);
    });

    test('reads and bounds the minimum search length', () {
      expect(
        SiteConfig.fromSettings(
          settings(minSearchTermLength: 1),
        ).minSearchTermLength,
        1,
      );
      expect(
        SiteConfig.fromSettings(
          settings(minSearchTermLength: -4),
        ).minSearchTermLength,
        1,
      );
    });

    test('reads category navigation ordering and anonymous defaults', () {
      final config = SiteConfig.fromSettings(
        settings(
          fixedCategoryPositions: true,
          allowUncategorizedTopics: true,
          defaultNavigationMenuCategories: '4|2|invalid|4|0',
        ),
      );

      expect(config.fixedCategoryPositions, isTrue);
      expect(config.allowUncategorizedTopics, isTrue);
      expect(config.defaultNavigationMenuCategoryIds, [4, 2]);
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

    test('reads optional Assign statuses without claiming capability', () {
      final enabled = SiteConfig.fromSettings(
        settings(
          enableAssignStatus: true,
          assignStatuses: 'New|In Progress|Done',
        ),
      );
      final disabled = SiteConfig.fromSettings(
        settings(enableAssignStatus: false, assignStatuses: 'New|Done'),
      );

      expect(enabled.assignStatusesEnabled, isTrue);
      expect(enabled.assignStatuses, ['New', 'In Progress', 'Done']);
      expect(disabled.assignStatusesEnabled, isFalse);
      expect(disabled.assignStatuses, isEmpty);
    });

    test('reads local-date authoring and preview defaults', () {
      final config = SiteConfig.fromSettings(
        settings(
          localDatesEnabled: true,
          localDateFormats: 'LLL|YYYY-MM-DD [at] HH:mm',
          localDateTimezones: 'Etc/UTC|Asia/Tokyo',
        ),
      );

      expect(config.localDatesEnabled, isTrue);
      expect(config.localDateFormats, ['LLL', 'YYYY-MM-DD [at] HH:mm']);
      expect(config.localDateTimezones, ['Etc/UTC', 'Asia/Tokyo']);
    });

    test(
      'missing local-date enablement disables authoring but keeps defaults',
      () {
        final config = SiteConfig.fromSettings(const {});

        expect(config.localDatesEnabled, isFalse);
        expect(config.localDateFormats, SiteConfig.defaultLocalDateFormats);
        expect(config.localDateTimezones, SiteConfig.defaultLocalDateTimezones);
      },
    );

    test('reads GIF proxy presentation and result-limit settings', () {
      final config = SiteConfig.fromSettings(
        settings(
          gifsEnabled: true,
          gifFileDetail: 'gif',
          gifResultLimitEnabled: true,
          gifMaxResults: 96,
        ),
      );

      expect(config.gifsEnabled, isTrue);
      expect(config.gifFileDetail, 'gif');
      expect(config.gifResultLimitEnabled, isTrue);
      expect(config.gifMaxResults, 96);
    });

    test('bounds unknown GIF format and result-limit values', () {
      final config = SiteConfig.fromSettings(
        settings(gifFileDetail: 'future-format', gifMaxResults: 23),
      );

      expect(config.gifFileDetail, SiteConfig.defaultGifFileDetail);
      expect(config.gifMaxResults, SiteConfig.defaultGifMaxResults);
      expect(
        SiteConfig.fromSettings(settings(gifMaxResults: '48')).gifMaxResults,
        48,
      );
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

  group('composer uploads', () {
    test('reads site limits and separates staff-only extensions', () {
      final config = SiteConfig.fromSettings(
        settings(
          authorizedExtensions: 'jpg|jpeg|png',
          authorizedExtensionsForStaff: 'ico|psd',
          simultaneousUploads: 4,
          maxImageWidth: 900,
          maxImageHeight: 700,
        ),
      );

      expect(config.canUploadImage('PHOTO.JPG', staff: false), isTrue);
      expect(config.canUploadImage('favicon.ico', staff: false), isFalse);
      expect(config.canUploadImage('favicon.ico', staff: true), isTrue);
      expect(config.canUploadImage('notes.txt', staff: true), isFalse);
      expect(config.simultaneousUploads, 4);
      expect(config.maxImageWidth, 900);
      expect(config.maxImageHeight, 700);
    });

    test('keeps eager upload batches within the local resource ceiling', () {
      for (final value in [1, 17, 30]) {
        expect(
          SiteConfig.fromSettings(
            settings(simultaneousUploads: value),
          ).simultaneousUploads,
          value,
        );
      }

      for (final value in [0, 31, 1000000000]) {
        final fresh = SiteConfig.fromSettings(
          settings(simultaneousUploads: value),
        );
        final restored = SiteConfig.fromJson({'simultaneousUploads': value});
        expect(
          fresh.simultaneousUploads,
          SiteConfig.maximumSimultaneousUploads,
        );
        expect(
          restored.simultaneousUploads,
          SiteConfig.maximumSimultaneousUploads,
        );
        expect(SiteConfig.fromJson(fresh.toJson()), fresh);
      }

      for (final value in [-1, -1000000000]) {
        expect(
          SiteConfig.fromSettings(
            settings(simultaneousUploads: value),
          ).simultaneousUploads,
          SiteConfig.defaultSimultaneousUploads,
        );
        expect(
          SiteConfig.fromJson({
            'simultaneousUploads': value,
          }).simultaneousUploads,
          SiteConfig.defaultSimultaneousUploads,
        );
      }
    });

    test('wildcard authorization still accepts images only', () {
      final config = SiteConfig.fromSettings(
        settings(authorizedExtensions: '*'),
      );

      expect(config.canUploadImage('photo.webp', staff: false), isTrue);
      expect(config.canUploadImage('archive.zip', staff: false), isFalse);
      expect(config.canUploadImage('no-extension', staff: false), isFalse);
    });

    test('uses core-compatible defaults when settings are absent', () {
      const config = SiteConfig.unknown();

      expect(config.canUploadImage('photo.png', staff: false), isTrue);
      expect(config.canUploadImage('photo.bmp', staff: false), isFalse);
      expect(config.simultaneousUploads, 15);
      expect(config.maxImageWidth, 690);
      expect(config.maxImageHeight, 500);
    });
  });

  group('shareUrl', () {
    const url = 'https://meta.discourse.org/t/a-topic/7/2';

    test('matches core referral links for a signed-in reader', () {
      expect(
        const SiteConfig.unknown().shareUrl(url, username: 'JoffreyJ'),
        '$url?u=joffreyj',
      );
    });

    test('omits the referral when either site setting disables it', () {
      for (final config in [
        SiteConfig.fromSettings(settings(badgesEnabled: false)),
        SiteConfig.fromSettings(settings(allowUsernameInShareLinks: false)),
      ]) {
        expect(config.shareUrl(url, username: 'joffreyj'), url);
      }
      expect(const SiteConfig.unknown().shareUrl(url), url);
    });
  });

  group('storage', () {
    final full = SiteConfig.fromSettings(
      settings(
        emojiEnabled: false,
        emojiSet: 'google',
        externalEmojiUrl: 'https://cdn.example/emoji',
        reactionsEnabled: true,
        reactionForLike: 'heart',
        enabledReactions: '+1|clap',
        allowAnyEmoji: true,
        desaturated: true,
        minSearchTermLength: 5,
        fixedCategoryPositions: true,
        allowUncategorizedTopics: true,
        defaultNavigationMenuCategories: '7|3',
        badgesEnabled: false,
        allowUsernameInShareLinks: false,
        localDatesEnabled: true,
        localDateFormats: 'LLL|YYYY',
        localDateTimezones: 'Etc/UTC|Asia/Tokyo',
        gifsEnabled: true,
        gifFileDetail: 'gif',
        gifResultLimitEnabled: true,
        gifMaxResults: 72,
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

  group('Resenha client settings', () {
    test('parses enabled capabilities and native quality caps', () {
      final resenha = SiteConfig.fromSettings({
        'resenha_enabled': true,
        'resenha_video_enabled': true,
        'resenha_video_max_publishers': 12,
        'resenha_livekit_recording_enabled': true,
        'resenha_max_voice_quality': 'high',
        'resenha_max_camera_quality': 'standard',
        'resenha_max_screen_share_quality': 'maximum',
        'resenha_idle_threshold_minutes': 7,
        'resenha_afk_auto_mute_threshold_minutes': 17,
        'resenha_afk_disconnect_threshold_minutes': 37,
        'resenha_auto_status_enabled': false,
        'resenha_chat_enabled': false,
      }).resenha;

      expect(resenha.enabled, isTrue);
      expect(resenha.videoEnabled, isTrue);
      expect(resenha.videoMaxPublishers, 12);
      expect(resenha.recordingEnabled, isTrue);
      expect(resenha.maxVoiceQuality, 'high');
      expect(resenha.maxCameraQuality, 'standard');
      expect(resenha.maxScreenShareQuality, 'maximum');
      expect(resenha.idleThresholdMinutes, 7);
      expect(resenha.afkAutoMuteThresholdMinutes, 17);
      expect(resenha.afkDisconnectThresholdMinutes, 37);
      expect(resenha.autoStatusEnabled, isFalse);
      expect(resenha.chatEnabled, isFalse);
    });

    test('defaults unknown values defensively and survives storage', () {
      final config = SiteConfig.fromSettings({
        'resenha_enabled': true,
        'resenha_video_max_publishers': 1000,
        'resenha_max_voice_quality': 'future-ultra',
        'resenha_idle_threshold_minutes': -1,
      });
      final decoded = SiteConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );

      expect(config.resenha.videoMaxPublishers, 8);
      expect(config.resenha.maxVoiceQuality, 'maximum');
      expect(config.resenha.idleThresholdMinutes, 5);
      expect(decoded, config);
    });
  });
}
