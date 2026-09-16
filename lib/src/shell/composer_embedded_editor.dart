import 'package:flutter/widgets.dart';

/// Isolates Native cell editors from the enclosing composer's text actions.
/// Controls use the outer editor group as their accessibility traversal parent.
class ComposerEmbeddedEditor extends StatelessWidget {
  const ComposerEmbeddedEditor({
    super.key,
    required this.owner,
    required this.semanticLabel,
    required this.child,
  });

  final Object owner;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: semanticLabel,
    traversalChildIdentifier: owner,
    child: Actions(
      actions: {
        DeleteCharacterIntent: _LocalTextAction<DeleteCharacterIntent>(),
        DeleteToNextWordBoundaryIntent:
            _LocalTextAction<DeleteToNextWordBoundaryIntent>(),
        DeleteToLineBreakIntent: _LocalTextAction<DeleteToLineBreakIntent>(),
        ExtendSelectionByCharacterIntent:
            _LocalTextAction<ExtendSelectionByCharacterIntent>(),
        ExtendSelectionToNextWordBoundaryIntent:
            _LocalTextAction<ExtendSelectionToNextWordBoundaryIntent>(),
        ExtendSelectionToNextParagraphBoundaryIntent:
            _LocalTextAction<ExtendSelectionToNextParagraphBoundaryIntent>(),
        ExtendSelectionToLineBreakIntent:
            _LocalTextAction<ExtendSelectionToLineBreakIntent>(),
        ExtendSelectionVerticallyToAdjacentLineIntent:
            _LocalTextAction<ExtendSelectionVerticallyToAdjacentLineIntent>(),
        ExtendSelectionVerticallyToAdjacentPageIntent:
            _LocalTextAction<ExtendSelectionVerticallyToAdjacentPageIntent>(),
        ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent:
            _LocalTextAction<
              ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent
            >(),
        ExtendSelectionToDocumentBoundaryIntent:
            _LocalTextAction<ExtendSelectionToDocumentBoundaryIntent>(),
        ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
            _LocalTextAction<
              ExtendSelectionToNextWordBoundaryOrCaretLocationIntent
            >(),
        ScrollToDocumentBoundaryIntent:
            _LocalTextAction<ScrollToDocumentBoundaryIntent>(),
        ExpandSelectionToLineBreakIntent:
            _LocalTextAction<ExpandSelectionToLineBreakIntent>(),
        ExpandSelectionToDocumentBoundaryIntent:
            _LocalTextAction<ExpandSelectionToDocumentBoundaryIntent>(),
        SelectAllTextIntent: _LocalTextAction<SelectAllTextIntent>(),
        CopySelectionTextIntent: _LocalTextAction<CopySelectionTextIntent>(),
        PasteTextIntent: _LocalTextAction<PasteTextIntent>(),
        TransposeCharactersIntent:
            _LocalTextAction<TransposeCharactersIntent>(),
        EditableTextTapOutsideIntent:
            _LocalTextAction<EditableTextTapOutsideIntent>(),
        EditableTextTapUpOutsideIntent:
            _LocalTextAction<EditableTextTapUpOutsideIntent>(),
        UndoTextIntent: _LocalTextAction<UndoTextIntent>(),
        RedoTextIntent: _LocalTextAction<RedoTextIntent>(),
      },
      child: child,
    ),
  );
}

/// Flutter's overridable editing actions otherwise find the parent
/// EditableText and operate on the composer. Relay to the originating
/// field's native implementation, including its clipboard and undo history.
class _LocalTextAction<T extends Intent> extends Action<T> {
  @override
  Object? invoke(T intent) => callingAction?.invoke(intent);

  @override
  bool isEnabled(T intent) => callingAction?.isEnabled(intent) ?? false;

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;
}
