import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'composer_images.dart';
import 'markdown_highlight.dart';

enum ComposerGalleryMode { grid, carousel }

/// Keeps native text edits out of an atomically projected image gallery.
///
/// A collapsed gallery preserves its raw source offsets with layout-neutral
/// text. Flutter can leave a visually trailing caret at one of those hidden
/// offsets. An insertion from that caret belongs after the gallery; partial
/// replacements of its implementation Markdown are rejected.
class ComposerImageGalleryInputFormatter extends TextInputFormatter {
  const ComposerImageGalleryInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return newValue;
    final galleries = parseComposerImageGalleries(oldValue.text);
    if (galleries.isEmpty) return newValue;

    var replacementStart = 0;
    final sharedLength = math.min(oldValue.text.length, newValue.text.length);
    while (replacementStart < sharedLength &&
        oldValue.text.codeUnitAt(replacementStart) ==
            newValue.text.codeUnitAt(replacementStart)) {
      replacementStart++;
    }
    var sharedSuffixLength = 0;
    while (sharedSuffixLength < oldValue.text.length - replacementStart &&
        sharedSuffixLength < newValue.text.length - replacementStart &&
        oldValue.text.codeUnitAt(
              oldValue.text.length - sharedSuffixLength - 1,
            ) ==
            newValue.text.codeUnitAt(
              newValue.text.length - sharedSuffixLength - 1,
            )) {
      sharedSuffixLength++;
    }
    final replacementEnd = oldValue.text.length - sharedSuffixLength;

    for (final gallery in galleries) {
      if (oldValue.selection.isValid &&
          oldValue.selection.isCollapsed &&
          oldValue.selection.extentOffset == replacementStart &&
          replacementStart == replacementEnd &&
          replacementStart > gallery.start &&
          replacementStart < gallery.end) {
        if (newValue.isComposingRangeValid && !newValue.composing.isCollapsed) {
          return oldValue;
        }
        final insertedEnd = newValue.text.length - sharedSuffixLength;
        final inserted = newValue.text.substring(replacementStart, insertedEnd);
        final caret = gallery.end + inserted.length;
        return TextEditingValue(
          text: oldValue.text.replaceRange(gallery.end, gallery.end, inserted),
          selection: TextSelection.collapsed(
            offset: caret,
            affinity: newValue.selection.affinity,
          ),
        );
      }

      if (replacementStart >= gallery.end || replacementEnd <= gallery.start) {
        continue;
      }
      final coversWholeGallery =
          replacementStart <= gallery.start && replacementEnd >= gallery.end;
      if (!coversWholeGallery) return oldValue;
    }
    return newValue;
  }
}

@immutable
class ComposerImageGalleryBlock {
  const ComposerImageGalleryBlock({
    required this.start,
    required this.end,
    required this.contentStart,
    required this.contentEnd,
    required this.source,
    required this.mode,
    required this.images,
  });

  final int start;
  final int end;
  final int contentStart;
  final int contentEnd;
  final String source;
  final ComposerGalleryMode mode;
  final List<ComposerImageBlock> images;

  int get length => end - start;

  bool containsOffset(int offset, {bool includeEnd = false}) =>
      offset >= start && (includeEnd ? offset <= end : offset < end);
}

