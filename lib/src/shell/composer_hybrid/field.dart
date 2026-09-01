import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../composer_document/component.dart';
import '../composer_document/document.dart';
import '../composer_document/interaction.dart';
import '../composer_document/selection.dart';
import '../composer_surface/composer_surface.dart';
import '../composer_surface/edit_translation.dart';
import 'session.dart';

/// A raw-free interaction slice backed by one [ComposerHybridEditingSession].
///
/// Ordinary text proposals are translated to verified source transactions;
/// active IME composition and clipboard commands remain deliberately disabled.
/// Atomic component rendering, semantic navigation, and snapped native
/// selection never introduce a second document model.
class ComposerHybridField extends StatefulWidget {
  const ComposerHybridField({
    super.key,
    required this.session,
    this.surfaceController,
    this.focusNode,
    this.scrollController,
    this.autofocus = false,
    this.style,
  });

  final ComposerHybridEditingSession session;
  final ComposerSurfaceController? surfaceController;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final bool autofocus;
  final TextStyle? style;

  @override
  State<ComposerHybridField> createState() => _ComposerHybridFieldState();
}

class _ComposerHybridFieldState extends State<ComposerHybridField> {
  static const _editTranslator = ComposerSurfaceEditTranslator();

  late ComposerSurfaceProjectionPlan _plan;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_handleSessionChanged);
  }

  @override
  void didUpdateWidget(ComposerHybridField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    oldWidget.session.removeListener(_handleSessionChanged);
    widget.session.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.session.snapshot;
    _plan = ComposerSurfaceProjectionPlan.fromProjection(snapshot.projection);
    final selection = _surfaceSelectionFor(snapshot.selection, _plan);
    final components = _componentsFor(snapshot);

    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (_) => null,
        ),
        PasteTextIntent: CallbackAction<PasteTextIntent>(onInvoke: (_) => null),
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            widget.session.undo();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            widget.session.redo();
            return null;
          },
        ),
      },
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: ComposerSurface(
          projection: snapshot.projection,
          components: components,
          controller: widget.surfaceController,
          focusNode: widget.focusNode,
          scrollController: widget.scrollController,
          autofocus: widget.autofocus,
          style: widget.style,
          selection: selection,
          onSelectionChanged: _handleSurfaceSelectionChanged,
          onComponentTap: _handleSurfaceComponentTap,
          onValueProposed: _handleSurfaceValueProposed,
          showCursor: snapshot.selection is! ComposerComponentSelection,
        ),
      ),
    );
  }

  ComposerSurfaceComponents _componentsFor(ComposerDocumentSnapshot snapshot) {
    final widgets = <ComposerComponentKind, ComposerSurfaceWidgetBuilder>{};
    final semanticLabels =
        <ComposerComponentKind, ComposerSurfaceSemanticLabelBuilder>{};
    for (final match in snapshot.projection.components) {
      final renderer = widget.session.rendererFor(match.kind);
      if (renderer == null || widgets.containsKey(match.kind)) continue;
      widgets[match.kind] = (context, component) {
        final currentMatch = _validatedMatch(component);
        if (currentMatch == null) return const SizedBox.shrink();
        final selected = switch (widget.session.selection) {
          ComposerComponentSelection(:final component) =>
            component == currentMatch.token,
          _ => false,
        };
        return renderer.build(
          context,
          match: currentMatch,
          baseStyle: widget.style ?? DefaultTextStyle.of(context).style,
          selected: selected,
          hovered: false,
        );
      };
      semanticLabels[match.kind] = (context, component) {
        final currentMatch = _validatedMatch(component);
        return currentMatch == null
            ? match.kind.value
            : renderer.semanticLabel(context, currentMatch);
      };
    }
    return ComposerSurfaceComponents(
      widgets: widgets,
      semanticLabels: semanticLabels,
    );
  }

  ComposerComponentMatch<Object>? _validatedMatch(
    ComposerSurfaceComponent component,
  ) {
    for (final match in widget.session.snapshot.projection.components) {
      if (match.revision == component.revision &&
          match.kind == component.kind &&
          match.layout == component.layout &&
          match.range == component.sourceRange &&
          identical(match.value, component.value)) {
        return match;
      }
    }
    return null;
  }

  void _handleSurfaceSelectionChanged(TextSelection selection) {
    if (!selection.isValid ||
        selection.baseOffset > _plan.surfaceLength ||
        selection.extentOffset > _plan.surfaceLength) {
      return;
    }
    final expected = _surfaceSelectionFor(widget.session.selection, _plan);
    if (selection.baseOffset == expected.baseOffset &&
        selection.extentOffset == expected.extentOffset) {
      return;
    }
    widget.session.dispatch(
      ComposerSelectIntent(
        anchor: _plan.sourceBoundaryForSurfaceBoundary(selection.baseOffset),
        focus: _plan.sourceBoundaryForSurfaceBoundary(selection.extentOffset),
      ),
    );
  }

  void _handleSurfaceComponentTap(ComposerSurfaceComponent component) {
    final match = _validatedMatch(component);
    if (match == null) return;
    widget.session.dispatch(ComposerSelectComponentIntent(match.token));
  }

  bool _handleSurfaceValueProposed(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.composing != newValue.composing) return false;
    final translation = _editTranslator.translate(
      snapshot: widget.session.snapshot,
      plan: _plan,
      oldValue: oldValue,
      newValue: newValue,
    );
    return switch (translation) {
      ComposerSurfaceSelectionTranslation() => true,
      ComposerSurfaceTextEditTranslation(:final transaction) => () {
        widget.session.commit(transaction);
        return false;
      }(),
      ComposerSurfaceEditRejected(:final reason, :final changedSurfaceRange) =>
        () {
          if (reason ==
                  ComposerSurfaceEditRejectionReason
                      .changedRangeIntersectsAtom &&
              changedSurfaceRange != null) {
            _routeSemanticDeletion(oldValue, newValue, changedSurfaceRange);
          }
          return false;
        }(),
    };
  }

  void _routeSemanticDeletion(
    TextEditingValue oldValue,
    TextEditingValue newValue,
    ComposerSurfaceRange changedRange,
  ) {
    if (newValue.text !=
        oldValue.text.replaceRange(changedRange.start, changedRange.end, '')) {
      return;
    }
    final selection = oldValue.selection;
    final ComposerDeleteDirection direction;
    if (selection.isCollapsed) {
      if (selection.extentOffset == changedRange.end) {
        direction = ComposerDeleteDirection.backward;
      } else if (selection.extentOffset == changedRange.start) {
        direction = ComposerDeleteDirection.forward;
      } else {
        return;
      }
    } else {
      if (selection.start != changedRange.start ||
          selection.end != changedRange.end) {
        return;
      }
      direction = ComposerDeleteDirection.backward;
    }
    widget.session.dispatch(ComposerDeleteIntent(direction));
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final hasCommandModifier =
        keyboard.isMetaPressed || keyboard.isControlPressed;
    final isUndoOrRedo =
        (hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyZ) ||
        (keyboard.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyY);
    if (isUndoOrRedo) {
      if (event is KeyDownEvent) {
        final redo =
            event.logicalKey == LogicalKeyboardKey.keyY ||
            keyboard.isShiftPressed;
        if (redo) {
          widget.session.redo();
        } else {
          widget.session.undo();
        }
      }
      return KeyEventResult.handled;
    }
    if (hasCommandModifier &&
        (event.logicalKey == LogicalKeyboardKey.keyC ||
            event.logicalKey == LogicalKeyboardKey.keyX ||
            event.logicalKey == LogicalKeyboardKey.keyV)) {
      return KeyEventResult.handled;
    }
    final hasModifier =
        hasCommandModifier || keyboard.isAltPressed || keyboard.isShiftPressed;
    if (hasModifier) return KeyEventResult.ignored;

    final intent = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => const ComposerMoveIntent(
        ComposerMoveDirection.left,
      ),
      LogicalKeyboardKey.arrowRight => const ComposerMoveIntent(
        ComposerMoveDirection.right,
      ),
      LogicalKeyboardKey.backspace => const ComposerDeleteIntent(
        ComposerDeleteDirection.backward,
      ),
      LogicalKeyboardKey.delete => const ComposerDeleteIntent(
        ComposerDeleteDirection.forward,
      ),
      LogicalKeyboardKey.escape when event is KeyDownEvent =>
        const ComposerEscapeIntent(),
      _ => null,
    };
    if (intent == null) return KeyEventResult.ignored;
    return widget.session.dispatch(intent).handled
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }
}

TextSelection _surfaceSelectionFor(
  ComposerSelection selection,
  ComposerSurfaceProjectionPlan plan,
) {
  return switch (selection) {
    ComposerCaretSelection(:final offset) => TextSelection.collapsed(
      offset: plan.surfaceBoundaryForSourceBoundary(offset),
    ),
    ComposerRangeSelection(:final anchor, :final focus) => TextSelection(
      baseOffset: plan.surfaceBoundaryForSourceBoundary(anchor),
      extentOffset: plan.surfaceBoundaryForSourceBoundary(focus),
      isDirectional: true,
    ),
    ComposerComponentSelection(:final component) => _componentSelection(
      component,
      plan,
    ),
  };
}

TextSelection _componentSelection(
  ComposerComponentToken component,
  ComposerSurfaceProjectionPlan plan,
) {
  for (final atom in plan.atoms) {
    if (atom.component.kind == component.kind &&
        atom.component.sourceRange == component.range) {
      return TextSelection(
        baseOffset: atom.surfaceBefore,
        extentOffset: atom.surfaceAfter,
        isDirectional: true,
      );
    }
  }
  return TextSelection.collapsed(
    offset: plan.surfaceBoundaryForSourceBoundary(component.range.start),
  );
}
