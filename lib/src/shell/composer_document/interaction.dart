import 'component.dart';
import 'document.dart';
import 'selection.dart';
import 'source.dart';

enum ComposerMoveDirection { left, right }

enum ComposerDeleteDirection { backward, forward }

sealed class ComposerInteractionIntent {
  const ComposerInteractionIntent();
}

final class ComposerMoveIntent extends ComposerInteractionIntent {
  const ComposerMoveIntent(this.direction);

  final ComposerMoveDirection direction;
}

final class ComposerDeleteIntent extends ComposerInteractionIntent {
  const ComposerDeleteIntent(this.direction);

  final ComposerDeleteDirection direction;
}

final class ComposerEscapeIntent extends ComposerInteractionIntent {
  const ComposerEscapeIntent();
}

/// A raw selection request from a surface, before atom boundary snapping.
final class ComposerSelectIntent extends ComposerInteractionIntent {
  const ComposerSelectIntent({required this.anchor, required this.focus});

  final int anchor;
  final int focus;
}

/// An exact atom hit reported by the surface's component placeholder.
final class ComposerSelectComponentIntent extends ComposerInteractionIntent {
  const ComposerSelectComponentIntent(this.component);

  final ComposerComponentToken component;
}

sealed class ComposerInteractionDecision {
  const ComposerInteractionDecision();
}

final class ComposerInteractionSelection extends ComposerInteractionDecision {
  const ComposerInteractionSelection(this.selection);

  final ComposerSelection selection;
}

final class ComposerInteractionTransaction extends ComposerInteractionDecision {
  const ComposerInteractionTransaction(this.transaction);

  final ComposerTransaction transaction;
}

/// The intent belongs to ordinary text/IME behavior rather than an atom.
final class ComposerInteractionPassThrough extends ComposerInteractionDecision {
  const ComposerInteractionPassThrough();
}

/// Reduces surface-independent editing intents at component boundaries.
final class ComposerInteractionReducer {
  const ComposerInteractionReducer({
    this.selectionNormalizer = const ComposerSelectionNormalizer(),
  });

  final ComposerSelectionNormalizer selectionNormalizer;

  ComposerInteractionDecision reduce(
    ComposerDocumentSnapshot snapshot,
    ComposerInteractionIntent intent,
  ) {
    return switch (intent) {
      ComposerMoveIntent() => _move(snapshot, intent.direction),
      ComposerDeleteIntent() => _delete(snapshot, intent.direction),
      ComposerEscapeIntent() => _escape(snapshot),
      ComposerSelectIntent() => _select(snapshot, intent),
      ComposerSelectComponentIntent() => _selectComponent(snapshot, intent),
    };
  }

  ComposerInteractionDecision _move(
    ComposerDocumentSnapshot snapshot,
    ComposerMoveDirection direction,
  ) {
    final selection = snapshot.selection;
    if (selection is ComposerComponentSelection) {
      final component = snapshot.projection.componentForToken(
        selection.component,
      );
      if (component == null) return const ComposerInteractionPassThrough();
      return ComposerInteractionSelection(
        ComposerCaretSelection(
          direction == ComposerMoveDirection.left
              ? component.range.start
              : component.range.end,
        ),
      );
    }
    if (selection is ComposerRangeSelection) {
      return ComposerInteractionSelection(
        ComposerCaretSelection(
          direction == ComposerMoveDirection.left
              ? selection.start
              : selection.end,
        ),
      );
    }
    if (selection is! ComposerCaretSelection) {
      return const ComposerInteractionPassThrough();
    }
    final component = direction == ComposerMoveDirection.left
        ? snapshot.projection.componentEndingAt(selection.offset)
        : snapshot.projection.componentStartingAt(selection.offset);
    return component == null
        ? const ComposerInteractionPassThrough()
        : ComposerInteractionSelection(
            ComposerComponentSelection(component.token),
          );
  }

  ComposerInteractionDecision _delete(
    ComposerDocumentSnapshot snapshot,
    ComposerDeleteDirection direction,
  ) {
    final selection = snapshot.selection;
    if (selection is ComposerRangeSelection) {
      return _deleteRange(
        snapshot,
        ComposerSourceRange(selection.start, selection.end),
        'delete selection',
      );
    }
    if (selection is ComposerComponentSelection) {
      final component = snapshot.projection.componentForToken(
        selection.component,
      );
      if (component == null) return const ComposerInteractionPassThrough();
      return _deleteRange(snapshot, component.range, 'delete component');
    }
    if (selection is! ComposerCaretSelection) {
      return const ComposerInteractionPassThrough();
    }
    final component = direction == ComposerDeleteDirection.backward
        ? snapshot.projection.componentEndingAt(selection.offset)
        : snapshot.projection.componentStartingAt(selection.offset);
    return component == null
        ? const ComposerInteractionPassThrough()
        : ComposerInteractionSelection(
            ComposerComponentSelection(component.token),
          );
  }

  ComposerInteractionDecision _deleteRange(
    ComposerDocumentSnapshot snapshot,
    ComposerSourceRange range,
    String debugLabel,
  ) {
    return ComposerInteractionTransaction(
      ComposerTransaction(
        baseRevision: snapshot.revision,
        edits: [
          ComposerSourceEdit(
            range: range,
            expectedSource: range.capture(snapshot.source),
            replacement: '',
          ),
        ],
        selectionAfter: ComposerCaretSelection(range.start),
        debugLabel: debugLabel,
      ),
    );
  }

  ComposerInteractionDecision _escape(ComposerDocumentSnapshot snapshot) {
    final selection = snapshot.selection;
    if (selection is! ComposerComponentSelection) {
      return const ComposerInteractionPassThrough();
    }
    final component = snapshot.projection.componentForToken(
      selection.component,
    );
    return component == null
        ? const ComposerInteractionPassThrough()
        : ComposerInteractionSelection(
            ComposerCaretSelection(component.range.end),
          );
  }

  ComposerInteractionDecision _select(
    ComposerDocumentSnapshot snapshot,
    ComposerSelectIntent intent,
  ) {
    if (intent.anchor == intent.focus) {
      final offset = intent.anchor.clamp(0, snapshot.source.length);
      final component = snapshot.projection.componentContainingOffset(offset);
      if (component != null) {
        return ComposerInteractionSelection(
          ComposerComponentSelection(component.token),
        );
      }
      return ComposerInteractionSelection(ComposerCaretSelection(offset));
    }
    final normalized = selectionNormalizer.normalize(
      ComposerRangeSelection(anchor: intent.anchor, focus: intent.focus),
      snapshot.projection,
    );
    return ComposerInteractionSelection(normalized);
  }

  ComposerInteractionDecision _selectComponent(
    ComposerDocumentSnapshot snapshot,
    ComposerSelectComponentIntent intent,
  ) {
    final component = snapshot.projection.componentForToken(intent.component);
    return component == null
        ? const ComposerInteractionPassThrough()
        : ComposerInteractionSelection(
            ComposerComponentSelection(component.token),
          );
  }
}
