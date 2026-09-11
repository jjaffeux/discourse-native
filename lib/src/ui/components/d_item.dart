import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_separator.dart';

enum DItemVariant { standard, outline, muted }

enum DItemSize { standard, sm, xs }

enum DItemMediaVariant { standard, icon, avatar, image }

/// A content row, optionally an action or link. Editable fields keep their own
/// FormField owner; selection is controlled by the caller.
///
/// Place [DItemContent] in [children] for flexible content (only the first grows).
/// Header/footer occupy the full width. Secondary controls remain independent
/// gesture and focus targets even when [onPressed] makes the row interactive.
class DItem extends StatefulWidget {
  const DItem({
    super.key,
    this.children = const [],
    this.header,
    this.footer,
    this.variant = DItemVariant.standard,
    this.size = DItemSize.standard,
    this.onPressed,
    this.link = false,
    this.enabled = true,
    this.selected = false,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.padding,
  });

  final List<Widget> children;
  final DItemHeader? header;
  final DItemFooter? footer;
  final DItemVariant variant;
  final DItemSize size;
  final VoidCallback? onPressed;

  /// Uses link semantics. Navigation and external URL policy remain caller-owned.
  final bool link;
  final bool enabled;

  /// Highlights the current item with an accent border, tint and checkmark.
  /// The caller owns selection changes; activation only calls [onPressed].
  final bool selected;

  /// Borrowed when supplied; never disposed by Item.
  final FocusNode? focusNode;
  final bool autofocus;

  /// Additional row announcement. Descendants retain their own semantics;
  /// use ExcludeSemantics on passive content when this replaces its full label.
  final String? semanticLabel;

  /// Explicit composition override, e.g. zero inside a menu-owned hit target.
  final EdgeInsetsGeometry? padding;

  @override
  State<DItem> createState() => _DItemState();
}

class _DItemState extends State<DItem> {
  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());
  bool _hover = false;
  bool _focusVisible = false;
  bool get _active => widget.enabled && widget.onPressed != null;

  @override
  void didUpdateWidget(DItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != null && _ownedFocus != null) {
      _ownedFocus!.dispose();
      _ownedFocus = null;
    }
  }

  @override
  void dispose() {
    _ownedFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final xs = widget.size == DItemSize.xs;
    final gap = xs ? 8.0 : 10.0;
    final described = widget.children.any(
      (child) =>
          child is DItemContent &&
          child.children.any((c) => c is DItemDescription),
    );
    final focus = _active && _focusVisible;
    final background = widget.selected
        ? tokens.primary.withValues(alpha: .12)
        : _active && _hover
        ? tokens.muted
        : widget.variant == DItemVariant.muted
        ? tokens.muted.withValues(alpha: tokens.muted.a * .5)
        : Colors.transparent;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    Widget result = _ItemScope(
      size: widget.size,
      described: described,
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: DiscourseTypography.sm,
          height: 20 / 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: tokens.foreground,
        ),
        child: CustomPaint(
          foregroundPainter: _ItemRing(
            focus
                ? tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5)
                : Colors.transparent,
            tokens.radius,
          ),
          child: AnimatedContainer(
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 100),
            ),
            curve: Curves.easeInOut,
            constraints: BoxConstraints(minHeight: touch && _active ? 48 : 0),
            decoration: BoxDecoration(
              color: background,
              borderRadius: tokens.borderRadius,
              border: Border.all(
                color: focus
                    ? tokens.focusRing
                    : widget.selected
                    ? tokens.primary
                    : widget.variant == DItemVariant.outline
                    ? tokens.border
                    : Colors.transparent,
              ),
            ),
            padding:
                widget.padding ??
                EdgeInsets.symmetric(
                  horizontal: xs ? 10 : 12,
                  vertical: xs ? 8 : 10,
                ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.header != null) ...[
                  widget.header!,
                  if (widget.children.isNotEmpty || widget.footer != null)
                    SizedBox(height: gap),
                ],
                if (widget.children.isNotEmpty)
                  _ItemBody(
                    gap: gap,
                    described: described,
                    children: [
                      ...widget.children,
                      if (widget.selected)
                        DItemMedia(
                          child: ExcludeSemantics(
                            child: DIcon(
                              DIcons.check,
                              size: 16,
                              color: tokens.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (widget.footer != null) ...[
                  if (widget.children.isNotEmpty) SizedBox(height: gap),
                  widget.footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.onPressed != null || widget.link) {
      result = FocusableActionDetector(
        enabled: _active,
        focusNode: _focus,
        autofocus: widget.autofocus,
        mouseCursor: _active
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        onShowFocusHighlight: (value) => setState(() => _focusVisible = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _active
              ? () {
                  _focus.requestFocus();
                  widget.onPressed!();
                }
              : null,
          child: result,
        ),
      );
      result = Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          // Descendant controls own their keystrokes, including Space/Return.
          if (!_active || !_focus.hasPrimaryFocus) {
            return KeyEventResult.ignored;
          }
          final activates =
              event.logicalKey == LogicalKeyboardKey.enter ||
              (!widget.link && event.logicalKey == LogicalKeyboardKey.space);
          if (!activates) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) widget.onPressed!();
          return KeyEventResult.handled;
        },
        child: result,
      );
    }
    return Semantics(
      container: true,
      button: widget.onPressed != null && !widget.link ? true : null,
      link: widget.link ? true : null,
      enabled: widget.onPressed != null || widget.link ? _active : null,
      label: widget.semanticLabel,
      selected: widget.selected ? true : null,
      onTap: _active ? widget.onPressed : null,
      child: result,
    );
  }
}

