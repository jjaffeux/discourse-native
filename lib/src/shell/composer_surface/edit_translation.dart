import 'package:flutter/services.dart';

import '../composer_document/document.dart';
import '../composer_document/selection.dart';
import '../composer_document/source.dart';
import 'projection.dart';

/// Why a native projected-buffer update could not become a canonical edit.
enum ComposerSurfaceEditRejectionReason {
  snapshotProjectionMismatch,
  planSnapshotMismatch,
  projectedBaseTextMismatch,
  invalidOldSelection,
  invalidNewSelection,
  invalidOldComposingRange,
  invalidNewComposingRange,
  replacementContainsObjectReplacementCharacter,
  changedRangeIntersectsAtom,
  activeComposition,
  compositionTouchesAtom,
}

sealed class ComposerSurfaceEditTranslationResult {
  const ComposerSurfaceEditTranslationResult();
}

/// One ordinary-text replacement translated to an exact source transaction.
final class ComposerSurfaceTextEditTranslation
    extends ComposerSurfaceEditTranslationResult {
  const ComposerSurfaceTextEditTranslation({
    required this.transaction,
    required this.changedSurfaceRange,
    required this.replacement,
  });

  final ComposerTransaction transaction;
  final ComposerSurfaceRange changedSurfaceRange;
  final String replacement;
}

/// A native update that changed selection but did not change projected text.
///
/// This is intentionally not represented by an empty transaction. The owner
/// can apply [after] through its semantic selection path without adding an
/// undo entry or advancing the source revision.
final class ComposerSurfaceSelectionTranslation
    extends ComposerSurfaceEditTranslationResult {
  const ComposerSurfaceSelectionTranslation({
    required this.before,
    required this.after,
  });

  final ComposerSelection before;
  final ComposerSelection after;

  bool get changed => before != after;
}

final class ComposerSurfaceEditRejected
    extends ComposerSurfaceEditTranslationResult {
  const ComposerSurfaceEditRejected({
    required this.reason,
    this.changedSurfaceRange,
  });

  final ComposerSurfaceEditRejectionReason reason;
  final ComposerSurfaceRange? changedSurfaceRange;
}

/// Translates one native edit of the raw-free surface into canonical source.
///
/// Both Dart string indices and Flutter text offsets are UTF-16 code-unit
/// offsets, so no character-count conversion is performed. Component
/// placeholders remain immutable: component selection and deletion are owned
/// by the semantic interaction reducer instead of this translator.
final class ComposerSurfaceEditTranslator {
  const ComposerSurfaceEditTranslator();

  ComposerSurfaceEditTranslationResult translate({
    required ComposerDocumentSnapshot snapshot,
    required ComposerSurfaceProjectionPlan plan,
    required TextEditingValue oldValue,
    required TextEditingValue newValue,
  }) {
    if (!_snapshotIsCoherent(snapshot)) {
      return const ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason.snapshotProjectionMismatch,
      );
    }
    if (!_planMatchesSnapshot(plan, snapshot)) {
      return const ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason.planSnapshotMismatch,
      );
    }
    if (oldValue.text != plan.snapshot.projectedText) {
      return const ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason.projectedBaseTextMismatch,
      );
    }

    if (!_selectionIsValidFor(oldValue.selection, oldValue.text.length)) {
      return const ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason.invalidOldSelection,
      );
    }
    if (!_selectionIsValidFor(newValue.selection, newValue.text.length)) {
      return const ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason.invalidNewSelection,
      );
    }
    if (!_composingRangeIsValidFor(oldValue.composing, oldValue.text.length)) {
      return const ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason.invalidOldComposingRange,
      );
    }
    if (!_composingRangeIsValidFor(newValue.composing, newValue.text.length)) {
      return const ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason.invalidNewComposingRange,
      );
    }

    final difference = _SurfaceDifference.betweenValues(oldValue, newValue);
    final changedSurfaceRange = difference.oldRange;
    final changeIntersectsAtom = _rangeIntersectsAtom(
      changedSurfaceRange,
      plan.atoms,
    );
    if (_hasActiveComposition(oldValue.composing) ||
        _hasActiveComposition(newValue.composing)) {
      final touchesAtom =
          changeIntersectsAtom ||
          _rangeIntersectsAtom(_surfaceRange(oldValue.composing), plan.atoms) ||
          _newCompositionTouchesAtom(
            newValue.composing,
            difference,
            plan.atoms,
          );
      return ComposerSurfaceEditRejected(
        reason: touchesAtom
            ? ComposerSurfaceEditRejectionReason.compositionTouchesAtom
            : ComposerSurfaceEditRejectionReason.activeComposition,
        changedSurfaceRange: changedSurfaceRange,
      );
    }

    if (oldValue.text == newValue.text) {
      return ComposerSurfaceSelectionTranslation(
        before: _selectionInUnchangedSource(oldValue.selection, plan),
        after: _selectionInUnchangedSource(newValue.selection, plan),
      );
    }
    if (difference.replacement.contains(
      composerSurfaceObjectReplacementCharacter,
    )) {
      return ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason
            .replacementContainsObjectReplacementCharacter,
        changedSurfaceRange: changedSurfaceRange,
      );
    }
    if (changeIntersectsAtom) {
      final replacesExactOldSelection =
          difference.replacement.isNotEmpty &&
          difference.inferredFromExplicitSelection &&
          _selectionRange(oldValue.selection) == changedSurfaceRange &&
          _rangeFullyCoversIntersectedAtoms(changedSurfaceRange, plan.atoms);
      if (replacesExactOldSelection) {
        return _translationForDifference(
          snapshot: snapshot,
          plan: plan,
          newSelection: newValue.selection,
          difference: difference,
        );
      }
      return ComposerSurfaceEditRejected(
        reason: ComposerSurfaceEditRejectionReason.changedRangeIntersectsAtom,
        changedSurfaceRange: changedSurfaceRange,
      );
    }

    return _translationForDifference(
      snapshot: snapshot,
      plan: plan,
      newSelection: newValue.selection,
      difference: difference,
    );
  }
}

