import 'dart:math' as math;
import 'dart:ui' show SemanticsValidationResult, lerpDouble;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';
import 'd_kbd.dart';
import 'd_spinner.dart';
import 'd_tooltip.dart';

enum DButtonVariant {
  outline,
  secondary,
  ghost,
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

enum DButtonSize { extraSmall, small, regular, large }

/// Icon placement follows the ambient reading direction.
enum DButtonIconPosition { start, end }

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

  DButtonStateStyle withOpacity(double opacity) => DButtonStateStyle(
    foregroundColor: foregroundColor.withValues(
      alpha: foregroundColor.a * opacity,
    ),
    backgroundColor: backgroundColor.withValues(
      alpha: backgroundColor.a * opacity,
    ),
    iconColor: iconColor.withValues(alpha: iconColor.a * opacity),
    border: border.copyWith(
      color: border.color.withValues(alpha: border.color.a * opacity),
    ),
  );

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
    this.disabledOpacity = 0.5,
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

  DButtonVariantStyle styleFor(DButtonVariant variant) => switch (variant) {
    DButtonVariant.outline => standard,
    DButtonVariant.secondary => standard,
    DButtonVariant.ghost => flat,
    DButtonVariant.destructive => danger,
    DButtonVariant.standard => standard,
    DButtonVariant.primary => primary,
    DButtonVariant.danger => danger,
    DButtonVariant.success => success,
    DButtonVariant.flat => flat,
    DButtonVariant.flatClose => flatClose,
    DButtonVariant.transparent => transparent,
    DButtonVariant.transparentPrimary => transparentPrimary,
    DButtonVariant.transparentDanger => transparentDanger,
    DButtonVariant.transparentSuccess => transparentSuccess,
    DButtonVariant.link => link,
  };

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
        borderRadius: 4,
        hover: colorScheme.surfaceContainerHigh,
        success: const Color(0xFF009900),
      );
}

