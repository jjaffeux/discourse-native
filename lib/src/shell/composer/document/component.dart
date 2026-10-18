import 'source.dart';

enum ComposerComponentLayout { inline, block }

/// A stable, namespaced identifier used to resolve component conflicts.
final class ComposerComponentKind implements Comparable<ComposerComponentKind> {
  ComposerComponentKind(this.value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
  }

  final String value;

  @override
  int compareTo(ComposerComponentKind other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) {
    return other is ComposerComponentKind && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class ComposerParseInput {
  const ComposerParseInput({required this.source, required this.revision});

  final String source;
  final ComposerRevision revision;
}

typedef ComposerComponentParser<T extends Object> =
    Iterable<ComposerComponentCandidate<T>> Function(ComposerParseInput input);

/// The complete extension point for recognizing one component kind.
///
/// Rendering and editing actions intentionally do not belong to this type.
final class ComposerComponentDefinition<T extends Object> {
  const ComposerComponentDefinition({
    required this.kind,
    required this.layout,
    required this.precedence,
    required this.parse,
  });

  final ComposerComponentKind kind;
  final ComposerComponentLayout layout;
  final int precedence;
  final ComposerComponentParser<T> parse;
}

/// A parser-owned typed value and its proposed source range.
///
/// The candidate cannot supply its source text. The resolver captures that
/// text from the canonical parse input after validating [range].
final class ComposerComponentCandidate<T extends Object> {
  const ComposerComponentCandidate({required this.range, required this.value});

  final ComposerSourceRange range;
  final T value;
}

/// An exact reference to a component in one source revision.
final class ComposerComponentToken {
  const ComposerComponentToken({
    required this.revision,
    required this.kind,
    required this.range,
    required this.source,
  });

  final ComposerRevision revision;
  final ComposerComponentKind kind;
  final ComposerSourceRange range;
  final String source;

  @override
  bool operator ==(Object other) {
    return other is ComposerComponentToken &&
        other.revision == revision &&
        other.kind == kind &&
        other.range == range &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(revision, kind, range, source);

  @override
  String toString() =>
      '${kind.value}@${range.start}:${range.end}#${revision.value}';
}

/// A validated, source-capturing component in the resolved projection.
final class ComposerComponentMatch<T extends Object> {
  const ComposerComponentMatch({
    required this.revision,
    required this.kind,
    required this.layout,
    required this.precedence,
    required this.range,
    required this.source,
    required this.value,
  });

  final ComposerRevision revision;
  final ComposerComponentKind kind;
  final ComposerComponentLayout layout;
  final int precedence;
  final ComposerSourceRange range;
  final String source;
  final T value;

  ComposerComponentToken get token => ComposerComponentToken(
    revision: revision,
    kind: kind,
    range: range,
    source: source,
  );
}
