/// Original UTF-16 boundaries, before component metadata or projection.
typedef ComposerMarkdownTokenBoundary = ({
  int openerStart,
  int labelStart,
  int labelEnd,
  int destinationStart,
  int tokenEnd,
});

typedef ComposerMarkdownImageToken = ({
  ComposerMarkdownTokenBoundary boundary,
  int urlStart,
  int urlEnd,
  bool escaped,
});

// Let `\\.` own backslashes. Matching them in both branches causes explosive
// backtracking and misreads CommonMark's escaped `\]`.
final RegExp _imageAltPattern = RegExp(r'!\[((?:\\.|[^\\\]\n])*)');
final _imageParagraphBreak = RegExp(
  r'(?:\r\n|\r(?!\n)|\n)[ \t]*(?:\r\n|\r(?!\n)|\n)',
);
final RegExp _imageSchemePattern = RegExp(
  r'(?:upload://|https?://)',
  caseSensitive: false,
);

class ComposerMarkdownImageReader {
  ComposerMarkdownImageReader(this.source);

  final String source;
  final _destinationEnds = <int, int>{};
  var _paragraphEnd = -1;

  ComposerMarkdownImageDestination? destinationAt(int start, int limit) =>
      _imageDestination(source, start, limit, _destinationEnds);

  Iterable<ComposerMarkdownImageToken> tokens({
    bool Function(int)? excludesOpener,
  }) sync* {
    var offset = 0;
    while (offset < source.length) {
      final start = source.indexOf('![', offset);
      if (start < 0) break;
      if (excludesOpener?.call(start) ?? false) {
        offset = start + 2;
        continue;
      }
      final alt = _imageAltPattern.matchAsPrefix(source, start)!;
      final bracket = alt.end;
      offset = bracket + 1;
      if (!source.startsWith('](', bracket)) continue;
      if (start >= _paragraphEnd) {
        _paragraphEnd =
            _imageParagraphBreak.allMatches(source, start).firstOrNull?.start ??
            source.length;
      }
      final destination = destinationAt(bracket + 2, _paragraphEnd);
      if (destination == null) continue;
      final (:urlStart, :urlEnd, :end) = destination;
      offset = end;
      var slashes = 0;
      for (var at = start - 1; at >= 0 && source.codeUnitAt(at) == 0x5c; at--) {
        slashes++;
      }
      yield (
        boundary: (
          openerStart: start,
          labelStart: start + 2,
          labelEnd: bracket,
          destinationStart: bracket + 2,
          tokenEnd: end,
        ),
        urlStart: urlStart,
        urlEnd: urlEnd,
        escaped: slashes.isOdd,
      );
    }
  }
}

typedef ComposerMarkdownImageDestination = ({
  int urlStart,
  int urlEnd,
  int end,
});

ComposerMarkdownImageDestination? _imageDestination(
  String source,
  int start,
  int paragraphEnd,
  Map<int, int> destinationEnds,
) {
  var at = start;
  while (at < paragraphEnd && _imageDestinationSpace(source.codeUnitAt(at))) {
    at++;
  }
  final angle = at < paragraphEnd && source.codeUnitAt(at) == 0x3c;
  if (angle) at++;
  final urlStart = at;
  final scheme = _imageSchemePattern.matchAsPrefix(source, urlStart);
  if (scheme == null) return null;
  var nesting = 0;
  while (at < paragraphEnd) {
    final unit = source.codeUnitAt(at);
    if (angle) {
      if (unit == 0x0a || unit == 0x0d || unit == 0x3c) return null;
      if (unit == 0x3e) break;
    } else {
      if (unit <= 0x20 || unit == 0x7f) break;
      if (unit == 0x28) {
        nesting++;
        // Match the cooker and bound retries of nested malformed images.
        if (nesting > 32) return null;
      } else if (unit == 0x29) {
        if (nesting == 0) break;
        nesting--;
      }
    }
    if (unit == 0x5c && at + 1 < paragraphEnd) {
      // A backslash cannot escape a space in a bare destination.
      at += !angle && source.codeUnitAt(at + 1) == 0x20 ? 1 : 2;
    } else {
      at++;
    }
  }
  final urlEnd = at;
  if (urlEnd <= scheme.end || nesting != 0) return null;
  if (angle) {
    if (at >= paragraphEnd || source.codeUnitAt(at) != 0x3e) return null;
    at++;
  }
  final end = destinationEnds.putIfAbsent(
    at,
    () => _imageDestinationEnd(source, at, paragraphEnd),
  );
  if (end < 0) return null;
  return (urlStart: urlStart, urlEnd: urlEnd, end: end);
}

