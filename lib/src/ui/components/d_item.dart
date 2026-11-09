import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../foundation/icons/d_icons.dart';
import '../../theme/d_icon.dart';
import '../../theme/discourse_typography.dart';
import '../../theme/tokens.dart';
import '../foundation/control_hit_test.dart';
import '../foundation/control_style.dart';
import '../foundation/highlight_mode_tracking.dart';
import '../foundation/interactive_row.dart';
import '../foundation/item_interaction.dart';
import '../foundation/sidebar_row_surface.dart';
import '../foundation/touch_target.dart';
import 'd_card.dart';
import 'd_link_interaction.dart';
import 'd_separator.dart';

enum DItemVariant {
  standard,
  outline,
  muted,

  /// A grid action with selected-color focus and the Native hover treatment.
  picker,
}

enum DItemSize {
  standard,
  sm,
  xs,

  /// No inset or internal gaps. Rich content supplies its own visible bounds
  /// and text metrics while Item retains activation and focus treatment.
  artwork,
}

/// Card follows Card surface corners, menu uses 8px, and fullWidth stays flush.
enum DItemShape { standard, card, menu, fullWidth, pill, calendarEvent }

enum DItemSelectionStyle {
  tinted,

  /// Accent fill without a border or leading stripe.
  filled,
  outline,

  strongNeutral,

  /// Flat sidebar hover and selection fills.
  sidebar,
  leadingAccent,
}

enum DItemMediaVariant { standard, icon, avatar }

typedef DItemPreviewBuilder =
    ({Widget? header, Widget preview}) Function(BuildContext, BoxConstraints);

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
    this.highlightOnInteraction = true,
    this.link = false,
    this.enabled = true,
    this.selected = false,
    this.closed = false,
    this.closedRuleAbove = false,
    this.closedRuleBelow = false,
    this.selectionStyle = DItemSelectionStyle.tinted,
    this.showSelectionIndicator = true,
    this.focusNode,
    this.mouseCursor,
    this.clipBehavior = Clip.none,

    this.semanticLabel,
    this.padding,
    this.cornerAction,
    this.dragData,
    this.dragFeedback,
  }) : _previewBuilder = null,
       _previewKey = null;

  /// A row whose preview card owns its hover, press, and focus treatment.
  const DItem.preview({
    super.key,
    required DItemPreviewBuilder builder,
    required VoidCallback this.onPressed,
    this.semanticLabel,
    this.focusNode,
    this._previewKey,
  }) : _previewBuilder = builder,
       children = const [],
       header = null,
       footer = null,
       variant = DItemVariant.standard,
       borderColor = null,
       size = DItemSize.artwork,
       fitContent = false,
       shape = DItemShape.fullWidth,
       onHoverChanged = null,
       highlightOnInteraction = true,
       link = false,
       enabled = true,
       selected = false,
       closed = false,
       closedRuleAbove = false,
       closedRuleBelow = false,
       selectionStyle = DItemSelectionStyle.tinted,
       showSelectionIndicator = true,
       mouseCursor = null,
       clipBehavior = Clip.none,
       padding = const EdgeInsets.fromLTRB(12, 20, 12, 22),
       cornerAction = null,
       dragData = null,
       dragFeedback = null;

  final DItemPreviewBuilder? _previewBuilder;
  final Key? _previewKey;

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

  /// Whether hover and press paint an interaction background.
  ///
  /// When `false`, the resting surface, selected state, keyboard focus ring,
  /// and [onHoverChanged] callbacks are retained.
  final bool highlightOnInteraction;

  /// Uses link semantics. Navigation and external URL policy remain caller-owned.
  final bool link;
  final bool enabled;

  /// Highlights the current item using [selectionStyle] and a checkmark.
  /// The caller owns selection changes; activation only calls [onPressed].
  final bool selected;

  /// Shades a closed row with a trailing hatch, leaving the reading area clear.
  /// Resting corners are square; selection keeps the item's selected shape.
  final bool closed;

  /// Closed rows own their inset, fading boundary rules. The list suppresses
  /// the neighboring separator and omits a rule beside a selected neighbor,
  /// at the list edge, or below a consecutive closed row.
  final bool closedRuleAbove;
  final bool closedRuleBelow;

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

  /// Cursor for enabled artwork, including draggable rail destinations.
  final MouseCursor? mouseCursor;

  /// Clips full-bleed artwork to the same corners as the interactive item.
  /// Overlay badges may retain the default non-clipping composition.
  final Clip clipBehavior;

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

