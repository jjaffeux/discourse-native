import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// The three conversation marker layouts from shadcn Base UI.
enum DMarkerVariant { inline, border, separator }

/// Explicit action semantics. Navigation remains owned by the caller.
enum DMarkerAction { button, link }

/// A conversation note, status, action, or labeled boundary.
///
/// Presentational by default. [liveRegion] announces changing status text;
/// it does not invent a numeric progress value. Compose a decorative DSpinner
/// in [icon] for busy work. Editable state and Form ownership belong to callers.
/// Set [action] for an interactive marker; a null [onPressed] then disables it.
/// A supplied [focusNode] is borrowed and never disposed.
class DMarker extends StatefulWidget {
  const DMarker({
    super.key,
    required this.child,
    this.icon,
    this.variant = DMarkerVariant.inline,
    this.axis = Axis.horizontal,
    this.liveRegion = false,
    this.semanticLabel,
    this.action,
    this.onPressed,
    this.focusNode,
    this.color,
    this.borderColor,
  }) : assert(onPressed == null || action != null);

  final Widget child;
  final DMarkerIcon? icon;
  final DMarkerVariant variant;
  final Axis axis;
  final bool liveRegion;
  final String? semanticLabel;
  final DMarkerAction? action;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final Color? color;
  final Color? borderColor;

  @override
  State<DMarker> createState() => _DMarkerState();
}

class _DMarkerState extends State<DMarker> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final interactive = widget.action != null;
    final enabled = interactive && widget.onPressed != null;
    final separator = widget.variant == DMarkerVariant.separator;
    final color =
        widget.color ??
        (enabled && _hover ? tokens.foreground : tokens.mutedForeground);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: color,
      decoration: widget.action == DMarkerAction.link
          ? TextDecoration.underline
          : TextDecoration.none,
    );
    Widget content = DefaultTextStyle(
      style: style,
      textAlign: separator ? TextAlign.center : TextAlign.start,
      child: IconTheme.merge(
        data: IconThemeData(size: 16, color: color),
        child: widget.axis == Axis.vertical
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    widget.icon!,
                    const SizedBox(height: 8),
                  ],
                  widget.child,
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    widget.icon!,
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: widget.child),
                ],
              ),
      ),
    );
    final lineColor = widget.borderColor ?? tokens.border;
    if (separator) {
      final label = content;
      content = LayoutBuilder(
        builder: (context, constraints) {
          final gap = math.min(12.0, constraints.maxWidth / 2);
          return Row(
            children: [
              Expanded(
                child: ColoredBox(
                  color: lineColor,
                  child: const SizedBox(height: 1),
                ),
              ),
              SizedBox(width: gap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(0, constraints.maxWidth - gap * 2),
                ),
                child: IntrinsicWidth(child: label),
              ),
              SizedBox(width: gap),
              Expanded(
                child: ColoredBox(
                  color: lineColor,
                  child: const SizedBox(height: 1),
                ),
              ),
            ],
          );
        },
      );
    }
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    content = Container(
      constraints: BoxConstraints(minHeight: interactive && touch ? 48 : 16),
      width: double.infinity,
      padding: widget.variant == DMarkerVariant.border
          ? const EdgeInsets.only(bottom: 8)
          : null,
      decoration: widget.variant == DMarkerVariant.border
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: lineColor)),
            )
          : null,
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(
              border: Border.all(
                color: tokens.focusRing,
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            )
          : null,
      child: Align(
        heightFactor: 1,
        alignment: separator || widget.axis == Axis.vertical
            ? Alignment.center
            : AlignmentDirectional.centerStart,
        child: content,
      ),
    );
    if (interactive) {
      content = FocusableActionDetector(
        enabled: enabled,
        focusNode: widget.focusNode,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focus = value),
        onShowHoverHighlight: (value) => setState(() => _hover = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          child: content,
        ),
      );
    }
    return Semantics(
      container:
          interactive || widget.liveRegion || widget.semanticLabel != null,
      liveRegion: widget.liveRegion,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      button: widget.action == DMarkerAction.button,
      link: widget.action == DMarkerAction.link,
      enabled: interactive ? enabled : null,
      onTap: enabled ? widget.onPressed : null,
      child: content,
    );
  }
}

