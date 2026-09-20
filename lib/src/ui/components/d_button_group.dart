import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
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
/// A direct nested group enables an 8px gap between the outer group's children.
class DButtonGroup extends StatefulWidget {
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
  State<DButtonGroup> createState() => _DButtonGroupState();
}

class _DButtonGroupState extends State<DButtonGroup> {
  int? _focusedIndex;

  void _focusChanged(int index, bool focused) {
    if (!mounted) return;
    final next = focused
        ? index
        : (_focusedIndex == index ? null : _focusedIndex);
    if (next != _focusedIndex) setState(() => _focusedIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    assert(children.isNotEmpty, 'A button group needs at least one child.');
    assert(
      widget.semanticLabel == null || widget.semanticLabel!.trim().isNotEmpty,
    );
    final axis = widget.orientation == DButtonGroupOrientation.horizontal
        ? Axis.horizontal
        : Axis.vertical;
    final containsNestedGroup = children.any((child) {
      final layoutChild = child is DButtonGroupExpanded ? child.child : child;
      return layoutChild is DButtonGroup;
    });
    Widget scope(int index, Widget child) => DJoinedControlScope(
      axis: axis,
      first: index == 0,
      last: index == children.length - 1,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: (focused) => _focusChanged(index, focused),
        child: child,
      ),
    );
    final scoped = <Widget>[
      for (var index = 0; index < children.length; index++)
        if (axis == Axis.horizontal && children[index] is DButtonGroupExpanded)
          Expanded(
            child: scope(
              index,
              (children[index] as DButtonGroupExpanded).child,
            ),
          )
        else
          scope(
            index,
            children[index] is DButtonGroupExpanded
                ? (children[index] as DButtonGroupExpanded).child
                : children[index],
          ),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: _ButtonGroupFlex(
        direction: axis,
        mainAxisSize: widget.mainAxisSize,
        spacing: containsNestedGroup ? DSpacing.sm : 0,
        focusedIndex: _focusedIndex,
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
/// horizontal when dividing controls in a vertical group. Two full-length
/// shades of [color] create a recessed edge matching the adjacent buttons.
class DButtonGroupSeparator extends StatelessWidget {
  const DButtonGroupSeparator({
    super.key,
    this.orientation = Axis.vertical,
    this.color,
    this.decorative = true,
    this.semanticLabel,
  });

  final Axis orientation;

  /// Adjacent button fill. Defaults to the secondary button color.
  final Color? color;
  final bool decorative;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final base = color ?? DTokens.of(context).muted;
    return _GroupSeparatorExtent(
      orientation: orientation,
      child: ColoredBox(
        color: Color.lerp(base, const Color(0xff000000), .25)!,
        child: Padding(
          padding: orientation == Axis.vertical
              ? const EdgeInsetsDirectional.only(start: 1)
              : const EdgeInsets.only(top: 1),
          child: DSeparator(
            orientation: orientation,
            color: Color.lerp(base, const Color(0xffffffff), .15),
            decorative: decorative,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
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
    final joined = DJoinedControlScope.maybeOf(context);
    final direction = Directionality.of(context);
    final radius = BorderRadius.circular(tokens.buttonTheme.radius);
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
      child: _GroupTextExtent(
        child: DecoratedBox(
          decoration: DControlDecoration(
            strokeWidth: 1,
            color: tokens.buttonTheme.outline.background,
            borderColor: tokens.buttonTheme.outline.border,
            borderRadius: joined?.resolveRadius(radius, direction) ?? radius,
            joinedAxis: joined?.omitsLeadingBorder ?? false
                ? joined!.axis
                : null,
          ),
          child: Padding(
            padding: padding,
            child: Align(
              alignment: alignment,
              widthFactor: 1,
              heightFactor: 1,
              child: text,
            ),
          ),
        ),
      ),
    );
  }
}

// Measure controls through their normal layout, then stretch passive text and separators
// to the resulting cross-axis extent. Intrinsic measurement cannot be used:
// composed controls such as DSelect contain LayoutBuilder.
class _ButtonGroupFlex extends Flex {
  const _ButtonGroupFlex({
    required super.direction,
    required super.mainAxisSize,
    required super.spacing,
    required super.children,
    required this.focusedIndex,
  });

  final int? focusedIndex;

  @override
  RenderFlex createRenderObject(BuildContext context) => _RenderButtonGroup(
    focusedIndex,
    direction: direction,
    mainAxisSize: mainAxisSize,
    textDirection: Directionality.of(context),
    spacing: spacing,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderButtonGroup renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.focusedIndex = focusedIndex;
  }
}

class _RenderButtonGroup extends RenderFlex {
  _RenderButtonGroup(
    this._focusedIndex, {
    required super.direction,
    required super.mainAxisSize,
    required super.textDirection,
    required super.spacing,
  });

  int? _focusedIndex;
  set focusedIndex(int? value) {
    if (_focusedIndex == value) return;
    _focusedIndex = value;
    markNeedsPaint();
  }

  @override
  void defaultPaint(PaintingContext context, Offset offset) {
    // Match focus-visible z-index without changing layout or traversal order.
    RenderBox? focusedChild;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (index++ == _focusedIndex) {
        focusedChild = child;
      } else {
        final data = child.parentData! as FlexParentData;
        context.paintChild(child, data.offset + offset);
      }
    }
    if (focusedChild != null) {
      final data = focusedChild.parentData! as FlexParentData;
      context.paintChild(focusedChild, data.offset + offset);
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    // Separators follow painted controls, not their invisible touch padding.
    Rect? surfaceBounds;
    var foundSurface = false;
    void collectSurfaces(RenderObject node) {
      if (node is RenderDJoinedControlSurface) {
        foundSurface = true;
        final bounds = MatrixUtils.transformRect(
          node.getTransformTo(this),
          node.layoutBounds,
        );
        surfaceBounds = surfaceBounds?.expandToInclude(bounds) ?? bounds;
      } else if (node is! _RenderButtonGroup) {
        node.visitChildren(collectSurfaces);
      }
    }

    for (var child = firstChild; child != null; child = childAfter(child)) {
      foundSurface = false;
      collectSurfaces(child);
      if (!foundSurface && child is! _RenderGroupSeparatorExtent) {
        final data = child.parentData! as FlexParentData;
        final bounds = data.offset & child.size;
        surfaceBounds = surfaceBounds?.expandToInclude(bounds) ?? bounds;
      }
    }
    for (var child = firstChild; child != null; child = childAfter(child)) {
      RenderBox? content = child;
      while (content is RenderProxyBox && content is! _RenderGroupTextExtent) {
        content = content.child;
      }
      if (content is! _RenderGroupTextExtent &&
          (child is! _RenderGroupSeparatorExtent ||
              child.orientation == direction)) {
        continue;
      }
      final data = child.parentData! as FlexParentData;
      final bounds = child is _RenderGroupSeparatorExtent
          ? surfaceBounds ?? (Offset.zero & size)
          : Offset.zero & size;
      if (direction == Axis.horizontal) {
        child.layout(
          child.constraints.copyWith(
            minHeight: bounds.height,
            maxHeight: bounds.height,
          ),
          parentUsesSize: true,
        );
        data.offset = Offset(data.offset.dx, bounds.top);
      } else {
        child.layout(
          child.constraints.copyWith(
            minWidth: bounds.width,
            maxWidth: bounds.width,
          ),
          parentUsesSize: true,
        );
        data.offset = Offset(bounds.left, data.offset.dy);
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

class _GroupTextExtent extends SingleChildRenderObjectWidget {
  const _GroupTextExtent({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGroupTextExtent();
}

class _RenderGroupTextExtent extends RenderProxyBox {}
