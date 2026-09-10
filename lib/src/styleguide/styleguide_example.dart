import 'package:flutter/widgets.dart';

const omittedComponentDocumentationSections = {
  'Installation',
  'Usage',
  'Composition',
  'API Reference',
  'Accessibility',
};

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
    this.topLevel = false,
  });

  final String title;
  final String description;
  final String code;
  final WidgetBuilder builder;
  final List<String> states;

  /// Renders this example before the component's documented sections.
  final bool topLevel;
}

@immutable
class ComponentExamples {
  const ComponentExamples({
    required this.status,
    required this.examples,
    this.description = '',
    this.notes = '',
    this.omittedSections = const {},
  });

  final ComponentStatus status;
  final List<StyleguideExample> examples;

  /// A short introduction for the documentation page.
  final String description;
  final String notes;
  final Set<String> omittedSections;

  /// Applies component-specific omissions without changing the frozen source
  /// catalogue used for scope and search.
  Iterable<ComponentReferenceSection> documentOutlineFor(
    ComponentReference reference,
  ) sync* {
    var insideOmittedBlock = false;
    for (final section in reference.documentOutline) {
      if (section.depth == 0) {
        insideOmittedBlock = omittedSections.contains(section.label);
      }
      if (!insideOmittedBlock) yield section;
    }
  }
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
  /// Setup, usage, composition, API reference, and accessibility blocks are
  /// omitted together with their nested entries. Those sections depend on
  /// explanatory prose that the native styleguide does not render.
  Iterable<ComponentReferenceSection> get documentOutline sync* {
    var insideOmittedBlock = false;
    for (final section in outline) {
      if (section.depth == 0) {
        insideOmittedBlock = omittedComponentDocumentationSections.contains(
          section.label,
        );
      }
      if (!insideOmittedBlock) yield section;
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
