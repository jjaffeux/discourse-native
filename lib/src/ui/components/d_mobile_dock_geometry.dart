import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// What the bar's row holds past its places: nothing, when every place has a
/// column; the ⋮ that opens the rest; or the page a person is on when it is
/// one of the rest, standing where the ⋮ would be.
enum DMobileDockTail { none, more, page }

/// Where one item of the row sits, from the row's start.
typedef DMobileDockSlot = ({double start, double width});

/// The open row from its start: each shown place's column, the fourth
/// column's ⋮, and the action at the row's end.
typedef DMobileDockRowSlots = ({
  List<DMobileDockSlot> places,
  DMobileDockSlot? tail,
  DMobileDockSlot? action,
});

/// Where a phone's bar sits and how it is cut, from the screen's foot and the
/// dock's text scale. The dock, the shell's footer, the chat composer and the
/// topic timeline read this one value, so none of them restates an edge.
///
/// On a screen with a foot, a bottom safe inset and so round corners, the
/// open bar runs the screen's full width down to its foot: round top corners
/// of half the capsule's height, square bottom corners the screen's own
/// corners round, and its row held above the foot by the bar's own bottom
/// padding. On a square screen it floats as a capsule [inset] in from every
/// edge. Something that lifts the bar off the foot, a minimized composer,
/// leaves it that capsule over the room it takes and the foot.
///
/// Folded, the bar is a circle in the screen's bottom-start corner, on the
/// corner's diagonal and as far in from its curve as the open bar is from
/// the edges; what follows it settles into a corner the same way, [cornerAt]
/// its own height.
@immutable
class DMobileDockGeometry {
  const DMobileDockGeometry({
    required this.foot,
    this.lift = 0,
    this.growth = 0,
  });

  factory DMobileDockGeometry.of(BuildContext context, {double lift = 0}) =>
      DMobileDockGeometry(
        foot: MediaQuery.paddingOf(context).bottom,
        lift: lift,
        growth: math.max(0.0, MediaQuery.textScalerOf(context).scale(11) - 11),
      );

  /// The screen's bottom safe inset, which is 0 while the keyboard is up.
  final double foot;

  /// Room below the bar that keeps it off the foot.
  final double lift;

  /// How much taller the dock's text scale makes its row than the default.
  final double growth;

  /// The corner radius of the screens the mockup assumes.
  static const screenRadius = 55.0;

  /// The bar's distance from a screen edge it does not reach, and its row's
  /// distance from the bar's own edges.
  static const inset = 6.0;

  /// Half the capsule's height at the default text scale. The room the bar
  /// keeps above the foot is taken from the screen's curve and this corner,
  /// and larger text does not push the row down into the foot.
  static const capsuleRadius = 31.0;

  /// The row is a grid of four columns with [columnGap] between them. The
  /// places take one column each, so at most [placeColumns] show; the fourth
  /// holds the ⋮, [moreWidth] wide at its start, and the action at its end.
  static const columns = 4;
  static const placeColumns = 3;
  static const columnGap = 4.0;
  static const moreWidth = 40.0;

  double get rowHeight => 50 + growth;

  /// The folded bar.
  double get circle => 48 + growth;

  bool get grounded => lift == 0;

  double get _foot => grounded ? foot : 0;

  /// How far the bar stays from the screen's sides and foot: [inset] on a
  /// square screen, nothing once the foot is at least that deep.
  double get reach => inset - math.min(inset, _foot);

  /// What the bar's edges are measured up from: the screen's bottom edge, or
  /// the top of what lifts the bar off it.
  double get ground => grounded ? 0 : lift + foot;

  /// Around the bar, between it and the screen's edges or the page above it.
  EdgeInsetsDirectional get margin =>
      EdgeInsetsDirectional.fromSTEB(reach, inset, reach, reach + ground);

  /// Half the capsule's height, so its ends are round.
  double get topRadius => (rowHeight + 2 * inset) / 2;

  /// Inside the bar, around its row. At the foot the bar is as tall as the
  /// screen's curve and its own corner together, so its corner ends where the
  /// screen's begins.
  EdgeInsetsDirectional get padding => EdgeInsetsDirectional.fromSTEB(
    inset,
    inset,
    inset,
    inset + math.min(_foot, screenRadius - capsuleRadius),
  );

  BorderRadius get borderRadius => BorderRadius.vertical(
    top: Radius.circular(topRadius),
    bottom: Radius.circular(_foot > 0 ? 0 : topRadius),
  );

  double get barHeight => padding.vertical + rowHeight;

  /// The footer the shell measures and pages keep their last row clear of:
  /// the bar and its margins.
  double get footerExtent => margin.vertical + barHeight;

  /// Lays the open row out across a bar [barWidth] wide. The ⋮ and the
  /// action share the fourth column; on a bar too narrow for both side by
  /// side, that column grows to hold them and the places share what is left.
  /// A page standing where the ⋮ would be shares the room the three places
  /// and the ⋮ had equally with them, its name cut short like theirs.
  DMobileDockRowSlots rowSlots(
    double barWidth, {
    required int places,
    required DMobileDockTail tail,
    required bool action,
  }) {
    assert(places <= placeColumns);
    assert(tail == DMobileDockTail.none || places == placeColumns);
    final inner = barWidth - padding.horizontal;
    final actionWidth = action ? rowHeight : 0.0;
    const gaps = (columns - 1) * columnGap;
    var column = (inner - gaps) / columns;
    final fourth = tail != DMobileDockTail.none && action
        ? math.max(column, moreWidth + actionWidth)
        : column;
    if (fourth > column) column = (inner - gaps - fourth) / placeColumns;
    if (tail == DMobileDockTail.page) {
      column = (placeColumns * column + moreWidth) / columns;
    }
    DMobileDockSlot at(int index, double width) =>
        (start: index * (column + columnGap), width: width);
    return (
      places: [for (var index = 0; index < places; index++) at(index, column)],
      tail: switch (tail) {
        DMobileDockTail.none => null,
        DMobileDockTail.more => at(placeColumns, moreWidth),
        DMobileDockTail.page => at(placeColumns, column),
      },
      action: action ? (start: inner - actionWidth, width: actionWidth) : null,
    );
  }

  /// How far from the screen's start and bottom edges something [extent]
  /// across sits in its corner: on the corner's diagonal, as far in from the
  /// curve as the bar is from the edges, and never deeper than the foot. On a
  /// square screen it keeps the bar's [inset]. Measured up from [ground].
  double cornerAt(double extent) => math.max(
    inset,
    math.min(
      screenRadius - (screenRadius - inset - extent / 2) * 0.7071 - extent / 2,
      _foot,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is DMobileDockGeometry &&
      other.foot == foot &&
      other.lift == lift &&
      other.growth == growth;

  @override
  int get hashCode => Object.hash(foot, lift, growth);
}