int _imageDestinationEnd(String source, int start, int paragraphEnd) {
  var at = start;
  while (at < paragraphEnd && _imageDestinationSpace(source.codeUnitAt(at))) {
    at++;
  }
  if (at >= paragraphEnd) return -1;
  if (source.codeUnitAt(at) == 0x29) return at + 1;
  if (at == start) return -1;
  var marker = source.codeUnitAt(at);
  if (marker != 0x22 && marker != 0x27 && marker != 0x28) return -1;
  if (marker == 0x28) marker = 0x29;
  at++;
  while (at < paragraphEnd) {
    final unit = source.codeUnitAt(at++);
    if (unit == marker) {
      while (at < paragraphEnd &&
          _imageDestinationSpace(source.codeUnitAt(at))) {
        at++;
      }
      return at < paragraphEnd && source.codeUnitAt(at) == 0x29 ? at + 1 : -1;
    }
    if (unit == 0x28 && marker == 0x29) return -1;
    if (unit == 0x5c && at < paragraphEnd) at++;
  }
  return -1;
}

bool _imageDestinationSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

Map<int, ComposerMarkdownTokenBoundary> composerMarkdownLinkCandidates(
  String source, {
  int start = 0,
  int? end,
  bool Function(int)? excludesBracket,
  bool Function(int, int)? overlapsCode,
  int? Function(int, int)? skipInline,
  ComposerMarkdownImageReader? images,
}) {
  final candidates = <int, ComposerMarkdownTokenBoundary>{};
  final limit = end ?? source.length;
  final labels = <({int start, bool nestedLink})>[];
  for (var offset = start; offset < limit; offset += 1) {
    final skipped = skipInline?.call(offset, limit);
    if (skipped != null && skipped > offset) {
      offset = skipped - 1;
      continue;
    }
    final unit = source.codeUnitAt(offset);
    if (unit == 0x5C &&
        offset + 1 < limit &&
        source.codeUnitAt(offset + 1) != 0x0A) {
      offset += 1;
    } else if (unit == 0x0A) {
      labels.clear();
    } else if ((unit == 0x5B || unit == 0x5D) &&
        (excludesBracket?.call(offset) ?? false)) {
      // Code can contain unmatched brackets inside an otherwise valid label.
      continue;
    } else if (unit == 0x5B) {
      labels.add((start: offset, nestedLink: false));
    } else if (unit == 0x5D && labels.isNotEmpty) {
      final label = labels.removeLast();
      final image = label.start > 0 && source[label.start - 1] == '!';
      final end =
          offset > label.start + 1 &&
              offset + 2 < limit &&
              source[offset + 1] == '('
          ? image && images != null
                ? images.destinationAt(offset + 2, limit)?.end
                : _markdownLinkDestinationEnd(source, offset + 2, limit)
          : null;
      final accepted = end != null && (image || !label.nestedLink);
      if (accepted) {
        candidates[label.start] = (
          openerStart: image ? label.start - 1 : label.start,
          labelStart: label.start + 1,
          labelEnd: offset,
          destinationStart: offset + 2,
          tokenEnd: end,
        );
      }
      // Markdown allows an image inside a label, but not another actual link.
      final nestedLink = image && accepted
          ? false
          : label.nestedLink ||
                (accepted && !(overlapsCode?.call(label.start, end) ?? false));
      if (nestedLink && labels.isNotEmpty) {
        labels.last = (start: labels.last.start, nestedLink: true);
      }
      if (accepted) offset = end - 1;
    }
  }
  return candidates;
}

int? _markdownLinkDestinationEnd(String source, int start, int limit) {
  var close = start;
  var nesting = 0;
  while (close < limit) {
    final unit = source.codeUnitAt(close);
    if (_linkWhitespace(unit)) break;
    if (unit == 0x5C &&
        close + 1 < limit &&
        !_linkWhitespace(source.codeUnitAt(close + 1))) {
      close += 2;
      continue;
    }
    if (unit == 0x28) {
      nesting += 1;
      // Match markdown-it's limit and bound rescans of unfinished nesting.
      if (nesting > 32) break;
    } else if (unit == 0x29) {
      if (nesting == 0) break;
      nesting -= 1;
    }
    close += 1;
  }
  return close > start && close < limit && source[close] == ')'
      ? close + 1
      : null;
}

bool _linkWhitespace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D);
