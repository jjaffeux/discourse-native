import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_mobile_dock_geometry.dart';

/// One labelled destination in a mobile navigation dock.
///
/// The entire icon and label share a single button target. [badge] is a
/// non-interactive compact count, placed beside the label rather than over the
/// icon; a [bare] item, its glyph alone, carries its count on the glyph's
/// corner instead, as a phone's closed bar shows its places. The destination
/// owner decides which items are visible and owns routing.
///
/// As the bar grows into its panel, [growth] from 0 to 1 makes the item one
/// of the panel's tiles: taller and square-cornered, with a hover fill, its
/// icon a touch smaller and its name in the grid's lighter type; the current
/// one is lit by a tenth of the text colour, as far as the bar has grown.
/// The name fades in as its space opens, moving the icon above it. Reversing
/// growth returns the icon to the centre as the name fades away.
/// The panel's own tiles are fully grown.
class DMobileDockItem extends StatelessWidget {
  const DMobileDockItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
    this.selected = false,
    this.bare = false,
    this.collapsed = false,
    this.growth = 0,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.expanded = false,
    this.hasPopup = false,
    this.customSemanticsActions,
  }) : assert(growth >= 0);

  final Widget icon;
  final String label;
  final Widget? badge;
  final bool selected;
  final bool bare;
  final bool collapsed;
  final double growth;

  /// Said instead of [label], for a tile whose name is not what it is.
  final String? semanticLabel;

  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool expanded;
  final bool hasPopup;

  /// What assistive technology can do with the item besides pressing it,
  /// as moving it among its places.
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;

  /// A tile's hover and pressed fill: the mockup's `--state-hover`.
  static Color hoverFill(DTokens tokens) =>
      tokens.foreground.withValues(alpha: .08);

  /// The tile of the place a person is on, lit by a tenth of the text.
  static Color currentFill(DTokens tokens, double growth) =>
      tokens.foreground.withValues(alpha: .10 * growth.clamp(0, 1));

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final tile = growth > 0;
    final grown = growth.clamp(0.0, 1.0);
    final nameProgress = bare ? 0.0 : (tile ? grown : 1.0);
    final geometry = DMobileDockGeometry.of(context);
    final fontSize = tile ? DiscourseTypography.metadata : null;
    final fontWeight = selected
        ? FontWeight.w600
        : tile
        ? FontWeight.w400
        : FontWeight.w500;

    final scaleDelta = math.max(
      0.0,
      MediaQuery.textScalerOf(context).scale(11) - 11,
    );
    final labelHeight = 14 + scaleDelta;
    final measure = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelLarge!.copyWith(
          fontSize: fontSize ?? DiscourseTypography.micro,
          fontWeight: FontWeight.w600,
        ),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final labelWidth = measure.width;
    measure.dispose();
    if (collapsed) {
      return DButton.iconOnly(
        density: DButtonDensity.mobileDockCollapsed,
        variant: DButtonVariant.ghost,
        shape: DButtonShape.pill,
        icon: icon,
        tooltip: label,
        focusNode: focusNode,
        onPressed: onPressed,
      );
    }
    final button = DButton(
      density: tile ? DButtonDensity.mobileDockTile : DButtonDensity.mobileDock,
      variant: DButtonVariant.ghost,
      shape: DButtonShape.pill,
      borderRadius: tile
          ? BorderRadius.circular(DMobileDockPanelGeometry.tileRadius)
          : null,
      tooltip: label,
      semanticLabel: semanticLabel ?? (bare ? label : null),
      focusNode: focusNode,
      autofocus: autofocus,
      expanded: expanded,
      hasPopup: hasPopup,
      onPressed: onPressed,
      // The bar marks the current place on its own edge; the item says
      // it only by its colour and weight, until it is a tile.
      foregroundColor: selected ? tokens.foreground : tokens.mutedForeground,
      backgroundColor: tile && selected
          ? currentFill(tokens, grown)
          : Colors.transparent,
      interactiveBackgroundColor: tile ? hoverFill(tokens) : null,
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: const ValueKey('mobile-dock-glyph'),
            height: (26) + scaleDelta,
            child: Center(
              child: ExcludeSemantics(
                child: tile
                    ? Transform.scale(scale: 1 - .1 * grown, child: icon)
                    : icon,
              ),
            ),
          ),
          if (!bare)
            Opacity(
              opacity: Curves.easeInOut.transform(nameProgress),
              child: Align(
                heightFactor: nameProgress,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    height: labelHeight,
                    child: CustomMultiChildLayout(
                      delegate: _LabelAndCount(
                        textDirection: Directionality.of(context),
                        height: labelHeight,
                        labelWidth: labelWidth,
                      ),
                      children: [
                        LayoutId(
                          id: _LabelAndCount.label,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: fontWeight,
                            ),
                          ),
                        ),
                        if (badge case final count?)
                          LayoutId(id: _LabelAndCount.count, child: count),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // One structure whether or not the corner count is drawn, so the count
    // coming or going, or the bar growing, keeps the button and its focus.
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        customSemanticsActions: customSemanticsActions,
        child: Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              height: math.max(
                geometry.rowHeight + 2 * geometry.headOverflow * grown,
                26 + scaleDelta + (2 + labelHeight) * nameProgress,
              ),
              child: button,
            ),
            if (nameProgress < 1 && badge != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    excluding: !bare,
                    child: Opacity(
                      opacity: 1 - Curves.easeInOut.transform(nameProgress),
                      child: CustomSingleChildLayout(
                        delegate: _CornerCount(Directionality.of(context)),
                        child: badge,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A bare item's count on its glyph's corner: [DMobileDockGeometry.countTop]
/// below the item's top, its start edge [DMobileDockGeometry.countPastMiddle]
/// past the item's middle, at its own size whatever the column's.
class _CornerCount extends SingleChildLayoutDelegate {
  _CornerCount(this.textDirection);

  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final past = size.width / 2 + DMobileDockGeometry.countPastMiddle;
    return Offset(
      textDirection == TextDirection.ltr
          ? past
          : size.width - past - childSize.width,
      DMobileDockGeometry.countTop,
    );
  }

  @override
  bool shouldRelayout(_CornerCount oldDelegate) =>
      textDirection != oldDelegate.textDirection;
}

/// The label and its count side by side, centred in the column. The label
/// gives way first, cut to one line, and the count keeps its own width until
/// the column cannot hold even that, so neither can push past the column.
class _LabelAndCount extends MultiChildLayoutDelegate {
  _LabelAndCount({
    required this.textDirection,
    required this.height,
    required this.labelWidth,
  });

  static const label = 'label';
  static const count = 'count';
  static const gap = 4.0;

  final TextDirection textDirection;
  final double height;

  /// The label's natural width, which stands in for the column's where
  /// nothing bounds it.
  final double labelWidth;

  @override
  Size getSize(BoxConstraints constraints) => Size(
    constraints.hasBoundedWidth ? constraints.maxWidth : labelWidth,
    height,
  );

  @override
  void performLayout(Size size) {
    var countSize = Size.zero;
    var spacing = 0.0;
    if (hasChild(count)) {
      // The count keeps its own height, centred on the line it may overhang.
      countSize = layoutChild(count, BoxConstraints(maxWidth: size.width));
      spacing = gap;
    }
    final labelSize = layoutChild(
      label,
      BoxConstraints(
        maxWidth: math.max(0, size.width - countSize.width - spacing),
        maxHeight: size.height,
      ),
    );
    final total = labelSize.width + spacing + countSize.width;
    final start = (size.width - total) / 2;
    final ltr = textDirection == TextDirection.ltr;
    double left(double fromStart, double width) =>
        ltr ? start + fromStart : size.width - start - fromStart - width;
    positionChild(
      label,
      Offset(left(0, labelSize.width), (size.height - labelSize.height) / 2),
    );
    if (hasChild(count)) {
      positionChild(
        count,
        Offset(
          left(labelSize.width + spacing, countSize.width),
          (size.height - countSize.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_LabelAndCount oldDelegate) =>
      textDirection != oldDelegate.textDirection ||
      height != oldDelegate.height ||
      labelWidth != oldDelegate.labelWidth;
}
