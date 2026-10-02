import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'poll_composer_parser.dart';

enum PollResultMode {
  always('always'),
  onVote('on_vote'),
  onClose('on_close'),
  staffOnly('staff_only'),
  unknown('');

  const PollResultMode(this.markupValue);

  final String markupValue;
  String get label => switch (this) {
    always => appL10n.alwaysVisible,
    onVote => appL10n.afterVoting,
    onClose => appL10n.afterThePollCloses,
    staffOnly => appL10n.staffOnly,
    unknown => appL10n.unknown,
  };

  static PollResultMode parse(String? value) => switch (value) {
    null || '' || 'always' => always,
    'on_vote' => onVote,
    'on_close' => onClose,
    'staff_only' => staffOnly,
    _ => unknown,
  };
}

@immutable
class PollComposerValidation {
  const PollComposerValidation(this.errors);

  final List<String> errors;

  bool get isValid => errors.isEmpty;
  String? get firstError => errors.firstOrNull;
}

@immutable
class PollComposerDraft {
  const PollComposerDraft._({
    required this.name,
    required this.title,
    required this.type,
    required this.options,
    required this.minimum,
    required this.maximum,
    required this.step,
    required this.results,
    required this.resultsSource,
    required this.publicVoters,
    required this.close,
    required this.sourceBlock,
    required this._initial,
  });

  factory PollComposerDraft.newPoll({
    required String name,
    required bool defaultPublic,
  }) => PollComposerDraft._(
    name: name,
    title: '',
    type: ComposerPollType.regular,
    options: const ['', ''],
    minimum: 1,
    maximum: 2,
    step: 1,
    results: PollResultMode.always,
    resultsSource: PollResultMode.always.markupValue,
    publicVoters: defaultPublic,
    close: '',
    sourceBlock: null,
    initial: null,
  );

  factory PollComposerDraft.fromBlock(
    PollComposerBlock block, {
    int maximumOptions = 20,
  }) {
    if (!block.canProject) {
      throw ArgumentError.value(
        block.type,
        'block',
        'unknown poll types must remain raw source',
      );
    }

    final type = block.type;
    final options = List<String>.unmodifiable(block.optionSources);
    final minimum = _integer(block.attribute('min')) ?? 1;
    final maximum =
        _integer(block.attribute('max')) ??
        switch (type) {
          ComposerPollType.number => maximumOptions,
          _ => options.length,
        };
    final resultsSource = block.attribute('results') ?? 'always';
    final values = _PollDraftSnapshot(
      name: block.name,
      title: block.titleSource ?? '',
      type: type,
      options: options,
      minimum: minimum,
      maximum: maximum,
      step: _integer(block.attribute('step')) ?? 1,
      results: PollResultMode.parse(resultsSource),
      resultsSource: resultsSource,
      publicVoters: block.attribute('public') == 'true',
      close: block.attribute('close') ?? '',
    );
    return PollComposerDraft._(
      name: values.name,
      title: values.title,
      type: values.type,
      options: values.options,
      minimum: values.minimum,
      maximum: values.maximum,
      step: values.step,
      results: values.results,
      resultsSource: values.resultsSource,
      publicVoters: values.publicVoters,
      close: values.close,
      sourceBlock: block,
      initial: values,
    );
  }

  final String name;
  final String title;
  final ComposerPollType type;
  final List<String> options;
  final int minimum;
  final int maximum;
  final int step;
  final PollResultMode results;

  /// Retains an unknown future results policy while editing other fields.
  final String resultsSource;
  final bool publicVoters;

  final String close;
  final PollComposerBlock? sourceBlock;
  final _PollDraftSnapshot? _initial;

  bool get isNew => sourceBlock == null;

  String get effectiveResultsValue =>
      results == PollResultMode.unknown ? resultsSource : results.markupValue;