/// A rail destination with a 44px phone action in a 52px layout slot, or a
/// 36px desktop action in a 48px slot.
/// The marker is decorative. Hover changes its Native-owned height.
class DItemRail extends StatefulWidget {
  const DItemRail({
    super.key,
    required this.artwork,
    required this.onPressed,
    required this.selected,
    required this.markerColor,
    this.markerKey,
    this.mouseCursor,
    this.controlWrapper,
  });

  final Widget artwork;
  final VoidCallback onPressed;
  final bool selected;
  final Color markerColor;
  final Key? markerKey;
  final MouseCursor? mouseCursor;
  final Widget Function(BuildContext, Widget)? controlWrapper;

  /// Shared with the rail's image adapter and drag feedback.
  static double artworkDimensionOf(BuildContext context) =>
      DControlStyle.isTouch(context) ? 44 : 36;

  /// Shared with the rail's lazy list and reorder insertion calculation.
  static double itemExtentOf(BuildContext context) =>
      DControlStyle.isTouch(context) ? 52 : 48;

  static BorderRadius artworkBorderRadiusOf(
    BuildContext context, {
    required bool selected,
  }) => BorderRadius.circular(
    selected
        ? DControlStyle.isTouch(context)
              ? 14
              : 12
        : artworkDimensionOf(context) / 2,
  );

  @override
  State<DItemRail> createState() => _DItemRailState();
}

class _DItemRailState extends State<DItemRail> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mobile = DControlStyle.isTouch(context);
    final dimension = DItemRail.artworkDimensionOf(context);
    final action = DItem(
      size: DItemSize.artwork,
      shape: DItemShape.pill,
      mouseCursor: widget.mouseCursor,
      onPressed: widget.onPressed,
      onHoverChanged: (hovered) => setState(() => _hovered = hovered),
      children: [SizedBox.square(dimension: dimension, child: widget.artwork)],
    );
    final control = widget.controlWrapper?.call(context, action) ?? action;
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        IgnorePointer(
          child: AnimatedContainer(
            key: widget.markerKey,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 4,
            height: widget.selected
                ? dimension - 8
                : mobile
                ? 0
                : _hovered
                ? 16
                : 8,
            decoration: BoxDecoration(
              color: widget.markerColor,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
            ),
          ),
        ),
        Center(
          child: SizedBox.square(
            dimension: DItemRail.itemExtentOf(context),
            child: Center(child: control),
          ),
        ),
      ],
    );
  }
}

