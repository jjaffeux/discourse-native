/// Finds what each character of markdown source means, without changing any of
/// it.
///
/// The composer posts raw markdown, so the field's text *is* the payload. A
/// document model over it has to convert both ways and cannot do so without
/// loss — that is what took the rich editor out. Nothing here converts
/// anything: it reports how each character should be *drawn*, and the text goes
/// to the site exactly as it was typed.
library;

import 'package:flutter/foundation.dart';

import 'syntax.dart';

/// What can be true of one character at once.
///
/// A bitmask per character rather than a tree of spans. Nesting is then free —
/// `***x***` is bold and italic on the same character, and a mark that opens
/// inside another needs no bracket matching — and the runs that fall out of it
/// cannot overlap, which is the shape `TextSpan.children` wants.
abstract final class Md {
  /// The syntax itself: the `**`, the `#`, the backticks, the `](`. Drawn
  /// dimmed rather than hidden, because hiding it is where a WYSIWYG editor
  /// starts lying about what will be posted.
  static const int marker = 1 << 0;

  static const int bold = 1 << 1;
  static const int italic = 1 << 2;
  static const int strikethrough = 1 << 3;

  /// Between backticks, on one line.
  static const int code = 1 << 4;

  /// Inside a ``` fence. Carries the highlight.js scope in
  /// [MarkdownRun.detail], where the highlighter had an opinion.
  static const int codeBlock = 1 << 5;

  /// Text of a `#` line. The level is in [MarkdownRun.detail].
  static const int heading = 1 << 6;

  /// Text of a `>` line.
  static const int quote = 1 << 7;

  /// The `text` half of `[text](url)`.
  static const int linkText = 1 << 8;

  /// The `url` half, and a bare URL written on its own.
  static const int linkUrl = 1 << 9;

  /// An `@someone`. The username is in [MarkdownRun.token].
  static const int mention = 1 << 10;

  /// A `:shortcode:`.
  static const int emoji = 1 << 11;

  /// Between one of [allowedInlineTags]. The tag is in [MarkdownRun.detail].
  static const int htmlTag = 1 << 12;

  /// A `#category` or `#tag`. The ref — sigil stripped — is in
  /// [MarkdownRun.token].
  static const int hashtag = 1 << 13;
}

/// The inline HTML tags Discourse keeps when it cooks a post.
///
/// Taken from the web client's `ALLOWED_INLINE`
/// (`static/prosemirror/extensions/html-inline.js`). Writing `<kbd>` in a post
/// works, so the composer draws it as what it will become rather than as
/// literal angle brackets.
const Set<String> allowedInlineTags = {
  'kbd',
  'sup',
  'sub',
  'mark',
  'small',
  'big',
  'ins',
  'del',
};

/// A stretch of source characters that are all marked the same way.
///
/// Half-open, and always contiguous: concatenating every run's text gives back
/// the source exactly. That is the property the composer depends on — the
/// painted text and the posted text are the same string.
@immutable
class MarkdownRun {
  const MarkdownRun(this.start, this.end, this.mask, [this.detail, this.token]);

  final int start;
  final int end;
  final int mask;

  /// Identity a flag alone cannot carry: the tag for [Md.htmlTag], the
  /// heading level for [Md.heading], the highlight.js scope inside a fence.
  ///
  /// Set by whatever *encloses* a character.
  final String? detail;

  /// The name of the inline token this run **is** — the `smile` of a
  /// `:smile:`, the `sam` of an `@sam`.
  ///
  /// A second slot rather than a second use of [detail], because the two are
  /// written by passes that legitimately overlap: `<kbd>` claims everything
  /// inside it while a shortcode within it claims its own name, and one shared
  /// slot means whichever pass runs last silently wins. That is not
  /// hypothetical — it is why `<kbd>:smile:</kbd>` drew without its monospace
  /// chip, and why a mention could not carry a username without flattening
  /// `###### @sam` to a level-one heading.
  final String? token;

  int get length => end - start;

  bool has(int flag) => mask & flag != 0;

  @override
  String toString() => '[$start,$end) ${mask.toRadixString(2)} $detail $token';
}

/// A fence body the scan left as plain code instead of tokenizing.
///
/// The receiver owes the fence a later `highlightLines(body, language)` — that
/// warms the cache in `syntax.dart` — and a rescan, after which the same fence
/// tokenizes synchronously.
typedef DeferredFenceHighlight = void Function(String body, String? language);

/// At or under this many characters, a fence body is tokenized synchronously
/// even when the caller offered to defer.
///
/// A small block parses in well under a frame, and deferring it would flash
/// plain code where the highlight used to be immediate.
const int maxSynchronousFenceChars = 512;

/// Which parts of a scanned document are code, in order and merged.
///
/// Every parser reading composer source has to ignore what code contains — a
/// `[quote` inside a fence opens nothing, an `![alt](...)` inside one is not an
/// image — and each of them was deriving that from the same scan, as its own
/// list, and then asking it one candidate at a time by walking the whole list.
///
/// Both halves of that are worth owning here. A scan emits a run per change of
/// style, so a highlighted fence is one run per token: merging the adjacent
/// ones turns hundreds of ranges into one. And a document with many candidates
/// asked the question many times, which made the walk the product of the two —
/// a post full of images, or a paste full of brackets, paid for its own size
/// twice over.
final class CodeRanges {
  const CodeRanges._(this._starts, this._ends);

