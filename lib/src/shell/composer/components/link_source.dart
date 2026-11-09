import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../models/site_config.dart';
import '../html_comments.dart';
import '../markdown_highlight.dart';
import '../markdown_tokens.dart';

enum ComposerLinkKind { markdown, linkify }

@immutable
class ComposerLinkBlock {
  const ComposerLinkBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.anchor,
    required this.url,
    required this.kind,
  });

  final int start;
  final int end;
  final String source;
  final String anchor;
  final String url;
  final ComposerLinkKind kind;
}

final RegExp _linkifyHostBoundaryPattern = RegExp(r'[:/?#]');
final RegExp _linkReferencePrefixPattern = RegExp(
  r'[^\S\n]*\[[^\]\n]+\]:[^\S\n]*',
);

List<ComposerLinkBlock> parseComposerLinks(
  String source, {
  CodeRanges? codeRanges,
  bool enableLinkify = true,
  List<String> linkifyTlds = SiteConfig.defaultMarkdownLinkifyTlds,
}) {
  if (source.isEmpty) return const [];
  final literals = ComposerLiteralContainers(source);
  final code = literals.isEmpty
      ? codeRanges ?? markdownCodeRanges(source)
      : markdownCodeRanges(literals.mask(source));
  final links = <ComposerLinkBlock>[];
  final markdownRanges = <TextRange>[];
  var offset = 0;
  Map<int, ComposerMarkdownTokenBoundary>? candidates;

  while (offset < source.length) {
    final start = source.indexOf('[', offset);
    if (start < 0) break;
    if (literals.contains(start)) {
      offset = start + 1;
      continue;
    }
    final candidate = (candidates ??= composerMarkdownLinkCandidates(
      source,
      excludesBracket: (at) => literals.contains(at) || code.contains(at),
      overlapsCode: code.overlaps,
    ))[start];
    if (candidate == null) {
      offset = start + 1;
      continue;
    }
    final bracket = candidate.labelEnd;
    final end = candidate.tokenEnd;
    final urlStart = bracket + 2;
    final destination = source.substring(urlStart, end - 1);
    offset = end;
    markdownRanges.add(TextRange(start: start, end: end));
    if (code.overlaps(start, end)) continue;
    if (candidate.openerStart < start) continue;
    links.add(
      ComposerLinkBlock(
        start: start,
        end: end,
        source: source.substring(start, end),
        anchor: source.substring(start + 1, bracket),
        url: destination.startsWith('<') && destination.endsWith('>')
            ? destination.substring(1, destination.length - 1)
            : destination,
        kind: ComposerLinkKind.markdown,
      ),
    );
  }

  if (enableLinkify) {
    final tlds = linkifyTlds
        .map(_normalizedTld)
        .where((value) => value.isNotEmpty)
        .toSet();
    final context = _LinkifyContext(source);
    var markdownRangeIndex = 0;
    for (final (start, matchEnd) in composerLinkifyCandidates(source)) {
      final end = _trimLinkifyEnd(source, start, matchEnd);
      while (markdownRangeIndex < markdownRanges.length &&
          markdownRanges[markdownRangeIndex].end <= start) {
        markdownRangeIndex += 1;
      }
      final overlapsMarkdown =
          markdownRangeIndex < markdownRanges.length &&
          markdownRanges[markdownRangeIndex].start < end;
      if (end <= start ||
          literals.contains(start) ||
          code.overlaps(start, end) ||
          overlapsMarkdown ||
          context.isInHtmlOrReference(start) ||
          !_hasLinkifyBoundary(source, start)) {
        continue;
      }

      final raw = source.substring(start, end);
      final normalized = _normalizedLinkifyUrl(raw, tlds);
      if (normalized == null) continue;
      links.add(
        ComposerLinkBlock(
          start: start,
          end: end,
          source: raw,
          anchor: raw,
          url: normalized,
          kind: ComposerLinkKind.linkify,
        ),
      );
    }
  }

  links.sort((a, b) => a.start.compareTo(b.start));
  return List.unmodifiable(links);
}

String _normalizedTld(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('.') ? normalized.substring(1) : normalized;
}

int _trimLinkifyEnd(String source, int start, int end) {
  const punctuation = {0x21, 0x22, 0x27, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F};
  while (end > start && punctuation.contains(source.codeUnitAt(end - 1))) {
    end -= 1;
  }
  const closings = {0x28: 0x29, 0x5B: 0x5D, 0x7B: 0x7D};
  final balances = {for (final closing in closings.values) closing: 0};
  for (var index = start; index < end; index++) {
    final unit = source.codeUnitAt(index);
    if (closings[unit] case final closing?) {
      balances[closing] = balances[closing]! - 1;
    } else if (balances.containsKey(unit)) {
      balances[unit] = balances[unit]! + 1;
    }
  }
  while (end > start) {
    final closing = source.codeUnitAt(end - 1);
    if ((balances[closing] ?? 0) <= 0) break;
    balances[closing] = balances[closing]! - 1;
    end--;
  }
  return end;
}

