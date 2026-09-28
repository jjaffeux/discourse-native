import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

int? timeGapDaysBetween(DateTime? earlier, DateTime? later) {
  if (earlier == null || later == null) return null;
  return later.difference(earlier).inDays;
}

String timeGapLabel(int daysSince) {
  assert(daysSince >= 0);
  if (daysSince < 30) {
    return appL10n.later(daysSince);
  }
  if (daysSince < 365) {
    final months = (daysSince / 30).round();
    return appL10n.laterTimegap(months);
  }
  final years = (daysSince / 365).round();
  return appL10n.laterTimegapValue(years);
}

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
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
