import 'component.dart';
import 'projection.dart';
import 'selection.dart';
import 'source.dart';

final class ComposerSourceEdit {
  const ComposerSourceEdit({
    required this.range,
    required this.expectedSource,
    required this.replacement,
  });

  final ComposerSourceRange range;
  final String expectedSource;
  final String replacement;
}

/// A revision- and source-verified atomic mutation.
final class ComposerTransaction {
  ComposerTransaction({
    required this.baseRevision,
    required Iterable<ComposerSourceEdit> edits,
    required this.selectionAfter,
    this.debugLabel,
  }) : edits = List.unmodifiable(edits);

  final ComposerRevision baseRevision;
  final List<ComposerSourceEdit> edits;
  final ComposerSelection selectionAfter;
  final String? debugLabel;
}

enum ComposerTransactionFailureCode {
  noEdits,
  staleRevision,
  invalidRange,
  overlappingEdits,
  sourceMismatch,
}

final class ComposerTransactionFailure {
  const ComposerTransactionFailure({
    required this.code,
    this.edit,
    this.actualSource,
  });

  final ComposerTransactionFailureCode code;
  final ComposerSourceEdit? edit;
  final String? actualSource;
}

final class ComposerDocumentSnapshot {
  const ComposerDocumentSnapshot({
    required this.source,
    required this.revision,
    required this.projection,
    required this.selection,
  });

  final String source;
  final ComposerRevision revision;
  final ComposerProjection projection;
  final ComposerSelection selection;
}

sealed class ComposerCommitResult {
  const ComposerCommitResult();
}

final class ComposerCommitApplied extends ComposerCommitResult {
  const ComposerCommitApplied({required this.before, required this.after});

  final ComposerDocumentSnapshot before;
  final ComposerDocumentSnapshot after;
}

final class ComposerCommitRejected extends ComposerCommitResult {
  const ComposerCommitRejected({required this.current, required this.failure});

  final ComposerDocumentSnapshot current;
  final ComposerTransactionFailure failure;
}

/// Owns exact source, semantic selection, verified commits, and local history.
final class ComposerDocument {
  factory ComposerDocument({
    required String source,
    required Iterable<ComposerComponentDefinition<Object>> definitions,
    ComposerSelection? selection,
    ComposerProjectionResolver resolver = const ComposerProjectionResolver(),
    ComposerSelectionNormalizer selectionNormalizer =
        const ComposerSelectionNormalizer(),
  }) {
    const revision = ComposerRevision(0);
    final frozenDefinitions =
        List<ComposerComponentDefinition<Object>>.unmodifiable(definitions);
    final projection = resolver.resolve(
      input: ComposerParseInput(source: source, revision: revision),
      definitions: frozenDefinitions,
    );
    final normalizedSelection = selectionNormalizer.normalize(
      selection ?? ComposerCaretSelection(source.length),
      projection,
    );
    return ComposerDocument._(
      definitions: frozenDefinitions,
      resolver: resolver,
      selectionNormalizer: selectionNormalizer,
      snapshot: ComposerDocumentSnapshot(
        source: source,
        revision: revision,
        projection: projection,
        selection: normalizedSelection,
      ),
    );
  }

  ComposerDocument._({
    required this._definitions,
    required this._resolver,
    required this._selectionNormalizer,
    required this._snapshot,
  });

  final List<ComposerComponentDefinition<Object>> _definitions;
  final ComposerProjectionResolver _resolver;
  final ComposerSelectionNormalizer _selectionNormalizer;
  final List<_StoredDocument> _undo = [];
  final List<_StoredDocument> _redo = [];
  ComposerDocumentSnapshot _snapshot;

  ComposerDocumentSnapshot get snapshot => _snapshot;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  ComposerDocumentSnapshot setSelection(ComposerSelection selection) {
    _snapshot = ComposerDocumentSnapshot(
      source: _snapshot.source,
      revision: _snapshot.revision,
      projection: _snapshot.projection,
      selection: _selectionNormalizer.normalize(
        selection,
        _snapshot.projection,
      ),
    );
    return _snapshot;
  }

