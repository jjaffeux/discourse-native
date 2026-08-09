import 'package:flutter/foundation.dart';

import 'json.dart';

/// The handful of a site's client settings that decide how something is
/// *drawn*, or what may be *offered*.
///
/// Deliberately not a capability layer, and the distinction is the whole point.
/// Nothing here may decide whether a feature exists — that is the payload's
/// job, because this arrives asynchronously and can be refused, and a gate that
/// is wrong for a frame produces a wrong *write* rather than a missing button.
/// See `SitePlugin`.
///
/// So every field has a default, every default is core's own, and a site that
/// will not answer is simply drawn as core. There is no loading state and no
/// error state, because there is nothing here worth telling a reader about.
@immutable
class SiteConfig {
  const SiteConfig({
    this.emojiSet = defaultEmojiSet,
    this.externalEmojiUrl,
    this.mainReaction,
    this.offeredReactions = const [],
    this.allowAnyEmoji = false,
    this.desaturatedReactionPanel = false,
    this.pollMaximumOptions = defaultPollMaximumOptions,
    this.pollDefaultPublic = true,
    this.assignStatusesEnabled = false,
    this.assignStatuses = const [],
    this.authorizedExtensions = defaultAuthorizedExtensions,
    this.authorizedExtensionsForStaff = const [],
    this.simultaneousUploads = 15,
    this.maxImageWidth = 690,
    this.maxImageHeight = 500,
    this.minSearchTermLength = defaultMinSearchTermLength,
    this.fixedCategoryPositions = false,
    this.allowUncategorizedTopics = false,
    this.defaultNavigationMenuCategoryIds = const [],
    this.resenha = const ResenhaClientConfig(),
  });

  /// What a site looks like before it has been asked, and what one that refuses
  /// keeps looking like.
  const SiteConfig.unknown() : this();

  /// `emoji_set`'s own default, server side.
  static const String defaultEmojiSet = 'twitter';
  static const int defaultPollMaximumOptions = 20;
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

  /// Reads `GET /site/settings.json`, which is `SiteSetting.client_settings_json`
  /// — every setting marked `client: true`, core's and every plugin's alike.
  ///
  /// A plugin's settings are registered whether or not it is enabled, so they
  /// are here either way. Reading them without checking the plugin's own
  /// `_enabled` flag would offer a picker on a site that has switched reactions
  /// off, which is why that check is not a formality.
  factory SiteConfig.fromSettings(Map<String, dynamic> json) {
    final reactions = json['discourse_reactions_enabled'] == true;
    final main = reactions
        ? jsonText(json['discourse_reactions_reaction_for_like'])
        : null;

    return SiteConfig(
      emojiSet: jsonText(json['emoji_set']) ?? defaultEmojiSet,
      externalEmojiUrl: _trimSlash(jsonText(json['external_emoji_url'])),
      mainReaction: main,
      offeredReactions: reactions
          ? _offered(json['discourse_reactions_enabled_reactions'], main)
          : const [],
      allowAnyEmoji:
          reactions && json['discourse_reactions_allow_any_emoji'] == true,
      desaturatedReactionPanel:
          reactions &&
          json['discourse_reactions_desaturated_reaction_panel'] == true,
      pollMaximumOptions: switch (jsonIntOrNull(json['poll_maximum_options'])) {
        final value? when value >= 2 => value,
        _ => defaultPollMaximumOptions,
      },
      pollDefaultPublic: json['poll_default_public'] != false,
      assignStatusesEnabled: json['enable_assign_status'] == true,
      assignStatuses: json['enable_assign_status'] == true
          ? _pipeList(json['assign_statuses'])
          : const [],
      authorizedExtensions: _extensionList(
        json['authorized_extensions'],
        defaultAuthorizedExtensions,
      ),
      authorizedExtensionsForStaff: _extensionList(
        json['authorized_extensions_for_staff'],
        const [],
      ),
      simultaneousUploads: switch (jsonIntOrNull(
        json['simultaneous_uploads'],
      )) {
        final value? when value >= 0 => value,
        _ => 15,
      },
      maxImageWidth: _positiveInt(json['max_image_width'], 690),
      maxImageHeight: _positiveInt(json['max_image_height'], 500),
      minSearchTermLength:
          jsonIntOrNull(json['min_search_term_length'])?.clamp(1, 100) ??
          defaultMinSearchTermLength,
      fixedCategoryPositions: json['fixed_category_positions'] == true,
      allowUncategorizedTopics: json['allow_uncategorized_topics'] == true,
      defaultNavigationMenuCategoryIds: _categoryIds(
        json['default_navigation_menu_categories'],
      ),
      resenha: ResenhaClientConfig.fromSettings(json),
    );
  }

