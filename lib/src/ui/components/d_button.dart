import 'dart:ui' show SemanticsValidationResult, lerpDouble;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../foundation/control_artwork.dart';
import '../foundation/control_style.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';
import 'd_kbd.dart';
import 'd_spinner.dart';
import 'd_tooltip.dart';

/// The reference variants, [transparentBackground] and [inline] are the
/// application styling contract.
/// Legacy names remain source-compatible aliases for external plugin callers.
enum DButtonVariant {
  outline,

  /// Creation tile with a dashed frame and framed leading icon. Give it a
  /// tight width constraint when the whole row should activate the action.
  dashedTile,
  secondary,
  ghost,

  /// Clear at rest, with a subdued foreground and a neutral interaction fill.
  transparentBackground,

  /// Transparent text action with no horizontal inset, for inline metadata.
  /// Retains the shared control height, keyboard focus and touch target.
  inline,
  destructive,
  standard,
  primary,
  danger,
  success,
  flat,
  flatClose,
  transparent,
  transparentPrimary,
  transparentDanger,
  transparentSuccess,
  link,
}

typedef DButtonSize = DControlSize;

/// Icon placement follows the ambient reading direction.
enum DButtonIconPosition { start, end }

/// Pill also produces a circular surface for icon-only buttons.
enum DButtonShape { rounded, pill }

/// Named artwork presets with shared styling and accessible touch targets.
enum DButtonDensity {
  standard,

  /// A 32px circular profile trigger with a 2px border against its avatar.
  /// Use an icon-only button with a borderless DAvatar. The image fills the
  /// interior; artwork and hit bounds grow with text.
  avatar,

  /// Text-sized 12px metadata actions and links with no visible insets.
  /// Pair with the inline variant; targets exactly follow the label bounds.
  inlineMetadata,

  /// Hierarchical back link: 13px medium text, an 11px chevron and no insets.
  /// Pair with [DButtonVariant.inline]; the hit area follows the label.
  backLink,
  mobileNavigation,

  /// A 46px labelled mobile dock item with a 20px icon and one button target.
  /// The caller supplies the icon capsule and label within the Native kit.
  mobileDock,

  /// The primary action beside a mobile dock: a 44px pill with a 20px icon
  /// matching the dock's artwork. Icon-only, its square bounds keep the pill
  /// circular, with the hit area matching the visible surface.
  mobileDockAction,

  /// Short toolbar surfaces: 24px high, 32px wide for icon-only actions,
  /// with 14px icons and matching hit areas on every platform.
  compactToolbar,

  /// Narrow desktop block actions, retaining regular icons and height.
  composerBlock,

  /// Chat message actions: 26px artwork, 11px icon and 6px corners.
  chatMessageAction,
}

@immutable
class DButtonStateStyle {
  const DButtonStateStyle({
    required this.foregroundColor,
    required this.backgroundColor,
    required this.iconColor,
    required this.border,
  });

  final Color foregroundColor;
  final Color backgroundColor;
  final Color iconColor;
  final BorderSide border;

  static DButtonStateStyle lerp(
    DButtonStateStyle first,
    DButtonStateStyle second,
    double t,
  ) => DButtonStateStyle(
    foregroundColor: Color.lerp(
      first.foregroundColor,
      second.foregroundColor,
      t,
    )!,
    backgroundColor: Color.lerp(
      first.backgroundColor,
      second.backgroundColor,
      t,
    )!,
    iconColor: Color.lerp(first.iconColor, second.iconColor, t)!,
    border: BorderSide.lerp(first.border, second.border, t),
  );
}

@immutable
class DButtonVariantStyle {
  const DButtonVariantStyle({
    required this.enabled,
    required this.interactive,
    DButtonStateStyle? focused,
    DButtonStateStyle? expanded,
  }) : focused = focused ?? interactive,
       expanded = expanded ?? enabled;

  final DButtonStateStyle enabled;
  final DButtonStateStyle interactive;
  final DButtonStateStyle focused;

  /// Surface of an open popup trigger. Defaults to [enabled].
  final DButtonStateStyle expanded;

  static DButtonVariantStyle lerp(
    DButtonVariantStyle first,
    DButtonVariantStyle second,
    double t,
  ) => DButtonVariantStyle(
    enabled: DButtonStateStyle.lerp(first.enabled, second.enabled, t),
    interactive: DButtonStateStyle.lerp(
      first.interactive,
      second.interactive,
      t,
    ),
    focused: DButtonStateStyle.lerp(first.focused, second.focused, t),
    expanded: DButtonStateStyle.lerp(first.expanded, second.expanded, t),
  );
}

