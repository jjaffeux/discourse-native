import 'dart:convert';

import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/assign/assign_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';

SiteConfig pluginSettings(Map<String, dynamic> json) =>
    installedPlugins.models.siteConfig(json, 'https://example.com');

SiteConfig restorePluginSettings(SiteConfig config) => SiteConfig.fromJson(
  jsonDecode(jsonEncode(config.toJson(extensions: pluginRegistry)))
      as Map<String, dynamic>,
  extensions: pluginRegistry,
);

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
  bool? chatUploadsEnabled,
  int? maxImageWidth,
  int? maxImageHeight,
  int? minSearchTermLength,
  bool? logSearchQueries,
  bool? groupDirectoryEnabled,
  bool? mentionsEnabled,
  bool? smtpEnabled,
  bool? chatSearchEnabled,
  int? chatChannelRetentionDays,
  int? chatDmRetentionDays,
  bool? taggingEnabled,
  int? maxTagSearchResults,
  bool? usePgHeadlinesForExcerpt,
  int? showTimeGapDays,
  bool? fixedCategoryPositions,
  bool? allowUncategorizedTopics,
  Object? defaultNavigationMenuCategories,
  String? topPageDefaultPeriod,
  bool? badgesEnabled,
  bool? allowUsernameInShareLinks,
  Object? readTimeWordCount,
  bool? enableAssignStatus,
  String? assignStatuses,
  bool? localDatesEnabled,
  String? localDateFormats,
  String? localDateTimezones,
  bool? gifsEnabled,
  String? gifFileDetail,
  bool? gifResultLimitEnabled,
  Object? gifMaxResults,
  bool? enableAutoGridImages,
  bool? enableMarkdownLinkify,
  String? markdownLinkifyTlds,
  bool? fastEditEnabled,
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
  'chat_allow_uploads': ?chatUploadsEnabled,
  'max_image_width': ?maxImageWidth,
  'max_image_height': ?maxImageHeight,
  'min_search_term_length': ?minSearchTermLength,
  'log_search_queries': ?logSearchQueries,
  'enable_group_directory': ?groupDirectoryEnabled,
  'enable_mentions': ?mentionsEnabled,
  'enable_smtp': ?smtpEnabled,
  'chat_search_enabled': ?chatSearchEnabled,
  'chat_channel_retention_days': ?chatChannelRetentionDays,
  'chat_dm_retention_days': ?chatDmRetentionDays,
  'tagging_enabled': ?taggingEnabled,
  'max_tag_search_results': ?maxTagSearchResults,
  'use_pg_headlines_for_excerpt': ?usePgHeadlinesForExcerpt,
  'show_time_gap_days': ?showTimeGapDays,
  'fixed_category_positions': ?fixedCategoryPositions,
  'allow_uncategorized_topics': ?allowUncategorizedTopics,
  'default_navigation_menu_categories': ?defaultNavigationMenuCategories,
  'top_page_default_timeframe': ?topPageDefaultPeriod,
  'enable_badges': ?badgesEnabled,
  'allow_username_in_share_links': ?allowUsernameInShareLinks,
  'read_time_word_count': ?readTimeWordCount,
  'enable_assign_status': ?enableAssignStatus,
  'assign_statuses': ?assignStatuses,
  'discourse_local_dates_enabled': ?localDatesEnabled,
  'discourse_local_dates_default_formats': ?localDateFormats,
  'discourse_local_dates_default_timezones': ?localDateTimezones,
  'enable_gifs': ?gifsEnabled,
  'klipy_file_detail': ?gifFileDetail,
  'klipy_limit_infinite_search_results': ?gifResultLimitEnabled,
  'klipy_max_results_limit': ?gifMaxResults,
  'enable_auto_grid_images': ?enableAutoGridImages,
  'enable_markdown_linkify': ?enableMarkdownLinkify,
  'markdown_linkify_tlds': ?markdownLinkifyTlds,
  'enable_fast_edit': ?fastEditEnabled,
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

    test('reads and preserves the fast edit gate', () {
      final disabled = SiteConfig.fromSettings(
        settings(fastEditEnabled: false),
      );

      expect(disabled.fastEditEnabled, isFalse);
      expect(SiteConfig.fromJson(disabled.toJson()).fastEditEnabled, isFalse);
      expect(disabled.withPlugins(disabled.plugins).fastEditEnabled, isFalse);
      expect(SiteConfig.fromSettings(const {}).fastEditEnabled, isTrue);
      expect(SiteConfig.fromJson(const {}).fastEditEnabled, isTrue);
    });

    test('reads and preserves the automatic image gallery gate', () {
      final disabled = SiteConfig.fromSettings(
        settings(enableAutoGridImages: false),
      );
      final restored = SiteConfig.fromJson(disabled.toJson());

      expect(disabled.enableAutoGridImages, isFalse);
      expect(restored.enableAutoGridImages, isFalse);
      expect(
        disabled.withPlugins(disabled.plugins).enableAutoGridImages,
        isFalse,
      );
    });

    test('reads, validates, and preserves the Top page default period', () {
      final monthly = SiteConfig.fromSettings(
        settings(topPageDefaultPeriod: 'monthly'),
      );

      expect(monthly.topPageDefaultPeriod, 'monthly');
      expect(
        SiteConfig.fromJson(monthly.toJson()).topPageDefaultPeriod,
        'monthly',
      );
      expect(
        SiteConfig.fromSettings(
          settings(topPageDefaultPeriod: 'invalid'),
        ).topPageDefaultPeriod,
        SiteConfig.defaultTopPagePeriod,
      );
    });

    test('reads and preserves the core linkify settings', () {
      final config = SiteConfig.fromSettings(
        settings(enableMarkdownLinkify: false, markdownLinkifyTlds: 'fr|dev'),
      );
      final restored = SiteConfig.fromJson(config.toJson());

      expect(config.enableMarkdownLinkify, isFalse);
      expect(config.markdownLinkifyTlds, ['fr', 'dev']);
      expect(restored, config);
      expect(config.withPlugins(config.plugins), config);
    });

    test('reads and persists the core group surface settings', () {
      final config = SiteConfig.fromSettings(
        settings(
          groupDirectoryEnabled: false,
          mentionsEnabled: false,
          smtpEnabled: true,
        ),
      );

      expect(config.groupDirectoryEnabled, isFalse);
      expect(config.mentionsEnabled, isFalse);
      expect(config.smtpEnabled, isTrue);
      final restored = SiteConfig.fromJson(config.toJson());
      expect(restored.groupDirectoryEnabled, isFalse);
      expect(restored.mentionsEnabled, isFalse);
      expect(restored.smtpEnabled, isTrue);
    });

    test('falls back to core defaults for everything absent', () {
      const unknown = SiteConfig.unknown();
      expect(SiteConfig.fromSettings(const {}), unknown);
      expect(unknown.emojiSet, 'twitter');
      expect(unknown.emojiEnabled, isTrue);
      expect(unknown.enableAutoGridImages, isTrue);
      expect(unknown.enableMarkdownLinkify, isTrue);
      expect(unknown.fastEditEnabled, isTrue);
      expect(
        unknown.markdownLinkifyTlds,
        SiteConfig.defaultMarkdownLinkifyTlds,
      );
      expect(unknown.mainReaction, isNull);
      expect(unknown.offeredReactions, isEmpty);
      expect(unknown.minSearchTermLength, 3);
      expect(unknown.logSearchQueries, isTrue);
      expect(unknown.chatSearchEnabled, isFalse);
      expect(unknown.taggingEnabled, isTrue);
      expect(unknown.maxTagSearchResults, 5);
      expect(unknown.usePgHeadlinesForExcerpt, isFalse);
      expect(unknown.showTimeGapDays, SiteConfig.defaultShowTimeGapDays);
      expect(unknown.gifsEnabled, isFalse);
      expect(unknown.gifFileDetail, GifsSettings.defaultFileDetail);
      expect(unknown.gifResultLimitEnabled, isFalse);
      expect(unknown.gifMaxResults, GifsSettings.defaultMaxResults);
      expect(unknown.readTimeWordCount, SiteConfig.defaultReadTimeWordCount);
      expect(unknown.minPersonalMessagePostLength, 10);
      expect(unknown.allowAllUsersToFlagIllegalContent, isFalse);
      expect(unknown.anonymousFlagReportEmail, isNull);
    });

    test('a core-only decoder ignores optional plugin schemas', () {
      final core = SiteConfig.fromSettings({
        ...settings(
          reactionsEnabled: true,
          reactionForLike: 'heart',
          chatSearchEnabled: true,
          localDatesEnabled: true,
          gifsEnabled: true,
          enableAssignStatus: true,
        ),
        'poll_maximum_options': 37,
        'voice_enabled': true,
      });

      expect(core.plugins.isEmpty, isTrue);
      expect(core.toJson(), isNot(contains('plugins')));
    });

    test('reads the topic-map reading speed and rejects invalid values', () {
      expect(
        SiteConfig.fromSettings(
          settings(readTimeWordCount: 350),
        ).readTimeWordCount,
        350,
      );
      expect(
        SiteConfig.fromSettings(
          settings(readTimeWordCount: 0),
        ).readTimeWordCount,
        SiteConfig.defaultReadTimeWordCount,
      );
    });

    test('reads flag message and anonymous illegal-report settings', () {
      final config = SiteConfig.fromSettings(const {
        'min_personal_message_post_length': 17,
        'allow_all_users_to_flag_illegal_content': true,
        'contact_email': ' contact@example.com ',
        'email_address_to_report_illegal_content': ' legal@example.com ',
      });

      expect(config.minPersonalMessagePostLength, 17);
      expect(config.allowAllUsersToFlagIllegalContent, isTrue);
      expect(config.contactEmail, 'contact@example.com');
      expect(config.illegalContentReportEmail, 'legal@example.com');
      expect(config.anonymousFlagReportEmail, 'legal@example.com');
    });

    test('falls back from the illegal-report address to contact email', () {
      final config = SiteConfig.fromSettings(const {
        'allow_all_users_to_flag_illegal_content': true,
        'contact_email': 'team@example.com',
        'email_address_to_report_illegal_content': ' ',
      });

      expect(config.anonymousFlagReportEmail, 'team@example.com');
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

    test('reads the header-search presentation settings', () {
      final config = SiteConfig.fromSettings(
        settings(
          logSearchQueries: false,
          taggingEnabled: false,
          usePgHeadlinesForExcerpt: true,
        ),
      );

      expect(config.logSearchQueries, isFalse);
      expect(config.taggingEnabled, isFalse);
      expect(config.usePgHeadlinesForExcerpt, isTrue);
    });

    test('enables chat search only from an explicit true setting', () {
      expect(pluginSettings(const {}).chatSearchEnabled, isFalse);
      expect(
        pluginSettings(settings(chatSearchEnabled: true)).chatSearchEnabled,
        isTrue,
      );
      expect(
        pluginSettings(settings(chatSearchEnabled: false)).chatSearchEnabled,
        isFalse,
      );
      final enabled = pluginSettings(settings(chatSearchEnabled: true));
      expect(restorePluginSettings(enabled), enabled);
    });

    test('retains the chat history periods shown in channel settings', () {
      final config = pluginSettings(
        settings(chatChannelRetentionDays: 180, chatDmRetentionDays: 30),
      );

      expect(config.chatChannelRetentionDays, 180);
      expect(config.chatDmRetentionDays, 30);
      expect(restorePluginSettings(config), config);
      expect(pluginSettings(const {}).chatChannelRetentionDays, 0);
      expect(
        pluginSettings(
          settings(chatChannelRetentionDays: -1),
        ).chatChannelRetentionDays,
        0,
      );
    });

    test('reads and bounds the post time-gap threshold', () {
      expect(
        SiteConfig.fromSettings(settings(showTimeGapDays: 30)).showTimeGapDays,
        30,
      );
      expect(
        SiteConfig.fromSettings(settings(showTimeGapDays: 0)).showTimeGapDays,
        0,
      );
      for (final invalid in [-1, SiteConfig.maximumShowTimeGapDays + 1]) {
        expect(
          SiteConfig.fromSettings(
            settings(showTimeGapDays: invalid),
          ).showTimeGapDays,
          SiteConfig.defaultShowTimeGapDays,
        );
      }
    });

    test('reads the tag search page the site will accept', () {
      // Core validates the composer's `limit` against this setting and answers
      // 400 above it, so a wrong value here is a broken tag picker rather than
      // a longer list.
      expect(
        SiteConfig.fromSettings(
          settings(maxTagSearchResults: 30),
        ).maxTagSearchResults,
        30,
      );
      expect(
        SiteConfig.fromSettings(
          settings(maxTagSearchResults: 0),
        ).maxTagSearchResults,
        SiteConfig.defaultMaxTagSearchResults,
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

    test('treats an empty external emoji URL as no external emoji URL', () {
      // Discourse writes "" rather than null for an unset string setting.
      expect(SiteConfig.fromSettings(settings()).externalEmojiUrl, isNull);
    });

    test('drops a trailing slash from the external emoji URL', () {
      expect(
        SiteConfig.fromSettings(
          settings(externalEmojiUrl: 'https://cdn.example/emoji/'),
        ).externalEmojiUrl,
        'https://cdn.example/emoji',
      );
    });

    test('splits the offered reactions on the pipe the setting uses', () {
      final config = pluginSettings(
        settings(
          reactionsEnabled: true,
          reactionForLike: 'heart',
          enabledReactions: '+1|laughing|clap',
        ),
      );

      expect(config.offeredReactions, ['heart', '+1', 'laughing', 'clap']);
    });

    test('does not offer the main reaction twice', () {
      final config = pluginSettings(
        settings(
          reactionsEnabled: true,
          reactionForLike: 'clap',
          enabledReactions: '+1|clap',
        ),
      );

      expect(config.offeredReactions, ['+1', 'clap']);
    });

    test('reads nothing about reactions from a site that has them off', () {
      final config = pluginSettings(
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
      final config = pluginSettings(
        settings(reactionsEnabled: true, enabledReactions: '+1|clap'),
      );

      expect(config.mainReaction, isNull);
    });

    test('reads optional Assign statuses without claiming capability', () {
      final enabled = pluginSettings(
        settings(
          enableAssignStatus: true,
          assignStatuses: 'New|In Progress|Done',
        ),
      );
      final disabled = pluginSettings(
        settings(enableAssignStatus: false, assignStatuses: 'New|Done'),
      );

      expect(enabled.assignStatusesEnabled, isTrue);
      expect(enabled.assignStatuses, ['New', 'In Progress', 'Done']);
      expect(disabled.assignStatusesEnabled, isFalse);
      expect(disabled.assignStatuses, isEmpty);
    });

    test('reads local-date authoring and preview defaults', () {
      final config = pluginSettings(
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
        final config = pluginSettings(const {});

        expect(config.localDatesEnabled, isFalse);
        expect(config.localDateFormats, LocalDatesSettings.defaultFormats);
        expect(config.localDateTimezones, LocalDatesSettings.defaultTimezones);
      },
    );

    test('reads GIF proxy presentation and result-limit settings', () {
      final config = pluginSettings(
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
      final config = pluginSettings(
        settings(gifFileDetail: 'future-format', gifMaxResults: 23),
      );

      expect(config.gifFileDetail, GifsSettings.defaultFileDetail);
      expect(config.gifMaxResults, GifsSettings.defaultMaxResults);
      expect(pluginSettings(settings(gifMaxResults: '48')).gifMaxResults, 48);
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
      expect(config.chatUploadsEnabled, isTrue);
      expect(config.maxImageWidth, 690);
      expect(config.maxImageHeight, 500);
    });

    test('reads and persists the chat upload gate', () {
      final disabled = pluginSettings(settings(chatUploadsEnabled: false));

      expect(disabled.chatUploadsEnabled, isFalse);
      expect(restorePluginSettings(disabled), disabled);
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
    final full = pluginSettings(
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
        logSearchQueries: false,
        taggingEnabled: false,
        maxTagSearchResults: 30,
        usePgHeadlinesForExcerpt: true,
        showTimeGapDays: 30,
        fixedCategoryPositions: true,
        allowUncategorizedTopics: true,
        defaultNavigationMenuCategories: '7|3',
        badgesEnabled: false,
        allowUsernameInShareLinks: false,
        readTimeWordCount: 350,
        localDatesEnabled: true,
        localDateFormats: 'LLL|YYYY',
        localDateTimezones: 'Etc/UTC|Asia/Tokyo',
        gifsEnabled: true,
        gifFileDetail: 'gif',
        gifResultLimitEnabled: true,
        gifMaxResults: 72,
      ),
    );

    test('preserves the complete core and plugin setting snapshot', () {
      final decoded = restorePluginSettings(full);

      expect(decoded, full);
    });

    test('reads a stored copy that predates a field', () {
      expect(SiteConfig.fromJson(const {}), const SiteConfig.unknown());
    });

    test('persists flag settings backward-compatibly', () {
      const config = SiteConfig(
        minPersonalMessagePostLength: 20,
        allowAllUsersToFlagIllegalContent: true,
        contactEmail: 'contact@example.com',
        illegalContentReportEmail: 'legal@example.com',
      );

      expect(SiteConfig.fromJson(config.toJson()), config);
      expect(
        SiteConfig.fromJson(const {}).minPersonalMessagePostLength,
        SiteConfig.defaultMinPersonalMessagePostLength,
      );
    });

    test('compares by value, so an unchanged answer is not rewritten', () {
      expect(
        SiteConfig.fromJson(
              full.toJson(extensions: pluginRegistry),
              extensions: pluginRegistry,
            ) ==
            full,
        isTrue,
        reason: 'a decoded copy must equal what it was encoded from',
      );
      expect(full == const SiteConfig.unknown(), isFalse);
    });
  });
}
