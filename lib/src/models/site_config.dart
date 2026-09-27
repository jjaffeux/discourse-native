import 'package:flutter/foundation.dart';

import '../plugin_api/plugin_data.dart';
import 'composer_upload.dart';
import 'invite.dart';
import 'json.dart';

@immutable
class SiteConfig {
  const SiteConfig({
    this.emojiEnabled = true,
    this.emojiShortcutsEnabled = true,
    this.inlineEmojiTranslationEnabled = false,
    this.unicodeUsernames = false,
    this.traditionalMarkdownLinebreaks = false,
    this.markdownTypographerEnabled = true,
    this.markdownTypographerQuotationMarks = '“|”|‘|’',
    this.defaultCodeLang = 'auto',
    this.secureUploads = false,
    this.blockHotlinkedMediaExceptions = '',
    this.blockHotlinkedMedia = false,
    this.excludeRelNofollowDomains = '',
    this.addRelNofollow = true,
    this.cookingKnownSettings = const {},
    this.cookingSettingsStale = false,
    this.userStatusEnabled = false,
    this.emojiSet = defaultEmojiSet,
    this.externalEmojiUrl,
    this.authorizedExtensions = defaultAuthorizedExtensions,
    this.authorizedExtensionsForStaff = const [],
    this.allowStaffToUploadAnyFileInPm = true,
    this.maxImageSizeKb = defaultMaxImageSizeKb,
    this.maxAttachmentSizeKb = defaultMaxAttachmentSizeKb,
    this.simultaneousUploads = defaultSimultaneousUploads,
    this.maxImageWidth = 690,
    this.maxImageHeight = 500,
    this.enableAutoGridImages = true,
    this.enableMarkdownLinkify = true,
    this.markdownLinkifyTlds = defaultMarkdownLinkifyTlds,
    this.minSearchTermLength = defaultMinSearchTermLength,
    this.logSearchQueries = true,
    this.groupDirectoryEnabled = true,
    this.userDirectoryEnabled = true,
    this.mentionsEnabled = true,
    this.smtpEnabled = false,
    this.taggingEnabled = true,
    this.maxTagSearchResults = defaultMaxTagSearchResults,
    this.usePgHeadlinesForExcerpt = false,
    this.showTimeGapDays = defaultShowTimeGapDays,
    this.fixedCategoryPositions = false,
    this.allowUncategorizedTopics = false,
    this.defaultNavigationMenuCategoryIds = const [],
    this.defaultHomepage = '',
    this.topMenu = const ['latest', 'new', 'unread', 'hot', 'categories'],
    this.topPageDefaultPeriod = defaultTopPagePeriod,
    this.badgesEnabled = true,
    this.allowUsernameInShareLinks = true,
    this.readTimeWordCount = defaultReadTimeWordCount,
    this.minPersonalMessagePostLength = defaultMinPersonalMessagePostLength,
    this.allowAllUsersToFlagIllegalContent = false,
    this.contactEmail,
    this.illegalContentReportEmail,
    this.suggestWeekendsInDatePickers = true,
    this.fastEditEnabled = true,
    this.displayNameOnPosts = false,
    this.prioritizeUsernameInUx = true,
    this.invites = const InviteSettings(),
    this.composerImageOptimization = const ComposerImageOptimization(),
    this.plugins = PluginData.none,
  });

  const SiteConfig.unknown() : this();