  /// Reads our own persisted copy. Every field is optional, deliberately: a
  /// missing one has to mean "core's default" rather than throwing, because
  /// `InstanceStore.load` answers a decode failure by forgetting every site the
  /// user had.
  factory SiteConfig.fromJson(Map<String, dynamic> json) => SiteConfig(
    emojiSet: jsonText(json['emojiSet']) ?? defaultEmojiSet,
    externalEmojiUrl: jsonText(json['externalEmojiUrl']),
    mainReaction: jsonText(json['mainReaction']),
    offeredReactions: List.unmodifiable(
      jsonArray(json['offeredReactions']).map(jsonText).whereType<String>(),
    ),
    allowAnyEmoji: json['allowAnyEmoji'] == true,
    desaturatedReactionPanel: json['desaturatedReactionPanel'] == true,
    pollMaximumOptions:
        jsonIntOrNull(json['pollMaximumOptions']) ?? defaultPollMaximumOptions,
    pollDefaultPublic: json['pollDefaultPublic'] != false,
    assignStatusesEnabled: json['assignStatusesEnabled'] == true,
    assignStatuses: List.unmodifiable(
      jsonArray(json['assignStatuses']).map(jsonText).whereType<String>(),
    ),
    authorizedExtensions: _extensionList(
      json['authorizedExtensions'],
      defaultAuthorizedExtensions,
    ),
    authorizedExtensionsForStaff: _extensionList(
      json['authorizedExtensionsForStaff'],
      const [],
    ),
    simultaneousUploads:
        jsonIntOrNull(json['simultaneousUploads'])?.clamp(0, 30) ?? 15,
    maxImageWidth: _positiveInt(json['maxImageWidth'], 690),
    maxImageHeight: _positiveInt(json['maxImageHeight'], 500),
    minSearchTermLength:
        jsonIntOrNull(json['minSearchTermLength'])?.clamp(1, 100) ??
        defaultMinSearchTermLength,
    fixedCategoryPositions: json['fixedCategoryPositions'] == true,
    allowUncategorizedTopics: json['allowUncategorizedTopics'] == true,
    defaultNavigationMenuCategoryIds: _categoryIds(
      json['defaultNavigationMenuCategoryIds'],
    ),
    resenha: jsonObject(json['resenha']).isEmpty
        ? const ResenhaClientConfig()
        : ResenhaClientConfig.fromJson(jsonObject(json['resenha'])),
  );

  Map<String, dynamic> toJson() => {
    'emojiSet': emojiSet,
    'externalEmojiUrl': externalEmojiUrl,
    'mainReaction': mainReaction,
    'offeredReactions': offeredReactions,
    'allowAnyEmoji': allowAnyEmoji,
    'desaturatedReactionPanel': desaturatedReactionPanel,
    'pollMaximumOptions': pollMaximumOptions,
    'pollDefaultPublic': pollDefaultPublic,
    'assignStatusesEnabled': assignStatusesEnabled,
    'assignStatuses': assignStatuses,
    'authorizedExtensions': authorizedExtensions,
    'authorizedExtensionsForStaff': authorizedExtensionsForStaff,
    'simultaneousUploads': simultaneousUploads,
    'maxImageWidth': maxImageWidth,
    'maxImageHeight': maxImageHeight,
    'minSearchTermLength': minSearchTermLength,
    'fixedCategoryPositions': fixedCategoryPositions,
    'allowUncategorizedTopics': allowUncategorizedTopics,
    'defaultNavigationMenuCategoryIds': defaultNavigationMenuCategoryIds,
    'resenha': resenha.toJson(),
  };

  /// Which set of artwork the site draws its emoji from — `twitter`, `apple`,
  /// `google`, `facebook`. Part of the URL, so it cannot be guessed.
  final String emojiSet;

  /// Where that artwork is served from, for a site that has moved it off its
  /// own origin. Null is the ordinary case.
  final String? externalEmojiUrl;