/// A compact shadcn button with application-owned activation and busy state.
///
/// [loading] blocks activation; callbacks own asynchronous work and errors.
/// [focusNode] is borrowed and never disposed. [label] accepts rich content;
/// Text can opt into wrapping using its own softWrap and maxLines properties.
/// Icon-only controls require an accessible tooltip. Desktop surfaces follow
/// base-nova sizes; touch platforms expand their invisible targets to 48px.
/// The painted surface is a [DButtonDecoration]: hover, expanded, focus,
/// invalid and pressed changes transition together over 150ms.
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
    this.loading = false,
    this.loadingSemanticLabel = 'Loading',
    this.loadingLabel,
    this.tooltip,
    this.shortcut,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.alignment = Alignment.center,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.interactiveBackgroundColor,
  }) : insetSurface = false,
       _iconOnly = false;

  const DButton.iconOnly({
    super.key,
    required Widget icon,
    required String tooltip,
    required this.onPressed,
    this.variant = DButtonVariant.primary,
    this.size = DButtonSize.regular,
    this.insetSurface = false,
    this.loading = false,
    this.loadingSemanticLabel = 'Loading',
    this.shortcut,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.interactiveBackgroundColor,
    this.expanded = false,
    this.invalid = false,
    this.hasPopup = false,
    this.isLink = false,
  }) : iconPosition = DButtonIconPosition.start,
       label = const SizedBox.shrink(),
       padding = null,
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

  /// Popup triggers do not translate down when pressed.
  final bool hasPopup;

  /// Gives navigation callbacks a link role while retaining button styling.
  /// The application owns route or URL opening; no networking is performed.
  final bool isLink;
  final DButtonVariant variant;
  final DButtonSize size;

  /// Insets the icon surface while preserving the size's full hit target.
  final bool insetSurface;
  final bool loading;

  /// Localizable busy status, separate from the persistent action name.
  final String loadingSemanticLabel;
  final Widget? loadingLabel;
  final String? tooltip;
  final DShortcut? shortcut;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final AlignmentGeometry alignment;

  /// Replaces the size's padding, including its 1px border inset.
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;

  /// Overrides the variant's fill in every state, including expanded and
  /// disabled. [interactiveBackgroundColor] takes precedence on hover/focus
  /// and compatibility-variant presses. Foreground colors remain variant-owned.
  final Color? backgroundColor;

  /// Overrides the 1px border in every state except [invalid]. The themed focus
  /// ring remains visible, and joined groups still omit the shared border.
  final Color? borderColor;

  /// Overrides the hover/focus fill and compatibility-variant pressed fill.
  /// An expanded secondary button keeps its expanded fill instead.
  final Color? interactiveBackgroundColor;
  final bool _iconOnly;

  static const double minimumDimension = 48;
  static const double flatSurfacePadding = 4;

  static double fontSizeFor(DButtonSize size) => switch (size) {
    DButtonSize.extraSmall => DiscourseTypography.xs,
    DButtonSize.small => DiscourseTypography.base * .8,
    _ => DiscourseTypography.sm,
  };

  static double visualDimensionFor(DButtonSize size) => switch (size) {
    DButtonSize.extraSmall => 24,
    DButtonSize.small => 28,
    DButtonSize.regular => 32,
    DButtonSize.large => 36,
  };

  /// Legacy shell hit targets remain available for inset icon actions.
  static double iconOnlyDimensionFor(DButtonSize size) => switch (size) {
    DButtonSize.extraSmall => 48,
    DButtonSize.small => 40,
    DButtonSize.regular => minimumDimension,
    DButtonSize.large => 56,
  };

  bool get _isReferenceVariant => switch (variant) {
    DButtonVariant.primary ||
    DButtonVariant.outline ||
    DButtonVariant.secondary ||
    DButtonVariant.ghost ||
    DButtonVariant.destructive ||
    DButtonVariant.link => true,
    _ => false,
  };

  DButtonVariantStyle _referenceStyle(
    DTokens tokens,
    bool dark,
    DiscourseButtonTheme compatibility,
  ) {
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
    final input = tokens.colors.outlineVariant;
    return switch (variant) {
      DButtonVariant.primary => pair(
        tokens.primary,
        _alpha(tokens.primary, .8),
        tokens.primaryForeground,
      ),
      // Dark rest and hover surfaces are declared after aria-expanded in the
      // reference stylesheet, so an open dark outline trigger does not change.
      DButtonVariant.outline when dark => pair(
        _alpha(input, .3),
        _alpha(input, .5),
        tokens.foreground,
        border: input,
      ),
      DButtonVariant.outline => pair(
        tokens.background,
        tokens.muted,
        tokens.foreground,
        border: tokens.border,
        expanded: tokens.muted,
      ),
      DButtonVariant.secondary => pair(
        tokens.muted,
        Color.lerp(tokens.muted, tokens.foreground, .05)!,
        tokens.foreground,
        expanded: tokens.muted,
      ),
      DButtonVariant.ghost => pair(
        Colors.transparent,
        _alpha(tokens.muted, dark ? .5 : 1),
        tokens.foreground,
        expanded: tokens.muted,
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
      _ => compatibility.styleFor(variant),
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
    final reference = _isReferenceVariant;
    final variantStyle = _referenceStyle(tokens, dark, buttons);
    final fontSize = fontSizeFor(size);
    final spacingUnit = switch (size) {
      DButtonSize.extraSmall => 12.0,
      DButtonSize.small => _iconOnly ? 16.0 : 14.0,
      _ => 16.0,
    };
    final gap = size == DButtonSize.extraSmall || size == DButtonSize.small
        ? 4.0
        : 6.0;
    final visualDimension = visualDimensionFor(size);
    final touch =
        theme.platform == TargetPlatform.iOS ||
        theme.platform == TargetPlatform.android;
    final iconOnlyDimension = iconOnlyDimensionFor(size);
    final iconTargetDimension = touch
        ? iconOnlyDimension.clamp(DSpacing.touchTarget, double.infinity)
        : iconOnlyDimension;
    final insetIconSurface =
        _iconOnly &&
        (insetSurface ||
            variant == DButtonVariant.flat ||
            variant == DButtonVariant.flatClose);
    final iconOnlySurfaceDimension = insetIconSurface
        ? iconOnlyDimension - flatSurfacePadding * 2
        : visualDimension;
    final enabled = onPressed != null && !loading;
    final baseRadius =
        borderRadius ??
        BorderRadius.circular(
          size == DButtonSize.extraSmall || size == DButtonSize.small
              ? (tokens.radius * .8).clamp(
                  0,
                  size == DButtonSize.extraSmall ? 10 : 12,
                )
              : tokens.radius,
        );
    final direction = Directionality.of(context);
    final joined = DJoinedControlScope.maybeOf(context);
    final radius =
        joined?.resolveRadius(baseRadius, direction) ??
        baseRadius.resolve(direction);
    final animationDuration = DMotion.duration(
      context,
      const Duration(milliseconds: 150),
    );
    // dark:border-input is declared after focus-visible:border-ring in the
    // reference stylesheet, so a focused dark outline keeps its input border.
    final focusBorderColor = switch (variant) {
      DButtonVariant.destructive => _alpha(tokens.destructive, .4),
      DButtonVariant.outline when dark => null,
      _ => tokens.focusRing,
    };
    final destructiveRing = invalid || variant == DButtonVariant.destructive;
    final ringColor = destructiveRing
        ? _alpha(tokens.destructive, dark ? .4 : .2)
        : _alpha(tokens.focusRing, .5);

    DButtonStateStyle withBackground(
      DButtonStateStyle state, {
      bool interactive = false,
    }) {
      final background = interactive
          ? interactiveBackgroundColor ?? backgroundColor
          : backgroundColor;
      if (background == null) return state;
      return DButtonStateStyle(
        foregroundColor: state.foregroundColor,
        backgroundColor: background,
        iconColor: state.iconColor,
        border: state.border,
      );
    }

    DButtonStateStyle resolveState(Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return withBackground(variantStyle.enabled);
      }
      // Reference hover surfaces sit behind a (hover: hover) media query, so
      // a touch press only translates. Compatibility variants keep their
      // pressed fill as touch feedback.
      final interactive =
          states.contains(WidgetState.hovered) ||
          (!reference && states.contains(WidgetState.pressed));
      // aria-expanded:bg-secondary is declared after the secondary hover mix,
      // so an open secondary trigger keeps its expanded surface while hovered.
      if (expanded && (!interactive || variant == DButtonVariant.secondary)) {
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
        _iconOnly
            ? Size.square(iconOnlySurfaceDimension)
            : Size(0, visualDimension),
      ),
      fixedSize: _iconOnly
          ? WidgetStatePropertyAll(Size.square(iconOnlySurfaceDimension))
          : null,
      maximumSize: _iconOnly
          ? WidgetStatePropertyAll(Size.square(iconOnlySurfaceDimension))
          : const WidgetStatePropertyAll(Size.infinite),
      padding: WidgetStatePropertyAll(
        padding ??
            (_iconOnly
                ? EdgeInsets.zero
                : EdgeInsetsDirectional.only(
                    start:
                        (icon != null || (loading && loadingLabel != null)) &&
                            iconPosition == DButtonIconPosition.start
                        ? (size == DButtonSize.extraSmall ||
                                  size == DButtonSize.small
                              ? 7
                              : 9)
                        : (size == DButtonSize.extraSmall ? 9 : 11),
                    end:
                        (icon != null || (loading && loadingLabel != null)) &&
                            iconPosition == DButtonIconPosition.end
                        ? (size == DButtonSize.extraSmall ||
                                  size == DButtonSize.small
                              ? 7
                              : 9)
                        : (size == DButtonSize.extraSmall ? 9 : 11),
                    top: 1,
                    bottom: 1,
                  )),
      ),
      textStyle: WidgetStateProperty.resolveWith(
        (states) => theme.textTheme.labelLarge!.copyWith(
          fontSize: fontSize,
          height: switch (size) {
            DButtonSize.extraSmall => 16 / fontSize,
            DButtonSize.small => 22.4 / fontSize,
            _ => 20 / fontSize,
          },
          fontWeight: FontWeight.w500,
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
      // transition and translate together; the Material stays transparent.
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      side: const WidgetStatePropertyAll(BorderSide.none),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: radius),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      animationDuration: animationDuration,
      visualDensity: insetIconSurface
          ? VisualDensity(
              // Density changes only the padded target, not the fixed surface.
              // Legacy compact desktop targets must not shrink touch bounds.
              horizontal: (iconTargetDimension - kMinInteractiveDimension) / 4,
              vertical: (iconTargetDimension - kMinInteractiveDimension) / 4,
            )
          : VisualDensity.standard,
      tapTargetSize: insetIconSurface || touch
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      mouseCursor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
      ),
      alignment: alignment,
      backgroundBuilder: (context, states, child) {
        final state = resolveState(states);
        final focused = states.contains(WidgetState.focused);
        final border = state.border;
        final resolvedBorderColor = invalid
            ? _alpha(tokens.destructive, dark ? .5 : 1)
            : borderColor ??
                  (focused && focusBorderColor != null
                      ? focusBorderColor
                      : border.style == BorderStyle.none || border.width == 0
                      ? Colors.transparent
                      : border.color);
        return AnimatedContainer(
          duration: animationDuration,
          curve: Curves.ease,
          transform: Matrix4.translationValues(
            0,
            states.contains(WidgetState.pressed) && !hasPopup ? 1 : 0,
            0,
          ),
          decoration: DButtonDecoration(
            color: state.backgroundColor,
            borderColor: resolvedBorderColor,
            borderRadius: radius,
            ringColor: ringColor,
            ringWidth: focused || invalid ? 3 : 0,
            joinedAxis: joined?.omitsLeadingBorder ?? false
                ? joined!.axis
                : null,
          ),
          child: child,
        );
      },
    );

    Widget child = _iconOnly
        ? ExcludeSemantics(child: icon!)
        : DefaultTextStyle.merge(
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            child: icon == null
                ? ExcludeSemantics(
                    excluding: semanticLabel != null,
                    child: label,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (iconPosition == DButtonIconPosition.start) ...[
                        ExcludeSemantics(child: icon!),
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
                        ExcludeSemantics(child: icon!),
                      ],
                    ],
                  ),
          );
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
        shortcut: shortcut,
        excludeFromSemantics: effectiveSemanticLabel != null,
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

/// The painted button surface: a fill clipped to the padding box, a 1px
/// border and an exterior focus or invalid ring.
///
/// Like base-nova's `border border-transparent bg-clip-padding`, the fill
/// stops at the border, so a transparent border leaves a one-pixel frame
/// rather than showing the fill through it. [joinedAxis] names the axis along
/// which the leading edge is shared with a preceding control: that edge has no
/// border and the fill reaches it. The ring is painted outside the bounds.
@immutable
class DButtonDecoration extends Decoration {
  const DButtonDecoration({
    required this.color,
    required this.borderColor,
    required this.borderRadius,
    this.ringColor = const Color(0x00000000),
    this.ringWidth = 0,
    this.joinedAxis,
  }) : assert(ringWidth >= 0);

  static const double borderWidth = 1;

  final Color color;
  final Color borderColor;
  final BorderRadius borderRadius;
  final Color ringColor;
  final double ringWidth;
  final Axis? joinedAxis;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DButtonPainter(this);

  @override
  Decoration? lerpFrom(Decoration? a, double t) => a is DButtonDecoration
      ? DButtonDecoration(
          color: Color.lerp(a.color, color, t)!,
          borderColor: Color.lerp(a.borderColor, borderColor, t)!,
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
          ringColor: Color.lerp(a.ringColor, ringColor, t)!,
          ringWidth: lerpDouble(a.ringWidth, ringWidth, t)!,
          joinedAxis: t < .5 ? a.joinedAxis : joinedAxis,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is DButtonDecoration ? b.lerpFrom(this, t) : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is DButtonDecoration &&
      other.color == color &&
      other.borderColor == borderColor &&
      other.borderRadius == borderRadius &&
      other.ringColor == ringColor &&
      other.ringWidth == ringWidth &&
      other.joinedAxis == joinedAxis;

  @override
  int get hashCode => Object.hash(
    color,
    borderColor,
    borderRadius,
    ringColor,
    ringWidth,
    joinedAxis,
  );
}

class _DButtonPainter extends BoxPainter {
  const _DButtonPainter(this.decoration);

  final DButtonDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final outer = decoration.borderRadius.toRRect(rect);
    final direction = configuration.textDirection ?? TextDirection.ltr;
    final axis = decoration.joinedAxis;
    const width = DButtonDecoration.borderWidth;
    final sharesStart = axis == Axis.horizontal;
    final inner = RRect.fromRectAndCorners(
      Rect.fromLTRB(
        rect.left + (sharesStart && direction == TextDirection.ltr ? 0 : width),
        rect.top + (axis == Axis.vertical ? 0 : width),
        rect.right -
            (sharesStart && direction == TextDirection.rtl ? 0 : width),
        rect.bottom - width,
      ),
      topLeft: _shrink(outer.tlRadius, width),
      topRight: _shrink(outer.trRadius, width),
      bottomLeft: _shrink(outer.blRadius, width),
      bottomRight: _shrink(outer.brRadius, width),
    );
    if (decoration.ringWidth > 0 && decoration.ringColor.a > 0) {
      canvas.drawDRRect(
        outer.inflate(decoration.ringWidth),
        outer,
        Paint()..color = decoration.ringColor,
      );
    }
    if (decoration.borderColor.a > 0) {
      // The shared edge leaves the inner and outer paths touching, which an
      // even-odd path difference handles where drawDRRect is undefined.
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(outer)
          ..addRRect(inner),
        Paint()..color = decoration.borderColor,
      );
    }
    if (decoration.color.a > 0) {
      canvas.drawRRect(inner, Paint()..color = decoration.color);
    }
  }

  static Radius _shrink(Radius radius, double by) =>
      Radius.elliptical(math.max(0, radius.x - by), math.max(0, radius.y - by));
}

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
