import 'package:flutter/foundation.dart';

import '../models/composer_upload.dart';
import '../models/site_config.dart';
import 'markdown_highlight.dart';

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
  });

  final int start;
  final int end;
  final String source;
  final String alt;
  final String url;
  final int? width;
  final int? height;
  final int? scale;

  bool get hasDimensions => width != null && height != null;

  String toMarkdown({String? alt, int? width, int? height, int? scale}) {
    final nextWidth = width ?? this.width;
    final nextHeight = height ?? this.height;
    final nextScale = scale ?? this.scale;
    final dimensions = nextWidth != null && nextHeight != null
        ? '|${nextWidth}x$nextHeight${nextScale == null ? '' : ', $nextScale%'}'
        : '';
    return '![${composerImageAlt(alt ?? this.alt)}$dimensions]($url)';
  }
}

// Let `\\.` own backslashes. Matching them in both branches causes explosive
// backtracking and misreads CommonMark's escaped `\]`.
final RegExp _imageAltPattern = RegExp(r'!\[((?:\\.|[^\\\]\n])*)');
final RegExp _imageSchemePattern = RegExp(
  r'\]\((?:upload://|https?://)',
  caseSensitive: false,
);
final RegExp _imageUrlEndPattern = RegExp(r'[)\s]');
final RegExp _imageTitlePattern = RegExp(r'\s+"[^"]*"\)');

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
// stays raw source.
bool _isPlayableMediaLabel(String label) {
  if (!label.contains('|')) return false;
  final segments = label.split('|');
  var first = segments.length;
  while (first > 1 && _isKnownImageSuffix(segments[first - 1])) {
    first -= 1;
  }
  return first < segments.length &&
      (segments[first] == 'video' || segments[first] == 'audio');
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
  // Every image starts with its opener; without one, skip the markdown scan.
  if (!source.contains('![')) return const [];
  final code = codeRanges ?? markdownCodeRanges(source);
  final images = <ComposerImageBlock>[];
  var offset = 0;
  var urlEnd = -1;
  var end = -1;
  while (offset < source.length) {
    final start = source.indexOf('![', offset);
    if (start < 0) break;

    // Openers inside this alt share its stopping point, including an unfinished
    // escape or a closer with an invalid destination. None can succeed if this
    // one fails, so do not retry the same suffix for each nested `![`.
    final alt = _imageAltPattern.matchAsPrefix(source, start)!;
    final bracket = alt.end;
    offset = bracket + 1;
    final scheme = _imageSchemePattern.matchAsPrefix(source, bracket);
    if (scheme == null) continue;

    // A failed URL/title can itself contain image openers. Retain the boundary
    // and title result while their URLs share the same non-whitespace run.
    if (scheme.end > urlEnd) {
      final boundary = source.indexOf(_imageUrlEndPattern, scheme.end);
      urlEnd = boundary < 0 ? source.length : boundary;
      end = -1;
      if (urlEnd < source.length) {
        end = source.codeUnitAt(urlEnd) == 0x29
            ? urlEnd + 1
            : _imageTitlePattern.matchAsPrefix(source, urlEnd)?.end ?? -1;
      }
    }
    if (scheme.end == urlEnd || end < 0) continue;

    offset = end;
    if (code.overlaps(start, end)) continue;
    final rawLabel = alt.group(1)!;
    if (_isPlayableMediaLabel(rawLabel)) continue;
    final label = _labelPattern.firstMatch(rawLabel);
    if (label == null) continue;
    final width = int.tryParse(label.group(2) ?? '');
    final height = int.tryParse(label.group(3) ?? '');
    final hasValidDimensions =
        width != null && width > 0 && height != null && height > 0;
    final scale = int.tryParse(label.group(4) ?? '');
    images.add(
      ComposerImageBlock(
        start: start,
        end: end,
        source: source.substring(start, end),
        alt: unescapeImageAlt(label.group(1)!),
        url: source.substring(bracket + 2, urlEnd),
        width: hasValidDimensions ? width : null,
        height: hasValidDimensions ? height : null,
        scale: scale != null && scale >= 1 && scale <= 100 ? scale : null,
      ),
    );
  }
  return List.unmodifiable(images);
}

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

/// Mirrors core's `getUploadMarkdown`, except that other files stay plain
/// links: core writes `[name|attachment](url) (size)`, and the composer draws
/// a link's label verbatim, marker included.
String uploadFileMarkdown(ComposerUploadResult upload) {
  final filename = upload.originalFilename;
  if (SiteConfig.isImageFilename(filename)) return uploadImageMarkdown(upload);
  final media = _audioFilenamePattern.hasMatch(filename)
      ? 'audio'
      : _videoFilenamePattern.hasMatch(filename)
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