ComposerSurfaceTextEditTranslation _translationForDifference({
  required ComposerDocumentSnapshot snapshot,
  required ComposerSurfaceProjectionPlan plan,
  required TextSelection newSelection,
  required _SurfaceDifference difference,
}) {
  final changedSurfaceRange = difference.oldRange;
  final sourceRange = plan.sourceRangeForSurfaceRange(changedSurfaceRange);
  final selectionAfter = _selectionInEditedSource(
    newSelection,
    difference: difference,
    sourceRange: sourceRange,
    plan: plan,
  );
  return ComposerSurfaceTextEditTranslation(
    changedSurfaceRange: changedSurfaceRange,
    replacement: difference.replacement,
    transaction: ComposerTransaction(
      baseRevision: snapshot.revision,
      edits: [
        ComposerSourceEdit(
          range: sourceRange,
          expectedSource: sourceRange.capture(snapshot.source),
          replacement: difference.replacement,
        ),
      ],
      selectionAfter: selectionAfter,
      debugLabel: 'projected ordinary-text edit',
    ),
  );
}

final class _SurfaceDifference {
  const _SurfaceDifference({
    required this.oldRange,
    required this.replacement,
    required this.inferredFromExplicitSelection,
  });

  factory _SurfaceDifference.betweenValues(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selectedReplacement = _differenceForExplicitSelection(
      oldValue,
      newValue,
    );
    if (selectedReplacement != null) return selectedReplacement;

    final minimal = _SurfaceDifference._minimal(oldValue.text, newValue.text);
    if (minimal.replacement.isNotEmpty ||
        newValue.text.length >= oldValue.text.length) {
      return minimal;
    }

    final intendedRange = _intendedCollapsedDeletionRange(oldValue, newValue);
    if (intendedRange == null ||
        !_deletionProducesText(oldValue.text, newValue.text, intendedRange)) {
      return minimal;
    }
    return _SurfaceDifference(
      oldRange: intendedRange,
      replacement: '',
      inferredFromExplicitSelection: false,
    );
  }

  factory _SurfaceDifference._minimal(String oldText, String newText) {
    final shortestLength = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    var prefixLength = 0;
    while (prefixLength < shortestLength &&
        oldText.codeUnitAt(prefixLength) == newText.codeUnitAt(prefixLength)) {
      prefixLength += 1;
    }

    var suffixLength = 0;
    final oldRemainder = oldText.length - prefixLength;
    final newRemainder = newText.length - prefixLength;
    while (suffixLength < oldRemainder &&
        suffixLength < newRemainder &&
        oldText.codeUnitAt(oldText.length - suffixLength - 1) ==
            newText.codeUnitAt(newText.length - suffixLength - 1)) {
      suffixLength += 1;
    }

    return _SurfaceDifference(
      oldRange: ComposerSurfaceRange(
        prefixLength,
        oldText.length - suffixLength,
      ),
      replacement: newText.substring(
        prefixLength,
        newText.length - suffixLength,
      ),
      inferredFromExplicitSelection: false,
    );
  }

