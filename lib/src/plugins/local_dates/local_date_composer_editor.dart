import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'local_date.dart';
import 'local_date_composer_parser.dart';
import 'local_date_environment.dart';

@immutable
class LocalDateComposerValidation {
  const LocalDateComposerValidation(this.errors);

  final List<String> errors;
  bool get isValid => errors.isEmpty;
  String? get firstError => errors.firstOrNull;
}

@immutable
class LocalDateComposerDraft {
  const LocalDateComposerDraft._({
    required this.startDate,
    required this.startTime,
    required this.endDate,
    required this.endTime,
    required this.timezone,
    required this.recurring,
    required this.countdown,
    required this.displayedTimezone,
    required this.calendar,
    required this.previewTimezones,
    required this.format,
    required this.sourceBlock,
    required this._initial,
  });

  factory LocalDateComposerDraft.newDate({
    required DateTime now,
    required String timezone,
  }) => LocalDateComposerDraft._(
    startDate: _date(now),
    startTime: null,
    endDate: null,
    endTime: null,
    timezone: timezone,
    recurring: null,
    countdown: false,
    displayedTimezone: null,
    calendar: null,
    previewTimezones: const [],
    format: null,
    sourceBlock: null,
    initial: null,
  );

  factory LocalDateComposerDraft.fromBlock(LocalDateComposerBlock block) {
    if (!block.canProject) {
      throw ArgumentError.value(
        block.source,
        'block',
        'markup must remain raw',
      );
    }
    final start = _splitDateTime(
      block.kind == LocalDateComposerKind.date
          ? block.attribute('date')!
          : block.attribute('from')!,
    );
    final end = block.kind == LocalDateComposerKind.range
        ? _splitDateTime(block.attribute('to')!)
        : null;
    final values = _LocalDateDraftSnapshot(
      startDate: start.$1,
      startTime: block.kind == LocalDateComposerKind.date
          ? block.attribute('time')
          : start.$2,
      endDate: end?.$1,
      endTime: end?.$2,
      timezone: block.attribute('timezone') ?? 'UTC',
      recurring: block.attribute('recurring'),
      countdown: _truthy(block.attribute('countdown')),
      displayedTimezone: block.attribute('displayedTimezone'),
      calendar: switch (block.attribute('calendar')) {
        'on' => true,
        'off' => false,
        _ => null,
      },
      previewTimezones: List.unmodifiable(
        (block.attribute('timezones') ?? '')
            .split('|')
            .where((zone) => zone.isNotEmpty),
      ),
      format: block.attribute('format'),
    );
    return LocalDateComposerDraft._(
      startDate: values.startDate,
      startTime: values.startTime,
      endDate: values.endDate,
      endTime: values.endTime,
      timezone: values.timezone,
      recurring: values.recurring,
      countdown: values.countdown,
      displayedTimezone: values.displayedTimezone,
      calendar: values.calendar,
      previewTimezones: values.previewTimezones,
      format: values.format,
      sourceBlock: block,
      initial: values,
    );
  }

  final String startDate;
  final String? startTime;
  final String? endDate;
  final String? endTime;
  final String timezone;
  final String? recurring;
  final bool countdown;
  final String? displayedTimezone;
  final bool? calendar;
  final List<String> previewTimezones;
  final String? format;
  final LocalDateComposerBlock? sourceBlock;
  final _LocalDateDraftSnapshot? _initial;

  bool get isNew => sourceBlock == null;
  bool get isRange => endDate != null;

