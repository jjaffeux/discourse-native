import 'package:discourse_native/discourse_plugin_composer.dart';
import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'poll_composer_parser.dart';

const pollComposerSyntaxId = 'poll/poll';

abstract interface class PollComposerProjectionData {
  PollComposerBlock get pollBlock;
}

extension PollComposerEditing on MarkdownEditingController {
  List<PollComposerBlock> get pollBlocks => [
    for (final occurrence in syntaxBlocks) ?_pollBlock(occurrence),
  ];

  ComposerSyntaxOccurrence? _pollOccurrence(PollComposerBlock block) {
    for (final occurrence in syntaxBlocks) {
      final projected = _pollBlock(occurrence);
      if (projected != null &&
          (identical(projected, block) ||
              occurrence.start == block.start &&
                  occurrence.end == block.end &&
                  occurrence.source == block.source)) {
        return occurrence;
      }
    }
    return null;
  }

  PollComposerBlock? collapsedPollAtOffset(int offset) {
    final occurrence = collapsedSyntaxAtOffset(offset);
    return occurrence == null ? null : _pollBlock(occurrence);
  }

  bool isPollCollapsed(PollComposerBlock block) {
    final occurrence = _pollOccurrence(block);
    return occurrence != null && isSyntaxCollapsed(occurrence);
  }

  void keepPollCollapsedForPointerEdit(PollComposerBlock block) {
    final occurrence = _pollOccurrence(block);
    if (occurrence != null) keepSyntaxCollapsedForPointerEdit(occurrence);
  }

  void releasePollPointerEdit(PollComposerBlock block) {
    final occurrence = _pollOccurrence(block);
    if (occurrence != null) releaseSyntaxPointerEdit(occurrence);
  }

  PollComposerBlock? get keyboardSelectedPoll {
    final occurrence = keyboardSelectedSyntax;
    return occurrence == null ? null : _pollBlock(occurrence);
  }
}

PollComposerBlock? _pollBlock(ComposerSyntaxOccurrence occurrence) {
  if (occurrence.kind.id != pollComposerSyntaxId) return null;
  return switch (occurrence.projection) {
    final PollComposerProjectionData projection => projection.pollBlock,
    _ => null,
  };
}