class _DItemState extends State<DItem> with DHighlightModeTracking {
  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());
  bool _hover = false;
  bool _pressed = false;
  bool _focused = false;
  bool get _canRequestFocus =>
      switch (MediaQuery.maybeNavigationModeOf(context)) {
        NavigationMode.directional => true,
        NavigationMode.traditional || null => _active,
      };
  bool get _focusVisible =>
      _focused && _canRequestFocus && highlightModeShowsHighlight;
  bool _focusWithin = false;
  bool _pointerOnChildControl = false;
  bool get _active => widget.enabled && widget.onPressed != null;

  bool _childControlAt(Offset position, VoidCallback activate) {
    final root = context.findRenderObject();
    final hits = HitTestResult();
    GestureBinding.instance.hitTestInView(
      hits,
      position,
      View.of(context).viewId,
    );
    for (final entry in hits.path) {
      final hit = entry.target;
      if (hit is! RenderObject || !isControlRenderObject(hit)) continue;
      if (hit is RenderSemanticsGestureHandler && hit.onTap == null) continue;
      if (hit is RenderSemanticsAnnotations &&
          identical(hit.properties.onTap, activate)) {
        continue;
      }
      for (RenderObject? node = hit; node != null; node = node.parent) {
        if (identical(node, root)) return true;
      }
    }
    return false;
  }

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
    final linkActivation = DLinkInteractionBinding.capture(
      context,
      widget.onPressed,
    );
    final previewBuilder = widget._previewBuilder;
    final children = previewBuilder == null
        ? widget.children
        : <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final content = previewBuilder(context, constraints);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (content.header case final header?) ...[
                      header,
                      const SizedBox(height: 13),
                    ],
                    DCard(
                      key: widget._previewKey,
                      variant: DCardVariant.itemPreview,
                      child: content.preview,
                    ),
                  ],
                );
              },
            ),
          ];
    final tokens = DTokens.of(context);
    final drawer =
        widget.selectionStyle == DItemSelectionStyle.sidebar &&
        DSidebarRowScope.drawerOf(context);
    final xs = widget.size == DItemSize.xs;
    final artwork = widget.size == DItemSize.artwork;
    final gap = drawer
        ? 8.0
        : artwork
        ? 0.0
        : xs
        ? 8.0
        : 12.0;
    final described = children.any(
      (child) =>
          child is DItemContent &&
          child.children.any((c) => c is DItemDescription),
    );
    final preview = widget._previewBuilder != null;
    final focus = _active && _focusVisible && !preview;
    final outlineSelection =
        widget.selectionStyle == DItemSelectionStyle.outline;
    final neutralSelection =
        widget.selectionStyle == DItemSelectionStyle.strongNeutral ||
        widget.selectionStyle == DItemSelectionStyle.sidebar;
    final sidebarSelection =
        widget.selectionStyle == DItemSelectionStyle.sidebar;
    final strongNeutralSelection =
        widget.selectionStyle == DItemSelectionStyle.strongNeutral;
    final leadingSelection =
        widget.selectionStyle == DItemSelectionStyle.leadingAccent;
    final radius = widget.closed && !widget.selected
        ? 0.0
        : switch (widget.shape) {
            DItemShape.fullWidth => 0.0,
            DItemShape.calendarEvent => 3.0,
            DItemShape.pill => DRadius.pill,
            DItemShape.card => DRadius.panel,
            DItemShape.menu => 8.0,
            DItemShape.standard => DRadius.popover,
          };
    final borderRadius = BorderRadius.circular(radius);
    final background =
        widget.variant == DItemVariant.picker && _active && _focused
        ? tokens.selected
        : widget.selected && !outlineSelection
        ? neutralSelection
              ? tokens.foreground.withValues(
                  alpha: strongNeutralSelection ? .13 : .05,
                )
              : tokens.selectionTint
        : !preview &&
              widget.highlightOnInteraction &&
              _active &&
              (_hover || _pressed)
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
    final contentPadding =
        widget.padding ??
        (drawer
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : artwork
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
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
              ));
    Widget content =
        artwork &&
            widget.header == null &&
            widget.footer == null &&
            children.length == 1 &&
            !(widget.selected && widget.showSelectionIndicator)
        ? ClipRRect(
            borderRadius: borderRadius,
            clipBehavior: widget.clipBehavior,
            child: children.single,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: widget.fitContent
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.stretch,
            children: [
              if (widget.header != null) ...[
                widget.header!,
                if (children.isNotEmpty || widget.footer != null)
                  SizedBox(height: gap),
              ],
              if (children.isNotEmpty)
                _ItemBody(
                  gap: gap,
                  described: described,
                  fitContent: widget.fitContent,
                  children: [
                    ...children,
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
                if (children.isNotEmpty) SizedBox(height: gap),
                widget.footer!,
              ],
            ],
          );
    content = widget.closed
        ? CustomPaint(
            painter: _ClosedHatch(
              tokens.foreground,
              borderRadius,
              Directionality.of(context),
            ),
            foregroundPainter: _ClosedRules(
              tokens.footerBorder,
              Directionality.of(context),
              above: widget.closedRuleAbove,
              below: widget.closedRuleBelow,
            ),
            child: Padding(padding: contentPadding, child: content),
          )
        : Padding(padding: contentPadding, child: content);
    Widget result = _ItemScope(
      size: widget.size,
      described: described,
      drawer: drawer,
      child: DefaultTextStyle.merge(
        style: artwork
            ? DefaultTextStyle.of(context).style
            : Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: DControlStyle.labelFontSize,
                height:
                    DControlStyle.labelLineHeight / DControlStyle.labelFontSize,
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
            constraints: drawer
                ? const BoxConstraints(
                    minHeight: DSidebarRowScope.tallRowHeight,
                  )
                : null,
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
              color: sidebarSelection ? Colors.transparent : background,
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
                    : widget.variant == DItemVariant.outline && !widget.closed
                    ? widget.borderColor ?? tokens.border
                    : Colors.transparent,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
    if (sidebarSelection) {
      result = DSidebarRowSurface(
        radius: borderRadius,
        selected: widget.selected,
        hovered:
            widget.highlightOnInteraction && _active && (_hover || _pressed),
        child: Opacity(opacity: 1, child: result),
      );
    }
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
      // rings, which follow the focus highlight mode as
      // FocusableActionDetector's do. A list mounts an item per row, so the
      // item builds the detector's focus and cursor itself rather than paying
      // its per-mount global key, listener and post-frame callback.
      result = MouseRegion(
        cursor: _active
            ? widget.mouseCursor ?? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) {
          setState(() => _hover = true);
          if (_active) widget.onHoverChanged?.call(true);
        },
        onExit: (_) {
          setState(() => _hover = false);
          if (_active) widget.onHoverChanged?.call(false);
        },
        child: Focus(
          focusNode: _focus,
          canRequestFocus: _canRequestFocus,
          onFocusChange: (value) {
            setState(() => _focused = value);
            trackHighlightMode(engaged: value);
          },
          child: DTouchTarget(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTapDown: _active
                  ? (details) {
                      _pointerOnChildControl = _childControlAt(
                        details.globalPosition,
                        linkActivation.onPressed!,
                      );
                      if (!_pointerOnChildControl) {
                        setState(() => _pressed = true);
                      }
                    }
                  : null,
              onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
              // Always set, so the tap recognizer outlives a mid-press disable.
              onTapCancel: () => setState(() => _pressed = false),
              onTap: _active
                  ? () {
                      if (_pointerOnChildControl) return;
                      _focus.requestFocus();
                      linkActivation.onPressed!();
                    }
                  : null,
              child: result,
            ),
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
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              (!widget.link && event.logicalKey == LogicalKeyboardKey.space);
          if (!activates) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) linkActivation.onPressed!();
          return KeyEventResult.handled;
        },
        child: result,
      );
    }
    final item = DItemInteraction(
      hovered: _active && _hover,
      focused: _active && _focused,
      pressed: _active && _pressed,
      child: Semantics(
        container: true,
        button: widget.onPressed != null && !widget.link ? true : null,
        link: widget.link ? true : null,
        enabled: widget.onPressed != null || widget.link ? _active : null,
        label: widget.semanticLabel,
        selected: widget.selected ? true : null,
        onTap: _active ? linkActivation.onPressed : null,
        // Toggling enabled keeps the tree shape: a remount would recreate child
        // state and dispose the tap recognizer of a pointer still down.
        child: _ItemOpacity(dimmed: !widget.enabled, child: result),
      ),
    );
    if (widget.dragData == null) return linkActivation.wrap(item);
    return linkActivation.wrap(
      Draggable<Object>(
        data: widget.dragData!,
        maxSimultaneousDrags: widget.enabled ? null : 0,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: widget.dragFeedback ?? const SizedBox.shrink(),
        child: item,
      ),
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
    final nextFlexibleIndex = flexibleIndex;
    final nextMediaIndices = mediaIndices;
    final nextDirection = Directionality.of(context);
    final nextLargeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    if (renderObject.gap == gap &&
        renderObject.described == described &&
        renderObject.fitContent == fitContent &&
        renderObject.flexibleIndex == nextFlexibleIndex &&
        setEquals(renderObject.mediaIndices, nextMediaIndices) &&
        renderObject.direction == nextDirection &&
        renderObject.largeText == nextLargeText) {
      return;
    }
    renderObject
      ..gap = gap
      ..described = described
      ..fitContent = fitContent
      ..flexibleIndex = nextFlexibleIndex
      ..mediaIndices = nextMediaIndices
      ..direction = nextDirection
      ..largeText = nextLargeText
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

/// Dims a disabled item to half opacity. Flutter's [RenderOpacity] makes a
/// fully opaque child a repaint boundary with its own layer as well, and
/// every row of a list is an item, so an enabled item paints inline here.
class _ItemOpacity extends SingleChildRenderObjectWidget {
  const _ItemOpacity({required this.dimmed, required super.child});

  final bool dimmed;

  @override
  _RenderItemOpacity createRenderObject(BuildContext context) =>
      _RenderItemOpacity(dimmed);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderItemOpacity renderObject,
  ) => renderObject.dimmed = dimmed;
}

