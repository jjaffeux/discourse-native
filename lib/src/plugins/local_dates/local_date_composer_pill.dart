import 'package:flutter/material.dart';

import '../../shell/pill.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'local_date.dart';
import 'local_date_composer_editor.dart';
import 'local_date_composer_parser.dart';

const TextStyle _hiddenDateSource = TextStyle(
  color: Colors.transparent,
  fontSize: 0,
  height: 0,
  letterSpacing: 0,
  wordSpacing: 0,
);

String localDateComposerSummary(
  LocalDateComposerBlock block, {
  required Locale locale,
  String? accountTimezone,
  LocalDateFormatter formatter = const LocalDateFormatter(),
}) {
  try {
    final draft = LocalDateComposerDraft.fromBlock(block);
    LocalDateResolved? resolve(String date, String? time) => formatter.resolve(
      LocalDateSpec(
        date: date,
        time: time,
        timezone: draft.timezone,
        format: draft.format,
        calendar: draft.calendar,
        recurring: draft.recurring,
        countdown: draft.countdown,
        displayedTimezone: draft.displayedTimezone,
        timezones: draft.previewTimezones,
        fallbackText: block.source,
      ),
      locale: locale,
      accountTimezone: accountTimezone,
    );

    final start = resolve(draft.startDate, draft.startTime);
    if (start == null) return block.source;
    if (!draft.isRange) return start.formatted;
    final end = resolve(draft.endDate!, draft.endTime);
    if (end == null) return block.source;
    final sameDay =
        start.displayed.year == end.displayed.year &&
        start.displayed.month == end.displayed.month &&
        start.displayed.day == end.displayed.day;
    final endText = sameDay && draft.endTime != null
        ? LocalDateFormatter.formatMoment(end.displayed, 'LT', locale)
        : end.formatted;
    return '${start.formatted} → $endText';
  } on Object {
    return block.source;
  }
}

List<InlineSpan> buildCollapsedLocalDateSpans({
  required LocalDateComposerBlock block,
  required TextStyle baseStyle,
  required Locale locale,
  String? accountTimezone,
  Key? pillKey,
  bool highlighted = false,
}) {
  final source = block.source;
  if (source.isEmpty) return const [];
  final spans = <InlineSpan>[];
  final visibleAt = source.length - 1;
  var textStart = 0;
  for (var offset = 0; offset < visibleAt; offset++) {
    final codeUnit = source.codeUnitAt(offset);
    if (codeUnit != 0x0A && codeUnit != 0x0D) continue;
    if (textStart < offset) {
      spans.add(
        TextSpan(
          text: source.substring(textStart, offset),
          style: _hiddenDateSource,
        ),
      );
    }
    spans.add(
      const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox.shrink(),
      ),
    );
    textStart = offset + 1;
  }
  if (textStart < visibleAt) {
    spans.add(
      TextSpan(
        text: source.substring(textStart, visibleAt),
        style: _hiddenDateSource,
      ),
    );
  }
  final label = localDateComposerSummary(
    block,
    locale: locale,
    accountTimezone: accountTimezone,
  );
  spans.add(
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      style: baseStyle,
      child: LocalDateComposerPill(
        key: pillKey,
        label: label,
        baseStyle: baseStyle,
        highlighted: highlighted,
      ),
    ),
  );
  assert(
    TextSpan(
          children: spans,
        ).toPlainText(includeSemanticsLabels: false).length ==
        source.length,
    'the local-date projection drifted from its source range',
  );
  return spans;
}

class LocalDateComposerPill extends StatelessWidget {
  const LocalDateComposerPill({
    super.key,
    required this.label,
    required this.baseStyle,
    this.highlighted = false,
  });

  final String label;
  final TextStyle baseStyle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label. Activate to edit.',
    button: true,
    selected: highlighted,
    child: Pill(
      label: label,
      baseStyle: baseStyle,
      hoverable: true,
      highlighted: highlighted,
      leading: DIcon(DIcons.farClock, size: Pill.iconBoxFor(baseStyle)),
    ),
  );
}

bool localDateBlockNeedsRawSource({
  required LocalDateComposerBlock block,
  required TextEditingValue value,
  bool suppressCollapsedCaret = false,
}) {
  final composing = value.isComposingRangeValid
      ? value.composing
      : TextRange.empty;
  if (_overlap(block.start, block.end, composing.start, composing.end)) {
    return true;
  }
  final selection = value.selection;
  if (!selection.isValid) return false;
  if (selection.isCollapsed) {
    if (selection.extentOffset == block.start ||
        selection.extentOffset == block.end) {
      return false;
    }
    return !suppressCollapsedCaret &&
        block.containsOffset(selection.extentOffset);
  }
  return _overlap(block.start, block.end, selection.start, selection.end);
}

bool _overlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;
