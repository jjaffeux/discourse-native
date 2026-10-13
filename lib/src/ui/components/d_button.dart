import 'dart:ui' show SemanticsValidationResult, lerpDouble;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../foundation/control_artwork.dart';
import '../foundation/control_style.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/joined_control.dart';
import '../foundation/material_surface.dart';
import '../foundation/material_theme.dart';
import '../foundation/post_action_surface.dart';
import '../foundation/post_reaction_style.dart';
import '../foundation/tokens.dart';
import 'd_avatar.dart';
import 'd_kbd.dart';
import 'd_spinner.dart';
import 'd_tooltip.dart';

/// Native button styles used by the application.
enum DButtonVariant {
  outline,

  /// Inset secondary action with a dark well and no outer shadow. Used by
  /// the workspace tab list; size and shape remain independent.
  recessed,

  /// Creation tile with a dashed frame and framed leading icon. Give it a
  /// tight width constraint when the whole row should activate the action.
  dashedTile,

  /// Square, transparent destination with an accent icon above its label.
  /// The kit owns its artwork, scaling, interaction fill and exact hit bounds.
  launcher,
  secondary,
  ghost,

  /// Clear at rest, with a subdued foreground and a neutral interaction fill.

  /// Transparent text action with no horizontal inset, for inline metadata.
  /// Retains the shared control height, keyboard focus and touch target.
  inline,
  destructive,
  primary,
  link,

  /// A compact resume card with an accent icon tile, title, description and
  /// passive trailing artwork. Give it a bounded width. Existing variants keep
  /// their own geometry.
  resume,
}

typedef DButtonSize = DControlSize;

/// Icon placement follows the ambient reading direction.
enum DButtonIconPosition { start, end }

/// Pill also produces a circular surface for icon-only buttons.
enum DButtonShape { rounded, pill }

/// Named artwork presets with shared styling and accessible touch targets.
enum DButtonDensity {
  standard,

  /// Flat 30px post-reaction pills and circular picker actions.
  postReaction,

  /// Bare 30px post actions: 13px icons, 8px corners and in-bounds hover sheen.
  postAction,

  /// Compact header shortcuts: 28px high, 32px icon-only targets, 12.5px
  /// count labels, 8px content gaps and 10px horizontal label insets.
  /// Geometry grows with text; popup, hover and focus use the chosen variant.
  header,

  /// A 36px circular profile trigger with a 2px border against its avatar.
  /// Use an icon-only button with a borderless DAvatar. The image fills the
  /// interior; artwork and hit bounds grow with text.
  avatar,

  /// Text-sized 12px metadata actions and links with no visible insets.
  /// Pair with the inline variant; targets exactly follow the label bounds.
  inlineMetadata,

  /// Hierarchical back link: 13px medium text, an 11px chevron and no insets.
  /// Pair with [DButtonVariant.inline]; the hit area follows the label.
  backLink,

  /// A 46px labelled mobile dock item with a 20px icon and one button target.
  /// The caller supplies the icon capsule and label within the Native kit.
  mobileDock,

  /// The primary action beside a mobile dock: a 44px pill with a 20px icon
  /// matching the dock's artwork. Icon-only, its square bounds keep the pill
  /// circular, with the hit area matching the visible surface.
  mobileDockAction,

  /// Inset window actions: 32 by 28px, 15px icons and a flat hover tint.
  /// Pair with a small capsule DCard. The visible bounds are the hit bounds.
  chrome,

  /// A chrome dropdown glyph drawn 1.5px towards its preceding divider.
  /// The 32 by 28px surface grows with text, retaining matching hit bounds.
  chromeDropdown,

  /// Narrow desktop block actions, retaining regular icons and height.
  composerBlock,

  /// Chat message actions: 26px artwork, 11px icon and 6px corners.
  chatMessageAction,

  /// Bare 12px search-clear glyph with matching bounds, scaling with text.
  searchClear,
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
}