  LocalDateComposerDraft copyWith({
    String? startDate,
    Object? startTime = _unset,
    Object? endDate = _unset,
    Object? endTime = _unset,
    String? timezone,
    Object? recurring = _unset,
    bool? countdown,
    Object? displayedTimezone = _unset,
    Object? calendar = _unset,
    List<String>? previewTimezones,
    Object? format = _unset,
  }) => LocalDateComposerDraft._(
    startDate: startDate ?? this.startDate,
    startTime: startTime == _unset ? this.startTime : startTime as String?,
    endDate: endDate == _unset ? this.endDate : endDate as String?,
    endTime: endTime == _unset ? this.endTime : endTime as String?,
    timezone: timezone ?? this.timezone,
    recurring: recurring == _unset ? this.recurring : recurring as String?,
    countdown: countdown ?? this.countdown,
    displayedTimezone: displayedTimezone == _unset
        ? this.displayedTimezone
        : displayedTimezone as String?,
    calendar: calendar == _unset ? this.calendar : calendar as bool?,
    previewTimezones: List.unmodifiable(
      previewTimezones ?? this.previewTimezones,
    ),
    format: format == _unset ? this.format : format as String?,
    sourceBlock: sourceBlock,
    initial: _initial,
  );

  LocalDateComposerValidation validate({
    Locale locale = const Locale('en'),
    LocalDateFormatter formatter = const LocalDateFormatter(),
  }) {
    final errors = <String>[];
    if (!_validDate(startDate)) errors.add('Choose a valid start date.');
    if (startTime != null && !_validTime(startTime!)) {
      errors.add('Choose a valid start time.');
    }
    if (endDate != null && !_validDate(endDate!)) {
      errors.add('Choose a valid end date.');
    }
    if (endTime != null && (endDate == null || !_validTime(endTime!))) {
      errors.add('An end time needs a valid end date.');
    }
    if (previewTimezones.length > 5) {
      errors.add('Choose at most five preview timezones.');
    }
    final environment = formatter.environment ?? LocalDateEnvironment.instance;
    final zones = [timezone, ?displayedTimezone, ...previewTimezones];
    if (zones.any((zone) => environment.canonicalTimezone(zone) == null)) {
      errors.add('Every timezone must be a valid IANA timezone.');
    }
    if (recurring != null &&
        !RegExp(
          r'^[1-9]\d*\.(years?|quarters?|months?|weeks?|days?|hours?|minutes?|seconds?)$',
        ).hasMatch(recurring!)) {
      errors.add('Recurrence must look like “1.weeks”.');
    }
    if (isRange && (recurring != null || countdown)) {
      errors.add('Ranges cannot recur or use countdown mode.');
    }
    if (errors.isNotEmpty) {
      return LocalDateComposerValidation(List.unmodifiable(errors));
    }
    final start = formatter.resolve(
      LocalDateSpec(
        date: startDate,
        time: startTime,
        timezone: timezone,
        fallbackText: '',
      ),
      locale: locale,
      now: DateTime.fromMillisecondsSinceEpoch(0),
    );
    if (start == null) {
      errors.add('The start time does not exist in that timezone.');
    }
    if (endDate != null) {
      final end = formatter.resolve(
        LocalDateSpec(
          date: endDate!,
          time: endTime,
          timezone: timezone,
          fallbackText: '',
        ),
        locale: locale,
        now: DateTime.fromMillisecondsSinceEpoch(0),
      );
      if (end == null) {
        errors.add('The end time does not exist in that timezone.');
      } else if (start != null && end.source.isBefore(start.source)) {
        errors.add('The end must be after the start.');
      }
    }
    return LocalDateComposerValidation(List.unmodifiable(errors));
  }

  String serialize() {
    final original = sourceBlock;
    if (original != null && _matchesInitial) return original.source;
    final kind = isRange
        ? LocalDateComposerKind.range
        : LocalDateComposerKind.date;
    if (original == null || original.kind != kind) return _serializeCanonical();
    return _serializeEdited(original);
  }

  bool get _matchesInitial {
    final value = _initial;
    return value != null &&
        value.startDate == startDate &&
        value.startTime == startTime &&
        value.endDate == endDate &&
        value.endTime == endTime &&
        value.timezone == timezone &&
        value.recurring == recurring &&
        value.countdown == countdown &&
        value.displayedTimezone == displayedTimezone &&
        value.calendar == calendar &&
        listEquals(value.previewTimezones, previewTimezones) &&
        value.format == format;
  }

