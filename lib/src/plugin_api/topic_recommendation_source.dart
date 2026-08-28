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

/// The wire and presentation contract for one recommendation source.
@immutable
final class TopicRecommendationSourceDefinition {
  const TopicRecommendationSourceDefinition({
    required this.id,
    required this.payloadKey,
    required this.label,
    this.icon,
  });

  final TopicRecommendationSourceId id;
  final String payloadKey;
  final String label;
  final DIconData? icon;

  @override
  bool operator ==(Object other) =>
      other is TopicRecommendationSourceDefinition &&
      other.id == id &&
      other.payloadKey == payloadKey &&
      other.label == label &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, payloadKey, label, icon);
}

const coreSuggestedTopicRecommendationSourceId = TopicRecommendationSourceId(
  'core/suggested',
);

/// Core's one built-in source. Optional sources are supplied by plugins.
const coreSuggestedTopicRecommendationSource =
    TopicRecommendationSourceDefinition(
      id: coreSuggestedTopicRecommendationSourceId,
      payloadKey: 'suggested_topics',
      label: 'Suggested',
    );
