import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/input_group_scope.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_input.dart';
import 'd_kbd.dart';
import 'd_scroll_area.dart';
import 'd_textarea.dart';

/// Search uses a recessed capsule; composer supplies the mobile chat reference's
/// one-line editor, tool spacing and matching full/compact geometry.
enum DInputGroupVariant { standard, search, composer }

enum DInputGroupAddonAlignment { inlineStart, inlineEnd, blockStart, blockEnd }

typedef DInputGroupButtonSize = DButtonSize;

/// A single shadcn input surface composed from one editor and optional addons.
///
/// Keep the editor first in [children] for traversal and screen-reader order;
/// [DInputGroupAddon.alignment] controls visual placement. DInput and DTextarea
/// retain all editing, Form, selection, IME, controller and focus ownership.
/// The group owns only their shared border, focus/invalid ring and addon layout.
class DInputGroup extends StatefulWidget {
  const DInputGroup({
    super.key,
    required this.children,
    this.size = DControlSize.regular,
    this.variant = DInputGroupVariant.standard,
    this.enabled = true,
    this.invalid = false,
    this.borderless = false,
    this.semanticLabel,
    this.viewportHeight,
    this.compact = false,
    this.action,
  }) : assert(children.length > 0),
       assert(
         viewportHeight == null ||
             (viewportHeight > 0 && viewportHeight < double.infinity),
       );

  final List<Widget> children;
  final DControlSize size;
  final DInputGroupVariant variant;
  final bool enabled;
  final bool invalid;

  /// Lets a surrounding surface own the fill and border without changing the
  /// editor, addon spacing, size, focus behavior or semantics.
  final bool borderless;
  final String? semanticLabel;

  /// Fixed height for a vertically scrolling surface containing the editor
  /// and all addons. Null retains content-driven sizing. Use an unbounded
  /// textarea [DTextarea.maxLines] so the group owns vertical scrolling.
  /// The viewport owns its scroll controller and disposes it with the group.
  final double? viewportHeight;

  /// Folds block addons away and keeps [action] beside the editor. The editor
  /// stays mounted in the same slot so selection, drafts and IME survive.
  final bool compact;

  /// Primary composer action, at the footer's end or inline when compact.
  final Widget? action;

  /// The chat reference's matching full and compact composer corners.
  static const composerBorderRadius = BorderRadius.all(Radius.circular(24));

  static TextStyle composerTextStyleOf(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
        // The dock keeps chrome at reference scale, so use the mobile reading
        // baseline here while retaining its one-line editor geometry.
        fontSize: DiscourseTypography.mobileBase,
        height: 20 / DiscourseTypography.mobileBase,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      );

  static double composerLineExtentOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(20);

  @override
  State<DInputGroup> createState() => _DInputGroupState();
}

class _DInputGroupState extends State<DInputGroup> {
  final Map<FocusNode, ({bool enabled, bool invalid})> _controls = {};
  bool _updateQueued = false;

  void _report(FocusNode node, bool enabled, bool invalid) {
    if (!_controls.containsKey(node)) {
      node.addListener(_focusChanged);
    }
    final next = (enabled: enabled, invalid: invalid);
    if (_controls[node] == next) return;
    _controls[node] = next;
    _queueUpdate();
  }

  void _remove(FocusNode node) {
    if (_controls.remove(node) != null) {
      node.removeListener(_focusChanged);
      _queueUpdate();
    }
  }

  void _focusChanged() => _queueUpdate();

