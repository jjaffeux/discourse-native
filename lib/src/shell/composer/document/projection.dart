import 'component.dart';
import 'source.dart';

enum ComposerProjectionIssueCode {
  invalidRange,
  exactRangeConflict,
  partialOverlap,
  containedCandidate,
}

/// A candidate that was not admitted to the projection and why.
final class ComposerProjectionIssue {
  const ComposerProjectionIssue({
    required this.code,
    required this.kind,
    required this.range,
    this.conflictingKind,
    this.conflictingRange,
  });

  final ComposerProjectionIssueCode code;
  final ComposerComponentKind kind;
  final ComposerSourceRange range;
  final ComposerComponentKind? conflictingKind;
  final ComposerSourceRange? conflictingRange;
}

sealed class ComposerProjectionSegment {
  const ComposerProjectionSegment({required this.range, required this.source});

  final ComposerSourceRange range;
  final String source;
}

final class ComposerTextSegment extends ComposerProjectionSegment {
  const ComposerTextSegment({required super.range, required super.source});
}

final class ComposerComponentSegment extends ComposerProjectionSegment {
  ComposerComponentSegment(this.match)
    : super(range: match.range, source: match.source);

  final ComposerComponentMatch<Object> match;
}

/// A lossless partition of source text into plain text and atomic components.
final class ComposerProjection {
  ComposerProjection._({
    required this.source,
    required this.revision,
    required List<ComposerComponentMatch<Object>> components,
    required List<ComposerProjectionSegment> segments,
    required List<ComposerProjectionIssue> issues,
  }) : components = List.unmodifiable(components),
       segments = List.unmodifiable(segments),
       issues = List.unmodifiable(issues);

  final String source;
  final ComposerRevision revision;
  final List<ComposerComponentMatch<Object>> components;
  final List<ComposerProjectionSegment> segments;
  final List<ComposerProjectionIssue> issues;

  String get reconstructedSource =>
      segments.map((segment) => segment.source).join();

  ComposerComponentMatch<Object>? componentStartingAt(int offset) {
    for (final component in components) {
      if (component.range.start == offset) return component;
      if (component.range.start > offset) return null;
    }
    return null;
  }

  ComposerComponentMatch<Object>? componentEndingAt(int offset) {
    for (final component in components.reversed) {
      if (component.range.end == offset) return component;
      if (component.range.end < offset) return null;
    }
    return null;
  }

  ComposerComponentMatch<Object>? componentContainingOffset(int offset) {
    for (final component in components) {
      if (component.range.strictlyContainsOffset(offset)) return component;
      if (component.range.start >= offset) return null;
    }
    return null;
  }

  ComposerComponentMatch<Object>? componentForToken(
    ComposerComponentToken token,
  ) {
    for (final component in components) {
      if (component.token == token) return component;
    }
    return null;
  }
}

/// Resolves parser candidates into a deterministic, non-overlapping graph.
final class ComposerProjectionResolver {
  const ComposerProjectionResolver();