class _ItemBody extends MultiChildRenderObjectWidget {
  const _ItemBody({
    required this.gap,
    required this.described,
    required super.children,
  });
  final double gap;
  final bool described;
  int get flexibleIndex =>
      children.indexWhere((child) => child is DItemContent);
  Set<int> get mediaIndices => {
    for (var i = 0; i < children.length; i++)
      if (children[i] is DItemMedia) i,
  };
  @override
  RenderObject createRenderObject(BuildContext context) => _ItemLayout(
    gap,
    described,
    flexibleIndex,
    mediaIndices,
    Directionality.of(context),
    MediaQuery.textScalerOf(context).scale(14) > 21,
  );
  @override
  void updateRenderObject(BuildContext context, _ItemLayout renderObject) {
    renderObject
      ..gap = gap
      ..described = described
      ..flexibleIndex = flexibleIndex
      ..mediaIndices = mediaIndices
      ..direction = Directionality.of(context)
      ..largeText = MediaQuery.textScalerOf(context).scale(14) > 21
      ..markNeedsLayout();
  }
}

// One layout owner preserves child state across reflow and avoids intrinsic
// measurement (avatars and caller controls may themselves use LayoutBuilder).
class _ItemParentData extends ContainerBoxParentData<RenderBox> {}

class _ItemLayout extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _ItemLayout(
    this.gap,
    this.described,
    this.flexibleIndex,
    this.mediaIndices,
    this.direction,
    this.largeText,
  );
  double gap;
  bool described;
  int flexibleIndex;
  Set<int> mediaIndices;
  TextDirection direction;
  bool largeText;
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _ItemParentData();
    }
  }

  @override
  void performLayout() {
    final boxes = getChildrenAsList();
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 448.0;
    var stacked = largeText || width < 160;
    var occupied = gap * (boxes.length - 1);
    if (!stacked) {
      for (var i = 0; i < boxes.length; i++) {
        if (i == flexibleIndex) continue;
        boxes[i].layout(
          BoxConstraints(maxWidth: flexibleIndex < 0 ? width : width * .5),
          parentUsesSize: true,
        );
        occupied += boxes[i].size.width;
      }
      stacked =
          occupied > width || (flexibleIndex >= 0 && width - occupied < 64);
      if (!stacked && flexibleIndex >= 0) {
        boxes[flexibleIndex].layout(
          BoxConstraints.tightFor(width: width - occupied),
          parentUsesSize: true,
        );
      }
    }
    var height = 0.0;
    if (stacked) {
      for (final box in boxes) {
        box.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
        height += box.size.height;
      }
      height += gap * (boxes.length - 1);
    } else {
      for (final box in boxes) {
        if (box.size.height > height) height = box.size.height;
      }
    }
    size = constraints.constrain(Size(width, height));
    var position = 0.0;
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final x = stacked ? 0.0 : position;
      final y = stacked
          ? position
          : described && mediaIndices.contains(i)
          ? 2.0
          : (height - box.size.height) / 2;
      (box.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
        direction == TextDirection.rtl ? size.width - x - box.size.width : x,
        y,
      );
      position += (stacked ? box.size.height : box.size.width) + gap;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _ItemScope extends InheritedWidget {
  const _ItemScope({
    required this.size,
    required this.described,
    required super.child,
  });
  final DItemSize size;
  final bool described;
  static DItemSize sizeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ItemScope>()?.size ??
      DItemSize.standard;
  @override
  bool updateShouldNotify(_ItemScope oldWidget) =>
      size != oldWidget.size || described != oldWidget.described;
}

/// Eager composition for short lists. Keep application ListView.builder owners
/// for paginated lists. [size] sets spacing when children wrap their own Items;
/// otherwise direct Item children determine the tightest spacing as CSS :has.
class DItemGroup extends StatelessWidget {
  const DItemGroup({
    super.key,
    required this.children,
    this.size,
    this.spacing,
  });
  final List<Widget> children;
  final DItemSize? size;
  final double? spacing;
  @override
  Widget build(BuildContext context) {
    final effective =
        size ??
        (children.whereType<DItem>().any((c) => c.size == DItemSize.xs)
            ? DItemSize.xs
            : children.whereType<DItem>().any((c) => c.size == DItemSize.sm)
            ? DItemSize.sm
            : DItemSize.standard);
    final gap =
        spacing ??
        switch (effective) {
          DItemSize.standard => 16.0,
          DItemSize.sm => 10.0,
          DItemSize.xs => 8.0,
        };
    return Semantics(
      role: SemanticsRole.list,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            if (children[i] is DItemSeparator)
              children[i]
            else
              Semantics(role: SemanticsRole.listItem, child: children[i]),
          ],
        ],
      ),
    );
  }
}

