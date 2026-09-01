/// A monotonically increasing version of the canonical composer source.
final class ComposerRevision implements Comparable<ComposerRevision> {
  const ComposerRevision(this.value) : assert(value >= 0);

  final int value;

  ComposerRevision get next => ComposerRevision(value + 1);

  @override
  int compareTo(ComposerRevision other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) {
    return other is ComposerRevision && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ComposerRevision($value)';
}

/// A half-open range of UTF-16 code-unit offsets in the canonical source.
///
/// The constructor deliberately accepts unchecked offsets so parsers can hand
/// candidates to the projection resolver without throwing. Boundaries that
/// mutate or expose a document must validate the range with [isValidFor].
final class ComposerSourceRange {
  const ComposerSourceRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
  bool get isCollapsed => start == end;
  bool get isWellFormed => start >= 0 && end >= start;

  bool isValidFor(String source) => isWellFormed && end <= source.length;

  bool containsOffset(int offset) => start <= offset && offset < end;

  bool strictlyContainsOffset(int offset) => start < offset && offset < end;

  bool overlaps(ComposerSourceRange other) {
    return start < other.end && other.start < end;
  }

  bool strictlyContains(ComposerSourceRange other) {
    return start <= other.start &&
        end >= other.end &&
        (start != other.start || end != other.end);
  }

  String capture(String source) {
    if (!isValidFor(source)) {
      throw RangeError('Range $this is outside a source of ${source.length}');
    }
    return source.substring(start, end);
  }

  @override
  bool operator ==(Object other) {
    return other is ComposerSourceRange &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ComposerSourceRange($start, $end)';
}
