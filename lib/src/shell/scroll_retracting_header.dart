import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Composes a page's existing Native header and viewport. Only deliberate
/// scrolling in the body retracts the header; restoration and nested scrolls
/// leave it alone. Collapsible owns animation, reduced motion and hidden focus.
class ScrollRetractingHeader extends StatefulWidget {
  const ScrollRetractingHeader({
    super.key,
    required this.header,
    required this.child,
    this.identity,
  });

  final Widget header;
  final Widget child;
  final Object? identity;

  @override
  State<ScrollRetractingHeader> createState() => _ScrollRetractingHeaderState();
}

class _ScrollRetractingHeaderState extends State<ScrollRetractingHeader> {
  final _headerFocus = FocusNode(canRequestFocus: false);
  bool _visible = true;
  bool _userScrolling = false;
  ScrollDirection _direction = ScrollDirection.idle;
  double _distance = 0;
  bool _updateScheduled = false;

  @override
  void didUpdateWidget(ScrollRetractingHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _visible = true;
      _userScrolling = false;
      _direction = ScrollDirection.idle;
      _distance = 0;
    }
  }

  void _show(bool visible) {
    if (_visible == visible || (!visible && _headerFocus.hasFocus)) return;
    _visible = visible;
    // Scroll notifications can arrive during layout. Coalesce direction
    // changes without rebuilding the expensive body on each scroll tick.
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
      if (_userScrolling && _direction != notification.direction) {
        _direction = notification.direction;
        _distance = 0;
      }
    }
    if (notification is ScrollUpdateNotification && _userScrolling) {
      final metrics = notification.metrics;
      if (metrics.pixels <= metrics.minScrollExtent) {
        _distance = 0;
        _show(true);
      } else if (!metrics.outOfRange) {
        final delta = notification.scrollDelta ?? 0;
        // Ignore extent corrections and elastic rebound against the user's
        // direction, including when the header changes the viewport height.
        if ((_direction == ScrollDirection.reverse && delta > 0) ||
            (_direction == ScrollDirection.forward && delta < 0)) {
          _distance += delta.abs();
          final revealing = _direction == ScrollDirection.forward;
          final headerHeight = _headerFocus.context?.size?.height ?? 0;
          final canRetract =
              !_visible ||
              metrics.maxScrollExtent - metrics.minScrollExtent > headerHeight;
          if (_distance >= (revealing ? 6 : 12) && (revealing || canRetract)) {
            _show(revealing);
          }
        }
      }
    }
    return false;
  }

  @override
  void dispose() {
    _headerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      DCollapsible(
        open: _visible,
        child: DCollapsibleContent(
          keepMounted: true,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutCubic,
          child: Focus(focusNode: _headerFocus, child: widget.header),
        ),
      ),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
      ),
    ],
  );
}
