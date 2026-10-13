import 'package:flutter/material.dart';

/// Moves shared header parts between full and compact layouts in place.
/// The builder keeps control ownership and callbacks while the kit owns motion.
class DHeaderMorph extends StatefulWidget {
  const DHeaderMorph({super.key, required this.compact, required this.builder});
  final bool compact;
  final Widget Function(
    BuildContext context,
    bool compact,
    Widget Function(String id, Widget child) part,
  )
  builder;
  @override
  State<DHeaderMorph> createState() => _DHeaderMorphState();
}

class _DHeaderMorphState extends State<DHeaderMorph> {
  final _parts = <String, GlobalKey<_MorphPartState>>{};
  Map<String, Rect> _positions() => {
    for (final entry in _parts.entries)
      if (entry.value.currentState?.rect case final Rect rect) entry.key: rect,
  };
  @override
  void didUpdateWidget(DHeaderMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact == widget.compact ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final before = _positions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final entry in before.entries) {
        _parts[entry.key]?.currentState?.moveFrom(entry.value);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    widget.compact,
    (id, child) => _MorphPart(
      key: _parts.putIfAbsent(id, () => GlobalKey<_MorphPartState>()),
      child: child,
    ),
  );
}

class _MorphPart extends StatefulWidget {
  const _MorphPart({super.key, required this.child});
  final Widget child;
  @override
  State<_MorphPart> createState() => _MorphPartState();
}

class _MorphPartState extends State<_MorphPart>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Offset _offset = Offset.zero;
  double _scaleX = 1;
  double _scaleY = 1;
  final _box = GlobalKey();
  Rect? get rect {
    final box = _box.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  void moveFrom(Rect previous) {
    final next = rect;
    if (next == null || next.width == 0 || next.height == 0) return;
    _offset = previous.topLeft - next.topLeft;
    _scaleX = previous.width / next.width;
    _scaleY = previous.height / next.height;
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: SizedBox(key: _box, child: widget.child),
    builder: (context, child) {
      final remaining = 1 - const Cubic(.2, .8, .2, 1).transform(_motion.value);
      return Transform(
        alignment: Alignment.topLeft,
        // Targets travel with the same visible artwork.
        transformHitTests: true,
        transform: Matrix4.identity()
          ..translateByDouble(
            _offset.dx * remaining,
            _offset.dy * remaining,
            0,
            1,
          )
          ..scaleByDouble(
            1 + (_scaleX - 1) * remaining,
            1 + (_scaleY - 1) * remaining,
            1,
            1,
          ),
        child: child,
      );
    },
  );
}