/// Compatibility data for existing theme and plugin APIs. Button appearance
/// resolves through DTokens; only disabledOpacity affects the renderer.
@immutable
class DiscourseButtonTheme extends ThemeExtension<DiscourseButtonTheme> {
  const DiscourseButtonTheme({
    required this.borderRadius,
    required this.standard,
    required this.primary,
    required this.danger,
    required this.success,
    required this.flat,
    required this.flatClose,
    required this.transparent,
    required this.transparentPrimary,
    required this.transparentDanger,
    required this.transparentSuccess,
    required this.link,
    this.disabledOpacity = 0.6,
  });

  final double borderRadius;
  final double disabledOpacity;
  final DButtonVariantStyle standard;
  final DButtonVariantStyle primary;
  final DButtonVariantStyle danger;
  final DButtonVariantStyle success;
  final DButtonVariantStyle flat;
  final DButtonVariantStyle flatClose;
  final DButtonVariantStyle transparent;
  final DButtonVariantStyle transparentPrimary;
  final DButtonVariantStyle transparentDanger;
  final DButtonVariantStyle transparentSuccess;
  final DButtonVariantStyle link;

  factory DiscourseButtonTheme.fromColors(
    ColorScheme colors, {
    required double borderRadius,
    required Color hover,
    required Color success,
  }) {
    const none = BorderSide.none;

    DButtonStateStyle state({
      required Color foreground,
      required Color background,
      Color? icon,
      BorderSide border = none,
    }) => DButtonStateStyle(
      foregroundColor: foreground,
      backgroundColor: background,
      iconColor: icon ?? foreground,
      border: border,
    );

    DButtonVariantStyle filled({
      required Color background,
      required Color foreground,
      Color? interactiveBackground,
    }) => DButtonVariantStyle(
      enabled: state(foreground: foreground, background: background),
      interactive: state(
        foreground: foreground,
        background: interactiveBackground ?? background.withValues(alpha: 0.8),
      ),
    );

    DButtonVariantStyle transparent(Color foreground) => DButtonVariantStyle(
      enabled: state(foreground: foreground, background: Colors.transparent),
      interactive: state(foreground: foreground, background: hover),
    );

    final standard = DButtonVariantStyle(
      enabled: state(
        foreground: colors.onSurface,
        background: colors.surfaceContainerHigh,
        border: BorderSide(color: colors.outlineVariant),
      ),
      interactive: state(
        foreground: colors.onSurface,
        background: hover,
        border: BorderSide(color: colors.outline),
      ),
    );
    final flat = transparent(colors.onSurfaceVariant);

    return DiscourseButtonTheme(
      borderRadius: borderRadius,
      standard: standard,
      primary: filled(background: colors.primary, foreground: colors.onPrimary),
      danger: filled(background: colors.error, foreground: colors.onError),
      success: filled(background: success, foreground: colors.surface),
      flat: flat,
      flatClose: flat,
      transparent: DButtonVariantStyle(
        enabled: state(
          foreground: colors.onSurface,
          icon: colors.onSurfaceVariant,
          background: Colors.transparent,
        ),
        interactive: state(
          foreground: colors.primary,
          background: Colors.transparent,
        ),
      ),
      transparentPrimary: transparent(colors.primary),
      transparentDanger: transparent(colors.error),
      transparentSuccess: transparent(success),
      link: transparent(colors.primary),
    );
  }

  @override
  DiscourseButtonTheme copyWith({
    double? borderRadius,
    double? disabledOpacity,
    DButtonVariantStyle? standard,
    DButtonVariantStyle? primary,
    DButtonVariantStyle? danger,
    DButtonVariantStyle? success,
    DButtonVariantStyle? flat,
    DButtonVariantStyle? flatClose,
    DButtonVariantStyle? transparent,
    DButtonVariantStyle? transparentPrimary,
    DButtonVariantStyle? transparentDanger,
    DButtonVariantStyle? transparentSuccess,
    DButtonVariantStyle? link,
  }) => DiscourseButtonTheme(
    borderRadius: borderRadius ?? this.borderRadius,
    disabledOpacity: disabledOpacity ?? this.disabledOpacity,
    standard: standard ?? this.standard,
    primary: primary ?? this.primary,
    danger: danger ?? this.danger,
    success: success ?? this.success,
    flat: flat ?? this.flat,
    flatClose: flatClose ?? this.flatClose,
    transparent: transparent ?? this.transparent,
    transparentPrimary: transparentPrimary ?? this.transparentPrimary,
    transparentDanger: transparentDanger ?? this.transparentDanger,
    transparentSuccess: transparentSuccess ?? this.transparentSuccess,
    link: link ?? this.link,
  );

