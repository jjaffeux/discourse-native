import 'package:flutter/foundation.dart';

import '../theme/d_icon.dart';

/// Separate from the wire key so serializer changes do not invalidate saved tabs.
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

/// Null at the codec means absent; this payload may contain an empty list.
@immutable
final class TopicRecommendationSourcePayload {
  const TopicRecommendationSourcePayload({
    required this.definition,
    required this.topicRows,
  });

  final TopicRecommendationSourceDefinition definition;
  final List<Map<String, dynamic>> topicRows;
}

abstract base class TopicRecommendationSourceCodec {
  const TopicRecommendationSourceCodec();

  TopicRecommendationSourceDefinition get definition;

  /// Source-owned aliases written before the stable id existed.
  Set<String> get legacyStoredIds => const {};

  /// Returns this source's shared topic rows, or null when its wire payload is
  /// absent. Implementations must return an immutable list.
  List<Map<String, dynamic>>? decodeTopicRows(Map<String, dynamic> json);
}

/// This is intentionally not part of `PluginDataDecoder`: recommendation
/// lists are sibling resources on a topic response, not plugin data attached
/// to the core topic record.
abstract interface class TopicRecommendationSourceDecoder {
  List<TopicRecommendationSourceDefinition> get topicRecommendationSources;

  List<TopicRecommendationSourcePayload> readTopicRecommendationSources(
    Map<String, dynamic> json,
  );
}

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

/// This is separate from payload decoding because the preference store needs
/// no authority to read topic response fields.
abstract interface class TopicRecommendationSourceMigrationRegistry {
  TopicRecommendationSourceId? migrateLegacyStoredId(String storedId);
}

final class EmptyTopicRecommendationSourceMigrationRegistry
    implements TopicRecommendationSourceMigrationRegistry {
  const EmptyTopicRecommendationSourceMigrationRegistry();

  @override
  TopicRecommendationSourceId? migrateLegacyStoredId(String storedId) => null;
}

const coreSuggestedTopicRecommendationSourceId = TopicRecommendationSourceId(
  'core/suggested',
);

const coreSuggestedTopicRecommendationLegacyStoredId = 'suggested';

const coreSuggestedTopicRecommendationSource =
    TopicRecommendationSourceDefinition(
      id: coreSuggestedTopicRecommendationSourceId,
      label: 'Suggested',
    );
