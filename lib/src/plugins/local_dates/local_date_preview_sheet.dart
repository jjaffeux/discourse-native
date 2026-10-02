import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../theme/d_icons.dart';
import 'local_date.dart';

/// The touch preview emphasizes the reader's time, then compares other zones.
class LocalDatePreviewSheet extends StatelessWidget {
  const LocalDatePreviewSheet({
    super.key,
    required this.previews,
    required this.hasTime,
    required this.onClose,
    this.rangeEnd,
    this.rangeEndHasTime = true,
  }) : assert(previews.length > 0);

  final List<LocalDatePreview> previews;
  final bool hasTime;
  final DateTime? rangeEnd;
  final bool rangeEndHasTime;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final local = previews.firstWhere(
      (preview) => preview.current,
      orElse: () => previews.first,
    );
    final others = previews.where((preview) => preview != local).toList();
    final colors = Theme.of(context).colorScheme;
    final tokens = DTokens.of(context);
    final l10n = context.l10n;
    return DDrawerContent(
      semanticLabel: l10n.dateAndTime,
      children: [
        DDrawerHeader(
          textAlign: TextAlign.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DDrawerTitle(
                    child: DText(l10n.dateAndTime, variant: DTextVariant.h4),
                  ),
                ),
                const SizedBox(width: DSpacing.md),
                DButton.iconOnly(
                  onPressed: onClose,
                  size: DButtonSize.small,
                  shape: DButtonShape.pill,
                  variant: DButtonVariant.secondary,
                  icon: const DIcon(DIcons.xmark),
                  tooltip: l10n.close,
                ),
              ],
            ),
          ],
        ),
        DDrawerScrollArea(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DCard(
                key: const ValueKey('local-date-your-time'),
                border: false,
                spacing: 18,
                backgroundColor: Color.alphaBlend(
                  colors.primary.withValues(alpha: .1),
                  tokens.surface,
                ),
                borderRadius: BorderRadius.circular(16),
                children: [
                  DCardContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            DIcon(
                              DIcons.globe,
                              size: 14,
                              color: tokens.primary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: DText(
                                local.label,
                                variant: DTextVariant.small,
                                style: TextStyle(color: tokens.primary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _PreviewValues(
                          preview: local,
                          hasTime: hasTime,
                          rangeEnd: rangeEnd,
                          rangeEndHasTime: rangeEndHasTime,
                          referenceYear: local.value.year,
                          prominent: true,
                        ),
                        if (local.source) ...[
                          const SizedBox(height: 8),
                          DBadge(
                            variant: DBadgeVariant.secondary,
                            size: DBadgeSize.compact,
                            child: Text(l10n.source),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (var index = 0; index < others.length; index++) ...[
                  if (index > 0) const DSeparator(space: 1),
                  _ZoneRow(
                    preview: others[index],
                    local: local,
                    hasTime: hasTime,
                    rangeEnd: rangeEnd,
                    rangeEndHasTime: rangeEndHasTime,
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.preview,
    required this.local,
    required this.hasTime,
    required this.rangeEnd,
    required this.rangeEndHasTime,
  });

  final LocalDatePreview preview;
  final LocalDatePreview local;
  final bool hasTime;
  final DateTime? rangeEnd;
  final bool rangeEndHasTime;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    // Compare civil dates, not elapsed hours: DST days need not be 24h long.
    final days = _calendarDay(
      preview.value,
    ).difference(_calendarDay(local.value)).inDays;
    final dayLabel = switch (days) {
      -1 => l10n.localDatePreviousDay,
      1 => l10n.localDateNextDay,
      < -1 => l10n.localDateDaysEarlier(-days),
      > 1 => l10n.localDateDaysLater(days),
      _ => null,
    };
    final subtitle = [
      if (preview.source) l10n.source,
      preview.timezone == 'Etc/UTC' || preview.timezone == 'UTC'
          ? l10n.localDateUniversalTime
          : preview.value.timeZoneName,
    ].join(' · ');
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DText(
          preview.label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        if (dayLabel == null || preview.source) ...[
          const SizedBox(height: 4),
          DText(
            subtitle,
            variant: DTextVariant.small,
            style: TextStyle(color: tokens.mutedForeground),
          ),
        ],
        if (dayLabel != null) ...[
          const SizedBox(height: 4),
          DBadge(
            variant: DBadgeVariant.secondary,
            size: DBadgeSize.compact,
            backgroundColor: colors.tertiaryContainer,
            foregroundColor: colors.onTertiaryContainer,
            child: Text(dayLabel),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 240 ||
              MediaQuery.textScalerOf(context).scale(14) > 21;
          final values = _PreviewValues(
            preview: preview,
            hasTime: hasTime,
            rangeEnd: rangeEnd,
            rangeEndHasTime: rangeEndHasTime,
            referenceYear: local.value.year,
            alignEnd: !stacked,
          );
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, const SizedBox(height: 8), values],
                )
              : Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 12),
                    Expanded(child: values),
                  ],
                );
        },
      ),
    );
  }
}

class _PreviewValues extends StatelessWidget {
  const _PreviewValues({
    required this.preview,
    required this.hasTime,
    required this.rangeEnd,
    required this.rangeEndHasTime,
    required this.referenceYear,
    this.prominent = false,
    this.alignEnd = false,
  });

  final LocalDatePreview preview;
  final bool hasTime;
  final DateTime? rangeEnd;
  final bool rangeEndHasTime;
  final int referenceYear;
  final bool prominent;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final end = rangeEnd == null
        ? null
        : tz.TZDateTime.from(rangeEnd!, preview.value.location);
    final sameDay =
        end != null && _calendarDay(preview.value) == _calendarDay(end);
    final inlineEnd = sameDay && hasTime && rangeEndHasTime;
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;
    final foreground = DTokens.of(context).foreground;
    Widget date(DateTime value) => DText(
      (prominent
              ? DateFormat.yMMMMEEEEd(locale)
              : value.year != referenceYear
              ? DateFormat.yMMMEd(locale)
              : DateFormat.MMMEd(locale))
          .format(value),
      textAlign: textAlign,
      variant: hasTime ? DTextVariant.small : DTextVariant.paragraph,
      style: TextStyle(color: DTokens.of(context).mutedForeground),
    );
    Widget time(DateTime value) => _TimeLabel(
      value: value,
      prominent: prominent,
      color: foreground,
      textAlign: textAlign,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (hasTime) ...[
          if (inlineEnd)
            Wrap(
              alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [time(preview.value), const Text('→'), time(end)],
            )
          else
            time(preview.value),
          const SizedBox(height: 6),
        ],
        date(preview.value),
        if (end != null && !inlineEnd && (!sameDay || rangeEndHasTime)) ...[
          const SizedBox(height: 10),
          DText(context.l10n.end, variant: DTextVariant.small),
          if (rangeEndHasTime) time(end),
          date(end),
        ],
      ],
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({
    required this.value,
    required this.prominent,
    required this.color,
    required this.textAlign,
  });

  final DateTime value;
  final bool prominent;
  final Color color;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final time = TimeOfDay.fromDateTime(value);
    final hour24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final formatted = l10n.formatTimeOfDay(time, alwaysUse24HourFormat: hour24);
    final period = time.period == DayPeriod.am
        ? l10n.anteMeridiemAbbreviation
        : l10n.postMeridiemAbbreviation;
    final periodIndex = hour24 || period.isEmpty
        ? -1
        : formatted.indexOf(period);
    return DText.rich(
      TextSpan(
        children: periodIndex < 0
            ? [TextSpan(text: formatted)]
            : [
                TextSpan(text: formatted.substring(0, periodIndex)),
                TextSpan(
                  text: period,
                  style: TextStyle(fontSize: prominent ? 18 : 12),
                ),
                TextSpan(
                  text: formatted.substring(periodIndex + period.length),
                ),
              ],
      ),
      textAlign: textAlign,
      style: TextStyle(
        fontSize: prominent ? 44 : 24,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: prominent ? -1 : -.4,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

DateTime _calendarDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);
