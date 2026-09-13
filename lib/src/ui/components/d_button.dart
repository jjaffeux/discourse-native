import 'dart:ui' show SemanticsValidationResult, lerpDouble;

import 'package:flutter/material.dart';

import '../foundation/control_style.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';
import 'd_kbd.dart';
import 'd_spinner.dart';
import 'd_tooltip.dart';

/// The six reference variants are the application styling contract.
/// Legacy names remain source-compatible aliases for external plugin callers.
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

typedef DButtonSize = DControlSize;

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
/// the shared Native sizes; touch platforms expand their invisible targets to 48px.
/// The painted surface is a [DButtonDecoration]: hover, expanded, focus,
/// invalid and pressed changes transition together over 150ms. Hover exit
/// clears immediately to avoid overlapping highlights on neighboring buttons.
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
    required this.onPressed,
    this.variant = DButtonVariant.primary,
    this.size = DButtonSize.regular,
    this.loading = false,
    this.loadingSemanticLabel = 'Loading',
    this.shortcut,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.alignment = Alignment.center,
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

  /// Popup triggers do not translate down when pressed.
  final bool hasPopup;

  /// Gives navigation callbacks a link role while retaining button styling.
  /// The application owns route or URL opening; no networking is performed.
  final bool isLink;
  final DButtonVariant variant;
  final DButtonSize size;

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

  final BorderRadiusGeometry? borderRadius;

  /// Overrides the variant's fill in every state, including expanded and
  /// disabled. [interactiveBackgroundColor] takes precedence while hovered
  /// or focused. Use [foregroundColor] to override the variant's label and icon.
  final Color? backgroundColor;

  /// Overrides label and icon color together, including disabled states.
  /// The focus ring retains its separate themed color.
  final Color? foregroundColor;

  /// Overrides the 1px border in every state except [invalid]. The themed focus
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
    final input = DControlStyle.outlineBorder(tokens, dark: dark);
    return switch (_visualVariant) {
      DButtonVariant.primary => pair(
        tokens.controls?.primary.background ?? tokens.primary,
        tokens.controls?.primary.hover ?? _alpha(tokens.primary, .8),
        tokens.controls?.primary.foreground ?? tokens.primaryForeground,
      ),
      // The uncustomized dark reference keeps its resting fill when expanded.
      DButtonVariant.outline when dark => pair(
        DControlStyle.outlineFill(tokens, dark: true),
        DControlStyle.outlineFill(tokens, dark: true, hovered: true),
        tokens.controls?.outline.foreground ?? tokens.foreground,
        border: input,
        expanded: tokens.controls?.outline.hover,
      ),
      DButtonVariant.outline => pair(
        DControlStyle.outlineFill(tokens, dark: false),
        DControlStyle.outlineFill(tokens, dark: false, hovered: true),
        tokens.controls?.outline.foreground ?? tokens.foreground,
        border: input,
        expanded: tokens.controls?.outline.hover ?? tokens.muted,
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
    final fontSize = fontSizeFor(size);
    final spacingUnit = DControlStyle.iconDimension(size);
    final gap = DControlStyle.contentGap(size);
    final visualDimension = DControlStyle.scaledHeight(
      size,
      MediaQuery.textScalerOf(context),
    );
    final touch =
        theme.platform == TargetPlatform.iOS ||
        theme.platform == TargetPlatform.android;
    final iconOnlySurfaceDimension = visualDimension;
    final enabled = onPressed != null && !loading;
    final baseRadius =
        borderRadius ??
        BorderRadius.circular(DControlStyle.radius(tokens, size));
    final direction = Directionality.of(context);
    final joined = DJoinedControlScope.maybeOf(context);
    final radius =
        joined?.resolveRadius(baseRadius, direction) ??
        baseRadius.resolve(direction);
    final animationDuration = DMotion.duration(context, DControlStyle.duration);
    // dark:border-input is declared after focus-visible:border-ring in the
    // reference stylesheet, so a focused dark outline keeps its input border.
    final focusBorderColor = switch (_visualVariant) {
      DButtonVariant.destructive => _alpha(tokens.destructive, .4),
      DButtonVariant.outline when dark => null,
      _ => tokens.focusRing,
    };
    final destructiveRing =
        invalid || _visualVariant == DButtonVariant.destructive;
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
      if (background == null && foregroundColor == null) return state;
      return DButtonStateStyle(
        foregroundColor: foregroundColor ?? state.foregroundColor,
        backgroundColor: background ?? state.backgroundColor,
        iconColor: foregroundColor ?? state.iconColor,
        border: state.border,
      );
    }

    DButtonStateStyle resolveState(Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return withBackground(variantStyle.enabled);
      }
      // Reference hover surfaces sit behind a (hover: hover) media query, so
      // a touch press only translates. Legacy names resolve to the same
      // reference surfaces and interaction states.
      final interactive = states.contains(WidgetState.hovered);
      // aria-expanded:bg-secondary is declared after the secondary hover mix,
      // so an open secondary trigger keeps its expanded surface while hovered.
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
        (_iconOnly
            ? EdgeInsets.zero
            : EdgeInsetsDirectional.only(
                start:
                    (icon != null || (loading && loadingLabel != null)) &&
                        iconPosition == DButtonIconPosition.start
                    ? (size == DButtonSize.large ? 9 : 7)
                    : (size == DButtonSize.small ? 9 : 11),
                end:
                    (icon != null || (loading && loadingLabel != null)) &&
                        iconPosition == DButtonIconPosition.end
                    ? (size == DButtonSize.large ? 9 : 7)
                    : (size == DButtonSize.small ? 9 : 11),
                top: 1,
                bottom: 1,
              )),
      ),
      textStyle: WidgetStateProperty.resolveWith(
        (states) => theme.textTheme.labelLarge!.copyWith(
          fontSize: fontSize,
          height: DControlStyle.lineHeight(size) / fontSize,
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
      visualDensity: VisualDensity.standard,
      tapTargetSize: touch
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
        final focused =
            states.contains(WidgetState.focused) &&
            DFocusHighlight.visibleOf(context);
        final border = state.border;
        final resolvedBorderColor = invalid
            ? _alpha(tokens.destructive, dark ? .5 : 1)
            : borderColor ??
                  (focused && focusBorderColor != null
                      ? focusBorderColor
                      : border.style == BorderStyle.none || border.width == 0
                      ? Colors.transparent
                      : border.color);
        return _DButtonSurface(
          duration: animationDuration,
          hovered: states.contains(WidgetState.hovered),
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

// Clear an exited hover immediately so adjacent controls never retain a trail
// of highlights. Other state changes keep the shared control transition.
class _DButtonSurface extends StatefulWidget {
  const _DButtonSurface({
    required this.duration,
    required this.hovered,
    required this.transform,
    required this.decoration,
    required this.child,
  });

  final Duration duration;
  final bool hovered;
  final Matrix4 transform;
  final DButtonDecoration decoration;
  final Widget? child;

  @override
  State<_DButtonSurface> createState() => _DButtonSurfaceState();
}

class _DButtonSurfaceState extends State<_DButtonSurface> {
  bool _exitedHover = false;

  @override
  void didUpdateWidget(_DButtonSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _exitedHover = oldWidget.hovered && !widget.hovered;
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: _exitedHover ? Duration.zero : widget.duration,
    curve: Curves.ease,
    transform: widget.transform,
    decoration: widget.decoration,
    child: widget.child,
  );
}

/// The painted button surface: a fill clipped to the padding box, a 1px
/// border and an exterior focus or invalid ring.
///
/// Like base-nova's `border border-transparent bg-clip-padding`, the fill
/// stops at the border, so a transparent border leaves a one-pixel frame
/// rather than showing the fill through it. [joinedAxis] names the axis along
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