String? _normalizedLinkifyUrl(String raw, Set<String> tlds) {
  final lower = raw.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('ftp://') ||
      lower.startsWith('//')) {
    return raw;
  }

  final at = raw.lastIndexOf('@');
  final hostAndPath = at < 0 ? raw : raw.substring(at + 1);
  final boundary = hostAndPath.indexOf(_linkifyHostBoundaryPattern);
  final host = (boundary < 0 ? hostAndPath : hostAndPath.substring(0, boundary))
      .toLowerCase();
  final dot = host.lastIndexOf('.');
  if (dot < 0 || !tlds.contains(host.substring(dot + 1))) return null;
  return at < 0 ? 'http://$raw' : 'mailto:$raw';
}

bool _hasLinkifyBoundary(String source, int start) {
  if (start == 0) return true;
  final previous = source.codeUnitAt(start - 1);
  return !_isAsciiLetterOrNumber(previous) &&
      previous != 0x5F &&
      previous != 0x40;
}

bool _isAsciiLetterOrNumber(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A);

/// The `(start, end)` of each linkify candidate in [source], in source order.
///
/// A candidate is what this pattern matches case-insensitively, leftmost first
/// and resuming after each match:
///
/// ```text
/// (?:(?:https?|ftp)://|//)[^\s<]+
/// |[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@HOST
/// |HOST(?::[0-9]{1,5})?(?:[/?#][^\s<]*)?
/// ```
///
/// where HOST is `(?:LABEL\.)+[A-Za-z]{2,63}` and LABEL is
/// `[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?`.
///
/// It is scanned rather than matched because it runs on every keystroke. A
/// regular expression re-reads a run without spaces from each start in it,
/// looking for the `@` or the top-level domain the start before it already
/// failed to find, so a pasted token costs the square of its length. Every
/// start in a run shares where the run ends, and every dot in a host shares
/// where its labels end, so the scan works each out once.
@visibleForTesting
List<(int, int)> composerLinkifyCandidates(String source) {
  final scanner = _LinkifyScanner(source);
  final candidates = <(int, int)>[];
  for (var start = 0; start < source.length;) {
    final end = scanner.endAt(start);
    if (end < 0) {
      start += 1;
    } else {
      candidates.add((start, end));
      start = end;
    }
  }
  return candidates;
}

const _maxLabelLength = 63;

final class _LinkifyScanner {
  _LinkifyScanner(this.source);

  final String source;

  // Starts arrive in increasing order, so each run below stays valid for
  // every start until one passes its end.
  var _localPartEnd = -1;
  var _emailEnd = -1;
  var _labelRunEnd = -1;
  // The dots of the host chain walked last, and where its domain starts.
  var _chainFirstDot = -1;
  var _chainLastDot = -1;
  var _chainTld = -1;

  /// The end of the candidate at [start], or -1, trying the alternatives in
  /// the pattern's order.
  int endAt(int start) {
    final url = _urlEndAt(start);
    if (url >= 0) return url;
    final email = _emailEndAt(start);
    if (email >= 0) return email;
    return _hostEndAt(start);
  }

  int _urlEndAt(int start) {
    var at = start;
    if (_unitAt(at) == 0x2F) {
      if (_unitAt(at + 1) != 0x2F) return -1;
      at += 2;
    } else {
      if (_startsWithLetters(at, 'http')) {
        at += 4;
        final unit = _unitAt(at);
        if ((unit | 0x20) == 0x73 || unit == 0x17F) at += 1;
      } else if (_startsWithLetters(at, 'ftp')) {
        at += 3;
      } else {
        return -1;
      }
      if (!source.startsWith('://', at)) return -1;
      at += 3;
    }
    if (at >= source.length || _endsLinkifyUrl(source.codeUnitAt(at))) {
      return -1;
    }
    return _urlRunEnd(at + 1);
  }

  int _emailEndAt(int start) {
    if (!_isEmailLocalPart(source.codeUnitAt(start))) return -1;
    if (start >= _localPartEnd) {
      var at = start + 1;
      while (at < source.length && _isEmailLocalPart(source.codeUnitAt(at))) {
        at += 1;
      }
      _localPartEnd = at;
      final dot = _unitAt(at) == 0x40 ? _labelDot(at + 1) : -1;
      final tld = dot < 0 ? -1 : _tldAfter(dot);
      _emailEnd = tld < 0 ? -1 : _tldEnd(tld);
    }
    return _emailEnd;
  }

  int _hostEndAt(int start) {
    if (!_isLabelEdge(source.codeUnitAt(start))) return -1;
    if (start >= _labelRunEnd) {
      var at = start + 1;
      while (at < source.length && _isLabelCharacter(source.codeUnitAt(at))) {
        at += 1;
      }
      _labelRunEnd = at;
    }
    final dot = _labelRunEnd;
    if (dot - start > _maxLabelLength || !_endsLabel(dot)) return -1;
    final tld = _tldAfter(dot);
    if (tld < 0) return -1;

    var end = _tldEnd(tld);
    if (_unitAt(end) == 0x3A && _isAsciiDigit(_unitAt(end + 1))) {
      final portLimit = end + 6;
      end += 2;
      while (end < portLimit && _isAsciiDigit(_unitAt(end))) {
        end += 1;
      }
    }
    final unit = _unitAt(end);
    if (unit == 0x2F || unit == 0x3F || unit == 0x23) end = _urlRunEnd(end + 1);
    return end;
  }

