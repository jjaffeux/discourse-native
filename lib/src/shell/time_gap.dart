import 'package:flutter/material.dart';

/// Whole 24-hour periods between two stream entries, matching Discourse web's
/// `Math.floor((time2 - time1) / DAY_MS)` for chronologically ordered dates.
int? timeGapDaysBetween(DateTime? earlier, DateTime? later) {
  if (earlier == null || later == null) return null;
  return later.difference(earlier).inDays;
}

/// Discourse web's elapsed-time wording and unit boundaries.
String timeGapLabel(int daysSince) {
  assert(daysSince >= 0);
  if (daysSince < 30) {
    return '$daysSince ${daysSince == 1 ? 'day' : 'days'} later';
  }
  if (daysSince < 365) {
    final months = (daysSince / 30).round();
    return '$months ${months == 1 ? 'month' : 'months'} later';
  }
  final years = (daysSince / 365).round();
  return '$years ${years == 1 ? 'year' : 'years'} later';
}

/// The small, muted elapsed-time row immediately before a post or message.
///
/// Both native streams use the same 42px avatar gutter, so one inset lines the
/// text up with their bodies just as web's empty `.topic-avatar` column does.
class TimeGapNotice extends StatelessWidget {
  const TimeGapNotice({super.key, required this.daysSince});

  static const double height = 40;

  final int daysSince;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(left: 58, right: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            timeGapLabel(daysSince),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
