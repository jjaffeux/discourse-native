import 'package:flutter/widgets.dart';

enum ComposerTriggerKind {
  mention('@'),
  hashtag('#'),
  emoji(':');

  const ComposerTriggerKind(this.sigil);

  final String sigil;

  bool accepts(String character) => switch (this) {
    ComposerTriggerKind.mention => _mentionCharacter.hasMatch(character),
    ComposerTriggerKind.hashtag => _hashtagCharacter.hasMatch(character),
    ComposerTriggerKind.emoji => _emojiCharacter.hasMatch(character),
  };

  int get minimum => switch (this) {
    ComposerTriggerKind.mention => 0,
    ComposerTriggerKind.hashtag => 1,
    ComposerTriggerKind.emoji => 1,
  };

  int get maximum => switch (this) {
    // Core caps usernames at 60 scalars even when combining marks make fewer
    // visible characters. This also bounds group-name lookup terms.
    ComposerTriggerKind.mention => 60,
    // Core's own cap on a hashtag ref.
    ComposerTriggerKind.hashtag => 101,
    ComposerTriggerKind.emoji => 30,
  };
}

@immutable
class ComposerTrigger {
  const ComposerTrigger({
    required this.kind,
    required this.query,
    required this.start,
    required this.end,
  });

  final ComposerTriggerKind kind;

  final String query;

  final int start;

  final int end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComposerTrigger &&
          other.kind == kind &&
          other.query == query &&
          other.start == start &&
          other.end == end);

  @override
  int get hashCode => Object.hash(kind, query, start, end);

  @override
  String toString() => '${kind.sigil}$query @$start..$end';
}

const int runMaximum = 128;

ComposerTrigger? composerTriggerAt(TextEditingValue value) {
  final selection = value.selection;
  // A range is somebody selecting text, not somebody typing a name.
  if (!selection.isValid || !selection.isCollapsed) return null;

  final text = value.text;
  final caret = selection.baseOffset;
  if (caret < 0 || caret > text.length) return null;
  if (caret > 0 &&
      caret < text.length &&
      _isHighSurrogate(text.codeUnitAt(caret - 1)) &&
      _isLowSurrogate(text.codeUnitAt(caret))) {
    return null;
  }

  // The caret has to be at the end of the run. Clicking back into a word
  // already written is reading, and a completion accepted there would splice
  // itself into the middle of it.
  if (caret < text.length && _isName(_characterAt(text, caret))) return null;

  // Walk back over anything either kind would accept, then look at what
  // stopped us. Which characters are allowed depends on a kind that is not
  // known until the sigil is found, so the run is checked again below.
  var start = caret;
  while (start > 0) {
    final previous = _previousCharacterStart(text, start);
    if (!_isName(text.substring(previous, start))) break;
    start = previous;
    if (caret - start > runMaximum) return null;
  }

  var sigil = start - 1;
  if (sigil < 0) return null;

  var kind = switch (text[sigil]) {
    '@' => ComposerTriggerKind.mention,
    '#' => ComposerTriggerKind.hashtag,
    ':' => ComposerTriggerKind.emoji,
    _ => null,
  };
  if (kind == null) return null;

  // `#parent:child` initially looks like emoji `:child`; scan through colons
  // to recover the full hashtag ref. Emoji names cannot contain colons.
  if (kind == ComposerTriggerKind.emoji) {
    var scan = sigil;
    while (scan > 0) {
      final previous = _previousCharacterStart(text, scan);
      final character = text.substring(previous, scan);
      if (!_isName(character) && character != ':') break;
      scan = previous;
      if (caret - scan > runMaximum) break;
    }
    if (scan > 0 && text[scan - 1] == '#') {
      kind = ComposerTriggerKind.hashtag;
      start = scan;
      sigil = scan - 1;
    }
  }

  // A sigil has to start a word. This one rule does every job: it is what
  // keeps `me@example.com` from completing a username, what keeps the closing
  // colon of a finished `:smile:` from opening another list, and what keeps
  // `##foo` and `a#b` from opening one at all.
  if (sigil > 0 &&
      !_opensWord(
        text.substring(_previousCharacterStart(text, sigil), sigil),
      )) {
    return null;
  }

  final query = text.substring(start, caret);
  for (final rune in query.runes) {
    if (!kind.accepts(String.fromCharCode(rune))) return null;
  }

  final queryLength = kind == ComposerTriggerKind.mention
      ? query.runes.length
      : query.length;
  if (queryLength < kind.minimum || queryLength > kind.maximum) return null;

  return ComposerTrigger(kind: kind, query: query, start: sigil, end: caret);
}

TextEditingValue applyComposerCompletion(
  TextEditingValue value,
  ComposerTrigger trigger,
  String replacement,
) {
  final text = value.text;
  final followed = trigger.end < text.length && text[trigger.end] == ' ';

  final written = switch (trigger.kind) {
    ComposerTriggerKind.mention => '@$replacement',
    // The caller supplies a `ref`, never a slug — `parent:child`, `name::tag`
    // — because that is the only form that survives a subcategory or two
    // things sharing a name, and it is what the site cooks against.
    ComposerTriggerKind.hashtag => '#$replacement',
    ComposerTriggerKind.emoji => ':$replacement:',
  };
  final inserted = followed ? written : '$written ';
  final caret = trigger.start + inserted.length + (followed ? 1 : 0);

  return TextEditingValue(
    text: text.replaceRange(trigger.start, trigger.end, inserted),
    selection: TextSelection.collapsed(offset: caret),
  );
}

bool _isName(String character) => _nameCharacter.hasMatch(character);

bool _opensWord(String character) => _wordOpeningCharacter.hasMatch(character);

// Selection and replacement ranges use UTF-16 offsets, but name characters
// must be tested as complete Unicode scalars.
int _previousCharacterStart(String text, int end) {
  final previous = end - 1;
  return previous > 0 &&
          _isLowSurrogate(text.codeUnitAt(previous)) &&
          _isHighSurrogate(text.codeUnitAt(previous - 1))
      ? previous - 1
      : previous;
}

String _characterAt(String text, int start) {
  final end = start + 1;
  return text.substring(
    start,
    end < text.length &&
            _isHighSurrogate(text.codeUnitAt(start)) &&
            _isLowSurrogate(text.codeUnitAt(end))
        ? end + 1
        : end,
  );
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

const _unicodeName = r'\p{Alphabetic}\p{Mark}\p{Decimal_Number}';
final RegExp _mentionCharacter = RegExp('[${_unicodeName}_.-]', unicode: true);
final RegExp _hashtagCharacter = RegExp('[${_unicodeName}_:.-]', unicode: true);
final RegExp _emojiCharacter = RegExp(r'[A-Za-z0-9_+-]');
final RegExp _nameCharacter = RegExp('[${_unicodeName}_.+-]', unicode: true);
final RegExp _wordOpeningCharacter = RegExp(r'''[\s([{<"'`]''');