List<ComposerImageGalleryBlock> parseComposerImageGalleries(
  String source, {
  CodeRanges? codeRanges,
}) {
  if (source.isEmpty || !source.contains('[', 0)) return const [];

  final code = codeRanges ?? CodeRanges.of(scanMarkdown(source));
  final images = parseComposerImages(source, codeRanges: code);
  final pairs = <_GalleryTagPair>[];
  final stack = <_OpenGalleryTag>[];
  var offset = 0;
  var imageIndex = 0;

  while (offset < source.length) {
    final opening = source.indexOf('[', offset);
    if (opening < 0) break;

    while (imageIndex < images.length && images[imageIndex].end <= opening) {
      imageIndex++;
    }
    if (imageIndex < images.length &&
        images[imageIndex].start <= opening &&
        opening < images[imageIndex].end) {
      // A URL can legally contain `[grid]`; it is part of the image token,
      // not a gallery boundary.
      offset = images[imageIndex].end;
      continue;
    }
    if (code.contains(opening) || _isEscapedTag(source, opening)) {
      offset = opening + 1;
      continue;
    }

    final tag = _galleryTagAt(source, opening);
    if (tag == null) {
      offset = opening + 1;
      continue;
    }
    offset = tag.end;

    if (tag.closing) {
      // A malformed closer must not complete an otherwise valid gallery.
      if (!tag.valid || stack.isEmpty) continue;
      final open = stack.removeLast();
      if (stack.isEmpty && open.valid && !open.hasNestedTag) {
        pairs.add(_GalleryTagPair(open.tag, tag));
      }
      continue;
    }

    if (stack.isNotEmpty) stack.last.hasNestedTag = true;
    stack.add(_OpenGalleryTag(tag, valid: tag.valid));
  }

  if (pairs.isEmpty) return const [];

  final galleries = <ComposerImageGalleryBlock>[];
  imageIndex = 0;
  for (final pair in pairs) {
    final contentStart = pair.open.end;
    final contentEnd = pair.close.start;
    while (imageIndex < images.length &&
        images[imageIndex].end <= contentStart) {
      imageIndex++;
    }

    final members = <ComposerImageBlock>[];
    var memberIndex = imageIndex;
    var cursor = contentStart;
    var valid = true;
    while (memberIndex < images.length &&
        images[memberIndex].start < contentEnd) {
      final image = images[memberIndex++];
      if (image.start < cursor ||
          image.end > contentEnd ||
          !_isGalleryWhitespace(source, cursor, image.start)) {
        valid = false;
        break;
      }
      members.add(image);
      cursor = image.end;
    }
    if (valid && !_isGalleryWhitespace(source, cursor, contentEnd)) {
      valid = false;
    }

    // Even a rejected pair is before every later pair, so none of the images
    // beginning inside it need to be reconsidered.
    while (memberIndex < images.length &&
        images[memberIndex].start < contentEnd) {
      memberIndex++;
    }
    imageIndex = memberIndex;
    if (!valid) continue;

    galleries.add(
      ComposerImageGalleryBlock(
        start: pair.open.start,
        end: pair.close.end,
        contentStart: contentStart,
        contentEnd: contentEnd,
        source: source.substring(pair.open.start, pair.close.end),
        mode: pair.open.mode!,
        images: List.unmodifiable(members),
      ),
    );
  }
  return List.unmodifiable(galleries);
}

ComposerImageGalleryBlock? galleryAtComposerOffset(
  Iterable<ComposerImageGalleryBlock> galleries,
  int offset,
) {
  for (final gallery in galleries) {
    // This mirrors [imageAtComposerOffset]: a caret immediately after an
    // atomic projection still belongs to it for keyboard selection purposes.
    if (gallery.containsOffset(offset, includeEnd: true)) return gallery;
  }
  return null;
}

String? wrapComposerImagesInGallery(
  String source,
  Iterable<ComposerImageBlock> images, {
  ComposerGalleryMode mode = ComposerGalleryMode.grid,
}) {
  final expected = images.toList()
    ..sort((left, right) => left.start.compareTo(right.start));
  if (expected.isEmpty) return null;

  final currentImages = parseComposerImages(source);
  final byRange = <(int, int), ComposerImageBlock>{
    for (final image in currentImages) (image.start, image.end): image,
  };
  final current = <ComposerImageBlock>[];
  for (final image in expected) {
    final match = byRange[(image.start, image.end)];
    if (match == null || match.source != image.source) return null;
    if (current.isNotEmpty && match.start < current.last.end) return null;
    current.add(match);
  }

  for (var index = 1; index < current.length; index++) {
    if (!_isGalleryWhitespace(
      source,
      current[index - 1].end,
      current[index].start,
    )) {
      return null;
    }
  }

  final start = current.first.start;
  final end = current.last.end;
  for (final gallery in parseComposerImageGalleries(source)) {
    if (gallery.start < end && start < gallery.end) return null;
  }
  return source.replaceRange(
    start,
    end,
    _canonicalGallery(current.map((image) => image.source), mode),
  );
}

String? setComposerImageGalleryMode(
  String source,
  ComposerImageGalleryBlock gallery,
  ComposerGalleryMode mode,
) {
  final current = _currentGallery(source, gallery);
  if (current == null) return null;
  if (current.mode == mode) return source;
  return source.replaceRange(
    current.start,
    current.contentStart,
    _openingTag(mode),
  );
}

String? unwrapComposerImageGallery(
  String source,
  ComposerImageGalleryBlock gallery,
) {
  final current = _currentGallery(source, gallery);
  if (current == null) return null;
  return source.replaceRange(
    current.start,
    current.end,
    current.images.map((image) => image.source).join('\n'),
  );
}

String? appendComposerImageToGallery(
  String source,
  ComposerImageGalleryBlock gallery,
  String imageMarkdown,
) {
  final current = _currentGallery(source, gallery);
  if (current == null || !_isSingleImageMarkdown(imageMarkdown)) return null;
  return source.replaceRange(
    current.start,
    current.end,
    _canonicalGallery([
      ...current.images.map((image) => image.source),
      imageMarkdown,
    ], current.mode),
  );
}

