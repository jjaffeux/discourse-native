import 'package:flutter/widgets.dart';

enum ComponentStatus { planned, baseline, implemented }

/// A runnable example and the source a caller can copy to reproduce it.
@immutable
class StyleguideExample {
  const StyleguideExample({
    required this.title,
    required this.description,
    required this.code,
    required this.builder,
    this.states = const [],
  });

  final String title;
  final String description;
  final String code;
  final WidgetBuilder builder;
  final List<String> states;
}

@immutable
class ComponentExamples {
  const ComponentExamples({
    required this.status,
    required this.examples,
    this.description = '',
    this.notes = '',
  });

  final ComponentStatus status;
  final List<StyleguideExample> examples;

  /// A short introduction for the documentation page.
  final String description;
  final String notes;
}

@immutable
class ComponentReference {
  const ComponentReference({
    required this.id,
    required this.name,
    required this.url,
    required this.sections,
  });

  final String id;
  final String name;
  final String url;
  final List<String> sections;

  bool matches(String query) {
    final haystack = '$name $id ${sections.join(' ')}'.toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(haystack.contains);
  }
}