  void _queueUpdate() {
    if (_updateQueued) return;
    _updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _requestControlFocus() {
    if (!widget.enabled) return;
    for (final node in _controls.keys) {
      if (node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
  }

  @override
  void dispose() {
    for (final node in _controls.keys) {
      node.removeListener(_focusChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final search = widget.variant == DInputGroupVariant.search;
    final composer = widget.variant == DInputGroupVariant.composer;
    final compactComposerExtent =
        48 +
        (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(
          0.0,
          double.infinity,
        );
    final dark = Theme.of(context).brightness == Brightness.dark;
    final focused =
        DFocusHighlight.visibleOf(context) &&
        _controls.keys.any((node) => node.hasFocus);
    final controlEnabled =
        _controls.isEmpty || _controls.values.every((state) => state.enabled);
    final invalid =
        widget.invalid || _controls.values.any((state) => state.invalid);
    final border = invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .5 : 1),
          )
        : focused
        ? tokens.focusRing
        : tokens.buttonTheme.outline.border;
    final ring = invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .4 : .2),
          )
        : tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5);
    final joined = DJoinedControlScope.maybeOf(context);
    final baseRadius = composer
        ? DInputGroup.composerBorderRadius
        : BorderRadius.circular(
            search ? DRadius.pill : tokens.buttonTheme.radius,
          );
    final radius =
        joined?.resolveRadius(baseRadius, Directionality.of(context)) ??
        baseRadius;

    final inlineStart = <Widget>[];
    final inlineEnd = <Widget>[];
    final blockStart = <Widget>[];
    final blockEnd = <Widget>[];
    final controls = <Widget>[];
    var multiline = false;
    for (var index = 0; index < widget.children.length; index++) {
      final child = widget.children[index];
      final ordered = FocusTraversalOrder(
        order: NumericFocusOrder(index.toDouble()),
        child: child,
      );
      if (child is DInputGroupAddon) {
        switch (child.alignment) {
          case DInputGroupAddonAlignment.inlineStart:
            inlineStart.add(ordered);
          case DInputGroupAddonAlignment.inlineEnd:
            inlineEnd.add(ordered);
          case DInputGroupAddonAlignment.blockStart:
            blockStart.add(ordered);
          case DInputGroupAddonAlignment.blockEnd:
            blockEnd.add(ordered);
        }
      } else {
        multiline =
            multiline ||
            child is DInputGroupTextarea ||
            child is DInputGroupControl && child.multiline;
        controls.add(Expanded(child: ordered));
      }
    }
    assert(controls.length == 1, 'DInputGroup requires exactly one control.');

    Widget inline = LayoutBuilder(
      builder: (context, constraints) {
        // Keep both addon lanes shrinkable at large text sizes while reserving
        // space for the editor between them.
        Widget side(List<Widget> children, {bool leading = false}) =>
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * (search && leading ? .55 : .4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: search ? 8 : 0,
                children: [
                  for (final (index, child) in children.indexed)
                    if (search && children.length > 1 && index == 0)
                      child
                    else
                      Flexible(child: child),
                ],
              ),
            );
        return Row(
          crossAxisAlignment: multiline && !widget.compact
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (inlineStart.isNotEmpty) ...[
              side(inlineStart, leading: true),
              if (search) const SizedBox(width: 8),
            ],
            ...controls,
            if (inlineEnd.isNotEmpty) ...[
              if (search) const SizedBox(width: 8),
              side(inlineEnd),
            ],
            if (widget.compact && widget.action != null)
              Padding(
                padding: EdgeInsetsDirectional.only(end: composer ? 7 : 6),
                child: widget.action!,
              ),
          ],
        );
      },
    );
    Widget content = widget.action == null
        ? (blockStart.isEmpty && blockEnd.isEmpty
              ? inline
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...blockStart, inline, ...blockEnd],
                ))
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Offstage(
                offstage: widget.compact,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: blockStart,
                ),
              ),
              inline,
              Offstage(
                offstage: widget.compact,
                child: composer
                    ? Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          7,
                          6,
                          7,
                          7,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: blockEnd,
                              ),
                            ),
                            if (!widget.compact && widget.action != null)
                              widget.action!,
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: blockEnd,
                            ),
                          ),
                          if (!widget.compact && widget.action != null)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: 6,
                                bottom: 6,
                              ),
                              child: widget.action!,
                            ),
                        ],
                      ),
              ),
            ],
          );
    if (search) {
      content = Padding(
        // The reference's 14px inset sits inside its 1px transparent border.
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: DIconGlyphTheme(scale: 1, child: content),
      );
    }
    content = FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: content,
    );

    if (widget.viewportHeight case final height?) {
      content = SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: radius,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _requestControlFocus,
            child: DScrollArea(child: content),
          ),
        ),
      );
    }

    final surface = Semantics(
      container: true,
      label: widget.semanticLabel,
      enabled: widget.enabled && controlEnabled,
      validationResult: invalid
          ? SemanticsValidationResult.invalid
          : SemanticsValidationResult.none,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onTap: _requestControlFocus,
        child: MouseRegion(
          cursor: widget.enabled
              ? MouseCursor.defer
              : SystemMouseCursors.forbidden,
          child: Opacity(
            opacity: widget.enabled && controlEnabled ? 1 : .5,
            child: ExcludeFocus(
              excluding: !widget.enabled,
              child: IgnorePointer(
                ignoring: !widget.enabled,
                child: AnimatedContainer(
                  duration: DMotion.duration(
                    context,
                    widget.borderless
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                  ),
                  constraints: BoxConstraints(
                    minHeight:
                        widget.viewportHeight ??
                        (composer
                            ? (widget.compact ? compactComposerExtent : 0)
                            : widget.compact
                            ? MediaQuery.textScalerOf(context).scale(48)
                            : multiline
                            ? 64
                            : DControlStyle.scaledHeight(
                                    widget.size,
                                    MediaQuery.textScalerOf(context),
                                    context: context,
                                  ) +
                                  (search && widget.size == DControlSize.field
                                      ? .5
                                      : 0)),
                  ),
                  decoration: search && !widget.borderless
                      ? _SearchInputSurfaceDecoration(dark: dark)
                      : _InputGroupSurfaceDecoration(
                          backgroundColor: widget.borderless
                              ? Colors.transparent
                              : tokens.buttonTheme.outline.background,
                          borderRadius: radius,
                          borderColor: widget.borderless
                              ? Colors.transparent
                              : border,
                          joinedAxis: joined?.axis,
                          omitLeadingBorder:
                              joined?.omitsLeadingBorder ?? false,
                        ),
                  foregroundDecoration: _InputGroupRingDecoration(
                    color: !widget.borderless && (invalid || focused)
                        ? ring
                        : ring.withValues(alpha: 0),
                    radius: radius,
                  ),
                  child: DJoinedControlScope.boundary(child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final compactComposerInset =
        ((compactComposerExtent - DInputGroup.composerLineExtentOf(context)) /
                2)
            .clamp(0.0, double.infinity);
    final inputPadding = composer
        ? EdgeInsetsDirectional.fromSTEB(
            17,
            widget.compact
                ? compactComposerInset
                : blockStart.isEmpty
                ? 12
                : 0,
            17,
            widget.compact ? compactComposerInset : 0,
          ).resolve(Directionality.of(context))
        : search
        ? const EdgeInsets.symmetric(vertical: 1)
        : EdgeInsetsDirectional.only(
            start: inlineStart.isEmpty
                ? DControlStyle.horizontalInset(widget.size)
                : 6,
            top: widget.compact
                ? 6
                : blockEnd.isEmpty
                ? 1
                : 12,
            end: inlineEnd.isEmpty
                ? DControlStyle.horizontalInset(widget.size)
                : 6,
            bottom: widget.compact
                ? 6
                : blockStart.isEmpty
                ? 1
                : 12,
          ).resolve(Directionality.of(context));
    return DInputGroupControlScope(
      report: _report,
      remove: _remove,
      requestControlFocus: _requestControlFocus,
      inputPadding: inputPadding,
      size: widget.size,
      search: search,
      composer: composer,
      editorStyle: composer ? DInputGroup.composerTextStyleOf(context) : null,
      enabled: widget.enabled,
      child: surface,
    );
  }
}

/// Non-editable group content positioned relative to the control.
///
/// Tapping non-action content focuses the editor. Nested buttons win the
/// gesture arena and remain independently actionable.
class DInputGroupAddon extends StatelessWidget {
  const DInputGroupAddon({
    super.key,
    Widget? child,

    this.alignment = DInputGroupAddonAlignment.inlineStart,
  }) : assert((child != null)),

       child = child,
       children = (const []);

  final List<Widget> children;
  final Widget? child;
  final DInputGroupAddonAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final size =
        DInputGroupControlScope.maybeOf(context)?.size ?? DControlSize.regular;
    final content = child == null ? children : <Widget>[child!];
    final block =
        alignment == DInputGroupAddonAlignment.blockStart ||
        alignment == DInputGroupAddonAlignment.blockEnd;
    final hasButton = content.any((item) => item is DInputGroupButton);
    final hasKbd = content.any(
      (item) => item is DKbd || item is DKbdGroup || item is DShortcutKeycaps,
    );
    // Keep the compact keycap rounded even with small site radii.
    final keycapRadius = BorderRadius.circular(tokens.radius * 0.6);
    final keycapBackground = tokens.mutedForeground.withValues(alpha: 0.12);
    final inlineInset = hasButton
        ? 3.2
        : hasKbd
        ? 5.6
        : 8.0;
    final search = DInputGroupControlScope.maybeOf(context)?.search ?? false;
    final foreground = search
        ? Color.lerp(tokens.background, tokens.foreground, .5)!
        : tokens.mutedForeground;
    final composer =
        DInputGroupControlScope.maybeOf(context)?.composer ?? false;
    final padding = composer && block
        ? alignment == DInputGroupAddonAlignment.blockEnd
              ? EdgeInsets.zero
              : const EdgeInsetsDirectional.fromSTEB(17, 12, 17, 6)
        : search && !block
        ? EdgeInsets.zero
        : switch (alignment) {
            DInputGroupAddonAlignment.inlineStart => EdgeInsetsDirectional.only(
              start: inlineInset,
              top: 0,
              bottom: 0,
            ),
            DInputGroupAddonAlignment.inlineEnd => EdgeInsetsDirectional.only(
              end: inlineInset,
              top: 0,
              bottom: 0,
            ),
            DInputGroupAddonAlignment.blockStart =>
              const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 6),
            DInputGroupAddonAlignment.blockEnd =>
              const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 8),
          };
    final row = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (var index = 0; index < content.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Flexible(
            child: content[index] is DKbd
                ? DKbdTheme(
                    foregroundColor: tokens.mutedForeground,
                    backgroundColor: keycapBackground,
                    borderRadius: keycapRadius,
                    child: content[index],
                  )
                : content[index],
          ),
        ],
      ],
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: DInputGroupControlScope.maybeOf(context)?.requestControlFocus,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Padding(
          padding: padding,
          child: IconTheme.merge(
            data: IconThemeData(
              size: DControlStyle.iconDimension(size, context: context),
              color: foreground,
            ),
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                fontSize: DControlStyle.fontSize(size, context: context),
                height:
                    DControlStyle.lineHeight(size, context: context) /
                    DControlStyle.fontSize(size, context: context),
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: foreground,
              ),
              child: DKbdTheme(
                foregroundColor: tokens.mutedForeground,
                backgroundColor: keycapBackground,
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Muted text or icon content for an addon.
class DInputGroupText extends StatelessWidget {
  const DInputGroupText(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ExcludeFocus(child: IgnorePointer(child: child));
}

/// A shadcn button fitted to an input-group addon.
class DInputGroupButton extends StatelessWidget {
  const DInputGroupButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,

    this.size = DInputGroupButtonSize.small,

    this.tooltip,
    this.focusNode,

    this.hasPopup = false,
  }) : _iconOnly = false;

  const DInputGroupButton.icon({
    super.key,
    required Widget this.icon,
    required String this.tooltip,
    required this.onPressed,

    this.size = DInputGroupButtonSize.small,

    this.focusNode,

    this.hasPopup = false,
  }) : label = const SizedBox.shrink(),

       _iconOnly = true;

  final bool _iconOnly;
  final Widget label;
  final VoidCallback? onPressed;
  final Widget? icon;

  final DInputGroupButtonSize size;

  final String? tooltip;
  final FocusNode? focusNode;

  final bool hasPopup;

  @override
  Widget build(BuildContext context) {
    final search = DInputGroupControlScope.maybeOf(context)?.search ?? false;
    final radius = (DTokens.of(context).radius - 3)
        .clamp(0, double.infinity)
        .toDouble();
    if (_iconOnly) {
      return DButton.iconOnly(
        icon: icon!,
        tooltip: tooltip!,
        onPressed: onPressed,
        variant: search ? DButtonVariant.ghost : DButtonVariant.ghost,
        density: search ? DButtonDensity.searchClear : DButtonDensity.standard,
        foregroundColor: search
            ? Color.lerp(
                DTokens.of(context).background,
                DTokens.of(context).foreground,
                .5,
              )
            : null,
        size: size,
        semanticLabel: null,
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(radius),
        loading: false,
        hasPopup: hasPopup,
      );
    }
    return DButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      iconPosition: DButtonIconPosition.start,
      variant: DButtonVariant.ghost,
      size: size,
      semanticLabel: null,
      tooltip: tooltip,
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(radius),
      loading: false,
      hasPopup: hasPopup,
    );
  }
}

/// DInput with its standalone surface replaced by the surrounding group.
class DInputGroupInput extends DInput {
  DInputGroupInput({
    super.key,
    super.controller,

    super.focusNode,

    super.semanticLabel,
    super.hintText,

    super.invalid,

    super.onChanged,
    super.onSubmitted,

    super.onTap,

    super.textInputAction,

    super.autofocus,

    super.autocorrect,
    super.enableSuggestions,

    super.enabled,
  });
}

/// DTextarea with its standalone surface replaced by the surrounding group.
class DInputGroupTextarea extends DTextarea {
  DInputGroupTextarea({
    super.key,
    super.controller,

    super.focusNode,

    super.semanticLabel,
    super.hintText,

    super.onChanged,

    super.autocorrect,
    super.enableSuggestions,

    super.minLines,
    super.maxLines,

    super.enabled,
  });
}

/// Adapts a third-party editor while keeping focus ownership explicit.
///
/// The builder must attach the supplied focus node to its real editable. A
/// caller-supplied node is borrowed; otherwise this widget owns and disposes it.
class DInputGroupControl extends StatefulWidget {
  const DInputGroupControl({
    super.key,
    required this.builder,
    this.focusNode,
    this.enabled = true,
    this.invalid = false,
    this.multiline = false,
  });

  final Widget Function(BuildContext context, FocusNode focusNode) builder;
  final FocusNode? focusNode;
  final bool enabled;
  final bool invalid;
  final bool multiline;

  @override
  State<DInputGroupControl> createState() => _DInputGroupControlState();
}

class _DInputGroupControlState extends State<DInputGroupControl> {
  FocusNode? _ownedFocus;
  DInputGroupControlScope? _group;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) _ownedFocus = FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DInputGroupControlScope.maybeOf(context);
    if (!identical(next, _group)) {
      _group?.remove(_focus);
      _group = next;
    }
  }

  @override
  void didUpdateWidget(DInputGroupControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    _group?.remove(oldWidget.focusNode ?? _ownedFocus!);
    _ownedFocus?.dispose();
    _ownedFocus = widget.focusNode == null ? FocusNode() : null;
  }

  @override
  void dispose() {
    _group?.remove(_focus);
    _ownedFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && (_group?.enabled ?? true);
    _group?.report(_focus, enabled, widget.invalid);
    final editor = Builder(
      builder: (context) => widget.builder(context, _focus),
    );
    return Padding(
      padding:
          _group?.inputPadding ??
          EdgeInsets.symmetric(
            horizontal: 10,
            vertical: widget.multiline ? 8 : 5,
          ),
      child: ExcludeFocus(
        excluding: !enabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: switch (_group) {
            final group? => DInputGroupControlScope.boundary(
              parent: group,
              child: editor,
            ),
            null => editor,
          },
        ),
      ),
    );
  }
}