  factory CodeRanges.of(List<MarkdownRun> runs) {
    final starts = <int>[];
    final ends = <int>[];
    for (final run in runs) {
      if (!run.has(Md.code) && !run.has(Md.codeBlock)) continue;
      // Runs are ordered and contiguous, so a neighbour extends in place.
      if (ends.isNotEmpty && ends.last == run.start) {
        ends[ends.length - 1] = run.end;
      } else {
        starts.add(run.start);
        ends.add(run.end);
      }
    }
    return CodeRanges._(starts, ends);
  }

  static const CodeRanges none = CodeRanges._([], []);

  final List<int> _starts;
  final List<int> _ends;

  bool get isEmpty => _starts.isEmpty;

  int get length => _starts.length;

  /// The merged ranges, ascending, for a caller that walks all of them rather
  /// than asking about one offset.
  Iterable<(int, int)> get ranges sync* {
    for (var index = 0; index < _starts.length; index += 1) {
      yield (_starts[index], _ends[index]);
    }
  }

  /// Whether the character at [offset] is code.
  bool contains(int offset) => overlaps(offset, offset + 1);

  /// Whether `[start, end)` meets any code at all.
  bool overlaps(int start, int end) {
    if (_starts.isEmpty || end <= start) return false;
    // The last range opening at or before [start] is the only earlier one that
    // can still be open there; the first one after it is the only later one
    // that can begin before [end].
    var low = 0;
    var high = _starts.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_starts[middle] <= start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low > 0 && _ends[low - 1] > start) return true;
    return low < _starts.length && _starts[low] < end;
  }
}

/// The stretches of [source] an inline construct may live inside.
///
/// A mark cannot span a paragraph break — an unclosed `*` at the end of one
/// paragraph would otherwise reach forward and italicise everything down to
/// the next asterisk anywhere in the post — and it cannot span anything named
/// in [excluding], which is how a fence is kept out: a fence ends the
/// paragraph around it, and it is the one construct that routinely holds
/// thousands of characters with no blank line in them.
///
/// Every boundary falls on a newline or an end of [source], so a rule about
/// the character outside a delimiter reads the same one it would have read had
/// the whole document been a single block.
List<({int offset, String text})> markdownBlocks(
  String source, {
  Iterable<(int, int)> excluding = const [],
}) {
  final breaks = <(int, int)>[
    ...excluding,
    for (final match in _paragraphBreakPattern.allMatches(source))
      (match.start, match.end),
  ]..sort((left, right) => left.$1.compareTo(right.$1));

  final blocks = <({int offset, String text})>[];
  void add(int start, int end) {
    blocks.add((offset: start, text: source.substring(start, end)));
  }

  var start = 0;
  for (final (breakStart, breakEnd) in breaks) {
    if (breakStart > start) add(start, breakStart);
    if (breakEnd > start) start = breakEnd;
  }
  if (start < source.length) add(start, source.length);
  return blocks;
}

final RegExp _paragraphBreakPattern = RegExp(r'\n\s*\n');

/// Where [delimiter] pairs up inside [text], leftmost and shortest first.
///
/// Markdown's emphasis rules: a non-space against the inside of each
/// delimiter, at least one character between them, and — with [wordBounded],
/// which is the underscore's — a word boundary on the outside of each, so that
/// `snake_case_name` stays a name.
///
/// [spokenFor] is asked about a delimiter's first character and skips it when
/// something already owns that offset — a code span, or the backslash that
/// escapes it. Skipping rather than rejecting afterwards is what matters:
/// a pair that is found and then refused has already consumed its closer, and
/// the emphasis after it loses one.
///
/// A scan rather than `allMatches` of a lazy pattern, because the two disagree
/// about what an unclosed delimiter costs. The pattern has to walk to the end
/// of [text] before it can report that an opener has no closer, and has to do
/// it again for the next opener, and the one after that. This knows something
/// the engine cannot: the closers after a later opener are a subset of the
/// closers after an earlier one, so the first opener to run out of them is the
/// last one worth trying. On a block with no blank line in it — which is what
/// a pasted stack trace is — that is linear against quadratic.
Iterable<(int, int)> markdownPairs(
  String text,
  String delimiter, {
  bool wordBounded = false,
  bool Function(int offset)? spokenFor,
}) sync* {
  final width = delimiter.length;
  var cursor = 0;
  while (cursor + width * 2 < text.length) {
    final open = _nextOpener(text, delimiter, cursor, wordBounded, spokenFor);
    if (open < 0) return;
    final close = _nextCloser(
      text,
      delimiter,
      open + width + 1,
      wordBounded,
      spokenFor,
    );
    if (close < 0) return;
    cursor = close + width;
    yield (open, cursor);
  }
}