  /// The reaction that *is* a like — `discourse_reactions_reaction_for_like`.
  ///
  /// **Null means not known**, which is a different thing from `heart`. The
  /// setting is enum-constrained to the reactions a site actually allows, and
  /// `heart` is not in the default enabled list — so on a site whose admin set
  /// it to `+1`, sending a guessed `heart` earns a 422 whose body says only
  /// "Sorry, an error has occurred." Nothing here ever guesses it; where it is
  /// unknown the picker is opened instead.
  final String? mainReaction;

  /// What the picker offers — `discourse_reactions_enabled_reactions`, with
  /// [mainReaction] at the front where the setting leaves it out. Empty until
  /// the site has been asked, and on a site with reactions switched off.
  final List<String> offeredReactions;

  /// Whether the site lets any emoji be used, not only the offered ones. The
  /// picker still offers the list; this says the row may hold others.
  final bool allowAnyEmoji;

  /// Whether the site draws its reaction picker desaturated.
  final bool desaturatedReactionPanel;

  /// Poll builder limits/defaults. These are presentation defaults, never a
  /// claim that Poll is enabled on a site.
  final int pollMaximumOptions;
  final bool pollDefaultPublic;

  /// Optional Assign status presentation. These settings only decide what an
  /// already-authorized assignment sheet offers; payload records and their
  /// per-target `can_assign` remain the feature and permission gates.
  final bool assignStatusesEnabled;
  final List<String> assignStatuses;
  final List<String> authorizedExtensions;
  final List<String> authorizedExtensionsForStaff;
  final int simultaneousUploads;
  final int maxImageWidth;
  final int maxImageHeight;
  final int minSearchTermLength;

  /// How core orders category navigation, and which categories anonymous
  /// visitors see when the site has chosen an explicit menu.
  final bool fixedCategoryPositions;
  final bool allowUncategorizedTopics;
  final List<int> defaultNavigationMenuCategoryIds;
  final ResenhaClientConfig resenha;

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

  /// Where the artwork for one emoji lives on this site.
  ///
  /// Mirrors `Emoji.url_for`: a `:tN` tone suffix becomes a `/N` path segment,
  /// and surrounding colons are not part of the name. The `?v=` core appends is
  /// a build constant with no JSON endpoint to read it from — it busts caches
  /// and nothing else, and `EmojiCache` is the cache here.
  ///
  /// Custom emoji are uploads and are not at this address — they would 404
  /// here. Callers go through `ShellController.emojiUrlFor`, which consults
  /// the site's own map of them before falling back to this.
  String emojiUrl(String name, {required String siteUrl}) {
    final base = externalEmojiUrl ?? '$siteUrl/images/emoji';
    return '$base/$emojiSet/${_toned(name)}.png';
  }

  /// `heart` stays `heart`; `:wave:t3:` becomes `wave/3`.
  static String _toned(String name) {
    final match = RegExp(r'^:?(.+?)(?::t([1-6]))?:?$').firstMatch(name);
    if (match == null) return name;
    final tone = match.group(2);
    return tone == null ? match.group(1)! : '${match.group(1)}/$tone';
  }

  /// The offered list, with the main reaction guaranteed a place.
  ///
  /// The two settings are independent, and the default pair leaves `heart` —
  /// the default main reaction — out of the offered list entirely. A picker
  /// that cannot offer the site's own like would be a strange thing to draw.
  ///
  /// Accepts a pipe-separated string or a list, and treats anything else as
  /// empty rather than throwing: a decode failure here costs the caller an
  /// attempt, and after enough of those the site is drawn as core for the
  /// rest of the session.
  static List<String> _offered(Object? raw, String? main) {
    final parts = switch (raw) {
      final String text => text.split('|'),
      final List<dynamic> list => list.map(jsonText).whereType<String>(),
      _ => const <String>[],
    };
    final listed = [
      for (final part in parts)
        if (part.trim().isNotEmpty) part.trim(),
    ];
    if (main == null || listed.contains(main)) {
      return List.unmodifiable(listed);
    }
    return List.unmodifiable([main, ...listed]);
  }

  static String? _trimSlash(String? value) => value == null
      ? null
      : (value.endsWith('/') ? value.substring(0, value.length - 1) : value);