class _InputGroupSurfaceDecoration extends Decoration {
  const _InputGroupSurfaceDecoration({
    required this.backgroundColor,
    required this.borderColor,
    required this.borderRadius,
    required this.joinedAxis,
    required this.omitLeadingBorder,
  });

  final Color backgroundColor;
  final Color borderColor;
  final BorderRadius borderRadius;
  final Axis? joinedAxis;
  final bool omitLeadingBorder;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _InputGroupSurfacePainter(this);

  @override
  Decoration? lerpFrom(Decoration? a, double t) =>
      a is _InputGroupSurfaceDecoration
      ? _InputGroupSurfaceDecoration(
          backgroundColor: Color.lerp(a.backgroundColor, backgroundColor, t)!,
          borderColor: Color.lerp(a.borderColor, borderColor, t)!,
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
          joinedAxis: t < .5 ? a.joinedAxis : joinedAxis,
          omitLeadingBorder: t < .5 ? a.omitLeadingBorder : omitLeadingBorder,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is _InputGroupSurfaceDecoration
      ? b.lerpFrom(this, t)
      : super.lerpTo(b, t);
}

class _InputGroupSurfacePainter extends BoxPainter {
  const _InputGroupSurfacePainter(this.decoration);
  final _InputGroupSurfaceDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final rrect = decoration.borderRadius.toRRect(rect);
    canvas.drawRRect(rrect, Paint()..color = decoration.backgroundColor);
    final outline = rrect.deflate(.5);
    final borderPaint = Paint()
      ..color = decoration.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (!decoration.omitLeadingBorder || decoration.joinedAxis == null) {
      canvas.drawRRect(outline, borderPaint);
      return;
    }
    final direction = configuration.textDirection ?? TextDirection.ltr;
    final clip = switch (decoration.joinedAxis!) {
      Axis.vertical => Rect.fromLTRB(
        rect.left - 1,
        rect.top + 1.01,
        rect.right + 1,
        rect.bottom + 1,
      ),
      Axis.horizontal when direction == TextDirection.rtl => Rect.fromLTRB(
        rect.left - 1,
        rect.top - 1,
        rect.right - 1.01,
        rect.bottom + 1,
      ),
      Axis.horizontal => Rect.fromLTRB(
        rect.left + 1.01,
        rect.top - 1,
        rect.right + 1,
        rect.bottom + 1,
      ),
    };
    canvas
      ..save()
      ..clipRect(clip)
      ..drawRRect(outline, borderPaint)
      ..restore();
  }
}

