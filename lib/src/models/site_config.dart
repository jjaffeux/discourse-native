import 'package:flutter/foundation.dart';

import '../plugin_api/plugin_data.dart';
import 'json.dart';

@immutable
class SiteConfig {
  const SiteConfig({
    this.emojiEnabled = true,
    this.userStatusEnabled = false,
    this.emojiSet = defaultEmojiSet,
    this.externalEmojiUrl,
    this.authorizedExtensions = defaultAuthorizedExtensions,
    this.authorizedExtensionsForStaff = const [],
    this.simultaneousUploads = defaultSimultaneousUploads,
    this.maxImageWidth = 690,
    this.maxImageHeight = 500,
    this.enableAutoGridImages = true,
    this.enableMarkdownLinkify = true,
    this.markdownLinkifyTlds = defaultMarkdownLinkifyTlds,
    this.minSearchTermLength = defaultMinSearchTermLength,
    this.logSearchQueries = true,
    this.groupDirectoryEnabled = true,
    this.mentionsEnabled = true,
    this.smtpEnabled = false,
    this.taggingEnabled = true,
    this.maxTagSearchResults = defaultMaxTagSearchResults,
    this.usePgHeadlinesForExcerpt = false,
    this.showTimeGapDays = defaultShowTimeGapDays,
    this.fixedCategoryPositions = false,
    this.allowUncategorizedTopics = false,
    this.defaultNavigationMenuCategoryIds = const [],
    this.topPageDefaultPeriod = defaultTopPagePeriod,
    this.badgesEnabled = true,
    this.allowUsernameInShareLinks = true,
    this.readTimeWordCount = defaultReadTimeWordCount,
    this.minPersonalMessagePostLength = defaultMinPersonalMessagePostLength,
    this.allowAllUsersToFlagIllegalContent = false,
    this.contactEmail,
    this.illegalContentReportEmail,
    this.suggestWeekendsInDatePickers = true,
    this.plugins = PluginData.none,
  });

  const SiteConfig.unknown() : this();

  static const String defaultEmojiSet = 'twitter';
  static const int defaultSimultaneousUploads = 15;