  final ComposerSurfaceRange oldRange;
  final String replacement;
  final bool inferredFromExplicitSelection;

  int get newRangeEnd => oldRange.start + replacement.length;
  int get surfaceLengthDelta => replacement.length - oldRange.length;
}

_SurfaceDifference? _differenceForExplicitSelection(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  if (oldValue.text == newValue.text || oldValue.selection.isCollapsed) {
    return null;
  }
  final selectedRange = _selectionRange(oldValue.selection);
  final replacementLength =
      newValue.text.length - oldValue.text.length + selectedRange.length;
  final replacementEnd = selectedRange.start + replacementLength;
  if (replacementLength < 0 || replacementEnd > newValue.text.length) {
    return null;
  }

  final replacement = newValue.text.substring(
    selectedRange.start,
    replacementEnd,
  );
  if (oldValue.text.replaceRange(
        selectedRange.start,
        selectedRange.end,
        replacement,
      ) !=
      newValue.text) {
    return null;
  }
  return _SurfaceDifference(
    oldRange: selectedRange,
    replacement: replacement,
    inferredFromExplicitSelection: true,
  );
}

ComposerSurfaceRange? _intendedCollapsedDeletionRange(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final deletedLength = oldValue.text.length - newValue.text.length;
  if (deletedLength <= 0) return null;

  final oldSelection = oldValue.selection;
  if (!oldSelection.isCollapsed) return null;

  final newSelection = newValue.selection;
  if (!newSelection.isCollapsed) return null;
  final oldCaret = oldSelection.extentOffset;
  final newCaret = newSelection.extentOffset;
  if (newCaret == oldCaret) {
    return ComposerSurfaceRange(oldCaret, oldCaret + deletedLength);
  }
  if (newCaret == oldCaret - deletedLength) {
    return ComposerSurfaceRange(newCaret, oldCaret);
  }
  return null;
}

ComposerSurfaceRange _selectionRange(TextSelection selection) {
  return ComposerSurfaceRange(selection.start, selection.end);
}

bool _deletionProducesText(
  String oldText,
  String newText,
  ComposerSurfaceRange range,
) {
  return range.isValidForLength(oldText.length) &&
      oldText.replaceRange(range.start, range.end, '') == newText;
}

bool _snapshotIsCoherent(ComposerDocumentSnapshot snapshot) {
  return snapshot.projection.source == snapshot.source &&
      snapshot.projection.revision == snapshot.revision &&
      snapshot.projection.reconstructedSource == snapshot.source;
}

bool _planMatchesSnapshot(
  ComposerSurfaceProjectionPlan actual,
  ComposerDocumentSnapshot snapshot,
) {
  final expected = ComposerSurfaceProjectionPlan.fromProjection(
    snapshot.projection,
  );
  if (actual.sourceLength != expected.sourceLength ||
      actual.snapshot.projectedText != expected.snapshot.projectedText ||
      actual.snapshot.inlineComponentCount !=
          expected.snapshot.inlineComponentCount ||
      actual.snapshot.blockComponentCount !=
          expected.snapshot.blockComponentCount ||
      actual.snapshot.nodes.length != expected.snapshot.nodes.length ||
      actual.atoms.length != expected.atoms.length) {
    return false;
  }
  for (var index = 0; index < actual.snapshot.nodes.length; index += 1) {
    final actualNode = actual.snapshot.nodes[index];
    final expectedNode = expected.snapshot.nodes[index];
    if (actualNode.layout != expectedNode.layout ||
        actualNode.projectedText != expectedNode.projectedText) {
      return false;
    }
  }
  for (var index = 0; index < actual.atoms.length; index += 1) {
    final actualAtom = actual.atoms[index];
    final expectedAtom = expected.atoms[index];
    if (actualAtom.surfaceOffset != expectedAtom.surfaceOffset ||
        actualAtom.component.revision != expectedAtom.component.revision ||
        actualAtom.component.kind != expectedAtom.component.kind ||
        actualAtom.component.layout != expectedAtom.component.layout ||
        actualAtom.component.sourceRange !=
            expectedAtom.component.sourceRange) {
      return false;
    }
  }
  return true;
}

