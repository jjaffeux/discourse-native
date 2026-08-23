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
    return '![${composerImageAlt(alt ?? this.alt)}$dimensions]($url)';
  }
}

// The alt class excludes the backslash on purpose. Letting it match there as
// well as through `\\.` gives a run of backslashes one parse per backslash,
// and the engine tries all of them before an alt with no `](` after it can
// fail: forty of them in a composer that rescans on every keystroke is a
// freeze, not a slow frame. Excluding it also reads `\]` the way CommonMark
// does — as an escaped bracket that does not close the alt.
final RegExp _imagePattern = RegExp(
  r'!\[((?:\\.|[^\\\]\n])*)\]\(((?:upload://|https?://)[^)\s]+)(?:\s+"[^"]*")?\)',
  caseSensitive: false,
);

// The ", N%" scale is only syntax after "|WxH", mirroring Discourse's own
// image-scale pattern; without dimensions the suffix is the author's alt text.
final RegExp _labelPattern = RegExp(
  r'^(.*?)(?:\|(\d{1,4})x(\d{1,4})(?:,\s*(\d{1,3})%)?)?(?:\|.*)?$',
);

/// [codeRanges] lets a caller that has already scanned [source] hand its
/// answer over. The scan is the expensive half of this, and the composer runs
/// it once for its own highlighting before asking any of these parsers
/// anything — without this each of them would repeat it on every keystroke.
List<ComposerImageBlock> parseComposerImages(
  String source, {
  CodeRanges? codeRanges,
}) {
  if (source.isEmpty) return const [];
  final code = codeRanges ?? CodeRanges.of(scanMarkdown(source));
  final images = <ComposerImageBlock>[];
  // Matched one opener at a time rather than with `allMatches`, so a line
  // shown to hold no `]` is not rediscovered at every `![` on it. The alt
  // cannot cross a newline, so a `]` somewhere on the line is necessary for a
  // match; without one the pattern would still walk to the line's end per
  // opener, which on one long line is quadratic.
  var offset = 0;
  var barrenTo = -1;
  var lineEnd = -1;
  while (offset < source.length) {
    final start = source.indexOf('![', offset);
    if (start < 0) break;
    if (start < barrenTo) {
      offset = start + 1;
      continue;
    }
    if (start >= lineEnd) {
      final next = source.indexOf('\n', start + 1);
      lineEnd = next < 0 ? source.length : next;
    }
    final bracket = source.indexOf(']', start + 2);
    if (bracket < 0) break;
    if (bracket > lineEnd) {
      barrenTo = lineEnd;
      offset = start + 1;
      continue;
    }

    final match = _imagePattern.matchAsPrefix(source, start);
    if (match == null) {
      offset = start + 1;
      continue;
    }
    offset = match.end;
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

/// [value] with what cannot appear inside an image alt taken out.
///
/// Two different questions, and both have to be answered before an alt is
/// written. A bracket, a backtick or a backslash survives a round trip,
/// because [escapeImageAlt] writes it and the parser reads it back. A `|` and
/// a line ending have no such spelling: the first opens the `|WxH` suffix, so
/// everything after it is read as dimensions and the rest of the alt is lost,
/// and the second ends the image outright — the markdown stops being an image
/// at all, to the site and to this composer's own projection. So they come out
/// here rather than going in.
///
/// Both become a space rather than nothing, because both were separating
/// something, and runs of space are then collapsed so a name that had a
/// bracket and a bar next to each other does not come out with a gap in it.
String flattenImageAlt(String value) =>
    value.replaceAll(_altSeparators, ' ').replaceAll(_altSpaceRuns, ' ').trim();

/// [value] as an image alt: flattened, then escaped. Every writer of one goes
/// through here — an upload's filename and a GIF's title are the same problem.
String composerImageAlt(String value) => escapeImageAlt(flattenImageAlt(value));

String escapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'[\\\[\]`]'), (match) => '\\${match[0]}');

String unescapeImageAlt(String value) =>
    value.replaceAllMapped(RegExp(r'\\([\\\[\]`])'), (match) => match[1]!);

final RegExp _altSeparators = RegExp(r'[|\r\n]+');
final RegExp _altSpaceRuns = RegExp(r' {2,}');
