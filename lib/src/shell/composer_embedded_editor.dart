import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Isolates Native cell editors from the enclosing composer's text actions.
/// Controls use the outer editor group as their accessibility traversal parent.
class ComposerEmbeddedEditor extends StatelessWidget {
  const ComposerEmbeddedEditor({
    super.key,
    required this.owner,
    this.scrollController,
    required this.semanticLabel,
    required this.child,
  });

  final Object owner;
  final ScrollController? scrollController;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => _EmbeddedViewport(
    scrollController: scrollController,
    child: FocusScope(
      // Keep the cell and main EditableText from both owning keyboard input
      // and scrolling to their carets when a cell receives focus.
      parentNode: FocusScope.of(context),
      child: _editor(),
    ),
  );

  Widget _editor() => Semantics(
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

/// RenderEditable scrolls inline children while painting, but omits that offset
/// from their coordinate transform. Restore it for native input and semantics,
/// without moving the already scrolled painting or pointer hit tests.
class _EmbeddedViewport extends SingleChildRenderObjectWidget {
  const _EmbeddedViewport({
    required this.scrollController,
    required super.child,
  });

  final ScrollController? scrollController;

  @override
  _RenderEmbeddedViewport createRenderObject(BuildContext context) =>
      _RenderEmbeddedViewport(scrollController);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEmbeddedViewport renderObject,
  ) {
    renderObject.scrollController = scrollController;
  }
}

class _RenderEmbeddedViewport extends RenderProxyBox {
  _RenderEmbeddedViewport(this._scrollController);

  ScrollController? _scrollController;

  set scrollController(ScrollController? value) {
    if (identical(_scrollController, value)) return;
    if (attached) _scrollController?.removeListener(markNeedsSemanticsUpdate);
    _scrollController = value;
    if (attached) _scrollController?.addListener(markNeedsSemanticsUpdate);
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrollController?.addListener(markNeedsSemanticsUpdate);
  }

  @override
  void detach() {
    _scrollController?.removeListener(markNeedsSemanticsUpdate);
    super.detach();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    final scroll = _scrollController;
    if (scroll != null && scroll.hasClients) {
      transform.translateByDouble(0, -scroll.offset, 0, 1);
    }
  }

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    // EditableText reveals its own caret but has no viewport adapter for
    // another editable embedded in a WidgetSpan. Relay native caret reveals
    // from both the summary and body to the enclosing document's scroll.
    final scroll = _scrollController;
    RenderObject? viewport = parent;
    while (viewport != null && viewport is! RenderEditable) {
      viewport = viewport.parent;
    }
    if (rect != null &&
        viewport is RenderEditable &&
        scroll != null &&
        scroll.hasClients) {
      final target = MatrixUtils.transformRect(
        (descendant ?? this).getTransformTo(viewport),
        rect,
      );
      final delta = target.bottom > viewport.size.height
          ? target.bottom - viewport.size.height
          : target.top < 0
          ? target.top
          : 0.0;
      final position = scroll.position;
      final offset = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (offset != position.pixels) scroll.jumpTo(offset);
    }
    super.showOnScreen(
      descendant: descendant,
      rect: rect,
      duration: duration,
      curve: curve,
    );
  }
}
