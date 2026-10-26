import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'boards_data.dart';

/// A position among a column's cards with the dragged card left out.
typedef BoardDropSlot = ({int columnId, int index});

/// A dragged card released over a slot that moves it, with the [token] the
/// page hands back to [BoardCardDrag.settle] once the move has finished.
typedef BoardCardDrop = ({
  BoardCard card,
  BoardDropSlot slot,
  CardPlacement placement,
  Object token,
});

/// The height a placeholder takes when the dragged card was never laid out.
const _fallbackCardHeight = 56.0;

/// How far from a scrollable's edge a held card starts scrolling it.
const _autoScrollEdge = 40.0;

/// Flutter's auto scroller moves at most 20 points per step and takes
/// 1000 / scalar milliseconds per step, so 30 gives 600 points per second with
/// the pointer 20 points or less from the edge, a phone column in about 0.6 s,
/// easing to a stop 40 points in.
const _autoScrollVelocityScalar = 30.0;

/// One card drag over a board: the card in the air, the slot under the
/// pointer, and after a release, the move still settling. Columns and cards
/// register their geometry through [column] and [card], so a global pointer
/// resolves to a slot without the page knowing how the lists lay out. The
/// dragged card leaves its list for the whole session and a placeholder of its
/// height stands where it would land, so a drop looks settled before the
/// server confirms it.
final class BoardCardDrag extends ChangeNotifier {
  BoardCardDrag({required this.board});

  final BoardSnapshot? Function() board;
  final _columns = <int, BuildContext>{};
  final _cards = <int, BuildContext>{};
  final _scrollers = <ScrollableState, EdgeDraggingAutoScroller>{};
  _Session? _session;
  bool _resolveScheduled = false, _disposed = false;

  Widget column(int id, Widget child) =>
      _Registered(registry: _columns, id: id, child: child);

  Widget card(int id, Widget child) =>
      _Registered(registry: _cards, id: id, child: child);

  /// The card in the air or settling after a drop, which its column leaves out.
  int? get hiddenCardId => _session?.card.id;

  /// Where column [columnId] shows the placeholder, if anywhere: the slot under
  /// the pointer, the drop slot while a move settles, or the card's home while
  /// the pointer is over nothing it can land on.
  ({int index, double height})? placeholderIn(int columnId) {
    final session = _session;
    if (session == null) return null;
    final slot = session.slot ?? session.home;
    if (slot.columnId != columnId) return null;
    return (index: slot.index, height: session.height);
  }

  void start(BoardCard card) {
    final index =
        board()
            ?.column(card.columnId)
            ?.cards
            .indexWhere((other) => other.id == card.id) ??
        -1;
    _session = _Session(
      card,
      _rectOf(_cards[card.id])?.height ?? _fallbackCardHeight,
      (columnId: card.columnId, index: index < 0 ? 0 : index),
    );
    notifyListeners();
  }

  void move(Offset pointer) {
    final session = _session;
    if (session == null || session.pending) return;
    session.pointer = pointer;
    final target = _columnAt(pointer);
    _autoScroll(pointer, target);
    _place(session, target == null ? null : _slotIn(target, pointer, session));
  }

  void leave() {
    final session = _session;
    if (session == null || session.pending) return;
    session.pointer = null;
    _stopScrolling();
    _place(session, null);
  }