bool _selectionIsValidFor(TextSelection selection, int textLength) {
  return selection.isValid &&
      selection.baseOffset <= textLength &&
      selection.extentOffset <= textLength;
}

bool _composingRangeIsValidFor(TextRange range, int textLength) {
  if (range.start == -1 && range.end == -1) return true;
  return range.start >= 0 &&
      range.end >= range.start &&
      range.end <= textLength;
}

bool _hasActiveComposition(TextRange range) {
  return range.start >= 0 && range.end > range.start;
}

ComposerSurfaceRange _surfaceRange(TextRange range) {
  return ComposerSurfaceRange(range.start, range.end);
}

bool _rangeIntersectsAtom(
  ComposerSurfaceRange range,
  List<ComposerSurfaceAtomMapping> atoms,
) {
  if (range.isCollapsed) return false;
  for (final atom in atoms) {
    if (range.start < atom.surfaceAfter && range.end > atom.surfaceBefore) {
      return true;
    }
  }
  return false;
}

bool _rangeFullyCoversIntersectedAtoms(
  ComposerSurfaceRange range,
  List<ComposerSurfaceAtomMapping> atoms,
) {
  for (final atom in atoms) {
    final intersects =
        range.start < atom.surfaceAfter && range.end > atom.surfaceBefore;
    if (intersects &&
        (range.start > atom.surfaceBefore || range.end < atom.surfaceAfter)) {
      return false;
    }
  }
  return true;
}

bool _newCompositionTouchesAtom(
  TextRange composition,
  _SurfaceDifference difference,
  List<ComposerSurfaceAtomMapping> atoms,
) {
  if (!_hasActiveComposition(composition)) return false;
  final compositionRange = _surfaceRange(composition);
  for (final atom in atoms) {
    final newAtomOffset = switch ((
      difference.oldRange.end <= atom.surfaceBefore,
      difference.oldRange.start >= atom.surfaceAfter,
    )) {
      (true, _) => atom.surfaceOffset + difference.surfaceLengthDelta,
      (_, true) => atom.surfaceOffset,
      _ => atom.surfaceOffset,
    };
    if (compositionRange.start < newAtomOffset + 1 &&
        compositionRange.end > newAtomOffset) {
      return true;
    }
  }
  return false;
}

ComposerSelection _selectionInUnchangedSource(
  TextSelection selection,
  ComposerSurfaceProjectionPlan plan,
) {
  final anchor = plan.sourceBoundaryForSurfaceBoundary(selection.baseOffset);
  final focus = plan.sourceBoundaryForSurfaceBoundary(selection.extentOffset);
  return _semanticSelection(anchor: anchor, focus: focus);
}

ComposerSelection _selectionInEditedSource(
  TextSelection selection, {
  required _SurfaceDifference difference,
  required ComposerSourceRange sourceRange,
  required ComposerSurfaceProjectionPlan plan,
}) {
  final anchor = _sourceBoundaryAfterEdit(
    selection.baseOffset,
    difference: difference,
    sourceRange: sourceRange,
    plan: plan,
  );
  final focus = _sourceBoundaryAfterEdit(
    selection.extentOffset,
    difference: difference,
    sourceRange: sourceRange,
    plan: plan,
  );
  return _semanticSelection(anchor: anchor, focus: focus);
}

int _sourceBoundaryAfterEdit(
  int newSurfaceOffset, {
  required _SurfaceDifference difference,
  required ComposerSourceRange sourceRange,
  required ComposerSurfaceProjectionPlan plan,
}) {
  if (newSurfaceOffset <= difference.oldRange.start) {
    return plan.sourceBoundaryForSurfaceBoundary(newSurfaceOffset);
  }
  if (newSurfaceOffset < difference.newRangeEnd) {
    return sourceRange.start + (newSurfaceOffset - difference.oldRange.start);
  }

  final oldSurfaceOffset =
      newSurfaceOffset -
      difference.replacement.length +
      difference.oldRange.length;
  final sourceLengthDelta = difference.replacement.length - sourceRange.length;
  return plan.sourceBoundaryForSurfaceBoundary(oldSurfaceOffset) +
      sourceLengthDelta;
}

ComposerSelection _semanticSelection({
  required int anchor,
  required int focus,
}) {
  if (anchor == focus) return ComposerCaretSelection(anchor);
  return ComposerRangeSelection(anchor: anchor, focus: focus);
}
