import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/surface_depth.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_mobile_dock_geometry.dart';
import 'd_mobile_dock_growth.dart';
import 'd_mobile_dock_item.dart';
import 'd_mobile_dock_reorder.dart';
import 'd_scroll_chrome.dart';

/// One of a phone's places, as the bar shows it in its row and as the panel
/// the bar grows into shows it as a tile.
@immutable
class DMobileDockPlace {
  const DMobileDockPlace({
    required this.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
    this.semanticLabel,
    this.selected = false,
  });

  DMobileDockPlace.avatar({
    required this.key,
    required Widget face,
    required this.label,
    required this.onPressed,
    Color? ring,
    this.semanticLabel,
  }) : icon = _Face(face: face, ring: ring),
       badge = null,
       selected = false;

  /// The bar's item carries this key; the panel's tile carries
  /// [DMobileDock.tileKey] of it.
  final Key key;
  final Widget icon;
  final String label;
  final String? semanticLabel;
  final Widget? badge;

  /// Whether this is the page a person is on.
  final bool selected;
  final VoidCallback onPressed;
}

/// The ⋮ that grows the bar into its panel.
typedef DMobileDockMore = ({Widget icon, String label});

/// Where the page a person is on stands among a bar's places.
sealed class DMobileDockCurrent {
  const DMobileDockCurrent();

  /// No place is the current page.
  const factory DMobileDockCurrent.none() = DMobileDockNowhere;

  /// The current page is the place at [index], within the bar's columns.
  const factory DMobileDockCurrent.place(int index) = DMobileDockAtPlace;

  /// The current page is the place at [index], one the bar has no column
  /// for. It stands where the ⋮ would be, and pressing it grows the bar as
  /// the ⋮ does.
  const factory DMobileDockCurrent.overflowed(int index) =
      DMobileDockOverflowed;

  /// Where the selected one of [places] stands.
  factory DMobileDockCurrent.of(List<DMobileDockPlace> places) {
    final index = places.indexWhere((place) => place.selected);
    return index < 0
        ? const DMobileDockCurrent.none()
        : index < DMobileDockGeometry.placeColumns
        ? DMobileDockCurrent.place(index)
        : DMobileDockCurrent.overflowed(index);
  }
}

const _liftedTile = BorderRadius.all(
  Radius.circular(DMobileDockPanelGeometry.tileRadius),
);

final class DMobileDockNowhere extends DMobileDockCurrent {
  const DMobileDockNowhere();
}

final class DMobileDockAtPlace extends DMobileDockCurrent {
  const DMobileDockAtPlace(this.index)
    : assert(index >= 0 && index < DMobileDockGeometry.placeColumns);
  final int index;
}

final class DMobileDockOverflowed extends DMobileDockCurrent {
  const DMobileDockOverflowed(this.index)
    : assert(index >= DMobileDockGeometry.placeColumns);
  final int index;
}

/// How far the bar around a [DMobileDockAction] has grown into its panel,
/// so the action can become one of the places it then stands among, and
/// how the panel closes, so the action pressed puts it away first as the
/// places beside it do.
class DMobileDockGrowthScope extends InheritedWidget {
  const DMobileDockGrowthScope({
    super.key,
    required this.growth,
    required this.closePanel,
    required super.child,
  });

  final double growth;

  /// Nothing to close while the bar is a bar.
  final VoidCallback closePanel;

  static DMobileDockGrowthScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DMobileDockGrowthScope>();

  @override
  bool updateShouldNotify(DMobileDockGrowthScope oldWidget) =>
      growth != oldWidget.growth || closePanel != oldWidget.closePanel;
}

/// A phone's bar, cut as its [DMobileDockGeometry] says. Its places take one
/// column each of the row's four; the fourth holds the ⋮ for the places past
/// them, or the current page when it is one of those, and the action at the
/// row's end. The current place is marked by a short bar on the bar's top
/// edge over its column. Folded, the bar is a circle in the screen's
/// bottom-start corner.
///
/// The ⋮, or the page standing in its slot, grows the bar into a panel of
/// the places past its columns, [DMobileDockPanelGeometry] tall, risen from
/// the screen's foot over the whole app and dimming what is under it. The
/// bar rides the panel's top edge up to be its head, its places becoming
/// tiles like the panel's, the ⋮ fading and the action moving over to the
/// last column as a place in the accent. It settles open or closed on a
/// spring, and a place in the head or a tile in the panel closes it and then
/// goes there. The panel paints above the app's chrome as a sheet does, and
/// below the sheets and menus opened after it.
class DMobileDock extends StatefulWidget {
  const DMobileDock({
    super.key,
    required this.geometry,
    required this.places,
    required this.more,
    required this.collapsedDestination,
    this.action,
    this.collapsed = false,
    this.destinationsHidden = false,
    this.covered = false,
    this.onPanelChanged,
    this.onMoved,
  });

  final DMobileDockGeometry geometry;

  /// Every place in order; the bar shows the first
  /// [DMobileDockGeometry.placeColumns] and the panel holds the rest.
  final List<DMobileDockPlace> places;
  final DMobileDockMore more;
  final Widget collapsedDestination;
  final Widget? action;

  final bool collapsed;
  final bool destinationsHidden;

  /// Whether something in the app stands over the bar, a composer's sheet,
  /// that the panel must not stand over in turn. The panel is put away
  /// with the bar.
  final bool covered;

  /// Told once as the panel comes out and once as it goes, never during a
  /// build. A dock taken out of the tree while the panel is out, as when
  /// the sidebar takes the bar, tells as it is disposed that the panel is
  /// in: a listener that outlives the dock is not left thinking it out.
  final ValueChanged<bool>? onPanelChanged;

  /// Told, as a place let go in the open panel settles into its slot, that
  /// the place at [from] among [places] now stands at [to]; the next build
  /// is expected to bring the places in that order. Without it no place can
  /// be moved.
  final void Function(int from, int to)? onMoved;

  /// Around the folded circle's own button.
  static const circlePadding = 4.0;

  static const moreKey = ValueKey('mobile-mode-more');
  static const panelKey = ValueKey('mobile-dock-panel');
  static const dimKey = ValueKey('mobile-dock-dim');
  static const grabberKey = ValueKey('mobile-dock-grabber');

  /// The panel's tile for the place keyed [place].
  static Key tileKey(Key place) => ValueKey(('mobile-dock-tile', place));