  /// Hand-written because a stored copy is compared against a fresh one to
  /// decide whether preferences are worth rewriting, and identity would answer
  /// "changed" every launch.
  @override
  bool operator ==(Object other) =>
      other is SiteConfig &&
      other.emojiSet == emojiSet &&
      other.externalEmojiUrl == externalEmojiUrl &&
      other.mainReaction == mainReaction &&
      other.allowAnyEmoji == allowAnyEmoji &&
      other.desaturatedReactionPanel == desaturatedReactionPanel &&
      other.pollMaximumOptions == pollMaximumOptions &&
      other.pollDefaultPublic == pollDefaultPublic &&
      other.assignStatusesEnabled == assignStatusesEnabled &&
      listEquals(other.assignStatuses, assignStatuses) &&
      listEquals(other.authorizedExtensions, authorizedExtensions) &&
      listEquals(
        other.authorizedExtensionsForStaff,
        authorizedExtensionsForStaff,
      ) &&
      other.simultaneousUploads == simultaneousUploads &&
      other.maxImageWidth == maxImageWidth &&
      other.maxImageHeight == maxImageHeight &&
      other.minSearchTermLength == minSearchTermLength &&
      other.fixedCategoryPositions == fixedCategoryPositions &&
      other.allowUncategorizedTopics == allowUncategorizedTopics &&
      listEquals(
        other.defaultNavigationMenuCategoryIds,
        defaultNavigationMenuCategoryIds,
      ) &&
      other.resenha == resenha &&
      listEquals(other.offeredReactions, offeredReactions);

  @override
  int get hashCode => Object.hash(
    emojiSet,
    externalEmojiUrl,
    mainReaction,
    allowAnyEmoji,
    desaturatedReactionPanel,
    pollMaximumOptions,
    pollDefaultPublic,
    assignStatusesEnabled,
    Object.hashAll(assignStatuses),
    Object.hashAll(authorizedExtensions),
    Object.hashAll(authorizedExtensionsForStaff),
    simultaneousUploads,
    maxImageWidth,
    maxImageHeight,
    minSearchTermLength,
    fixedCategoryPositions,
    allowUncategorizedTopics,
    Object.hashAll(defaultNavigationMenuCategoryIds),
    resenha,
    Object.hashAll(offeredReactions),
  );

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

  static List<String> _pipeList(Object? raw) {
    final values = switch (raw) {
      final String value => value.split('|'),
      final List<dynamic> value => value.map(jsonText).whereType<String>(),
      _ => const <String>[],
    };
    return List.unmodifiable(
      values.map((value) => value.trim()).where((value) => value.isNotEmpty),
    );
  }

