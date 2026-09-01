library;

import 'package:flutter/foundation.dart';

import 'syntax.dart';

abstract final class Md {
  static const int marker = 1 << 0;

  static const int bold = 1 << 1;
  static const int italic = 1 << 2;
  static const int strikethrough = 1 << 3;

  static const int code = 1 << 4;

  static const int codeBlock = 1 << 5;

  static const int heading = 1 << 6;

  static const int quote = 1 << 7;

  static const int linkText = 1 << 8;

  static const int linkUrl = 1 << 9;

  static const int mention = 1 << 10;

  static const int emoji = 1 << 11;

  static const int htmlTag = 1 << 12;

  static const int hashtag = 1 << 13;
}

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

@immutable
class MarkdownRun {
  const MarkdownRun(this.start, this.end, this.mask, [this.detail, this.token]);

  final int start;
  final int end;
  final int mask;

  final String? detail;

  final String? token;

  int get length => end - start;

  bool has(int flag) => mask & flag != 0;

  @override
  String toString() => '[$start,$end) ${mask.toRadixString(2)} $detail $token';
}

typedef DeferredFenceHighlight = void Function(String body, String? language);

const int maxSynchronousFenceChars = 512;

final class CodeRanges {
  const CodeRanges._(this._starts, this._ends);

  factory CodeRanges.of(List<MarkdownRun> runs) {
    final starts = <int>[];
    final ends = <int>[];
    for (final run in runs) {
      if (!run.has(Md.code) && !run.has(Md.codeBlock)) continue;
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

  Iterable<(int, int)> get ranges sync* {
    for (var index = 0; index < _starts.length; index += 1) {
      yield (_starts[index], _ends[index]);
    }
  }

  bool contains(int offset) => overlaps(offset, offset + 1);

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

bool _insideLongerRun(String text, String delimiter, int at) {
  if (delimiter.length != 1) return false;
  final unit = delimiter.codeUnitAt(0);
  if (at > 0 && text.codeUnitAt(at - 1) == unit) return true;
  return at + 1 < text.length && text.codeUnitAt(at + 1) == unit;
}

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

final RegExp _emojiBoundaryPunctuationPattern = RegExp(
  r'[\p{P}\p{S}]',
  unicode: true,
);

/// Whether [character] can immediately precede an emoji shortcode.
///
/// This mirrors Discourse's default shortcode boundary. Keeping it shared
/// prevents composer edits from preserving artwork for source that the site
/// would no longer render as an emoji.
bool isEmojiShortcodeBoundary(String character) =>
    character == '\u200B' ||
    _isWhitespace(character.codeUnitAt(0)) ||
    _emojiBoundaryPunctuationPattern.hasMatch(character);

bool _isAsciiPunctuation(int unit) =>
    (unit >= 0x21 && unit <= 0x2F) ||
    (unit >= 0x3A && unit <= 0x40) ||
    (unit >= 0x5B && unit <= 0x60) ||
    (unit >= 0x7B && unit <= 0x7E);

bool _isWordCharacter(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x5F;

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

  final List<String?> tokens;

  final List<bool> _closed;

  final List<bool> _escaped;

  final Set<int> _cuts = {};

  final List<(int, int)> _fences = [];

  // A scan runs on every text change. Keep the compiled expressions with the
  // scanner type rather than rebuilding them for every line and every pass.
  static final RegExp _headingPattern = RegExp(r'^(#{1,6})(\s+)');
  static final RegExp _quotePattern = RegExp(r'^(>+)(\s?)');
  static final RegExp _linkAddressPattern = RegExp(r'[^)\s]*\)');
  static final RegExp _bareUrlPattern = RegExp(r'https?://[^\s<>\[\]()]+');

  static final RegExp _mentionPattern = RegExp(
    r'@(\w[\w.-]{0,58}[^\W_])|@(\w)',
  );
  static final RegExp _hashtagPattern = RegExp(
    r'(?<!/)#([\wÀ-῿Ⰰ-퟿:-]'
    r'(?:[\wÀ-῿Ⰰ-퟿:.-]{0,99}'
    r'[\wÀ-῿Ⰰ-퟿:-])?)',
  );

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

  void _markToken(int start, int end, int flag, String token) {
    _mark(start, end, flag);
    for (var i = start; i < end && i < source.length; i++) {
      tokens[i] = token;
    }
  }

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
      at += 1;
    }
  }

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

  bool _unescaped(int start, int end) {
    for (var i = start; i < end && i < source.length; i++) {
      if (_escaped[i]) return false;
    }
    return true;
  }

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

  static Iterable<(int, int, int)> _codeSpans(String text) sync* {
    final runs = _backtickRuns(text);
    var index = 0;
    while (index < runs.length) {
      final (open, width) = runs[index];
      var paired = false;
      for (var next = index + 1; next < runs.length; next += 1) {
        final (close, closeWidth) = runs[next];
        if (closeWidth != width || close <= open + width) continue;
        yield (open, width, close);
        index = next + 1;
        paired = true;
        break;
      }
      if (!paired) index += 1;
    }
  }

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
      // Match Core's default shortcode boundary so times and `word:smile:`
      // remain text. This scanner cannot see the setting that relaxes it.
      if (match.start > 0 &&
          !isEmojiShortcodeBoundary(source[match.start - 1])) {
        continue;
      }
      _markToken(match.start, match.end, Md.emoji, match.group(1)!);
      _close(match.start, match.end);
      _cuts.add(match.start);
      _cuts.add(match.end);
    }
  }

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

  static bool _isBoundary(String character) =>
      !_boundaryPattern.hasMatch(character);

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

class _Fence {
  const _Fence(this.delimiter, this.info);

  final String delimiter;

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
