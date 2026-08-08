import 'package:flutter/foundation.dart';

import 'json.dart';

/// One prefix, delimiter or special value advertised for a topic filter.
@immutable
class TopicFilterModifier {
  const TopicFilterModifier({required this.name, this.description});

  factory TopicFilterModifier.fromJson(Map<String, dynamic> json) =>
      TopicFilterModifier(
        name: jsonString(json['name']),
        description: jsonText(json['description']),
      );

  final String name;
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is TopicFilterModifier &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(name, description);
}

/// A query operator returned in `topic_list.filter_option_info`.
///
/// The server is the source of truth for this list. Plugins can add operators,
/// and older sites can omit fields newer clients understand, so every nested
/// value is optional and malformed entries are skipped rather than making the
/// whole topic list unreadable.
@immutable
class TopicFilterOption {
  const TopicFilterOption({
    required this.name,
    this.alias,
    this.description,
    this.priority = 0,
    this.type,
    this.delimiters = const [],
    this.prefixes = const [],
    this.extraEntries = const [],
  });

  static TopicFilterOption? parse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final name = jsonText(value['name']);
    if (name == null) return null;

    List<TopicFilterModifier> modifiers(Object? source) => List.unmodifiable([
      for (final item in jsonObjects(source))
        if (jsonText(item['name']) != null) TopicFilterModifier.fromJson(item),
    ]);

    return TopicFilterOption(
      name: name,
      alias: jsonText(value['alias']),
      description: jsonText(value['description']),
      priority: jsonInt(value['priority']),
      type: jsonText(value['type']),
      delimiters: modifiers(value['delimiters']),
      prefixes: modifiers(value['prefixes']),
      extraEntries: modifiers(value['extra_entries']),
    );
  }

  final String name;
  final String? alias;
  final String? description;
  final int priority;
  final String? type;
  final List<TopicFilterModifier> delimiters;
  final List<TopicFilterModifier> prefixes;
  final List<TopicFilterModifier> extraEntries;

  @override
  bool operator ==(Object other) =>
      other is TopicFilterOption &&
      other.name == name &&
      other.alias == alias &&
      other.description == description &&
      other.priority == priority &&
      other.type == type &&
      listEquals(other.delimiters, delimiters) &&
      listEquals(other.prefixes, prefixes) &&
      listEquals(other.extraEntries, extraEntries);

  @override
  int get hashCode => Object.hash(
    name,
    alias,
    description,
    priority,
    type,
    Object.hashAll(delimiters),
    Object.hashAll(prefixes),
    Object.hashAll(extraEntries),
  );
}

/// A remotely looked-up value used to complete a typed filter.
@immutable
class TopicFilterLookupValue {
  const TopicFilterLookupValue({required this.name, this.description});

  final String name;
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is TopicFilterLookupValue &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(name, description);
}
