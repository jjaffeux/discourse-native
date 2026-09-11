import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/input_group_scope.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_input.dart';
import 'd_kbd.dart';
import 'd_textarea.dart';

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
    this.enabled = true,
    this.invalid = false,
    this.semanticLabel,
  }) : assert(children.length > 0);

  final List<Widget> children;
  final DControlSize size;
  final bool enabled;
  final bool invalid;
  final String? semanticLabel;

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final focused = _controls.keys.any((node) => node.hasFocus);
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
        : tokens.colors.outlineVariant;
    final ring = invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .4 : .2),
          )
        : tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5);
    final joined = DJoinedControlScope.maybeOf(context);
    final radius =
        joined?.resolveRadius(
          BorderRadius.circular(tokens.radius),
          Directionality.of(context),
        ) ??
        BorderRadius.circular(tokens.radius);

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
        final maxSideWidth = constraints.maxWidth * .4;
        Widget side(List<Widget> children) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxSideWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final child in children) Flexible(child: child)],
          ),
        );
        return Row(
          crossAxisAlignment: multiline
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (inlineStart.isNotEmpty) side(inlineStart),
            ...controls,
            if (inlineEnd.isNotEmpty) side(inlineEnd),
          ],
        );
      },
    );
    Widget content = blockStart.isEmpty && blockEnd.isEmpty
        ? inline
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...blockStart, inline, ...blockEnd],
          );
    content = FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: content,
    );

    final surface = Semantics(
      container: true,
      label: widget.semanticLabel,
      enabled: widget.enabled && controlEnabled,
      validationResult: invalid
          ? SemanticsValidationResult.invalid
          : SemanticsValidationResult.none,
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
                  const Duration(milliseconds: 150),
                ),
                constraints: BoxConstraints(
                  minHeight: multiline ? 64 : DControlStyle.height(widget.size),
                ),
                decoration: _InputGroupSurfaceDecoration(
                  backgroundColor: dark
                      ? tokens.colors.outlineVariant.withValues(
                          alpha:
                              tokens.colors.outlineVariant.a *
                              (controlEnabled ? .3 : .8),
                        )
                      : controlEnabled
                      ? Colors.transparent
                      : tokens.colors.outlineVariant.withValues(
                          alpha: tokens.colors.outlineVariant.a * .5,
                        ),
                  borderRadius: radius,
                  borderColor: border,
                  joinedAxis: joined?.axis,
                  omitLeadingBorder: joined?.omitsLeadingBorder ?? false,
                ),
                foregroundDecoration: _InputGroupRingDecoration(
                  color: invalid || focused ? ring : ring.withValues(alpha: 0),
                  radius: radius,
                ),
                child: DJoinedControlScope.boundary(child: content),
              ),
            ),
          ),
        ),
      ),
    );
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final inputPadding = EdgeInsetsDirectional.only(
      start: inlineStart.isEmpty ? 10 : 6,
      top: blockEnd.isEmpty ? 1 : 12,
      end: inlineEnd.isEmpty ? 10 : 6,
      bottom: blockStart.isEmpty ? 1 : 12,
    ).resolve(Directionality.of(context));
    return DInputGroupControlScope(
      report: _report,
      remove: _remove,
      requestControlFocus: _requestControlFocus,
      inputPadding: inputPadding,
      enabled: widget.enabled,
      child: touch && !multiline
          ? GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _requestControlFocus,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DSpacing.touchTarget,
                ),
                child: Align(heightFactor: 1, child: surface),
              ),
            )
          : surface,
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
    List<Widget>? children,
    this.alignment = DInputGroupAddonAlignment.inlineStart,
  }) : assert(child != null || children != null),
       assert(child == null || children == null),
       child = child,
       children = children ?? const [];

  final List<Widget> children;
  final Widget? child;
  final DInputGroupAddonAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
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
    final padding = switch (alignment) {
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
            data: IconThemeData(size: 16, color: tokens.mutedForeground),
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                fontSize: DiscourseTypography.sm,
                height: 20 / DiscourseTypography.sm,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: tokens.mutedForeground,
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
    this.iconPosition = DButtonIconPosition.start,
    this.variant = DButtonVariant.ghost,
    this.size = DInputGroupButtonSize.extraSmall,
    this.semanticLabel,
    this.tooltip,
    this.focusNode,
    this.loading = false,
    this.hasPopup = false,
  }) : _iconOnly = false;

  const DInputGroupButton.icon({
    super.key,
    required Widget this.icon,
    required String this.tooltip,
    required this.onPressed,
    this.variant = DButtonVariant.ghost,
    this.size = DInputGroupButtonSize.extraSmall,
    this.semanticLabel,
    this.focusNode,
    this.loading = false,
    this.hasPopup = false,
  }) : label = const SizedBox.shrink(),
       iconPosition = DButtonIconPosition.start,
       _iconOnly = true;

  final bool _iconOnly;
  final Widget label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final DButtonIconPosition iconPosition;
  final DButtonVariant variant;
  final DInputGroupButtonSize size;
  final String? semanticLabel;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool loading;
  final bool hasPopup;

  @override
  Widget build(BuildContext context) {
    final radius = (DTokens.of(context).radius - 3)
        .clamp(0, double.infinity)
        .toDouble();
    if (_iconOnly) {
      return DButton.iconOnly(
        icon: icon!,
        tooltip: tooltip!,
        onPressed: onPressed,
        variant: variant,
        size: size,
        semanticLabel: semanticLabel,
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(radius),
        loading: loading,
        hasPopup: hasPopup,
      );
    }
    return DButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      iconPosition: iconPosition,
      variant: variant,
      size: size,
      semanticLabel: semanticLabel,
      tooltip: tooltip,
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(radius),
      loading: loading,
      hasPopup: hasPopup,
    );
  }
}

