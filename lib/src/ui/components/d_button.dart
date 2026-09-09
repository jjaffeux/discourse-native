import 'dart:ui' show lerpDouble;

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
  }) : focused = focused ?? interactive;

  final DButtonStateStyle enabled;
  final DButtonStateStyle interactive;
  final DButtonStateStyle focused;

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
  );
}

@immutable
class DiscourseButtonTheme extends ThemeExtension<DiscourseButtonTheme> {
  const DiscourseButtonTheme({
    required this.borderRadius,
    required this.focusRingColor,
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
  final Color focusRingColor;
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
      focusRingColor: colors.primary,
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
    Color? focusRingColor,
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
    focusRingColor: focusRingColor ?? this.focusRingColor,
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
      focusRingColor: Color.lerp(focusRingColor, other.focusRingColor, t)!,
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

  /// Expanded popup triggers retain their active surface.
  final bool expanded;

  /// Validation styling for a form or popup trigger.
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
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;
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
      Color foreground, [
      Color? border,
    ]) => DButtonVariantStyle(
      enabled: state(background, foreground, border),
      interactive: state(hover, foreground, border),
      focused: state(background, foreground, border),
    );
    return switch (variant) {
      DButtonVariant.primary => pair(
        tokens.primary,
        tokens.primary.withValues(alpha: tokens.primary.a * .8),
        tokens.primaryForeground,
      ),
      DButtonVariant.outline => pair(
        dark
            ? tokens.colors.outlineVariant.withValues(
                alpha: tokens.colors.outlineVariant.a * .3,
              )
            : tokens.background,
        dark
            ? tokens.colors.outlineVariant.withValues(
                alpha: tokens.colors.outlineVariant.a * .5,
              )
            : tokens.muted,
        tokens.foreground,
        dark ? tokens.colors.outlineVariant : tokens.border,
      ),
      DButtonVariant.secondary => pair(
        tokens.muted,
        Color.lerp(tokens.muted, tokens.foreground, .05)!,
        tokens.foreground,
      ),
      DButtonVariant.ghost => pair(
        Colors.transparent,
        tokens.muted.withValues(alpha: tokens.muted.a * (dark ? .5 : 1)),
        tokens.foreground,
      ),
      DButtonVariant.destructive => pair(
        tokens.destructive.withValues(
          alpha: tokens.destructive.a * (dark ? .2 : .1),
        ),
        tokens.destructive.withValues(
          alpha: tokens.destructive.a * (dark ? .3 : .2),
        ),
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

  @override
  Widget build(BuildContext context) {
    final effectiveSemanticLabel =
        semanticLabel ?? (_iconOnly ? tooltip : null);
    final theme = Theme.of(context);
    final buttons = theme.discourseButtons;
    final tokens = DTokens.of(context);
    final dark = theme.brightness == Brightness.dark;
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

    DButtonStateStyle withInteractiveBackground(DButtonStateStyle state) {
      final background = interactiveBackgroundColor;
      if (background == null) return state;
      return DButtonStateStyle(
        foregroundColor: state.foregroundColor,
        backgroundColor: background,
        iconColor: state.iconColor,
        border: state.border,
      );
    }

    DButtonStateStyle resolveState(Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) return variantStyle.enabled;
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered)) {
        return withInteractiveBackground(variantStyle.interactive);
      }
      if (states.contains(WidgetState.focused)) {
        return withInteractiveBackground(variantStyle.focused);
      }
      if (expanded &&
          (variant == DButtonVariant.outline ||
              variant == DButtonVariant.secondary ||
              variant == DButtonVariant.ghost)) {
        return variantStyle.interactive;
      }
      return variantStyle.enabled;
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
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => resolveState(states).backgroundColor,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => invalid
            ? BorderSide(
                color: tokens.destructive.withValues(alpha: dark ? .5 : 1),
              )
            : states.contains(WidgetState.focused)
            ? BorderSide(
                color: variant == DButtonVariant.destructive
                    ? tokens.destructive.withValues(alpha: .4)
                    : tokens.focusRing,
              )
            : resolveState(states).border,
      ),
      shape: WidgetStatePropertyAll(
        joined?.omitsLeadingBorder ?? false
            ? _DButtonBorder(
                borderRadius: radius,
                joinedAxis: joined?.axis,
                omitLeadingBorder: true,
              )
            : RoundedRectangleBorder(borderRadius: radius),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      animationDuration: DMotion.duration(
        context,
        const Duration(milliseconds: 150),
      ),
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
      mouseCursor: WidgetStateMouseCursor.clickable,
      alignment: alignment,
      backgroundBuilder: (context, states, child) {
        final focused = states.contains(WidgetState.focused);
        Widget result = child!;
        if (focused || invalid) {
          final destructive = invalid || variant == DButtonVariant.destructive;
          final color = destructive ? tokens.destructive : tokens.focusRing;
          result = DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: color.withValues(
                  alpha: destructive ? (dark ? .4 : .2) : .5,
                ),
                width: 3,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: result,
          );
        }
        return Transform.translate(
          offset: Offset(
            0,
            states.contains(WidgetState.pressed) && !hasPopup ? 1 : 0,
          ),
          child: result,
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
      final indicator = DSpinner(size: spacingUnit, semanticLabel: null);
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

    Widget result = isLink
        ? _DLinkPrimitive(
            onPressed: enabled ? onPressed : null,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: joined == null ? null : Clip.none,
            child: child,
          )
        : FilledButton(
            onPressed: enabled ? onPressed : null,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: joined == null ? null : Clip.none,
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
        liveRegion: loading,
        label: effectiveSemanticLabel,
        value: loading ? loadingSemanticLabel : null,
        child: result,
      ),
    );
  }
}

/// A rounded button outline that can omit only the shared leading edge.
///
/// Material's regular `side` is uniform, while base-nova removes the second
/// control's leading border. Clipping that one painted edge avoids doubled
/// seams without changing hit testing, layout, or the control's outer edges.
class _DButtonBorder extends OutlinedBorder {
  const _DButtonBorder({
    required this.borderRadius,
    required this.joinedAxis,
    required this.omitLeadingBorder,
    super.side,
  });

