import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'd_tooltip.dart';
import 'discourse_typography.dart';

enum DButtonVariant {
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

enum DButtonSize { small, regular, large }

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
    this.disabledOpacity = 0.4,
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
      transparent: transparent(colors.onSurface),
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

class DButton extends StatelessWidget {
  const DButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = DButtonVariant.standard,
    this.size = DButtonSize.regular,
    this.loading = false,
    this.loadingLabel,
    this.tooltip,
    this.shortcut,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.interactiveBackgroundColor,
  }) : _iconOnly = false;

  const DButton.iconOnly({
    super.key,
    required Widget icon,
    required String tooltip,
    required this.onPressed,
    this.variant = DButtonVariant.standard,
    this.size = DButtonSize.regular,
    this.loading = false,
    this.shortcut,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.interactiveBackgroundColor,
  }) : label = const SizedBox.shrink(),
       loadingLabel = null,
       // ignore: prefer_initializing_formals
       icon = icon,
       // ignore: prefer_initializing_formals
       tooltip = tooltip,
       _iconOnly = true;

  final Widget label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final DButtonVariant variant;
  final DButtonSize size;
  final bool loading;
  final Widget? loadingLabel;
  final String? tooltip;
  final DShortcut? shortcut;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final AlignmentGeometry alignment;
  final BorderRadiusGeometry? borderRadius;
  final Color? interactiveBackgroundColor;
  final bool _iconOnly;

  static const double minimumDimension = 48;
  static const double _borderWidth = 1;
  static const double _textLineHeight = 1.2;

  static double fontSizeFor(DButtonSize size) => switch (size) {
    DButtonSize.small => DiscourseTypography.fontDown1,
    DButtonSize.regular => DiscourseTypography.base,
    DButtonSize.large => DiscourseTypography.fontUp1,
  };

  static double iconOnlyDimensionFor(DButtonSize size) => switch (size) {
    DButtonSize.small => 40,
    DButtonSize.regular => minimumDimension,
    DButtonSize.large => 56,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttons = theme.discourseButtons;
    final variantStyle = buttons.styleFor(variant);
    final fontSize = fontSizeFor(size);
    final iconOnlyDimension = iconOnlyDimensionFor(size);
    final enabled = onPressed != null && !loading;
    final radius = borderRadius ?? BorderRadius.circular(buttons.borderRadius);

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
      return variantStyle.enabled;
    }

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        _iconOnly ? Size.square(iconOnlyDimension) : Size.zero,
      ),
      fixedSize: _iconOnly
          ? WidgetStatePropertyAll(Size.square(iconOnlyDimension))
          : null,
      maximumSize: _iconOnly
          ? WidgetStatePropertyAll(Size.square(iconOnlyDimension))
          : const WidgetStatePropertyAll(Size.infinite),
      padding: WidgetStatePropertyAll(
        _iconOnly
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
                // Core uses border-box sizing with 1px borders around its
                // 0.5em/0.65em padding. Flutter paints borders inside the
                // layout box, so include that space in the padding here.
                horizontal: fontSize * 0.65 + _borderWidth,
                vertical: fontSize * 0.5 + _borderWidth,
              ),
      ),
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.normal,
          height: _textLineHeight,
        ),
      ),
      iconSize: WidgetStatePropertyAll(fontSize),
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
        (states) => resolveState(states).border,
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: radius),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      animationDuration: Duration.zero,
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      mouseCursor: WidgetStateMouseCursor.clickable,
      alignment: alignment,
      backgroundBuilder: (context, states, child) {
        if (!states.contains(WidgetState.focused)) return child!;
        return DecoratedBox(
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: buttons.focusRingColor, width: 2),
            ),
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
                      ExcludeSemantics(child: icon!),
                      SizedBox(width: fontSize * 0.45),
                      Flexible(
                        child: ExcludeSemantics(
                          excluding: semanticLabel != null,
                          child: label,
                        ),
                      ),
                    ],
                  ),
          );
    if (loading) {
      final indicator = ExcludeSemantics(
        child: SizedBox.square(
          dimension: fontSize,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
      child = loadingLabel == null
          ? indicator
          : DefaultTextStyle.merge(
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  indicator,
                  SizedBox(width: fontSize * 0.45),
                  Flexible(
                    child: ExcludeSemantics(
                      excluding: semanticLabel != null,
                      child: loadingLabel!,
                    ),
                  ),
                ],
              ),
            );
    }

    Widget result = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      child: child,
    );
    if (onPressed == null && !loading) {
      result = Opacity(opacity: buttons.disabledOpacity, child: result);
    }
    if (tooltip case final tooltip?) {
      result = DTooltip(
        message: tooltip,
        shortcut: shortcut,
        excludeFromSemantics: semanticLabel != null,
        child: result,
      );
    }

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        liveRegion: loading,
        label: semanticLabel,
        value: loading ? 'Loading' : null,
        child: result,
      ),
    );
  }
}