/// Shared button geometry and disabled opacity.
@immutable
class DiscourseButtonTheme extends ThemeExtension<DiscourseButtonTheme> {
  const DiscourseButtonTheme({
    required this.borderRadius,
    this.disabledOpacity = 0.6,
  });
  final double borderRadius;
  final double disabledOpacity;
  @override
  DiscourseButtonTheme copyWith({
    double? borderRadius,
    double? disabledOpacity,
  }) => DiscourseButtonTheme(
    borderRadius: borderRadius ?? this.borderRadius,
    disabledOpacity: disabledOpacity ?? this.disabledOpacity,
  );
  @override
  DiscourseButtonTheme lerp(covariant DiscourseButtonTheme? other, double t) =>
      other == null
      ? this
      : DiscourseButtonTheme(
          borderRadius: lerpDouble(borderRadius, other.borderRadius, t)!,
          disabledOpacity: lerpDouble(
            disabledOpacity,
            other.disabledOpacity,
            t,
          )!,
        );
}

extension DiscourseButtonThemeAccess on ThemeData {
  DiscourseButtonTheme get discourseButtons =>
      extension<DiscourseButtonTheme>() ??
      const DiscourseButtonTheme(borderRadius: DRadius.control);
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
    this.description,
    this.trailing,
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
       description = null,
       trailing = null,
       loadingLabel = null,
       // ignore: prefer_initializing_formals
       icon = icon,
       // ignore: prefer_initializing_formals
       tooltip = tooltip,
       _iconOnly = true;

  final Widget label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Secondary text for the opt-in [DButtonVariant.resume] card.
  final Widget? description;

  /// Passive restore artwork for [DButtonVariant.resume], never another target.
  final Widget? trailing;
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