class _RenderItemOpacity extends RenderProxyBox {
  _RenderItemOpacity(this._dimmed);

  static final _dimmedAlpha = Color.getAlphaFromOpacity(.5);

  bool _dimmed;
  set dimmed(bool value) {
    if (value == _dimmed) return;
    _dimmed = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _dimmed;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_dimmed) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushOpacity(
      offset,
      _dimmedAlpha,
      super.paint,
      oldLayer: layer as OpacityLayer?,
    );
  }
}

class _ItemScope extends InheritedWidget {
  const _ItemScope({
    required this.size,
    required this.described,
    this.drawer = false,
    required super.child,
  });
  final DItemSize size;
  final bool described;
  final bool drawer;
  static bool drawerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ItemScope>()?.drawer ?? false;
  static DItemSize sizeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ItemScope>()?.size ??
      DItemSize.standard;
  @override
  bool updateShouldNotify(_ItemScope oldWidget) =>
      size != oldWidget.size ||
      described != oldWidget.described ||
      drawer != oldWidget.drawer;
}

/// Eager composition for short lists. Keep application ListView.builder owners
/// for paginated lists. [size] sets spacing when children wrap their own Items;
/// otherwise direct Item children determine the tightest spacing as CSS :has.
class DItemGroup extends StatelessWidget {
  const DItemGroup({super.key, required this.children, this.spacing});
  final List<Widget> children;

