import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

import '../../../models/composer_upload.dart';
import '../../../models/site_config.dart';
import '../markdown_highlight.dart';

@immutable
class ComposerImageBlock {
  const ComposerImageBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.alt,
    required this.url,
    this.width,
    this.height,
    this.scale,
    this.markdownDestination,
  });

  final int start;
  final int end;
  final String source;
  final String alt;
  final String url;
  final int? width;
  final int? height;
  final int? scale;
  final String? markdownDestination;

  bool get hasDimensions => width != null && height != null;

  String toMarkdown({String? alt, int? width, int? height, int? scale}) {
    final nextWidth = width ?? this.width;
    final nextHeight = height ?? this.height;
    final nextScale = scale ?? this.scale;
    final dimensions = nextWidth != null && nextHeight != null
        ? '|${nextWidth}x$nextHeight${nextScale == null ? '' : ', $nextScale%'}'
        : '';
    return '![${composerImageAlt(alt ?? this.alt)}$dimensions]'
        '(${markdownDestination ?? url})';
  }
}

@immutable
final class ComposerVideoBlock {
  const ComposerVideoBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.title,
    required this.url,
  });

  final int start;
  final int end;
  final String source;
  final String title;
  final String url;
}

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

// The ", N%" scale is only syntax after "|WxH", mirroring Discourse's own
// image-scale pattern; without dimensions the suffix is the author's alt text.
final RegExp _labelPattern = RegExp(
  r'^(.*?)(?:\|(\d{1,4})x(\d{1,4})(?:,\s*(\d{1,3})%)?)?(?:\|.*)?$',
);

// Core's `IMG_SIZE_REGEX`, restated so that no run of digits can be divided
// between two quantifiers: `[1-9]+[0-9]*` accepts the same strings.
final RegExp _imageSizeSuffixPattern = RegExp(
  r'[1-9][0-9]*x[1-9][0-9]*(?:\s*,\s*x?[1-9][0-9]{0,2}[%x]?)?$',
);
// Core's `extractDataAttribute`: a `key=value` segment whose key is a valid
// `data-` attribute name.
final RegExp _dataAttributeSuffixPattern = RegExp(r'[\w\-:.]*=');

// Core draws an image token as a player when the run of known `|` suffixes
// ending its alt starts with `video` or `audio` (`isKnownImageSuffix` in
// discourse-markdown-it's engine). As an image block that media would be
// fetched as a picture, and rewriting the block would drop the suffix, so it
// stays out of image projections.
({String title, String media})? _playableMediaLabel(String label) {
  if (!label.contains('|')) return null;
  final segments = label.split('|');
  var first = segments.length;
  while (first > 1 && _isKnownImageSuffix(segments[first - 1])) {
    first -= 1;
  }
  if (first == segments.length ||
      (segments[first] != 'video' && segments[first] != 'audio')) {
    return null;
  }
  return (
    title: unescapeImageAlt(segments.take(first).join('|')),
    media: segments[first],
  );
}

bool _isKnownImageSuffix(String segment) =>
    segment == 'video' ||
    segment == 'audio' ||
    segment == 'thumbnail' ||
    _imageSizeSuffixPattern.matchAsPrefix(segment) != null ||
    _dataAttributeSuffixPattern.matchAsPrefix(segment) != null;

List<ComposerImageBlock> parseComposerImages(
  String source, {
  CodeRanges? codeRanges,
}) {
  if (!source.contains('![')) return const [];
  final images = <ComposerImageBlock>[];
  for (final token in _imageTokens(source, codeRanges: codeRanges)) {
    if (token.escaped || _playableMediaLabel(token.label) != null) continue;
    final label = _labelPattern.firstMatch(token.label);
    if (label == null) continue;
    final width = int.tryParse(label.group(2) ?? '');
    final height = int.tryParse(label.group(3) ?? '');
    final hasValidDimensions =
        width != null && width > 0 && height != null && height > 0;
    final scale = int.tryParse(label.group(4) ?? '');
    images.add(
      ComposerImageBlock(
        start: token.start,
        end: token.end,
        source: token.source,
        alt: unescapeImageAlt(label.group(1)!),
        url: token.url,
        markdownDestination: token.destination,
        width: hasValidDimensions ? width : null,
        height: hasValidDimensions ? height : null,
        scale: scale != null && scale >= 1 && scale <= 100 ? scale : null,
      ),
    );
  }
  return List.unmodifiable(images);
}

