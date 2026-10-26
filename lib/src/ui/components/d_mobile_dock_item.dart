import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_mobile_dock_geometry.dart';

/// One labelled destination in a mobile navigation dock.
///
/// The entire icon and label share a single button target. [badge] is a
/// non-interactive compact count, placed beside the label rather than over the
/// icon. The destination owner decides which items are visible and owns routing.
///
/// As the bar grows into its panel, [growth] from 0 to 1 makes the item one
/// of the panel's tiles: taller and square-cornered, with a hover fill, its
/// icon a touch smaller and its name in the grid's lighter type; the current
/// one is lit by a tenth of the text colour, as far as the bar has grown.
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
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: DButton(
          density: tile
              ? DButtonDensity.mobileDockTile
              : DButtonDensity.mobileDock,
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
          foregroundColor: selected
              ? tokens.foreground
              : tokens.mutedForeground,
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
              if (!bare) ...[
                const SizedBox(height: 2),
                SizedBox(
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
              ],
            ],
          ),
        ),
      ),
    );
  }
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
      countSize = layoutChild(count, BoxConstraints.loose(size));
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
