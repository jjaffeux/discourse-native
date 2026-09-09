import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';
import 'd_separator.dart';

/// Layout direction for a [DButtonGroup].
enum DButtonGroupOrientation { horizontal, vertical }

/// Groups independent actions or fields into one joined visual composition.
///
/// Children retain their own callbacks, focus nodes and accessibility roles.
/// The group adds a semantic boundary and joined-edge metadata only; it does
/// not implement selection, roving focus, or toolbar keyboard behavior.
class DButtonGroup extends StatelessWidget {
  const DButtonGroup({
    super.key,
    required this.children,
    this.orientation = DButtonGroupOrientation.horizontal,
    this.semanticLabel,
    this.mainAxisSize = MainAxisSize.min,
  }) : assert(semanticLabel == null || semanticLabel != '');

  final List<Widget> children;
  final DButtonGroupOrientation orientation;

  /// Localized group name. Individual children still need their own labels.
  final String? semanticLabel;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    assert(children.isNotEmpty, 'A button group needs at least one child.');
    assert(semanticLabel == null || semanticLabel!.trim().isNotEmpty);
    final axis = orientation == DButtonGroupOrientation.horizontal
        ? Axis.horizontal
        : Axis.vertical;
    final scoped = <Widget>[
      for (var index = 0; index < children.length; index++)
        if (axis == Axis.horizontal && children[index] is DButtonGroupExpanded)
          Expanded(
            child: DJoinedControlScope(
              axis: axis,
              first: index == 0,
              last: index == children.length - 1,
              child: (children[index] as DButtonGroupExpanded).child,
            ),
          )
        else
          DJoinedControlScope(
            axis: axis,
            first: index == 0,
            last: index == children.length - 1,
            child: children[index] is DButtonGroupExpanded
                ? (children[index] as DButtonGroupExpanded).child
                : children[index],
          ),
    ];
    final Widget layout = axis == Axis.horizontal
        ? Row(
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: scoped,
          )
        : Column(
            mainAxisSize: mainAxisSize,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: scoped,
          );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: layout,
    );
  }
}

/// Gives a direct group child the horizontal space left by fixed controls.
///
/// This is the Flutter equivalent of the reference's `input:flex-1`. Place the
/// group in a finite-width parent and set [DButtonGroup.mainAxisSize] to max.
class DButtonGroupExpanded extends StatelessWidget {
  const DButtonGroupExpanded({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A visual divider between adjacent group controls.
///
/// The default vertical rule matches a horizontal group. Set [orientation] to
/// horizontal when dividing controls in a vertical group.
class DButtonGroupSeparator extends StatelessWidget {
  const DButtonGroupSeparator({
    super.key,
    this.orientation = Axis.vertical,
    this.color,
    this.decorative = true,
    this.semanticLabel,
  });

  final Axis orientation;
  final Color? color;
  final bool decorative;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: orientation == Axis.vertical
        ? const EdgeInsets.symmetric(vertical: 1)
        : const EdgeInsets.symmetric(horizontal: 1),
    child: DSeparator(
      orientation: orientation,
      color: color,
      decorative: decorative,
      semanticLabel: semanticLabel,
    ),
  );
}

/// Passive rich content aligned with controls in a [DButtonGroup].
///
/// Use [semanticLabel] to replace complex visual content with concise spoken
/// text. This part is not focusable and does not add a button role.
class DButtonGroupText extends StatelessWidget {
  const DButtonGroupText({
    super.key,
    required this.child,
    this.semanticLabel,
    this.padding = const EdgeInsetsDirectional.symmetric(horizontal: 10),
    this.alignment = AlignmentDirectional.center,
  });

  final Widget child;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final text = DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: tokens.foreground,
        fontSize: DiscourseTypography.sm,
        height: 20 / DiscourseTypography.sm,
        fontWeight: FontWeight.w400,
      ),
      child: IconTheme.merge(
        data: IconThemeData(size: 16, color: tokens.mutedForeground),
        child: child,
      ),
    );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Padding(
        padding: padding,
        child: Align(alignment: alignment, child: text),
      ),
    );
  }
}