  /// The place keyed [place] as it is drawn while a place is being moved:
  /// lifted under the finger, or sliding to make room.
  static Key movingKey(Key place) => ValueKey(('mobile-dock-moving', place));

  /// How the bar settles once let go: a touch past where it is going, open
  /// or closed, and back, as a sheet set down is.
  static const settleDuration = Duration(milliseconds: 460);
  static const settleCurve = Cubic(.3, 1.36, .5, 1);

  /// The dim's colour and the grid's opacity ease on their own time.
  static const fadeDuration = Duration(milliseconds: 300);
  static const dimOpacity = .32;

  /// A trackpad swipe settles this long after its last movement, and the
  /// momentum the system sends on after that, for this long, is the same
  /// swipe and must not start another.
  static const swipeRest = Duration(milliseconds: 180);
  static const swipeSpent = Duration(milliseconds: 160);

  @override
  State<DMobileDock> createState() => _DMobileDockState();
}

/// How far the bar has grown into its panel, and what is moving it.
sealed class _Growth {
  const _Growth();
}

/// The bar alone; the panel is not in the tree.
final class _Closed extends _Growth {
  const _Closed();
}

/// Under a finger, from where it was when the drag began, with how far the
/// finger has pulled and where it has been lately.
final class _Dragging extends _Growth {
  _Dragging({required this.start, required this.finger});
  final double start;

  /// The recognizer whose finger has it, or none for a trackpad swipe. One
  /// drag owns the growth at a time: another finger landing on the bar or
  /// the panel meanwhile moves nothing.
  final _GrowDragRecognizer? finger;

  /// Upward, summed from the finger's moves rather than read from where
  /// the finger is: a second finger on the same bar stands in for the
  /// first from wherever it landed.
  double pulled = 0;
  final trail = DMobileDockDragTrail();
}

/// Pressed or let go, on its spring to open or closed.
final class _Settling extends _Growth {
  const _Settling({required this.opening});
  final bool opening;
}

final class _Open extends _Growth {
  const _Open();
}

/// A place being moved in the open panel, or none. Holding a place still,
/// with the timer running, is the recognizer's own state.
sealed class _Reorder {
  const _Reorder();
}

final class _Still extends _Reorder {
  const _Still();
}

/// A place on the move: the one keyed [key], from [from] among [keys], the
/// places as they stood at the lift, over the panel's [slots], from its
/// top-start corner and taken once at the lift, bound for the slot [to].
/// The slots are fixed; which place stands in each is what changes.
sealed class _Moving extends _Reorder {
  _Moving({
    required this.key,
    required this.keys,
    required this.from,
    required this.to,
    required this.slots,
  });
  final Key key;
  final List<Key> keys;
  final int from;
  int to;
  final List<Rect> slots;

  /// Which place stands in each slot now.
  List<Key> get order => DMobileDockReorder.moved(keys, from, to);
}

/// Lifted under [finger], grabbed [grab] in from its tile's top-start corner,
/// the finger [at] now.
final class _Lifted extends _Moving {
  _Lifted({
    required this.finger,
    required this.grab,
    required this.at,
    required super.key,
    required super.keys,
    required super.from,
    required super.slots,
  }) : super(to: from);
  final _LiftRecognizer finger;
  final Offset grab;
  Offset at;

  /// Where the tile stands under the finger.
  Rect get rect => (at - grab) & slots[from].size;
}

/// Let go at [letGo], settling into its slot.
final class _Dropped extends _Moving {
  _Dropped(_Lifted lifted)
    : letGo = lifted.rect,
      super(
        key: lifted.key,
        keys: lifted.keys,
        from: lifted.from,
        to: lifted.to,
        slots: lifted.slots,
      );
  final Rect letGo;
}

/// Repaints the moving places as the finger goes, with no build of the dock.
final class _Repaint extends ChangeNotifier {
  void call() => notifyListeners();
}

