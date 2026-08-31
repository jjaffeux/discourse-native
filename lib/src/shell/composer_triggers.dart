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
    ComposerTriggerKind.mention => 1,
    ComposerTriggerKind.hashtag => 1,
    ComposerTriggerKind.emoji => 2,
  };

  int get maximum => switch (this) {
    ComposerTriggerKind.mention => 30,
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

  // The caret has to be at the end of the run. Clicking back into a word
  // already written is reading, and a completion accepted there would splice
  // itself into the middle of it.
  if (caret < text.length && _isName(text[caret])) return null;

  // Walk back over anything either kind would accept, then look at what
  // stopped us. Which characters are allowed depends on a kind that is not
  // known until the sigil is found, so the run is checked again below.
  var start = caret;
  while (start > 0 && _isName(text[start - 1])) {
    start--;
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
    while (scan > 0 && (_isName(text[scan - 1]) || text[scan - 1] == ':')) {
      scan--;
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
  if (sigil > 0 && !_opensWord(text[sigil - 1])) return null;

  final query = text.substring(start, caret);
  for (var index = 0; index < query.length; index++) {
    if (!kind.accepts(query[index])) return null;
  }

  if (query.length < kind.minimum || query.length > kind.maximum) return null;

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

final RegExp _mentionCharacter = RegExp(r'[A-Za-z0-9_.-]');
final RegExp _hashtagCharacter = RegExp(r'[A-Za-z0-9_:.-]');
final RegExp _emojiCharacter = RegExp(r'[A-Za-z0-9_+-]');
final RegExp _nameCharacter = RegExp(r'[A-Za-z0-9_.+-]');
final RegExp _wordOpeningCharacter = RegExp(r'''[\s([{<"'`]''');
