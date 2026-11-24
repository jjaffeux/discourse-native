import 'package:discourse_native/l10n/strings.dart';
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
    required this.onDismiss,
  });

  final List<({String label, Widget child})> days;
  final int initialIndex;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelected;
  final VoidCallback onExpand;
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _DayPanelGrabber(
                                key: ValueKey(('calendar-day-handle', index)),
                                expanded: expanded,
                                onExpand: onExpand,
                                onDismiss: onDismiss,
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

class _DayPanelGrabber extends StatefulWidget {
  const _DayPanelGrabber({
    super.key,
    required this.expanded,
    required this.onExpand,
    required this.onDismiss,
  });

  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onDismiss;

  @override
  State<_DayPanelGrabber> createState() => _DayPanelGrabberState();
}

class _DayPanelGrabberState extends State<_DayPanelGrabber> {
  double _travel = 0;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.expanded ? context.l10n.collapse : context.l10n.expand,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.expanded ? widget.onDismiss : widget.onExpand,
      onVerticalDragStart: (_) => _travel = 0,
      onVerticalDragUpdate: (details) => _travel += details.delta.dy,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (_travel > 30 || velocity > 400) {
          widget.onDismiss();
        } else if (_travel < -30 || velocity < -400) {
          widget.onExpand();
        }
      },
      child: const Padding(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 10),
        child: Center(child: DSheetGrabMark()),
      ),
    ),
  );
}
