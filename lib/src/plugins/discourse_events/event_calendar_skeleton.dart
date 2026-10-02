import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
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
    final schedule =
        view == EventCalendarView.schedule || view == EventCalendarView.year;
    final skeleton = DSkeletonRegion(
      semanticsLabel: context.l10n.loadingEvents,
      color: skeletonFill(context),
      expand: schedule,
      child: schedule ? _schedule(scaler) : _grid(scaler),
    );
    return schedule ? skeleton : SingleChildScrollView(child: skeleton);
  }

  Widget _schedule(TextScaler scaler) => LayoutBuilder(
    builder: (context, constraints) {
      final dateHeight = 24 + math.max(8, scaler.scale(16));
      final entryHeight =
          32 +
          math.max(scaler.scale(36), scaler.scale(16) + 8 + scaler.scale(12));
      // Even single-event dates must reach the bottom at the current text size.
      final days = constraints.hasBoundedHeight
          ? math.max(
              3,
              (constraints.maxHeight / (dateHeight + entryHeight)).ceil(),
            )
          : 3;
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var day = 0; day < days; day++) ...[
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
            for (var event = 0; event < (day % 3 == 1 ? 2 : 1); event++)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 0, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    DSkeleton(
                      width: scaler.scale(36),
                      height: scaler.scale(12),
                    ),
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
      return constraints.hasBoundedHeight
          ? ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: double.infinity,
                child: content,
              ),
            )
          : content;
    },
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
