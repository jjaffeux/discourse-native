import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/tokens.dart';

/// Shared measured selection artwork for Native's inset groups.
class DGroupIndicator extends StatefulWidget {
  const DGroupIndicator({
    super.key,
    required this.selectedKey,
    required this.child,
  });

  final GlobalKey? selectedKey;
  final Widget child;

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_IndicatorScope>() != null;

  @override
  State<DGroupIndicator> createState() => _DGroupIndicatorState();
}

class _DGroupIndicatorState extends State<DGroupIndicator> {
  final _bounds = GlobalKey();
  Rect? _rect;
  bool _measurementPending = false;

  void _measure() {
    if (_measurementPending) return;
    _measurementPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementPending = false;
      if (!mounted) return;
      final bounds = _bounds.currentContext?.findRenderObject();
      final selected = widget.selectedKey?.currentContext?.findRenderObject();
      final rect =
          bounds is RenderBox &&
              selected is RenderBox &&
              bounds.hasSize &&
              selected.hasSize
          ? bounds.globalToLocal(selected.localToGlobal(Offset.zero)) &
                selected.size
          : null;
      if (rect != _rect) setState(() => _rect = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    final rect = _rect;
    return _IndicatorScope(
      child: _IndicatorLayout(
        onLayout: _measure,
        child: Stack(
          key: _bounds,
          children: [
            if (rect != null)
              AnimatedPositioned(
                key: const ValueKey('toggle-group-sliding-indicator'),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: const Cubic(.2, .8, .2, 1),
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: DTokens.of(
                        context,
                      ).foreground.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(DRadius.pill),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _IndicatorScope extends InheritedWidget {
  const _IndicatorScope({required super.child});

  @override
  bool updateShouldNotify(_IndicatorScope oldWidget) => false;
}

class _IndicatorLayout extends SingleChildRenderObjectWidget {
  const _IndicatorLayout({required this.onLayout, required super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIndicatorLayout(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderIndicatorLayout renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderIndicatorLayout extends RenderProxyBox {
  _RenderIndicatorLayout(this.onLayout);

  VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}
