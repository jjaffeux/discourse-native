import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'poll_composer_parser.dart';

enum PollResultMode {
  always('always', 'Always visible'),
  onVote('on_vote', 'After voting'),
  onClose('on_close', 'After the poll closes'),
  staffOnly('staff_only', 'Staff only'),
  unknown('', 'Unknown');

  const PollResultMode(this.markupValue, this.label);

  final String markupValue;
  final String label;

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
  bool get typeIsLocked => type == ComposerPollType.rankedChoice;

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
      errors.add('The site poll option limit is unavailable.');
      return PollComposerValidation(List.unmodifiable(errors));
    }
    if (isNew && type == ComposerPollType.rankedChoice) {
      errors.add('Ranked-choice polls can only be created on the web.');
    }
    if (_initial?.type == ComposerPollType.rankedChoice &&
        type != ComposerPollType.rankedChoice) {
      errors.add('The type of an existing ranked-choice poll cannot change.');
    }
    if (type == ComposerPollType.unknown) {
      errors.add('This poll type can only be edited as raw source.');
    }

    if (results == PollResultMode.staffOnly &&
        !isStaff &&
        _initial?.results != PollResultMode.staffOnly) {
      errors.add('Only staff can make poll results staff-only.');
    }

    final closeValue = close.trim();
    if (closeValue.isNotEmpty &&
        DateTime.tryParse(closeValue) == null &&
        close != _initial?.close) {
      errors.add('Automatic close must be a valid ISO-8601 date and time.');
    }

    if (type == ComposerPollType.number) {
      if (minimum < 0) errors.add('Minimum must be zero or greater.');
      if (maximum < minimum) {
        errors.add('Maximum must be greater than or equal to minimum.');
      }
      if (step < 1) errors.add('Step must be at least 1.');
      if (minimum >= 0 && maximum >= minimum && step >= 1) {
        final generated = ((maximum - minimum) ~/ step) + 1;
        if (generated < 2) {
          errors.add('A number poll must generate at least two options.');
        }
        if (generated > maximumOptions) {
          errors.add(
            'A poll can have at most $maximumOptions generated options.',
          );
        }
      }
      return PollComposerValidation(List.unmodifiable(errors));
    }

    final trimmed = options.map((option) => option.trim()).toList();
    if (trimmed.any((option) => option.isEmpty)) {
      errors.add('Every option needs text.');
    }
    if (trimmed.length < 2) {
      errors.add('A poll needs at least two options.');
    }
    if (trimmed.length > maximumOptions) {
      errors.add('A poll can have at most $maximumOptions options.');
    }
    if (trimmed.toSet().length != trimmed.length) {
      errors.add('Poll options must be unique.');
    }

    if (type == ComposerPollType.multiple &&
        !(minimum >= 1 &&
            minimum <= maximum &&
            maximum <= trimmed.length &&
            minimum < trimmed.length)) {
      errors.add(
        'Multiple choice requires 1 ≤ minimum ≤ maximum ≤ option count, '
        'with minimum below the option count.',
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
        'close=${_renderPollAttributeValue(close.trim())}',
    ];
    return _withBody('[poll ${attributes.join(' ')}]', '[/poll]', '\n');
  }

  String _serializeEdited(PollComposerBlock block) {
    final originalClose = _initial?.close;
    final hadCloseAttribute = block.attribute('close') != null;
    final serializedClose = switch (close) {
      final value when value == originalClose && hadCloseAttribute => value,
      final value when value.trim().isNotEmpty => value.trim(),
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

  factory PollComposerMutation.stale(
    TextEditingValue value,
  ) => PollComposerMutation._(
    value: value,
    applied: false,
    message:
        'The composer changed while this poll was open. Nothing was changed.',
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
  final followingLineBreakLength = keepFollowingLine
      ? _leadingLineBreakLength('$suffix$after')
      : 0;
  assert(!keepFollowingLine || followingLineBreakLength > 0);
  return PollComposerMutation.applied(
    TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset:
            expectedBlock.start + replacement.length + followingLineBreakLength,
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
  final followingLineBreakLength = _leadingLineBreakLength('$suffix$after');
  assert(followingLineBreakLength > 0);
  return PollComposerMutation.applied(
    TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset:
            before.length +
            prefix.length +
            markup.length +
            followingLineBreakLength,
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

int _leadingLineBreakLength(String source) {
  if (source.isEmpty) return 0;
  if (source.codeUnitAt(0) == 0x0A) return 1;
  return source.length > 1 &&
          source.codeUnitAt(0) == 0x0D &&
          source.codeUnitAt(1) == 0x0A
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