class _InputGroupRingDecoration extends Decoration {
  const _InputGroupRingDecoration({required this.color, required this.radius});
  final Color color;
  final BorderRadius radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _InputGroupRingPainter(this);

  @override
  Decoration? lerpFrom(Decoration? a, double t) =>
      a is _InputGroupRingDecoration
      ? _InputGroupRingDecoration(
          color: Color.lerp(a.color, color, t)!,
          radius: BorderRadius.lerp(a.radius, radius, t)!,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) => b is _InputGroupRingDecoration
      ? _InputGroupRingDecoration(
          color: Color.lerp(color, b.color, t)!,
          radius: BorderRadius.lerp(radius, b.radius, t)!,
        )
      : super.lerpTo(b, t);
}

class _InputGroupRingPainter extends BoxPainter {
  _InputGroupRingPainter(this.decoration);
  final _InputGroupRingDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final inner = decoration.radius.toRRect(rect);
    canvas.drawDRRect(
      inner.inflate(3),
      inner,
      Paint()..color = decoration.color,
    );
  }
}

/// The title-bar well has no cast shadow or backdrop blur in either material.
class _SearchInputSurfaceDecoration extends Decoration {
  const _SearchInputSurfaceDecoration({required this.dark});
  final bool dark;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _SearchInputSurfacePainter(dark);
}

class _SearchInputSurfacePainter extends BoxPainter {
  _SearchInputSurfacePainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(999));
    canvas.drawRRect(
      shape,
      Paint()..color = Colors.black.withValues(alpha: dark ? .16 : .045),
    );
    canvas.save();
    canvas.clipRRect(shape);
    // An inset shadow is the blurred outside of the shape shifted down 1px.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(8))
      ..addRRect(shape.shift(const Offset(0, 1)));
    canvas.drawPath(
      outside,
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .32 : .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (dark ? Colors.white : Colors.black).withValues(
          alpha: dark ? .07 : .06,
        ),
    );
    final bottom = Path.combine(
      PathOperation.difference,
      Path()..addRRect(shape),
      Path()..addRRect(shape.shift(const Offset(0, -1))),
    );
    canvas.drawPath(
      bottom,
      Paint()..color = Colors.white.withValues(alpha: dark ? .08 : .8),
    );
    canvas.restore();
  }
}
