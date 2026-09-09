import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// The two base-nova Toggle surface treatments.
enum DToggleVariant { standard, outline }

/// The three base-nova Toggle sizes.
enum DToggleSize { small, regular, large }

/// Icon placement follows the ambient reading direction.
enum DToggleIconPosition { start, end }

/// A shadcn two-state button with native pressed-toggle semantics.
///
/// Supply [pressed] for controlled state, or omit it to own state initialized
/// by [initialPressed]. A controlled toggle with no [onPressedChanged] is
/// disabled; an uncontrolled toggle may omit its observer. [focusNode] is
/// borrowed and never disposed. Desktop artwork follows base-nova's compact
/// bounds while touch platforms receive an invisible 48px minimum target.
class DToggle extends StatefulWidget {
  const DToggle({
    super.key,
    required this.child,
    this.icon,
    this.selectedIcon,
    this.iconPosition = DToggleIconPosition.start,
    this.pressed,
    this.initialPressed = false,
    this.onPressedChanged,
    this.enabled = true,
    this.invalid = false,
    this.variant = DToggleVariant.standard,
    this.size = DToggleSize.regular,
    this.semanticLabel,
    this.semanticHint,
    this.focusNode,
    this.autofocus = false,
  }) : _iconOnly = false;

  const DToggle.iconOnly({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.semanticLabel,
    this.pressed,
    this.initialPressed = false,
    this.onPressedChanged,
    this.enabled = true,
    this.invalid = false,
    this.variant = DToggleVariant.standard,
    this.size = DToggleSize.regular,
    this.semanticHint,
    this.focusNode,
    this.autofocus = false,
  }) : child = const SizedBox.shrink(),
       iconPosition = DToggleIconPosition.start,
       _iconOnly = true;

  final Widget child;
  final Widget? icon;

  /// Optional replacement artwork while toggled on.
  final Widget? selectedIcon;
  final DToggleIconPosition iconPosition;

  /// Non-null values are parent-owned. Null uses [initialPressed].
  final bool? pressed;
  final bool initialPressed;
  final ValueChanged<bool>? onPressedChanged;
  final bool enabled;
  final bool invalid;
  final DToggleVariant variant;
  final DToggleSize size;
  final String? semanticLabel;
  final String? semanticHint;

  /// Borrowed from the caller and never disposed by this widget.
  final FocusNode? focusNode;
  final bool autofocus;
  final bool _iconOnly;

  static double visualDimensionFor(DToggleSize size) => switch (size) {
    DToggleSize.small => 28,
    DToggleSize.regular => 32,
    DToggleSize.large => 36,
  };

  static double iconDimensionFor(DToggleSize size) =>
      size == DToggleSize.small ? 14 : 16;

  static double fontSizeFor(DToggleSize size) => size == DToggleSize.small
      ? DiscourseTypography.base * .8
      : DiscourseTypography.sm;

  @override
  State<DToggle> createState() => _DToggleState();
}

class _DToggleState extends State<DToggle> {
  late bool _pressed = widget.initialPressed;
  bool _focusVisible = false;
  bool _hovered = false;
  bool _pointerPressed = false;
  final FocusNode _ownedFocus = FocusNode(debugLabel: 'Toggle');

  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  bool get _current => widget.pressed ?? _pressed;
  bool get _enabled =>
      widget.enabled &&
      (widget.pressed == null || widget.onPressedChanged != null);

