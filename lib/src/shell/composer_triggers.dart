import 'package:flutter/widgets.dart';

/// What someone has started typing that a list could finish.
///
/// The sigil is part of the enum for the same reason [ComposerMark] carries its
/// marker: what `@` means is a fact about mentions, not something the popup
/// should be told separately.
enum ComposerTriggerKind {
  mention('@'),
  hashtag('#'),
  emoji(':');

  const ComposerTriggerKind(this.sigil);

  final String sigil;

  /// What may follow the sigil. A mention allows the dots and hyphens
  /// Discourse allows in a username; a hashtag allows the colons that name a
  /// subcategory (`#parent:child`) or settle a collision (`#name::tag`); an
  /// emoji name allows the `+` of `:+1:` but never a colon, which is what
  /// stops a finished `:smile:` from reading as the start of another one.
  bool accepts(String character) => switch (this) {
    ComposerTriggerKind.mention => _mentionCharacter.hasMatch(character),
    ComposerTriggerKind.hashtag => _hashtagCharacter.hasMatch(character),
    ComposerTriggerKind.emoji => _emojiCharacter.hasMatch(character),
  };

  /// Enough typed for the answer to be worth asking for.
  ///
  /// One character for a person or a place, because `@j` and `#s` already
  /// narrow a site to something worth reading. Two for an emoji, because a
  /// single `:` is ordinary punctuation and every "Note: " in a reply would
  /// otherwise open a list.
  int get minimum => switch (this) {
    ComposerTriggerKind.mention => 1,
    ComposerTriggerKind.hashtag => 1,
    ComposerTriggerKind.emoji => 2,
  };

  /// Longer than any of these can be. A paragraph typed without a space is
  /// none of them, and is not worth sending to the site as a query.
  int get maximum => switch (this) {
    ComposerTriggerKind.mention => 30,
    // Core's own cap on a hashtag ref.
    ComposerTriggerKind.hashtag => 101,
    ComposerTriggerKind.emoji => 30,
  };
}

/// A trigger that is open, and what accepting a suggestion would replace.
@immutable
class ComposerTrigger {
  const ComposerTrigger({
    required this.kind,
    required this.query,
    required this.start,
    required this.end,
  });

  final ComposerTriggerKind kind;

  /// What has been typed after the sigil, without it.
  final String query;

  /// Where the sigil is.
  final int start;

  /// The caret. `[start, end)` is what a completion writes over.
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

/// How far back the walk will look before giving up.
///
/// Not what *refuses* a run — [ComposerTriggerKind.maximum] does that, per
/// kind, once the kind is known. This only stops the scan from reading the
/// length of a long paragraph on every keystroke.
const int runMaximum = 128;

/// The trigger the caret is sitting in, or null.
///
/// Pure, so what counts as a trigger is testable without a widget — the same
/// bargain `toggleMarkdownMark` makes. Every rule here exists to *refuse*: the
/// cost of a missed trigger is one more keystroke, and the cost of a false one
/// is a list covering the reply while someone writes an email address.
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

  // A colon is the one character two kinds share, and the walk cannot tell
  // them apart on its own: it stops there, leaving `#parent:child` looking
  // like an emoji called `child`. So when a colon stopped it, keep going —
  // over colons as well as names — and if a `#` opens the whole run, this was
  // a hashtag all along.
  //
  // Only in that direction. An emoji name may not contain a colon, so nothing
  // a `#` starts can be mistaken for one, and `:smile:` is untouched.
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

/// Writes [replacement] over [trigger], sigils and all.
///
/// The trailing space is what makes typing straight on work, and is not added
/// when there is already one there — accepting mid-sentence must not push the
/// words apart. The caret lands after it either way.
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

/// What a name may be made of. Also what decides where a run *ends*: a caret
/// with one of these after it is in the middle of a word.
bool _isName(String character) => _nameCharacter.hasMatch(character);

/// What may sit immediately before a sigil.
///
/// Whitespace, and the punctuation someone opens a parenthetical with — `(@sam
/// said so)` is a mention. Deliberately not a letter or a digit, which is the
/// whole of what stops `me@example.com` completing a username and what stops
/// the second colon of `:smile:` opening a list of its own.
bool _opensWord(String character) => _wordOpeningCharacter.hasMatch(character);

final RegExp _mentionCharacter = RegExp(r'[A-Za-z0-9_.-]');
final RegExp _hashtagCharacter = RegExp(r'[A-Za-z0-9_:.-]');
final RegExp _emojiCharacter = RegExp(r'[A-Za-z0-9_+-]');
final RegExp _nameCharacter = RegExp(r'[A-Za-z0-9_.+-]');
final RegExp _wordOpeningCharacter = RegExp(r'''[\s([{<"'`]''');