class DItemSeparator extends StatelessWidget {
  const DItemSeparator({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: DSeparator(),
  );
}

/// Avatar/default preserve child dimensions. Image clips at 40/32/24px;
/// supply a cover-fitting image. Icon supplies the reference 16px IconTheme.
class DItemMedia extends StatelessWidget {
  const DItemMedia({
    super.key,
    required this.child,
    this.variant = DItemMediaVariant.standard,
  });
  final Widget child;
  final DItemMediaVariant variant;
  @override
  Widget build(BuildContext context) {
    if (variant == DItemMediaVariant.image) {
      final dimension = switch (_ItemScope.sizeOf(context)) {
        DItemSize.standard => 40.0,
        DItemSize.sm => 32.0,
        DItemSize.xs => 24.0,
      };
      return ClipRRect(
        borderRadius: BorderRadius.circular(DTokens.of(context).radius * .6),
        child: SizedBox.square(dimension: dimension, child: child),
      );
    }
    return IconTheme.merge(
      data: IconThemeData(
        size: variant == DItemMediaVariant.icon ? 16 : null,
        color: DTokens.of(context).foreground,
      ),
      child: child,
    );
  }
}

class DItemContent extends StatelessWidget {
  const DItemContent({
    super.key,
    required this.children,
    this.spacing,
    this.alignment = CrossAxisAlignment.start,
  });
  final List<Widget> children;
  final double? spacing;
  final CrossAxisAlignment alignment;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: alignment,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          SizedBox(
            height:
                spacing ?? (_ItemScope.sizeOf(context) == DItemSize.xs ? 0 : 4),
          ),
        children[i],
      ],
    ],
  );
}

/// The reference clamps to one line. Large native text reflows automatically;
/// [maxLines] may be null when full domain content must remain visible.
class DItemTitle extends StatelessWidget {
  const DItemTitle({super.key, required this.child, this.maxLines = 1});
  final Widget child;
  final int? maxLines;
  @override
  Widget build(BuildContext context) {
    final effectiveMaxLines = MediaQuery.textScalerOf(context).scale(14) > 21
        ? null
        : maxLines;
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context).style.merge(
        const TextStyle(
          fontSize: DiscourseTypography.sm,
          height: 1.375,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
      maxLines: effectiveMaxLines,
      overflow: effectiveMaxLines == null
          ? TextOverflow.clip
          : TextOverflow.ellipsis,
      child: child,
    );
  }
}

class DItemDescription extends StatelessWidget {
  const DItemDescription({
    super.key,
    required this.child,
    this.maxLines = 2,
    this.height = 1.5,
  });
  final Widget child;
  final int? maxLines;
  final double height;
  @override
  Widget build(BuildContext context) {
    final effectiveMaxLines = MediaQuery.textScalerOf(context).scale(14) > 21
        ? null
        : maxLines;
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context).style.merge(
        TextStyle(
          fontSize: _ItemScope.sizeOf(context) == DItemSize.xs
              ? DiscourseTypography.xs
              : DiscourseTypography.sm,
          height: height,
          fontWeight: FontWeight.w400,
          color: DTokens.of(context).mutedForeground,
          letterSpacing: 0,
        ),
      ),
      textAlign: TextAlign.start,
      maxLines: effectiveMaxLines,
      overflow: effectiveMaxLines == null
          ? TextOverflow.clip
          : TextOverflow.ellipsis,
      child: child,
    );
  }
}

class DItemActions extends StatelessWidget {
  const DItemActions({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

/// Full-width content above the body. The child owns its row/wrap/image layout.
class DItemHeader extends StatelessWidget {
  const DItemHeader({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// Full-width content below the body. The child owns its row/wrap layout.
class DItemFooter extends StatelessWidget {
  const DItemFooter({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _ItemRing extends CustomPainter {
  const _ItemRing(this.color, this.radius);
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final inner = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawDRRect(inner.inflate(3), inner, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ItemRing oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
