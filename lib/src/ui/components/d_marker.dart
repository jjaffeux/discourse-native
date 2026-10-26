import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/oklab.dart';
import '../foundation/tokens.dart';

/// The three conversation marker layouts from shadcn Base UI.
enum DMarkerVariant { inline, separator }

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

    this.borderColor,
  });

  final Widget child;
  final DMarkerIcon? icon;
  final DMarkerVariant variant;
  final Axis axis;
  final bool liveRegion;

  final Color? borderColor;

  @override
  State<DMarker> createState() => _DMarkerState();
}

class _DMarkerState extends State<DMarker> {
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);

    final separator = widget.variant == DMarkerVariant.separator;
    final color = tokens.mutedForeground;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: color,
      decoration: TextDecoration.none,
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
    content = Container(
      constraints: const BoxConstraints(minHeight: 16),
      width: double.infinity,
      padding: null,
      decoration: null,
      foregroundDecoration: null,
      child: Align(
        heightFactor: 1,
        alignment: separator || widget.axis == Axis.vertical
            ? Alignment.center
            : AlignmentDirectional.centerStart,
        child: content,
      ),
    );

    return Semantics(
      container: widget.liveRegion,
      liveRegion: widget.liveRegion,
      label: null,
      excludeSemantics: false,
      button: false,
      link: false,
      enabled: null,
      onTap: null,
      child: content,
    );
  }
}

/// Decorative, non-interactive artwork. Adjacent content carries its meaning.
class DMarkerIcon extends StatelessWidget {
  const DMarkerIcon({super.key, required this.child})
    : assert((16 < double.infinity));
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ExcludeFocus(
      child: IgnorePointer(
        child: SizedBox.square(
          dimension: 16,
          child: FittedBox(
            child: IconTheme.merge(
              data: const IconThemeData(size: 16),
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
    // CSS derives the highlight in Oklch, preserving chroma and hue.
    final lab = Oklab.of(base);
    final highlightAlpha = dark ? math.min(1.0, base.a + .4) : base.a * .2;
    final highlightLightness = dark
        ? math.max(.8, lab.lightness + .4)
        : lab.lightness;
    final highlight = lab
        .withLightness(highlightLightness)
        .toColor(alpha: highlightAlpha);
    // CSS color-mix premultiplies alpha in Oklab before mixing.
    final middleAlpha = (base.a + highlightAlpha) / 2;
    final middleLightness = middleAlpha == 0
        ? lab.lightness
        : (lab.lightness * base.a + highlightLightness * highlightAlpha) /
              (base.a + highlightAlpha);
    final middle = lab
        .withLightness(middleLightness)
        .toColor(alpha: middleAlpha);
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
      // The shader owns color/alpha; the child supplies only glyph coverage.
      child: DefaultTextStyle.merge(
        style: TextStyle(color: base.withValues(alpha: 1)),
        child: widget.child,
      ),
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