/// The first place at or after [from] where [delimiter] could open a mark:
/// followed by a non-space, and for the word-bounded rule not preceded by a
/// word character.
int _nextOpener(
  String text,
  String delimiter,
  int from,
  bool wordBounded,
  bool Function(int offset)? spokenFor,
) {
  final width = delimiter.length;
  for (
    var at = text.indexOf(delimiter, from);
    at >= 0;
    at = text.indexOf(delimiter, at + 1)
  ) {
    if (at + width >= text.length) return -1;
    if (_isWhitespace(text.codeUnitAt(at + width))) continue;
    if (wordBounded && at > 0 && _isWordCharacter(text.codeUnitAt(at - 1))) {
      continue;
    }
    if (_insideLongerRun(text, delimiter, at)) continue;
    if (spokenFor != null && spokenFor(at)) continue;
    return at;
  }
  return -1;
}

/// The first place at or after [from] where [delimiter] could close a mark:
/// preceded by a non-space, and for the word-bounded rule not followed by a
/// word character.
///
/// [from] is past an opener and its one character of content, so it is never
/// zero and the preceding character is always there to read.
int _nextCloser(
  String text,
  String delimiter,
  int from,
  bool wordBounded,
  bool Function(int offset)? spokenFor,
) {
  final width = delimiter.length;
  for (
    var at = text.indexOf(delimiter, from);
    at >= 0;
    at = text.indexOf(delimiter, at + 1)
  ) {
    if (_isWhitespace(text.codeUnitAt(at - 1))) continue;
    if (wordBounded &&
        at + width < text.length &&
        _isWordCharacter(text.codeUnitAt(at + width))) {
      continue;
    }
    if (_insideLongerRun(text, delimiter, at)) continue;
    if (spokenFor != null && spokenFor(at)) continue;
    return at;
  }
  return -1;
}

/// Whether a one-character delimiter at [at] is really part of a longer run.
///
/// Markdown matches delimiters by run, not by character: `a ** b ** c` is two
/// runs of two, neither of which can open or close because of the spaces
/// against them, and taking one asterisk out of each gave a pair that
/// italicised a sentence the site leaves alone. The longer delimiters run
/// first and close what they took, so anything still adjacent to its own
/// character here is a run no pass above was able to use.
///
/// Only for a one-character delimiter: the ladder above `*` and `_` is what
/// answers for the longer runs, and `~~` has none.
bool _insideLongerRun(String text, String delimiter, int at) {
  if (delimiter.length != 1) return false;
  final unit = delimiter.codeUnitAt(0);
  if (at > 0 && text.codeUnitAt(at - 1) == unit) return true;
  return at + 1 < text.length && text.codeUnitAt(at + 1) == unit;
}

/// `\s` as Dart's regexps read it, so the scan agrees with the passes that are
/// still written as patterns.
bool _isWhitespace(int unit) =>
    unit == 0x20 ||
    (unit >= 0x09 && unit <= 0x0D) ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

/// The characters a backslash may escape, which is every ASCII punctuation
/// mark and nothing else — a backslash before a letter, a digit or a line
/// ending is a literal backslash.
bool _isAsciiPunctuation(int unit) =>
    (unit >= 0x21 && unit <= 0x2F) ||
    (unit >= 0x3A && unit <= 0x40) ||
    (unit >= 0x5B && unit <= 0x60) ||
    (unit >= 0x7B && unit <= 0x7E);