  static const String defaultEmojiSet = 'twitter';
  static const int defaultSimultaneousUploads = 15;
  static const int defaultMaxImageSizeKb = 10240;
  static const int defaultMaxAttachmentSizeKb = 10240;

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
      emojiShortcutsEnabled: json['enable_emoji_shortcuts'] != false,
      inlineEmojiTranslationEnabled:
          json['enable_inline_emoji_translation'] == true,
      unicodeUsernames: json['unicode_usernames'] == true,
      traditionalMarkdownLinebreaks:
          json['traditional_markdown_linebreaks'] == true,
      markdownTypographerEnabled: json['enable_markdown_typographer'] != false,
      markdownTypographerQuotationMarks:
          jsonText(json['markdown_typographer_quotation_marks']) ?? '“|”|‘|’',
      defaultCodeLang: jsonText(json['default_code_lang']) ?? 'auto',
      secureUploads: json['secure_uploads'] == true,
      blockHotlinkedMediaExceptions:
          jsonText(json['block_hotlinked_media_exceptions']) ?? '',
      blockHotlinkedMedia: json['block_hotlinked_media'] == true,
      excludeRelNofollowDomains:
          jsonText(json['exclude_rel_nofollow_domains']) ?? '',
      addRelNofollow: json['add_rel_nofollow_to_user_content'] != false,
      cookingKnownSettings: _knownCookingSettings(json, wire: true),
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
      allowStaffToUploadAnyFileInPm:
          json['allow_staff_to_upload_any_file_in_pm'] != false,
      maxImageSizeKb: _positiveInt(
        json['max_image_size_kb'],
        defaultMaxImageSizeKb,
      ),
      maxAttachmentSizeKb: _positiveInt(
        json['max_attachment_size_kb'],
        defaultMaxAttachmentSizeKb,
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
      userDirectoryEnabled: json['enable_user_directory'] != false,
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
      defaultHomepage: jsonText(json['default_homepage'])?.trim() ?? '',
      topMenu: _stringList(json['top_menu'], const [
        'latest',
        'new',
        'unread',
        'hot',
        'categories',
      ]),
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
      fastEditEnabled: json['enable_fast_edit'] != false,
      displayNameOnPosts: json['display_name_on_posts'] == true,
      prioritizeUsernameInUx: json['prioritize_username_in_ux'] != false,
      invites: InviteSettings.fromJson(json),
      composerImageOptimization: ComposerImageOptimization.fromJson(json),
      plugins: extensions.readSiteSettings(json, siteUrl),
    );
  }

  /// Every field is optional so older snapshots retain core defaults.
  factory SiteConfig.fromJson(
    Map<String, dynamic> json, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) => SiteConfig(
    emojiEnabled: json['emojiEnabled'] != false,
    emojiShortcutsEnabled: json['emojiShortcutsEnabled'] != false,
    inlineEmojiTranslationEnabled:
        json['inlineEmojiTranslationEnabled'] == true,
    unicodeUsernames: json['unicodeUsernames'] == true,
    traditionalMarkdownLinebreaks:
        json['traditionalMarkdownLinebreaks'] == true,
    markdownTypographerEnabled: json['markdownTypographerEnabled'] != false,
    markdownTypographerQuotationMarks:
        jsonText(json['markdownTypographerQuotationMarks']) ?? '“|”|‘|’',
    defaultCodeLang: jsonText(json['defaultCodeLang']) ?? 'auto',
    secureUploads: json['secureUploads'] == true,
    blockHotlinkedMediaExceptions:
        jsonText(json['blockHotlinkedMediaExceptions']) ?? '',
    blockHotlinkedMedia: json['blockHotlinkedMedia'] == true,
    excludeRelNofollowDomains:
        jsonText(json['excludeRelNofollowDomains']) ?? '',
    addRelNofollow: json['addRelNofollow'] != false,
    cookingKnownSettings: _knownCookingSettings(json, wire: false),
    cookingSettingsStale: json['cookingSettingsStale'] == true,
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
    allowStaffToUploadAnyFileInPm:
        json['allowStaffToUploadAnyFileInPm'] != false,
    maxImageSizeKb: _positiveInt(json['maxImageSizeKb'], defaultMaxImageSizeKb),
    maxAttachmentSizeKb: _positiveInt(
      json['maxAttachmentSizeKb'],
      defaultMaxAttachmentSizeKb,
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
    userDirectoryEnabled: json['userDirectoryEnabled'] != false,
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
    defaultHomepage: jsonText(json['defaultHomepage']) ?? '',
    topMenu: _stringList(json['topMenu'], const [
      'latest',
      'new',
      'unread',
      'hot',
      'categories',
    ]),
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
    fastEditEnabled: json['fastEditEnabled'] != false,
    displayNameOnPosts: json['displayNameOnPosts'] == true,
    prioritizeUsernameInUx: json['prioritizeUsernameInUx'] != false,
    invites: InviteSettings.fromJson(jsonObject(json['invites'])),
    composerImageOptimization: ComposerImageOptimization.fromJson(
      jsonObject(json['composerImageOptimization']),
    ),
    plugins: extensions.readStoredSiteSettings(json),
  );

  Map<String, dynamic> toJson({
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final pluginJson = extensions.writeStoredSiteSettings(plugins);
    return {
      'emojiEnabled': emojiEnabled,
      'emojiShortcutsEnabled': emojiShortcutsEnabled,
      'inlineEmojiTranslationEnabled': inlineEmojiTranslationEnabled,
      'unicodeUsernames': unicodeUsernames,
      'traditionalMarkdownLinebreaks': traditionalMarkdownLinebreaks,
      'markdownTypographerEnabled': markdownTypographerEnabled,
      'markdownTypographerQuotationMarks': markdownTypographerQuotationMarks,
      'defaultCodeLang': defaultCodeLang,
      'secureUploads': secureUploads,
      'blockHotlinkedMediaExceptions': blockHotlinkedMediaExceptions,
      'blockHotlinkedMedia': blockHotlinkedMedia,
      'excludeRelNofollowDomains': excludeRelNofollowDomains,
      'addRelNofollow': addRelNofollow,
      'cookingKnownSettings': cookingKnownSettings.toList()..sort(),
      'cookingSettingsStale': cookingSettingsStale,
      'userStatusEnabled': userStatusEnabled,
      'emojiSet': emojiSet,
      'externalEmojiUrl': externalEmojiUrl,
      'authorizedExtensions': authorizedExtensions,
      'authorizedExtensionsForStaff': authorizedExtensionsForStaff,
      'allowStaffToUploadAnyFileInPm': allowStaffToUploadAnyFileInPm,
      'maxImageSizeKb': maxImageSizeKb,
      'maxAttachmentSizeKb': maxAttachmentSizeKb,
      'simultaneousUploads': simultaneousUploads,
      'maxImageWidth': maxImageWidth,
      'maxImageHeight': maxImageHeight,
      'enableAutoGridImages': enableAutoGridImages,
      'enableMarkdownLinkify': enableMarkdownLinkify,
      'markdownLinkifyTlds': markdownLinkifyTlds,
      'minSearchTermLength': minSearchTermLength,
      'logSearchQueries': logSearchQueries,
      'groupDirectoryEnabled': groupDirectoryEnabled,
      'userDirectoryEnabled': userDirectoryEnabled,
      'mentionsEnabled': mentionsEnabled,
      'smtpEnabled': smtpEnabled,
      'taggingEnabled': taggingEnabled,
      'maxTagSearchResults': maxTagSearchResults,
      'usePgHeadlinesForExcerpt': usePgHeadlinesForExcerpt,
      'showTimeGapDays': showTimeGapDays,
      'fixedCategoryPositions': fixedCategoryPositions,
      'allowUncategorizedTopics': allowUncategorizedTopics,
      'defaultNavigationMenuCategoryIds': defaultNavigationMenuCategoryIds,
      'defaultHomepage': defaultHomepage,
      'topMenu': topMenu,
      'topPageDefaultPeriod': topPageDefaultPeriod,
      'badgesEnabled': badgesEnabled,
      'allowUsernameInShareLinks': allowUsernameInShareLinks,
      'readTimeWordCount': readTimeWordCount,
      'minPersonalMessagePostLength': minPersonalMessagePostLength,
      'allowAllUsersToFlagIllegalContent': allowAllUsersToFlagIllegalContent,
      'contactEmail': contactEmail,
      'illegalContentReportEmail': illegalContentReportEmail,
      'suggestWeekendsInDatePickers': suggestWeekendsInDatePickers,
      'fastEditEnabled': fastEditEnabled,
      'displayNameOnPosts': displayNameOnPosts,
      'prioritizeUsernameInUx': prioritizeUsernameInUx,
      'invites': invites.toJson(),
      'composerImageOptimization': composerImageOptimization.toJson(),
      if (pluginJson.isNotEmpty) 'plugins': pluginJson,
    };
  }

  /// Existing shortcode content remains renderable when this is false; this
  /// setting only gates authoring surfaces such as autocomplete and the picker.
  final bool emojiEnabled;
  final bool emojiShortcutsEnabled;
  final bool inlineEmojiTranslationEnabled;
  final bool unicodeUsernames;
  final bool traditionalMarkdownLinebreaks;
  final bool markdownTypographerEnabled;
  final String markdownTypographerQuotationMarks;
  final String defaultCodeLang;
  final bool secureUploads;
  final String blockHotlinkedMediaExceptions;
  final bool blockHotlinkedMedia;
  final String excludeRelNofollowDomains;
  final bool addRelNofollow;

  /// Valid core settings received from site initialization, by wire key.
  /// Missing or malformed fields retain defaults without claiming knowledge.
  final Set<String> cookingKnownSettings;

  /// Set by the cache owner when these values have not been refreshed.
  final bool cookingSettingsStale;

  /// A bounded projection of core data only; plugin bags never enter the worker.
  Map<String, Object?> get cookingSettings => Map.unmodifiable({
    'enable_emoji': emojiEnabled,
    'enable_mentions': mentionsEnabled,
    'emoji_set': emojiSet,
    'external_emoji_url': externalEmojiUrl,
    'enable_markdown_linkify': enableMarkdownLinkify,
    'markdown_linkify_tlds': markdownLinkifyTlds.join('|'),
    'enable_emoji_shortcuts': emojiShortcutsEnabled,
    'enable_inline_emoji_translation': inlineEmojiTranslationEnabled,
    'unicode_usernames': unicodeUsernames,
    'traditional_markdown_linebreaks': traditionalMarkdownLinebreaks,
    'enable_markdown_typographer': markdownTypographerEnabled,
    'markdown_typographer_quotation_marks': markdownTypographerQuotationMarks,
    'default_code_lang': defaultCodeLang,
    'secure_uploads': secureUploads,
    'block_hotlinked_media_exceptions': blockHotlinkedMediaExceptions,
    'block_hotlinked_media': blockHotlinkedMedia,
    'exclude_rel_nofollow_domains': excludeRelNofollowDomains,
    'add_rel_nofollow_to_user_content': addRelNofollow,
  });

  final bool userStatusEnabled;

  /// Part of the emoji URL, so it cannot be guessed locally.
  final String emojiSet;

  final String? externalEmojiUrl;

  final List<String> authorizedExtensions;
  final List<String> authorizedExtensionsForStaff;

  /// Lets staff attach any file to a new message or a post in one, which the
  /// server honours only for an upload marked `for_private_message`.
  final bool allowStaffToUploadAnyFileInPm;
  final int maxImageSizeKb;
  final int maxAttachmentSizeKb;
  final int simultaneousUploads;
  final int maxImageWidth;
  final int maxImageHeight;

  final bool enableAutoGridImages;
  final bool enableMarkdownLinkify;
  final List<String> markdownLinkifyTlds;
  final int minSearchTermLength;
  final bool logSearchQueries;
  final bool groupDirectoryEnabled;
  final bool userDirectoryEnabled;
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
  final String defaultHomepage;
  final List<String> topMenu;
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

  final bool fastEditEnabled;

  final bool displayNameOnPosts;
  final bool prioritizeUsernameInUx;

  /// Core's `prioritizeNameFallback`: a person's full name stands in for their
  /// username only where the site shows names on posts and does not put
  /// usernames first. Both settings' defaults put the username first.
  bool get prioritizesFullName => displayNameOnPosts && !prioritizeUsernameInUx;

  final InviteSettings invites;

  final ComposerImageOptimization composerImageOptimization;

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

  static bool isImageFilename(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot >= 0 &&
        imageExtensions.contains(filename.substring(dot + 1).toLowerCase());
  }

  /// [privateMessage] is a new message or a post in one.
  bool canUploadImage(
    String filename, {
    required bool staff,
    bool privateMessage = false,
  }) =>
      isImageFilename(filename) &&
      canUploadFile(filename, staff: staff, privateMessage: privateMessage);

  bool canUploadFile(
    String filename, {
    required bool staff,
    bool privateMessage = false,
  }) {
    if (_staffUploadsAnyFile(staff: staff, privateMessage: privateMessage)) {
      return true;
    }
    final normalized = filename.toLowerCase();
    final permitted = [
      ...authorizedExtensions,
      if (staff) ...authorizedExtensionsForStaff,
    ];
    return permitted.any(
      (extension) => extension == '*' || normalized.endsWith('.$extension'),
    );
  }

  /// Mirrors core's upload checks: the server downsizes an image to fit its
  /// limit rather than refusing it, so only an attachment's limit is enforced
  /// before sending.
  ComposerUploadSizeLimit uploadSizeLimit(
    String filename, {
    required bool staff,
    bool privateMessage = false,
  }) {
    final image = isImageFilename(filename);
    return ComposerUploadSizeLimit(
      (image ? maxImageSizeKb : maxAttachmentSizeKb) * 1024,
      enforced:
          !image &&
          !_staffUploadsAnyFile(staff: staff, privateMessage: privateMessage),
    );
  }

  /// Mirrors the early return in core's `UploadValidator`.
  bool _staffUploadsAnyFile({
    required bool staff,
    required bool privateMessage,
  }) => staff && privateMessage && allowStaffToUploadAnyFileInPm;

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

  SiteConfig withCookingSettingsStale(bool stale) =>
      withPlugins(plugins, cookingSettingsStale: stale);

  SiteConfig withPlugins(PluginData value, {bool? cookingSettingsStale}) =>
      SiteConfig(
        emojiEnabled: emojiEnabled,
        emojiShortcutsEnabled: emojiShortcutsEnabled,
        inlineEmojiTranslationEnabled: inlineEmojiTranslationEnabled,
        unicodeUsernames: unicodeUsernames,
        traditionalMarkdownLinebreaks: traditionalMarkdownLinebreaks,
        markdownTypographerEnabled: markdownTypographerEnabled,
        markdownTypographerQuotationMarks: markdownTypographerQuotationMarks,
        defaultCodeLang: defaultCodeLang,
        secureUploads: secureUploads,
        blockHotlinkedMediaExceptions: blockHotlinkedMediaExceptions,
        blockHotlinkedMedia: blockHotlinkedMedia,
        excludeRelNofollowDomains: excludeRelNofollowDomains,
        addRelNofollow: addRelNofollow,
        cookingKnownSettings: cookingKnownSettings,
        cookingSettingsStale: cookingSettingsStale ?? this.cookingSettingsStale,
        userStatusEnabled: userStatusEnabled,
        emojiSet: emojiSet,
        externalEmojiUrl: externalEmojiUrl,
        authorizedExtensions: authorizedExtensions,
        authorizedExtensionsForStaff: authorizedExtensionsForStaff,
        allowStaffToUploadAnyFileInPm: allowStaffToUploadAnyFileInPm,
        maxImageSizeKb: maxImageSizeKb,
        maxAttachmentSizeKb: maxAttachmentSizeKb,
        simultaneousUploads: simultaneousUploads,
        maxImageWidth: maxImageWidth,
        maxImageHeight: maxImageHeight,
        enableAutoGridImages: enableAutoGridImages,
        enableMarkdownLinkify: enableMarkdownLinkify,
        markdownLinkifyTlds: markdownLinkifyTlds,
        minSearchTermLength: minSearchTermLength,
        logSearchQueries: logSearchQueries,
        groupDirectoryEnabled: groupDirectoryEnabled,
        userDirectoryEnabled: userDirectoryEnabled,
        mentionsEnabled: mentionsEnabled,
        smtpEnabled: smtpEnabled,
        taggingEnabled: taggingEnabled,
        maxTagSearchResults: maxTagSearchResults,
        usePgHeadlinesForExcerpt: usePgHeadlinesForExcerpt,
        showTimeGapDays: showTimeGapDays,
        fixedCategoryPositions: fixedCategoryPositions,
        allowUncategorizedTopics: allowUncategorizedTopics,
        defaultNavigationMenuCategoryIds: defaultNavigationMenuCategoryIds,
        defaultHomepage: defaultHomepage,
        topMenu: topMenu,
        topPageDefaultPeriod: topPageDefaultPeriod,
        badgesEnabled: badgesEnabled,
        allowUsernameInShareLinks: allowUsernameInShareLinks,
        readTimeWordCount: readTimeWordCount,
        minPersonalMessagePostLength: minPersonalMessagePostLength,
        allowAllUsersToFlagIllegalContent: allowAllUsersToFlagIllegalContent,
        contactEmail: contactEmail,
        illegalContentReportEmail: illegalContentReportEmail,
        suggestWeekendsInDatePickers: suggestWeekendsInDatePickers,
        fastEditEnabled: fastEditEnabled,
        displayNameOnPosts: displayNameOnPosts,
        prioritizeUsernameInUx: prioritizeUsernameInUx,
        invites: invites,
        composerImageOptimization: composerImageOptimization,
        plugins: value,
      );

  @override
  bool operator ==(Object other) =>
      other is SiteConfig &&
      other.emojiEnabled == emojiEnabled &&
      other.emojiShortcutsEnabled == emojiShortcutsEnabled &&
      other.inlineEmojiTranslationEnabled == inlineEmojiTranslationEnabled &&
      other.unicodeUsernames == unicodeUsernames &&
      other.traditionalMarkdownLinebreaks == traditionalMarkdownLinebreaks &&
      other.markdownTypographerEnabled == markdownTypographerEnabled &&
      other.markdownTypographerQuotationMarks ==
          markdownTypographerQuotationMarks &&
      other.defaultCodeLang == defaultCodeLang &&
      other.secureUploads == secureUploads &&
      other.blockHotlinkedMediaExceptions == blockHotlinkedMediaExceptions &&
      other.blockHotlinkedMedia == blockHotlinkedMedia &&
      other.excludeRelNofollowDomains == excludeRelNofollowDomains &&
      other.addRelNofollow == addRelNofollow &&
      setEquals(other.cookingKnownSettings, cookingKnownSettings) &&
      other.cookingSettingsStale == cookingSettingsStale &&
      other.userStatusEnabled == userStatusEnabled &&
      other.emojiSet == emojiSet &&
      other.externalEmojiUrl == externalEmojiUrl &&
      listEquals(other.authorizedExtensions, authorizedExtensions) &&
      listEquals(
        other.authorizedExtensionsForStaff,
        authorizedExtensionsForStaff,
      ) &&
      other.allowStaffToUploadAnyFileInPm == allowStaffToUploadAnyFileInPm &&
      other.maxImageSizeKb == maxImageSizeKb &&
      other.maxAttachmentSizeKb == maxAttachmentSizeKb &&
      other.simultaneousUploads == simultaneousUploads &&
      other.maxImageWidth == maxImageWidth &&
      other.maxImageHeight == maxImageHeight &&
      other.enableAutoGridImages == enableAutoGridImages &&
      other.enableMarkdownLinkify == enableMarkdownLinkify &&
      listEquals(other.markdownLinkifyTlds, markdownLinkifyTlds) &&
      other.minSearchTermLength == minSearchTermLength &&
      other.logSearchQueries == logSearchQueries &&
      other.groupDirectoryEnabled == groupDirectoryEnabled &&
      other.userDirectoryEnabled == userDirectoryEnabled &&
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
      other.defaultHomepage == defaultHomepage &&
      listEquals(other.topMenu, topMenu) &&
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
      other.fastEditEnabled == fastEditEnabled &&
      other.displayNameOnPosts == displayNameOnPosts &&
      other.prioritizeUsernameInUx == prioritizeUsernameInUx &&
      other.invites == invites &&
      other.composerImageOptimization == composerImageOptimization &&
      other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    emojiEnabled,
    emojiShortcutsEnabled,
    inlineEmojiTranslationEnabled,
    unicodeUsernames,
    traditionalMarkdownLinebreaks,
    markdownTypographerEnabled,
    markdownTypographerQuotationMarks,
    defaultCodeLang,
    secureUploads,
    blockHotlinkedMediaExceptions,
    blockHotlinkedMedia,
    excludeRelNofollowDomains,
    addRelNofollow,
    Object.hashAllUnordered(cookingKnownSettings),
    cookingSettingsStale,
    userStatusEnabled,
    emojiSet,
    externalEmojiUrl,
    Object.hashAll(authorizedExtensions),
    Object.hashAll(authorizedExtensionsForStaff),
    allowStaffToUploadAnyFileInPm,
    maxImageSizeKb,
    maxAttachmentSizeKb,
    simultaneousUploads,
    maxImageWidth,
    maxImageHeight,
    enableAutoGridImages,
    enableMarkdownLinkify,
    Object.hashAll(markdownLinkifyTlds),
    minSearchTermLength,
    logSearchQueries,
    groupDirectoryEnabled,
    userDirectoryEnabled,
    mentionsEnabled,
    smtpEnabled,
    taggingEnabled,
    maxTagSearchResults,
    usePgHeadlinesForExcerpt,
    showTimeGapDays,
    fixedCategoryPositions,
    allowUncategorizedTopics,
    Object.hashAll(defaultNavigationMenuCategoryIds),
    defaultHomepage,
    Object.hashAll(topMenu),
    topPageDefaultPeriod,
    badgesEnabled,
    allowUsernameInShareLinks,
    readTimeWordCount,
    minPersonalMessagePostLength,
    allowAllUsersToFlagIllegalContent,
    contactEmail,
    illegalContentReportEmail,
    suggestWeekendsInDatePickers,
    fastEditEnabled,
    displayNameOnPosts,
    prioritizeUsernameInUx,
    invites,
    composerImageOptimization,
    plugins,
  ]);

  static Set<String> _knownCookingSettings(
    Map<String, dynamic> json, {
    required bool wire,
  }) {
    const types = <String, String>{
      'enable_emoji_shortcuts': 'bool',
      'enable_inline_emoji_translation': 'bool',
      'unicode_usernames': 'bool',
      'traditional_markdown_linebreaks': 'bool',
      'enable_markdown_typographer': 'bool',
      'markdown_typographer_quotation_marks': 'String',
      'default_code_lang': 'String',
      'secure_uploads': 'bool',
      'block_hotlinked_media_exceptions': 'String',
      'block_hotlinked_media': 'bool',
      'exclude_rel_nofollow_domains': 'String',
      'add_rel_nofollow_to_user_content': 'bool',
      'enable_emoji': 'bool',
      'enable_mentions': 'bool',
      'emoji_set': 'String',
      'external_emoji_url': 'String',
      'enable_markdown_linkify': 'bool',
      'markdown_linkify_tlds': 'list',
    };
    if (!wire) {
      final raw = json['cookingKnownSettings'];
      return Set.unmodifiable(
        raw is List
            ? raw.whereType<String>().where(types.containsKey)
            : const <String>[],
      );
    }
    return Set.unmodifiable([
      for (final entry in types.entries)
        if (switch (entry.value) {
          'bool' => json[entry.key] is bool,
          'String' => json[entry.key] is String,
          'list' =>
            json[entry.key] is String ||
                (json[entry.key] is List &&
                    (json[entry.key] as List).every((v) => v is String)),
          _ => false,
        })
          entry.key,
    ]);
  }

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
          .map(
            (value) =>
                value.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), ''),
          )
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

