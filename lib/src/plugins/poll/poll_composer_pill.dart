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
/// Every ordinary source code unit is retained as zero-size text. CR/LF code
/// units become zero-size one-character widgets so they no longer create
/// hidden blank lines. The final code unit becomes the visible pill. Flutter
/// therefore lays out exactly [PollComposerBlock.length] code units, just like
/// the underlying raw text used for copying, undo, drafts, and submission.
List<InlineSpan> buildCollapsedPollSpans({
  required PollComposerBlock block,
  required TextStyle baseStyle,
  Key? pillKey,
  int maximumOptions = 20,
}) {
  final source = block.source;
  if (source.isEmpty) return const [];

  final spans = <InlineSpan>[];
  final visibleAt = source.length - 1;
  var textStart = 0;
  for (var offset = 0; offset < visibleAt; offset++) {
    final codeUnit = source.codeUnitAt(offset);
    if (codeUnit != 0x0A && codeUnit != 0x0D) continue;
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
  if (textStart < visibleAt) {
    spans.add(
      TextSpan(
        text: source.substring(textStart, visibleAt),
        style: _pollHiddenSource,
      ),
    );
  }
  spans.add(
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      style: baseStyle,
      child: PollComposerPill(
        key: pillKey,
        block: block,
        label: pollComposerSummary(block, maximumOptions: maximumOptions),
        baseStyle: baseStyle,
      ),
    ),
  );

  assert(
    TextSpan(
          children: spans,
        ).toPlainText(includeSemanticsLabels: false).length ==
        source.length,
    'the poll projection drifted from its source range',
  );
  return spans;
}

class PollComposerPill extends StatelessWidget {
  const PollComposerPill({
    super.key,
    this.block,
    required this.label,
    required this.baseStyle,
  });

  final PollComposerBlock? block;
  final String label;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    void reportHover(bool hovering) {
      final block = this.block;
      if (block == null) return;
      PollComposerPillHoverNotification(
        block: block,
        hovering: hovering,
      ).dispatch(context);
    }

    return MouseRegion(
      onEnter: (_) => reportHover(true),
      onExit: (_) => reportHover(false),
      child: Semantics(
        label: '$label. Activate to show its markdown.',
        button: true,
        child: Pill(
          label: label,
          baseStyle: baseStyle,
          leading: DIcon(
            DIcons.squarePollHorizontal,
            size: Pill.iconBoxFor(baseStyle),
          ),
        ),
      ),
    );
  }
}

/// A hover reported by the inline pill itself.
///
/// Modern [EditableText] renderers hit-test [WidgetSpan] children. Dispatching
/// from the child gives the composer an exact signal and avoids depending on
/// a second, editor-wide coordinate lookup for the primary hover path.
class PollComposerPillHoverNotification extends Notification {
  const PollComposerPillHoverNotification({
    required this.block,
    required this.hovering,
  });

  final PollComposerBlock block;
  final bool hovering;
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
  bool explicitlyRaw = false,
  bool suppressCollapsedCaret = false,
}) {
  if (explicitlyRaw) return true;
  final composing = value.isComposingRangeValid
      ? value.composing
      : TextRange.empty;
  if (_rangesOverlap(block.start, block.end, composing.start, composing.end)) {
    return true;
  }

  final selection = value.selection;
  if (!selection.isValid) return false;
  if (selection.isCollapsed) {
    return !suppressCollapsedCaret &&
        block.containsOffset(selection.extentOffset);
  }
  return _rangesOverlap(block.start, block.end, selection.start, selection.end);
}

bool _rangesOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;

/// Tracks the explicit “Edit as raw” escape until the caret leaves that poll.
class PollRawExpansion {
  PollComposerBlock? _block;

  void expand(PollComposerBlock block) => _block = block;

  bool contains(PollComposerBlock block) =>
      _block?.start == block.start &&
      _block?.end == block.end &&
      _block?.source == block.source;

  void updateSelection(TextSelection selection) {
    final block = _block;
    if (block == null ||
        !selection.isValid ||
        !block.containsOffset(selection.extentOffset)) {
      _block = null;
    }
  }

  void clear() => _block = null;
}