class _DMobileDockState extends State<DMobileDock>
    with TickerProviderStateMixin {
  // Unbounded, so the spring can settle a touch past open or closed and back.
  late final _growth = AnimationController.unbounded(vsync: this);
  late final _fade = AnimationController(vsync: this);

  // A place let go, on its way into its slot.
  late final _land = AnimationController(vsync: this);
  final _repaint = _Repaint();
  _Reorder _reorder = const _Still();

  // A landing that was interrupted must not end a later move.
  int _landing = 0;
  final _portal = OverlayPortalController();
  final _barKey = GlobalKey(debugLabel: 'mobile-dock-bar');
  // The surface drops its decoration while the panel is out, which changes
  // the tree above its content; the key carries the content's state across.
  final _surfaceContentKey = GlobalKey(debugLabel: 'mobile-dock-surface');
  final _moreFocus = FocusNode(debugLabel: 'mobile-dock-more');
  final _panelFocus = FocusScopeNode(debugLabel: 'mobile-dock-panel');
  final _firstTile = FocusNode(debugLabel: 'mobile-dock-first-tile');

  /// The place [_firstTile] is on: the grid's first as the panel took the
  /// focus, and that place still wherever the moves take it.
  Key? _firstTileKey;

  /// What had the focus as the panel took it, to have it back as the panel
  /// closes.
  FocusNode? _focusBefore;
  _Growth _phase = const _Closed();

  // A settle that was interrupted must not report its end as the panel's.
  int _settle = 0;
  bool _reportedOut = false;

  // A trackpad swipe under way: how far it has pushed, upward positive,
  // the rest that settles it, and until when its momentum is ignored.
  double _swipePushed = 0;
  Timer? _swipeRest;
  Duration? _swipeSpentUntil;

  bool get _out => _phase is! _Closed;

  /// With nothing past the bar's columns, or the bar put away, there is
  /// nothing to grow into.
  bool get _grows =>
      widget.places.length > DMobileDockGeometry.placeColumns &&
      !widget.collapsed &&
      !widget.destinationsHidden &&
      !widget.covered;

  List<DMobileDockPlace> get _rest =>
      widget.places.skip(DMobileDockGeometry.placeColumns).toList();

  int get _tiles => _rest.length;

  @override
  void didUpdateWidget(DMobileDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_out && !_grows) _putAway();
    // A move is of the places as they stood at the lift, and a place let go
    // lands among them in their new order. Any other order under it, a
    // place come or gone or the same places put otherwise, as a stored
    // order read late or a screen reader's move brings them, is not the one
    // the person took hold of: the move ends with nothing told.
    if (_reorder case final _Moving moving) {
      final keys = [for (final place in widget.places) place.key];
      final stands = switch (moving) {
        _Lifted() => [moving.keys],
        _Dropped() => [moving.keys, moving.order],
      };
      if (!stands.any((order) => listEquals(order, keys))) _cancelMove();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read first, so the chrome's change is a dependency from the start.
    final away = DScrollChrome.footerAwayOf(context);
    if (away && _out) _putAway();
  }

  @override
  void dispose() {
    // Gone while out, the panel is in. Said now rather than from a
    // microtask, before whoever listens can be disposed after the dock.
    if (_reportedOut) {
      _reportedOut = false;
      widget.onPanelChanged?.call(false);
    }
    _swipeRest?.cancel();
    _growth.dispose();
    _fade.dispose();
    _land.dispose();
    _repaint.dispose();
    _moreFocus.dispose();
    _panelFocus.dispose();
    _firstTile.dispose();
    super.dispose();
  }

  /// A finger takes the growth over from a trackpad swipe, and never from
  /// another finger. A place lifted to be moved has the drag suspended.
  void _dragStart(_GrowDragRecognizer finger) {
    if (!_grows || _reorder is! _Still) return;
    if (_phase case _Dragging(finger: _?)) return;
    _settle++;
    _swipeRest?.cancel();
    _swipeRest = null;
    _swipePushed = 0;
    _growth.stop();
    _fade.stop();
    final start = _growth.value.clamp(0.0, 1.0);
    final wasOut = _out;
    setState(() => _phase = _Dragging(start: start, finger: finger));
    if (!wasOut) _portal.show();
    _reportOut();
  }

  void _dragUpdate(_GrowDragRecognizer finger, DragUpdateDetails details) {
    if (_phase case final _Dragging drag when drag.finger == finger) {
      final panel = widget.geometry.panel(tiles: _tiles);
      final travel = math.max(1.0, panel.reveal);
      drag.pulled -= details.delta.dy;
      final growth = (drag.start + drag.pulled / travel).clamp(0.0, 1.0);
      _growth.value = growth;
      _fade.value = growth;
      // Where a finger that had pulled this far would be, down the screen.
      drag.trail.add(-drag.pulled, details.sourceTimeStamp ?? Duration.zero);
    }
  }

  void _dragEnd(_GrowDragRecognizer finger) {
    if (_phase case final _Dragging drag when drag.finger == finger) {
      _grow(
        DMobileDockDrag.settlesOpen(
          start: drag.start,
          at: _growth.value,
          velocity: drag.trail.velocity,
        ),
      );
    }
  }

  /// Takes a vertical drag on [child] while the bar is open, and none once
  /// it is folded to its circle. The detector stays in the tree either way,
  /// so folding does not rebuild what it wraps.
  Widget _draggable(BuildContext context, Widget child) {
    final view = View.of(context);
    final screenBottom = view.physicalSize.height / view.devicePixelRatio;
    return _swipeable(
      RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: widget.collapsed
            ? const {}
            : {
                _GrowDragRecognizer:
                    GestureRecognizerFactoryWithHandlers<_GrowDragRecognizer>(
                      _GrowDragRecognizer.new,
                      (recognizer) {
                        recognizer.homeBandTop =
                            screenBottom - DMobileDockDrag.homeBand;
                        recognizer.dragStartBehavior = DragStartBehavior.down;
                        recognizer.onStart = (_) => _dragStart(recognizer);
                        recognizer.onUpdate = (details) =>
                            _dragUpdate(recognizer, details);
                        recognizer.onEnd = (_) => _dragEnd(recognizer);
                        recognizer.onCancel = () => _dragEnd(recognizer);
                      },
                    ),
              },
        child: child,
      ),
    );
  }

  /// A trackpad swipe over the bar, the panel or the dim grows and shrinks
  /// the bar as a sheet's does: [push] upward positive, at the event's
  /// [at]. Settled once it rests, by the way the whole swipe went.
  void _swipe(double push, Duration at) {
    if (!_grows || push == 0 || _reorder is! _Still) return;
    if (_swipeSpentUntil case final until? when at < until) {
      _swipeSpentUntil = at + DMobileDock.swipeSpent;
      return;
    }
    switch (_phase) {
      case _Dragging(finger: _?):
        return;
      case _Settling():
        _settle++;
        _growth.stop();
        _fade.stop();
      case _Closed() || _Open() || _Dragging():
        break;
    }
    final panel = widget.geometry.panel(tiles: _tiles);
    final travel = math.max(1.0, panel.reveal);
    final start = _growth.value.clamp(0.0, 1.0);
    final growth = (start + push / travel).clamp(0.0, 1.0);
    final wasOut = _out;
    if (!wasOut && growth == 0) return;
    if (_phase is! _Dragging) {
      setState(() => _phase = _Dragging(start: start, finger: null));
    }
    _swipePushed += push;
    _growth.value = growth;
    _fade.value = growth;
    if (!wasOut) _portal.show();
    _reportOut();
    _swipeRest?.cancel();
    _swipeRest = Timer(DMobileDock.swipeRest, () {
      _swipeRest = null;
      if (!mounted || _phase is! _Dragging) return;
      final opens = DMobileDockDrag.swipeSettlesOpen(
        pushed: _swipePushed,
        at: _growth.value,
      );
      _swipePushed = 0;
      _swipeSpentUntil = at + DMobileDock.swipeRest + DMobileDock.swipeSpent;
      _grow(opens);
    });
  }

  /// Takes trackpad swipes and wheel turns over [child]. Fingers moving up
  /// the trackpad, as a wheel turned down, push the bar up.
  Widget _swipeable(Widget child) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerPanZoomUpdate: (event) =>
        _swipe(-event.localPanDelta.dy, event.timeStamp),
    onPointerSignal: (event) {
      if (event is PointerScrollEvent) {
        _swipe(event.scrollDelta.dy, event.timeStamp);
      }
    },
    child: child,
  );

  void _grow(bool opening) {
    if (opening ? !_grows : !_out) return;
    _swipeRest?.cancel();
    _swipeRest = null;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final wasOut = _out;
    final token = ++_settle;
    setState(() {
      _cancelMove();
      _phase = _Settling(opening: opening);
    });
    if (!wasOut) _portal.show();
    _reportOut();
    if (opening) _takeFocus();
    _fade.animateTo(
      opening ? 1 : 0,
      duration: reduced ? Duration.zero : DMobileDock.fadeDuration,
      curve: Curves.ease,
    );
    _growth
        .animateTo(
          opening ? 1 : 0,
          duration: reduced ? Duration.zero : DMobileDock.settleDuration,
          curve: DMobileDock.settleCurve,
        )
        .whenCompleteOrCancel(() {
          if (!mounted || token != _settle) return;
          _settled(opening);
        });
  }

  void _close() => _grow(false);

  /// The focus moves into the panel, to its first tile, once the panel is
  /// meant to be open: pressed open, or let go to settle open. Not under a
  /// finger that may yet set it back down, which would take the focus, and
  /// the keyboard, from what a person is typing in.
  void _takeFocus() {
    if (_panelFocus.hasFocus) return;
    _focusBefore = FocusManager.instance.primaryFocus;
    _firstTileKey = _rest.first.key;
    _firstTile.requestFocus();
  }

  /// What had the focus takes it back. Nothing in particular had it, or it
  /// has gone since, and the ⋮ takes it, or the page standing in its slot
  /// that opened the panel in the ⋮'s stead.
  void _giveFocusBack() {
    final before = _focusBefore;
    _focusBefore = null;
    final target =
        before != null &&
            before is! FocusScopeNode &&
            before.enclosingScope != null &&
            before.canRequestFocus
        ? before
        : _moreFocus;
    target.requestFocus();
  }

  void _settled(bool opening) {
    if (opening) {
      setState(() => _phase = const _Open());
      return;
    }
    final hadFocus = _panelFocus.hasFocus;
    setState(() => _phase = const _Closed());
    _portal.hide();
    _reportOut();
    if (hadFocus) _giveFocusBack();
  }

  /// Put away with the bar, as by the composer it opened, it comes back as
  /// a bar, not as the panel it was. The bar is told during a build, so
  /// the overlay empties now and leaves once the frame is drawn.
  void _putAway() {
    _settle++;
    _swipeRest?.cancel();
    _swipeRest = null;
    _swipePushed = 0;
    _growth
      ..stop()
      ..value = 0;
    _fade
      ..stop()
      ..value = 0;
    _cancelMove();
    _phase = const _Closed();
    // Whatever took the bar away has the focus to give.
    _focusBefore = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_out) _portal.hide();
    });
    _reportOut();
  }

  /// The panel's slots for its places as it stands open, [width] across,
  /// from its top-start corner.
  List<Rect> _slots(double width) => widget.geometry
      .panel(tiles: _tiles)
      .placeRects(
        places: widget.places.length,
        width: width,
        action: widget.action != null,
      );

  /// A place can be lifted at [at], in the panel's coordinates, while the
  /// panel is open with nothing on the move and a place stands there.
  bool _canLift(Offset at, double width) =>
      _phase is _Open &&
      _reorder is _Still &&
      widget.onMoved != null &&
      _slots(width).any((slot) => slot.contains(at));

  void _lift(_LiftRecognizer finger, Offset at, double width) {
    if (!_canLift(at, width)) return;
    final slots = _slots(width);
    final from = slots.indexWhere((slot) => slot.contains(at));
    unawaited(HapticFeedback.lightImpact());
    setState(
      () => _reorder = _Lifted(
        finger: finger,
        grab: at - slots[from].topLeft,
        at: at,
        key: widget.places[from].key,
        keys: [for (final place in widget.places) place.key],
        from: from,
        slots: slots,
      ),
    );
  }

  /// The tile follows the finger, and the slot the finger is well inside,
  /// if any, is where the place is bound.
  void _follow(_LiftRecognizer finger, Offset at) {
    if (_reorder case final _Lifted lifted when lifted.finger == finger) {
      lifted.at = at;
      lifted.to = DMobileDockReorder.slotAt(lifted.slots, at) ?? lifted.to;
      _repaint();
    }
  }

  /// Let go, the place settles into its slot from where it is, and the move
  /// is told so the next build brings the places in their new order; the
  /// hidden places show again, so ordered, once it has landed.
  void _drop(_LiftRecognizer finger) {
    if (_reorder case final _Lifted lifted when lifted.finger == finger) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      final token = ++_landing;
      setState(() => _reorder = _Dropped(lifted));
      _land.value = 0;
      _land
          .animateTo(
            1,
            duration: reduced ? Duration.zero : DMobileDockReorder.settle,
            curve: DMobileDockReorder.curve,
          )
          .whenCompleteOrCancel(() {
            if (!mounted || token != _landing) return;
            setState(() => _reorder = const _Still());
          });
      if (lifted.to != lifted.from) {
        widget.onMoved?.call(lifted.from, lifted.to);
      }
    }
  }

  /// How a screen reader, which cannot press and hold, moves the place at
  /// [index]: a slot earlier or later, told at once. Nothing while the bar
  /// is a bar, as a hold lifts nothing then either.
  Map<CustomSemanticsAction, VoidCallback>? _moveActions(
    BuildContext context,
    int index,
  ) {
    final onMoved = widget.onMoved;
    if (!_out || onMoved == null) return null;
    final l10n = context.l10n;
    return {
      if (index > 0)
        CustomSemanticsAction(label: l10n.moveEarlier): () =>
            onMoved(index, index - 1),
      if (index < widget.places.length - 1)
        CustomSemanticsAction(label: l10n.moveLater): () =>
            onMoved(index, index + 1),
    };
  }

  /// A move ends with nothing told when the panel goes under it or its
  /// places change: the place is back where it was. Called where a build
  /// follows.
  void _cancelMove() {
    if (_reorder is _Still) return;
    _landing++;
    _land.stop();
    _reorder = const _Still();
  }

  // Whoever listens may rebuild on the news, so it waits for the build that
  // may be under way, and says only what is still true by then.
  void _reportOut() {
    scheduleMicrotask(() {
      if (!mounted || _reportedOut == _out) return;
      _reportedOut = _out;
      widget.onPanelChanged?.call(_out);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bar = KeyedSubtree(
      key: _barKey,
      child: AnimatedBuilder(
        animation: _growth,
        builder: (context, _) => _bar(context),
      ),
    );
    // The slot keeps the bar's room while the bar is away in the overlay,
    // so the page under it does not move.
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _grown,
      child: SizedBox(
        height: widget.geometry.barHeight,
        child: _out
            ? null
            : Align(
                alignment: AlignmentDirectional.bottomStart,
                // The page's lists thin under the bar from its top margin's
                // edge to the foot, as far as it reaches open or folded.
                child: DScrollFootCover(
                  margin: widget.geometry.margin.vertical,
                  child: bar,
                ),
              ),
      ),
    );
  }

  /// The layer over the whole app while the panel is out: the dim, the
  /// panel risen from the screen's foot, and the bar over both, in the
  /// slot's own place and lifted as far as it has grown.
  Widget _grown(BuildContext context, OverlayChildLayoutInfo info) {
    if (!_out) return const SizedBox.shrink();
    final slot = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    final panel = widget.geometry.panel(tiles: _tiles);
    return PopScope(
      // The system back closes the panel, as Escape does.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _grow(false);
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_growth, _fade]),
        builder: (context, _) => _layer(context, slot, panel),
      ),
    );
  }

  /// The layer as it stands at this growth.
  Widget _layer(
    BuildContext context,
    Rect slot,
    DMobileDockPanelGeometry panel,
  ) {
    final geometry = widget.geometry;
    // The screen's edges, which the bar's margins keep it from: the
    // panel runs between them, up from the foot.
    final margin = geometry.margin;
    final left = slot.left - margin.start;
    final width = slot.width + margin.horizontal;
    final foot = slot.bottom + margin.bottom;
    final tokens = DTokens.of(context);
    final topRadius = BorderRadius.vertical(
      top: Radius.circular(geometry.topRadius),
    );
    final bar = KeyedSubtree(
      key: _barKey,
      child: AnimatedBuilder(
        animation: _growth,
        builder: (context, _) => _bar(context),
      ),
    );
    final growth = _growth.value;
    final fade = _fade.value;
    // The panel's box, where a lifted place and the places it displaces are
    // drawn, over the bar.
    final box = Rect.fromLTWH(left, foot - panel.height, width, panel.height);
    final tiles = [
      for (final (index, place) in _rest.indexed)
        _tile(
          panel.tileRect(index, width),
          _whileStill(
            DMobileDockItem(
              key: DMobileDock.tileKey(place.key),
              growth: 1,
              focusNode: place.key == _firstTileKey ? _firstTile : null,
              icon: place.icon,
              label: place.label,
              semanticLabel: place.semanticLabel,
              badge: place.badge,
              selected: place.selected,
              customSemanticsActions: _moveActions(
                context,
                DMobileDockGeometry.placeColumns + index,
              ),
              onPressed: () {
                _grow(false);
                place.onPressed();
              },
            ),
          ),
          key: _slotKey(place.key),
        ),
    ];
    final body = DecoratedBox(
      key: DMobileDock.panelKey,
      decoration: BoxDecoration(
        color: tokens.wellFill,
        borderRadius: topRadius,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            top: panel.grabberTop(growth),
            start: 0,
            end: 0,
            child: Center(
              child: ExcludeSemantics(
                child: DecoratedBox(
                  key: DMobileDock.grabberKey,
                  decoration: BoxDecoration(
                    color: tokens.subtleMark,
                    borderRadius: BorderRadius.circular(
                      DMobileDockPanelGeometry.grabberRadius,
                    ),
                  ),
                  child: SizedBox.fromSize(
                    size: DMobileDockPanelGeometry.grabberSize,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: DMobileDockPanelGeometry.gridOpacity(fade),
              child: Stack(clipBehavior: Clip.none, children: tiles),
            ),
          ),
        ],
      ),
    );
    // The head is the panel's too: the keyboard goes round its places, the
    // action, the grid and you, and Escape closes it from any of them.
    return BlockSemantics(
      child: Semantics(
        container: true,
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: context.l10n.places,
        onDismiss: () => _grow(false),
        child: FocusScope(
          node: _panelFocus,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  _grow(false),
            },
            child: _liftable(
              context,
              box,
              Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _grow(false),
                      onPointerPanZoomUpdate: (event) =>
                          _swipe(-event.localPanDelta.dy, event.timeStamp),
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          _swipe(event.scrollDelta.dy, event.timeStamp);
                        }
                      },
                      child: ExcludeSemantics(
                        child: ColoredBox(
                          key: DMobileDock.dimKey,
                          color: Colors.black.withValues(
                            alpha: DMobileDock.dimOpacity * fade,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: left,
                    width: width,
                    top: foot - (panel.height - panel.clipInset(growth)),
                    height: panel.height - panel.clipInset(growth),
                    child: ClipRRect(
                      borderRadius: topRadius,
                      child: OverflowBox(
                        alignment: Alignment.bottomCenter,
                        minHeight: panel.height,
                        maxHeight: panel.height,
                        child: _draggable(context, body),
                      ),
                    ),
                  ),
                  Positioned(
                    left: slot.left,
                    top: slot.top - panel.barRise(growth),
                    width: slot.width,
                    height: slot.height,
                    child: bar,
                  ),
                  if (_reorder case final _Moving moving)
                    _movingPlaces(context, moving, box),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A tile keeps its own height, as the bar's places do: larger text grows
  // it past its row.
  Widget _tile(Rect rect, Widget child, {Key? key}) => PositionedDirectional(
    key: key,
    start: rect.left,
    top: rect.top,
    width: rect.width,
    child: child,
  );

  /// The slot a place's tile stands in, in the grid or in the head.
  static Key _slotKey(Key place) => ValueKey(('mobile-dock-slot', place));

  /// A place's own tile keeps its room, its keys, its semantics and the
  /// focus, and shows nothing, while a place is on the move: the moving
  /// places are drawn in its stead. The focus stays so Escape, bound inside
  /// the panel's scope, still closes it from the tile that had it.
  Widget _whileStill(Widget child) => Visibility(
    visible: _reorder is _Still,
    maintainState: true,
    maintainAnimation: true,
    maintainSize: true,
    maintainSemantics: true,
    maintainFocusability: true,
    child: child,
  );

  /// Takes a hold on a place of the open panel, within [box], the panel's
  /// own box in [child]'s coordinates, and hands the dock the finger in the
  /// panel's own, from its top-start corner.
  Widget _liftable(BuildContext context, Rect box, Widget child) {
    final ltr = Directionality.of(context) == TextDirection.ltr;
    Offset inPanel(Offset local) {
      final at = local - box.topLeft;
      return Offset(ltr ? at.dx : box.width - at.dx, at.dy);
    }

    return RawGestureDetector(
      excludeFromSemantics: true,
      gestures: {
        _LiftRecognizer: GestureRecognizerFactoryWithHandlers<_LiftRecognizer>(
          _LiftRecognizer.new,
          (recognizer) {
            recognizer.canLift = (local) => _canLift(inPanel(local), box.width);
            recognizer.onLift = (finger, local) =>
                _lift(finger, inPanel(local), box.width);
            recognizer.onFollow = (finger, local) =>
                _follow(finger, inPanel(local));
            recognizer.onDrop = _drop;
          },
        ),
      },
      child: child,
    );
  }

  /// The places as they stand while one is moved, drawn in the panel's
  /// [box] over the bar: the displaced sliding to their slots, and the
  /// lifted one under the finger, grown and raised, then settling into its
  /// slot once let go. They are drawn only; the places' own tiles, hidden
  /// under them, keep the keys and the focus.
  Widget _movingPlaces(BuildContext context, _Moving moving, Rect box) {
    final tokens = DTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final byKey = {for (final place in widget.places) place.key: place};
    Widget copy(DMobileDockPlace place) => DMobileDockItem(
      growth: 1,
      icon: place.icon,
      label: place.label,
      semanticLabel: place.semanticLabel,
      badge: place.badge,
      selected: place.selected,
      onPressed: () {},
    );
    return Positioned.fromRect(
      rect: box,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: Listenable.merge([_repaint, _land]),
            builder: (context, _) {
              final landed = _land.value;
              final rect = switch (moving) {
                _Lifted() => moving.rect,
                _Dropped(:final letGo) => Rect.lerp(
                  letGo,
                  moving.slots[moving.to],
                  landed,
                )!,
              };
              final scale = switch (moving) {
                _Lifted() => DMobileDockReorder.scale,
                _Dropped() => lerpDouble(DMobileDockReorder.scale, 1, landed)!,
              };
              final lifted = byKey[moving.key];
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final (index, key) in moving.order.indexed)
                    if (key != moving.key)
                      if (byKey[key] case final place?)
                        AnimatedPositionedDirectional(
                          key: DMobileDock.movingKey(key),
                          start: moving.slots[index].left,
                          top: moving.slots[index].top,
                          width: moving.slots[index].width,
                          height: moving.slots[index].height,
                          duration: reduced
                              ? Duration.zero
                              : DMobileDockReorder.slide,
                          curve: DMobileDockReorder.curve,
                          child: copy(place),
                        ),
                  if (lifted != null)
                    PositionedDirectional(
                      key: DMobileDock.movingKey(moving.key),
                      start: rect.left,
                      top: rect.top,
                      width: rect.width,
                      height: rect.height,
                      child: Transform.scale(
                        scale: scale,
                        child: switch (moving) {
                          _Lifted() => CustomPaint(
                            painter: const DSurfaceEdges(
                              shadows: [DMobileDockReorder.shadow],
                            ).castPainter(_liftedTile),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: tokens.raisedBackground,
                                borderRadius: _liftedTile,
                              ),
                              child: copy(lifted),
                            ),
                          ),
                          _Dropped() => copy(lifted),
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The bar: its row of places, the ⋮ or the current page past the columns
  /// in the fourth, and the action at the end, on the surface that folds to
  /// a circle. Grown, the row is the panel's head.
  Widget _bar(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final geometry = widget.geometry;
      final reduced = MediaQuery.disableAnimationsOf(context);
      final collapsed = widget.collapsed;
      final hidden = widget.destinationsHidden;
      final round = geometry.circle;
      final navOpacity = (collapsed ? 0.0 : 1.0);
      final revealOpacity = (collapsed ? 1.0 : 0.0);
      final radius = BorderRadius.circular(999);
      final tokens = DTokens.of(context);
      final out = _out;
      final growth = _growth.value;
      final grown = growth.clamp(0.0, 1.0);
      // Grown, the head's tiles stand past the row's edges; the row is then
      // as tall as they are, centred where it was, so the whole of each can
      // be pressed.
      final rowHeight = out ? geometry.tileHeight : geometry.rowHeight;
      final overflow = out ? geometry.headOverflow : 0.0;
      final padding = geometry.padding;
      final rowPadding = EdgeInsetsDirectional.fromSTEB(
        padding.start,
        padding.top - overflow,
        padding.end,
        padding.bottom - overflow,
      );

      final well = tokens.wellFill;
      final places = widget.places;
      final shown = places.take(DMobileDockGeometry.placeColumns).toList();
      final current = DMobileDockCurrent.of(places);
      final tail = places.length <= DMobileDockGeometry.placeColumns
          ? DMobileDockTail.none
          : switch (current) {
              DMobileDockOverflowed() => DMobileDockTail.page,
              DMobileDockNowhere() ||
              DMobileDockAtPlace() => DMobileDockTail.more,
            };
      final hasAction = widget.action != null;
      final atRest = geometry.rowSlots(
        constraints.maxWidth,
        places: shown.length,
        tail: tail,
        action: hasAction,
      );
      // Grown, a page standing where the ⋮ was gives its room back and the
      // three return to their columns.
      final grownSlots = tail == DMobileDockTail.page
          ? geometry.rowSlots(
              constraints.maxWidth,
              places: shown.length,
              tail: DMobileDockTail.more,
              action: hasAction,
            )
          : atRest;
      DMobileDockSlot between(DMobileDockSlot from, DMobileDockSlot to) => (
        start: lerpDouble(from.start, to.start, grown)!,
        width: lerpDouble(from.width, to.width, grown)!,
      );
      final placeSlots = [
        for (final (index, slot) in atRest.places.indexed)
          between(slot, grownSlots.places[index]),
      ];
      final tailSlot = switch (tail) {
        DMobileDockTail.none => null,
        DMobileDockTail.more => atRest.tail!,
        DMobileDockTail.page => between(atRest.tail!, (
          start: grownSlots.tail!.start,
          width: 0,
        )),
      };
      // The action moves over to the middle of the last column, taking a
      // place's tile there.
      final column = geometry.gridColumn(constraints.maxWidth);
      final actionSlot = atRest.action == null
          ? null
          : between(atRest.action!, (
              start:
                  (DMobileDockGeometry.columns - 1) *
                  (column + DMobileDockGeometry.columnGap),
              width: column,
            ));

      Widget destination(Widget child) => ExcludeSemantics(
        excluding: hidden,
        child: IgnorePointer(
          ignoring: hidden,
          child: Opacity(opacity: hidden ? 0 : 1, child: child),
        ),
      );
      Widget place(int index, DMobileDockPlace place) => DMobileDockItem(
        key: place.key,
        growth: out ? grown : 0,
        // The panel's focus follows its place into the head.
        focusNode: out && place.key == _firstTileKey ? _firstTile : null,
        icon: place.icon,
        label: place.label,
        semanticLabel: place.semanticLabel,
        badge: place.badge,
        selected: place.selected,
        customSemanticsActions: _moveActions(context, index),
        onPressed: () {
          if (_out) _grow(false);
          place.onPressed();
        },
      );
      // The ⋮, and the current page in its slot, open the panel; grown, the
      // ⋮ has nothing left to open and goes, and the page shrinks away.
      final gone = (1 - 2 * grown).clamp(0.0, 1.0);
      Widget fourth = switch (current) {
        DMobileDockOverflowed(:final index) => ClipRect(
          child: Opacity(
            opacity: gone,
            child: DMobileDockItem(
              key: places[index].key,
              growth: out ? grown : 0,
              icon: places[index].icon,
              label: places[index].label,
              badge: places[index].badge,
              selected: true,
              // It opens the panel in the ⋮'s stead, and takes the focus
              // back in its stead as the panel closes.
              focusNode: _moreFocus,
              hasPopup: true,
              expanded: out,
              onPressed: () => _grow(true),
            ),
          ),
        ),
        DMobileDockNowhere() || DMobileDockAtPlace() => IgnorePointer(
          ignoring: out,
          child: Opacity(
            opacity: gone,
            child: DMobileDockItem(
              key: DMobileDock.moreKey,
              bare: true,
              icon: widget.more.icon,
              label: widget.more.label,
              selected: current is DMobileDockNowhere,
              focusNode: _moreFocus,
              hasPopup: true,
              expanded: out,
              onPressed: () => _grow(true),
            ),
          ),
        ),
      };
      Widget at(DMobileDockSlot slot, Widget child, {Key? key}) =>
          PositionedDirectional(
            key: key,
            start: slot.start,
            width: slot.width,
            child: child,
          );
      // The row keeps its open size while the surface folds around it, and
      // fades before the fold reaches it.
      final navigation = OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: constraints.maxWidth - padding.horizontal,
        maxWidth: constraints.maxWidth - padding.horizontal,
        maxHeight: rowHeight,
        child: SizedBox(
          height: rowHeight,
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            clipBehavior: Clip.none,
            children: [
              for (final (index, entry) in shown.indexed)
                at(
                  placeSlots[index],
                  destination(_whileStill(place(index, entry))),
                  key: _slotKey(entry.key),
                ),
              // Grown, the ⋮ is out of the keyboard's round, not out of
              // reach: it takes the focus back as the panel closes.
              if (tailSlot case final slot?)
                at(
                  slot,
                  destination(
                    ExcludeFocusTraversal(excluding: out, child: fourth),
                  ),
                ),
              if (actionSlot case final slot?)
                PositionedDirectional(
                  start: slot.start,
                  width: slot.width,
                  height: rowHeight,
                  child: _ActionTile(
                    grown: out,
                    color: DMobileDockItem.hoverFill(tokens),
                    child: Center(
                      child: DMobileDockGrowthScope(
                        growth: out ? grown : 0,
                        closePanel: _close,
                        child: widget.action!,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      // Every column carries its own mark, grown in from nothing when its
      // place becomes current and gone the same way, so a move from one
      // place to another is one mark shrinking as the other grows. Grown,
      // the lit tile says it instead.
      final markedIndex = switch (current) {
        DMobileDockAtPlace(:final index) => index,
        DMobileDockOverflowed() => DMobileDockGeometry.placeColumns,
        DMobileDockNowhere() => null,
      };
      final markSlots = [
        ...placeSlots,
        if (tail == DMobileDockTail.page) tailSlot!,
      ];
      final marks = IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedOpacity(
            opacity: hidden ? 0 : navOpacity * gone,
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 100),
            child: Stack(
              children: [
                for (final (index, slot) in markSlots.indexed)
                  PositionedDirectional(
                    top: 0,
                    start: padding.start + slot.start,
                    width: slot.width,
                    height: DMobileDockGeometry.markHeight,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AnimatedContainer(
                        key: ValueKey('mobile-dock-mark-$index'),
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        curve: Curves.ease,
                        width: index == markedIndex
                            ? DMobileDockGeometry.markWidth
                            : 0,
                        height: DMobileDockGeometry.markHeight,
                        decoration: BoxDecoration(
                          color: tokens.foreground,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(
                              DMobileDockGeometry.markRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      // The circle's corner is measured from the screen's edges; the bar's
      // own margin already keeps part of that distance.
      final corner = geometry.cornerAt(round) - geometry.reach;
      return _draggable(
        context,
        AnimatedPadding(
          padding: collapsed
              ? EdgeInsetsDirectional.only(start: corner, bottom: corner)
              : EdgeInsetsDirectional.zero,
          duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
          curve: const Cubic(.32, .72, 0, 1),
          child: AnimatedContainer(
            key: const ValueKey('mobile-dock-surface'),
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 420),
            curve: const Cubic(.32, .72, 0, 1),
            width: collapsed ? round : constraints.maxWidth,
            height: collapsed ? round : geometry.barHeight,
            // The panel owns the head's fill while out. Remove the
            // decoration so returning to the bar restores its fill
            // immediately, without tweening from transparent.
            decoration: out
                ? null
                : BoxDecoration(
                    color: well,
                    borderRadius: collapsed
                        ? BorderRadius.circular(round / 2)
                        : geometry.borderRadius,
                  ),
            child: Stack(
              key: _surfaceContentKey,
              children: [
                AnimatedPadding(
                  key: const ValueKey('mobile-dock-controls'),
                  padding: collapsed
                      ? const EdgeInsets.all(DMobileDock.circlePadding)
                      : rowPadding,
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 420),
                  curve: const Cubic(.32, .72, 0, 1),
                  child: ClipRRect(
                    borderRadius: radius,
                    clipBehavior: out ? Clip.none : Clip.hardEdge,
                    child: Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [
                        ExcludeSemantics(
                          excluding: collapsed || navOpacity < 1,
                          child: IgnorePointer(
                            ignoring: collapsed || navOpacity < 1,
                            child: AnimatedOpacity(
                              opacity: navOpacity,
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 100),
                              child: navigation,
                            ),
                          ),
                        ),
                        if (collapsed || revealOpacity > 0)
                          ExcludeSemantics(
                            excluding: !collapsed || revealOpacity < 1,
                            child: IgnorePointer(
                              ignoring: !collapsed || revealOpacity < 1,
                              child: Opacity(
                                opacity: revealOpacity,
                                child: SizedBox(
                                  width: round - 2 * DMobileDock.circlePadding,
                                  height: round - 2 * DMobileDock.circlePadding,
                                  child: widget.collapsedDestination,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                marks,
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A drag up or down the bar or its panel: accepted past the bar's own slop
/// rather than the platform's, and never a touch that starts in the screen's
/// home band, which is the system's. A trackpad's swipe is not a drag; the
/// bar takes it as a sheet does, settling once it rests.
class _GrowDragRecognizer extends VerticalDragGestureRecognizer {
  _GrowDragRecognizer();

  double homeBandTop = double.infinity;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      super.isPointerAllowed(event) &&
      !(event.kind == PointerDeviceKind.touch &&
          event.position.dy >= homeBandTop);

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > DMobileDockDrag.slop;
}

/// A hold on a place of the open panel: still for [DMobileDockReorder.hold]
/// it lifts the place to be moved, and the finger is followed until it lets
/// go. Moved past the bar's slop before then, it is the panel's drag, which
/// wins the arena and ends the hold. Won early in the arena, it still waits
/// for the hold: a tap it would otherwise take is the place's own.
class _LiftRecognizer extends PrimaryPointerGestureRecognizer {
  _LiftRecognizer()
    : super(
        deadline: DMobileDockReorder.hold,
        preAcceptSlopTolerance: DMobileDockDrag.slop,
        postAcceptSlopTolerance: null,
        allowedButtonsFilter: _primaryButton,
      );

  static bool _primaryButton(int buttons) => buttons == kPrimaryButton;
  static bool _never(Offset _) => false;

  @override
  String get debugDescription => 'lift a place';

  /// Whether a touch down at [local] is on a place that can be lifted now.
  bool Function(Offset local) canLift = _never;
  void Function(_LiftRecognizer finger, Offset local)? onLift;
  void Function(_LiftRecognizer finger, Offset local)? onFollow;
  void Function(_LiftRecognizer finger)? onDrop;
  bool _lifted = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && canLift(event.localPosition);

  @override
  void didExceedDeadline() {
    resolve(GestureDisposition.accepted);
    _lifted = true;
    super.acceptGesture(primaryPointer!);
    onLift?.call(this, initialPosition!.local);
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void handlePrimaryPointer(PointerEvent event) {
    if (!_lifted) return;
    if (event is PointerMoveEvent) {
      onFollow?.call(this, event.localPosition);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _lifted = false;
      onDrop?.call(this);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _lifted = false;
    super.didStopTrackingLastPointer(pointer);
  }
}

/// Your face as the places' marks are, with your presence ringed round it as
/// it is in the rail: a ring 1.5 thick set 1.5 outside the 22 face, standing
/// past the 18 the marks beside it take so your name stays level with theirs.
class _Face extends StatelessWidget {
  const _Face({required this.face, required this.ring});

  final Widget face;
  final Color? ring;

  static const dimension = 22.0;
  static const ringWidth = 1.5;
  static const ringGap = 1.5;

  @override
  Widget build(BuildContext context) {
    const outer = dimension + 2 * (ringWidth + ringGap);
    return SizedBox(
      width: outer,
      height: outer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: ring == null
              ? null
              : Border.all(color: ring!, width: ringWidth),
        ),
        // The ring is drawn over the box's edge, so the face is set in from
        // it by the ring and its gap whether or not there is a ring.
        child: Padding(
          padding: const EdgeInsets.all(ringWidth + ringGap),
          child: ClipOval(child: face),
        ),
      ),
    );
  }
}

/// The place's tile the action takes under the pointer once it stands among
/// the places, the size of the others'. Only the action itself is pressed.
class _ActionTile extends StatefulWidget {
  const _ActionTile({
    required this.grown,
    required this.color,
    required this.child,
  });

  final bool grown;
  final Color color;
  final Widget child;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    opaque: false,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: widget.grown && _hovered ? widget.color : Colors.transparent,
        borderRadius: BorderRadius.circular(
          DMobileDockPanelGeometry.tileRadius,
        ),
      ),
      child: widget.child,
    ),
  );
}

/// The dock action: an icon-only circle in the primary button colours, as a
/// composer's send button is. Its label is its tooltip.
///
/// As the bar around it grows into its panel, it becomes one of the places
/// it then stands among, kept in the accent: its circle fades as far as the
/// bar has grown, its icon rises to where the places' are and its name comes
/// in under it, where theirs are. Pressed there, it closes the panel as the
/// places do, then does what it does.
class DMobileDockAction extends StatelessWidget {
  const DMobileDockAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.buttonKey,
  });
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Key? buttonKey;

  /// Where the icon rises to, and where the name's middle sits below the
  /// action's top, once grown.
  static const iconRise = 8.0;
  static const labelCentre = 39.0;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final colors = tokens.buttonTheme.primary;
    final scope = DMobileDockGrowthScope.maybeOf(context);
    final growth = (scope?.growth ?? 0).clamp(0.0, 1.0);
    final pressed = onPressed;
    final button = DButton.iconOnly(
      key: buttonKey,
      icon: growth == 0
          ? icon
          : Transform.translate(
              offset: Offset(0, -iconRise * growth),
              child: icon,
            ),
      tooltip: label,
      loading: loading,
      shape: DButtonShape.pill,
      density: DButtonDensity.mobileDockAction,
      foregroundColor: Color.lerp(colors.foreground, tokens.primary, growth),
      backgroundColor: colors.background.withValues(
        alpha: colors.background.a * (1 - growth),
      ),
      interactiveBackgroundColor: colors.hover.withValues(
        alpha: colors.hover.a * (1 - growth),
      ),
      onPressed: pressed == null
          ? null
          : () {
              scope?.closePanel();
              pressed();
            },
    );
    if (growth == 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        button,
        Positioned(
          top: labelCentre,
          child: FractionalTranslation(
            translation: const Offset(0, -.5),
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: growth,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: DiscourseTypography.metadata,
                      fontWeight: FontWeight.w400,
                      color: tokens.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