  PollComposerDraft copyWith({
    String? title,
    ComposerPollType? type,
    List<String>? options,
    int? minimum,
    int? maximum,
    int? step,
    PollResultMode? results,
    String? resultsSource,
    bool? publicVoters,
    String? close,
  }) => PollComposerDraft._(
    name: name,
    title: title ?? this.title,
    type: type ?? this.type,
    options: List.unmodifiable(options ?? this.options),
    minimum: minimum ?? this.minimum,
    maximum: maximum ?? this.maximum,
    step: step ?? this.step,
    results: results ?? this.results,
    resultsSource: resultsSource ?? this.resultsSource,
    publicVoters: publicVoters ?? this.publicVoters,
    close: close ?? this.close,
    sourceBlock: sourceBlock,
    initial: _initial,
  );

  PollComposerValidation validate({
    required int maximumOptions,
    required bool isStaff,
  }) {
    final errors = <String>[];
    if (maximumOptions < 1) {
      errors.add(appL10n.theSitePollOptionLimitIsUnavailable);
      return PollComposerValidation(List.unmodifiable(errors));
    }
    if (isNew && type == ComposerPollType.rankedChoice) {
      errors.add(appL10n.rankedChoicePollsCanOnlyBeCreatedOnTheWeb);
    }
    if (_initial?.type == ComposerPollType.rankedChoice &&
        type != ComposerPollType.rankedChoice) {
      errors.add(appL10n.theTypeOfAnExistingRankedChoicePollCannotChange);
    }
    if (type == ComposerPollType.unknown) {
      errors.add(appL10n.thisPollTypeCanOnlyBeEditedAsRawSource);
    }

    if (results == PollResultMode.staffOnly &&
        !isStaff &&
        _initial?.results != PollResultMode.staffOnly) {
      errors.add(appL10n.onlyStaffCanMakePollResultsStaffOnly);
    }

    final closeValue = close.trim();
    if (close != _initial?.close &&
        closeValue.isNotEmpty &&
        !_validCloseComponents(closeValue)) {
      errors.add(appL10n.automaticCloseMustBeAValidISO8601DateAndTime);
    }

    if (type == ComposerPollType.number) {
      if (minimum < 0) errors.add(appL10n.minimumMustBeZeroOrGreater);
      if (maximum < minimum) {
        errors.add(appL10n.maximumMustBeGreaterThanOrEqualToMinimum);
      }
      if (step < 1) errors.add(appL10n.stepMustBeAtLeast1);
      if (minimum >= 0 && maximum >= minimum && step >= 1) {
        final generated = ((maximum - minimum) ~/ step) + 1;
        if (generated < 2) {
          errors.add(appL10n.aNumberPollMustGenerateAtLeastTwoOptions);
        }
        if (generated > maximumOptions) {
          errors.add(
            appL10n.aPollCanHaveAtMostGeneratedOptions(
              (maximumOptions).toString(),
            ),
          );
        }
      }
      return PollComposerValidation(List.unmodifiable(errors));
    }

    final trimmed = options.map((option) => option.trim()).toList();
    if (trimmed.any((option) => option.isEmpty)) {
      errors.add(appL10n.everyOptionNeedsText);
    }
    if (trimmed.length < 2) {
      errors.add(appL10n.aPollNeedsAtLeastTwoOptions);
    }
    if (trimmed.length > maximumOptions) {
      errors.add(
        appL10n.aPollCanHaveAtMostOptions((maximumOptions).toString()),
      );
    }
    if (trimmed.toSet().length != trimmed.length) {
      errors.add(appL10n.pollOptionsMustBeUnique);
    }

    if (type == ComposerPollType.multiple &&
        !(minimum >= 1 &&
            minimum <= maximum &&
            maximum <= trimmed.length &&
            minimum < trimmed.length)) {
      errors.add(
        appL10n
            .multipleChoiceRequires1MinimumMaximumOptionCountWithMinimumBelow,
      );
    }
    return PollComposerValidation(List.unmodifiable(errors));
  }

  /// Returns the original source when an edit is a semantic no-op.
  String serialize() {
    final original = sourceBlock;
    if (original != null && _matchesInitial) return original.source;
    if (original == null) return _serializeNew();
    return _serializeEdited(original);
  }

