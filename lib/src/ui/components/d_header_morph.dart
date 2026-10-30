import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'd_sheet.dart';

/// Moves shared header parts between full and compact layouts in place.
/// The builder keeps control ownership and callbacks while the kit owns motion.
class DHeaderMorph extends StatefulWidget {
  const DHeaderMorph({super.key, required this.compact, required this.builder});
  static Widget scrollFade({
    required ValueListenable<double>? scroll,
    required double Function() extent,
    required ValueNotifier<double> titleOpacity,
    required Widget child,
  }) => _ScrollFadeScope(
    scroll: scroll,
    extent: extent,
    titleOpacity: titleOpacity,
    child: child,
  );

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
  final _root = GlobalKey();
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
  Widget build(BuildContext context) => RepaintBoundary(
    key: _root,
    child: widget.builder(
      context,
      widget.compact,
      (id, child) => _MorphPart(
        key: _parts.putIfAbsent(id, () => GlobalKey<_MorphPartState>()),
        child: _ReaderFadePart(id: id, root: _root, child: child),
      ),
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
    child: RepaintBoundary(key: _box, child: widget.child),
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

class _ScrollFadeScope extends InheritedWidget {
  const _ScrollFadeScope({
    required this.scroll,
    required this.extent,
    required this.titleOpacity,
    required super.child,
  });
  final ValueListenable<double>? scroll;
  final double Function() extent;
  final ValueNotifier<double> titleOpacity;
  @override
  bool updateShouldNotify(_ScrollFadeScope oldWidget) =>
      scroll != oldWidget.scroll || extent != oldWidget.extent;
}

class _ReaderFadePart extends StatefulWidget {
  const _ReaderFadePart({
    required this.id,
    required this.root,
    required this.child,
  });
  final String id;
  final GlobalKey root;
  final Widget child;
  @override
  State<_ReaderFadePart> createState() => _ReaderFadePartState();
}

class _ReaderFadePartState extends State<_ReaderFadePart> {
  final _box = GlobalKey();
  _ScrollFadeScope? _scope;
  ValueListenable<double>? _edge;
  double _opacity = 1;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope?.scroll?.removeListener(_measure);
    _edge?.removeListener(_measure);
    _scope = context.dependOnInheritedWidgetOfExactType<_ScrollFadeScope>();
    _edge = DSheetPageBand.edgeOf(context);
    if (_scope?.scroll?.value == double.infinity) _opacity = 0;
    _scope?.scroll?.addListener(_measure);
    _edge?.addListener(_measure);
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _schedule();
      return;
    }
    final scope = _scope;
    final box = _box.currentContext?.findRenderObject() as RenderBox?;
    final root = widget.root.currentContext?.findRenderObject() as RenderBox?;
    if (scope?.scroll == null ||
        box == null ||
        root == null ||
        !box.hasSize ||
        !root.hasSize) {
      return;
    }
    final bottom = box
        .localToGlobal(Offset(0, box.size.height), ancestor: root)
        .dy;
    final clearance = math.max(1.0, scope!.extent() - bottom);
    final gap = clearance - scope.scroll!.value - (_edge?.value ?? 0);
    final opacity = (gap / math.min(40, clearance)).clamp(0.0, 1.0);
    if (widget.id == 'title') scope.titleOpacity.value = opacity;
    if (_opacity != opacity) setState(() => _opacity = opacity);
  }

  @override
  void dispose() {
    _scope?.scroll?.removeListener(_measure);
    _edge?.removeListener(_measure);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_scope?.scroll == null) return widget.child;
    _schedule();
    return SizedBox(
      key: _box,
      child: IgnorePointer(
        ignoring: _opacity < .5,
        child: ExcludeSemantics(
          excluding: _opacity < .5,
          child: ExcludeFocus(
            excluding: _opacity < .5,
            child: Opacity(opacity: _opacity, child: widget.child),
          ),
        ),
      ),
    );
  }
}
