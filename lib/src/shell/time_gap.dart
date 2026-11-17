import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import 'small_action.dart';

export '../foundation/elapsed_time.dart' show timeGapDaysBetween;

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

/// A long pause before a post, said as the thread's other small notes are,
/// so the post after it reads as coming back to the topic.
class TimeGapNotice extends StatelessWidget {
  const TimeGapNotice({super.key, required this.daysSince});

  final int daysSince;

  @override
  Widget build(BuildContext context) =>
      SmallActionLine(icon: DIcons.clock, said: timeGapLabel(daysSince));
}

/// Where the reader left off, said above the first post they have not read:
/// what is below came after their last visit.
class LastVisitNotice extends StatelessWidget {
  const LastVisitNotice({super.key, this.count});

  /// The posts from here to the topic's end, when the stream says.
  final int? count;

  @override
  Widget build(BuildContext context) => SmallActionLine(
    icon: DIcons.envelopeOpen,
    tone: Theme.of(context).colorScheme.primary,
    said: context.l10n.newSinceLastVisit,
    semanticLabel: context.l10n.newSinceLastVisit,
    more: switch (count) {
      final count? when count > 0 => Text(
        context.l10n.newSinceLastVisitPosts(count),
      ),
      _ => null,
    },
  );
}