  bool get _matchesInitial {
    final starting = _initial;
    return starting != null &&
        name == starting.name &&
        title == starting.title &&
        type == starting.type &&
        listEquals(options, starting.options) &&
        minimum == starting.minimum &&
        maximum == starting.maximum &&
        step == starting.step &&
        results == starting.results &&
        resultsSource == starting.resultsSource &&
        publicVoters == starting.publicVoters &&
        close == starting.close;
  }

  String _serializeNew() {
    final attributes = <String>[
      'name=$name',
      'type=${type.markupValue}',
      'status=open',
      'results=$effectiveResultsValue',
      if (type == ComposerPollType.multiple ||
          type == ComposerPollType.number) ...[
        'min=$minimum',
        'max=$maximum',
      ],
      if (type == ComposerPollType.number) 'step=$step',
      'public=$publicVoters',
      'chartType=bar',
      if (close.trim().isNotEmpty)
        'close=${_renderPollAttributeValue(_closeMarkupValue(close))}',
    ];
    return _withBody('[poll ${attributes.join(' ')}]', '[/poll]', '\n');
  }

  String _serializeEdited(PollComposerBlock block) {
    final originalClose = _initial?.close;
    final hadCloseAttribute = block.attribute('close') != null;
    final serializedClose = switch (close) {
      final value when value == originalClose && hadCloseAttribute => value,
      final value when value.trim().isNotEmpty => _closeMarkupValue(value),
      _ => null,
    };
    final desired = <String, String>{
      'name': name,
      'type': type.markupValue,
      'results': effectiveResultsValue,
      'public': '$publicVoters',
      if (type == ComposerPollType.multiple ||
          type == ComposerPollType.number) ...{
        'min': '$minimum',
        'max': '$maximum',
      },
      if (type == ComposerPollType.number) 'step': '$step',
      'close': ?serializedClose,
    };
    final removed = <String>{
      if (type != ComposerPollType.multiple &&
          type != ComposerPollType.number) ...[
        'min',
        'max',
      ],
      if (type != ComposerPollType.number) 'step',
      if (serializedClose == null) 'close',
    };

    final seen = <String>{};
    final attributes = StringBuffer();
    for (final attribute in block.attributes) {
      final key = attribute.normalizedName;
      if (removed.contains(key)) continue;
      final replacement = desired[key];
      attributes.write(
        replacement == null ? attribute.raw : attribute.withValue(replacement),
      );
      if (replacement != null) seen.add(key);
    }
    for (final key in const [
      'name',
      'type',
      'results',
      'min',
      'max',
      'step',
      'public',
      'close',
    ]) {
      final value = desired[key];
      if (value != null && !seen.contains(key)) {
        attributes.write(' $key=${_renderPollAttributeValue(value)}');
      }
    }

    final opener =
        '${block.openingIndent}[poll$attributes'
        '${block.attributeTrailingWhitespace}]'
        '${block.openingTrailingWhitespace}';
    final closer =
        '${block.closingIndent}[/poll]${block.closingTrailingWhitespace}';
    return _withBody(opener, closer, block.lineEnding);
  }

  String _withBody(String opener, String closer, String lineEnding) {
    final body = <String>[opener];
    final indent = sourceBlock?.openingIndent ?? '';
    if (title.trim().isNotEmpty) body.add('$indent# ${title.trim()}');
    if (type != ComposerPollType.number) {
      for (final option in options) {
        body.add('$indent* ${option.trim()}');
      }
    }
    body.add(closer);
    return body.join(lineEnding);
  }
}

@immutable
class _PollDraftSnapshot {
  const _PollDraftSnapshot({
    required this.name,
    required this.title,
    required this.type,
    required this.options,
    required this.minimum,
    required this.maximum,
    required this.step,
    required this.results,
    required this.resultsSource,
    required this.publicVoters,
    required this.close,
  });

  final String name;
  final String title;
  final ComposerPollType type;
  final List<String> options;
  final int minimum;
  final int maximum;
  final int step;
  final PollResultMode results;
  final String resultsSource;
  final bool publicVoters;
  final String close;
}

