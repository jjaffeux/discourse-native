import 'package:flutter/material.dart';

/// Makes the source accounting behind a collapsed composer component
/// layout-neutral without changing any source offsets.
///
/// Component renderers flatten to the same UTF-16 length as [source]: a
/// [WidgetSpan] consumes one code unit and the remaining source is commonly
/// painted with zero-sized text. TextPainter still treats line endings in that
/// zero-sized text as real lines, though, and trailing zero-sized whitespace
/// can leave its end caret without measurable geometry. Project those code
/// units as zero-width characters instead. Each replacement still consumes
/// exactly one code unit, so editing, selection, and hit-testing offsets remain
/// lossless without adding placeholder widgets after EditableText has measured
/// a component's children.
///
/// This normalization happens at the shared controller boundary rather than
/// in individual component renderers. Core components and plugin syntax
/// projections therefore receive the same baseline behavior.
List<InlineSpan> normalizeCollapsedComponentSourceSpans({
  required String source,
  required List<InlineSpan> spans,
}) {
  final trailingWhitespaceStart = _trailingHorizontalWhitespaceStart(source);
  final normalizer = _CollapsedComponentSourceNormalizer(
    source: source,
    trailingWhitespaceStart: trailingWhitespaceStart,
  );
  final normalized = normalizer.normalize(spans);
  assert(
    normalizer.offset == source.length,
    'the component projection drifted from its source range',
  );
  return normalized;
}

int _trailingHorizontalWhitespaceStart(String source) {
  var offset = source.length;
  while (offset > 0) {
    final codeUnit = source.codeUnitAt(offset - 1);
    if (codeUnit != 0x20 && codeUnit != 0x09) break;
    offset--;
  }
  return offset;
}

final class _CollapsedComponentSourceNormalizer {
  _CollapsedComponentSourceNormalizer({
    required this.source,
    required this.trailingWhitespaceStart,
  });

  final String source;
  final int trailingWhitespaceStart;
  int offset = 0;

  List<InlineSpan> normalize(List<InlineSpan> spans) => [
    for (final span in spans) _normalizeSpan(span),
  ];

  InlineSpan _normalizeSpan(InlineSpan span, [TextStyle? inheritedStyle]) {
    if (span is WidgetSpan) {
      offset++;
      return span;
    }

    final textSpan = span as TextSpan;
    final effectiveStyle = switch ((inheritedStyle, textSpan.style)) {
      (final inherited?, final own?) => inherited.merge(own),
      (final inherited?, null) => inherited,
      (null, final own?) => own,
      (null, null) => null,
    };
    final originalText = textSpan.text;
    final originalChildren = textSpan.children;
    final normalizedText = originalText == null
        ? null
        : _normalizeText(originalText, effectiveStyle);
    final normalizedChildren = originalChildren == null
        ? null
        : [
            for (final child in originalChildren)
              _normalizeSpan(child, effectiveStyle),
          ];

    final textChanged = normalizedText != null;
    final childrenChanged =
        originalChildren != null &&
        normalizedChildren!.indexed.any(
          (entry) => !identical(entry.$2, originalChildren[entry.$1]),
        );
    if (!textChanged && !childrenChanged) return textSpan;

    return TextSpan(
      text: normalizedText ?? originalText,
      style: textSpan.style,
      children: normalizedChildren,
      recognizer: textSpan.recognizer,
      mouseCursor: textSpan.mouseCursor,
      onEnter: textSpan.onEnter,
      onExit: textSpan.onExit,
      semanticsLabel: textSpan.semanticsLabel,
      semanticsIdentifier: textSpan.semanticsIdentifier,
      locale: textSpan.locale,
      spellOut: textSpan.spellOut,
    );
  }

  String? _normalizeText(String text, TextStyle? effectiveStyle) {
    final startOffset = offset;
    final isLayoutNeutral =
        effectiveStyle?.fontSize == 0 || effectiveStyle?.height == 0;
    List<int>? result;

    for (var localOffset = 0; localOffset < text.length; localOffset++) {
      final sourceOffset = startOffset + localOffset;
      final codeUnit = text.codeUnitAt(localOffset);
      final isLineEnding = codeUnit == 0x0A || codeUnit == 0x0D;
      final isTrailingHorizontalWhitespace =
          sourceOffset >= trailingWhitespaceStart &&
          (codeUnit == 0x20 || codeUnit == 0x09);
      final matchesSource =
          sourceOffset < source.length &&
          source.codeUnitAt(sourceOffset) == codeUnit;
      if (!isLayoutNeutral ||
          !matchesSource ||
          (!isLineEnding && !isTrailingHorizontalWhitespace)) {
        continue;
      }

      result ??= List<int>.of(text.codeUnits);
      result[localOffset] = 0x200B;
    }

    offset += text.length;
    if (result == null) return null;
    return String.fromCharCodes(result);
  }
}
