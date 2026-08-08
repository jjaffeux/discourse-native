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

/// Reads [source] and reports how to draw it.
///
/// Pure, so the fiddly part — what counts as a marker and what is just an
/// asterisk — is testable without pumping a widget, the same bargain
/// `toggleMarkdownMark` makes.
List<MarkdownRun> scanMarkdown(String source) {
  if (source.isEmpty) return const [];

  final scan = _Scan(source);
  scan.blocks();
  scan.inlines();
  return scan.runs();
}

/// The masks being built up, one slot per character.
class _Scan {
  _Scan(this.source)
    : mask = List<int>.filled(source.length, 0),
      detail = List<String?>.filled(source.length, null),
      tokens = List<String?>.filled(source.length, null),
      _closed = List<bool>.filled(source.length, false);

  final String source;
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
    String? language;

    for (final line in source.split('\n')) {
      final end = offset + line.length;
      final fence = _fenceAt(line);

      if (bodyStart >= 0) {
        // Inside a fence: only its own closing line ends it.
        if (fence != null && fence.info.isEmpty) {
          _mark(offset, end, Md.marker);
          _close(offset, end);
          _highlightFence(bodyStart, offset, language);
          bodyStart = -1;
          language = null;
        }
      } else if (fence != null) {
        _mark(offset, end, Md.marker);
        _close(offset, end);
        language = fence.info.isEmpty ? null : fence.info;
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
    }
  }

  /// Headings and blockquotes, which claim a marker and then leave the rest of
  /// the line to the inline pass.
  void _lineBlock(int offset, String line) {
    final heading = RegExp(r'^(#{1,6})(\s+)').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      _mark(offset, offset + heading.end, Md.marker);
      _close(offset, offset + heading.end);
      _mark(offset + heading.end, offset + line.length, Md.heading, '$level');
      return;
    }

    final quote = RegExp(r'^(>+)(\s?)').firstMatch(line);
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
    _inlineCode();
    _htmlTags();
    _links();
    _bareUrls();
    _mentions();
    // After `_bareUrls`, so `https://x.com/a#top` keeps its fragment rather
    // than growing a hashtag inside it — core's `(?<!/)` alone does not cover
    // a fragment that follows something other than a slash. Before
    // `_emphasis`, so `#a_b_c` keeps its underscores.
    _hashtags();
    _emoji();
    _emphasis();
  }

  void _inlineCode() {
    for (final match in RegExp(
      r'(`+)([^`]|[^`][\s\S]*?[^`])\1',
    ).allMatches(source)) {
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
  void _htmlTags([int from = 0, int? to]) {
    final limit = to ?? source.length;
    for (final match in _tagPattern.allMatches(source, from)) {
      if (match.end > limit) break;
      final tag = match.group(1)!.toLowerCase();
      final open = match.start + tag.length + 2;
      final close = match.end - tag.length - 3;
      // As with emphasis, only the tags themselves must be unclaimed.
      if (!_free(match.start, open) || !_free(close, match.end)) continue;
      _mark(match.start, open, Md.marker);
      _addTag(open, close, tag);
      _mark(close, match.end, Md.marker);
      // Only the tags are spoken for; `<kbd>**x**</kbd>` is still bold.
      _close(match.start, open);
      _close(close, match.end);
      _htmlTags(open, close);
    }
  }

  void _links() {
    for (final match in RegExp(
      r'\[([^\]\n]*)\]\(([^)\s]*)\)',
    ).allMatches(source)) {
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
    for (final match in RegExp(r'https?://[^\s<>\[\]()]+').allMatches(source)) {
      if (!_free(match.start, match.end)) continue;
      _mark(match.start, match.end, Md.linkUrl);
      _close(match.start, match.end);
    }
  }

  void _mentions() {
    for (final match in RegExp(
      r'@([a-zA-Z0-9_][a-zA-Z0-9_.-]*)',
    ).allMatches(source)) {
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
    for (final match in RegExp(
      r'(?<!/)#([\wÀ-῿Ⰰ-퟿:-]'
      r'(?:[\wÀ-῿Ⰰ-퟿:.-]{0,99}'
      r'[\wÀ-῿Ⰰ-퟿:-])?)',
    ).allMatches(source)) {
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
    for (final match in RegExp(
      r':([a-z0-9_+-]+(?::t[1-6])?):',
    ).allMatches(source)) {
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
  void _emphasis() {
    _pairs(
      RegExp('\\*\\*\\*(?=\\S)($_within\\S)\\*\\*\\*'),
      3,
      Md.bold | Md.italic,
    );
    _pairs(RegExp('\\*\\*(?=\\S)($_within\\S)\\*\\*'), 2, Md.bold);
    _pairs(RegExp('\\*(?=\\S)($_within\\S)\\*'), 1, Md.italic);
    _pairs(RegExp('~~(?=\\S)($_within\\S)~~'), 2, Md.strikethrough);
    // Underscores only between word boundaries: `snake_case_name` is a name.
    _pairs(RegExp('(?<![\\w_])_(?=\\S)($_within\\S)_(?![\\w_])'), 1, Md.italic);
  }

  /// Any run of characters that does not cross a blank line.
  ///
  /// A mark cannot span a paragraph break — an unclosed `*` at the end of one
  /// paragraph would otherwise reach forward and italicise everything down to
  /// the next asterisk anywhere in the post.
  static const String _within = r'(?:(?!\n\s*\n)[\s\S])*?';

  void _pairs(RegExp pattern, int width, int flag) {
    for (final match in pattern.allMatches(source)) {
      // Only the delimiters have to be unclaimed. The content may hold
      // anything — `**bold with `code` inside**` is bold all the way across,
      // and the backticks inside it were spoken for by an earlier pass.
      if (!_free(match.start, match.start + width)) continue;
      if (!_free(match.end - width, match.end)) continue;
      _mark(match.start, match.start + width, Md.marker);
      _mark(match.start + width, match.end - width, flag);
      _mark(match.end - width, match.end, Md.marker);
      // Only the delimiters are closed — the content stays open so a mark
      // inside another one still lands.
      _close(match.start, match.start + width);
      _close(match.end - width, match.end);
    }
  }

  /// What may sit immediately before a sigil.
  ///
  /// `#` is in the excluded set so `##foo` does not mark `#foo` — at the cost
  /// of `x#@sam` no longer reading as a mention, which is not a sentence
  /// anybody writes.
  static bool _isBoundary(String character) =>
      !RegExp(r'[\w@#./-]').hasMatch(character);

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
  const _Fence(this.info);

  /// What follows the backticks on an opening fence — the language, usually.
  final String info;
}

_Fence? _fenceAt(String line) {
  final match = RegExp(r'^\s{0,3}(?:`{3,}|~{3,})\s*(.*)$').firstMatch(line);
  return match == null ? null : _Fence(match.group(1)!.trim());
}