  /// A local resource ceiling even when core's `0` asks for no batch limit.
  static const int maximumSimultaneousUploads = 30;
  static const List<String> defaultAuthorizedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'heic',
    'heif',
    'webp',
    'avif',
    'svg',
    'jxl',
  ];
  static const Set<String> imageExtensions = {
    'png',
    'webp',
    'jpg',
    'jpeg',
    'gif',
    'svg',
    'ico',
    'heic',
    'heif',
    'avif',
    'jxl',
  };
  static const int defaultMinSearchTermLength = 3;
  static const List<String> defaultMarkdownLinkifyTlds = [
    'com',
    'net',
    'org',
    'io',
    'onion',
    'co',
    'tv',
    'ru',
    'cn',
    'us',
    'uk',
    'me',
    'de',
    'fr',
    'fi',
    'gov',
  ];
  static const int defaultReadTimeWordCount = 500;
  static const int defaultShowTimeGapDays = 7;
  static const int maximumShowTimeGapDays = 36500;
  static const int defaultMinPersonalMessagePostLength = 10;
  static const String defaultTopPagePeriod = 'yearly';
  static const Set<String> topPagePeriods = {
    'all',
    'yearly',
    'quarterly',
    'monthly',
    'weekly',
    'daily',
  };

  static const int defaultMaxTagSearchResults = 5;

  factory SiteConfig.fromSettings(
    Map<String, dynamic> json, {
    String siteUrl = '',
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    return SiteConfig(
      emojiEnabled: json['enable_emoji'] != false,
      userStatusEnabled: json['enable_user_status'] == true,
      emojiSet: jsonText(json['emoji_set']) ?? defaultEmojiSet,
      externalEmojiUrl: _trimSlash(jsonText(json['external_emoji_url'])),
      authorizedExtensions: _extensionList(
        json['authorized_extensions'],
        defaultAuthorizedExtensions,
      ),
      authorizedExtensionsForStaff: _extensionList(
        json['authorized_extensions_for_staff'],
        const [],
      ),
      simultaneousUploads: _simultaneousUploads(json['simultaneous_uploads']),
      maxImageWidth: _positiveInt(json['max_image_width'], 690),
      maxImageHeight: _positiveInt(json['max_image_height'], 500),
      enableAutoGridImages: json['enable_auto_grid_images'] != false,
      enableMarkdownLinkify: json['enable_markdown_linkify'] != false,
      markdownLinkifyTlds: _stringList(
        json['markdown_linkify_tlds'],
        defaultMarkdownLinkifyTlds,
      ),
      minSearchTermLength:
          jsonIntOrNull(json['min_search_term_length'])?.clamp(1, 100) ??
          defaultMinSearchTermLength,
      logSearchQueries: json['log_search_queries'] != false,
      groupDirectoryEnabled: json['enable_group_directory'] != false,
      mentionsEnabled: json['enable_mentions'] != false,
      smtpEnabled: json['enable_smtp'] == true,
      taggingEnabled: json['tagging_enabled'] != false,
      maxTagSearchResults: _positiveInt(
        json['max_tag_search_results'],
        defaultMaxTagSearchResults,
      ),
      usePgHeadlinesForExcerpt: json['use_pg_headlines_for_excerpt'] == true,
      showTimeGapDays: _showTimeGapDays(json['show_time_gap_days']),
      fixedCategoryPositions: json['fixed_category_positions'] == true,
      allowUncategorizedTopics: json['allow_uncategorized_topics'] == true,
      defaultNavigationMenuCategoryIds: _categoryIds(
        json['default_navigation_menu_categories'],
      ),
      topPageDefaultPeriod: _topPagePeriod(json['top_page_default_timeframe']),
      badgesEnabled: json['enable_badges'] != false,
      allowUsernameInShareLinks: json['allow_username_in_share_links'] != false,
      readTimeWordCount: _positiveInt(
        json['read_time_word_count'],
        defaultReadTimeWordCount,
      ),
      minPersonalMessagePostLength: _positiveInt(
        json['min_personal_message_post_length'],
        defaultMinPersonalMessagePostLength,
      ),
      allowAllUsersToFlagIllegalContent:
          json['allow_all_users_to_flag_illegal_content'] == true,
      contactEmail: _nonemptyText(json['contact_email']),
      illegalContentReportEmail: _nonemptyText(
        json['email_address_to_report_illegal_content'],
      ),
      suggestWeekendsInDatePickers:
          json['suggest_weekends_in_date_pickers'] != false,
      plugins: extensions.readSiteSettings(json, siteUrl),
    );
  }

  /// Every field is optional so older snapshots retain core defaults.
  factory SiteConfig.fromJson(
    Map<String, dynamic> json, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) => SiteConfig(
    emojiEnabled: json['emojiEnabled'] != false,
    userStatusEnabled: json['userStatusEnabled'] == true,
    emojiSet: jsonText(json['emojiSet']) ?? defaultEmojiSet,
    externalEmojiUrl: jsonText(json['externalEmojiUrl']),
    authorizedExtensions: _extensionList(
      json['authorizedExtensions'],
      defaultAuthorizedExtensions,
    ),
    authorizedExtensionsForStaff: _extensionList(
      json['authorizedExtensionsForStaff'],
      const [],
    ),
    simultaneousUploads: _simultaneousUploads(json['simultaneousUploads']),
    maxImageWidth: _positiveInt(json['maxImageWidth'], 690),
    maxImageHeight: _positiveInt(json['maxImageHeight'], 500),
    enableAutoGridImages: json['enableAutoGridImages'] != false,
    enableMarkdownLinkify: json['enableMarkdownLinkify'] != false,
    markdownLinkifyTlds: _stringList(
      json['markdownLinkifyTlds'],
      defaultMarkdownLinkifyTlds,
    ),
    minSearchTermLength:
        jsonIntOrNull(json['minSearchTermLength'])?.clamp(1, 100) ??
        defaultMinSearchTermLength,
    logSearchQueries: json['logSearchQueries'] != false,
    groupDirectoryEnabled: json['groupDirectoryEnabled'] != false,
    mentionsEnabled: json['mentionsEnabled'] != false,
    smtpEnabled: json['smtpEnabled'] == true,
    taggingEnabled: json['taggingEnabled'] != false,
    maxTagSearchResults: _positiveInt(
      json['maxTagSearchResults'],
      defaultMaxTagSearchResults,
    ),
    usePgHeadlinesForExcerpt: json['usePgHeadlinesForExcerpt'] == true,
    showTimeGapDays: _showTimeGapDays(json['showTimeGapDays']),
    fixedCategoryPositions: json['fixedCategoryPositions'] == true,
    allowUncategorizedTopics: json['allowUncategorizedTopics'] == true,
    defaultNavigationMenuCategoryIds: _categoryIds(
      json['defaultNavigationMenuCategoryIds'],
    ),
    topPageDefaultPeriod: _topPagePeriod(json['topPageDefaultPeriod']),
    badgesEnabled: json['badgesEnabled'] != false,
    allowUsernameInShareLinks: json['allowUsernameInShareLinks'] != false,
    readTimeWordCount: _positiveInt(
      json['readTimeWordCount'],
      defaultReadTimeWordCount,
    ),
    minPersonalMessagePostLength: _positiveInt(
      json['minPersonalMessagePostLength'],
      defaultMinPersonalMessagePostLength,
    ),
    allowAllUsersToFlagIllegalContent:
        json['allowAllUsersToFlagIllegalContent'] == true,
    contactEmail: _nonemptyText(json['contactEmail']),
    illegalContentReportEmail: _nonemptyText(json['illegalContentReportEmail']),
    suggestWeekendsInDatePickers: json['suggestWeekendsInDatePickers'] != false,
    plugins: extensions.readStoredSiteSettings(json),
  );

  Map<String, dynamic> toJson({
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final pluginJson = extensions.writeStoredSiteSettings(plugins);
    return {
      'emojiEnabled': emojiEnabled,
      'userStatusEnabled': userStatusEnabled,
      'emojiSet': emojiSet,
      'externalEmojiUrl': externalEmojiUrl,
      'authorizedExtensions': authorizedExtensions,
      'authorizedExtensionsForStaff': authorizedExtensionsForStaff,
      'simultaneousUploads': simultaneousUploads,
      'maxImageWidth': maxImageWidth,
      'maxImageHeight': maxImageHeight,
      'enableAutoGridImages': enableAutoGridImages,
      'enableMarkdownLinkify': enableMarkdownLinkify,
      'markdownLinkifyTlds': markdownLinkifyTlds,
      'minSearchTermLength': minSearchTermLength,
      'logSearchQueries': logSearchQueries,
      'groupDirectoryEnabled': groupDirectoryEnabled,
      'mentionsEnabled': mentionsEnabled,
      'smtpEnabled': smtpEnabled,
      'taggingEnabled': taggingEnabled,
      'maxTagSearchResults': maxTagSearchResults,
      'usePgHeadlinesForExcerpt': usePgHeadlinesForExcerpt,
      'showTimeGapDays': showTimeGapDays,
      'fixedCategoryPositions': fixedCategoryPositions,
      'allowUncategorizedTopics': allowUncategorizedTopics,
      'defaultNavigationMenuCategoryIds': defaultNavigationMenuCategoryIds,
      'topPageDefaultPeriod': topPageDefaultPeriod,
      'badgesEnabled': badgesEnabled,
      'allowUsernameInShareLinks': allowUsernameInShareLinks,
      'readTimeWordCount': readTimeWordCount,
      'minPersonalMessagePostLength': minPersonalMessagePostLength,
      'allowAllUsersToFlagIllegalContent': allowAllUsersToFlagIllegalContent,
      'contactEmail': contactEmail,
      'illegalContentReportEmail': illegalContentReportEmail,
      'suggestWeekendsInDatePickers': suggestWeekendsInDatePickers,
      if (pluginJson.isNotEmpty) 'plugins': pluginJson,
    };
  }

  /// Existing shortcode content remains renderable when this is false; this
  /// setting only gates authoring surfaces such as autocomplete and the picker.
  final bool emojiEnabled;

  final bool userStatusEnabled;

  /// Part of the emoji URL, so it cannot be guessed locally.
  final String emojiSet;

  final String? externalEmojiUrl;

  final List<String> authorizedExtensions;
  final List<String> authorizedExtensionsForStaff;
  final int simultaneousUploads;
  final int maxImageWidth;
  final int maxImageHeight;

  final bool enableAutoGridImages;
  final bool enableMarkdownLinkify;
  final List<String> markdownLinkifyTlds;
  final int minSearchTermLength;
  final bool logSearchQueries;
  final bool groupDirectoryEnabled;
  final bool mentionsEnabled;
  final bool smtpEnabled;
  final bool taggingEnabled;

  /// `/tags/filter/search.json` returns 400 when `limit` exceeds this value.
  final int maxTagSearchResults;

  final bool usePgHeadlinesForExcerpt;

  final int showTimeGapDays;

  final bool fixedCategoryPositions;
  final bool allowUncategorizedTopics;
  final List<int> defaultNavigationMenuCategoryIds;
  final String topPageDefaultPeriod;

  final bool badgesEnabled;
  final bool allowUsernameInShareLinks;

  final int readTimeWordCount;

  final int minPersonalMessagePostLength;
  final bool allowAllUsersToFlagIllegalContent;
  final String? contactEmail;
  final String? illegalContentReportEmail;

  String? get anonymousFlagReportEmail =>
      illegalContentReportEmail ?? contactEmail;

  final bool suggestWeekendsInDatePickers;

  /// Values decoded by the installed feature manifest. Core intentionally
  /// cannot name or interpret anything in this bag.
  final PluginData plugins;

  String shareUrl(String url, {String? username}) {
    final account = username?.trim().toLowerCase();
    if (!badgesEnabled ||
        !allowUsernameInShareLinks ||
        account == null ||
        account.isEmpty) {
      return url;
    }
    return '$url?u=${Uri.encodeQueryComponent(account)}';
  }

  bool canUploadImage(String filename, {required bool staff}) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return false;
    final extension = filename.substring(dot + 1).toLowerCase();
    if (!imageExtensions.contains(extension)) return false;
    final permitted = [
      ...authorizedExtensions,
      if (staff) ...authorizedExtensionsForStaff,
    ];
    return permitted.contains('*') || permitted.contains(extension);
  }

  /// Mirrors `Emoji.url_for`; custom uploads must be resolved before fallback.
  String emojiUrl(String name, {required String siteUrl}) {
    final base = externalEmojiUrl ?? '$siteUrl/images/emoji';
    return '$base/$emojiSet/${_toned(name)}.png';
  }

  static String _toned(String name) {
    final match = RegExp(r'^:?(.+?)(?::t([1-6]))?:?$').firstMatch(name);
    if (match == null) return name;
    final tone = match.group(2);
    return tone == null ? match.group(1)! : '${match.group(1)}/$tone';
  }

  static String? _trimSlash(String? value) => value == null
      ? null
      : (value.endsWith('/') ? value.substring(0, value.length - 1) : value);

  SiteConfig withPlugins(PluginData value) => SiteConfig(
    emojiEnabled: emojiEnabled,
    userStatusEnabled: userStatusEnabled,
    emojiSet: emojiSet,
    externalEmojiUrl: externalEmojiUrl,
    authorizedExtensions: authorizedExtensions,
    authorizedExtensionsForStaff: authorizedExtensionsForStaff,
    simultaneousUploads: simultaneousUploads,
    maxImageWidth: maxImageWidth,
    maxImageHeight: maxImageHeight,
    enableAutoGridImages: enableAutoGridImages,
    enableMarkdownLinkify: enableMarkdownLinkify,
    markdownLinkifyTlds: markdownLinkifyTlds,
    minSearchTermLength: minSearchTermLength,
    logSearchQueries: logSearchQueries,
    groupDirectoryEnabled: groupDirectoryEnabled,
    mentionsEnabled: mentionsEnabled,
    smtpEnabled: smtpEnabled,
    taggingEnabled: taggingEnabled,
    maxTagSearchResults: maxTagSearchResults,
    usePgHeadlinesForExcerpt: usePgHeadlinesForExcerpt,
    showTimeGapDays: showTimeGapDays,
    fixedCategoryPositions: fixedCategoryPositions,
    allowUncategorizedTopics: allowUncategorizedTopics,
    defaultNavigationMenuCategoryIds: defaultNavigationMenuCategoryIds,
    topPageDefaultPeriod: topPageDefaultPeriod,
    badgesEnabled: badgesEnabled,
    allowUsernameInShareLinks: allowUsernameInShareLinks,
    readTimeWordCount: readTimeWordCount,
    minPersonalMessagePostLength: minPersonalMessagePostLength,
    allowAllUsersToFlagIllegalContent: allowAllUsersToFlagIllegalContent,
    contactEmail: contactEmail,
    illegalContentReportEmail: illegalContentReportEmail,
    suggestWeekendsInDatePickers: suggestWeekendsInDatePickers,
    plugins: value,
  );

  @override
  bool operator ==(Object other) =>
      other is SiteConfig &&
      other.emojiEnabled == emojiEnabled &&
      other.userStatusEnabled == userStatusEnabled &&
      other.emojiSet == emojiSet &&
      other.externalEmojiUrl == externalEmojiUrl &&
      listEquals(other.authorizedExtensions, authorizedExtensions) &&
      listEquals(
        other.authorizedExtensionsForStaff,
        authorizedExtensionsForStaff,
      ) &&
      other.simultaneousUploads == simultaneousUploads &&
      other.maxImageWidth == maxImageWidth &&
      other.maxImageHeight == maxImageHeight &&
      other.enableAutoGridImages == enableAutoGridImages &&
      other.enableMarkdownLinkify == enableMarkdownLinkify &&
      listEquals(other.markdownLinkifyTlds, markdownLinkifyTlds) &&
      other.minSearchTermLength == minSearchTermLength &&
      other.logSearchQueries == logSearchQueries &&
      other.groupDirectoryEnabled == groupDirectoryEnabled &&
      other.mentionsEnabled == mentionsEnabled &&
      other.smtpEnabled == smtpEnabled &&
      other.taggingEnabled == taggingEnabled &&
      other.maxTagSearchResults == maxTagSearchResults &&
      other.usePgHeadlinesForExcerpt == usePgHeadlinesForExcerpt &&
      other.showTimeGapDays == showTimeGapDays &&
      other.fixedCategoryPositions == fixedCategoryPositions &&
      other.allowUncategorizedTopics == allowUncategorizedTopics &&
      listEquals(
        other.defaultNavigationMenuCategoryIds,
        defaultNavigationMenuCategoryIds,
      ) &&
      other.topPageDefaultPeriod == topPageDefaultPeriod &&
      other.badgesEnabled == badgesEnabled &&
      other.allowUsernameInShareLinks == allowUsernameInShareLinks &&
      other.readTimeWordCount == readTimeWordCount &&
      other.minPersonalMessagePostLength == minPersonalMessagePostLength &&
      other.allowAllUsersToFlagIllegalContent ==
          allowAllUsersToFlagIllegalContent &&
      other.contactEmail == contactEmail &&
      other.illegalContentReportEmail == illegalContentReportEmail &&
      other.suggestWeekendsInDatePickers == suggestWeekendsInDatePickers &&
      other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    emojiEnabled,
    userStatusEnabled,
    emojiSet,
    externalEmojiUrl,
    Object.hashAll(authorizedExtensions),
    Object.hashAll(authorizedExtensionsForStaff),
    simultaneousUploads,
    maxImageWidth,
    maxImageHeight,
    enableAutoGridImages,
    enableMarkdownLinkify,
    Object.hashAll(markdownLinkifyTlds),
    minSearchTermLength,
    logSearchQueries,
    groupDirectoryEnabled,
    mentionsEnabled,
    smtpEnabled,
    taggingEnabled,
    maxTagSearchResults,
    usePgHeadlinesForExcerpt,
    showTimeGapDays,
    fixedCategoryPositions,
    allowUncategorizedTopics,
    Object.hashAll(defaultNavigationMenuCategoryIds),
    topPageDefaultPeriod,
    badgesEnabled,
    allowUsernameInShareLinks,
    readTimeWordCount,
    minPersonalMessagePostLength,
    allowAllUsersToFlagIllegalContent,
    contactEmail,
    illegalContentReportEmail,
    suggestWeekendsInDatePickers,
    plugins,
  ]);

  static String _topPagePeriod(Object? raw) {
    final value = jsonText(raw);
    return topPagePeriods.contains(value) ? value! : defaultTopPagePeriod;
  }

  static List<String> _extensionList(Object? raw, List<String> fallback) {
    final values = switch (raw) {
      final String value => value.split('|'),
      final List<dynamic> value => value.map(jsonText).whereType<String>(),
      _ => fallback,
    };
    return List.unmodifiable(
      values
          .map((value) => value.trim().toLowerCase().replaceFirst('.', ''))
          .where((value) => value.isNotEmpty),
    );
  }

  static List<String> _stringList(Object? raw, List<String> fallback) {
    final values = switch (raw) {
      final String value => value.split('|'),
      final List<dynamic> value => value.map(jsonText).whereType<String>(),
      _ => fallback,
    };
    return List.unmodifiable(
      values
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty),
    );
  }

  static int _positiveInt(Object? raw, int fallback) =>
      switch (jsonIntOrNull(raw)) {
        final value? when value > 0 => value,
        _ => fallback,
      };

  static String? _nonemptyText(Object? raw) {
    final value = jsonText(raw)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static int _simultaneousUploads(Object? raw) => switch (jsonIntOrNull(raw)) {
    0 => maximumSimultaneousUploads,
    final value? when value > maximumSimultaneousUploads =>
      maximumSimultaneousUploads,
    final value? when value > 0 => value,
    _ => defaultSimultaneousUploads,
  };

  static int _showTimeGapDays(Object? raw) => switch (jsonIntOrNull(raw)) {
    final value? when value >= 0 && value <= maximumShowTimeGapDays => value,
    _ => defaultShowTimeGapDays,
  };

  static List<int> _categoryIds(Object? raw) {
    final values = switch (raw) {
      final String value => value.split('|'),
      final List<dynamic> value => value,
      _ => const <Object?>[],
    };
    final seen = <int>{};
    return List.unmodifiable([
      for (final value in values)
        if (jsonIntOrNull(value) case final id? when id > 0)
          if (seen.add(id)) id,
    ]);
  }
}
