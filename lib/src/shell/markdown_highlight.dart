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
      _closed = List<bool>.filled(source.length, false);

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
  static final RegExp _inlineCodePattern = RegExp(
    r'(`+)([^`]|[^`][\s\S]*?[^`])\1',
  );
  static final RegExp _linkPattern = RegExp(r'\[([^\]\n]*)\]\(([^)\s]*)\)');
  static final RegExp _bareUrlPattern = RegExp(r'https?://[^\s<>\[\]()]+');
  static final RegExp _mentionPattern = RegExp(
    r'@([a-zA-Z0-9_][a-zA-Z0-9_.-]*)',
  );
  static final RegExp _hashtagPattern = RegExp(
    r'(?<!/)#([\wÀ-῿Ⰰ-퟿:-]'
    r'(?:[\wÀ-῿Ⰰ-퟿:.-]{0,99}'
    r'[\wÀ-῿Ⰰ-퟿:-])?)',
  );
  static final RegExp _emojiPattern = RegExp(r':([a-z0-9_+-]+(?::t[1-6])?):');
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
    _inlineCode();
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

  void _inlineCode() {
    for (final match in _inlineCodePattern.allMatches(source)) {
      if (!_free(match.start, match.end)) continue;
      final ticks = match.group(1)!.length;
      _mark(match.start, match.start + ticks, Md.marker);
      _mark(match.start + ticks, match.end - ticks, Md.code);
      _mark(match.end - ticks, match.end, Md.marker);
      _close(match.start, match.end);
    }
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
    for (final match in _tagPattern.allMatches(text)) {
      final tag = match.group(1)!.toLowerCase();
      final start = offset + match.start;
      final end = offset + match.end;
      final open = start + tag.length + 2;
      final close = end - tag.length - 3;
      // As with emphasis, only the tags themselves must be unclaimed.
      if (!_free(start, open) || !_free(close, end)) continue;
      _mark(start, open, Md.marker);
      _addTag(open, close, tag);
      _mark(close, end, Md.marker);
      // Only the tags are spoken for; `<kbd>**x**</kbd>` is still bold.
      _close(start, open);
      _close(close, end);
      _htmlTags(source.substring(open, close), open);
    }
  }

  void _links() {
    for (final match in _linkPattern.allMatches(source)) {
      final textStart = match.start + 1;
      final textEnd = textStart + match.group(1)!.length;
      final urlStart = textEnd + 2;
      final urlEnd = urlStart + match.group(2)!.length;
      // The brackets and the address have to be unclaimed; the link text is
      // prose and may already carry a mark.
      if (!_free(match.start, textStart) || !_free(textEnd, match.end)) {
        continue;
      }

      _mark(match.start, textStart, Md.marker);
      _mark(textStart, textEnd, Md.linkText);
      _mark(textEnd, urlStart, Md.marker);
      _mark(urlStart, urlEnd, Md.linkUrl);
      _mark(urlEnd, match.end, Md.marker);
      // The URL is spoken for — an underscore in it is not italic — but the
      // link text is ordinary prose and may be marked up.
      _close(match.start, textStart);
      _close(textEnd, match.end);
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
      _markToken(match.start, match.end, Md.mention, match.group(1)!);
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
      // The name goes in the token so whatever draws this does not have to
      // parse the colons back off it.
      _markToken(match.start, match.end, Md.emoji, match.group(1)!);
      _close(match.start, match.end);
      _cuts.add(match.start);
      _cuts.add(match.end);
    }
  }

  /// `***x***`, `**x**`, `*x*`, `_x_` and `~~x~~`.
  ///
  /// Longest marker first, or the opening `**` of a bold run is read as an
  /// italic `*` followed by a stray one.
  void _emphasis(List<({int offset, String text})> blocks) {
    _pairs('***', Md.bold | Md.italic, blocks);
    _pairs('**', Md.bold, blocks);
    _pairs('*', Md.italic, blocks);
    _pairs('~~', Md.strikethrough, blocks);
    // Underscores only between word boundaries: `snake_case_name` is a name.
    _pairs('_', Md.italic, blocks, wordBounded: true);
  }

  static final RegExp _paragraphBreakPattern = RegExp(r'\n\s*\n');

  /// The ranges an inline construct may live inside: a paragraph, minus any
  /// fence in it.
  ///
  /// A mark cannot span a paragraph break — an unclosed `*` at the end of one
  /// paragraph would otherwise reach forward and italicise everything down to
  /// the next asterisk anywhere in the post — and it cannot span a fence,
  /// which ends the paragraph around it. Both are the same rule about where a
  /// block ends, so both are expressed here, once, as where [_pairs] looks.
  ///
  /// Every boundary falls on a newline or an end of the source, so the
  /// word-boundary rules read the same character they would have read had the
  /// whole document been one block.
  List<({int offset, String text})> _blocks() {
    final breaks = <(int, int)>[
      ..._fences,
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

  /// Pairs up one delimiter across [blocks], leftmost and shortest first.
  ///
  /// Written as a scan rather than as `allMatches` of a lazy pattern because
  /// the two disagree about what an unclosed delimiter costs. The pattern has
  /// to walk to the end of the block before it can report that an opener has
  /// no closer, and it has to do it again for the next opener, and the one
  /// after that. A scan knows something the engine cannot: the closers after
  /// a later opener are a subset of the closers after an earlier one, so once
  /// an opener runs out of them the rest of the block has run out too.
  ///
  /// [wordBounded] is the underscore rule — `snake_case_name` is a name, not
  /// three words with emphasis between them.
  void _pairs(
    String delimiter,
    int flag,
    List<({int offset, String text})> blocks, {
    bool wordBounded = false,
  }) {
    final width = delimiter.length;
    for (final block in blocks) {
      final text = block.text;
      var cursor = 0;
      while (cursor + width * 2 < text.length) {
        final open = _nextOpener(text, delimiter, cursor, wordBounded);
        if (open < 0) break;
        final close = _nextCloser(
          text,
          delimiter,
          open + width + 1,
          wordBounded,
        );
        if (close < 0) break;

        final start = block.offset + open;
        final end = block.offset + close + width;
        cursor = close + width;
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

  /// The first place at or after [from] where [delimiter] could open a mark:
  /// followed by a non-space, and for the word-bounded rule not preceded by a
  /// word character.
  static int _nextOpener(
    String text,
    String delimiter,
    int from,
    bool wordBounded,
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
      return at;
    }
    return -1;
  }

  /// The first place at or after [from] where [delimiter] could close a mark:
  /// preceded by a non-space, and for the word-bounded rule not followed by a
  /// word character.
  static int _nextCloser(
    String text,
    String delimiter,
    int from,
    bool wordBounded,
  ) {
    final width = delimiter.length;
    for (
      var at = text.indexOf(delimiter, from);
      at >= 0;
      at = text.indexOf(delimiter, at + 1)
    ) {
      if (at + width > text.length) return -1;
      if (_isWhitespace(text.codeUnitAt(at - 1))) continue;
      if (wordBounded &&
          at + width < text.length &&
          _isWordCharacter(text.codeUnitAt(at + width))) {
        continue;
      }
      return at;
    }
    return -1;
  }

  /// `\s` as Dart's regexps read it, so the scan agrees with the passes that
  /// are still written as patterns.
  static bool _isWhitespace(int unit) =>
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

  /// `[\w_]`, which is `\w`: the underscore is already in it.
  static bool _isWordCharacter(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F;

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