String? moveComposerImageIntoGallery(
  String source,
  ComposerImageGalleryBlock gallery,
  ComposerImageBlock image,
) {
  final currentGallery = _currentGallery(source, gallery);
  final currentImage = _currentImage(source, image);
  if (currentGallery == null || currentImage == null) return null;
  if (currentGallery.images.any(
    (member) =>
        member.start == currentImage.start && member.end == currentImage.end,
  )) {
    return null;
  }

  late final int start;
  late final int end;
  late final Iterable<String> members;
  if (currentImage.end <= currentGallery.start &&
      _isGalleryWhitespace(source, currentImage.end, currentGallery.start)) {
    start = currentImage.start;
    end = currentGallery.end;
    members = [
      currentImage.source,
      ...currentGallery.images.map((member) => member.source),
    ];
  } else if (currentGallery.end <= currentImage.start &&
      _isGalleryWhitespace(source, currentGallery.end, currentImage.start)) {
    start = currentGallery.start;
    end = currentImage.end;
    members = [
      ...currentGallery.images.map((member) => member.source),
      currentImage.source,
    ];
  } else {
    return null;
  }

  return source.replaceRange(
    start,
    end,
    _canonicalGallery(members, currentGallery.mode),
  );
}

String? moveComposerImageOutOfGallery(
  String source,
  ComposerImageGalleryBlock gallery,
  ComposerImageBlock image,
) {
  final (:galleryBlock, :member) = _currentMember(source, gallery, image);
  if (galleryBlock == null || member == null) return null;
  if (galleryBlock.images.length == 1) {
    return source.replaceRange(
      galleryBlock.start,
      galleryBlock.end,
      member.source,
    );
  }

  final remaining = galleryBlock.images.where(
    (candidate) =>
        candidate.start != member.start || candidate.end != member.end,
  );
  final replacement =
      '${_canonicalGallery(remaining.map((item) => item.source), galleryBlock.mode)}\n'
      '${member.source}';
  return source.replaceRange(galleryBlock.start, galleryBlock.end, replacement);
}

String? deleteComposerImageFromGallery(
  String source,
  ComposerImageGalleryBlock gallery,
  ComposerImageBlock image,
) {
  final (:galleryBlock, :member) = _currentMember(source, gallery, image);
  if (galleryBlock == null || member == null) return null;
  if (galleryBlock.images.length == 1) {
    return source.replaceRange(galleryBlock.start, galleryBlock.end, '');
  }

  return source.replaceRange(
    galleryBlock.start,
    galleryBlock.end,
    _canonicalGallery(
      galleryBlock.images
          .where(
            (candidate) =>
                candidate.start != member.start || candidate.end != member.end,
          )
          .map((candidate) => candidate.source),
      galleryBlock.mode,
    ),
  );
}

ComposerImageGalleryBlock? _currentGallery(
  String source,
  ComposerImageGalleryBlock expected,
) {
  if (expected.start < 0 ||
      expected.end < expected.start ||
      expected.end > source.length ||
      expected.source.length != expected.end - expected.start ||
      !source.startsWith(expected.source, expected.start)) {
    return null;
  }
  for (final current in parseComposerImageGalleries(source)) {
    if (current.start == expected.start &&
        current.end == expected.end &&
        current.contentStart == expected.contentStart &&
        current.contentEnd == expected.contentEnd &&
        current.source == expected.source &&
        current.mode == expected.mode) {
      return current;
    }
  }
  return null;
}

ComposerImageBlock? _currentImage(String source, ComposerImageBlock expected) {
  if (expected.start < 0 ||
      expected.end < expected.start ||
      expected.end > source.length ||
      expected.source.length != expected.end - expected.start ||
      !source.startsWith(expected.source, expected.start)) {
    return null;
  }
  for (final current in parseComposerImages(source)) {
    if (current.start == expected.start &&
        current.end == expected.end &&
        current.source == expected.source) {
      return current;
    }
  }
  return null;
}

({ComposerImageGalleryBlock? galleryBlock, ComposerImageBlock? member})
_currentMember(
  String source,
  ComposerImageGalleryBlock gallery,
  ComposerImageBlock image,
) {
  final current = _currentGallery(source, gallery);
  if (current == null) return (galleryBlock: null, member: null);
  for (final member in current.images) {
    if (member.start == image.start &&
        member.end == image.end &&
        member.source == image.source) {
      return (galleryBlock: current, member: member);
    }
  }
  return (galleryBlock: null, member: null);
}

bool _isSingleImageMarkdown(String source) {
  if (source.isEmpty) return false;
  final images = parseComposerImages(source);
  return images.length == 1 &&
      images.single.start == 0 &&
      images.single.end == source.length;
}

String _canonicalGallery(Iterable<String> members, ComposerGalleryMode mode) {
  final sources = members.toList();
  final content = sources.isEmpty ? '' : '${sources.join('\n')}\n';
  return '${_openingTag(mode)}\n$content[/grid]';
}

