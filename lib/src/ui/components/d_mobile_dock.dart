import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_mobile_dock_geometry.dart';
import 'd_mobile_dock_growth.dart';
import 'd_mobile_dock_item.dart';

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
    this.selected = false,
  });

  /// The bar's item carries this key; the panel's tile carries
  /// [DMobileDock.tileKey] of it.
  final Key key;
  final Widget icon;
  final String label;
  final Widget? badge;

  /// Whether this is the page a person is on.
  final bool selected;
  final VoidCallback onPressed;
}

/// The ⋮ that grows the bar into its panel.
typedef DMobileDockMore = ({Widget icon, String label});

/// You, a tile among the panel's places: your face, 22 across, ringed in
/// [ring] when there is something to say of your presence; your name; what
/// is said of your account and presence; and what pressing it opens.
typedef DMobileDockYou = ({
  Widget face,
  String name,
  Color? ring,
  String semanticLabel,
  VoidCallback onPressed,
});

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
/// so the action can become one of the places it then stands among.
class DMobileDockGrowthScope extends InheritedWidget {
  const DMobileDockGrowthScope({
    super.key,
    required this.growth,
    required super.child,
  });

  final double growth;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DMobileDockGrowthScope>()
          ?.growth ??
      0;

  @override
  bool updateShouldNotify(DMobileDockGrowthScope oldWidget) =>
      growth != oldWidget.growth;
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
    this.you,
    this.collapsed = false,
    this.destinationsHidden = false,
    this.onPanelChanged,
  });

  final DMobileDockGeometry geometry;

  /// Every place in order; the bar shows the first
  /// [DMobileDockGeometry.placeColumns] and the panel holds the rest.
  final List<DMobileDockPlace> places;
  final DMobileDockMore more;
  final Widget collapsedDestination;
  final Widget? action;

  /// The panel's last tile, while signed in.
  final DMobileDockYou? you;
  final bool collapsed;
  final bool destinationsHidden;

  /// Told once as the panel comes out and once as it goes, never during a
  /// build.
  final ValueChanged<bool>? onPanelChanged;

  /// Around the folded circle's own button.
  static const circlePadding = 4.0;

  static const moreKey = ValueKey('mobile-mode-more');
  static const panelKey = ValueKey('mobile-dock-panel');
  static const dimKey = ValueKey('mobile-dock-dim');
  static const grabberKey = ValueKey('mobile-dock-grabber');
  static const youKey = ValueKey('mobile-dock-you');

  /// The panel's tile for the place keyed [place].
  static Key tileKey(Key place) => ValueKey(('mobile-dock-tile', place));

  /// How the bar settles once let go: a touch past where it is going, open
  /// or closed, and back, as a sheet set down is.
  static const settleDuration = Duration(milliseconds: 460);
  static const settleCurve = Cubic(.3, 1.36, .5, 1);

  /// The dim's colour and the grid's opacity ease on their own time.
  static const fadeDuration = Duration(milliseconds: 300);
  static const dimOpacity = .32;

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

/// Under a finger, from where it was when the drag began, with where the
/// finger has been lately.
final class _Dragging extends _Growth {
  _Dragging({required this.start});
  final double start;
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

class _DMobileDockState extends State<DMobileDock>
    with TickerProviderStateMixin {
  // Unbounded, so the spring can settle a touch past open or closed and back.
  late final _growth = AnimationController.unbounded(vsync: this);
  late final _fade = AnimationController(vsync: this);
  final _portal = OverlayPortalController();
  final _barKey = GlobalKey(debugLabel: 'mobile-dock-bar');
  final _moreFocus = FocusNode(debugLabel: 'mobile-dock-more');
  final _panelFocus = FocusScopeNode(debugLabel: 'mobile-dock-panel');
  _Growth _phase = const _Closed();

  // A settle that was interrupted must not report its end as the panel's.
  int _settle = 0;
  bool _reportedOut = false;

  bool get _out => _phase is! _Closed;

  /// With nothing past the bar's columns, or the bar put away, there is
  /// nothing to grow into.
  bool get _grows =>
      widget.places.length > DMobileDockGeometry.placeColumns &&
      !widget.collapsed &&
      !widget.destinationsHidden;

  List<DMobileDockPlace> get _rest =>
      widget.places.skip(DMobileDockGeometry.placeColumns).toList();

  int get _tiles => _rest.length + (widget.you == null ? 0 : 1);

  @override
  void didUpdateWidget(DMobileDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_out && !_grows) _putAway();
  }

  @override
  void dispose() {
    _growth.dispose();
    _fade.dispose();
    _moreFocus.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  /// Where a drag began on the screen, so growth follows the finger from
  /// where it was.
  double _dragOrigin = 0;

  void _dragStart(DragStartDetails details) {
    if (!_grows) return;
    _settle++;
    _growth.stop();
    _fade.stop();
    final start = _growth.value.clamp(0.0, 1.0);
    _dragOrigin = details.globalPosition.dy;
    final wasOut = _out;
    setState(() => _phase = _Dragging(start: start));
    if (!wasOut) _portal.show();
    _reportOut();
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_phase case _Dragging(:final start, :final trail)) {
      final panel = widget.geometry.panel(tiles: _tiles);
      final travel = math.max(1.0, panel.reveal);
      final pulled = _dragOrigin - details.globalPosition.dy;
      final growth = (start + pulled / travel).clamp(0.0, 1.0);
      _growth.value = growth;
      _fade.value = growth;
      trail.add(
        details.globalPosition.dy,
        details.sourceTimeStamp ?? Duration.zero,
      );
    }
  }