int? _integer(String? value) => value == null ? null : int.tryParse(value);

bool _validCloseComponents(String value) {
  if (DateTime.tryParse(value) == null) return false;
  final parts = _closeComponents.firstMatch(value);
  if (parts == null) return false;
  int component(int group) => int.parse(parts.group(group) ?? '0');
  final year = component(1);
  final month = component(2);
  final day = component(3);
  final hour = component(4);
  final minute = component(5);
  final second = component(6);
  final fraction = parts.group(7);
  if (month < 1 || month > 12) return false;
  final daysInMonth = switch (month) {
    2 => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };
  // Dart normalizes overflowing components. Keep ISO's end-of-day and leap
  // second forms, which Discourse's parser also accepts, but reject typos.
  return day >= 1 &&
      day <= daysInMonth &&
      hour <= 24 &&
      minute <= 59 &&
      second <= 60 &&
      (hour != 24 ||
          minute == 0 &&
              second == 0 &&
              (fraction == null || !fraction.contains(RegExp('[1-9]')))) &&
      component(8) <= 23 &&
      component(9) <= 59;
}

final _closeComponents = RegExp(
  r'^([+-]?\d{4,6})-?(\d{2})-?(\d{2})'
  r'(?:[ T](\d{2})(?::?(\d{2})(?::?(\d{2})(?:[.,](\d+))?)?)?'
  r'(?: ?[zZ]| ?[+-](\d{2})(?::?(\d{2}))?)?)?$',
);

/// Discourse parses a close value without an offset as UTC, but the web
/// composer's picker and the poll card both work in device-local time. An
/// offset-less entry therefore means local time and is written with the
/// device's offset at that moment; an explicit offset is kept as entered.
String _closeMarkupValue(String entered) {
  final value = entered.trim();
  final local = DateTime.tryParse(value);
  if (local == null || local.isUtc) return value;

  var wallTime = local.toIso8601String();
  if (wallTime.endsWith('.000')) {
    wallTime = wallTime.substring(0, wallTime.length - 4);
  }
  final offset = local.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '$wallTime${offset.isNegative ? '-' : '+'}'
      '${twoDigits(minutes ~/ 60)}:${twoDigits(minutes % 60)}';
}

String _renderPollAttributeValue(String value) {
  if (value.isNotEmpty && !value.contains(RegExp(r'''[\s\]]'''))) {
    return value;
  }
  if (!value.contains('"')) return '"$value"';
  if (!value.contains("'")) return "'$value'";
  throw ArgumentError.value(value, 'value', 'cannot be represented safely');
}

/// Inserts a separator before text added at a projected poll boundary. One
/// formatter transaction preserves IME and undo behavior.
class PollComposerInputFormatter extends TextInputFormatter {
  const PollComposerInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return newValue;

    final oldSelection = oldValue.selection;
    if (!oldSelection.isValid ||
        oldSelection.start > oldValue.text.length ||
        oldSelection.end > oldValue.text.length) {
      return newValue;
    }
    final selectedLength = oldSelection.end - oldSelection.start;
    final insertedLength =
        newValue.text.length - (oldValue.text.length - selectedLength);
    final shiftedStart = oldSelection.start + insertedLength;
    if (insertedLength < 0 ||
        shiftedStart > newValue.text.length ||
        newValue.text.substring(0, oldSelection.start) !=
            oldValue.text.substring(0, oldSelection.start) ||
        newValue.text.substring(shiftedStart) !=
            oldValue.text.substring(oldSelection.end)) {
      return newValue;
    }

    PollComposerBlock? poll;
    for (final block in parsePollComposerBlocks(oldValue.text)) {
      if (block.start == oldSelection.end && block.canProject) {
        poll = block;
        break;
      }
    }
    if (poll == null) return newValue;

