import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: _ButtonGroupFlex(
        direction: axis,
        mainAxisSize: mainAxisSize,
        children: scoped,
      ),
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
  Widget build(BuildContext context) => _GroupSeparatorExtent(
    orientation: orientation,
    child: Padding(
      padding: orientation == Axis.vertical
          ? const EdgeInsets.symmetric(vertical: 1)
          : const EdgeInsets.symmetric(horizontal: 1),
      child: DSeparator(
        orientation: orientation,
        color: color,
        decorative: decorative,
        semanticLabel: semanticLabel,
      ),
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
        child: Align(
          alignment: alignment,
          widthFactor: 1,
          heightFactor: 1,
          child: text,
        ),
      ),
    );
  }
}

// Measure controls through their normal layout, then stretch only separators
// to the resulting cross-axis extent. Intrinsic measurement cannot be used:
// composed controls such as DSelect contain LayoutBuilder.
class _ButtonGroupFlex extends Flex {
  const _ButtonGroupFlex({
    required super.direction,
    required super.mainAxisSize,
    required super.children,
  });

  @override
  RenderFlex createRenderObject(BuildContext context) => _RenderButtonGroup(
    direction: direction,
    mainAxisSize: mainAxisSize,
    textDirection: Directionality.of(context),
  );
}

class _RenderButtonGroup extends RenderFlex {
  _RenderButtonGroup({
    required super.direction,
    required super.mainAxisSize,
    required super.textDirection,
  });

  @override
  void performLayout() {
    super.performLayout();
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child is! _RenderGroupSeparatorExtent ||
          child.orientation == direction) {
        continue;
      }
      final data = child.parentData! as FlexParentData;
      if (direction == Axis.horizontal) {
        child.layout(
          BoxConstraints.tightFor(width: child.size.width, height: size.height),
          parentUsesSize: true,
        );
        data.offset = Offset(data.offset.dx, 0);
      } else {
        child.layout(
          BoxConstraints.tightFor(width: size.width, height: child.size.height),
          parentUsesSize: true,
        );
        data.offset = Offset(0, data.offset.dy);
      }
    }
  }
}

class _GroupSeparatorExtent extends SingleChildRenderObjectWidget {
  const _GroupSeparatorExtent({
    required this.orientation,
    required super.child,
  });

  final Axis orientation;

  @override
  _RenderGroupSeparatorExtent createRenderObject(BuildContext context) =>
      _RenderGroupSeparatorExtent(orientation);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGroupSeparatorExtent renderObject,
  ) => renderObject.orientation = orientation;
}

class _RenderGroupSeparatorExtent extends RenderProxyBox {
  _RenderGroupSeparatorExtent(this._orientation);

  Axis _orientation;
  Axis get orientation => _orientation;
  set orientation(Axis value) {
    if (_orientation == value) return;
    _orientation = value;
    markNeedsLayout();
  }

  BoxConstraints _contentConstraints(BoxConstraints constraints) =>
      orientation == Axis.vertical
      ? constraints.copyWith(maxHeight: constraints.minHeight)
      : constraints.copyWith(maxWidth: constraints.minWidth);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child!.getDryLayout(_contentConstraints(constraints));

  @override
  void performLayout() {
    child!.layout(_contentConstraints(constraints), parentUsesSize: true);
    size = child!.size;
  }
}