  String _serializeCanonical() {
    final unknown = sourceBlock?.attributes.where(
      (attribute) =>
          !localDateAttributeNames.contains(attribute.normalizedName),
    );
    final attributes = <String>[];
    if (isRange) {
      attributes.add('from=${_render(_dateTime(startDate, startTime))}');
      attributes.add('to=${_render(_dateTime(endDate!, endTime))}');
    } else {
      attributes.add('=${_render(startDate)}');
      if (startTime != null) attributes.add('time=${_render(startTime!)}');
    }
    attributes.add('timezone=${_render(timezone)}');
    if (format case final value? when value.isNotEmpty) {
      attributes.add('format=${_render(value)}');
    }
    if (!isRange) {
      if (recurring case final value? when value.isNotEmpty) {
        attributes.add('recurring=${_render(value)}');
      }
    }
    if (previewTimezones.isNotEmpty) {
      attributes.add('timezones=${_render(previewTimezones.join('|'))}');
    }
    if (!isRange && countdown) attributes.add('countdown=true');
    if (displayedTimezone case final value? when value.isNotEmpty) {
      attributes.add('displayedTimezone=${_render(value)}');
    }
    if (calendar != null) {
      attributes.add('calendar=${calendar! ? 'on' : 'off'}');
    }
    final tail = unknown?.map((attribute) => attribute.raw).join() ?? '';
    final tag = isRange ? 'date-range' : 'date';
    final separator = isRange ? ' ' : '';
    return '[$tag$separator${attributes.join(' ')}$tail]';
  }

  String _serializeEdited(LocalDateComposerBlock block) {
    final initial = _initial!;
    String? originalWhen(String name, String? canonical, bool unchanged) =>
        unchanged && block.attribute(name) != null
        ? block.attribute(name)
        : canonical;
    final desired = <String, String?>{
      if (isRange) ...{
        'from': originalWhen(
          'from',
          _dateTime(startDate, startTime),
          initial.startDate == startDate && initial.startTime == startTime,
        ),
        'to': originalWhen(
          'to',
          _dateTime(endDate!, endTime),
          initial.endDate == endDate && initial.endTime == endTime,
        ),
      } else ...{
        'date': originalWhen('date', startDate, initial.startDate == startDate),
        'time': originalWhen('time', startTime, initial.startTime == startTime),
      },
      'timezone': originalWhen(
        'timezone',
        timezone,
        initial.timezone == timezone,
      ),
      'format': originalWhen('format', format, initial.format == format),
      'recurring': isRange
          ? null
          : originalWhen(
              'recurring',
              recurring,
              initial.recurring == recurring,
            ),
      'timezones': originalWhen(
        'timezones',
        previewTimezones.isEmpty ? null : previewTimezones.join('|'),
        listEquals(initial.previewTimezones, previewTimezones),
      ),
      'countdown': isRange || !countdown
          ? null
          : originalWhen('countdown', 'true', initial.countdown == countdown),
      'displayedtimezone': originalWhen(
        'displayedTimezone',
        displayedTimezone,
        initial.displayedTimezone == displayedTimezone,
      ),
      'calendar': originalWhen(
        'calendar',
        calendar == null ? null : (calendar! ? 'on' : 'off'),
        initial.calendar == calendar,
      ),
    };
    final seen = <String>{};
    final rendered = StringBuffer();
    for (final attribute in block.attributes) {
      final key = attribute.normalizedName;
      if (!localDateAttributeNames.contains(key)) {
        rendered.write(attribute.raw);
        continue;
      }
      final replacement = desired[key];
      if (replacement == null) continue;
      rendered.write(attribute.withValue(replacement));
      seen.add(key);
    }
    for (final name in localDateAttributesInWriteOrder) {
      final value = desired[name.toLowerCase()];
      if (value == null || seen.contains(name.toLowerCase())) continue;
      rendered.write(' $name=${_render(value)}');
    }
    return '[${block.tagName}$rendered${block.trailingWhitespace}]';
  }
}

@immutable
class _LocalDateDraftSnapshot {
  const _LocalDateDraftSnapshot({
    required this.startDate,
    required this.startTime,
    required this.endDate,
    required this.endTime,
    required this.timezone,
    required this.recurring,
    required this.countdown,
    required this.displayedTimezone,
    required this.calendar,
    required this.previewTimezones,
    required this.format,
  });

