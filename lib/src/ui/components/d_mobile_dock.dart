import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_mobile_dock_geometry.dart';

/// Where the page a person is on stands among a bar's places.
sealed class DMobileDockCurrent {
  const DMobileDockCurrent();

  /// No place is the current page.
  const factory DMobileDockCurrent.none() = DMobileDockNowhere;

  /// The current page is the place at [index], within the bar's columns.
  const factory DMobileDockCurrent.place(int index) = DMobileDockAtPlace;

  /// The current page is one the bar has no column for. It stands where the
  /// ⋮ would be, as [page], and pressing it opens the rest as the ⋮ does.
  const factory DMobileDockCurrent.overflowed(Widget page) =
      DMobileDockOverflowed;
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
  const DMobileDockOverflowed(this.page);
  final Widget page;
}

/// A phone's bar, cut as its [DMobileDockGeometry] says. Its places take one
/// column each of the row's four; the fourth holds the ⋮ for the places past
/// them, or the current page when it is one of those, and the action at the
/// row's end. The current place is marked by a short bar on the bar's top
/// edge over its column. Folded, the bar is a circle in the screen's
/// bottom-start corner.
class DMobileDock extends StatelessWidget {
  const DMobileDock({
    super.key,
    required this.geometry,
    required this.places,
    required this.more,
    required this.current,
    required this.collapsedDestination,
    this.action,
    this.collapsed = false,
    this.destinationsHidden = false,
  });

  final DMobileDockGeometry geometry;

  /// Every place in order; the bar shows the first
  /// [DMobileDockGeometry.placeColumns] and the ⋮ holds the rest.
  final List<Widget> places;
  final Widget more;
  final DMobileDockCurrent current;
  final Widget collapsedDestination;
  final Widget? action;
  final bool collapsed;
  final bool destinationsHidden;

  /// Around the folded circle's own button.
  static const circlePadding = 4.0;

  Widget _destination(Widget child) => ExcludeSemantics(
    excluding: destinationsHidden,
    child: IgnorePointer(
      ignoring: destinationsHidden,
      child: Opacity(opacity: destinationsHidden ? 0 : 1, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      final round = geometry.circle;
      final navOpacity = (collapsed ? 0.0 : 1.0);
      final revealOpacity = (collapsed ? 1.0 : 0.0);
      final radius = BorderRadius.circular(999);
      final tokens = DTokens.of(context);

      final well = tokens.wellFill;
      final shown = places.take(DMobileDockGeometry.placeColumns).toList();
      final (tail, fourth) = places.length <= DMobileDockGeometry.placeColumns
          ? (DMobileDockTail.none, null)
          : switch (current) {
              DMobileDockOverflowed(:final page) => (
                DMobileDockTail.page,
                page,
              ),
              DMobileDockNowhere() ||
              DMobileDockAtPlace() => (DMobileDockTail.more, more),
            };
      final slots = geometry.rowSlots(
        constraints.maxWidth,
        places: shown.length,
        tail: tail,
        action: action != null,
      );
      // Each item keeps its own height, centred on the row; larger text
      // grows a place past the row and the bar's edge clips it, as before.
      Widget at(DMobileDockSlot slot, Widget child) => PositionedDirectional(
        start: slot.start,
        width: slot.width,
        child: child,
      );
      // The row keeps its open size while the surface folds around it, and
      // fades before the fold reaches it.
      final navigation = OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: constraints.maxWidth - geometry.padding.horizontal,
        maxWidth: constraints.maxWidth - geometry.padding.horizontal,
        maxHeight: geometry.rowHeight,
        child: SizedBox(
          height: geometry.rowHeight,
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            clipBehavior: Clip.none,
            children: [
              for (final (index, place) in shown.indexed)
                at(slots.places[index], _destination(place)),
              if (slots.tail case final slot?) at(slot, _destination(fourth!)),
              if (slots.action case final slot?) at(slot, action!),
            ],
          ),
        ),
      );
      // Every column carries its own mark, grown in from nothing when its
      // place becomes current and gone the same way, so a move from one
      // place to another is one mark shrinking as the other grows.
      final markedIndex = switch (current) {
        DMobileDockAtPlace(:final index) => index,
        DMobileDockOverflowed() => DMobileDockGeometry.placeColumns,
        DMobileDockNowhere() => null,
      };
      final markSlots = [
        ...slots.places,
        if (tail == DMobileDockTail.page) slots.tail!,
      ];
      final marks = IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedOpacity(
            opacity: destinationsHidden ? 0 : navOpacity,
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 100),
            child: Stack(
              children: [
                for (final (index, slot) in markSlots.indexed)
                  PositionedDirectional(
                    top: 0,
                    start: geometry.padding.start + slot.start,
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
      final capsuleArtwork = AnimatedPadding(
        padding: collapsed
            ? EdgeInsetsDirectional.only(start: corner, bottom: corner)
            : EdgeInsetsDirectional.zero,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
        curve: const Cubic(.32, .72, 0, 1),
        child: AnimatedContainer(
          key: const ValueKey('mobile-dock-surface'),
          duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
          curve: const Cubic(.32, .72, 0, 1),
          width: collapsed ? round : constraints.maxWidth,
          height: collapsed ? round : geometry.barHeight,
          decoration: BoxDecoration(
            color: well,
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
                    : geometry.padding,
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: const Cubic(.32, .72, 0, 1),
                child: ClipRRect(
                  borderRadius: radius,
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
                                child: collapsedDestination,
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
      );
      return SizedBox(
        height: geometry.barHeight,
        child: Align(
          alignment: AlignmentDirectional.bottomStart,
          child: capsuleArtwork,
        ),
      );
    },
  );
}

/// The dock action: an icon-only circle in the primary button colours, as a
/// composer's send button is. Its label is its tooltip.
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
  @override
  Widget build(BuildContext context) {
    final colors = DTokens.of(context).buttonTheme.primary;
    return DButton.iconOnly(
      key: buttonKey,
      icon: icon,
      tooltip: label,
      loading: loading,
      shape: DButtonShape.pill,
      density: DButtonDensity.mobileDockAction,
      foregroundColor: colors.foreground,
      backgroundColor: colors.background,
      interactiveBackgroundColor: colors.hover,
      onPressed: onPressed,
    );
  }
}