  @override
  DiscourseButtonTheme lerp(covariant DiscourseButtonTheme? other, double t) {
    if (other == null) return this;
    return DiscourseButtonTheme(
      borderRadius: lerpDouble(borderRadius, other.borderRadius, t)!,
      disabledOpacity: lerpDouble(disabledOpacity, other.disabledOpacity, t)!,
      standard: DButtonVariantStyle.lerp(standard, other.standard, t),
      primary: DButtonVariantStyle.lerp(primary, other.primary, t),
      danger: DButtonVariantStyle.lerp(danger, other.danger, t),
      success: DButtonVariantStyle.lerp(success, other.success, t),
      flat: DButtonVariantStyle.lerp(flat, other.flat, t),
      flatClose: DButtonVariantStyle.lerp(flatClose, other.flatClose, t),
      transparent: DButtonVariantStyle.lerp(transparent, other.transparent, t),
      transparentPrimary: DButtonVariantStyle.lerp(
        transparentPrimary,
        other.transparentPrimary,
        t,
      ),
      transparentDanger: DButtonVariantStyle.lerp(
        transparentDanger,
        other.transparentDanger,
        t,
      ),
      transparentSuccess: DButtonVariantStyle.lerp(
        transparentSuccess,
        other.transparentSuccess,
        t,
      ),
      link: DButtonVariantStyle.lerp(link, other.link, t),
    );
  }
}

extension DiscourseButtonThemeAccess on ThemeData {
  DiscourseButtonTheme get discourseButtons =>
      extension<DiscourseButtonTheme>() ??
      DiscourseButtonTheme.fromColors(
        colorScheme,
        borderRadius: DRadius.control,
        hover: colorScheme.surfaceContainerHigh,
        success: const Color(0xFF009900),
      );
}

