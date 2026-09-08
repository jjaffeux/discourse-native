import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../foundation/tokens.dart';

/// An indeterminate busy indicator. The caller owns loading and completion.
///
/// Uses native Apple activity artwork on iOS/macOS and Material artwork on
/// other platforms. Supply [child] to rotate custom artwork instead. Neither
/// artwork nor its descendants receive focus, pointer input or semantics.
///
/// The indicator remains visible without motion when [animating] is false,
/// reduced motion is requested, its ticker subtree is disabled, or the app is
/// inactive. It never reports a numeric percentage, including when stationary.
class DSpinner extends StatefulWidget {
  const DSpinner({
    super.key,
    this.size = DSpacing.lg,
    this.color,
    this.strokeWidth = 2,
    this.semanticLabel = 'Loading',
    this.animating = true,
    this.child,
  }) : assert(size > 0 && size < double.infinity),
       assert(strokeWidth > 0 && strokeWidth < double.infinity);

  /// Preferred diameter in logical pixels; tight parent constraints win.
  /// Does not scale with text. Use a wrapping label for large text layouts.
  final double size;

  /// Inherits the surrounding icon color, then the host's foreground token.
  /// Custom artwork receives this color through IconTheme and DefaultTextStyle.
  final Color? color;

  /// Material ring thickness. Native Apple and custom artwork own their strokes.
  final double strokeWidth;

  /// Localizable loading status. Null makes the spinner decorative when its
  /// containing button, input or status text already describes the operation.
  final String? semanticLabel;

  /// Whether motion is requested. False preserves the busy status and geometry.
  /// Remove the spinner when the operation has completed.
  final bool animating;

  /// Optional artwork, fitted into [size] and rotated clockwise once a second.
  /// The inherited icon size is [size]. Rotation is independent of direction.
  final Widget? child;

  @override
  State<DSpinner> createState() => _DSpinnerState();
}

class _DSpinnerState extends State<DSpinner> with WidgetsBindingObserver {
  late bool _active;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _active = _isActive(binding.lifecycleState);
    binding.addObserver(this);
  }

  static bool _isActive(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = _isActive(state);
    if (_active != active) setState(() => _active = active);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        IconTheme.of(context).color ??
        DTokens.of(context).foreground;
    final animate =
        widget.animating &&
        _active &&
        TickerMode.valuesOf(context).enabled &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final Widget artwork;
    if (widget.child case final child?) {
      artwork = _SpinnerArtwork(animating: animate, child: child);
    } else {
      artwork = switch (Theme.of(context).platform) {
        TargetPlatform.iOS ||
        TargetPlatform.macOS => CupertinoActivityIndicator(
          animating: animate,
          radius: widget.size / 2,
          color: color,
        ),
        _ => CircularProgressIndicator(
          // A static arc avoids motion while the outer semantics remain busy.
          value: animate ? null : 0.75,
          color: color,
          strokeWidth: widget.strokeWidth,
          strokeAlign: CircularProgressIndicator.strokeAlignInside,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tight(Size.square(widget.size)),
        ),
      };
    }

    final indicator = ExcludeSemantics(
      child: ExcludeFocus(
        child: IgnorePointer(
          child: SizedBox.square(
            dimension: widget.size,
            child: FittedBox(
              child: SizedBox.square(
                dimension: widget.size,
                child: IconTheme.merge(
                  data: IconThemeData(color: color, size: widget.size),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: color),
                    child: artwork,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.semanticLabel == null) return indicator;
    return Semantics(
      container: true,
      role: SemanticsRole.loadingSpinner,
      label: widget.semanticLabel,
      liveRegion: true,
      child: indicator,
    );
  }
}

class _SpinnerArtwork extends StatefulWidget {
  const _SpinnerArtwork({required this.animating, required this.child});

  final bool animating;
  final Widget child;

  @override
  State<_SpinnerArtwork> createState() => _SpinnerArtworkState();
}

class _SpinnerArtworkState extends State<_SpinnerArtwork>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: DMotion.spin,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animating) _rotation.repeat();
  }

  @override
  void didUpdateWidget(_SpinnerArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating == oldWidget.animating) return;
    if (widget.animating) {
      _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _rotation,
    child: FittedBox(child: widget.child),
  );
}
