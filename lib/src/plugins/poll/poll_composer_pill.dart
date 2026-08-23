import 'package:flutter/material.dart';

import '../../shell/pill.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'poll_composer_parser.dart';

const TextStyle _pollHiddenSource = TextStyle(
  color: Colors.transparent,
  fontSize: 0,
  height: 0,
  letterSpacing: 0,
  wordSpacing: 0,
);

/// A concise projection of a poll block for the markdown composer.
String pollComposerSummary(PollComposerBlock block, {int maximumOptions = 20}) {
  final title = block.titleSource?.trim();
  final optionCount = switch (block.type) {
    ComposerPollType.number => _generatedOptionCount(
      minimum: int.tryParse(block.attribute('min') ?? '') ?? 1,
      maximum: int.tryParse(block.attribute('max') ?? '') ?? maximumOptions,
      step: int.tryParse(block.attribute('step') ?? '') ?? 1,
      cap: maximumOptions,
    ),
    _ => block.optionSources.length,
  };
  final noun = optionCount == 1 ? 'option' : 'options';
  return 'Poll · ${title == null || title.isEmpty ? 'Untitled' : title} · '
      '$optionCount $noun';
}

int _generatedOptionCount({
  required int minimum,
  required int maximum,
  required int step,
  required int cap,
}) {
  if (minimum < 0 || maximum < minimum || step < 1) return 0;
  final count = ((maximum - minimum) ~/ step) + 1;
  return count.clamp(0, cap + 1);
}

/// Builds the collapsed poll projection without changing a single source
/// offset.
///
/// The first code unit becomes the visible pill. Every remaining ordinary
/// source code unit is retained as zero-size text, while CR/LF code units
/// become zero-size one-character widgets so they no longer create hidden
/// blank lines. When the owning document has no real line ending after the
/// block, the second code unit is projected as one transparent line ending.
/// The pill therefore remains block-shaped at EOF without changing the raw
/// Markdown used for copying, undo, drafts, and submission.
///
/// The spaces and tabs a closing `[/poll]` line carries are projected as
/// widgets too, for a reason that has nothing to do with blank lines. The
/// block keeps that whitespace byte for byte because the editor writes it
/// back, and `TextPainter` anchors an end-of-text caret to the paragraph's
/// last glyph whenever the paragraph ends in a space separator — asserting
/// that the glyph has bounds, which a `fontSize: 0` space has not. Typing a
/// space after a poll is the ordinary way to reach that.
List<InlineSpan> buildCollapsedPollSpans({
  required PollComposerBlock block,
  required TextStyle baseStyle,
  Key? pillKey,
  int maximumOptions = 20,
  bool highlighted = false,
  bool hovered = false,
  bool followedByLineBreak = false,
}) {
  final source = block.source;
  if (source.isEmpty) return const [];

  final projectsLineBreak = !followedByLineBreak && source.length > 1;
  final spans = <InlineSpan>[
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      style: baseStyle,
      child: PollComposerPill(
        key: pillKey,
        label: pollComposerSummary(block, maximumOptions: maximumOptions),
        baseStyle: baseStyle,
        highlighted: highlighted,
        hovered: hovered,
      ),
    ),
    if (projectsLineBreak)
      TextSpan(
        text: '\n',
        style: baseStyle.copyWith(color: Colors.transparent),
      ),
  ];
  final hiddenFrom = projectsLineBreak ? 2 : 1;
  // Where the trailing whitespace of the closing line begins.
  var trailingFrom = source.length;
  while (trailingFrom > hiddenFrom &&
      _isHorizontalSpace(source.codeUnitAt(trailingFrom - 1))) {
    trailingFrom--;
  }
  var textStart = hiddenFrom;
  for (var offset = hiddenFrom; offset < source.length; offset++) {
    final codeUnit = source.codeUnitAt(offset);
    final projectsWidget =
        codeUnit == 0x0A || codeUnit == 0x0D || offset >= trailingFrom;
    if (!projectsWidget) continue;
    if (textStart < offset) {
      spans.add(
        TextSpan(
          text: source.substring(textStart, offset),
          style: _pollHiddenSource,
        ),
      );
    }
    spans.add(
      const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox.shrink(),
      ),
    );
    textStart = offset + 1;
  }
  if (textStart < source.length) {
    spans.add(
      TextSpan(text: source.substring(textStart), style: _pollHiddenSource),
    );
  }

  assert(
    TextSpan(
          children: spans,
        ).toPlainText(includeSemanticsLabels: false).length ==
        source.length,
    'the poll projection drifted from its source range',
  );
  return spans;
}

bool _isHorizontalSpace(int codeUnit) => codeUnit == 0x20 || codeUnit == 0x09;

class PollComposerPill extends StatelessWidget {
  const PollComposerPill({
    super.key,
    required this.label,
    required this.baseStyle,
    this.highlighted = false,
    this.hovered = false,
  });

  final String label;
  final TextStyle baseStyle;
  final bool highlighted;
  final bool hovered;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label. Activate to edit.',
    button: true,
    selected: highlighted,
    child: Pill(
      label: label,
      baseStyle: baseStyle,
      hoverable: true,
      hovered: hovered,
      highlighted: highlighted,
      leading: DIcon(
        DIcons.squarePollHorizontal,
        size: Pill.iconBoxFor(baseStyle),
      ),
    ),
  );
}

/// Maps an actual source offset back to a poll range.
///
/// A poll's trailing boundary belongs to the content after it. Pointer hit
/// testing uses the visible pill rectangle instead, because Flutter can place
/// the caret at that boundary for points on either side of a placeholder.
PollComposerBlock? pollBlockAtComposerOffset(
  Iterable<PollComposerBlock> blocks,
  int offset,
) {
  for (final block in blocks) {
    if (block.containsOffset(offset)) return block;
  }
  return null;
}

/// Whether a block must be raw so a selection or IME composition remains
/// truthful. A pointer-triggered sheet can suppress only the collapsed caret;
/// composing and non-collapsed selections always reveal source.
bool pollBlockNeedsRawSource({
  required PollComposerBlock block,
  required TextEditingValue value,
  bool suppressCollapsedCaret = false,
}) {
  final composing = value.isComposingRangeValid
      ? value.composing
      : TextRange.empty;
  if (_rangesOverlap(block.start, block.end, composing.start, composing.end)) {
    return true;
  }

  final selection = value.selection;
  if (!selection.isValid) return false;
  if (selection.isCollapsed) {
    if (selection.extentOffset == block.start ||
        selection.extentOffset == block.end) {
      return false;
    }
    return !suppressCollapsedCaret &&
        block.containsOffset(selection.extentOffset);
  }
  return _rangesOverlap(block.start, block.end, selection.start, selection.end);
}

bool _rangesOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;