  /// A scroll moved the cards under the pointer. The viewport lays them out
  /// again during the frame, so the slot follows once that frame is done.
  void scrolled() {
    if (_resolveScheduled || _disposed || _session == null) return;
    _resolveScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveScheduled = false;
      final session = _session;
      final pointer = session?.pointer;
      if (_disposed || session == null || pointer == null || session.pending) {
        return;
      }
      _place(session, _slotAt(pointer, session));
    });
  }

  void _place(_Session session, BoardDropSlot? slot) {
    if (slot == session.slot) return;
    session.slot = slot;
    notifyListeners();
  }

  /// Marks the session pending and answers what to write, or null when the
  /// card was released over nothing or over its own place.
  BoardCardDrop? drop() {
    final session = _session;
    if (session == null || session.pending) return null;
    final board = this.board();
    final slot = session.slot;
    final target = slot == null ? null : board?.column(slot.columnId);
    if (slot == null || target == null) return null;
    final placement = boardDropPlacement(session.card, target, slot.index);
    if (placement == null) return null;
    session.droppedOn = board;
    _stopScrolling();
    notifyListeners();
    return (
      card: session.card,
      slot: slot,
      placement: placement,
      token: session,
    );
  }

  /// The source's drag ended. Flutter delivers the drop before this, so a
  /// pending session stays until its move settles.
  void end() {
    if (_session?.pending ?? false) return;
    _clear();
  }

  void settle(Object token) {
    if (identical(_session, token)) _clear();
  }

  /// A refreshed board already shows the card where the move put it.
  void boardChanged() {
    final dropped = _session?.droppedOn;
    if (dropped != null && !identical(board(), dropped)) _clear();
  }

  void cancel() => _clear();

  @override
  void dispose() {
    _disposed = true;
    _stopScrolling();
    super.dispose();
  }

  void _clear() {
    _stopScrolling();
    if (_session == null) return;
    _session = null;
    notifyListeners();
  }

  /// Scrolls whatever the pointer is near the edge of: the board sideways, the
  /// page when it scrolls as a whole, and the target column's card list.
  /// Scrollables the pointer has left are stopped and forgotten rather than
  /// reused, since a stopped scroller may still be finishing its last step.
  void _autoScroll(Offset pointer, BoardColumn? target) {
    final wanted = target == null
        ? const <ScrollableState>[]
        : _scrollablesFor(target).toList();
    for (final state in _scrollers.keys.toList()) {
      if (!wanted.contains(state)) _scrollers.remove(state)!.stopAutoScroll();
    }
    for (final state in wanted) {
      _feed(_scrollers.putIfAbsent(state, () => _scroller(state)), pointer);
    }
  }

  EdgeDraggingAutoScroller _scroller(ScrollableState state) {
    late final EdgeDraggingAutoScroller scroller;
    // The scroller keeps its target relative to the scroll origin, so after
    // each step it must be fed the pointer again or it stops.
    scroller = EdgeDraggingAutoScroller(
      state,
      velocityScalar: _autoScrollVelocityScalar,
      onScrollViewScrolled: () {
        final pointer = _session?.pointer;
        if (!identical(_scrollers[state], scroller) || pointer == null) return;
        _feed(scroller, pointer);
        scrolled();
      },
    );
    return scroller;
  }

  /// The auto scroller asserts its target fits inside the scrollable, so the
  /// edge zone shrinks to a short list's own size.
  void _feed(EdgeDraggingAutoScroller scroller, Offset pointer) {
    final box = scroller.scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    scroller.startAutoScrollIfNecessary(
      Rect.fromCenter(
        center: pointer,
        width: math.min(2 * _autoScrollEdge, box.size.width),
        height: math.min(2 * _autoScrollEdge, box.size.height),
      ),
    );
  }

  void _stopScrolling() {
    for (final scroller in _scrollers.values) {
      scroller.stopAutoScroll();
    }
    _scrollers.clear();
  }

  /// The nearest ancestors of the column on each axis are the board's own
  /// horizontal scrollable and the page's vertical one. The column's card list
  /// sits above its laid-out cards. Ancestor lookups rather than
  /// Scrollable.maybeOf, which would register a dependency.
  Iterable<ScrollableState> _scrollablesFor(BoardColumn target) sync* {
    final column = _columns[target.id];
    if (column != null && column.mounted) {
      final axes = <Axis>{};
      var ancestor = column.findAncestorStateOfType<ScrollableState>();
      while (ancestor != null && axes.length < Axis.values.length) {
        if (axes.add(axisDirectionToAxis(ancestor.axisDirection))) {
          yield ancestor;
        }
        ancestor = ancestor.context.findAncestorStateOfType<ScrollableState>();
      }
    }
    for (final card in target.cards) {
      final context = _cards[card.id];
      if (context == null || !context.mounted) continue;
      final list = context.findAncestorStateOfType<ScrollableState>();
      if (list != null &&
          axisDirectionToAxis(list.axisDirection) == Axis.vertical) {
        yield list;
        return;
      }
    }
  }

  BoardDropSlot? _slotAt(Offset pointer, _Session session) {
    final target = _columnAt(pointer);
    return target == null ? null : _slotIn(target, pointer, session);
  }

  BoardDropSlot? _slotIn(BoardColumn target, Offset pointer, _Session session) {
    final card = session.card;
    switch (target.order) {
      case BoardColumnOrder.unsupported:
        return null;
      case BoardColumnOrder.recency:
        return card.columnId == target.id
            ? null
            : (columnId: target.id, index: 0);
      case BoardColumnOrder.priority:
        var index = 0;
        int? afterLaidOut;
        for (final other in target.cards) {
          if (other.id == card.id) continue;
          // A lazy list lays out only the cards near its viewport.
          if (_rectOf(_cards[other.id]) case final rect?) {
            if (pointer.dy < rect.center.dy) {
              return (columnId: target.id, index: index);
            }
            afterLaidOut = index + 1;
          }
          index++;
        }
        return (columnId: target.id, index: afterLaidOut ?? index);
    }
  }

  BoardColumn? _columnAt(Offset pointer) {
    BoardColumn? nearest;
    var best = double.infinity;
    for (final column in board()?.columns ?? const <BoardColumn>[]) {
      final rect = _rectOf(_columns[column.id]);
      if (rect == null) continue;
      final distance = pointer.dx < rect.left
          ? rect.left - pointer.dx
          : pointer.dx > rect.right
          ? pointer.dx - rect.right
          : 0.0;
      if (distance < best) {
        best = distance;
        nearest = column;
      }
    }
    return nearest;
  }
}

final class _Session {
  _Session(this.card, this.height, this.home);
  final BoardCard card;
  final double height;
  final BoardDropSlot home;
  BoardDropSlot? slot;
  Offset? pointer;
  BoardSnapshot? droppedOn;
  bool get pending => droppedOn != null;
}

Rect? _rectOf(BuildContext? context) {
  if (context == null || !context.mounted) return null;
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

/// Records its context under [id] while mounted. A map rather than a GlobalKey
/// per id, so two cards sharing an id in a malformed payload cannot crash the
/// build; the later one wins and the earlier one leaves the map alone.
class _Registered extends StatefulWidget {
  const _Registered({
    required this.registry,
    required this.id,
    required this.child,
  });
  final Map<int, BuildContext> registry;
  final int id;
  final Widget child;

  @override
  State<_Registered> createState() => _RegisteredState();
}

class _RegisteredState extends State<_Registered> {
  @override
  void initState() {
    super.initState();
    widget.registry[widget.id] = context;
  }

  @override
  void didUpdateWidget(_Registered oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        !identical(oldWidget.registry, widget.registry)) {
      _forget(oldWidget);
      widget.registry[widget.id] = context;
    }
  }

  @override
  void dispose() {
    _forget(widget);
    super.dispose();
  }

  void _forget(_Registered registration) {
    if (identical(registration.registry[registration.id], context)) {
      registration.registry.remove(registration.id);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
