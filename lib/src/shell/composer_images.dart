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

List<ComposerImageBlock> parseComposerImages(
  String source, {
  CodeRanges? codeRanges,
}) {
  if (source.isEmpty) return const [];
  final code = codeRanges ?? CodeRanges.of(scanMarkdown(source));
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
    final label = _labelPattern.firstMatch(alt.group(1)!);
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

String uploadFileMarkdown(ComposerUploadResult upload) {
  if (SiteConfig.isImageFilename(upload.originalFilename)) {
    return uploadImageMarkdown(upload);
  }
  return '[${composerImageAlt(upload.originalFilename)}](${upload.shortUrl})';
}

String uploadImageMarkdown(ComposerUploadResult upload) {
  final filename = upload.originalFilename;
  final dot = filename.lastIndexOf('.');
  // Brackets are dropped from a *filename* rather than escaped: the alt is a
  // caption the app invented from a name, and a name is better read without
  // them than with backslashes through it.
  final base = (dot > 0 ? filename.substring(0, dot) : filename).replaceAll(
    RegExp(r'[\[\]]'),
    '',
  );
  final width = upload.markdownWidth;
  final height = upload.markdownHeight;
  final dimensions = width == null || height == null ? '' : '|${width}x$height';
  return '![${composerImageAlt(base)}$dimensions](${upload.shortUrl})';
}

String flattenImageAlt(String value) =>
    value.replaceAll(_altSeparators, ' ').replaceAll(_altSpaceRuns, ' ').trim();

String composerImageAlt(String value) => escapeImageAlt(flattenImageAlt(value));

String escapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'[\\\[\]`]'), (match) => '\\${match[0]}');

String unescapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'\\([\\\[\]`])'), (match) => match[1]!);

final RegExp _altSeparators = RegExp(r'[|\r\n]+');
final RegExp _altSpaceRuns = RegExp(r' {2,}');
