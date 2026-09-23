part of 'd_sidebar.dart';

/// An insertion into another sidebar section. [newIndex] is a gap in the
/// destination list; the source row has not been removed from that list.
@immutable
class DSidebarMove {
  const DSidebarMove({
    required this.sourceId,
    required this.targetId,
    required this.oldIndex,
    required this.newIndex,
  });

  final Object sourceId;
  final Object targetId;
  final int oldIndex;
  final int newIndex;
}

/// Connects reorderable menus sharing a sidebar viewport. Flutter continues
/// to own drag recognition, the proxy, within-section gaps and edge scrolling.
class DSidebarReorderScope extends StatefulWidget {
  const DSidebarReorderScope({super.key, required this.child});
  final Widget child;

  @override
  State<DSidebarReorderScope> createState() => _DSidebarReorderScopeState();
}

class _DSidebarReorderScopeState extends State<DSidebarReorderScope> {
  final targets = <_DSidebarDropTargetState>{};
  final _positions = <int, Offset>{};
  Object? _source;
  int? _index;
  int? _pointer;
  _DSidebarDropTargetState? _hovered;
  DSidebarMove? _move;
  bool _overOtherSection = false;

  void begin(Object source, int index, int? pointer) {
    _source = source;
    _index = index;
    _pointer = pointer;
    _update();
  }

  void _update() {
    final position = _positions[_pointer];
    final source = _source;
    _DSidebarDropTargetState? hovered;
    DSidebarMove? move;
    _overOtherSection = false;
    final viewport = context.findRenderObject();
    if (position != null &&
        source != null &&
        viewport is RenderBox &&
        (viewport.localToGlobal(Offset.zero) & viewport.size).contains(
          position,
        )) {
      for (final target in targets) {
        if (!target.mounted || target.widget.sectionId == source) continue;
        if (!target.contains(position)) continue;
        _overOtherSection = true;
        final candidate = target.moveAt(position, source, _index!);
        if (candidate != null) {
          hovered = target;
          move = candidate;
          break;
        }
      }
    }
    final previous = _hovered;
    final changed = previous != hovered || _move?.newIndex != move?.newIndex;
    _hovered = hovered;
    _move = move;
    if (changed) {
      previous?.refresh();
      if (hovered != previous) hovered?.refresh();
    }
  }

  VoidCallback? finish(Object? source, int? index) {
    if (source == null || source != _source || index != _index) return null;
    _update();
    final target = _hovered;
    final move = _move;
    final callback = target?.widget.onMove;
    final rejected = _overOtherSection;
    _clear();
    if (target == null || move == null || callback == null) {
      return rejected ? () {} : null;
    }
    return () {
      if (target.mounted && (target.widget.canMove?.call(move) ?? true)) {
        callback(move);
      }
    };
  }

  void _clear() {
    final previous = _hovered;
    _source = null;
    _index = null;
    _pointer = null;
    _hovered = null;
    _move = null;
    previous?.refresh();
  }

  @override
  Widget build(BuildContext context) => _SidebarReorderScope(
    state: this,
    child: Listener(
      onPointerDown: (event) => _positions[event.pointer] = event.position,
      onPointerMove: (event) {
        _positions[event.pointer] = event.position;
        if (_pointer == event.pointer) _update();
      },
      onPointerUp: (event) {
        // ReorderableList finishes later in this same pointer dispatch.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _positions.remove(event.pointer);
          if (mounted && _pointer == event.pointer) _clear();
        });
      },
      onPointerCancel: (event) {
        _positions.remove(event.pointer);
        if (_pointer == event.pointer) _clear();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          if (_source != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _update();
            });
          }
          return false;
        },
        child: widget.child,
      ),
    ),
  );
}

class _SidebarReorderScope extends InheritedWidget {
  const _SidebarReorderScope({required this.state, required super.child});
  final _DSidebarReorderScopeState state;
  static _DSidebarReorderScopeState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SidebarReorderScope>()?.state;
  @override
  bool updateShouldNotify(_SidebarReorderScope oldWidget) =>
      state != oldWidget.state;
}

/// A section header or row that accepts a link from another menu. A header
/// passes the section's length as [index] and sets [append] to true, allowing
/// collapsed and empty sections to accept drops. Rows choose either side of
/// their midpoint. Null [onMove] disables the target.
class DSidebarDropTarget extends StatefulWidget {
  const DSidebarDropTarget({
    super.key,
    required this.sectionId,
    required this.index,
    required this.child,
    required this.onMove,
    this.canMove,
    this.append = false,
  });

  final Object sectionId;
  final int index;
  final Widget child;
  final ValueChanged<DSidebarMove>? onMove;
  final bool Function(DSidebarMove move)? canMove;
  final bool append;

  @override
  State<DSidebarDropTarget> createState() => _DSidebarDropTargetState();
}

class _DSidebarDropTargetState extends State<DSidebarDropTarget> {
  _DSidebarReorderScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope?.targets.remove(this);
    _scope = _SidebarReorderScope.of(context);
    _scope?.targets.add(this);
  }

  @override
  void dispose() {
    _scope?.targets.remove(this);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  bool contains(Offset position) {
    final box = context.findRenderObject();
    return box is RenderBox &&
        box.attached &&
        box.hasSize &&
        (box.localToGlobal(Offset.zero) & box.size).contains(position);
  }

  DSidebarMove? moveAt(Offset position, Object source, int index) {
    if (widget.onMove == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.contains(position)) return null;
    final move = DSidebarMove(
      sourceId: source,
      targetId: widget.sectionId,
      oldIndex: index,
      newIndex:
          widget.index +
          (!widget.append && position.dy >= rect.center.dy ? 1 : 0),
    );
    return (widget.canMove?.call(move) ?? true) ? move : null;
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = _scope?._hovered == this;
    final before = !widget.append && _scope?._move?.newIndex == widget.index;
    final border = BorderSide(color: DTokens.of(context).primary, width: 2);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: highlighted
            ? Border(
                top: before ? border : BorderSide.none,
                bottom: before ? BorderSide.none : border,
              )
            : null,
      ),
      child: widget.child,
    );
  }
}
