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
    this.sectionDepths = const [],
  });

  final String id;
  final String name;
  final String url;
  final List<String> sections;
  final List<int> sectionDepths;

  Iterable<ComponentReferenceSection> get outline sync* {
    for (var index = 0; index < sections.length; index++) {
      yield ComponentReferenceSection(
        label: sections[index],
        depth: index < sectionDepths.length ? sectionDepths[index] : 0,
      );
    }
  }

  /// The sections rendered by the native styleguide.
  ///
  /// Installation is repository-owned, and API reference blocks are omitted
  /// together with their nested entries.
  Iterable<ComponentReferenceSection> get documentOutline sync* {
    var insideApiReference = false;
    for (final section in outline) {
      if (section.label == 'Installation') continue;
      if (section.depth == 0) {
        insideApiReference = section.label == 'API Reference';
      }
      if (!insideApiReference) yield section;
    }
  }

  bool matches(String query) {
    final documentedSections = documentOutline
        .map((section) => section.label)
        .join(' ');
    final haystack = '$name $id $documentedSections'.toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(haystack.contains);
  }
}

@immutable
class ComponentReferenceSection {
  const ComponentReferenceSection({required this.label, this.depth = 0});

  final String label;
  final int depth;
}
