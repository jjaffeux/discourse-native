import 'dart:ui' show FontFeature, SemanticsRole;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_label.dart';

/// Read-only progress. Values use [min]..[max] (0..100 by default); null or
/// non-finite values represent unknown progress. Finite values are clamped.
/// The caller owns asynchronous work and can use ValueListenableBuilder for
/// controller composition. This is not an editable field or a keyboard stop.
///
/// [label] and [valueLabel] share a wrapping header with a 12px gap to [track].
/// Set [child] to replace that layout with arbitrary composition of the public
/// parts. Supply [semanticsLabel] when the visible label is absent. A numeric
/// accessible percentage is updated without repeatedly interrupting speech.
class DProgress extends StatelessWidget {
  const DProgress({
    super.key,
    this.value,
    this.min = 0,
    this.max = 100,
    this.label,
    this.valueLabel,
    this.track = const DProgressTrack(),
    this.child,
    this.semanticsLabel,
    this.semanticsValue,
  }) : assert(min > double.negativeInfinity && min < double.infinity),
       assert(max > min && max < double.infinity);

  final double? value;
  final double min;
  final double max;
  final Widget? label;
  final Widget? valueLabel;
  final Widget track;
  final Widget? child;
  final String? semanticsLabel;

  /// Optional numeric percentage override, matching Flutter range semantics.
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    final fraction = value == null || !value!.isFinite
        ? null
        : ((max - min).isFinite
              ? (value!.clamp(min, max) - min) / (max - min)
              : (value!.clamp(min, max) / 2 - min / 2) / (max / 2 - min / 2));
    return _ProgressScope(
      fraction: fraction,
      child: Semantics(
        container: true,
        role: fraction == null
            ? SemanticsRole.loadingSpinner
            : SemanticsRole.progressBar,
        label: semanticsLabel,
        value: fraction == null
            ? null
            : semanticsValue ?? '${(fraction * 100).round()}',
        minValue: fraction == null ? null : '0',
        maxValue: fraction == null ? null : '100',
        child:
            child ??
            (label == null && valueLabel == null
                ? track
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (label != null || valueLabel != null) ...[
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Intrinsic wrapping keeps both labels visible at large text
                            // sizes without changing their element identity on resize.
                            return Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 12,
                              children: [?label, ?valueLabel],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      track,
                    ],
                  )),
      ),
    );
  }
}

class _ProgressScope extends InheritedWidget {
  const _ProgressScope({required this.fraction, required super.child});
  final double? fraction;
  static _ProgressScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ProgressScope>();
    assert(scope != null, 'Progress parts must be descendants of DProgress.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_ProgressScope oldWidget) =>
      fraction != oldWidget.fraction;
}

/// Rounded muted track. Thin application loading strips can override [height].
/// Give progress finite horizontal constraints (or an explicit [width]).
class DProgressTrack extends StatelessWidget {
  const DProgressTrack({
    super.key,
    this.height = 4,
    this.width,
    this.color,
    this.child = const DProgressIndicator(),
  }) : assert(height >= 0 && height < double.infinity),
       assert(width == null || (width >= 0 && width < double.infinity));
  final double height;
  final double? width;
  final Color? color;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: width,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: ColoredBox(
        color: color ?? DTokens.of(context).muted,
        child: child,
      ),
    ),
  );
}

/// Logical-start fill with the reference's 150ms CSS transition. Unknown work
/// uses a moving one-third segment; reduced motion holds it at logical start.
/// This native adaptation makes existing asynchronous loading strips visible;
/// upstream's unstyled null-value indicator has no intrinsic width.
class DProgressIndicator extends StatefulWidget {
  const DProgressIndicator({super.key, this.color});
  final Color? color;
  @override
  State<DProgressIndicator> createState() => _DProgressIndicatorState();
}

class _DProgressIndicatorState extends State<DProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final unknown = _ProgressScope.of(context).fraction == null;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (unknown && !reduced && TickerMode.valuesOf(context).enabled) {
      if (!_animation.isAnimating) _animation.repeat();
    } else {
      _animation.stop();
      _animation.value = 0;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _ProgressScope.of(context).fraction;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final fill = ColoredBox(color: widget.color ?? DTokens.of(context).primary);
    if (fraction == null) {
      return AnimatedBuilder(
        animation: _animation,
        builder: (context, _) => Align(
          alignment: AlignmentDirectional(-1 + _animation.value * 2, 0),
          child: FractionallySizedBox(
            widthFactor: 1 / 3,
            heightFactor: 1,
            child: fill,
          ),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: fraction, end: fraction),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 150),
      curve: Curves.fastOutSlowIn,
      builder: (context, value, _) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: value,
          heightFactor: 1,
          child: fill,
        ),
      ),
    );
  }
}

/// Visible accessible progress label using the reference's 14px/20px metrics.
class DProgressLabel extends StatelessWidget {
  const DProgressLabel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DLabel(
    style: const TextStyle(height: 20 / 14),
    child: child,
  );
}

/// Formatted percentage; unknown values render [indeterminateText]. A builder
/// receives a normalized fraction or null and can localize units and digits.
/// The root owns numeric semantics, avoiding a duplicate spoken percentage.
class DProgressValue extends StatelessWidget {
  const DProgressValue({super.key, this.builder, this.indeterminateText = '—'});
  final Widget Function(BuildContext context, double? fraction)? builder;
  final String indeterminateText;
  @override
  Widget build(BuildContext context) {
    final fraction = _ProgressScope.of(context).fraction;
    return ExcludeSemantics(
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: DiscourseTypography.sm,
          height: 20 / 14,
          fontWeight: FontWeight.w400,
          color: DTokens.of(context).mutedForeground,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        child:
            builder?.call(context, fraction) ??
            Text(
              fraction == null
                  ? indeterminateText
                  : '${(fraction * 100).round()}%',
            ),
      ),
    );
  }
}
