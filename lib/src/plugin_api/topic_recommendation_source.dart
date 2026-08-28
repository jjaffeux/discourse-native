import 'package:flutter/foundation.dart';

import '../theme/d_icon.dart';

/// Stable, namespaced identity for one source in a topic's recommendations.
///
/// Installed plugin contributions are validated as `plugin-name/source-name`
/// at the composition boundary. Keeping the identity separate from the wire
/// key lets a plugin evolve its serializer without invalidating a reader's
/// saved tab choice.
@immutable
final class TopicRecommendationSourceId {
  const TopicRecommendationSourceId(this.value);

  final String value;

  static final RegExp _namespacedPattern = RegExp(
    r'^[a-z0-9]+(?:[._-][a-z0-9]+)*/[a-z0-9]+(?:[._-][a-z0-9]+)*$',
  );

  bool get isNamespaced => _namespacedPattern.hasMatch(value);

  String? get namespace => isNamespaced ? value.split('/').first : null;

  @override
  bool operator ==(Object other) =>
      other is TopicRecommendationSourceId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The presentation contract for one recommendation source.
///
/// Wire decoding deliberately lives on [TopicRecommendationSourceCodec]. A
/// source can therefore evolve or normalize its serializer payload without
/// teaching the core topic model which field it owns.
@immutable
final class TopicRecommendationSourceDefinition {
  const TopicRecommendationSourceDefinition({
    required this.id,
    required this.label,
    this.icon,
  });

  final TopicRecommendationSourceId id;
  final String label;
  final DIconData? icon;

  @override
  bool operator ==(Object other) =>
      other is TopicRecommendationSourceDefinition &&
      other.id == id &&
      other.label == label &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, label, icon);
}

/// One source's decoded view of a topic-detail payload.
///
/// The rows keep the shared recommendation-topic wire shape opaque until the
/// core topic model constructs its ordinary [Topic] values. Null from a codec
/// means the source's field was absent; an empty list means the source was
/// present and had no recommendations.
@immutable
final class TopicRecommendationSourcePayload {
  const TopicRecommendationSourcePayload({
    required this.definition,
    required this.topicRows,
  });

  final TopicRecommendationSourceDefinition definition;
  final List<Map<String, dynamic>> topicRows;
}

/// Owns the serializer decoding for one optional recommendation source.
///
/// Implementations live beside their source. Core never switches on a plugin
/// payload key and the generic plugin-record decoder never catalogs sources.
abstract base class TopicRecommendationSourceCodec {
  const TopicRecommendationSourceCodec();

  TopicRecommendationSourceDefinition get definition;

  /// Values written by older releases before this source had its stable id.
  ///
  /// Persistence composes these aliases at the registry boundary. They are
  /// intentionally source-owned so core only migrates its own historic value.
  Set<String> get legacyStoredIds => const {};

  /// Returns this source's shared topic rows, or null when its wire payload is
  /// absent. Implementations must return an immutable list.
  List<Map<String, dynamic>>? decodeTopicRows(Map<String, dynamic> json);
}

/// Separate catalog and decoder for installed recommendation-source codecs.
///
/// This is intentionally not part of `PluginDataDecoder`: recommendation
/// lists are sibling resources on a topic response, not plugin data attached
/// to the core topic record.
abstract interface class TopicRecommendationSourceDecoder {
  List<TopicRecommendationSourceDefinition> get topicRecommendationSources;

  List<TopicRecommendationSourcePayload> readTopicRecommendationSources(
    Map<String, dynamic> json,
  );
}

/// The recommendation decoder used by a core-only composition.
final class EmptyTopicRecommendationSourceDecoder
    implements TopicRecommendationSourceDecoder {
  const EmptyTopicRecommendationSourceDecoder();

  @override
  List<TopicRecommendationSourceDefinition> get topicRecommendationSources =>
      const [];

  @override
  List<TopicRecommendationSourcePayload> readTopicRecommendationSources(
    Map<String, dynamic> json,
  ) => const [];
}

/// Resolves pre-stable preference values claimed by installed source codecs.
///
/// This is separate from payload decoding because the preference store needs
/// no authority to read topic response fields. Stable namespaced ids and
/// core's own legacy values remain core concerns.
abstract interface class TopicRecommendationSourceMigrationRegistry {
  TopicRecommendationSourceId? migrateLegacyStoredId(String storedId);
}

/// The migration registry used by a core-only composition.
final class EmptyTopicRecommendationSourceMigrationRegistry
    implements TopicRecommendationSourceMigrationRegistry {
  const EmptyTopicRecommendationSourceMigrationRegistry();

  @override
  TopicRecommendationSourceId? migrateLegacyStoredId(String storedId) => null;
}

const coreSuggestedTopicRecommendationSourceId = TopicRecommendationSourceId(
  'core/suggested',
);

/// The value written before core recommendations received a stable source id.
const coreSuggestedTopicRecommendationLegacyStoredId = 'suggested';

/// Core's one built-in source. Optional sources are supplied by plugins.
const coreSuggestedTopicRecommendationSource =
    TopicRecommendationSourceDefinition(
      id: coreSuggestedTopicRecommendationSourceId,
      label: 'Suggested',
    );
