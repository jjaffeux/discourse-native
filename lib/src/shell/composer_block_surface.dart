import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/d_icons.dart';
import 'composer_blocks.dart';
import 'composer_controller.dart';
import 'composer_drop_geometry.dart';
import 'platform.dart';

class _BlockDrag {
  const _BlockDrag(this.composer, this.id, this.revision);
  final ComposerController composer;
  final int id;
  final int revision;
}

/// Adds structural controls around a single, continuously mounted text editor.
/// Geometry comes from the editor, so soft wraps never become separate blocks.
class ComposerBlockSurface extends StatefulWidget {
  const ComposerBlockSurface({
    super.key,
    required this.composer,
    required this.child,
    required this.blockRect,
    required this.emptyLineAt,
    required this.editorScroll,
    required this.expands,
    this.geometryChanges,
  });

  final ComposerController composer;
  final Widget child;
  final Rect? Function(ComposerBodyBlock block) blockRect;
  final ComposerEmptyLine? Function(Offset? position) emptyLineAt;
  final ScrollPosition? Function() editorScroll;
  final bool expands;
  final Listenable? geometryChanges;

  @override
  State<ComposerBlockSurface> createState() => _ComposerBlockSurfaceState();
}

class _ComposerBlockSurfaceState extends State<ComposerBlockSurface> {
  final _bounds = GlobalKey();
  final _dragFocus = FocusNode(debugLabel: 'Composer block drag');
  late final AppLifecycleListener _lifecycle;
  _BlockDrag? _drag;
  ComposerDropTarget? _dropTarget;
  int? _hoveredId;
  Offset? _hoverPosition;
  TextRange? _emptyLine;
  Offset? _pointer;
  Timer? _autoScroll;
  bool _refreshScheduled = false;
  final _blockActionsKey = GlobalKey();
  Rect? _handleRect;
  double? _dropTop;

  ComposerController get composer => widget.composer;

  ComposerBodyBlock? get _activeBlock =>
      composer.blocks.index.byId(_drag?.id ?? _hoveredId ?? -1) ??
      composer.blocks.selected;