    if (shiftedStart == 0 ||
        newValue.text.codeUnitAt(shiftedStart - 1) == 0x0A) {
      if (shiftedStart > 0 &&
          newValue.selection.isCollapsed &&
          newValue.selection.extentOffset == shiftedStart) {
        final breakLength =
            shiftedStart > 1 &&
                newValue.text.codeUnitAt(shiftedStart - 2) == 0x0D
            ? 2
            : 1;
        return newValue.copyWith(
          selection: TextSelection.collapsed(
            offset: shiftedStart - breakLength,
            affinity: newValue.selection.affinity,
          ),
        );
      }
      return newValue;
    }

    var separator = poll.lineEnding;
    var caretOverride = -1;
    if (newValue.text.codeUnitAt(shiftedStart - 1) == 0x0D) {
      separator = '\n';
      if (newValue.selection.isCollapsed &&
          newValue.selection.extentOffset == shiftedStart) {
        caretOverride = shiftedStart - 1;
      }
    }

    int shiftedOffset(int offset) =>
        offset > shiftedStart ? offset + separator.length : offset;
    final selection = caretOverride >= 0
        ? TextSelection.collapsed(
            offset: caretOverride,
            affinity: newValue.selection.affinity,
          )
        : newValue.selection.isValid
        ? TextSelection(
            baseOffset: shiftedOffset(newValue.selection.baseOffset),
            extentOffset: shiftedOffset(newValue.selection.extentOffset),
            affinity: newValue.selection.affinity,
            isDirectional: newValue.selection.isDirectional,
          )
        : newValue.selection;
    final composing = newValue.composing.isValid
        ? TextRange(
            start: shiftedOffset(newValue.composing.start),
            end: shiftedOffset(newValue.composing.end),
          )
        : newValue.composing;

    return newValue.copyWith(
      text: newValue.text.replaceRange(shiftedStart, shiftedStart, separator),
      selection: selection,
      composing: composing,
    );
  }
}

@immutable
class PollComposerMutation {
  const PollComposerMutation._({
    required this.value,
    required this.applied,
    this.message,
  });

  factory PollComposerMutation.applied(TextEditingValue value) =>
      PollComposerMutation._(value: value, applied: true);

  factory PollComposerMutation.stale(TextEditingValue value) =>
      PollComposerMutation._(
        value: value,
        applied: false,
        message:
            appL10n.theComposerChangedWhileThisPollWasOpenNothingWasChanged,
      );

  final TextEditingValue value;
  final bool applied;
  final String? message;
}

/// Refuses replacement if the captured source block changed under the sheet.
PollComposerMutation replaceVerifiedPoll({
  required TextEditingValue current,
  required String expectedDocument,
  required PollComposerBlock expectedBlock,
  required String replacement,
}) => _replaceVerifiedPoll(
  current: current,
  expectedDocument: expectedDocument,
  expectedBlock: expectedBlock,
  replacement: replacement,
  keepFollowingLine: true,
);

PollComposerMutation _replaceVerifiedPoll({
  required TextEditingValue current,
  required String expectedDocument,
  required PollComposerBlock expectedBlock,
  required String replacement,
  required bool keepFollowingLine,
}) {
  if (!_stillContainsExpectedBlock(
    current.text,
    expectedDocument,
    expectedBlock,
  )) {
    return PollComposerMutation.stale(current);
  }
  final after = current.text.substring(expectedBlock.end);
  final lineEnding = _documentLineEnding(current.text);
  final suffix = keepFollowingLine && after.isEmpty ? lineEnding : '';
  final next = current.text.replaceRange(
    expectedBlock.start,
    expectedBlock.end,
    '$replacement$suffix',
  );
  final followingGapLength = keepFollowingLine
      ? _followingGapLength('$suffix$after')
      : 0;
  assert(!keepFollowingLine || followingGapLength > 0);
  return PollComposerMutation.applied(
    TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: expectedBlock.start + replacement.length + followingGapLength,
      ),
    ),
  );
}

PollComposerMutation removeVerifiedPoll({
  required TextEditingValue current,
  required String expectedDocument,
  required PollComposerBlock expectedBlock,
}) => _replaceVerifiedPoll(
  current: current,
  expectedDocument: expectedDocument,
  expectedBlock: expectedBlock,
  replacement: '',
  keepFollowingLine: false,
);