List<ComposerVideoBlock> parseComposerVideos(
  String source, {
  CodeRanges? codeRanges,
}) {
  if (!source.contains('|video')) return const [];
  return List.unmodifiable([
    for (final token in _imageTokens(source, codeRanges: codeRanges))
      if (!token.escaped)
        if (_playableMediaLabel(token.label) case final label?
            when label.media == 'video')
          ComposerVideoBlock(
            start: token.start,
            end: token.end,
            source: token.source,
            title: label.title,
            url: token.url,
          ),
  ]);
}

typedef _ImageToken = ({
  int start,
  int end,
  String source,
  String label,
  String url,
  String destination,
  bool escaped,
});

Iterable<_ImageToken> _imageTokens(
  String source, {
  CodeRanges? codeRanges,
}) sync* {
  // Every image starts with its opener; without one, skip the markdown scan.
  if (!source.contains('![')) return;
  final code = codeRanges ?? markdownCodeRanges(source);
  var offset = 0;
  var paragraphEnd = -1;
  final destinationEnds = <int, int>{};
  while (offset < source.length) {
    final start = source.indexOf('![', offset);
    if (start < 0) break;

    // Openers inside this alt share its stopping point, including an unfinished
    // escape or a closer with an invalid destination. None can succeed if this
    // one fails, so do not retry the same suffix for each nested `![`.
    final alt = _imageAltPattern.matchAsPrefix(source, start)!;
    final bracket = alt.end;
    offset = bracket + 1;
    if (!source.startsWith('](', bracket)) continue;
    if (start >= paragraphEnd) {
      paragraphEnd =
          _imageParagraphBreak.allMatches(source, start).firstOrNull?.start ??
          source.length;
    }
    final destination = _imageDestination(
      source,
      bracket + 2,
      paragraphEnd,
      destinationEnds,
    );
    if (destination == null) continue;
    final (:urlStart, :urlEnd, :end) = destination;

    offset = end;
    if (code.overlaps(start, end)) continue;
    var slashes = 0;
    for (var at = start - 1; at >= 0 && source.codeUnitAt(at) == 0x5c; at--) {
      slashes++;
    }
    yield (
      start: start,
      end: end,
      source: source.substring(start, end),
      label: alt.group(1)!,
      url: _unescapeImageDestination(source.substring(urlStart, urlEnd)),
      destination: source.substring(bracket + 2, end - 1),
      escaped: slashes.isOdd,
    );
  }
}

typedef _ImageDestination = ({int urlStart, int urlEnd, int end});