/// `[\w_]`, which is `\w`: the underscore is already in it.
bool _isWordCharacter(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x5F;

/// Reads [source] and reports how to draw it.
///
/// Pure, so the fiddly part — what counts as a marker and what is just an
/// asterisk — is testable without pumping a widget, the same bargain
/// `toggleMarkdownMark` makes.
///
/// [deferHighlight] takes fence tokenization off the caller's frame. Typing
/// inside a fence changes its body on every keystroke, so the highlight cache
/// misses every time and the parser reruns over the whole block — milliseconds
/// per key on a large one. With the callback set, a fence body longer than
/// [maxSynchronousFenceChars] whose parse is not already cached is reported
/// instead of tokenized, and its runs come back as unscoped [Md.codeBlock] —
/// plain code styling, never unstyled text. Without it, every fence is
/// tokenized in place, exactly as callers with no repaint path require.
List<MarkdownRun> scanMarkdown(
  String source, {
  DeferredFenceHighlight? deferHighlight,
}) {
  if (source.isEmpty) return const [];

  final scan = _Scan(source, deferHighlight);
  scan.blocks();
  scan.inlines();
  return scan.runs();
}

/// The masks being built up, one slot per character.
class _Scan {
  _Scan(this.source, this._deferHighlight)
    : mask = List<int>.filled(source.length, 0),
      detail = List<String?>.filled(source.length, null),
      tokens = List<String?>.filled(source.length, null),
      _closed = List<bool>.filled(source.length, false),
      _escaped = List<bool>.filled(source.length, false);

  final String source;
  final DeferredFenceHighlight? _deferHighlight;
  final List<int> mask;
  final List<String?> detail;

  /// See [MarkdownRun.token]. Kept apart from [detail] so an enclosing
  /// construct and the token inside it can both be remembered.
  final List<String?> tokens;

  /// Characters no further pass may claim. Code is the whole reason this
  /// exists: `` `**x**` `` is four literal asterisks, not bold.
  final List<bool> _closed;

  /// Characters a backslash made literal, which is a *narrower* claim than
  /// [_closed] — see [_escapes] for which passes it binds and why.
  final List<bool> _escaped;

  /// Offsets a run may never span.
  ///
  /// Runs are otherwise collapsed by what is true of each character, which
  /// would merge `:smile::smile:` into one — and something drawing a picture
  /// per run would then draw one picture over two shortcodes.
  final Set<int> _cuts = {};

  /// Fenced regions, in order, recorded by [blocks] for [_emphasisBlocks].
  ///
  /// A fence ends the paragraph around it, so no mark reaches across one. That
  /// is not merely a nicety here: a fence is the one construct that routinely
  /// holds thousands of characters with no blank line in them.
  final List<(int, int)> _fences = [];

  // A scan runs on every text change. Keep the compiled expressions with the
  // scanner type rather than rebuilding them for every line and every pass.
  static final RegExp _headingPattern = RegExp(r'^(#{1,6})(\s+)');
  static final RegExp _quotePattern = RegExp(r'^(>+)(\s?)');
  static final RegExp _linkAddressPattern = RegExp(r'[^)\s]*\)');
  static final RegExp _bareUrlPattern = RegExp(r'https?://[^\s<>\[\]()]+');

  /// Transcribed from core's own `mentionRegex`
  /// (`frontend/pretty-text/addon/mentions.js`), which is what decides whether
  /// the site will cook this as a mention at all — the ASCII branch, since the
  /// unicode-username one is not implemented here either.
  ///
  /// The tail is the part worth naming: a name may not *end* in a dot, a dash
  /// or an underscore, so `thanks @sam.` mentions `sam`. Reading the period as
  /// part of the name asked the site about `sam.`, was told no, and drew no
  /// pill on a mention the post really has — which is how most sentences that
  /// end in one are written. The second alternative is core's, for the
  /// one-character name the first cannot express.
  static final RegExp _mentionPattern = RegExp(
    r'@(\w[\w.-]{0,58}[^\W_])|@(\w)',
  );
  static final RegExp _hashtagPattern = RegExp(
    r'(?<!/)#([\wÀ-῿Ⰰ-퟿:-]'
    r'(?:[\wÀ-῿Ⰰ-퟿:.-]{0,99}'
    r'[\wÀ-῿Ⰰ-퟿:-])?)',
  );

  /// Core's `MAX_NAME_LENGTH` is 60 and it refuses a name that reaches it, so
  /// fifty-nine is the longest one it will draw. The class is this app's own
  /// and narrower than core's, which takes anything up to the next colon and
  /// lets the emoji lookup refuse it.
  static final RegExp _emojiPattern = RegExp(
    r':([a-z0-9_+-]{1,59}(?::t[1-6])?):',
  );
  static final RegExp _boundaryPattern = RegExp(r'[\w@#./-]');

  void _mark(int start, int end, int flag, [String? note]) {
    for (var i = start; i < end && i < source.length; i++) {
      mask[i] |= flag;
      if (note != null) detail[i] = note;
    }
  }

  /// [_mark], plus the name of the token the range *is*.
  ///
  /// Separate from [_mark]'s `note` because that writes [detail], which
  /// belongs to whatever encloses these characters — see [MarkdownRun.token].
  void _markToken(int start, int end, int flag, String token) {
    _mark(start, end, flag);
    for (var i = start; i < end && i < source.length; i++) {
      tokens[i] = token;
    }
  }

  /// Adds a tag to a span that may already be inside another one, so
  /// `<mark>look <kbd>here</kbd></mark>` keeps both rather than the inner
  /// overwriting the outer. Outermost first, which is the order they nest in.
  void _addTag(int start, int end, String tag) {
    for (var i = start; i < end && i < source.length; i++) {
      mask[i] |= Md.htmlTag;
      final already = detail[i];
      detail[i] = already == null ? tag : '$already,$tag';
    }
  }

  void _close(int start, int end) {
    for (var i = start; i < end && i < source.length; i++) {
      _closed[i] = true;
    }
  }

  bool _free(int start, int end) {
    for (var i = start; i < end && i < source.length; i++) {
      if (_closed[i]) return false;
    }
    return true;
  }

  /// Fences, headings and quote markers — everything decided by which line a
  /// character is on rather than by what surrounds it.
  void blocks() {
    var offset = 0;
    var bodyStart = -1;
    var fenceStart = -1;
    _Fence? openingFence;
    String? language;

    for (final line in source.split('\n')) {
      final end = offset + line.length;
      final fence = _fenceAt(line);

      if (bodyStart >= 0) {
        // Inside a fence: only its own closing line ends it.
        if (fence != null && fence.closes(openingFence!)) {
          _mark(offset, end, Md.marker);
          _close(offset, end);
          _highlightFence(bodyStart, offset, language);
          _fences.add((fenceStart, end));
          bodyStart = -1;
          fenceStart = -1;
          openingFence = null;
          language = null;
        }
      } else if (fence != null) {
        _mark(offset, end, Md.marker);
        _close(offset, end);
        openingFence = fence;
        language = fence.info.isEmpty ? null : fence.info;
        fenceStart = offset;
        bodyStart = end + 1;
      } else {
        _lineBlock(offset, line);
      }

      offset = end + 1;
    }

    // An unterminated fence still reads as code while it is being typed —
    // refusing to draw it until the closing ``` is there would flicker the
    // whole block in as someone finishes the line.
    if (bodyStart >= 0) {
      _highlightFence(bodyStart, source.length, language);
      _fences.add((fenceStart, source.length));
    }
  }

  /// Headings and blockquotes, which claim a marker and then leave the rest of
  /// the line to the inline pass.
  void _lineBlock(int offset, String line) {
    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      _mark(offset, offset + heading.end, Md.marker);
      _close(offset, offset + heading.end);
      _mark(offset + heading.end, offset + line.length, Md.heading, '$level');
      return;
    }

    final quote = _quotePattern.firstMatch(line);
    if (quote != null) {
      _mark(offset, offset + quote.end, Md.marker);
      _close(offset, offset + quote.end);
      _mark(offset + quote.end, offset + line.length, Md.quote);
    }
  }

  /// Tokenises a fence's contents so code in the composer reads the way it
  /// will read in the post.
  void _highlightFence(int start, int end, String? language) {
    if (start >= end || start >= source.length) return;
    final body = source.substring(start, end.clamp(start, source.length));

    _mark(start, start + body.length, Md.codeBlock);
    _close(start, start + body.length);

    // Only a body whose parse would actually run may be deferred: a cached or
    // plain-path body costs a split, and skipping it would flash plain code on
    // every scan a *different* part of the source triggered.
    if (_deferHighlight case final defer?
        when body.length > maxSynchronousFenceChars &&
            highlightNeedsParse(body, language)) {
      defer(body, language);
      return;
    }

    var at = start;
    for (final tokens in highlightLines(body, language)) {
      for (final token in tokens) {
        if (token.scope != null) {
          _mark(at, at + token.text.length, Md.codeBlock, token.scope);
        }
        at += token.text.length;
      }
      // The newline `highlightLines` split on.
      at += 1;
    }
  }

  /// Everything decided by what surrounds a character rather than by its line.
  ///
  /// Order is the whole design: code closes what it covers, so a marker inside
  /// it is left as the literal character it is, and emphasis runs last so it
  /// cannot eat a URL's underscores or a shortcode's colons.
  void inlines() {
    final blocks = _blocks();
    // Before the escapes, and it has to be: a backslash inside a code span is
    // a literal backslash, so the span has to be claimed before anything can
    // read one as syntax. `_codeSpans` has its own escape rule for the
    // backticks that delimit it.
    _inlineCode(blocks);
    _escapes();
    for (final block in blocks) {
      _htmlTags(block.text, block.offset);
    }
    _links();
    _bareUrls();
    _mentions();
    // After `_bareUrls`, so `https://x.com/a#top` keeps its fragment rather
    // than growing a hashtag inside it — core's `(?<!/)` alone does not cover
    // a fragment that follows something other than a slash. Before
    // `_emphasis`, so `#a_b_c` keeps its underscores.
    _hashtags();
    _emoji();
    _emphasis(blocks);
  }

  /// Records each `\x`, so the passes a backslash really protects can decline
  /// to read the `x` as syntax.
  ///
  /// A backslash before ASCII punctuation makes that character literal, and
  /// the composer was drawing several such characters as markup the site cooks
  /// as themselves. But it protects *some* of what this scan finds and not
  /// all of it, and the difference is where in Discourse's pipeline each thing
  /// is decided.
  ///
  /// Emphasis, links, code spans and inline HTML are markdown-it's own inline
  /// rules, and the escape has already consumed the character by the time they
  /// run. Mentions, hashtags and emoji are Discourse's, added through
  /// `textPostProcess`, which `pretty-text/text-replace.js` runs over the
  /// **text tokens of the finished inline pass** — by which point `\@sam` is
  /// the text `@sam` and matches. So the site draws that mention, and so does
  /// this. The backslash is dimmed either way, because markdown-it consumed it
  /// and the post does not show it.
  ///
  /// Recorded only where the offsets are free, which is what keeps it out of a
  /// fenced block and a code span: a backslash in either is a backslash, and
  /// the reader is shown it. [_inlineCode] answers for its own delimiters in
  /// [_backtickRuns], since it runs before this.
  void _escapes() {
    var index = 0;
    while (index + 1 < source.length) {
      if (source.codeUnitAt(index) != 0x5C ||
          !_isAsciiPunctuation(source.codeUnitAt(index + 1))) {
        index += 1;
        continue;
      }
      if (_free(index, index + 2)) {
        _mark(index, index + 1, Md.marker);
        _escaped[index] = true;
        _escaped[index + 1] = true;
      }
      index += 2;
    }
  }

  /// Whether nothing in `[start, end)` was made literal by a backslash.
  bool _unescaped(int start, int end) {
    for (var i = start; i < end && i < source.length; i++) {
      if (_escaped[i]) return false;
    }
    return true;
  }

  /// Searched one block at a time, for the reason [_htmlTags] is.
  ///
  /// A code span is an inline construct, and inline parsing runs inside one
  /// block: the blank line that ends a paragraph is also what stops a backtick
  /// reaching the next one. Over the whole document an unclosed backtick pairs
  /// with the next one anywhere below it, and everything in between — the
  /// bold, the mentions, the headings the site will really cook — is drawn as
  /// code and closed to every later pass.
  void _inlineCode(List<({int offset, String text})> blocks) {
    for (final block in blocks) {
      for (final (open, width, close) in _codeSpans(block.text)) {
        final start = block.offset + open;
        final end = block.offset + close + width;
        if (!_free(start, end)) continue;
        _mark(start, start + width, Md.marker);
        _mark(start + width, end - width, Md.code);
        _mark(end - width, end, Md.marker);
        _close(start, end);
      }
    }
  }

  /// The code spans in one block, as `(opener, width, closer)` offsets into it.
  ///
  /// Two rules, and the pattern this replaces got both slightly wrong.
  ///
  /// A backslash-escaped backtick is not a delimiter. CommonMark's escapes
  /// work everywhere except *inside* a code span, so `\`` is a literal
  /// backtick that cannot open one — and treating it as a delimiter drew a
  /// whole sentence as code, with the bold and the mentions in it closed to
  /// every later pass, that the site cooks as ordinary prose. An escaped
  /// backtick also ends the run it is in rather than lengthening it, because
  /// the run either side of it is what a closer has to match.
  ///
  /// And a delimiter is a *maximal* run: `` `a`` `` opens with one backtick
  /// and the only run after it is two, so it is not a code span at all. The
  /// backreference could take the first backtick of that longer run instead,
  /// and closed a span the site leaves as text.
  static Iterable<(int, int, int)> _codeSpans(String text) sync* {
    final runs = _backtickRuns(text);
    var index = 0;
    while (index < runs.length) {
      final (open, width) = runs[index];
      var paired = false;
      for (var next = index + 1; next < runs.length; next += 1) {
        final (close, closeWidth) = runs[next];
        // Equal length, and at least one character of content between them.
        if (closeWidth != width || close <= open + width) continue;
        yield (open, width, close);
        index = next + 1;
        paired = true;
        break;
      }
      if (!paired) index += 1;
    }
  }

  /// The maximal runs of unescaped backticks in [text], as `(start, length)`.
  static List<(int, int)> _backtickRuns(String text) {
    final runs = <(int, int)>[];
    var start = -1;
    var index = 0;
    void endRun() {
      if (start < 0) return;
      runs.add((start, index - start));
      start = -1;
    }

    while (index < text.length) {
      final unit = text.codeUnitAt(index);
      if (unit == 0x5C) {
        // A backslash spends itself on the next character, whatever it is —
        // so `\\` leaves a backtick after it free to open a span.
        endRun();
        index += 2;
        continue;
      }
      if (unit == 0x60) {
        if (start < 0) start = index;
        index += 1;
        continue;
      }
      endRun();
      index += 1;
    }
    endRun();
    return runs;
  }

  static final RegExp _tagPattern = RegExp(
    '<(${allowedInlineTags.join('|')})>([\\s\\S]*?)</\\1>',
    caseSensitive: false,
  );

  /// Recursive, because `<mark>look <kbd>here</kbd></mark>` is two tags and a
  /// single sweep only ever sees the outer one — the inner pair lies inside
  /// the match the sweep has already stepped over.
  ///
  /// Searched one block at a time, and one match at a time within it, for the
  /// reason [_blocks] exists: an unclosed `<kbd>` is a lazy pattern with
  /// nothing to stop it, so left to the whole document each one walks the rest
  /// of it before giving up.
  void _htmlTags(String text, int offset) {
    // Every match needs a `</`, and the body between the tags is lazy with
    // nothing to stop it: without one, each opener walks the rest of the block
    // before giving up, and a line of unclosed `<del>` is quadratic. One
    // substring search answers for all of them.
    if (!text.contains('</')) return;
    for (final match in _tagPattern.allMatches(text)) {
      final tag = match.group(1)!.toLowerCase();
      final start = offset + match.start;
      final end = offset + match.end;
      final open = start + tag.length + 2;
      final close = end - tag.length - 3;
      // As with emphasis, only the tags themselves must be unclaimed.
      if (!_free(start, open) || !_free(close, end)) continue;
      if (!_unescaped(start, open) || !_unescaped(close, end)) continue;
      _mark(start, open, Md.marker);
      _addTag(open, close, tag);
      _mark(close, end, Md.marker);
      // Only the tags are spoken for; `<kbd>**x**</kbd>` is still bold.
      _close(start, open);
      _close(close, end);
      _htmlTags(source.substring(open, close), open);
    }
  }

  /// `[text](url)`, found by scanning rather than by a pattern.
  ///
  /// The pattern this replaces was `\[([^\]\n]*)\]\(([^)\s]*)\)`, and the
  /// text class excludes `]`, so the closing bracket is always the first one
  /// on the line — but the engine cannot know that. At every `[` it consumed
  /// to the end of the line and then gave the characters back one at a time
  /// looking for a `]` that the class it just matched had already ruled out.
  /// One line holding many `[` and no `]` — a pasted log line, a minified
  /// array — cost that walk per bracket. The scan below finds the same
  /// bracket with `indexOf`, and when a line has none it says so once instead
  /// of rediscovering it at every `[` after that.
  void _links() {
    // The end of a line already shown to hold no `]` after it.
    var barrenTo = -1;
    // The newline ending the line the bracket under consideration is on.
    // Carried, because openings only move forward: looking it up per bracket
    // would walk to the end of a newline-free document at every one of them,
    // which is the cost this scan exists to remove.
    var lineEnd = -1;
    var offset = 0;
    while (offset < source.length) {
      final open = source.indexOf('[', offset);
      if (open < 0) break;
      if (open < barrenTo) {
        offset = open + 1;
        continue;
      }
      if (open >= lineEnd) {
        final next = source.indexOf('\n', open + 1);
        lineEnd = next < 0 ? source.length : next;
      }

      final close = source.indexOf(']', open + 1);
      if (close < 0) {
        // Nothing later can close either.
        break;
      }
      if (close > lineEnd) {
        barrenTo = lineEnd;
        offset = open + 1;
        continue;
      }
      if (close + 1 >= source.length || source[close + 1] != '(') {
        offset = open + 1;
        continue;
      }

      final urlStart = close + 2;
      final address = _linkAddressPattern.matchAsPrefix(source, urlStart);
      if (address == null) {
        offset = open + 1;
        continue;
      }

      final textStart = open + 1;
      final textEnd = close;
      final urlEnd = address.end - 1;
      final end = address.end;
      // The brackets and the address have to be unclaimed; the link text is
      // prose and may already carry a mark.
      if (!_free(open, textStart) ||
          !_free(textEnd, end) ||
          !_unescaped(open, textStart) ||
          !_unescaped(textEnd, end)) {
        offset = open + 1;
        continue;
      }

      _mark(open, textStart, Md.marker);
      _mark(textStart, textEnd, Md.linkText);
      _mark(textEnd, urlStart, Md.marker);
      _mark(urlStart, urlEnd, Md.linkUrl);
      _mark(urlEnd, end, Md.marker);
      // The URL is spoken for — an underscore in it is not italic — but the
      // link text is ordinary prose and may be marked up.
      _close(open, textStart);
      _close(textEnd, end);
      offset = end;
    }
  }

  void _bareUrls() {
    for (final match in _bareUrlPattern.allMatches(source)) {
      if (!_free(match.start, match.end)) continue;
      _mark(match.start, match.end, Md.linkUrl);
      _close(match.start, match.end);
    }
  }

  void _mentions() {
    for (final match in _mentionPattern.allMatches(source)) {
      if (!_free(match.start, match.end)) continue;
      // `joffrey@example.com` is an address, not a mention of `example`.
      if (match.start > 0 && !_isBoundary(source[match.start - 1])) continue;
      // Core reads it as `matches[1] || matches[2]` for the same reason.
      final name = match.group(1) ?? match.group(2)!;
      _markToken(match.start, match.end, Md.mention, name);
      _close(match.start, match.end);
      // As for a shortcode: two of these side by side are two pills, and
      // collapsed by mask alone they would be one run and one pill over both.
      _cuts.add(match.start);
      _cuts.add(match.end);
    }
  }

  /// `#category`, `#parent:child`, `#name::tag`.
  ///
  /// Transcribed from core's own matcher in `hashtag-autocomplete.js`, which is
  /// what decides whether the site will cook this as a hashtag at all: not
  /// preceded by `/` — that is what keeps `example.com/#anchor` whole — one to
  /// 101 characters, and `:` allowed so a subcategory and a disambiguated tag
  /// survive.
  ///
  /// No heading conflict to resolve: `_lineBlock`'s pattern already requires
  /// whitespace after the hashes, so `# Heading` is a heading and `#heading` is
  /// not, exactly as CommonMark and Discourse both have it.
  void _hashtags() {
    for (final match in _hashtagPattern.allMatches(source)) {
      if (!_free(match.start, match.end)) continue;
      // `##foo` is not a hashtag of `#foo`, and `a#b` is not one at all.
      if (match.start > 0 && !_isBoundary(source[match.start - 1])) continue;
      _markToken(match.start, match.end, Md.hashtag, match.group(1)!);
      _close(match.start, match.end);
      _cuts.add(match.start);
      _cuts.add(match.end);
    }
  }

  void _emoji() {
    for (final match in _emojiPattern.allMatches(source)) {
      if (!_free(match.start, match.end)) continue;
      // Core's `getEmojiName` refuses a shortcode whose opening colon has an
      // ordinary character before it, which is what keeps `10:30:45` from
      // containing an emoji called `30` — and what stops the composer drawing
      // a picture where the site leaves `word:smile:` as text. The rule is
      // switched off by the `inline emoji` site setting, which is off by
      // default and is not a setting this scan can see; drawing the default is
      // the side that cannot invent markup.
      if (match.start > 0 && !_opensEmoji(source[match.start - 1])) continue;
      // The name goes in the token so whatever draws this does not have to
      // parse the colons back off it.
      _markToken(match.start, match.end, Md.emoji, match.group(1)!);
      _close(match.start, match.end);
      _cuts.add(match.start);
      _cuts.add(match.end);
    }
  }

  /// `***x***`, `**x**`, `*x*`, `___x___`, `__x__`, `_x_` and `~~x~~`.
  ///
  /// Longest delimiter first, so a run of three is one mark and not three, and
  /// the opening `**` of a bold run is not read as an italic `*` followed by a
  /// stray one.
  ///
  /// Each pass closes the delimiters it took, and the passes below skip a
  /// character something already owns — which is what makes the ladder a
  /// ladder rather than three passes fighting over the same asterisks.
  ///
  /// The underscore has the same ladder as the asterisk, because Discourse
  /// reads it the same way: `__bold__` is bold, not an italic `_bold_`. Only
  /// between word boundaries, though — `snake_case_name` is a name.
  void _emphasis(List<({int offset, String text})> blocks) {
    _pairs('***', Md.bold | Md.italic, blocks);
    _pairs('**', Md.bold, blocks);
    _pairs('*', Md.italic, blocks);
    _pairs('~~', Md.strikethrough, blocks);
    _pairs('___', Md.bold | Md.italic, blocks, wordBounded: true);
    _pairs('__', Md.bold, blocks, wordBounded: true);
    _pairs('_', Md.italic, blocks, wordBounded: true);
  }

  List<({int offset, String text})> _blocks() =>
      markdownBlocks(source, excluding: _fences);

  /// Applies one delimiter's pairs across [blocks].
  void _pairs(
    String delimiter,
    int flag,
    List<({int offset, String text})> blocks, {
    bool wordBounded = false,
  }) {
    final width = delimiter.length;
    for (final block in blocks) {
      for (final (open, close) in markdownPairs(
        block.text,
        delimiter,
        wordBounded: wordBounded,
        spokenFor: (offset) =>
            _closed[block.offset + offset] || _escaped[block.offset + offset],
      )) {
        final start = block.offset + open;
        final end = block.offset + close;
        // Only the delimiters have to be unclaimed. The content may hold
        // anything — `**bold with `code` inside**` is bold all the way across,
        // and the backticks inside it were spoken for by an earlier pass. A
        // claimed delimiter still consumes its span, the way the pass that
        // stepped over whole matches did.
        if (!_free(start, start + width)) continue;
        if (!_free(end - width, end)) continue;
        _mark(start, start + width, Md.marker);
        _mark(start + width, end - width, flag);
        _mark(end - width, end, Md.marker);
        // Only the delimiters are closed — the content stays open so a mark
        // inside another one still lands.
        _close(start, start + width);
        _close(end - width, end);
      }
    }
  }

  /// What may sit immediately before a shortcode's opening colon.
  ///
  /// Core's `isValidEmojiPrecedingChar`: whitespace, punctuation, or a
  /// zero-width space. Its whitespace test is markdown-it's, which is a tab or
  /// a space — a line ending never reaches it because a soft break is its own
  /// token — so this reads a line ending as whitespace, which is the same
  /// position in a document that has not been split into tokens yet.
  static bool _opensEmoji(String character) =>
      character == '\u200B' ||
      _isWhitespace(character.codeUnitAt(0)) ||
      _punctuationPattern.hasMatch(character);

  static final RegExp _punctuationPattern = RegExp(
    r'[\p{P}\p{S}]',
    unicode: true,
  );

  /// What may sit immediately before a sigil.
  ///
  /// `#` is in the excluded set so `##foo` does not mark `#foo` — at the cost
  /// of `x#@sam` no longer reading as a mention, which is not a sentence
  /// anybody writes.
  static bool _isBoundary(String character) =>
      !_boundaryPattern.hasMatch(character);

  /// Collapses equal neighbours, so the span tree has one child per visible
  /// change rather than one per character.
  List<MarkdownRun> runs() {
    final out = <MarkdownRun>[];
    var start = 0;

    for (var i = 1; i <= source.length; i++) {
      final ends =
          i == source.length ||
          mask[i] != mask[start] ||
          detail[i] != detail[start] ||
          tokens[i] != tokens[start] ||
          _cuts.contains(i);
      if (!ends) continue;
      out.add(MarkdownRun(start, i, mask[start], detail[start], tokens[start]));
      start = i;
    }
    return out;
  }
}

/// An opening or closing ``` line.
class _Fence {
  const _Fence(this.delimiter, this.info);

  final String delimiter;

  /// What follows the backticks on an opening fence — the language, usually.
  final String info;

  bool closes(_Fence opening) =>
      info.isEmpty &&
      delimiter.codeUnitAt(0) == opening.delimiter.codeUnitAt(0) &&
      delimiter.length >= opening.delimiter.length;
}

final RegExp _fencePattern = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*(.*)$');

_Fence? _fenceAt(String line) {
  final match = _fencePattern.firstMatch(line);
  return match == null ? null : _Fence(match.group(1)!, match.group(2)!.trim());
}