String _openingTag(ComposerGalleryMode mode) => switch (mode) {
  ComposerGalleryMode.grid => '[grid]',
  ComposerGalleryMode.carousel => '[grid mode=carousel]',
};

bool _isGalleryWhitespace(String source, int start, int end) {
  if (start < 0 || end < start || end > source.length) return false;
  for (var index = start; index < end; index++) {
    if (switch (source.codeUnitAt(index)) {
      0x09 || 0x0a || 0x0d || 0x20 => false,
      _ => true,
    }) {
      return false;
    }
  }
  return true;
}

bool _isEscapedTag(String source, int opening) {
  var backslashes = 0;
  for (
    var index = opening - 1;
    index >= 0 && source.codeUnitAt(index) == 0x5c;
    index--
  ) {
    backslashes++;
  }
  return backslashes.isOdd;
}

final RegExp _validOpenTag = RegExp(
  r'^grid(?:[ \t]+mode[ \t]*=[ \t]*(grid|carousel))?[ \t]*$',
  caseSensitive: false,
);
final RegExp _validCloseTag = RegExp(r'^/grid[ \t]*$', caseSensitive: false);
final RegExp _gridName = RegExp(r'^grid(?:$|[ \t=])', caseSensitive: false);
final RegExp _closingGridName = RegExp(
  r'^/grid(?:$|[ \t=])',
  caseSensitive: false,
);
final RegExp _unterminatedGridName = RegExp(
  r'^grid(?:$|[ \t=\r\n])',
  caseSensitive: false,
);
final RegExp _unterminatedClosingGridName = RegExp(
  r'^/grid(?:$|[ \t=\r\n])',
  caseSensitive: false,
);

// Valid gallery tags are short. Bounding a malformed candidate prevents a
// line with thousands of `[grid ` openers and one distant `]` from rescanning
// the same suffix once per opener.
const int _maximumGalleryTagLength = 64;

_GalleryTag? _galleryTagAt(String source, int opening) {
  final limit = (opening + _maximumGalleryTagLength).clamp(0, source.length);
  var close = -1;
  for (var index = opening + 1; index < limit; index++) {
    final codeUnit = source.codeUnitAt(index);
    if (codeUnit == 0x0a || codeUnit == 0x0d) break;
    if (codeUnit == 0x5d) {
      close = index;
      break;
    }
  }
  if (close < 0) {
    // An overlong or unterminated grid-shaped opener still makes everything
    // beneath it ambiguous. Track the short name prefix without searching for
    // a distant `]`, retaining the linear bound above while preventing a
    // valid-looking inner pair from being projected as an independent grid.
    final prefixEnd = (opening + 8).clamp(0, source.length);
    final prefix = source.substring(opening + 1, prefixEnd);
    final closing = _unterminatedClosingGridName.hasMatch(prefix);
    if (!closing && !_unterminatedGridName.hasMatch(prefix)) return null;
    return _GalleryTag(
      start: opening,
      end: (opening + (closing ? 6 : 5)).clamp(0, source.length),
      closing: closing,
      valid: false,
    );
  }

  final body = source.substring(opening + 1, close);
  final open = _validOpenTag.firstMatch(body);
  if (open != null) {
    final value = open.group(1)?.toLowerCase();
    return _GalleryTag(
      start: opening,
      end: close + 1,
      closing: false,
      valid: true,
      mode: value == 'carousel'
          ? ComposerGalleryMode.carousel
          : ComposerGalleryMode.grid,
    );
  }
  if (_validCloseTag.hasMatch(body)) {
    return _GalleryTag(
      start: opening,
      end: close + 1,
      closing: true,
      valid: true,
    );
  }

  // Track malformed grid-shaped openers so a valid-looking pair nested in
  // one is not projected out of ambiguous source.
  if (_gridName.hasMatch(body)) {
    return _GalleryTag(
      start: opening,
      end: close + 1,
      closing: false,
      valid: false,
    );
  }
  if (_closingGridName.hasMatch(body)) {
    return _GalleryTag(
      start: opening,
      end: close + 1,
      closing: true,
      valid: false,
    );
  }
  return null;
}

@immutable
class _GalleryTag {
  const _GalleryTag({
    required this.start,
    required this.end,
    required this.closing,
    required this.valid,
    this.mode,
  });

  final int start;
  final int end;
  final bool closing;
  final bool valid;
  final ComposerGalleryMode? mode;
}

class _OpenGalleryTag {
  _OpenGalleryTag(this.tag, {required this.valid});

  final _GalleryTag tag;
  final bool valid;
  bool hasNestedTag = false;
}

@immutable
class _GalleryTagPair {
  const _GalleryTagPair(this.open, this.close);

  final _GalleryTag open;
  final _GalleryTag close;
}
