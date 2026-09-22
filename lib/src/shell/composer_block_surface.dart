import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/d_icons.dart';
import 'composer_blocks.dart';
import 'composer_controller.dart';
import 'composer_drop_geometry.dart';
import 'platform.dart';

class ComposerArrangeButton extends StatelessWidget {
  const ComposerArrangeButton({super.key, required this.composer});
  final ComposerController composer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([composer, composer.blocks]),
    builder: (context, _) => DButton.iconOnly(
      key: const ValueKey('composer-arrange'),
      tooltip: composer.blocks.arranging ? 'Done arranging' : 'Arrange blocks',
      variant: DButtonVariant.transparentBackground,
      icon: DIcon(composer.blocks.arranging ? DIcons.check : DIcons.list),
      onPressed:
          composer.blocks.enabled && composer.blocks.index.blocks.isNotEmpty
          ? () {
              if (composer.blocks.arranging) {
                composer.blocks.finishArranging();
                composer.focus.requestFocus();
              } else if (composer.blocks.startArranging()) {
                composer.activeEditor.focus.unfocus();
              }
            }
          : null,
    ),
  );
}

class _BlockDrag {
  const _BlockDrag(this.composer, this.id, this.revision);
  final ComposerController composer;
  final int id;
  final int revision;
}

typedef ComposerEmptyLine = ({TextRange range, Rect rect});

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
  final _outlineScroll = ScrollController();
  final _arrangeFocus = FocusNode(debugLabel: 'Composer arrangement');
  final _rows = <int, GlobalKey>{};
  late final AppLifecycleListener _lifecycle;
  _BlockDrag? _drag;
  int? _gap;
  int? _hoveredId;
  Offset? _hoverPosition;
  TextRange? _emptyLine;
  Offset? _pointer;
  Timer? _autoScroll;
  bool _wasArranging = false;
  bool _refreshScheduled = false;
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
    _outlineScroll.addListener(_scheduleGeometry);
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
      _rows.clear();
      _hoveredId = null;
    }
    _scheduleGeometry();
  }

  void _changed() {
    _hoverPosition = null;
    if (_drag case final drag?) {
      if (!_accepts(drag)) _cancelDrag();
    }
    if (composer.blocks.arranging && !_wasArranging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !composer.blocks.arranging) return;
        _arrangeFocus.requestFocus();
        final selected = _rows[composer.blocks.selected?.id]?.currentContext;
        if (selected != null) Scrollable.ensureVisible(selected, alignment: .4);
      });
    }
    _wasArranging = composer.blocks.arranging;
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
      final emptyLine = _drag == null && !composer.blocks.arranging
          ? widget.emptyLineAt(_hoverPosition) ??
                (block == null ? widget.emptyLineAt(null) : null)
          : null;
      final rect = composer.blocks.arranging
          ? null
          : emptyLine?.rect ?? (block == null ? null : widget.blockRect(block));
      final box = _bounds.currentContext?.findRenderObject();
      final localRect = rect == null || box is! RenderBox || !box.hasSize
          ? null
          : Rect.fromPoints(
              box.globalToLocal(rect.topLeft),
              box.globalToLocal(rect.bottomRight),
            );
      final dropTop = composer.blocks.arranging ? null : _dropY();
      if (localRect != _handleRect ||
          dropTop != _dropTop ||
          emptyLine?.range != _emptyLine) {
        setState(() {
          _emptyLine = emptyLine?.range;
          _handleRect = localRect;
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
    _outlineScroll.dispose();
    _arrangeFocus.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  Rect? _rect(ComposerBodyBlock block) {
    if (!composer.blocks.arranging) return widget.blockRect(block);
    final object = _rows[block.id]?.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize
        ? object.localToGlobal(Offset.zero) & object.size
        : null;
  }

  bool _validSnapshot(_BlockDrag drag) =>
      identical(drag.composer, composer) &&
      drag.revision == composer.blocks.revision &&
      composer.blocks.enabled;

  bool _accepts(_BlockDrag drag) =>
      identical(_drag, drag) && _validSnapshot(drag);

  ComposerDropGeometry get _dropGeometry =>
      ComposerDropGeometry(composer.blocks.index.blocks, _rect);

  int? _gapAt(Offset position) => _dropGeometry.gapAt(position);

  void _moveDrag(_BlockDrag drag, Offset position) {
    if (!_accepts(drag)) return;
    _pointer = position;
    final candidate = _gapAt(position);
    final source = composer.blocks.index.blocks.indexWhere(
      (block) => block.id == drag.id,
    );
    final gap =
        candidate != null &&
            (candidate == source ||
                candidate == source + 1 ||
                composer.blocks.index.move(drag.id, candidate) != null)
        ? candidate
        : null;
    if (_gap != gap) {
      setState(() => _gap = gap);
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
    final position = composer.blocks.arranging && widget.expands
        ? (_outlineScroll.hasClients ? _outlineScroll.position : null)
        : widget.editorScroll();
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
        _gap = null;
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
    final gap = _gapAt(position);
    if (gap != null) {
      if (composer.blocks.moveTo(
        gap,
        blockId: drag.id,
        expectedRevision: drag.revision,
      )) {
        _revealSelection();
      }
    }
    _cancelDrag();
    if (!composer.blocks.arranging) composer.focus.requestFocus();
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
      if (composer.blocks.arranging) {
        final row = _rows[block.id]?.currentContext;
        if (row != null) Scrollable.ensureVisible(row, alignment: .4);
      } else {
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
      }
      _scheduleGeometry();
    });
  }

  void _done() {
    _cancelDrag();
    composer.blocks.finishArranging();
    composer.focus.requestFocus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_drag != null) {
        _cancelDrag();
        if (!composer.blocks.arranging) composer.focus.requestFocus();
      } else if (composer.blocks.choosingDestination) {
        composer.blocks.cancelDestination();
      } else if (composer.blocks.arranging) {
        _done();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (composer.blocks.arranging &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        keyboard.isShiftPressed
            ? composer.history.redo()
            : composer.history.undo();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyY &&
          keyboard.isControlPressed) {
        composer.history.redo();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _handle(ComposerBodyBlock block) {
    final position = composer.blocks.index.blocks.indexOf(block);
    // Only the selected handle can have an open menu. Avoid reparsing the
    // entire draft for both actions on every row of a long outline.
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
          DDropdownMenuItem(
            onPressed: composer.blocks.enabled && block.movable
                ? () {
                    composer.blocks.select(block.id);
                    composer.blocks.chooseDestination();
                    composer.activeEditor.focus.unfocus();
                  }
                : null,
            child: const Text('Move to…'),
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, trigger) => DDragHandle<_BlockDrag>(
          key: ValueKey('composer-block-handle-${block.id}'),
          data: drag,
          label: '${block.label} actions',
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
            _arrangeFocus.requestFocus();
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
    composer.blocks.finishArranging();
    final inserted = composer.blocks.index.atOffset(caret);
    if (inserted != null) composer.blocks.select(inserted.id);
    composer.focus.requestFocus();
    _revealSelection();
  }

  Widget _blockActions(ComposerBodyBlock? block, {TextRange? emptyLine}) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: DSpacing.controlGap,
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

  Widget _outline() {
    final blocks = composer.blocks.index.blocks;
    final selected = composer.blocks.selected;
    final position = selected == null ? -1 : blocks.indexOf(selected);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
        child: Semantics(
          liveRegion: true,
          child: Text(
            composer.blocks.choosingDestination
                ? 'Choose a position for ${selected?.label.toLowerCase() ?? 'this block'}.'
                : '${selected?.label ?? 'Block'} · ${position + 1} of ${blocks.length}. Drag a handle or use the arrows.',
            style: TextStyle(color: DTokens.of(context).mutedForeground),
          ),
        ),
      ),
      for (var i = 0; i <= blocks.length; i++) ...[
        if (composer.blocks.choosingDestination && composer.blocks.canMoveTo(i))
          DButton(
            key: ValueKey('composer-block-place-$i'),
            variant: DButtonVariant.outline,
            onPressed: () => _move(i),
            label: Text(i == blocks.length ? 'Move to end' : 'Move here'),
          ),
        if (_gap == i) const DDropIndicator(),
        if (i < blocks.length)
          Padding(
            key: _rows.putIfAbsent(blocks[i].id, GlobalKey.new),
            padding: const EdgeInsets.symmetric(vertical: DSpacing.xs),
            child: DItem(
              variant: DItemVariant.outline,
              shape: DItemShape.card,
              selected: selected?.id == blocks[i].id,
              semanticLabel:
                  '${blocks[i].label}, block ${i + 1} of ${blocks.length}',
              onPressed: () => composer.blocks.select(blocks[i].id),
              children: [
                DItemContent(
                  children: [
                    DItemTitle(child: Text(blocks[i].label)),
                    DItemDescription(
                      child: Text(
                        blocks[i].movable
                            ? blocks[i].excerpt
                            : 'Keep in place: unsupported Markdown',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                _blockActions(blocks[i]),
              ],
            ),
          ),
      ],
    ];
    final toolbar = ListenableBuilder(
      listenable: composer.history,
      builder: (context, _) => Wrap(
        spacing: DSpacing.controlGap,
        runSpacing: DSpacing.controlGap,
        children: [
          DButton(onPressed: _done, label: const Text('Done')),
          DButton.iconOnly(
            tooltip: 'Move up',
            icon: const DIcon(DIcons.arrowUp),
            onPressed: composer.blocks.canMoveTo(position - 1)
                ? () => _move(position - 1)
                : null,
          ),
          DButton.iconOnly(
            tooltip: 'Move down',
            icon: const RotatedBox(
              quarterTurns: 2,
              child: DIcon(DIcons.arrowUp),
            ),
            onPressed: composer.blocks.canMoveTo(position + 2)
                ? () => _move(position + 2)
                : null,
          ),
          DButton.iconOnly(
            tooltip: 'Undo',
            icon: const DIcon(DIcons.arrowRotateLeft),
            onPressed: composer.isEditing && composer.history.canUndo
                ? composer.history.undo
                : null,
          ),
          DButton.iconOnly(
            tooltip: 'Redo',
            icon: Transform.flip(
              flipX: true,
              child: const DIcon(DIcons.arrowRotateLeft),
            ),
            onPressed: composer.isEditing && composer.history.canRedo
                ? composer.history.redo
                : null,
          ),
          if (composer.blocks.choosingDestination)
            DButton(
              onPressed: composer.blocks.cancelDestination,
              label: const Text('Cancel move'),
            )
          else
            DButton(
              onPressed: composer.blocks.enabled && selected?.movable == true
                  ? composer.blocks.chooseDestination
                  : null,
              label: const Text('Move to…'),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.expands ? MainAxisSize.max : MainAxisSize.min,
      children: [
        toolbar,
        if (widget.expands)
          Expanded(
            child: DScrollArea(
              controller: _outlineScroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          )
        else
          ...children,
      ],
    );
  }

  double? _dropY() {
    final gap = _gap;
    final box = _bounds.currentContext?.findRenderObject();
    if (gap == null || box is! RenderBox || !box.hasSize) {
      return null;
    }
    final y = _dropGeometry.gapY(gap);
    return y == null ? null : box.globalToLocal(Offset(0, y)).dy;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleGeometry();
    final arranging = composer.blocks.arranging;
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
        DSpacing.controlGap * 2;
    final line = arranging || _dropTop == null
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
      focusNode: _arrangeFocus,
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
            onHover: desktop && !arranging && _drag == null
                ? (event) {
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
                Offstage(
                  offstage: arranging,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: desktop ? gutter : 0,
                    ),
                    child: widget.child,
                  ),
                ),
                if (arranging) _outline(),
                if (!arranging && _drag != null && handleRect != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: handleRect.top - DSpacing.xs,
                    height: handleRect.height + DSpacing.xs * 2,
                    child: const DDragHighlight(),
                  ),
                if (!arranging &&
                    desktop &&
                    (block != null || _emptyLine != null) &&
                    handleRect != null &&
                    (handleRect.top >= 0 ||
                        (_emptyLine != null && handleRect.bottom > 0)))
                  PositionedDirectional(
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
