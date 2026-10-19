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
/// Supply [semanticsLabel] to name the operation. The numeric accessible
/// percentage updates without repeatedly interrupting speech. Use [track] to
/// compose the existing progress parts when visible labels are needed.
class DProgress extends StatelessWidget {
  const DProgress({
    super.key,
    this.value,

    this.max = 100,

    this.track = const DProgressTrack(),

    this.semanticsLabel,
  }) : assert(max > 0 && max < double.infinity);

  final double? value;

  final double max;

  final Widget track;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final fraction = value == null || !value!.isFinite
        ? null
        : value!.clamp(0, max) / max;
    return _ProgressScope(
      fraction: fraction,
      child: Semantics(
        container: true,
        role: fraction == null
            ? SemanticsRole.loadingSpinner
            : SemanticsRole.progressBar,
        label: semanticsLabel,
        value: fraction == null ? null : ('${(fraction * 100).round()}'),
        minValue: fraction == null ? null : '0',
        maxValue: fraction == null ? null : '100',
        child: (((track))),
      ),
    );
  }
}

/// Circular artwork for a [DProgress] owner, including unknown progress.
class DProgressRing extends StatelessWidget {
  const DProgressRing({super.key, this.size = 24, this.strokeWidth = 2})
    : assert(size > 0 && size < double.infinity),
      assert(strokeWidth > 0 && strokeWidth < double.infinity);

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        value: _ProgressScope.of(context).fraction,
        strokeWidth: strokeWidth,
        color: DTokens.of(context).primary,
      ),
    ),
  );
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
  const DProgressTrack({super.key, this.height = 4})
    : assert(height >= 0 && height < double.infinity);
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: null,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: ColoredBox(
        color: (DTokens.of(context).muted),
        child: const DProgressIndicator(),
      ),
    ),
  );
}

/// Logical-start fill with the reference's 150ms CSS transition. Unknown work
/// uses a moving one-third segment; reduced motion holds it at logical start.
/// This native adaptation makes existing asynchronous loading strips visible;
/// upstream's unstyled null-value indicator has no intrinsic width.
class DProgressIndicator extends StatefulWidget {
  const DProgressIndicator({super.key});

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
    final fill = ColoredBox(color: (DTokens.of(context).primary));
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
