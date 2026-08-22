import 'package:flutter/foundation.dart';

import '../models/composer_upload.dart';
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
    return '![${escapeImageAlt(alt ?? this.alt)}$dimensions]($url)';
  }
}

final RegExp _imagePattern = RegExp(
  r'!\[((?:\\.|[^\]\n])*)\]\(((?:upload://|https?://)[^)\s]+)(?:\s+"[^"]*")?\)',
  caseSensitive: false,
);

// The ", N%" scale is only syntax after "|WxH", mirroring Discourse's own
// image-scale pattern; without dimensions the suffix is the author's alt text.
final RegExp _labelPattern = RegExp(
  r'^(.*?)(?:\|(\d{1,4})x(\d{1,4})(?:,\s*(\d{1,3})%)?)?(?:\|.*)?$',
);

List<ComposerImageBlock> parseComposerImages(String source) {
  if (source.isEmpty) return const [];
  final code = CodeRanges.of(scanMarkdown(source));
  final images = <ComposerImageBlock>[];
  for (final match in _imagePattern.allMatches(source)) {
    if (code.overlaps(match.start, match.end)) continue;
    final label = _labelPattern.firstMatch(match.group(1)!);
    if (label == null) continue;
    final width = int.tryParse(label.group(2) ?? '');
    final height = int.tryParse(label.group(3) ?? '');
    final hasValidDimensions =
        width != null && width > 0 && height != null && height > 0;
    final scale = int.tryParse(label.group(4) ?? '');
    images.add(
      ComposerImageBlock(
        start: match.start,
        end: match.end,
        source: match.group(0)!,
        alt: unescapeImageAlt(label.group(1)!),
        url: match.group(2)!,
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

String uploadImageMarkdown(ComposerUploadResult upload) {
  final filename = upload.originalFilename;
  final dot = filename.lastIndexOf('.');
  final base = (dot > 0 ? filename.substring(0, dot) : filename).replaceAll(
    RegExp(r'[\[\]\|]'),
    '',
  );
  final width = upload.markdownWidth;
  final height = upload.markdownHeight;
  final dimensions = width == null || height == null ? '' : '|${width}x$height';
  return '![${escapeImageAlt(base)}$dimensions](${upload.shortUrl})';
}

String escapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'[\\\[\]`]'), (match) => '\\${match[0]}');

String unescapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'\\([\\\[\]`])'), (match) => match[1]!);
