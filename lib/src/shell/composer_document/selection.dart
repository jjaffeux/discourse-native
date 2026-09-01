import 'component.dart';
import 'projection.dart';

sealed class ComposerSelection {
  const ComposerSelection();
}

final class ComposerCaretSelection extends ComposerSelection {
  const ComposerCaretSelection(this.offset);

  final int offset;

  @override
  bool operator ==(Object other) {
    return other is ComposerCaretSelection && other.offset == offset;
  }

  @override
  int get hashCode => offset.hashCode;

  @override
  String toString() => 'ComposerCaretSelection($offset)';
}

final class ComposerRangeSelection extends ComposerSelection {
  factory ComposerRangeSelection({required int anchor, required int focus}) {
    if (anchor == focus) {
      throw ArgumentError('A range selection must not be collapsed');
    }
    return ComposerRangeSelection._(anchor: anchor, focus: focus);
  }

  const ComposerRangeSelection._({required this.anchor, required this.focus});

  final int anchor;
  final int focus;

  int get start => anchor < focus ? anchor : focus;
  int get end => anchor < focus ? focus : anchor;
  bool get isReversed => anchor > focus;

  @override
  bool operator ==(Object other) {
    return other is ComposerRangeSelection &&
        other.anchor == anchor &&
        other.focus == focus;
  }

  @override
  int get hashCode => Object.hash(anchor, focus);

  @override
  String toString() => 'ComposerRangeSelection($anchor, $focus)';
}

final class ComposerComponentSelection extends ComposerSelection {
  const ComposerComponentSelection(this.component);

  final ComposerComponentToken component;

  @override
  bool operator ==(Object other) {
    return other is ComposerComponentSelection && other.component == component;
  }

  @override
  int get hashCode => component.hashCode;

  @override
  String toString() => 'ComposerComponentSelection($component)';
}

enum ComposerSelectionBias { backward, nearest, forward }

/// Enforces the semantic-selection invariants of a resolved projection.
final class ComposerSelectionNormalizer {
  const ComposerSelectionNormalizer();

  ComposerSelection normalize(
    ComposerSelection selection,
    ComposerProjection projection, {
    ComposerSelectionBias bias = ComposerSelectionBias.nearest,
  }) {
    return switch (selection) {
      ComposerCaretSelection() => _normalizeCaret(
        selection.offset,
        projection,
        bias,
      ),
      ComposerRangeSelection() => _normalizeRange(selection, projection),
      ComposerComponentSelection() => _normalizeComponent(
        selection,
        projection,
      ),
    };
  }

  ComposerSelection _normalizeCaret(
    int offset,
    ComposerProjection projection,
    ComposerSelectionBias bias,
  ) {
    final clamped = offset.clamp(0, projection.source.length);
    final component = projection.componentContainingOffset(clamped);
    if (component == null) return ComposerCaretSelection(clamped);
    final resolved = switch (bias) {
      ComposerSelectionBias.backward => component.range.start,
      ComposerSelectionBias.forward => component.range.end,
      ComposerSelectionBias.nearest =>
        clamped - component.range.start < component.range.end - clamped
            ? component.range.start
            : component.range.end,
    };
    return ComposerCaretSelection(resolved);
  }

  ComposerSelection _normalizeRange(
    ComposerRangeSelection selection,
    ComposerProjection projection,
  ) {
    var lower = selection.start.clamp(0, projection.source.length);
    var upper = selection.end.clamp(0, projection.source.length);
    if (lower == upper) {
      return _normalizeCaret(lower, projection, ComposerSelectionBias.nearest);
    }
    for (final component in projection.components) {
      if (lower < component.range.end && upper > component.range.start) {
        if (component.range.start < lower) lower = component.range.start;
        if (component.range.end > upper) upper = component.range.end;
      }
    }
    return selection.isReversed
        ? ComposerRangeSelection(anchor: upper, focus: lower)
        : ComposerRangeSelection(anchor: lower, focus: upper);
  }

  ComposerSelection _normalizeComponent(
    ComposerComponentSelection selection,
    ComposerProjection projection,
  ) {
    final match = projection.componentForToken(selection.component);
    if (match != null) return ComposerComponentSelection(match.token);
    return _normalizeCaret(
      selection.component.range.start,
      projection,
      ComposerSelectionBias.nearest,
    );
  }
}
