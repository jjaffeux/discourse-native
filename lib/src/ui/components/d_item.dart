import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/interactive_row.dart';
import '../foundation/tokens.dart';
import 'd_separator.dart';

enum DItemVariant { standard, outline, muted }

enum DItemSize { standard, sm, xs }

/// Card follows Card surface corners, menu uses 8px, and fullWidth stays flush.
enum DItemShape { standard, card, menu, fullWidth }

enum DItemSelectionStyle {
  tinted,

  /// Accent fill without a border or leading stripe.
  filled,
  outline,
  neutral,
  strongNeutral,
  leadingAccent,
}

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
    this.borderColor,
    this.size = DItemSize.standard,
    this.fitContent = false,
    this.shape = DItemShape.standard,
    this.onPressed,
    this.onHoverChanged,
    this.link = false,
    this.enabled = true,
    this.selected = false,
    this.selectionStyle = DItemSelectionStyle.tinted,
    this.showSelectionIndicator = true,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.padding,
    this.cornerAction,
    this.dragData,
    this.dragFeedback,
  });

  final List<Widget> children;
  final DItemHeader? header;
  final DItemFooter? footer;
  final DItemVariant variant;

  /// Overrides the outline variant's resting border color. Selected and
  /// keyboard-focused items keep their theme accent and focus colors.
  final Color? borderColor;

  final DItemSize size;

  /// Whether the item uses its content width within the parent's constraints.
  ///
  /// Use loose constraints, such as a [Wrap], for naturally sized items.
  /// Tight constraints and children that expand still determine the width.
  /// Padding, focus, activation, and dragging keep the same visible bounds.
  final bool fitContent;

  final DItemShape shape;
  final VoidCallback? onPressed;

  /// Pointer entry/exit for an enabled, actionable item. Does not report
  /// keyboard focus or removal; callers must release async work on disposal.
  final ValueChanged<bool>? onHoverChanged;

  /// Uses link semantics. Navigation and external URL policy remain caller-owned.
  final bool link;
  final bool enabled;

  /// Highlights the current item using [selectionStyle] and a checkmark.
  /// The caller owns selection changes; activation only calls [onPressed].
  final bool selected;

  /// Leading-accent selection uses an accent tint and a directional 3px edge,
  /// with a fainter accent tint on hover. Combine with fullWidth for flush rows.
  /// Outline selection keeps the normal surface and paints a 2px accent border
  /// without moving the content, with a subtle neutral fill on hover. Neutral
  /// selection uses a subtle surface tint and no accent border. Strong neutral
  /// selection uses the same treatment at menu-selected emphasis (13%). Both
  /// retain keyboard focus styling.
  final DItemSelectionStyle selectionStyle;

  /// Shows a checkmark when selected. Selection styling and semantics remain
  /// when false.
  final bool showSelectionIndicator;

  /// Borrowed when supplied; never disposed by Item.
  final FocusNode? focusNode;
  final bool autofocus;

  /// Additional row announcement. Descendants retain their own semantics;
  /// use ExcludeSemantics on passive content when this replaces its full label.
  final String? semanticLabel;

  /// Explicit composition override, e.g. zero inside a menu-owned hit target.
  final EdgeInsetsGeometry? padding;

  /// An independent control in the top trailing corner, usually a small Button.
  /// Hover or focus within the item reveals it immediately. Touch platforms and
  /// accessible navigation keep it visible. Its focus, semantics and state stay
  /// mounted while hidden. Reserve this corner in the header's content.
  final Widget? cornerAction;

  /// Immutable payload offered when the entire row is dragged.
  /// Ordinary tap, focus, and link actions remain available.
  final Object? dragData;

  /// Visual shown under the pointer while [dragData] is being dragged.
  final Widget? dragFeedback;

  @override
  State<DItem> createState() => _DItemState();
}

