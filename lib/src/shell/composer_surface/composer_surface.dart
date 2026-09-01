import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../composer_document/component.dart';
import '../composer_document/projection.dart';
import 'component.dart';
import 'projection.dart';

export 'capability_gate.dart';
export 'component.dart';
export 'projection.dart';

typedef ComposerSurfaceValueProposal =
    bool Function(TextEditingValue oldValue, TextEditingValue newValue);

/// A dependency-free projected component surface spike.
///
/// The canonical raw source stays in [ComposerProjection]. The surface is
/// read-only by default; only an owner that supplies [onValueProposed] can open
/// the native text connection, and that owner decides synchronously whether a
/// proposed value may enter the projected controller.
class ComposerSurface extends StatefulWidget {
  const ComposerSurface({
    super.key,
    required this.projection,
    required this.components,
    this.controller,
    this.focusNode,
    this.scrollController,
    this.autofocus = false,
    this.style,
    this.selection,
    this.onSelectionChanged,
    this.onComponentTap,
    this.onValueProposed,
    this.showCursor = true,
  });

  final ComposerProjection projection;
  final ComposerSurfaceComponents components;
  final ComposerSurfaceController? controller;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final bool autofocus;
  final TextStyle? style;

  /// A selection in the raw-free projected buffer.
  ///
  /// The owner is responsible for translating it to and from canonical source
  /// positions through [ComposerSurfaceProjectionPlan].
  final TextSelection? selection;
  final ValueChanged<TextSelection>? onSelectionChanged;
  final ValueChanged<ComposerSurfaceComponent>? onComponentTap;

  /// Intercepts a native controller proposal before it is stored.
  ///
  /// A non-null callback is also the capability that enables the editable
  /// text connection. The hybrid owner returns false for text/composition
  /// proposals after translating them to canonical transactions, so the
  /// projected buffer never becomes a second source of truth.
  final ComposerSurfaceValueProposal? onValueProposed;
  final bool showCursor;

  @override
  State<ComposerSurface> createState() => _ComposerSurfaceState();
}

class _ComposerSurfaceState extends State<ComposerSurface> {
  final GlobalKey _fieldKey = GlobalKey();
  late ComposerSurfaceProjectionPlan _plan;
  late _ProjectedTextEditingController _textController;
  bool _synchronizingController = false;
  int? _pointer;
  Offset? _pointerOrigin;
  bool _pointerDragged = false;

  @override
  void initState() {
    super.initState();
    _createProjection();
  }