  final String startDate;
  final String? startTime;
  final String? endDate;
  final String? endTime;
  final String timezone;
  final String? recurring;
  final bool countdown;
  final String? displayedTimezone;
  final bool? calendar;
  final List<String> previewTimezones;
  final String? format;
}

const Object _unset = Object();

@immutable
class LocalDateComposerMutation {
  const LocalDateComposerMutation._({
    required this.value,
    required this.applied,
    this.message,
  });

  factory LocalDateComposerMutation.applied(TextEditingValue value) =>
      LocalDateComposerMutation._(value: value, applied: true);

  factory LocalDateComposerMutation.stale(
    TextEditingValue value,
  ) => LocalDateComposerMutation._(
    value: value,
    applied: false,
    message:
        'The composer changed while this date was open. Nothing was changed.',
  );

  final TextEditingValue value;
  final bool applied;
  final String? message;
}

LocalDateComposerMutation replaceVerifiedLocalDate({
  required TextEditingValue current,
  required String expectedDocument,
  required LocalDateComposerBlock expectedBlock,
  required String replacement,
}) {
  if (!_stillContains(current.text, expectedDocument, expectedBlock)) {
    return LocalDateComposerMutation.stale(current);
  }
  final text = current.text.replaceRange(
    expectedBlock.start,
    expectedBlock.end,
    replacement,
  );
  return LocalDateComposerMutation.applied(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: expectedBlock.start + replacement.length,
      ),
    ),
  );
}

LocalDateComposerMutation removeVerifiedLocalDate({
  required TextEditingValue current,
  required String expectedDocument,
  required LocalDateComposerBlock expectedBlock,
}) => replaceVerifiedLocalDate(
  current: current,
  expectedDocument: expectedDocument,
  expectedBlock: expectedBlock,
  replacement: '',
);

LocalDateComposerMutation insertVerifiedLocalDate({
  required TextEditingValue current,
  required String expectedDocument,
  required TextSelection expectedSelection,
  required String markup,
}) {
  if (current.text != expectedDocument) {
    return LocalDateComposerMutation.stale(current);
  }
  final selection = expectedSelection.isValid
      ? expectedSelection
      : TextSelection.collapsed(offset: current.text.length);
  if (selection.start < 0 || selection.end > current.text.length) {
    return LocalDateComposerMutation.stale(current);
  }
  final text = current.text.replaceRange(
    selection.start,
    selection.end,
    markup,
  );
  return LocalDateComposerMutation.applied(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.start + markup.length,
      ),
    ),
  );
}

bool _stillContains(
  String current,
  String expectedDocument,
  LocalDateComposerBlock expected,
) =>
    current == expectedDocument &&
    expected.start >= 0 &&
    expected.end <= current.length &&
    current.substring(expected.start, expected.end) == expected.source &&
    parseLocalDateComposerBlocks(current).any(
      (block) =>
          block.start == expected.start &&
          block.end == expected.end &&
          block.source == expected.source,
    );

(String, String?) _splitDateTime(String value) {
  final split = value.indexOf('T');
  return split == -1
      ? (value, null)
      : (value.substring(0, split), value.substring(split + 1));
}

String _dateTime(String date, String? time) =>
    time == null ? date : '${date}T$time';

bool _truthy(String? value) =>
    value != null && !const {'false', 'off', '0'}.contains(value.toLowerCase());

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

bool _validDate(String value) {
  final parsed = DateTime.tryParse(value);
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      parsed != null &&
      _date(parsed) == value;
}

bool _validTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(value);
  return match != null &&
      int.parse(match.group(1)!) <= 23 &&
      int.parse(match.group(2)!) <= 59 &&
      int.parse(match.group(3) ?? '0') <= 59;
}

String _render(String value) {
  if (value.isNotEmpty && !value.contains(RegExp(r'[\s\]]'))) return value;
  if (!value.contains('"')) return '"$value"';
  if (!value.contains("'")) return "'$value'";
  throw ArgumentError.value(value, 'value', 'cannot be represented safely');
}