  final BorderRadius borderRadius;
  final Axis? joinedAxis;
  final bool omitLeadingBorder;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  _DButtonBorder copyWith({BorderSide? side}) => _DButtonBorder(
    borderRadius: borderRadius,
    joinedAxis: joinedAxis,
    omitLeadingBorder: omitLeadingBorder,
    side: side ?? this.side,
  );

  @override
  ShapeBorder scale(double t) => _DButtonBorder(
    borderRadius: borderRadius * t,
    joinedAxis: joinedAxis,
    omitLeadingBorder: omitLeadingBorder,
    side: side.scale(t),
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect).deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final inset = side.strokeInset;
    final outline = borderRadius.toRRect(rect).deflate(inset);
    if (!omitLeadingBorder || joinedAxis == null) {
      canvas.drawRRect(outline, side.toPaint());
      return;
    }
    final edge = side.width + 0.01;
    final direction = textDirection ?? TextDirection.ltr;
    final clip = switch (joinedAxis!) {
      Axis.vertical => Rect.fromLTRB(
        rect.left - side.width,
        rect.top + edge,
        rect.right + side.width,
        rect.bottom + side.width,
      ),
      Axis.horizontal when direction == TextDirection.rtl => Rect.fromLTRB(
        rect.left - side.width,
        rect.top - side.width,
        rect.right - edge,
        rect.bottom + side.width,
      ),
      Axis.horizontal => Rect.fromLTRB(
        rect.left + edge,
        rect.top - side.width,
        rect.right + side.width,
        rect.bottom + side.width,
      ),
    };
    canvas
      ..save()
      ..clipRect(clip)
      ..drawRRect(outline, side.toPaint())
      ..restore();
  }

  @override
  bool operator ==(Object other) =>
      other is _DButtonBorder &&
      other.borderRadius == borderRadius &&
      other.joinedAxis == joinedAxis &&
      other.omitLeadingBorder == omitLeadingBorder &&
      other.side == side;

  @override
  int get hashCode =>
      Object.hash(borderRadius, joinedAxis, omitLeadingBorder, side);
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
