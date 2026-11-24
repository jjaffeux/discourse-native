import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'd_card.dart';
import 'd_carousel.dart';
import 'd_sheet.dart';

/// The phone calendar's horizontally paged, vertically expandable day panels.
class DCalendarDayPanels extends StatelessWidget {
  const DCalendarDayPanels({
    super.key,
    required this.days,
    required this.initialIndex,
    required this.selectedIndex,
    required this.expanded,
    required this.onSelected,
    required this.onExpand,
    required this.onCollapse,
    required this.onDismiss,
  });

  final List<({String label, Widget child})> days;
  final int initialIndex;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelected;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final selected = days[selectedIndex];
    final tokens = DTokens.of(context);
    return Column(
      children: [
        Expanded(
          child: DCarousel(
            navigationInsets: false,
            semanticLabel: context.l10n.events,
            onSelected: onSelected,
            children: [
              DCarouselContent(
                initialIndex: initialIndex,
                viewportPeek: 18,
                spacing: DSpacing.sm,
                children: [
                  for (final (index, day) in days.indexed)
                    DCarouselItem(
                      child: DCard(
                        backgroundColor: tokens.panelBackground,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(30),
                        ),
                        spacing: 0,
                        child: Expanded(
                          child: _DayPanelDrag(
                            expanded: expanded,
                            onExpand: onExpand,
                            onCollapse: onCollapse,
                            onDismiss: onDismiss,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  button: true,
                                  label: expanded
                                      ? context.l10n.collapse
                                      : context.l10n.expand,
                                  child: GestureDetector(
                                    key: ValueKey((
                                      'calendar-day-handle',
                                      index,
                                    )),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: expanded ? onCollapse : onExpand,
                                    child: const Padding(
                                      padding: EdgeInsets.fromLTRB(0, 6, 0, 8),
                                      child: Center(child: DSheetGrabMark()),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Semantics(
                                    container: true,
                                    label: day.label,
                                    child: day.child,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (expanded)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(DSpacing.sm),
              child: Text(
                selected.label,
                style: Theme.of(context).textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _DayPanelDrag extends StatefulWidget {
  const _DayPanelDrag({
    required this.expanded,
    required this.onExpand,
    required this.onCollapse,
    required this.onDismiss,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_DayPanelDrag> createState() => _DayPanelDragState();
}

class _DayPanelDragState extends State<_DayPanelDrag> {
  double _travel = 0;
  bool _scrollStartedAtTop = false;

  void _finish(double velocity) {
    final travel = _travel;
    _travel = 0;
    if (widget.expanded) {
      if (travel > 280) {
        widget.onDismiss();
      } else if (travel > 48 || (travel > 8 && velocity > 400)) {
        widget.onCollapse();
      }
    } else if (travel > 100 || (travel > 24 && velocity > 600)) {
      widget.onDismiss();
    } else if (travel < -48 || (travel < -8 && velocity < -400)) {
      widget.onExpand();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    switch (notification) {
      case ScrollStartNotification(:final dragDetails, :final metrics):
        _scrollStartedAtTop =
            dragDetails != null && metrics.pixels <= metrics.minScrollExtent;
        _travel = 0;
      case OverscrollNotification(:final overscroll, :final dragDetails)
          when _scrollStartedAtTop && dragDetails != null && overscroll < 0:
        _travel -= overscroll;
      case ScrollUpdateNotification(:final metrics)
          when metrics.pixels > metrics.minScrollExtent:
        _scrollStartedAtTop = false;
      case ScrollEndNotification(:final dragDetails) when _scrollStartedAtTop:
        _scrollStartedAtTop = false;
        final velocity = dragDetails?.primaryVelocity ?? 0;
        final binding = WidgetsBinding.instance;
        binding.addPostFrameCallback((_) {
          if (mounted) _finish(velocity);
        });
        binding.ensureVisualUpdate();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    dragStartBehavior: DragStartBehavior.down,
    onVerticalDragStart: (_) => _travel = 0,
    onVerticalDragUpdate: (details) => _travel += details.delta.dy,
    onVerticalDragEnd: (details) => _finish(details.primaryVelocity ?? 0),
    onVerticalDragCancel: () => _travel = 0,
    child: NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          physics: widget.expanded
              ? const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                )
              : const NeverScrollableScrollPhysics(),
        ),
        child: widget.child,
      ),
    ),
  );
}