bool _stillContainsExpectedBlock(
  String current,
  String expectedDocument,
  PollComposerBlock expectedBlock,
) {
  if (current != expectedDocument ||
      expectedBlock.start < 0 ||
      expectedBlock.end > current.length ||
      expectedBlock.start >= expectedBlock.end ||
      current.substring(expectedBlock.start, expectedBlock.end) !=
          expectedBlock.source) {
    return false;
  }
  return parsePollComposerBlocks(current).any(
    (block) =>
        block.start == expectedBlock.start &&
        block.end == expectedBlock.end &&
        block.source == expectedBlock.source,
  );
}

/// Keeps one real line ending after an EOF poll so subsequent typing cannot
/// corrupt `[/poll]`.
PollComposerMutation insertVerifiedPoll({
  required TextEditingValue current,
  required String expectedDocument,
  required TextSelection expectedSelection,
  required String markup,
}) {
  if (current.text != expectedDocument) {
    return PollComposerMutation.stale(current);
  }

  final selection = expectedSelection.isValid
      ? expectedSelection
      : TextSelection.collapsed(offset: current.text.length);
  if (selection.start < 0 || selection.end > current.text.length) {
    return PollComposerMutation.stale(current);
  }
  final before = current.text.substring(0, selection.start);
  final after = current.text.substring(selection.end);
  final lineEnding = _documentLineEnding(current.text);
  final prefix = _blankLinePrefix(before, lineEnding);
  final suffix = _blankLineSuffix(after, lineEnding);
  final insertion = '$prefix$markup$suffix';
  final next = '$before$insertion$after';
  final followingGapLength = _followingGapLength('$suffix$after');
  assert(followingGapLength > 0);
  return PollComposerMutation.applied(
    TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset:
            before.length + prefix.length + markup.length + followingGapLength,
      ),
    ),
  );
}

String _documentLineEnding(String source) =>
    source.contains('\r\n') ? '\r\n' : '\n';

String _blankLinePrefix(String before, String lineEnding) {
  if (before.isEmpty || _endsWithLineBreaks(before, 2)) return '';
  return _endsWithLineBreaks(before, 1) ? lineEnding : '$lineEnding$lineEnding';
}

String _blankLineSuffix(String after, String lineEnding) {
  if (after.isEmpty) return lineEnding;
  if (_startsWithLineBreaks(after, 2)) return '';
  return _startsWithLineBreaks(after, 1)
      ? lineEnding
      : '$lineEnding$lineEnding';
}

/// The composer draws the blank line between a poll and the next block as
/// structural spacing that cannot hold a caret, so the caret after a poll
/// passes the poll's own line break and that blank line, landing where the
/// next block starts. Text typed inside the gap would join the next block.
int _followingGapLength(String source) {
  var cursor = 0;
  for (var lineBreaks = 0; lineBreaks < 2; lineBreaks++) {
    final length = _lineBreakLengthAt(source, cursor);
    if (length == 0) break;
    cursor += length;
  }
  return cursor;
}

int _lineBreakLengthAt(String source, int offset) {
  if (offset >= source.length) return 0;
  if (source.codeUnitAt(offset) == 0x0A) return 1;
  return offset + 1 < source.length &&
          source.codeUnitAt(offset) == 0x0D &&
          source.codeUnitAt(offset + 1) == 0x0A
      ? 2
      : 0;
}

bool _endsWithLineBreaks(String source, int count) {
  var cursor = source.length;
  for (var found = 0; found < count; found++) {
    if (cursor == 0 || source.codeUnitAt(cursor - 1) != 0x0A) return false;
    cursor--;
    if (cursor > 0 && source.codeUnitAt(cursor - 1) == 0x0D) cursor--;
  }
  return true;
}

bool _startsWithLineBreaks(String source, int count) {
  var cursor = 0;
  for (var found = 0; found < count; found++) {
    if (cursor < source.length && source.codeUnitAt(cursor) == 0x0D) cursor++;
    if (cursor >= source.length || source.codeUnitAt(cursor) != 0x0A) {
      return false;
    }
    cursor++;
  }
  return true;
}