/// Site policy shared by the pre-upload optimizer and native photo picker.
/// The picker applies size/quality while exporting mobile JPEGs; other inputs
/// are prepared by the composer before networking starts.
@immutable
final class ComposerImageOptimization {
  const ComposerImageOptimization({
    this.enabled = true,
    this.iosEnabled = true,
    this.bytesThreshold = defaultBytesThreshold,
    this.resizeDimensionsThreshold = defaultResizeDimensionsThreshold,
    this.resizeWidthTarget = defaultResizeWidthTarget,
    this.encodeQuality = 0,
    this.imageQuality = defaultImageQuality,
  });

  /// Stored copies keep the wire keys, so one reader serves both.
  factory ComposerImageOptimization.fromJson(
    Map<String, dynamic> json,
  ) => ComposerImageOptimization(
    enabled: json['composer_media_optimization_image_enabled'] != false,
    iosEnabled: json['composer_ios_media_optimisation_image_enabled'] != false,
    bytesThreshold: _threshold(
      json['composer_media_optimization_image_bytes_optimization_threshold'],
      defaultBytesThreshold,
    ),
    resizeDimensionsThreshold: _threshold(
      json['composer_media_optimization_image_resize_dimensions_threshold'],
      defaultResizeDimensionsThreshold,
    ),
    resizeWidthTarget: switch (jsonIntOrNull(
      json['composer_media_optimization_image_resize_width_target'],
    )) {
      final value? when value > 0 => value,
      _ => defaultResizeWidthTarget,
    },
    encodeQuality:
        _quality(json['composer_media_optimization_image_encode_quality']) ?? 0,
    imageQuality: _quality(json['image_quality']) ?? defaultImageQuality,
  );

