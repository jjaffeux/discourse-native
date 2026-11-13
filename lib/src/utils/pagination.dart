import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/widgets.dart';

export 'paging_policy.dart';

/// Exposes ballistic speed for fetching ahead without polling during scrolling.
class PaginationScrollController extends ScrollController {
  double get velocity =>
      hasClients ? (position as PaginationScrollPosition).velocity : 0;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => PaginationScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class PaginationScrollPosition extends ScrollPositionWithSingleContext {
  PaginationScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  double get velocity => activity?.velocity ?? 0;
}

/// Requests a page when its list boundary reaches the viewport.
class ScrollPageTrigger extends StatefulWidget {
  const ScrollPageTrigger({
    super.key,
    required this.enabled,
    required this.onLoad,
    required this.child,
    this.leading = false,
  });

  final bool enabled;
  final VoidCallback onLoad;
  final Widget child;
  final bool leading;

  @override
  State<ScrollPageTrigger> createState() => _ScrollPageTriggerState();
}

class _ScrollPageTriggerState extends State<ScrollPageTrigger> {
  ScrollPosition? _position;
  bool _scheduled = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position == _position) return;
    _position?.removeListener(_scheduleCheck);
    _position = position;
    position?.addListener(_scheduleCheck);
  }

  @override
  void didUpdateWidget(ScrollPageTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    _requested = false;
  }

  void _scheduleCheck() {
    if (!widget.enabled || _scheduled || _requested) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !widget.enabled) return;
      final position = _position;
      final target = context.findRenderObject();
      if (position == null ||
          !position.hasContentDimensions ||
          target == null ||
          !target.attached) {
        return;
      }
      final viewport = RenderAbstractViewport.maybeOf(target);
      if (viewport == null) return;
      final bottom = viewport.getOffsetToReveal(target, 1).offset;
      final top = widget.leading
          ? viewport.getOffsetToReveal(target, 0).offset
          : null;
      if (bottom <= position.pixels + 0.5 &&
          (top == null || top >= position.pixels - 0.5)) {
        _requested = true;
        widget.onLoad();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleCheck);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    MediaQuery.maybeSizeOf(context);
    _scheduleCheck();
    return widget.child;
  }
}
