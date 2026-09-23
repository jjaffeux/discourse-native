import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/discourse_typography.dart';

/// A paper-calendar composition of the Native Card used across event surfaces.
class EventDateStamp extends StatelessWidget {
  const EventDateStamp({
    super.key,
    required this.date,
    this.locale,
    this.compact = false,
  });

  final DateTime date;
  final String? locale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Calendar paper and its red binding retain their identity in every palette.
    const red = Color(0xFFB92B32);
    const paper = Color(0xFFFFFFFF);
    const ink = Color(0xFF202124);
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.textScalerOf(context).scale(compact ? 36 : 44),
        ),
        child: DCard(
          spacing: 0,
          border: false,
          borderRadius: BorderRadius.zero,
          backgroundColor: paper,
          leading: ColoredBox(
            color: red,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text(
                DateFormat.MMM(locale).format(date).toUpperCase(),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: paper,
                  height: 1.2,
                ),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Text(
              DateFormat.d(locale).format(date),
              textAlign: TextAlign.center,
              style:
                  (compact
                          ? theme.textTheme.titleMedium?.copyWith(
                              fontSize: DiscourseTypography.lg,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            )
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(color: ink),
            ),
          ),
        ),
      ),
    );
  }
}