/// A compact Native button with application-owned activation and busy state.
///
/// [loading] blocks activation; callbacks own asynchronous work and errors.
/// [focusNode] is borrowed and never disposed. [label] accepts rich content;
/// Text can opt into wrapping using its own softWrap and maxLines properties.
/// Icon-only controls require an accessible tooltip. Desktop surfaces follow
/// the shared Native sizes, with platform-sized surfaces and matching hit areas.
/// The painted surface is a [DButtonDecoration]: state changes transition
/// together over 150ms, except hover changes and popup dismissal, which apply
/// immediately to avoid lingering highlights.
class DButton extends StatelessWidget {
  const DButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconPosition = DButtonIconPosition.start,
    this.expanded = false,
    this.invalid = false,
    this.hasPopup = false,
    this.isLink = false,
    this.variant = DButtonVariant.primary,
    this.size = DButtonSize.regular,
    this.density = DButtonDensity.standard,
    this.loading = false,
    this._loadingSemanticLabel,
    this.loadingLabel,
    this.tooltip,
    this.tooltipSide = DTooltipSide.top,
    this.shortcut,
    this.semanticLabel,
    this.focusNode,
    this.mouseCursor,
    this.autofocus = false,
    this.alignment = Alignment.center,
    this.shape = DButtonShape.rounded,
    this.animationDuration,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.interactiveBackgroundColor,
  }) : _iconOnly = false;

  const DButton.iconOnly({
    super.key,
    required Widget icon,
    required String tooltip,
    this.tooltipSide = DTooltipSide.top,
    required this.onPressed,
    this.variant = DButtonVariant.primary,
    this.size = DButtonSize.regular,
    this.density = DButtonDensity.standard,
    this.loading = false,
    this._loadingSemanticLabel,
    this.shortcut,
    this.semanticLabel,
    this.focusNode,
    this.mouseCursor,
    this.autofocus = false,
    this.alignment = Alignment.center,
    this.shape = DButtonShape.rounded,
    this.animationDuration,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.interactiveBackgroundColor,
    this.expanded = false,
    this.invalid = false,
    this.hasPopup = false,
    this.isLink = false,
  }) : iconPosition = DButtonIconPosition.start,
       label = const SizedBox.shrink(),
       loadingLabel = null,
       // ignore: prefer_initializing_formals
       icon = icon,
       // ignore: prefer_initializing_formals
       tooltip = tooltip,
       _iconOnly = true;

  final Widget label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final DButtonIconPosition iconPosition;

  /// Open popup triggers keep their expanded surface. With [hasPopup] the
  /// state is also exposed to assistive technology.
  final bool expanded;

  /// Validation styling and semantics for a form or popup trigger.
  final bool invalid;

  /// Exposes popup and expanded semantics without changing the button's shape.
  final bool hasPopup;

  /// Gives navigation callbacks a link role while retaining button styling.
  /// The application owns route or URL opening; no networking is performed.
  final bool isLink;
  final DButtonVariant variant;
  final DButtonSize size;

  /// Mobile navigation supersedes [size] with a 44px surface, 18px icon and
  /// regular typography. It grows with text scaling.
  /// Mobile dock supersedes [size] with a 46px clear surface and 11px label;
  /// DMobileDockItem supplies its selected icon capsule and inline count.
  /// Mobile dock action supersedes [size] with a 44px surface and 20px icon;
  /// icon-only, it takes its parent's width with the icon centred.
  /// Compact toolbar supersedes [size] with small typography, 14px icons and
  /// 24px artwork (32px wide for icon-only actions), with matching hit areas.
  /// Chat message actions use 26px artwork, 11px icons and 6px corners.
  final DButtonDensity density;

  final bool loading;

  final String? _loadingSemanticLabel;

  /// Localizable busy status, separate from the persistent action name.
  String get loadingSemanticLabel =>
      _loadingSemanticLabel ?? appL10n.loadingDbutton;
  final Widget? loadingLabel;
  final String? tooltip;

  /// Preferred placement of the tooltip relative to the button.
  final DTooltipSide tooltipSide;
  final DShortcut? shortcut;
  final String? semanticLabel;
  final FocusNode? focusNode;

  /// Cursor for enabled actions, e.g. an open hand on a drag handle.
  /// Disabled actions retain the default arrow.
  final MouseCursor? mouseCursor;
  final bool autofocus;
  final AlignmentGeometry alignment;

  /// Primary actions default to a pill; other buttons use the control radius.
  final DButtonShape shape;

  /// Overrides the button's state and shape transition duration.
  /// Reduced motion still applies changes immediately.
  final Duration? animationDuration;
  final BorderRadiusGeometry? borderRadius;

  /// Overrides the variant's fill in every state, including expanded and
  /// disabled. [interactiveBackgroundColor] takes precedence while hovered
  /// or focused. Use [foregroundColor] to override the variant's label and icon.
  final Color? backgroundColor;

  /// Overrides label and icon color together, including disabled states.
  /// The focus ring retains its separate themed color.
  final Color? foregroundColor;

  /// Overrides the one-pixel border in every state except [invalid]. The themed focus
  /// ring remains visible, and joined groups still omit the shared border.
  final Color? borderColor;

  /// Overrides the hover/focus fill.
  /// An expanded secondary button keeps its expanded fill instead.
  final Color? interactiveBackgroundColor;
  final bool _iconOnly;

  static double fontSizeFor(DButtonSize size) => DControlStyle.fontSize(size);

  static double visualDimensionFor(DButtonSize size) =>
      DControlStyle.height(size);

  static double iconOnlyDimensionFor(DButtonSize size) =>
      DControlStyle.height(size);

  /// Width reserved by compact composer actions; touch keeps regular geometry.
  static double composerBlockWidth(BuildContext context) {
    final height = DControlStyle.scaledHeight(
      DButtonSize.regular,
      MediaQuery.textScalerOf(context),
      context: context,
    );
    return DControlStyle.isTouch(context) ? height : height * 20 / 34;
  }

  DButtonVariant get _visualVariant => switch (variant) {
    DButtonVariant.standard => DButtonVariant.outline,
    DButtonVariant.danger ||
    DButtonVariant.transparentDanger => DButtonVariant.destructive,
    DButtonVariant.success ||
    DButtonVariant.transparentSuccess ||
    DButtonVariant.transparentPrimary => DButtonVariant.primary,
    DButtonVariant.flat ||
    DButtonVariant.flatClose ||
    DButtonVariant.transparent => DButtonVariant.ghost,
    _ => variant,
  };

  DButtonVariantStyle _referenceStyle(DTokens tokens, bool dark) {
    final buttons = tokens.buttonTheme;
    final subduedForeground = buttons.accent.foreground;
    DButtonStateStyle state(
      Color background,
      Color foreground, [
      Color? border,
    ]) => DButtonStateStyle(
      foregroundColor: foreground,
      backgroundColor: background,
      iconColor: foreground,
      border: BorderSide(color: border ?? Colors.transparent),
    );
    DButtonVariantStyle pair(
      Color background,
      Color hover,
      Color foreground, {
      Color? border,
      Color? expanded,
    }) => DButtonVariantStyle(
      enabled: state(background, foreground, border),
      interactive: state(hover, foreground, border),
      focused: state(background, foreground, border),
      expanded: state(expanded ?? background, foreground, border),
    );
    final outline = DButtonVariantStyle(
      enabled: state(
        buttons.outline.background,
        buttons.outline.foreground,
        buttons.outline.border,
      ),
      interactive: state(
        buttons.outline.hover,
        buttons.outline.foreground,
        buttons.outline.hoverBorder,
      ),
      focused: state(
        buttons.outline.background,
        buttons.outline.foreground,
        buttons.outline.border,
      ),
      expanded: state(
        buttons.outline.hover,
        buttons.outline.foreground,
        buttons.outline.hoverBorder,
      ),
    );
    return switch (_visualVariant) {
      DButtonVariant.primary => pair(
        buttons.primary.background,
        buttons.primary.hover,
        buttons.primary.foreground,
        expanded: buttons.primary.hover,
      ),
      DButtonVariant.outline || DButtonVariant.secondary => outline,
      DButtonVariant.dashedTile => DButtonVariantStyle(
        enabled: state(
          Colors.transparent,
          tokens.mutedForeground,
          tokens.border,
        ),
        interactive: state(
          buttons.accent.hover,
          tokens.foreground,
          tokens.border,
        ),
        focused: state(Colors.transparent, tokens.foreground, tokens.border),
      ),
      DButtonVariant.ghost ||
      DButtonVariant.transparentBackground => DButtonVariantStyle(
        enabled: state(Colors.transparent, subduedForeground),
        interactive: state(buttons.accent.hover, tokens.foreground),
        focused: state(Colors.transparent, tokens.foreground),
        expanded: state(buttons.accent.hover, tokens.foreground),
      ),
      DButtonVariant.inline => DButtonVariantStyle(
        enabled: state(Colors.transparent, subduedForeground),
        interactive: state(Colors.transparent, tokens.foreground),
        focused: state(Colors.transparent, tokens.foreground),
        expanded: state(Colors.transparent, tokens.foreground),
      ),
      DButtonVariant.destructive => pair(
        _alpha(tokens.destructive, dark ? .2 : .1),
        _alpha(tokens.destructive, dark ? .3 : .2),
        tokens.destructive,
      ),
      DButtonVariant.link => pair(
        Colors.transparent,
        Colors.transparent,
        tokens.primary,
      ),
      _ => throw StateError('Unresolved legacy button variant: $variant'),
    };
  }

  /// CSS opacity modifiers multiply the token's own alpha.
  static Color _alpha(Color color, double factor) =>
      color.withValues(alpha: color.a * factor);

  @override
  Widget build(BuildContext context) {
    final effectiveSemanticLabel =
        semanticLabel ?? (_iconOnly ? tooltip : null);
    final theme = Theme.of(context);
    final buttons = theme.discourseButtons;
    final tokens = DTokens.of(context);
    final dark = theme.brightness == Brightness.dark;
    final variantStyle = _referenceStyle(tokens, dark);
    final mobileNavigation = density == DButtonDensity.mobileNavigation;
    final mobileDock = density == DButtonDensity.mobileDock;
    final mobileDockAction = density == DButtonDensity.mobileDockAction;
    final compactToolbar = density == DButtonDensity.compactToolbar;
    final chatMessageAction = density == DButtonDensity.chatMessageAction;
    final backLink = density == DButtonDensity.backLink;
    final inlineMetadata = density == DButtonDensity.inlineMetadata;
    final avatar = density == DButtonDensity.avatar;
    final dashedTile = variant == DButtonVariant.dashedTile;
    final intrinsicIcon =
        _iconOnly &&
        (size == DControlSize.chip || size == DControlSize.chrome) &&
        density == DButtonDensity.standard;
    final composerBlock = _iconOnly && density == DButtonDensity.composerBlock;
    final effectiveSize = backLink
        ? DButtonSize.toolbar
        : compactToolbar
        ? DButtonSize.small
        : avatar ||
              mobileNavigation ||
              mobileDock ||
              mobileDockAction ||
              composerBlock
        ? DButtonSize.regular
        : size;
    final fontSize = inlineMetadata
        ? 12.0
        : dashedTile
        ? DControlStyle.fontSize(DButtonSize.large, context: context)
        : DControlStyle.fontSize(effectiveSize, context: context);
    final spacingUnit = backLink
        ? 11.0
        : mobileDock || mobileDockAction
        ? 20.0
        : mobileNavigation
        ? 18.0
        : chatMessageAction
        ? 16.0
        : compactToolbar
        ? 14.0
        : DControlStyle.iconDimension(effectiveSize, context: context);
    final gap = dashedTile ? 12.0 : DControlStyle.contentGap(effectiveSize);
    final standardDimension =
        DControlStyle.scaledHeight(
          effectiveSize,
          MediaQuery.textScalerOf(context),
          context: compactToolbar ? null : context,
        ).clamp(
          mobileDock
              ? 46.0
              : mobileNavigation || mobileDockAction
              ? 44.0
              : 0.0,
          double.infinity,
        );
    final visualDimension = avatar
        ? 32.0 *
              (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                1,
                double.infinity,
              )
        : inlineMetadata
        ? MediaQuery.textScalerOf(context).scale(12) * 1.5
        : backLink
        ? MediaQuery.textScalerOf(context).scale(fontSize) * 1.5
        : dashedTile
        ? 50 +
              (MediaQuery.textScalerOf(context).scale(fontSize) - fontSize) *
                  1.5
        : chatMessageAction
        ? 26 +
              (MediaQuery.textScalerOf(context).scale(fontSize) - fontSize) *
                  1.5
        : standardDimension;
    final enabled = onPressed != null && !loading;
    final baseRadius =
        borderRadius ??
        BorderRadius.circular(
          avatar ||
                  shape == DButtonShape.pill ||
                  variant == DButtonVariant.primary
              ? DRadius.pill
              : chatMessageAction
              ? 6
              : effectiveSize == DControlSize.tabAction
              ? 9
              : dashedTile
              ? DRadius.bubble
              : DRadius.control,
        );
    final direction = Directionality.of(context);
    final joined = DJoinedControlScope.maybeOf(context);
    final surfaceWidth = composerBlock
        ? composerBlockWidth(context)
        : compactToolbar || effectiveSize == DControlSize.chip
        ? visualDimension + 8
        : visualDimension;
    final surfaceHeight = visualDimension;
    final iconOnlySurfaceSize = Size(surfaceWidth, surfaceHeight);
    var radius =
        joined?.resolveRadius(baseRadius, direction) ??
        baseRadius.resolve(direction);
    if (_iconOnly) {
      // Interpolate the visible corners, not the oversized pill sentinel.
      // A 999px radius stays circular until the very end of a shape tween.
      final visible = radius
          .toRRect(Offset.zero & iconOnlySurfaceSize)
          .scaleRadii();
      radius = BorderRadius.only(
        topLeft: visible.tlRadius,
        topRight: visible.trRadius,
        bottomLeft: visible.blRadius,
        bottomRight: visible.brRadius,
      );
    }
    final effectiveAnimationDuration = DMotion.duration(
      context,
      animationDuration ?? DControlStyle.duration,
    );
    final destructiveRing =
        invalid || _visualVariant == DButtonVariant.destructive;
    final ringColor = destructiveRing ? tokens.destructive : tokens.focusRing;

    DButtonStateStyle withBackground(
      DButtonStateStyle state, {
      bool interactive = false,
    }) {
      final background = interactive
          ? interactiveBackgroundColor ?? backgroundColor
          : backgroundColor;
      if (background == null && foregroundColor == null) return state;
      return DButtonStateStyle(
        foregroundColor: foregroundColor ?? state.foregroundColor,
        backgroundColor: background ?? state.backgroundColor,
        iconColor: foregroundColor ?? state.iconColor,
        border: state.border,
      );
    }

    DButtonStateStyle resolveState(Set<WidgetState> states) {
      if (mobileDock) {
        final foreground = foregroundColor ?? tokens.mutedForeground;
        return DButtonStateStyle(
          foregroundColor: foreground,
          iconColor: foreground,
          backgroundColor: Colors.transparent,
          border: BorderSide.none,
        );
      }
      if (states.contains(WidgetState.disabled)) {
        final base = withBackground(variantStyle.enabled);
        return _visualVariant == DButtonVariant.primary ||
                _visualVariant == DButtonVariant.destructive ||
                foregroundColor != null
            ? base
            : DButtonStateStyle(
                foregroundColor: tokens.mutedForeground,
                iconColor: tokens.mutedForeground,
                backgroundColor: base.backgroundColor,
                border: base.border,
              );
      }
      final interactive =
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed);
      if (expanded &&
          (!interactive || _visualVariant == DButtonVariant.secondary)) {
        return withBackground(variantStyle.expanded);
      }
      if (interactive) {
        return withBackground(variantStyle.interactive, interactive: true);
      }
      if (states.contains(WidgetState.focused)) {
        return withBackground(variantStyle.focused, interactive: true);
      }
      return withBackground(variantStyle.enabled);
    }

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        _iconOnly && !intrinsicIcon
            ? iconOnlySurfaceSize
            : Size(0, surfaceHeight),
      ),
      fixedSize: _iconOnly && !intrinsicIcon
          ? WidgetStatePropertyAll(iconOnlySurfaceSize)
          : null,
      maximumSize: _iconOnly && !intrinsicIcon
          ? WidgetStatePropertyAll(iconOnlySurfaceSize)
          : const WidgetStatePropertyAll(Size.infinite),
      padding: WidgetStatePropertyAll(
        (avatar
            ? const EdgeInsets.all(2)
            : _iconOnly && !intrinsicIcon
            ? EdgeInsets.zero
            : mobileDock || backLink || inlineMetadata
            ? EdgeInsets.zero
            : dashedTile
            ? const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8)
            : variant == DButtonVariant.inline
            ? const EdgeInsets.symmetric(vertical: 1)
            : DControlStyle.isApplicationSize(effectiveSize)
            ? EdgeInsets.symmetric(
                horizontal: DControlStyle.horizontalInset(effectiveSize),
                vertical: 1,
              )
            : EdgeInsetsDirectional.only(
                start:
                    (icon != null || (loading && loadingLabel != null)) &&
                        iconPosition == DButtonIconPosition.start
                    ? (effectiveSize == DButtonSize.small ? 6 : 8)
                    : (effectiveSize == DButtonSize.small ? 8 : 12),
                end:
                    (icon != null || (loading && loadingLabel != null)) &&
                        iconPosition == DButtonIconPosition.end
                    ? (effectiveSize == DButtonSize.small ? 6 : 8)
                    : (effectiveSize == DButtonSize.small ? 8 : 12),
                top: 1,
                bottom: 1,
              )),
      ),
      textStyle: WidgetStateProperty.resolveWith(
        (states) => theme.textTheme.labelLarge!.copyWith(
          fontSize: mobileDock ? 11 : fontSize,
          height: inlineMetadata
              ? 1.5
              : mobileDock
              ? 13 / 11
              : dashedTile
              ? DControlStyle.lineHeight(DButtonSize.large, context: context) /
                    fontSize
              : DControlStyle.lineHeight(effectiveSize, context: context) /
                    fontSize,
          fontWeight: mobileDock || backLink
              ? FontWeight.w500
              : _visualVariant == DButtonVariant.primary || dashedTile
              ? FontWeight.w600
              : FontWeight.w400,
          letterSpacing: 0,
          decoration:
              variant == DButtonVariant.link &&
                  states.contains(WidgetState.hovered)
              ? TextDecoration.underline
              : TextDecoration.none,
        ),
      ),
      iconSize: WidgetStatePropertyAll(spacingUnit),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => resolveState(states).foregroundColor,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => resolveState(states).iconColor,
      ),
      // The surface built below paints fill, border and ring so that they
      // transition together; the Material stays transparent.
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      side: const WidgetStatePropertyAll(BorderSide.none),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: radius),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      animationDuration: effectiveAnimationDuration,
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      mouseCursor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : mouseCursor ?? SystemMouseCursors.click,
      ),
      alignment: alignment,
      backgroundBuilder: (context, states, child) {
        final state = resolveState(states);
        final focused =
            states.contains(WidgetState.focused) &&
            DFocusHighlight.visibleOf(context);
        final border = state.border;
        final resolvedBorderColor = invalid
            ? _alpha(tokens.destructive, dark ? .5 : 1)
            : joined?.sharedOutline == true
            ? Colors.transparent
            : borderColor ??
                  (avatar ? tokens.border : null) ??
                  (border.style == BorderStyle.none || border.width == 0
                      ? Colors.transparent
                      : border.color);
        final surface = _DButtonSurface(
          duration: effectiveAnimationDuration,
          hovered:
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed),
          expanded: expanded,
          transform: Matrix4.identity(),
          decoration: DButtonDecoration(
            color: state.backgroundColor,
            borderColor: resolvedBorderColor,
            borderRadius: radius,
            ringColor: ringColor,
            ringWidth: focused || invalid ? DControlStyle.focusWidth : 0,
            ringOffset: DControlStyle.focusOffset,
            strokeWidth: avatar ? 2 : 1,
            dashed: dashedTile,
            joinedAxis: joined?.omitsLeadingBorder ?? false
                ? joined!.axis
                : null,
          ),
          child: child,
        );
        final artwork = DControlArtwork(child: surface);
        return joined == null ? artwork : DJoinedControlSurface(child: artwork);
      },
    );

    final leadingIcon = dashedTile && icon != null
        ? SizedBox(
            width: 34,
            height: 34,
            child: DecoratedBox(
              decoration: DButtonDecoration(
                color: Colors.transparent,
                borderColor: tokens.border,
                borderRadius: BorderRadius.circular(DRadius.control),
                strokeWidth: 1,
                dashed: true,
              ),
              child: Center(child: icon),
            ),
          )
        : icon;
    Widget child = _iconOnly
        ? ExcludeSemantics(child: icon!)
        : DefaultTextStyle.merge(
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            child: leadingIcon == null
                ? ExcludeSemantics(
                    excluding: semanticLabel != null,
                    child: label,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (iconPosition == DButtonIconPosition.start) ...[
                        ExcludeSemantics(child: leadingIcon),
                        SizedBox(width: gap),
                      ],
                      Flexible(
                        child: ExcludeSemantics(
                          excluding: semanticLabel != null,
                          child: label,
                        ),
                      ),
                      if (iconPosition == DButtonIconPosition.end) ...[
                        SizedBox(width: gap),
                        ExcludeSemantics(child: leadingIcon),
                      ],
                    ],
                  ),
          );
    if (avatar && _iconOnly) {
      child = SizedBox.expand(child: child);
    }
    if (mobileNavigation ||
        mobileDock ||
        mobileDockAction ||
        DControlStyle.isApplicationSize(effectiveSize)) {
      child = DIconGlyphTheme(
        scale: 1,
        naturalWidth: DControlStyle.isApplicationSize(effectiveSize),
        child: child,
      );
    }
    if (loading) {
      final labelChild = child;
      // The reference Spinner carries its own size-4 class, so it stays 16px
      // where a plain icon would shrink with the xs and sm sizes.
      const indicator = DSpinner(semanticLabel: null);
      child = loadingLabel == null
          ? indicator
          : DefaultTextStyle.merge(
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (iconPosition == DButtonIconPosition.start) ...[
                    indicator,
                    SizedBox(width: gap),
                  ],
                  Flexible(
                    child: ExcludeSemantics(
                      excluding: semanticLabel != null,
                      child: loadingLabel!,
                    ),
                  ),
                  if (iconPosition == DButtonIconPosition.end) ...[
                    SizedBox(width: gap),
                    indicator,
                  ],
                ],
              ),
            );
      if (!_iconOnly && semanticLabel == null) {
        child = Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(child: child),
            // Keep the label's own semantics without painting it or changing
            // the loading content's size. Its layout keeps the usual constraints.
            SizedOverflowBox(
              size: Size.zero,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0,
                  alwaysIncludeSemantics: true,
                  child: labelChild,
                ),
              ),
            ),
          ],
        );
      }
    }

    // The exterior ring paints beyond the Material, so the button never clips.
    Widget result = isLink
        ? _DLinkPrimitive(
            onPressed: enabled ? onPressed : null,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: Clip.none,
            child: child,
          )
        : FilledButton(
            onPressed: enabled ? onPressed : null,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: Clip.none,
            child: child,
          );
    if (!enabled) {
      result = Opacity(opacity: buttons.disabledOpacity, child: result);
    }
    if (tooltip case final tooltip?) {
      result = DTooltip(
        message: tooltip,
        side: tooltipSide,
        shortcut: shortcut,
        excludeFromSemantics: effectiveSemanticLabel != null,
        child: result,
      );
    }

    if (backLink) {
      // The reference chevron has no leading bearing: tuck the link 2px
      // into the page gutter while keeping its focus ring and target together.
      result = Transform.translate(
        offset: Offset(direction == TextDirection.ltr ? -2 : 2, 0),
        child: result,
      );
    }

    return MergeSemantics(
      child: Semantics(
        button: !isLink,
        link: isLink,
        enabled: enabled,
        expanded: hasPopup ? expanded : null,
        validationResult: invalid
            ? SemanticsValidationResult.invalid
            : SemanticsValidationResult.none,
        liveRegion: loading,
        label: effectiveSemanticLabel,
        value: loading ? loadingSemanticLabel : null,
        child: result,
      ),
    );
  }
}