class _DItemState extends State<DItem> {
  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());
  bool _hover = false;
  bool _pressed = false;
  bool _focusVisible = false;
  bool _focusWithin = false;
  bool get _active => widget.enabled && widget.onPressed != null;

  @override
  void didUpdateWidget(DItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_active) _pressed = false;
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
    final gap = xs ? 8.0 : 12.0;
    final described = widget.children.any(
      (child) =>
          child is DItemContent &&
          child.children.any((c) => c is DItemDescription),
    );
    final focus = _active && _focusVisible;
    final outlineSelection =
        widget.selectionStyle == DItemSelectionStyle.outline;
    final neutralSelection =
        widget.selectionStyle == DItemSelectionStyle.neutral ||
        widget.selectionStyle == DItemSelectionStyle.strongNeutral;
    final strongNeutralSelection =
        widget.selectionStyle == DItemSelectionStyle.strongNeutral;
    final leadingSelection =
        widget.selectionStyle == DItemSelectionStyle.leadingAccent;
    final radius = switch (widget.shape) {
      DItemShape.fullWidth => 0.0,
      DItemShape.card => DRadius.panel,
      DItemShape.menu => 8.0,
      DItemShape.standard => DRadius.popover,
    };
    final borderRadius = BorderRadius.circular(radius);
    final background = widget.selected && !outlineSelection
        ? neutralSelection
              ? tokens.foreground.withValues(
                  alpha: strongNeutralSelection ? .13 : .05,
                )
              : tokens.primary.withValues(alpha: .12)
        : _active && (_hover || _pressed)
        ? leadingSelection
              ? tokens.primary.withValues(alpha: _pressed ? .09 : .06)
              : outlineSelection
              ? tokens.foreground.withValues(
                  alpha: Theme.of(context).brightness == Brightness.light
                      ? .09
                      : .05,
                )
              : neutralSelection
              ? tokens.foreground.withValues(alpha: .06)
              : DControlStyle.rowHover(tokens)
        : widget.variant == DItemVariant.muted
        ? tokens.surface
        : widget.variant == DItemVariant.outline
        ? tokens.surface
        : Colors.transparent;
    Widget result = _ItemScope(
      size: widget.size,
      described: described,
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: DControlStyle.labelFontSize,
          height: DControlStyle.labelLineHeight / DControlStyle.labelFontSize,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: tokens.foreground,
        ),
        child: CustomPaint(
          foregroundPainter: _ItemRing(
            focus ? tokens.focusRing : Colors.transparent,
            radius,
          ),
          child: interactiveRowSurface(
            foregroundDecoration: widget.selected && leadingSelection
                ? BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(color: tokens.primary, width: 3),
                    ),
                  )
                : widget.selected && outlineSelection
                ? BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(color: tokens.primary, width: 2),
                  )
                : null,
            decoration: BoxDecoration(
              color: background,
              borderRadius: borderRadius,
              border: Border.all(
                width: DControlDecoration.borderWidth,
                strokeAlign: BorderSide.strokeAlignOutside,
                color: focus
                    ? tokens.focusRing
                    : widget.selected &&
                          !neutralSelection &&
                          !leadingSelection &&
                          widget.selectionStyle != DItemSelectionStyle.filled
                    ? tokens.primary
                    : widget.variant == DItemVariant.outline
                    ? widget.borderColor ?? tokens.border
                    : Colors.transparent,
              ),
            ),
            padding:
                widget.padding ??
                EdgeInsets.symmetric(
                  horizontal: xs
                      ? 10
                      : widget.size == DItemSize.sm
                      ? 12
                      : 16,
                  vertical: xs
                      ? 8
                      : widget.size == DItemSize.sm
                      ? 10
                      : 12,
                ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: widget.fitContent
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.stretch,
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
                    fitContent: widget.fitContent,
                    children: [
                      ...widget.children,
                      if (widget.selected && widget.showSelectionIndicator)
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
    if (widget.cornerAction case final action?) {
      final showAction =
          _hover ||
          _focusWithin ||
          DControlStyle.isTouch(context) ||
          MediaQuery.accessibleNavigationOf(context);
      result = Stack(
        fit: StackFit.passthrough,
        children: [
          result,
          PositionedDirectional(
            top: DSpacing.sm,
            end: DSpacing.sm,
            child: Opacity(
              opacity: showAction ? 1 : 0,
              alwaysIncludeSemantics: true,
              child: action,
            ),
          ),
        ],
      );
    }
    if (widget.onPressed != null ||
        widget.link ||
        widget.cornerAction != null) {
      // Pointer hover remains visible while the app suppresses keyboard focus
      // rings. FocusableActionDetector's hover highlight follows that policy.
      result = MouseRegion(
        onEnter: (_) {
          setState(() => _hover = true);
          if (_active) widget.onHoverChanged?.call(true);
        },
        onExit: (_) {
          setState(() => _hover = false);
          if (_active) widget.onHoverChanged?.call(false);
        },
        child: FocusableActionDetector(
          enabled: _active,
          focusNode: _focus,
          autofocus: widget.autofocus,
          mouseCursor: _active
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowFocusHighlight: (value) =>
              setState(() => _focusVisible = value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: _active ? (_) => setState(() => _pressed = true) : null,
            onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
            // Always set, so the tap recognizer outlives a mid-press disable.
            onTapCancel: () => setState(() => _pressed = false),
            onTap: _active
                ? () {
                    _focus.requestFocus();
                    widget.onPressed!();
                  }
                : null,
            child: result,
          ),
        ),
      );
      result = Focus(
        canRequestFocus: false,
        onFocusChange: widget.cornerAction == null
            ? null
            : (value) => setState(() => _focusWithin = value),
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
    final item = Semantics(
      container: true,
      button: widget.onPressed != null && !widget.link ? true : null,
      link: widget.link ? true : null,
      enabled: widget.onPressed != null || widget.link ? _active : null,
      label: widget.semanticLabel,
      selected: widget.selected ? true : null,
      onTap: _active ? widget.onPressed : null,
      // Toggling enabled keeps the tree shape: a remount would recreate child
      // state and dispose the tap recognizer of a pointer still down.
      child: Opacity(opacity: widget.enabled ? 1 : .5, child: result),
    );
    if (widget.dragData == null) return item;
    return Draggable<Object>(
      data: widget.dragData!,
      maxSimultaneousDrags: widget.enabled ? null : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: widget.dragFeedback ?? const SizedBox.shrink(),
      child: item,
    );
  }
}

class _ItemBody extends MultiChildRenderObjectWidget {
  const _ItemBody({
    required this.gap,
    required this.described,
    required this.fitContent,
    required super.children,
  });
  final double gap;
  final bool described;
  final bool fitContent;
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
    fitContent,
  );
  @override
  void updateRenderObject(BuildContext context, _ItemLayout renderObject) {
    renderObject
      ..gap = gap
      ..described = described
      ..fitContent = fitContent
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
    this.fitContent,
  );
  double gap;
  bool described;
  int flexibleIndex;
  Set<int> mediaIndices;
  TextDirection direction;
  bool largeText;
  bool fitContent;
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
          fitContent
              ? BoxConstraints(maxWidth: width - occupied)
              : BoxConstraints.tightFor(width: width - occupied),
          parentUsesSize: true,
        );
      }
    }
    var height = 0.0;
    var contentWidth = 0.0;
    if (stacked) {
      for (final box in boxes) {
        box.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
        height += box.size.height;
        if (box.size.width > contentWidth) contentWidth = box.size.width;
      }
      height += gap * (boxes.length - 1);
    } else {
      contentWidth = gap * (boxes.length - 1);
      for (final box in boxes) {
        contentWidth += box.size.width;
        if (box.size.height > height) height = box.size.height;
      }
    }
    size = constraints.constrain(
      Size(fitContent ? contentWidth : width, height),
    );
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
          fontSize: DiscourseTypography.rowTitle,
          height: DiscourseTypography.lineHeightRowTitle,
          fontWeight: FontWeight.w600,
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
    this.height = DiscourseTypography.lineHeightPreview,
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
          fontSize: DiscourseTypography.preview,
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
    canvas.drawDRRect(
      inner.inflate(3),
      inner.inflate(2),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ItemRing oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