  void _dragEnd([DragEndDetails? _]) {
    if (_phase case _Dragging(:final start, :final trail)) {
      _grow(
        DMobileDockDrag.settlesOpen(
          start: start,
          at: _growth.value,
          velocity: trail.velocity,
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
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: widget.collapsed
          ? const {}
          : {
              _GrowDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<_GrowDragRecognizer>(
                    _GrowDragRecognizer.new,
                    (recognizer) => recognizer
                      ..homeBandTop = screenBottom - DMobileDockDrag.homeBand
                      ..dragStartBehavior = DragStartBehavior.down
                      ..onStart = _dragStart
                      ..onUpdate = _dragUpdate
                      ..onEnd = _dragEnd
                      ..onCancel = _dragEnd,
                  ),
            },
      child: child,
    );
  }

  void _grow(bool opening) {
    if (opening ? !_grows : !_out) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final wasOut = _out;
    final token = ++_settle;
    setState(() => _phase = _Settling(opening: opening));
    if (!wasOut) _portal.show();
    _reportOut();
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

  void _settled(bool opening) {
    if (opening) {
      setState(() => _phase = const _Open());
      return;
    }
    final restoreFocus = _panelFocus.hasFocus;
    setState(() => _phase = const _Closed());
    _portal.hide();
    _reportOut();
    if (restoreFocus) _moreFocus.requestFocus();
  }

  /// Put away with the bar, as by the composer it opened, it comes back as
  /// a bar, not as the panel it was. The bar is told during a build, so
  /// the overlay empties now and leaves once the frame is drawn.
  void _putAway() {
    _settle++;
    _growth
      ..stop()
      ..value = 0;
    _fade
      ..stop()
      ..value = 0;
    _phase = const _Closed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_out) _portal.hide();
    });
    _reportOut();
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
            : Align(alignment: AlignmentDirectional.bottomStart, child: bar),
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
    final geometry = widget.geometry;
    // The screen's edges, which the bar's margins keep it from: the panel
    // runs between them, up from the foot.
    final margin = geometry.margin;
    final left = slot.left - margin.start;
    final width = slot.width + margin.horizontal;
    final foot = slot.bottom + margin.bottom;
    final panel = geometry.panel(tiles: _tiles);
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
    return AnimatedBuilder(
      animation: Listenable.merge([_growth, _fade]),
      builder: (context, _) {
        final growth = _growth.value;
        final fade = _fade.value;
        final tiles = [
          for (final (index, place) in _rest.indexed)
            _tile(
              panel.tileRect(index, width),
              DMobileDockItem(
                key: DMobileDock.tileKey(place.key),
                growth: 1,
                autofocus: index == 0,
                icon: place.icon,
                label: place.label,
                badge: place.badge,
                selected: place.selected,
                onPressed: () {
                  _grow(false);
                  place.onPressed();
                },
              ),
            ),
          if (widget.you case final you?)
            _tile(
              panel.tileRect(_rest.length, width),
              DMobileDockItem(
                key: DMobileDock.youKey,
                growth: 1,
                icon: _Face(face: you.face, ring: you.ring),
                label: you.name,
                semanticLabel: you.semanticLabel,
                onPressed: () {
                  _grow(false);
                  you.onPressed();
                },
              ),
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
        return BlockSemantics(
          child: Semantics(
            container: true,
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: context.l10n.places,
            onDismiss: () => _grow(false),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _grow(false),
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
                      child: FocusScope(
                        node: _panelFocus,
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(
                              LogicalKeyboardKey.escape,
                            ): () =>
                                _grow(false),
                          },
                          child: _draggable(context, body),
                        ),
                      ),
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
              ],
            ),
          ),
        );
      },
    );
  }

  // A tile keeps its own height, as the bar's places do: larger text grows
  // it past its row.
  Widget _tile(Rect rect, Widget child) => PositionedDirectional(
    start: rect.left,
    top: rect.top,
    width: rect.width,
    child: child,
  );

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
      Widget place(DMobileDockPlace place) => DMobileDockItem(
        key: place.key,
        growth: out ? grown : 0,
        icon: place.icon,
        label: place.label,
        badge: place.badge,
        selected: place.selected,
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
      Widget at(DMobileDockSlot slot, Widget child) => PositionedDirectional(
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
                at(placeSlots[index], destination(place(entry))),
              if (tailSlot case final slot?) at(slot, destination(fourth)),
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
            decoration: BoxDecoration(
              // The panel shows through the head so the grid can come up
              // under its row.
              color: out ? well.withValues(alpha: 0) : well,
              borderRadius: collapsed
                  ? BorderRadius.circular(round / 2)
                  : geometry.borderRadius,
            ),
            child: Stack(
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
/// home band, which is the system's.
class _GrowDragRecognizer extends VerticalDragGestureRecognizer {
  _GrowDragRecognizer();

  double homeBandTop = double.infinity;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      super.isPointerAllowed(event) &&
      !(event.kind == PointerDeviceKind.touch &&
          event.position.dy >= homeBandTop);

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > DMobileDockDrag.slop;
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
/// in under it, where theirs are.
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
    final growth = DMobileDockGrowthScope.of(context).clamp(0.0, 1.0);
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
      onPressed: onPressed,
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
                      fontSize: 11.5,
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