// Apply hover changes immediately: entry must not cycle through intermediate
// fills, and exit must not leave a trail on adjacent controls. Clear expanded
// styling immediately on dismissal too. Other state changes keep the shared
// control transition.
class _DButtonSurface extends StatefulWidget {
  const _DButtonSurface({
    required this.duration,
    required this.hovered,
    required this.expanded,
    required this.transform,
    required this.decoration,
    required this.child,
  });

  final Duration duration;
  final bool hovered;
  final bool expanded;
  final Matrix4 transform;
  final DButtonDecoration decoration;
  final Widget? child;

  @override
  State<_DButtonSurface> createState() => _DButtonSurfaceState();
}

class _DButtonSurfaceState extends State<_DButtonSurface> {
  bool _skipTransition = false;

  @override
  void didUpdateWidget(_DButtonSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _skipTransition =
        oldWidget.hovered != widget.hovered ||
        (oldWidget.expanded && !widget.expanded);
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: _skipTransition ? Duration.zero : widget.duration,
    curve: Curves.ease,
    transform: widget.transform,
    decoration: widget.decoration,
    child: widget.child,
  );
}

/// The painted button surface: a fill clipped to the padding box, a one-pixel
/// border and exterior focus or invalid ring.
///
/// A visible border surrounds the fill; borderless surfaces fill their bounds.
/// [DControlDecoration.joinedAxis] names the axis along
/// which the leading edge is shared with a preceding control: that edge has no
/// border and the fill reaches it. The ring is painted outside the bounds.
typedef DButtonDecoration = DControlDecoration;

// ButtonStyleButton retains native Actions/Focus and activation semantics.
// Navigation must not expose the button role inherited by FilledButton.
class _DLinkPrimitive extends FilledButton {
  const _DLinkPrimitive({
    required super.onPressed,
    required super.child,
    super.style,
    super.focusNode,
    super.autofocus,
    super.clipBehavior,
  });

  @override
  bool get isSemanticButton => false;
}
