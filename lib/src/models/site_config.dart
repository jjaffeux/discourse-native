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
  });

  /// What a site looks like before it has been asked, and what one that refuses
  /// keeps looking like.
  const SiteConfig.unknown() : this();

  /// `emoji_set`'s own default, server side.
  static const String defaultEmojiSet = 'twitter';
  static const int defaultPollMaximumOptions = 20;

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
    Object.hashAll(offeredReactions),
  );
}