  /// Where the domain after the label ending at [dot] starts, or -1.
  ///
  /// `(?:LABEL\.)+` takes every further label that ends in a dot, then gives
  /// them back one at a time until two letters follow the last dot it kept.
  /// Every dot of that chain reaches the same last dot, so it settles on the
  /// same domain as the first one, or on none once past it.
  int _tldAfter(int dot) {
    if (dot < _chainFirstDot || dot > _chainLastDot) {
      var last = dot;
      for (
        var next = _labelDot(dot + 1);
        next >= 0;
        next = _labelDot(next + 1)
      ) {
        last = next;
      }
      var tld = -1;
      for (var at = last; ; at = source.lastIndexOf('.', at - 1)) {
        if (_isLinkifyLetter(_unitAt(at + 1)) &&
            _isLinkifyLetter(_unitAt(at + 2))) {
          tld = at + 1;
          break;
        }
        if (at == dot) break;
      }
      _chainFirstDot = dot;
      _chainLastDot = last;
      _chainTld = tld;
    }
    return dot < _chainTld ? _chainTld : -1;
  }

  /// The dot that ends a label starting at [start], or -1.
  int _labelDot(int start) {
    if (!_isLabelEdge(_unitAt(start))) return -1;
    var at = start + 1;
    while (at - start <= _maxLabelLength && _isLabelCharacter(_unitAt(at))) {
      at += 1;
    }
    return at - start <= _maxLabelLength && _endsLabel(at) ? at : -1;
  }

  bool _endsLabel(int dot) =>
      _unitAt(dot) == 0x2E && _isLabelEdge(_unitAt(dot - 1));

  int _tldEnd(int start) {
    var at = start + 2;
    while (at - start < _maxLabelLength && _isLinkifyLetter(_unitAt(at))) {
      at += 1;
    }
    return at;
  }

  int _urlRunEnd(int start) {
    var at = start;
    while (at < source.length && !_endsLinkifyUrl(source.codeUnitAt(at))) {
      at += 1;
    }
    return at;
  }

  bool _startsWithLetters(int start, String lowercase) {
    for (var index = 0; index < lowercase.length; index += 1) {
      if ((_unitAt(start + index) | 0x20) != lowercase.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }

  int _unitAt(int index) =>
      index < source.length ? source.codeUnitAt(index) : -1;
}

// ASCII letters as a case-insensitive Unicode pattern reads them: case folding
// maps ſ (U+017F) onto s and the Kelvin sign (U+212A) onto k.
bool _isLinkifyLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x17F ||
    unit == 0x212A;

bool _isAsciiDigit(int unit) => unit >= 0x30 && unit <= 0x39;

bool _isLabelEdge(int unit) => _isLinkifyLetter(unit) || _isAsciiDigit(unit);

bool _isLabelCharacter(int unit) => unit == 0x2D || _isLabelEdge(unit);

// A letter, a digit, or one of .!#$%&'*+/=?^_`{|}~-
bool _isEmailLocalPart(int unit) =>
    _isLabelEdge(unit) ||
    switch (unit) {
      0x21 || 0x2A || 0x2B || 0x3D || 0x3F => true,
      >= 0x23 && <= 0x27 || >= 0x2D && <= 0x2F => true,
      >= 0x5E && <= 0x60 || >= 0x7B && <= 0x7E => true,
      _ => false,
    };

// `[^\s<]` stops at `<` and at `\s`, which Dart reads as ECMAScript's white
// space and line terminators.
bool _endsLinkifyUrl(int unit) =>
    unit == 0x3C ||
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

final class _LinkifyContext {
  _LinkifyContext(this.source);

  final String source;
  var _offset = 0;
  var _insideAngles = false;
  var _lineStart = 0;
  var _referenceLineStart = -1;
  var _referenceDestination = -1;

  bool isInHtmlOrReference(int start) {
    // Candidates arrive in source order and never start with an angle or LF.
    // Include text from skipped candidates when advancing to the next one.
    while (_offset < start) {
      final unit = source.codeUnitAt(_offset);
      if (unit == 0x3C) _insideAngles = true;
      if (unit == 0x3E) _insideAngles = false;
      if (unit == 0x0A) _lineStart = _offset + 1;
      _offset += 1;
    }
    if (_insideAngles) return true;

    if (_referenceLineStart != _lineStart) {
      _referenceLineStart = _lineStart;
      // Match at most once per line without copying its growing prefix. LF is
      // excluded from whitespace so the match cannot scan subsequent lines.
      _referenceDestination =
          _linkReferencePrefixPattern.matchAsPrefix(source, _lineStart)?.end ??
          -1;
    }
    return start == _referenceDestination;
  }
}