  static const int defaultResizeWidthTarget = 1920;
  static const int defaultBytesThreshold = 524288;
  static const int defaultResizeDimensionsThreshold = 1920;
  static const int defaultImageQuality = 90;

  final bool enabled;

  /// Checked in addition to [enabled], on iOS only, as core does.
  final bool iosEnabled;
  final int bytesThreshold;
  final int resizeDimensionsThreshold;

  /// Core resizes only past a separate dimensions threshold. A picker can
  /// only cap the width, and both settings default to the same value.
  final int resizeWidthTarget;

  /// Zero defers to [imageQuality].
  final int encodeQuality;
  final int imageQuality;

  /// The width a wider photo is scaled down to, or null where core would
  /// upload it at full resolution.
  int? resizeWidth({required bool ios}) =>
      enabled && (iosEnabled || !ios) ? resizeWidthTarget : null;

  /// Applies even where [resizeWidth] is null: the photo library re-encodes
  /// every photo, and without a quality it encodes at the maximum, several
  /// times the size of the camera's own file.
  int get quality => encodeQuality > 0 ? encodeQuality : imageQuality;

  Map<String, dynamic> toJson() => {
    'composer_media_optimization_image_enabled': enabled,
    'composer_ios_media_optimisation_image_enabled': iosEnabled,
    'composer_media_optimization_image_bytes_optimization_threshold':
        bytesThreshold,
    'composer_media_optimization_image_resize_dimensions_threshold':
        resizeDimensionsThreshold,
    'composer_media_optimization_image_resize_width_target': resizeWidthTarget,
    'composer_media_optimization_image_encode_quality': encodeQuality,
    'image_quality': imageQuality,
  };

  @override
  bool operator ==(Object other) =>
      other is ComposerImageOptimization &&
      other.enabled == enabled &&
      other.iosEnabled == iosEnabled &&
      other.bytesThreshold == bytesThreshold &&
      other.resizeDimensionsThreshold == resizeDimensionsThreshold &&
      other.resizeWidthTarget == resizeWidthTarget &&
      other.encodeQuality == encodeQuality &&
      other.imageQuality == imageQuality;

  @override
  int get hashCode => Object.hash(
    enabled,
    iosEnabled,
    bytesThreshold,
    resizeDimensionsThreshold,
    resizeWidthTarget,
    encodeQuality,
    imageQuality,
  );

  /// The photo library rejects a quality outside 0–100, and core's zero
  /// means unset, never the lowest quality.
  static int? _quality(Object? raw) => switch (jsonIntOrNull(raw)) {
    final value? when value > 0 && value <= 100 => value,
    _ => null,
  };

  static int _threshold(Object? raw, int fallback) =>
      switch (jsonIntOrNull(raw)) {
        final value? when value >= 0 => value,
        _ => fallback,
      };
}