  @override
  void didUpdateWidget(ComposerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.projection, widget.projection)) {
      _textController.removeListener(_handleControllerChanged);
      _textController.dispose();
      _createProjection();
      return;
    }
    _textController.components = widget.components;
    _textController.onValueProposed = widget.onValueProposed;
    if (oldWidget.selection != widget.selection) _synchronizeSelection();
    if (oldWidget.controller != widget.controller) {
      widget.controller?.updateSnapshot(_plan.snapshot);
    }
  }

  void _createProjection() {
    _plan = ComposerSurfaceProjectionPlan.fromProjection(widget.projection);
    _textController = _ProjectedTextEditingController(
      plan: _plan,
      components: widget.components,
      selection: _validSelection(widget.selection),
      onValueProposed: widget.onValueProposed,
    );
    _textController.addListener(_handleControllerChanged);
    widget.controller?.updateSnapshot(_plan.snapshot);
  }

  TextSelection _validSelection(TextSelection? requested) {
    if (requested == null || !requested.isValid) {
      return const TextSelection.collapsed(offset: 0);
    }
    return TextSelection(
      baseOffset: requested.baseOffset.clamp(0, _plan.surfaceLength),
      extentOffset: requested.extentOffset.clamp(0, _plan.surfaceLength),
      affinity: requested.affinity,
      isDirectional: requested.isDirectional,
    );
  }

  void _synchronizeSelection() {
    final selection = _validSelection(widget.selection);
    if (_textController.selection == selection) return;
    _synchronizingController = true;
    _textController.setOwnerValue(
      _textController.value.copyWith(
        selection: selection,
        composing: TextRange.empty,
      ),
    );
    _synchronizingController = false;
  }

  void _handleControllerChanged() {
    if (_synchronizingController) return;
    final selection = _textController.selection;
    if (!selection.isValid) return;
    widget.onSelectionChanged?.call(selection);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _pointerOrigin = event.position;
    _pointerDragged = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer || _pointerDragged) return;
    final origin = _pointerOrigin;
    final slop = switch (event.kind) {
      PointerDeviceKind.mouse ||
      PointerDeviceKind.trackpad ||
      PointerDeviceKind.stylus ||
      PointerDeviceKind.invertedStylus => kPrecisePointerHitSlop,
      _ => kTouchSlop,
    };
    if (origin != null && (event.position - origin).distance > slop) {
      _pointerDragged = true;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_pointer != event.pointer) return;
    _clearPointer();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    final wasDragged = _pointerDragged;
    _clearPointer();
    if (wasDragged) return;
    final onComponentTap = widget.onComponentTap;
    final editable = _renderEditable;
    if (onComponentTap == null || editable == null) return;
    final localPosition = editable.globalToLocal(event.position);
    for (final atom in _plan.atoms) {
      final boxes = editable.getBoxesForSelection(
        TextSelection(
          baseOffset: atom.surfaceBefore,
          extentOffset: atom.surfaceAfter,
        ),
      );
      if (boxes.any((box) => box.toRect().contains(localPosition))) {
        final component = atom.component;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComponentTap?.call(component);
        });
        return;
      }
    }
  }

  void _clearPointer() {
    _pointer = null;
    _pointerOrigin = null;
    _pointerDragged = false;
  }

  RenderEditable? get _renderEditable {
    final root = _fieldKey.currentContext?.findRenderObject();
    if (root == null) return null;
    final pending = <RenderObject>[root];
    while (pending.isNotEmpty) {
      final object = pending.removeLast();
      if (object is RenderEditable) return object;
      object.visitChildren(pending.add);
    }
    return null;
  }

  @override
  void dispose() {
    _textController.removeListener(_handleControllerChanged);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: TextField(
        key: _fieldKey,
        controller: _textController,
        focusNode: widget.focusNode,
        scrollController: widget.scrollController,
        autofocus: widget.autofocus,
        readOnly: widget.onValueProposed == null,
        maxLines: null,
        enableInteractiveSelection: true,
        showCursor: widget.showCursor,
        contextMenuBuilder: (context, editableTextState) =>
            const SizedBox.shrink(),
        style: widget.style,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

final class _ProjectedTextEditingController extends TextEditingController {
  _ProjectedTextEditingController({
    required this.plan,
    required this.components,
    required TextSelection selection,
    required this.onValueProposed,
  }) : super.fromValue(
         TextEditingValue(
           text: plan.snapshot.projectedText,
           selection: selection,
         ),
       );

  final ComposerSurfaceProjectionPlan plan;
  ComposerSurfaceComponents components;
  ComposerSurfaceValueProposal? onValueProposed;
  bool _settingOwnerValue = false;

  void setOwnerValue(TextEditingValue ownerValue) {
    _settingOwnerValue = true;
    try {
      value = ownerValue;
    } finally {
      _settingOwnerValue = false;
    }
  }

  @override
  set value(TextEditingValue proposedValue) {
    if (_settingOwnerValue) {
      super.value = proposedValue;
      return;
    }
    final oldValue = super.value;
    if (oldValue == proposedValue) return;
    final proposal = onValueProposed;
    if (proposal == null) {
      if (oldValue.text != proposedValue.text ||
          oldValue.composing != proposedValue.composing) {
        return;
      }
    } else if (!proposal(oldValue, proposedValue)) {
      return;
    }
    super.value = proposedValue;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    var textOffset = 0;
    for (final entry in plan.componentsBySurfaceOffset.entries) {
      if (textOffset < entry.key) {
        spans.add(TextSpan(text: text.substring(textOffset, entry.key)));
      }
      final component = components.build(context, entry.value);
      final isBlock = entry.value.layout == ComposerComponentLayout.block;
      spans.add(
        WidgetSpan(
          alignment: isBlock
              ? PlaceholderAlignment.bottom
              : PlaceholderAlignment.middle,
          child: isBlock
              ? SizedBox(width: double.infinity, child: component)
              : component,
        ),
      );
      textOffset = entry.key + 1;
    }
    if (textOffset < text.length) {
      spans.add(TextSpan(text: text.substring(textOffset)));
    }

    return TextSpan(style: style, children: spans);
  }
}
