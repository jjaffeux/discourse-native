import 'package:flutter/widgets.dart';

/// Gives Flutter sole ownership of scaling embedded composer content.
///
/// WidgetSpan scales its entire child using the surrounding text's scaler.
/// Removing the inherited scaler inside that child prevents text, controls,
/// and nested editors from applying it again. Apply this to the final span
/// tree so core artwork and plugin projections share the same behavior.
InlineSpan normalizeComposerTextScaling(InlineSpan span) {
  if (span is ComposerWidgetSpan) return span;
  if (span is WidgetSpan) return ComposerWidgetSpan(span);
  if (span is! TextSpan || span.children == null) return span;

  final children = span.children!.map(normalizeComposerTextScaling).toList();
  if (children.indexed.every(
    (entry) => identical(entry.$2, span.children![entry.$1]),
  )) {
    return span;
  }
  return TextSpan(
    text: span.text,
    children: children,
    style: span.style,
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    semanticsIdentifier: span.semanticsIdentifier,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

/// A normalized widget span retaining its content for composer decorations.
final class ComposerWidgetSpan extends WidgetSpan {
  ComposerWidgetSpan(WidgetSpan span)
    : content = span.child,
      super(
        alignment: span.alignment,
        baseline: span.baseline,
        style: span.style,
        child: MediaQuery.withNoTextScaling(child: span.child),
      );

  final Widget content;
}