  ComposerCommitResult commit(ComposerTransaction transaction) {
    final before = _snapshot;
    final failure = _validate(transaction);
    if (failure != null) {
      return ComposerCommitRejected(current: before, failure: failure);
    }

    final orderedEdits = transaction.edits.toList()
      ..sort((left, right) {
        final start = right.range.start.compareTo(left.range.start);
        if (start != 0) return start;
        return right.range.end.compareTo(left.range.end);
      });
    var nextSource = before.source;
    for (final edit in orderedEdits) {
      nextSource = nextSource.replaceRange(
        edit.range.start,
        edit.range.end,
        edit.replacement,
      );
    }

    final after = _createSnapshot(
      source: nextSource,
      revision: before.revision.next,
      selection: transaction.selectionAfter,
    );
    _undo.add(_StoredDocument.fromSnapshot(before));
    _redo.clear();
    _snapshot = after;
    return ComposerCommitApplied(before: before, after: _snapshot);
  }

  ComposerDocumentSnapshot? undo() {
    if (_undo.isEmpty) return null;
    final restored = _undo.last;
    final next = _createSnapshot(
      source: restored.source,
      revision: _snapshot.revision.next,
      selection: restored.selection,
    );
    _redo.add(_StoredDocument.fromSnapshot(_snapshot));
    _undo.removeLast();
    _snapshot = next;
    return _snapshot;
  }

  ComposerDocumentSnapshot? redo() {
    if (_redo.isEmpty) return null;
    final restored = _redo.last;
    final next = _createSnapshot(
      source: restored.source,
      revision: _snapshot.revision.next,
      selection: restored.selection,
    );
    _undo.add(_StoredDocument.fromSnapshot(_snapshot));
    _redo.removeLast();
    _snapshot = next;
    return _snapshot;
  }

  ComposerTransactionFailure? _validate(ComposerTransaction transaction) {
    if (transaction.edits.isEmpty) {
      return const ComposerTransactionFailure(
        code: ComposerTransactionFailureCode.noEdits,
      );
    }
    if (transaction.baseRevision != _snapshot.revision) {
      return const ComposerTransactionFailure(
        code: ComposerTransactionFailureCode.staleRevision,
      );
    }

    final ordered = transaction.edits.toList()
      ..sort((left, right) {
        final start = left.range.start.compareTo(right.range.start);
        if (start != 0) return start;
        return left.range.end.compareTo(right.range.end);
      });
    ComposerSourceEdit? previous;
    for (final edit in ordered) {
      if (!edit.range.isValidFor(_snapshot.source)) {
        return ComposerTransactionFailure(
          code: ComposerTransactionFailureCode.invalidRange,
          edit: edit,
        );
      }
      if (previous != null &&
          (edit.range.start < previous.range.end ||
              edit.range.start == previous.range.start)) {
        return ComposerTransactionFailure(
          code: ComposerTransactionFailureCode.overlappingEdits,
          edit: edit,
        );
      }
      final actual = edit.range.capture(_snapshot.source);
      if (actual != edit.expectedSource) {
        return ComposerTransactionFailure(
          code: ComposerTransactionFailureCode.sourceMismatch,
          edit: edit,
          actualSource: actual,
        );
      }
      previous = edit;
    }
    return null;
  }

  ComposerDocumentSnapshot _createSnapshot({
    required String source,
    required ComposerRevision revision,
    required ComposerSelection selection,
  }) {
    final projection = _resolver.resolve(
      input: ComposerParseInput(source: source, revision: revision),
      definitions: _definitions,
    );
    final reboundSelection = _rebindComponentSelection(selection, projection);
    return ComposerDocumentSnapshot(
      source: source,
      revision: revision,
      projection: projection,
      selection: _selectionNormalizer.normalize(reboundSelection, projection),
    );
  }

  ComposerSelection _rebindComponentSelection(
    ComposerSelection selection,
    ComposerProjection projection,
  ) {
    if (selection is! ComposerComponentSelection) return selection;
    final previous = selection.component;
    for (final component in projection.components) {
      if (component.kind == previous.kind &&
          component.range == previous.range &&
          component.source == previous.source) {
        return ComposerComponentSelection(component.token);
      }
    }
    return selection;
  }
}

final class _StoredDocument {
  const _StoredDocument({required this.source, required this.selection});

  factory _StoredDocument.fromSnapshot(ComposerDocumentSnapshot snapshot) {
    return _StoredDocument(
      source: snapshot.source,
      selection: snapshot.selection,
    );
  }

  final String source;
  final ComposerSelection selection;
}
