import 'package:flutter/foundation.dart';

import '../../models/json.dart';
import '../../models/site_config.dart';
import '../../plugin_api/plugin_data.dart';

const reactionsSettingsDataKey = PluginDataKey<ReactionsSettings>(
  owner: 'discourse-reactions',
  name: 'site-settings',
);

/// Client settings owned by discourse-reactions.
///
/// Post payload presence remains the feature gate. These values only describe
/// which reactions an authoring surface may offer and how to present them.
@immutable
final class ReactionsSettings {
  const ReactionsSettings({
    this.mainReaction,
    this.offeredReactions = const [],
    this.allowAnyEmoji = false,
    this.desaturatedPanel = false,
  });

  factory ReactionsSettings.fromSiteSettings(Map<String, dynamic> json) {
    if (json['discourse_reactions_enabled'] != true) {
      return const ReactionsSettings();
    }
    final mainReaction = jsonText(
      json['discourse_reactions_reaction_for_like'],
    );
    return ReactionsSettings(
      mainReaction: mainReaction,
      offeredReactions: _offeredReactions(
        json['discourse_reactions_enabled_reactions'],
        mainReaction,
      ),
      allowAnyEmoji: json['discourse_reactions_allow_any_emoji'] == true,
      desaturatedPanel:
          json['discourse_reactions_desaturated_reaction_panel'] == true,
    );
  }

  static ReactionsSettings? fromStored(Object? value) {
    final json = _objectFields(value);
    if (json == null) return null;
    return ReactionsSettings(
      mainReaction: jsonText(json['mainReaction']),
      offeredReactions: _storedReactionList(json['offeredReactions']),
      allowAnyEmoji: json['allowAnyEmoji'] == true,
      desaturatedPanel: json['desaturatedPanel'] == true,
    );
  }

  final String? mainReaction;
  final List<String> offeredReactions;
  final bool allowAnyEmoji;
  final bool desaturatedPanel;

  Map<String, Object?> toStored() => {
    'mainReaction': mainReaction,
    'offeredReactions': offeredReactions,
    'allowAnyEmoji': allowAnyEmoji,
    'desaturatedPanel': desaturatedPanel,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReactionsSettings &&
          other.mainReaction == mainReaction &&
          listEquals(other.offeredReactions, offeredReactions) &&
          other.allowAnyEmoji == allowAnyEmoji &&
          other.desaturatedPanel == desaturatedPanel;

  @override
  int get hashCode => Object.hash(
    mainReaction,
    Object.hashAll(offeredReactions),
    allowAnyEmoji,
    desaturatedPanel,
  );
}

final class ReactionsSettingsPersistenceCodec
    extends PluginDataPersistenceCodec<ReactionsSettings> {
  const ReactionsSettingsPersistenceCodec();

  @override
  PluginDataKey<ReactionsSettings> get key => reactionsSettingsDataKey;

  @override
  ReactionsSettings? decode(Object? value) =>
      ReactionsSettings.fromStored(value);

  @override
  Object encode(ReactionsSettings value) => value.toStored();

  @override
  ReactionsSettings? decodeLegacy(Map<String, dynamic> json) {
    if (!json.containsKey('mainReaction') &&
        !json.containsKey('offeredReactions') &&
        !json.containsKey('allowAnyEmoji') &&
        !json.containsKey('desaturatedReactionPanel')) {
      return null;
    }
    return ReactionsSettings(
      mainReaction: jsonText(json['mainReaction']),
      offeredReactions: _storedReactionList(json['offeredReactions']),
      allowAnyEmoji: json['allowAnyEmoji'] == true,
      desaturatedPanel: json['desaturatedReactionPanel'] == true,
    );
  }
}

const reactionsSettingsPersistenceCodec = ReactionsSettingsPersistenceCodec();

extension SiteConfigReactionsSettings on SiteConfig {
  ReactionsSettings get reactionsSettings =>
      plugins.get(reactionsSettingsDataKey) ?? const ReactionsSettings();

  String? get mainReaction => reactionsSettings.mainReaction;

  List<String> get offeredReactions => reactionsSettings.offeredReactions;

  bool get allowAnyEmoji => reactionsSettings.allowAnyEmoji;

  bool get desaturatedReactionPanel => reactionsSettings.desaturatedPanel;
}

List<String> _offeredReactions(Object? raw, String? mainReaction) {
  final parts = switch (raw) {
    final String text => text.split('|'),
    final List<dynamic> values => values.map(jsonText).whereType<String>(),
    _ => const <String>[],
  };
  final offered = [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trim(),
  ];
  if (mainReaction != null && !offered.contains(mainReaction)) {
    offered.insert(0, mainReaction);
  }
  return List.unmodifiable(offered);
}

List<String> _storedReactionList(Object? raw) =>
    List.unmodifiable(jsonArray(raw).map(jsonText).whereType<String>());

Map<String, Object?>? _objectFields(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}
