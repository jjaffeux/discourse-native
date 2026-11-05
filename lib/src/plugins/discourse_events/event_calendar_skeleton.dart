import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'event_data.dart';

/// How the month view arranges itself for the available width.
enum EventMonthLayout { compact, grid, split }

/// The month geometry a loaded calendar uses, so loading does not reflow.
final class EventMonthMetrics {
  const EventMonthMetrics({
    required this.layout,
    required this.dayHeaderHeight,
    required this.laneHeight,
    required this.panelWidth,
    required this.panelGap,
  });

  final EventMonthLayout layout;
  final double dayHeaderHeight;
  final double laneHeight;
  final double panelWidth;
  final double panelGap;
}

/// Loading geometry follows the selected view without exposing stale events.
final class EventCalendarSkeleton extends StatelessWidget {
  const EventCalendarSkeleton({
    super.key,
    required this.view,
    required this.dayCount,
    required this.month,
  });

  final EventCalendarView view;
  final int dayCount;
  final EventMonthMetrics month;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final schedule =
        view == EventCalendarView.schedule || view == EventCalendarView.year;
    final isMonth = view == EventCalendarView.month;
    final skeleton = DSkeletonRegion(
      semanticsLabel: context.l10n.loadingEvents,
      color: skeletonFill(context),
      expand: schedule || isMonth,
      child: schedule
          ? _schedule(scaler)
          : isMonth
          ? _month(context, scaler)
          : _grid(scaler),
    );
    return schedule || isMonth
        ? skeleton
        : SingleChildScrollView(child: skeleton);
  }

  Widget _month(BuildContext context, TextScaler scaler) {
    final tokens = DTokens.of(context);
    final weeks = math.max(1, dayCount ~/ 7);
    final layout = month.layout;
    final grid = layout == EventMonthLayout.grid;
    final lineColor = grid
        ? tokens.border.withValues(alpha: .55)
        : tokens.border;
    final line = BorderSide(color: lineColor);
    final labelHeight = math.max(32.0, scaler.scale(12) * 1.3 + 8);
    final numberHeight = grid
        ? month.dayHeaderHeight
        : math.max(28.0, scaler.scale(13) + 12);
    final laneHeight = grid ? month.laneHeight : 9.0;
    final minWeek = grid
        ? month.dayHeaderHeight + 4 * month.laneHeight
        : numberHeight + 2 * laneHeight + 6;
    // A deterministic spread, so the placeholder reads as a month of
    // varied days rather than a uniform pattern.
    const busy = [2, 3, 1, 3, 2, 0, 1, 1, 3, 2, 0, 2, 3, 1];

    Widget weekdays() => Row(
      children: [
        for (var day = 0; day < 7; day++)
          Expanded(
            child: SizedBox(
              height: labelHeight,
              child: Align(
                alignment: grid
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.center,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: grid ? 9 : 0),
                  child: DSkeleton(width: 24, height: scaler.scale(10)),
                ),
              ),
            ),
          ),
      ],
    );

    Widget cell(int week, int day) {
      final lanes = busy[(week * 3 + day) % busy.length];
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: line,
            left: day == 0 && !grid ? BorderSide.none : line,
            right: grid && day == 6 ? line : BorderSide.none,
            bottom: grid && week == weeks - 1 ? line : BorderSide.none,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Full lanes keep a row for "+N more"; thin bars share it.
            final fit = math.max(
              0,
              ((constraints.maxHeight - numberHeight - (grid ? 0 : 6)) /
                          laneHeight)
                      .floor() -
                  (grid ? 1 : 0),
            );
            return ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: numberHeight,
                    child: Align(
                      alignment: grid
                          ? AlignmentDirectional.centerStart
                          : AlignmentDirectional.topStart,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: 9,
                          top: grid ? 0 : 8,
                        ),
                        child: DSkeleton(width: 14, height: scaler.scale(10)),
                      ),
                    ),
                  ),
                  for (var lane = 0; lane < math.min(lanes, fit); lane++)
                    SizedBox(
                      height: laneHeight,
                      child: grid
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Row(
                                children: [
                                  const DSkeleton.circle(diameter: 6),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: FractionallySizedBox(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      widthFactor: const [
                                        .85,
                                        .6,
                                        .75,
                                      ][(week + day + lane) % 3],
                                      child: DSkeleton(
                                        height: math.min(
                                          laneHeight - 8,
                                          scaler.scale(10),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 2,
                              ),
                              child: DSkeleton(height: 5),
                            ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    }

    Widget body() => LayoutBuilder(
      builder: (context, constraints) {
        // The phone month keeps natural week heights; wider months fill.
        final height =
            constraints.hasBoundedHeight && layout != EventMonthLayout.compact
            ? math.max(constraints.maxHeight, weeks * minWeek)
            : weeks * minWeek;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: height,
            maxHeight: height,
            child: Column(
              children: [
                for (var week = 0; week < weeks; week++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var day = 0; day < 7; day++)
                          Expanded(child: cell(week, day)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (layout != EventMonthLayout.split) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          weekdays(),
          Expanded(child: body()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(
            end: month.panelWidth + month.panelGap,
          ),
          child: weekdays(),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: body()),
              SizedBox(width: month.panelGap),
              SizedBox(
                width: month.panelWidth,
                child: _dayPanel(tokens, scaler),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayPanel(DTokens tokens, TextScaler scaler) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: tokens.border),
      borderRadius: BorderRadius.circular(tokens.radius),
    ),
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DSkeleton(width: 160, height: scaler.scale(16)),
              const SizedBox(height: 20),
              for (var entry = 0; entry < 4; entry++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      DSkeleton(
                        width: scaler.scale(36),
                        height: scaler.scale(12),
                      ),
                      DSkeleton(width: 3, height: scaler.scale(32)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 8,
                          children: [
                            FractionallySizedBox(
                              alignment: AlignmentDirectional.centerStart,
                              widthFactor: entry.isEven ? .9 : .7,
                              child: DSkeleton(height: scaler.scale(14)),
                            ),
                            FractionallySizedBox(
                              alignment: AlignmentDirectional.centerStart,
                              widthFactor: .55,
                              child: DSkeleton(height: scaler.scale(11)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

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
    final columns = view == EventCalendarView.day ? 1 : 7;
    const rows = 4;
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
                  const Expanded(child: DSkeleton(height: 48)),
              ],
            ),
          ),
      ],
    );
  }
}
