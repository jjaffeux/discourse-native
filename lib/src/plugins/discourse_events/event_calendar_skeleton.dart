import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import 'event_data.dart';

/// Loading geometry follows the selected view without exposing stale events.
final class EventCalendarSkeleton extends StatelessWidget {
  const EventCalendarSkeleton({
    super.key,
    required this.view,
    required this.dayCount,
  });

  final EventCalendarView view;
  final int dayCount;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SingleChildScrollView(
      child: DSkeletonRegion(
        semanticsLabel: 'Loading events',
        color: skeletonFill(context),
        child: switch (view) {
          EventCalendarView.schedule ||
          EventCalendarView.year => _schedule(scaler),
          _ => _grid(scaler),
        },
      ),
    );
  }

  Widget _schedule(TextScaler scaler) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var day = 0; day < 3; day++) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            spacing: 12,
            children: [
              const DSkeleton.circle(diameter: 8),
              DSkeleton(width: 88, height: scaler.scale(16)),
            ],
          ),
        ),
        for (var event = 0; event < (day == 1 ? 2 : 1); event++)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 0, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                DSkeleton(width: scaler.scale(36), height: scaler.scale(12)),
                DSkeleton(width: 3, height: scaler.scale(36)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: event == 0 ? 0.9 : 0.7,
                        child: DSkeleton(height: scaler.scale(16)),
                      ),
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 0.65,
                        child: DSkeleton(height: scaler.scale(12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ],
  );

  Widget _grid(TextScaler scaler) {
    final month = view == EventCalendarView.month;
    final columns = view == EventCalendarView.day ? 1 : 7;
    final rows = month ? dayCount ~/ 7 : 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            spacing: 8,
            children: [
              for (var day = 0; day < columns; day++)
                Expanded(
                  child: Center(
                    child: DSkeleton(width: 24, height: scaler.scale(12)),
                  ),
                ),
            ],
          ),
        ),
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                for (var day = 0; day < columns; day++)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        if (month)
                          DSkeleton(width: 14, height: scaler.scale(12)),
                        DSkeleton(height: month ? 5 : 48),
                        if (month) const DSkeleton(height: 5),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
