import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

import '../../../models/composer_upload.dart';
import '../../../models/site_config.dart';
import '../html_comments.dart';
import '../markdown_highlight.dart';
import '../markdown_tokens.dart';

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
  final literals = ComposerLiteralContainers(source);
  final code = literals.isEmpty
      ? codeRanges ?? markdownCodeRanges(source)
      : markdownCodeRanges(literals.mask(source));
  for (final token in ComposerMarkdownImageReader(
    source,
  ).tokens(excludesOpener: literals.contains)) {
    final boundary = token.boundary;
    final start = boundary.openerStart;
    final end = boundary.tokenEnd;
    if (code.overlaps(start, end)) continue;
    yield (
      start: start,
      end: end,
      source: source.substring(start, end),
      label: source.substring(boundary.labelStart, boundary.labelEnd),
      url: _unescapeImageDestination(
        source.substring(token.urlStart, token.urlEnd),
      ),
      destination: source.substring(boundary.destinationStart, end - 1),
      escaped: token.escaped,
    );
  }
}

final _imageDestinationEscape = RegExp(
  r'\\([!-/:-@\[-`{-~])|&([a-z#][a-z0-9]{1,31});',
  caseSensitive: false,
);

final _imageCoreNumericEntity = RegExp(
  r'^#(?:x[a-f0-9]{1,8}|[0-9]{1,8})$',
  caseSensitive: false,
);
final _imageHtmlNumericEntity = RegExp(
  r'^#(?:x[a-f0-9]+|[0-9]+)$',
  caseSensitive: false,
);

String _unescapeImageDestination(String value) =>
    value.replaceAllMapped(_imageDestinationEscape, (match) {
      if (match[1] case final escaped?) return escaped;
      final entity = match[2]!;
      if (entity.startsWith('#') && !_imageHtmlNumericEntity.hasMatch(entity)) {
        return match[0]!;
      }
      if (_imageCoreNumericEntity.hasMatch(entity)) {
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
      if (entity.startsWith('#')) {
        final hex = entity[1].toLowerCase() == 'x';
        final code = int.tryParse(
          entity.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        if (code == null || code < 0 || code > 0x10ffff) return '\ufffd';
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