_ImageDestination? _imageDestination(
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

final _imageDestinationEscape = RegExp(
  r'\\([!-/:-@\[-`{-~])|&([a-z#][a-z0-9]{1,31});',
  caseSensitive: false,
);

String _unescapeImageDestination(String value) =>
    value.replaceAllMapped(_imageDestinationEscape, (match) {
      if (match[1] case final escaped?) return escaped;
      final entity = match[2]!;
      if (entity.startsWith('#')) {
        final hex = entity.length > 1 && entity[1].toLowerCase() == 'x';
        final code = int.tryParse(
          entity.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        if (code == null ||
            code <= 8 ||
            code == 11 ||
            code >= 14 && code <= 31 ||
            code >= 127 && code <= 159 ||
            code >= 0xd800 && code <= 0xdfff ||
            code >= 0xfdd0 && code <= 0xfdef ||
            (code & 0xffff) >= 0xfffe ||
            code > 0x10ffff) {
          return match[0]!;
        }
        return String.fromCharCode(code);
      }
      // Attribute parsing leaves unknown named entities intact instead of
      // accepting a legacy semicolon-free prefix from their name.
      return html
          .parseFragment('<i data-url="${match[0]}"></i>')
          .querySelector('i')!
          .attributes['data-url']!;
    });

ComposerImageBlock? imageAtComposerOffset(
  Iterable<ComposerImageBlock> images,
  int offset,
) => images
    .where((image) => offset >= image.start && offset <= image.end)
    .firstOrNull;

// Core's `isVideo` and `isAudio` in `lib/uploads.js`.
final RegExp _videoFilenamePattern = RegExp(
  r'\.(?:mov|mp4|webm|m4v|3gp|ogv|avi|mpeg)$',
  caseSensitive: false,
);
final RegExp _audioFilenamePattern = RegExp(
  r'\.(?:mp3|og[ga]|opus|wav|m4[abpr]|aac|flac)$',
  caseSensitive: false,
);

bool isComposerVideoFilename(String filename) =>
    _videoFilenamePattern.hasMatch(filename);

/// Mirrors core's `getUploadMarkdown`, except that other files stay plain
/// links: core writes `[name|attachment](url) (size)`, and the composer draws
/// a link's label verbatim, marker included.
String uploadFileMarkdown(ComposerUploadResult upload) {
  final filename = upload.originalFilename;
  if (SiteConfig.isImageFilename(filename)) return uploadImageMarkdown(upload);
  final media = _audioFilenamePattern.hasMatch(filename)
      ? 'audio'
      : isComposerVideoFilename(filename)
      ? 'video'
      : null;
  if (media == null) {
    return '[${composerImageAlt(filename)}](${upload.shortUrl})';
  }
  final alt = composerImageAlt(_uploadCaption(filename));
  return '![$alt|$media](${upload.shortUrl})';
}

String uploadImageMarkdown(ComposerUploadResult upload) {
  final width = upload.markdownWidth;
  final height = upload.markdownHeight;
  final dimensions = width == null || height == null ? '' : '|${width}x$height';
  final alt = composerImageAlt(_uploadCaption(upload.originalFilename));
  return '![$alt$dimensions](${upload.shortUrl})';
}

String _uploadCaption(String filename) {
  final dot = filename.lastIndexOf('.');
  // Brackets are dropped from a *filename* rather than escaped: the alt is a
  // caption the app invented from a name, and a name is better read without
  // them than with backslashes through it.
  final base = (dot > 0 ? filename.substring(0, dot) : filename).replaceAll(
    RegExp(r'[\[\]]'),
    '',
  );
  // The iOS photo library names every photo after a temporary file. Like
  // core's `markdownNameFromFileName` for a GUID name, caption it for what
  // it is rather than have a screen reader spell the GUID out.
  return _photoLibraryTemporaryName.hasMatch(base) ? 'image' : base;
}

/// `image_picker_` and `NSProcessInfo.globallyUniqueString`.
final RegExp _photoLibraryTemporaryName = RegExp(
  r'^image_picker_[0-9a-f]{8}-[0-9a-f-]+$',
  caseSensitive: false,
);

String flattenImageAlt(String value) =>
    value.replaceAll(_altSeparators, ' ').replaceAll(_altSpaceRuns, ' ').trim();

String composerImageAlt(String value) => escapeImageAlt(flattenImageAlt(value));

String escapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'[\\\[\]`]'), (match) => '\\${match[0]}');

String unescapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'\\([\\\[\]`])'), (match) => match[1]!);

final RegExp _altSeparators = RegExp(r'[|\r\n]+');
final RegExp _altSpaceRuns = RegExp(r' {2,}');