  static int _positiveInt(Object? raw, int fallback) =>
      switch (jsonIntOrNull(raw)) {
        final value? when value > 0 => value,
        _ => fallback,
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

/// Resenha's client-marked site settings. These shape native controls but do
/// not claim the plugin is available; successful directory discovery remains
/// the capability signal.
@immutable
class ResenhaClientConfig {
  const ResenhaClientConfig({
    this.enabled = false,
    this.videoEnabled = false,
    this.videoMaxPublishers = 8,
    this.recordingEnabled = false,
    this.maxVoiceQuality = 'maximum',
    this.maxCameraQuality = 'maximum',
    this.maxScreenShareQuality = 'maximum',
    this.idleThresholdMinutes = 5,
    this.afkAutoMuteThresholdMinutes = 15,
    this.afkDisconnectThresholdMinutes = 30,
    this.autoStatusEnabled = true,
    this.chatEnabled = true,
  });

  factory ResenhaClientConfig.fromSettings(Map<String, dynamic> json) =>
      ResenhaClientConfig(
        enabled: json['resenha_enabled'] == true,
        videoEnabled: json['resenha_video_enabled'] == true,
        videoMaxPublishers: _boundedInt(
          json['resenha_video_max_publishers'],
          fallback: 8,
          minimum: 2,
          maximum: 16,
        ),
        recordingEnabled: json['resenha_livekit_recording_enabled'] == true,
        maxVoiceQuality: _quality(json['resenha_max_voice_quality']),
        maxCameraQuality: _quality(json['resenha_max_camera_quality']),
        maxScreenShareQuality: _quality(
          json['resenha_max_screen_share_quality'],
        ),
        idleThresholdMinutes: _boundedInt(
          json['resenha_idle_threshold_minutes'],
          fallback: 5,
          minimum: 0,
          maximum: 60,
        ),
        afkAutoMuteThresholdMinutes: _boundedInt(
          json['resenha_afk_auto_mute_threshold_minutes'],
          fallback: 15,
          minimum: 0,
          maximum: 120,
        ),
        afkDisconnectThresholdMinutes: _boundedInt(
          json['resenha_afk_disconnect_threshold_minutes'],
          fallback: 30,
          minimum: 0,
          maximum: 240,
        ),
        autoStatusEnabled: json['resenha_auto_status_enabled'] != false,
        chatEnabled: json['resenha_chat_enabled'] != false,
      );

  factory ResenhaClientConfig.fromJson(Map<String, dynamic> json) =>
      ResenhaClientConfig(
        enabled: json['enabled'] == true,
        videoEnabled: json['videoEnabled'] == true,
        videoMaxPublishers: _boundedInt(
          json['videoMaxPublishers'],
          fallback: 8,
          minimum: 2,
          maximum: 16,
        ),
        recordingEnabled: json['recordingEnabled'] == true,
        maxVoiceQuality: _quality(json['maxVoiceQuality']),
        maxCameraQuality: _quality(json['maxCameraQuality']),
        maxScreenShareQuality: _quality(json['maxScreenShareQuality']),
        idleThresholdMinutes: _boundedInt(
          json['idleThresholdMinutes'],
          fallback: 5,
          minimum: 0,
          maximum: 60,
        ),
        afkAutoMuteThresholdMinutes: _boundedInt(
          json['afkAutoMuteThresholdMinutes'],
          fallback: 15,
          minimum: 0,
          maximum: 120,
        ),
        afkDisconnectThresholdMinutes: _boundedInt(
          json['afkDisconnectThresholdMinutes'],
          fallback: 30,
          minimum: 0,
          maximum: 240,
        ),
        autoStatusEnabled: json['autoStatusEnabled'] != false,
        chatEnabled: json['chatEnabled'] != false,
      );

  final bool enabled;
  final bool videoEnabled;
  final int videoMaxPublishers;
  final bool recordingEnabled;
  final String maxVoiceQuality;
  final String maxCameraQuality;
  final String maxScreenShareQuality;
  final int idleThresholdMinutes;
  final int afkAutoMuteThresholdMinutes;
  final int afkDisconnectThresholdMinutes;
  final bool autoStatusEnabled;
  final bool chatEnabled;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'videoEnabled': videoEnabled,
    'videoMaxPublishers': videoMaxPublishers,
    'recordingEnabled': recordingEnabled,
    'maxVoiceQuality': maxVoiceQuality,
    'maxCameraQuality': maxCameraQuality,
    'maxScreenShareQuality': maxScreenShareQuality,
    'idleThresholdMinutes': idleThresholdMinutes,
    'afkAutoMuteThresholdMinutes': afkAutoMuteThresholdMinutes,
    'afkDisconnectThresholdMinutes': afkDisconnectThresholdMinutes,
    'autoStatusEnabled': autoStatusEnabled,
    'chatEnabled': chatEnabled,
  };

  @override
  bool operator ==(Object other) =>
      other is ResenhaClientConfig &&
      other.enabled == enabled &&
      other.videoEnabled == videoEnabled &&
      other.videoMaxPublishers == videoMaxPublishers &&
      other.recordingEnabled == recordingEnabled &&
      other.maxVoiceQuality == maxVoiceQuality &&
      other.maxCameraQuality == maxCameraQuality &&
      other.maxScreenShareQuality == maxScreenShareQuality &&
      other.idleThresholdMinutes == idleThresholdMinutes &&
      other.afkAutoMuteThresholdMinutes == afkAutoMuteThresholdMinutes &&
      other.afkDisconnectThresholdMinutes == afkDisconnectThresholdMinutes &&
      other.autoStatusEnabled == autoStatusEnabled &&
      other.chatEnabled == chatEnabled;

  @override
  int get hashCode => Object.hash(
    enabled,
    videoEnabled,
    videoMaxPublishers,
    recordingEnabled,
    maxVoiceQuality,
    maxCameraQuality,
    maxScreenShareQuality,
    idleThresholdMinutes,
    afkAutoMuteThresholdMinutes,
    afkDisconnectThresholdMinutes,
    autoStatusEnabled,
    chatEnabled,
  );

  static String _quality(Object? value) => switch (jsonText(value)) {
    'standard' => 'standard',
    'high' => 'high',
    'maximum' => 'maximum',
    _ => 'maximum',
  };

  static int _boundedInt(
    Object? value, {
    required int fallback,
    required int minimum,
    required int maximum,
  }) {
    final parsed = jsonIntOrNull(value);
    if (parsed == null || parsed < minimum || parsed > maximum) return fallback;
    return parsed;
  }
}