  /// Two text lines and visible insets, growing with the user's text size.
  static double resumeHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return (17 + scaler.scale(13.5) * 18 / 13.5 + scaler.scale(12) * 16 / 12)
        .clamp(52, double.infinity);
  }

  /// Width reserved by compact composer actions; touch keeps regular geometry.
  static double composerBlockWidth(BuildContext context) {
    final height = DControlStyle.scaledHeight(
      DButtonSize.regular,
      MediaQuery.textScalerOf(context),
      context: context,
    );
    return DControlStyle.isTouch(context) ? height : height * 20 / 34;
  }

  /// Minimum square cell for launcher grids, growing with the label's text.
  static double launcherMinimumExtent(BuildContext context) =>
      112 + (MediaQuery.textScalerOf(context).scale(13) - 13) * 3;

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
    return switch (variant) {
      DButtonVariant.launcher => DButtonVariantStyle(
        enabled: state(Colors.transparent, tokens.foreground),
        interactive: state(
          (dark ? Colors.white : Colors.black).withValues(
            alpha: dark ? .055 : .045,
          ),
          tokens.foreground,
        ),
        focused: state(
          (dark ? Colors.white : Colors.black).withValues(
            alpha: dark ? .055 : .045,
          ),
          tokens.foreground,
        ),
      ),
      DButtonVariant.recessed => pair(
        Colors.black.withValues(alpha: dark ? .16 : .045),
        (dark ? Colors.white : Colors.black).withValues(
          alpha: dark ? .05 : .07,
        ),
        buttons.outline.foreground,
      ),
      DButtonVariant.resume => pair(
        buttons.outline.background,
        buttons.outline.background,
        tokens.foreground,
        border: Color.lerp(tokens.background, tokens.foreground, .12),
      ),
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
      DButtonVariant.ghost => DButtonVariantStyle(
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
    final postAction = density == DButtonDensity.postAction;
    final glass = DMaterialTheme.glassOf(context);
    final postReaction = density == DButtonDensity.postReaction;
    final chrome =
        density == DButtonDensity.chrome ||
        density == DButtonDensity.chromeDropdown;
    final primaryChrome = chrome && variant == DButtonVariant.primary;
    final expandedChrome =
        primaryChrome && expanded && onPressed != null && !loading;
    final header = density == DButtonDensity.header;
    final variantStyle = _referenceStyle(tokens, dark);

    final mobileDock = density == DButtonDensity.mobileDock;
    final mobileDockAction = density == DButtonDensity.mobileDockAction;

    final chatMessageAction = density == DButtonDensity.chatMessageAction;
    final backLink = density == DButtonDensity.backLink;
    final inlineMetadata = density == DButtonDensity.inlineMetadata;
    final searchClear = density == DButtonDensity.searchClear;
    final avatar = density == DButtonDensity.avatar;
    final dashedTile = variant == DButtonVariant.dashedTile;
    final resume = variant == DButtonVariant.resume;
    final launcher = variant == DButtonVariant.launcher;
    final intrinsicIcon =
        _iconOnly &&
        (size == DControlSize.chip || size == DControlSize.chrome) &&
        density == DButtonDensity.standard;
    final composerBlock = _iconOnly && density == DButtonDensity.composerBlock;
    final effectiveSize = postReaction || postAction
        ? DButtonSize.post
        : backLink
        ? DButtonSize.toolbar
        : ((avatar) || mobileDock || mobileDockAction || composerBlock
              ? DButtonSize.regular
              : size);
    final fontSize = postReaction
        ? DPostReactionStyle.fontSize
        : header
        ? 12.5
        : launcher
        ? 13.0
        : chrome && !_iconOnly
        ? 12.5
        : inlineMetadata
        ? 12.0
        : dashedTile
        ? DControlStyle.fontSize(DButtonSize.large, context: context)
        : DControlStyle.fontSize(effectiveSize, context: context);
    // Both dock densities scale artwork with the 11px destination labels.
    final spacingUnit = postReaction
        ? DPostReactionStyle.iconSize
        : header
        ? 16.0
        : chrome
        ? 15.0
        : backLink
        ? 11.0
        : mobileDock || mobileDockAction
        ? 20.0 + MediaQuery.textScalerOf(context).scale(11) - 11
        : (chatMessageAction
              ? 16.0
              : (DControlStyle.iconDimension(effectiveSize, context: context)));
    final gap = postReaction
        ? DPostReactionStyle.gap
        : header
        ? 8.0
        : dashedTile
        ? 12.0
        : chrome
        ? 8.0
        : DControlStyle.contentGap(effectiveSize);
    final standardDimension =
        DControlStyle.scaledHeight(
          effectiveSize,
          MediaQuery.textScalerOf(context),
          context: (context),
        ).clamp(
          mobileDock
              ? 46.0
              : (mobileDockAction)
              ? 44.0
              : 0.0,
          double.infinity,
        );
    final visualDimension = postReaction
        ? DPostReactionStyle.height(MediaQuery.textScalerOf(context))
        : header
        ? 28 +
              (MediaQuery.textScalerOf(context).scale(fontSize) - fontSize) *
                  1.5
        : launcher
        ? launcherMinimumExtent(context)
        : resume
        ? resumeHeight(context)
        : chrome
        ? DControlStyle.scaledHeight(
            DControlSize.segment,
            MediaQuery.textScalerOf(context),
            context: context,
          )
        : searchClear
        ? MediaQuery.textScalerOf(context).scale(12)
        : avatar
        ? 36.0 *
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
          resume || launcher
              ? 16
              : postAction
              ? 8
              : postReaction ||
                    chrome ||
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
    final surfaceWidth = header || chrome
        ? visualDimension + 4
        : composerBlock
        ? composerBlockWidth(context)
        : (effectiveSize == DControlSize.chip)
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
      DControlStyle.duration,
    );
    final destructiveRing = invalid || variant == DButtonVariant.destructive;
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
      if (postAction) {
        final interacting =
            !states.contains(WidgetState.disabled) &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        final foreground = Color.lerp(
          tokens.background,
          tokens.foreground,
          interacting || states.contains(WidgetState.focused) ? .62 : .32,
        )!;
        return DButtonStateStyle(
          foregroundColor: foreground,
          iconColor: foreground,
          backgroundColor: interacting
              ? glass
                    ? Color.lerp(
                        tokens.colors.surface,
                        tokens.foreground,
                        .10,
                      )!.withValues(alpha: .28)
                    : tokens.foreground.withValues(alpha: .08)
              : Colors.transparent,
          border: BorderSide.none,
        );
      }
      if (postReaction) {
        final interactive =
            !states.contains(WidgetState.disabled) &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        final foreground = DPostReactionStyle.foreground(tokens);
        return DButtonStateStyle(
          foregroundColor: foreground,
          iconColor: foreground,
          backgroundColor: DPostReactionStyle.fill(
            tokens,
            dark,
            interacting: interactive,
          ),
          border: BorderSide.none,
        );
      }
      if (chrome) {
        final interactive =
            !states.contains(WidgetState.disabled) &&
            (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed));
        final foreground =
            foregroundColor ??
            (primaryChrome
                ? tokens.buttonTheme.primary.foreground
                : tokens.mutedForeground);
        return DButtonStateStyle(
          foregroundColor: foreground,
          iconColor: foreground,
          backgroundColor: expandedChrome
              ? tokens.buttonTheme.primary.background
              : interactive
              ? (primaryChrome || dark ? Colors.white : Colors.black)
                    .withValues(alpha: primaryChrome ? .16 : (dark ? .09 : .06))
              : Colors.transparent,
          border: BorderSide.none,
        );
      }
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
        return variant == DButtonVariant.primary ||
                variant == DButtonVariant.destructive ||
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
        _iconOnly && !intrinsicIcon
            ? iconOnlySurfaceSize
            : Size(postReaction ? visualDimension : 0, surfaceHeight),
      ),
      fixedSize: _iconOnly && !intrinsicIcon
          ? WidgetStatePropertyAll(iconOnlySurfaceSize)
          : null,
      maximumSize: _iconOnly && !intrinsicIcon
          ? WidgetStatePropertyAll(iconOnlySurfaceSize)
          : const WidgetStatePropertyAll(Size.infinite),
      padding: WidgetStatePropertyAll(
        (header
            ? (_iconOnly
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 1))
            : postReaction
            ? (_iconOnly
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 10))
            : resume || launcher
            ? const EdgeInsets.all(8)
            : avatar
            ? const EdgeInsets.all(2)
            : density == DButtonDensity.chromeDropdown
            ? const EdgeInsetsDirectional.only(end: 3)
            : _iconOnly && !intrinsicIcon
            ? EdgeInsets.zero
            : chrome
            ? EdgeInsets.symmetric(
                horizontal: variant == DButtonVariant.primary ? 11 : 10,
              )
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
          height: postReaction || header || inlineMetadata
              ? 1.5
              : mobileDock
              ? 13 / 11
              : dashedTile
              ? DControlStyle.lineHeight(DButtonSize.large, context: context) /
                    fontSize
              : DControlStyle.lineHeight(effectiveSize, context: context) /
                    fontSize,
          fontWeight: postReaction
              ? FontWeight.w500
              : header
              ? FontWeight.w600
              : mobileDock || backLink
              ? FontWeight.w500
              : variant == DButtonVariant.primary || dashedTile || launcher
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
            // Launcher cells use a flat interaction tint in both materials.
            color: expandedChrome || (postAction && glass)
                ? Colors.transparent
                : postAction || postReaction || chrome || launcher
                ? state.backgroundColor
                : DMaterialSurface.fill(context, state.backgroundColor),
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
        final artwork = DControlArtwork(
          child: postAction
              ? DPostActionSurface(
                  radius: radius,
                  color: state.backgroundColor,
                  interacting:
                      enabled &&
                      (states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.pressed)),
                  child: surface,
                )
              : expandedChrome
              ? DMaterialSurface(
                  radius: radius,
                  color: state.backgroundColor,
                  depth: DSurfaceDepth.chromeSelection,
                  child: surface,
                )
              : postReaction || chrome || launcher
              ? surface
              : DMaterialSurface(
                  radius: radius,
                  color: state.backgroundColor,
                  depth: variant == DButtonVariant.recessed
                      ? DSurfaceDepth.recessed
                      : DSurfaceDepth.raised,
                  preserveColor: variant == DButtonVariant.recessed,
                  insetEdges: variant == DButtonVariant.recessed,
                  accented:
                      variant == DButtonVariant.primary ||
                      variant == DButtonVariant.destructive,
                  child: surface,
                ),
        );
        final result = joined == null
            ? artwork
            : DJoinedControlSurface(child: artwork);
        return resume
            ? _ResumeInteraction(
                active:
                    enabled &&
                    (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.pressed) ||
                        focused),
                child: result,
              )
            : result;
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
    Widget child = launcher && !_iconOnly
        ? ExcludeSemantics(
            excluding: semanticLabel != null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  DAvatar(
                    dimension: 52,
                    decorative: true,
                    border: false,
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: Color.alphaBlend(
                        tokens.primary.withValues(alpha: .2),
                        tokens.background,
                      ),
                      child: Center(
                        child: IconTheme.merge(
                          data: IconThemeData(size: 24, color: tokens.primary),
                          child: DIconGlyphTheme(scale: 1, child: icon!),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                DefaultTextStyle.merge(
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  child: label,
                ),
              ],
            ),
          )
        : resume && !_iconOnly
        ? ExcludeSemantics(
            excluding: semanticLabel != null,
            child: _ResumeContent(
              icon: icon,
              label: label,
              description: description,
              trailing: trailing,
            ),
          )
        : _iconOnly
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
    if (header ||
        chrome ||
        (mobileDock) ||
        mobileDockAction ||
        DControlStyle.isApplicationSize(effectiveSize)) {
      child = DIconGlyphTheme(
        scale: 1,
        naturalWidth:
            header || chrome || DControlStyle.isApplicationSize(effectiveSize),
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
        : postAction
        ? _DPostActionPrimitive(
            onPressed: enabled ? onPressed : null,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
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

    if (launcher) {
      final button = result;
      result = LayoutBuilder(
        builder: (context, constraints) {
          final extent = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : launcherMinimumExtent(context);
          return SizedBox.square(dimension: extent, child: button);
        },
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

class _ResumeInteraction extends InheritedWidget {
  const _ResumeInteraction({required this.active, required super.child});
  final bool active;

  @override
  bool updateShouldNotify(_ResumeInteraction oldWidget) =>
      active != oldWidget.active;
}

class _ResumeContent extends StatelessWidget {
  const _ResumeContent({
    required this.icon,
    required this.label,
    required this.description,
    required this.trailing,
  });

  final Widget? icon;
  final Widget label;
  final Widget? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final active =
        context
            .dependOnInheritedWidgetOfExactType<_ResumeInteraction>()
            ?.active ??
        false;
    final duration = DMotion.duration(
      context,
      const Duration(milliseconds: 150),
    );
    return Row(
      spacing: 12,
      children: [
        if (icon != null)
          ExcludeSemantics(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.buttonTheme.primary.background,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: DIconGlyphTheme(
                scale: 1,
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 14,
                    color: tokens.buttonTheme.primary.foreground,
                  ),
                  child: icon!,
                ),
              ),
            ),
          ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 13.5,
                  height: 18 / 13.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.foreground,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                child: label,
              ),
              if (description != null)
                DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w400,
                    color: tokens.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  child: description!,
                ),
            ],
          ),
        ),
        if (trailing != null)
          ExcludeSemantics(
            child: AnimatedContainer(
              duration: duration,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: active
                    ? tokens.primary.withValues(alpha: .12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(DRadius.pill),
              ),
              alignment: Alignment.center,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: active ? -2 : 0),
                duration: duration,
                builder: (context, rise, child) =>
                    Transform.translate(offset: Offset(0, rise), child: child),
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 18,
                    color: tokens.buttonTheme.accent.foreground,
                  ),
                  child: trailing!,
                ),
              ),
            ),
          ),
      ],
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

class _DPostActionPrimitive extends StatefulWidget {
  const _DPostActionPrimitive({
    required this.onPressed,
    required this.style,
    required this.focusNode,
    required this.autofocus,
    required this.child,
  });
  final VoidCallback? onPressed;
  final ButtonStyle style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget child;

  @override
  State<_DPostActionPrimitive> createState() => _DPostActionPrimitiveState();
}

class _DPostActionPrimitiveState extends State<_DPostActionPrimitive> {
  final _states = WidgetStatesController();
  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Set<WidgetState>>(
        valueListenable: _states,
        child: FilledButton(
          onPressed: widget.onPressed,
          style: widget.style,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          statesController: _states,
          clipBehavior: Clip.none,
          child: widget.child,
        ),
        builder: (context, states, child) {
          final pressed =
              widget.onPressed != null && states.contains(WidgetState.pressed);
          final glass = DMaterialTheme.glassOf(context);
          return AnimatedScale(
            scale: pressed ? .92 : 1,
            duration: DMotion.duration(
              context,
              Duration(milliseconds: pressed ? 80 : (glass ? 400 : 0)),
            ),
            curve: glass ? const Cubic(.34, 1.56, .64, 1) : Curves.ease,
            child: child,
          );
        },
      );
}