  @override
  void initState() {
    super.initState();
    composer.blocks.addListener(_changed);
    widget.geometryChanges?.addListener(_scheduleGeometry);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _cancelDrag();
      },
    );
  }

  @override
  void didUpdateWidget(ComposerBlockSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.geometryChanges, widget.geometryChanges)) {
      oldWidget.geometryChanges?.removeListener(_scheduleGeometry);
      widget.geometryChanges?.addListener(_scheduleGeometry);
    }
    if (!identical(oldWidget.composer, composer)) {
      oldWidget.composer.blocks.removeListener(_changed);
      composer.blocks.addListener(_changed);
      _cancelDrag();
      _hoveredId = null;
    }
    _scheduleGeometry();
  }

  void _changed() {
    _hoverPosition = null;
    if (_drag case final drag?) {
      if (!_accepts(drag)) _cancelDrag();
    }
    _scheduleGeometry();
    setState(() {});
  }

  void _scheduleGeometry() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      final block = _activeBlock;
      final emptyLine = _drag == null
          ? widget.emptyLineAt(_hoverPosition) ??
                (block == null ? widget.emptyLineAt(null) : null)
          : null;
      final rect =
          emptyLine?.rect ?? (block == null ? null : widget.blockRect(block));
      final box = _bounds.currentContext?.findRenderObject();
      final localRect = rect == null || box is! RenderBox || !box.hasSize
          ? null
          : Rect.fromPoints(
              box.globalToLocal(rect.topLeft),
              box.globalToLocal(rect.bottomRight),
            );
      final target = _pointer == null ? _dropTarget : _targetAt(_pointer!);
      final dropTop = _dropY(target);
      if (localRect != _handleRect ||
          dropTop != _dropTop ||
          target != _dropTarget ||
          emptyLine?.range != _emptyLine) {
        setState(() {
          _emptyLine = emptyLine?.range;
          _handleRect = localRect;
          _dropTarget = target;
          _dropTop = dropTop;
        });
      }
    });
  }

  @override
  void dispose() {
    composer.blocks.removeListener(_changed);
    widget.geometryChanges?.removeListener(_scheduleGeometry);
    _autoScroll?.cancel();
    _dragFocus.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  bool _validSnapshot(_BlockDrag drag) =>
      identical(drag.composer, composer) &&
      drag.revision == composer.blocks.revision &&
      composer.blocks.enabled;

  bool _accepts(_BlockDrag drag) =>
      identical(_drag, drag) && _validSnapshot(drag);

  ComposerDropGeometry get _dropGeometry => ComposerDropGeometry(
    composer.blocks.index,
    widget.blockRect,
    emptyLineAt: widget.emptyLineAt,
  );

  ComposerDropTarget? _targetAt(Offset position) {
    final drag = _drag;
    if (drag == null || !_accepts(drag)) return null;
    final candidate = _dropGeometry.targetAt(
      position,
      previousTarget: _dropTarget,
    );
    if (candidate == null) return null;
    // The drag revision is unchanged, so a previously accepted destination
    // needs only fresh geometry, not another parse of the entire draft.
    if (candidate.gap == _dropTarget?.gap &&
        candidate.offset == _dropTarget?.offset) {
      return candidate;
    }
    final source = composer.blocks.index.blocks.indexWhere(
      (block) => block.id == drag.id,
    );
    return candidate.gap == source ||
            candidate.gap == source + 1 ||
            composer.blocks.index.move(
                  drag.id,
                  candidate.gap,
                  offset: candidate.offset,
                ) !=
                null
        ? candidate
        : null;
  }

  void _moveDrag(_BlockDrag drag, Offset position) {
    if (!_accepts(drag)) return;
    _pointer = position;
    final target = _targetAt(position);
    if (_dropTarget != target) {
      setState(() {
        _dropTarget = target;
      });
      _scheduleGeometry();
    }
    _autoScroll ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _scrollDrag(),
    );
  }

  void _scrollDrag() {
    final pointer = _pointer;
    final drag = _drag;
    if (pointer == null || drag == null || !_accepts(drag)) return;
    final position = widget.editorScroll();
    final object = _bounds.currentContext?.findRenderObject();
    if (position == null || object is! RenderBox || !object.hasSize) return;
    final bounds = object.localToGlobal(Offset.zero) & object.size;
    // Intersect a growing mobile editor with its scroll viewport.
    final viewport = position.context.notificationContext?.findRenderObject();
    final visible = viewport is RenderBox && viewport.hasSize
        ? bounds.intersect(viewport.localToGlobal(Offset.zero) & viewport.size)
        : bounds;
    const edge = DSpacing.touchTarget;
    final delta = pointer.dy < visible.top + edge
        ? -((visible.top + edge - pointer.dy) / edge).clamp(0, 1) * 10
        : pointer.dy > visible.bottom - edge
        ? ((pointer.dy - visible.bottom + edge) / edge).clamp(0, 1) * 10
        : 0.0;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next != position.pixels) {
      position.jumpTo(next);
      _moveDrag(drag, pointer);
      _scheduleGeometry();
    }
  }

  void _leaveDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _pointer = null;
    if (mounted) {
      setState(() {
        _dropTarget = null;
        _dropTop = null;
      });
    }
  }

  void _cancelDrag() {
    _drag = null;
    _leaveDrag();
  }

  void _drop(_BlockDrag drag, Offset position) {
    if (!_accepts(drag)) return;
    final target = _targetAt(position);
    if (target != null) {
      if (composer.blocks.moveTo(
        target.gap,
        offset: target.offset,
        blockId: drag.id,
        expectedRevision: drag.revision,
      )) {
        _revealSelection();
      }
    }
    _cancelDrag();
    composer.focus.requestFocus();
  }

  void _move(int gap) {
    if (composer.blocks.moveTo(
      gap,
      expectedRevision: composer.blocks.revision,
    )) {
      _revealSelection();
    }
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final block = composer.blocks.selected;
      if (block == null) return;
      final rect = widget.blockRect(block);
      final position = widget.editorScroll();
      final box = _bounds.currentContext?.findRenderObject();
      if (rect == null ||
          position == null ||
          box is! RenderBox ||
          !box.hasSize) {
        return;
      }
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      final delta = rect.top < bounds.top
          ? rect.top - bounds.top
          : rect.bottom > bounds.bottom
          ? rect.bottom - bounds.bottom
          : 0.0;
      if (delta != 0) {
        position.jumpTo(
          (position.pixels + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
      _scheduleGeometry();
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _drag != null) {
      _cancelDrag();
      composer.focus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _handle(ComposerBodyBlock block) {
    final position = composer.blocks.index.blocks.indexOf(block);
    // Only the selected handle can have an open menu. Avoid reparsing the
    // entire draft for both actions on every block.
    final active = composer.blocks.selected?.id == block.id;
    final drag = _drag?.id == block.id
        ? _drag!
        : _BlockDrag(composer, block.id, composer.blocks.revision);
    return DDropdownMenu(
      sheetOnMobile: true,
      content: DDropdownMenuContent(
        semanticLabel: '${block.label} actions',
        children: [
          DDropdownMenuItem(
            onPressed:
                active &&
                    composer.blocks.enabled &&
                    composer.blocks.index.move(block.id, position - 1) != null
                ? () {
                    composer.blocks.select(block.id);
                    _move(position - 1);
                  }
                : null,
            child: const Text('Move up'),
          ),
          DDropdownMenuItem(
            onPressed:
                active &&
                    composer.blocks.enabled &&
                    composer.blocks.index.move(block.id, position + 2) != null
                ? () {
                    composer.blocks.select(block.id);
                    _move(position + 2);
                  }
                : null,
            child: const Text('Move down'),
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, trigger) => DDragHandle<_BlockDrag>(
          key: ValueKey('composer-block-handle-${block.id}'),
          data: drag,
          label: 'Drag to move or click to open menu',
          enabled:
              composer.blocks.enabled &&
              block.movable &&
              (_drag == null || identical(_drag, drag)),
          focusNode: trigger.focusNode,
          expanded: trigger.open,
          onPressed: () {
            composer.blocks.select(block.id);
            trigger.toggle();
          },
          onDragStarted: () {
            composer.blocks.select(block.id);
            _dragFocus.requestFocus();
            setState(() => _drag = drag);
          },
          onDragEnd: () {
            if (identical(_drag, drag)) _cancelDrag();
          },
        ),
      ),
    );
  }

  void _addBlock(ComposerBodyBlock? block, TextRange? emptyLine) {
    if (!composer.blocks.enabled || _drag != null) return;
    final source = composer.text.text;
    final current = block == null ? null : composer.blocks.index.byId(block.id);
    if (block != null && current?.source != block.source) return;
    final start = emptyLine?.start ?? current?.end;
    if (start == null || start > source.length) return;
    final end = emptyLine?.end ?? start;
    if (end > source.length ||
        (emptyLine != null && source.substring(start, end).trim().isNotEmpty)) {
      return;
    }
    final newline = source.contains('\r\n') ? '\r\n' : '\n';
    final prefix = emptyLine == null ? newline * 2 : '';
    var suffix = '';
    if (emptyLine == null && source.substring(end).trim().isNotEmpty) {
      final following = RegExp(r'^[\r\n]*').stringMatch(source.substring(end))!;
      final breaks = '\n'.allMatches(following).length;
      if (breaks < 2) suffix = newline * (2 - breaks);
    }
    final caret = start + prefix.length + 1;
    composer.history.transact(() {
      composer.text.clearKeyboardPillSelection();
      composer.text.value = TextEditingValue(
        text: source.replaceRange(start, end, '$prefix/$suffix'),
        selection: TextSelection.collapsed(offset: caret),
      );
    });
    _hoveredId = null;
    final inserted = composer.blocks.index.atOffset(caret);
    if (inserted != null) composer.blocks.select(inserted.id);
    composer.focus.requestFocus();
    _revealSelection();
  }

  Widget _blockActions(ComposerBodyBlock? block, {TextRange? emptyLine}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DButton.iconOnly(
        key: ValueKey('composer-block-add-${emptyLine?.start ?? block?.id}'),
        tooltip: 'Add block',
        variant: DButtonVariant.transparentBackground,
        icon: const DIcon(DIcons.plus),
        hasPopup: true,
        onPressed:
            composer.blocks.enabled &&
                _drag == null &&
                !(block?.kind == ComposerBlockKind.code && !block!.movable)
            ? () => _addBlock(block, emptyLine)
            : null,
      ),
      if (emptyLine != null)
        DDragHandle<TextRange>(
          key: ValueKey('composer-block-empty-handle-${emptyLine.start}'),
          data: emptyLine,
          label: 'Empty paragraph actions',
          // There is no indexed block to move until this line has content.
          enabled: false,
          onPressed: null,
        )
      else if (block != null)
        _handle(block),
    ],
  );

  double? _dropY(ComposerDropTarget? target) {
    final box = _bounds.currentContext?.findRenderObject();
    if (target == null || box is! RenderBox || !box.hasSize) {
      return null;
    }
    return box.globalToLocal(Offset(0, target.y)).dy;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleGeometry();
    final desktop = !context.isTouch;
    final block = _activeBlock;
    final handleRect = _handleRect;
    final gutter =
        DControlStyle.scaledHeight(
              DControlSize.regular,
              MediaQuery.textScalerOf(context),
              context: context,
            ) *
            2 +
        DSpacing.controlGap;
    final line = _dropTop == null
        ? null
        : PositionedDirectional(
            start: gutter,
            end: 0,
            top: _dropTop,
            child: const FractionalTranslation(
              translation: Offset(0, -.5),
              child: DDropIndicator(),
            ),
          );
    return Focus(
      focusNode: _dragFocus,
      onKeyEvent: _key,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _scheduleGeometry();
          return false;
        },
        child: DDragRegion<_BlockDrag>(
          accepts: _validSnapshot,
          onMove: _moveDrag,
          onDrop: _drop,
          onLeave: _leaveDrag,
          child: MouseRegion(
            onHover: desktop && _drag == null
                ? (event) {
                    // Controls can extend below a short text line. Keep their
                    // block stable instead of selecting the blank line beneath.
                    final actions = _blockActionsKey.currentContext
                        ?.findRenderObject();
                    if (actions is RenderBox &&
                        actions.hasSize &&
                        (Offset.zero & actions.size).contains(
                          actions.globalToLocal(event.position),
                        )) {
                      return;
                    }
                    _hoverPosition = event.position;
                    _scheduleGeometry();
                    for (final item in composer.blocks.index.blocks) {
                      final rect = widget.blockRect(item);
                      if (rect != null &&
                          event.position.dy >= rect.top &&
                          event.position.dy <= rect.bottom) {
                        if (_hoveredId != item.id) {
                          setState(() => _hoveredId = item.id);
                          _scheduleGeometry();
                        }
                        break;
                      }
                    }
                  }
                : null,
            child: Stack(
              key: _bounds,
              fit: widget.expands ? StackFit.expand : StackFit.loose,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: desktop ? gutter : 0,
                  ),
                  child: widget.child,
                ),
                if (_drag != null && handleRect != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: handleRect.top - DSpacing.xs,
                    height: handleRect.height + DSpacing.xs * 2,
                    child: const DDragHighlight(),
                  ),
                if (desktop &&
                    (block != null || _emptyLine != null) &&
                    handleRect != null &&
                    (handleRect.top >= 0 ||
                        (_emptyLine != null && handleRect.bottom > 0)))
                  PositionedDirectional(
                    key: _blockActionsKey,
                    start: 0,
                    top: handleRect.top < 0 ? 0 : handleRect.top,
                    child: _blockActions(block, emptyLine: _emptyLine),
                  ),
                ?line,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