  final double? spacing;
  @override
  Widget build(BuildContext context) {
    final effective =
        ((children.whereType<DItem>().any((c) => c.size == DItemSize.artwork)
        ? DItemSize.artwork
        : children.whereType<DItem>().any((c) => c.size == DItemSize.xs)
        ? DItemSize.xs
        : children.whereType<DItem>().any((c) => c.size == DItemSize.sm)
        ? DItemSize.sm
        : DItemSize.standard));
    final gap =
        spacing ??
        switch (effective) {
          DItemSize.standard => 16.0,
          DItemSize.sm => 10.0,
          DItemSize.xs => 8.0,
          DItemSize.artwork => 0.0,
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
    spacing:
        spacing ??
        (_ItemScope.drawerOf(context)
            ? 2
            : (switch (_ItemScope.sizeOf(context)) {
                DItemSize.xs || DItemSize.artwork => 0,
                _ => 4,
              })),
    children: children,
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
        TextStyle(
          fontSize: _ItemScope.drawerOf(context)
              ? DiscourseTypography.sm
              : DiscourseTypography.rowTitle,
          height: _ItemScope.drawerOf(context)
              ? 1.25
              : DiscourseTypography.lineHeightRowTitle,
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
  const DItemDescription({super.key, required this.child, this.maxLines = 2});
  final Widget child;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final effectiveMaxLines = MediaQuery.textScalerOf(context).scale(14) > 21
        ? null
        : maxLines;
    return DefaultTextStyle(
      style: DefaultTextStyle.of(context).style.merge(
        TextStyle(
          fontSize: DiscourseTypography.preview,
          height: _ItemScope.drawerOf(context)
              ? 1.25
              : DiscourseTypography.lineHeightPreview,
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

class _ClosedHatch extends CustomPainter {
  const _ClosedHatch(this.color, this.radius, this.direction);
  final Color color;
  final BorderRadius radius;
  final TextDirection direction;

  /// How far from the trailing edge the hatch fades out completely.
  static const _reach = .55;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ltr = direction == TextDirection.ltr;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: ltr ? Alignment.centerRight : Alignment.centerLeft,
        end: ltr ? Alignment.centerLeft : Alignment.centerRight,
        colors: [color.withValues(alpha: .16), color.withValues(alpha: 0)],
        stops: const [0, _reach],
      ).createShader(rect);
    // CSS -45deg: parallel strokes one pixel wide, six pixels apart along
    // their normal. Keep the angle in RTL; only the directional fade mirrors.
    // Only strokes that cross the inked band are drawn, on the same lattice.
    // One path keeps Impeller from shading every stroke in its own subpass,
    // which cost whole milliseconds of raster time per visible closed row.
    const step = 6 * math.sqrt2;
    final start = ltr ? size.width * (1 - _reach) : 0.0;
    final end = (ltr ? size.width : size.width * _reach) + size.height;
    final strokes = Path();
    for (var x = (start / step).ceil() * step; x < end; x += step) {
      strokes
        ..moveTo(x, 0)
        ..lineTo(x - size.height, size.height);
    }
    canvas.save();
    canvas.clipRRect(radius.toRRect(rect));
    canvas.drawPath(strokes, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClosedHatch oldDelegate) =>
      color != oldDelegate.color ||
      radius != oldDelegate.radius ||
      direction != oldDelegate.direction;
}

class _ClosedRules extends CustomPainter {
  const _ClosedRules(
    this.color,
    this.direction, {
    required this.above,
    required this.below,
  });
  final Color color;
  final TextDirection direction;
  final bool above;
  final bool below;

  @override
  void paint(Canvas canvas, Size size) {
    if ((!above && !below) || size.width <= 24) return;
    final rect = Rect.fromLTWH(12, 0, size.width - 24, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: direction == TextDirection.ltr
            ? Alignment.centerLeft
            : Alignment.centerRight,
        end: direction == TextDirection.ltr
            ? Alignment.centerRight
            : Alignment.centerLeft,
        colors: [color, color.withValues(alpha: 0)],
        stops: const [.45, 1],
      ).createShader(rect);
    if (above) {
      canvas.drawRect(Rect.fromLTWH(rect.left, 0, rect.width, 1), paint);
    }
    if (below) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, size.height - 1, rect.width, 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ClosedRules oldDelegate) =>
      color != oldDelegate.color ||
      direction != oldDelegate.direction ||
      above != oldDelegate.above ||
      below != oldDelegate.below;
}