/// DInput with its standalone surface replaced by the surrounding group.
class DInputGroupInput extends DInput {
  DInputGroupInput({
    super.key,
    super.controller,
    super.value,
    super.initialValue,
    super.focusNode,
    super.labelText,
    super.semanticLabel,
    super.hintText,
    super.helperText,
    super.errorText,
    super.invalid,
    super.isRequired,
    super.prefix,
    super.suffix,
    super.onChanged,
    super.onSubmitted,
    super.onEditingComplete,
    super.onTap,
    super.onTapOutside,
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization,
    super.autofocus,
    super.readOnly,
    super.obscureText,
    super.obscuringCharacter,
    super.autocorrect,
    super.enableSuggestions,
    super.enableInteractiveSelection,
    super.inputFormatters,
    super.autofillHints,
    super.maxLength,
    super.maxLengthEnforcement,
    super.textAlign,
    super.textDirection,
    super.undoController,
    super.contextMenuBuilder,
    super.enabled,
    super.onSaved,
    super.onReset,
    super.validator,
    super.autovalidateMode,
  });
}

/// DTextarea with its standalone surface replaced by the surrounding group.
class DInputGroupTextarea extends DTextarea {
  DInputGroupTextarea({
    super.key,
    super.controller,
    super.value,
    super.initialValue,
    super.focusNode,
    super.labelText,
    super.semanticLabel,
    super.hintText,
    super.helperText,
    super.errorText,
    super.invalid,
    super.isRequired,
    super.onChanged,
    super.onSubmitted,
    super.onEditingComplete,
    super.onTap,
    super.onTapOutside,
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization,
    super.autofocus,
    super.readOnly,
    super.autocorrect,
    super.enableSuggestions,
    super.enableInteractiveSelection,
    super.inputFormatters,
    super.autofillHints,
    super.minLines,
    super.maxLines,
    super.scrollController,
    super.scrollPhysics,
    super.showCounter,
    super.maxLength,
    super.maxLengthEnforcement,
    super.textAlign,
    super.textDirection,
    super.undoController,
    super.contextMenuBuilder,
    super.enabled,
    super.onSaved,
    super.onReset,
    super.validator,
    super.autovalidateMode,
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
          child: widget.builder(context, _focus),
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
