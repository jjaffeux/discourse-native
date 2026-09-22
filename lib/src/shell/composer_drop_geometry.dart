import 'dart:ui';

import 'composer_blocks.dart';

/// Shared hit testing and insertion-line geometry for blocks and media.
class ComposerDropGeometry {
  const ComposerDropGeometry(this.blocks, this.blockRect);

  final List<ComposerBodyBlock> blocks;
  final Rect? Function(ComposerBodyBlock block) blockRect;

  int? gapAt(Offset position) {
    int? afterLastVisible;
    for (var i = 0; i < blocks.length; i++) {
      final rect = blockRect(blocks[i]);
      if (rect == null) continue;
      if (position.dy < rect.center.dy) return i;
      afterLastVisible = i + 1;
    }
    return afterLastVisible;
  }

  double? gapY(int gap) {
    if (blocks.isEmpty || gap < 0 || gap > blocks.length) return null;
    final before = gap > 0 ? blockRect(blocks[gap - 1]) : null;
    final after = gap < blocks.length ? blockRect(blocks[gap]) : null;
    return before != null && after != null
        ? (before.bottom + after.top) / 2
        : after?.top ?? before?.bottom;
  }

  int offsetAt(int gap) => gap == 0 ? 0 : blocks[gap - 1].end;
}