  ComposerProjection resolve({
    required ComposerParseInput input,
    required Iterable<ComposerComponentDefinition<Object>> definitions,
  }) {
    final issues = <ComposerProjectionIssue>[];
    final candidates = <_ResolvedCandidate>[];
    var ordinal = 0;
    final orderedDefinitions = definitions.toList()
      ..sort((left, right) {
        final kindOrder = left.kind.compareTo(right.kind);
        if (kindOrder != 0) return kindOrder;
        return right.precedence.compareTo(left.precedence);
      });

    for (final definition in orderedDefinitions) {
      for (final candidate in definition.parse(input)) {
        final range = candidate.range;
        if (!range.isValidFor(input.source) || range.isCollapsed) {
          issues.add(
            ComposerProjectionIssue(
              code: ComposerProjectionIssueCode.invalidRange,
              kind: definition.kind,
              range: range,
            ),
          );
          continue;
        }
        candidates.add(
          _ResolvedCandidate(
            ordinal: ordinal++,
            match: ComposerComponentMatch<Object>(
              revision: input.revision,
              kind: definition.kind,
              layout: definition.layout,
              precedence: definition.precedence,
              range: range,
              source: range.capture(input.source),
              value: candidate.value,
            ),
          ),
        );
      }
    }

    final exactWinners = <_ResolvedCandidate>[];
    final byRange = <ComposerSourceRange, List<_ResolvedCandidate>>{};
    for (final candidate in candidates) {
      byRange.putIfAbsent(candidate.match.range, () => []).add(candidate);
    }
    final exactGroups = byRange.values.toList()
      ..sort((left, right) => _compareDocumentOrder(left.first, right.first));
    for (final group in exactGroups) {
      group.sort(_compareConflictPriority);
      final winner = group.first;
      exactWinners.add(winner);
      for (final loser in group.skip(1)) {
        issues.add(
          ComposerProjectionIssue(
            code: ComposerProjectionIssueCode.exactRangeConflict,
            kind: loser.match.kind,
            range: loser.match.range,
            conflictingKind: winner.match.kind,
            conflictingRange: winner.match.range,
          ),
        );
      }
    }

    exactWinners.sort(_compareDocumentOrder);
    final partials = <_ResolvedCandidate>{};
    for (var leftIndex = 0; leftIndex < exactWinners.length; leftIndex++) {
      final left = exactWinners[leftIndex];
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < exactWinners.length;
        rightIndex++
      ) {
        final right = exactWinners[rightIndex];
        if (right.match.range.start >= left.match.range.end) break;
        if (_partiallyOverlap(left.match.range, right.match.range)) {
          partials.add(left);
          partials.add(right);
          issues
            ..add(
              ComposerProjectionIssue(
                code: ComposerProjectionIssueCode.partialOverlap,
                kind: left.match.kind,
                range: left.match.range,
                conflictingKind: right.match.kind,
                conflictingRange: right.match.range,
              ),
            )
            ..add(
              ComposerProjectionIssue(
                code: ComposerProjectionIssueCode.partialOverlap,
                kind: right.match.kind,
                range: right.match.range,
                conflictingKind: left.match.kind,
                conflictingRange: left.match.range,
              ),
            );
        }
      }
    }

    final admitted = <ComposerComponentMatch<Object>>[];
    for (final candidate in exactWinners) {
      if (partials.contains(candidate)) continue;
      ComposerComponentMatch<Object>? container;
      for (final accepted in admitted) {
        if (accepted.range.strictlyContains(candidate.match.range)) {
          container = accepted;
          break;
        }
      }
      if (container != null) {
        issues.add(
          ComposerProjectionIssue(
            code: ComposerProjectionIssueCode.containedCandidate,
            kind: candidate.match.kind,
            range: candidate.match.range,
            conflictingKind: container.kind,
            conflictingRange: container.range,
          ),
        );
        continue;
      }
      admitted.add(candidate.match);
    }

    final segments = <ComposerProjectionSegment>[];
    var sourceOffset = 0;
    for (final component in admitted) {
      if (sourceOffset < component.range.start) {
        final range = ComposerSourceRange(sourceOffset, component.range.start);
        segments.add(
          ComposerTextSegment(
            range: range,
            source: range.capture(input.source),
          ),
        );
      }
      segments.add(ComposerComponentSegment(component));
      sourceOffset = component.range.end;
    }
    if (sourceOffset < input.source.length) {
      final range = ComposerSourceRange(sourceOffset, input.source.length);
      segments.add(
        ComposerTextSegment(range: range, source: range.capture(input.source)),
      );
    }

    final projection = ComposerProjection._(
      source: input.source,
      revision: input.revision,
      components: admitted,
      segments: segments,
      issues: issues,
    );
    if (projection.reconstructedSource != input.source) {
      throw StateError('Projection did not reconstruct its canonical source');
    }
    return projection;
  }
}

final class _ResolvedCandidate {
  const _ResolvedCandidate({required this.ordinal, required this.match});

  final int ordinal;
  final ComposerComponentMatch<Object> match;
}

int _compareConflictPriority(
  _ResolvedCandidate left,
  _ResolvedCandidate right,
) {
  final precedence = right.match.precedence.compareTo(left.match.precedence);
  if (precedence != 0) return precedence;
  final kind = left.match.kind.compareTo(right.match.kind);
  if (kind != 0) return kind;
  return left.ordinal.compareTo(right.ordinal);
}

int _compareDocumentOrder(_ResolvedCandidate left, _ResolvedCandidate right) {
  final start = left.match.range.start.compareTo(right.match.range.start);
  if (start != 0) return start;
  final end = right.match.range.end.compareTo(left.match.range.end);
  if (end != 0) return end;
  return _compareConflictPriority(left, right);
}

bool _partiallyOverlap(ComposerSourceRange left, ComposerSourceRange right) {
  if (!left.overlaps(right)) return false;
  return !left.strictlyContains(right) && !right.strictlyContains(left);
}