  @override
  void didUpdateWidget(DToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pressed case final previous? when widget.pressed == null) {
      _pressed = previous;
    }
  }

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_enabled) return;
    final next = !_current;
    if (widget.pressed == null) setState(() => _pressed = next);
    widget.onPressedChanged?.call(next);
  }

  void _setPointerPressed(bool value) {
    if (_pointerPressed == value || !mounted) return;
    setState(() => _pointerPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final dark = theme.brightness == Brightness.dark;
    final visualDimension = DToggle.visualDimensionFor(widget.size);
    final iconDimension = DToggle.iconDimensionFor(widget.size);
    final fontSize = DToggle.fontSizeFor(widget.size);
    final touch = switch (theme.platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    final activeSurface = _current || _hovered || _pointerPressed;
    final borderColor = widget.invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .5 : 1),
          )
        : _focusVisible
        ? tokens.focusRing
        : widget.variant == DToggleVariant.outline
        ? tokens.colors.outlineVariant
        : Colors.transparent;
    final ringColor = widget.invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .4 : .2),
          )
        : _focusVisible
        ? tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5)
        : Colors.transparent;
    final radius = BorderRadius.circular(
      widget.size == DToggleSize.small
          ? (tokens.radius * .8).clamp(0, 12)
          : tokens.radius,
    );
    final duration = DMotion.duration(
      context,
      const Duration(milliseconds: 150),
    );
    final effectiveIcon = _current
        ? widget.selectedIcon ?? widget.icon
        : widget.icon;
    final iconEdgePadding = widget.size == DToggleSize.small ? 6.0 : 8.0;
    final contentPadding = widget._iconOnly
        ? EdgeInsets.zero
        : effectiveIcon == null
        ? const EdgeInsets.symmetric(horizontal: 10)
        : widget.iconPosition == DToggleIconPosition.start
        ? EdgeInsetsDirectional.only(start: iconEdgePadding, end: 10)
        : EdgeInsetsDirectional.only(start: 10, end: iconEdgePadding);

    Widget content = widget._iconOnly
        ? ExcludeSemantics(child: effectiveIcon!)
        : DefaultTextStyle.merge(
            style: theme.textTheme.labelLarge?.copyWith(
              color: tokens.foreground,
              fontSize: fontSize,
              height: 20 / fontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            child: effectiveIcon == null
                ? ExcludeSemantics(
                    excluding: widget.semanticLabel != null,
                    child: widget.child,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.iconPosition == DToggleIconPosition.start) ...[
                        ExcludeSemantics(child: effectiveIcon),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: ExcludeSemantics(
                          excluding: widget.semanticLabel != null,
                          child: widget.child,
                        ),
                      ),
                      if (widget.iconPosition == DToggleIconPosition.end) ...[
                        const SizedBox(width: 4),
                        ExcludeSemantics(child: effectiveIcon),
                      ],
                    ],
                  ),
          );
    content = IconTheme.merge(
      data: IconThemeData(size: iconDimension, color: tokens.foreground),
      child: content,
    );

    final artwork = AnimatedContainer(
      duration: duration,
      curve: const Cubic(.4, 0, .2, 1),
      constraints: BoxConstraints(
        minWidth: visualDimension,
        minHeight: visualDimension,
      ),
      padding: contentPadding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: activeSurface ? tokens.muted : Colors.transparent,
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: ringColor,
          width: 3,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: content,
    );

    final target = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: touch ? DSpacing.touchTarget : visualDimension,
        minHeight: touch ? DSpacing.touchTarget : visualDimension,
      ),
      child: Center(child: artwork),
    );

    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        toggled: _current,
        enabled: _enabled,
        label: widget.semanticLabel,
        hint: widget.semanticHint,
        validationResult: widget.invalid
            ? SemanticsValidationResult.invalid
            : SemanticsValidationResult.none,
        onTap: _enabled ? _toggle : null,
        child: FocusableActionDetector(
          enabled: _enabled,
          focusNode: _focus,
          autofocus: widget.autofocus,
          mouseCursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          onShowHoverHighlight: (value) {
            if (_hovered != value) setState(() => _hovered = value);
          },
          onShowFocusHighlight: (value) {
            if (_focusVisible != value) setState(() => _focusVisible = value);
          },
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _toggle();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: _enabled ? (_) => _setPointerPressed(true) : null,
            onTapUp: _enabled ? (_) => _setPointerPressed(false) : null,
            onTapCancel: _enabled ? () => _setPointerPressed(false) : null,
            onTap: _enabled
                ? () {
                    _focus.requestFocus();
                    _toggle();
                  }
                : null,
            child: Opacity(opacity: _enabled ? 1 : .5, child: target),
          ),
        ),
      ),
    );
  }
}