/// Decorative, non-interactive artwork. Adjacent content carries its meaning.
class DMarkerIcon extends StatelessWidget {
  const DMarkerIcon({super.key, required this.child, this.size = 16})
    : assert(size > 0 && size < double.infinity);
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ExcludeFocus(
      child: IgnorePointer(
        child: SizedBox.square(
          dimension: size,
          child: FittedBox(
            child: IconTheme.merge(
              data: IconThemeData(size: size),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Wrapping marker content with optional two-second streaming shimmer.
///
/// Motion pauses while inactive or ticker-disabled. Reduced motion paints plain
/// text. No external controller is retained; replacing the child preserves phase.
class DMarkerContent extends StatefulWidget {
  const DMarkerContent({super.key, required this.child, this.shimmer = false});
  final Widget child;
  final bool shimmer;

  @override
  State<DMarkerContent> createState() => _DMarkerContentState();
}

class _DMarkerContentState extends State<DMarkerContent>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  bool _active = true;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _active =
        binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _active = state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final animate =
        widget.shimmer &&
        !reduced &&
        _active &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_animation.isAnimating) _animation.repeat();
    if (!animate && _animation.isAnimating) _animation.stop();
    if (!widget.shimmer || reduced) return widget.child;
    final style = DefaultTextStyle.of(context).style;
    final base = style.color ?? DTokens.of(context).mutedForeground;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lab = _toOklab(base);
    final highlightAlpha = dark ? math.min(1.0, base.a + .4) : base.a * .2;
    final highlightLightness = dark ? math.max(.8, lab.$1 + .4) : lab.$1;
    final highlight = _fromOklab(
      highlightLightness,
      lab.$2,
      lab.$3,
      highlightAlpha,
    );
    // CSS color-mix premultiplies alpha in Oklab before mixing.
    final middleAlpha = (base.a + highlightAlpha) / 2;
    final middleLightness = middleAlpha == 0
        ? lab.$1
        : (lab.$1 * base.a + highlightLightness * highlightAlpha) /
              (base.a + highlightAlpha);
    final middle = _fromOklab(middleLightness, lab.$2, lab.$3, middleAlpha);
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final spread = 3 * painter.width + 40;
    painter.dispose();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          final phase = rtl ? 1 - _animation.value : _animation.value;
          final center = -spread + (bounds.width + 2 * spread) * phase;
          return LinearGradient(
            colors: [base, middle, highlight, middle, base],
            stops: const [0, .25, .5, .75, 1],
            transform: const GradientRotation(20 * math.pi / 180),
          ).createShader(
            Rect.fromLTWH(center - spread, 0, spread * 2, bounds.height),
          );
        },
        child: child,
      ),
    );
  }
}

// CSS shimmer derives its highlight in Oklch, preserving chroma and hue.
// Oklab is equivalent here because only lightness/alpha change.
(double, double, double) _toOklab(Color color) {
  double linear(double v) =>
      v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  double root(double v) => v.sign * math.pow(v.abs(), 1 / 3).toDouble();
  final r = linear(color.r), g = linear(color.g), b = linear(color.b);
  final l = root(.4122214708 * r + .5363325363 * g + .0514459929 * b);
  final m = root(.2119034982 * r + .6806995451 * g + .1073969566 * b);
  final s = root(.0883024619 * r + .2817188376 * g + .6299787005 * b);
  return (
    .2104542553 * l + .793617785 * m - .0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + .4505937099 * s,
    .0259040371 * l + .7827717662 * m - .808675766 * s,
  );
}

Color _fromOklab(double lightness, double a, double b, double alpha) {
  double cube(double v) => v * v * v;
  double gamma(double v) =>
      (v <= .0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - .055)
          .clamp(0.0, 1.0)
          .toDouble();
  final l = cube(lightness + .3963377774 * a + .2158037573 * b);
  final m = cube(lightness - .1055613458 * a - .0638541728 * b);
  final s = cube(lightness - .0894841775 * a - 1.291485548 * b);
  return Color.from(
    alpha: alpha,
    red: gamma(4.0767416621 * l - 3.3077115913 * m + .2309699292 * s),
    green: gamma(-1.2684380046 * l + 2.6097574011 * m - .3413193965 * s),
    blue: gamma(-.0041960863 * l - .7034186147 * m + 1.707614701 * s),
  );
}
