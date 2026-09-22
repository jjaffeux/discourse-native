import 'dart:ui';

import 'composer_blocks.dart';

typedef ComposerEmptyLine = ({TextRange range, Rect rect});
typedef ComposerDropTarget = ({int gap, int? offset, double y});

/// Shared hit testing and insertion-line geometry for blocks and media.
class ComposerDropGeometry {
  const ComposerDropGeometry(this.index, this.blockRect, {this.emptyLineAt});

  final ComposerBlockIndex index;
  final Rect? Function(ComposerBodyBlock block) blockRect;
  final ComposerEmptyLine? Function(Offset position)? emptyLineAt;

  List<ComposerBodyBlock> get blocks => index.blocks;

  ComposerDropTarget? targetAt(
    Offset position, {
    ComposerDropTarget? previousTarget,
  }) {
    final target = _targetAt(position);
    if (target == null ||
        previousTarget == null ||
        _sameDestination(target, previousTarget)) {
      return target;
    }

    // Cross a midpoint deliberately before changing destinations. Scale the
    // tolerance down for nearby empty lines so each one remains reachable.
    final tolerance = ((target.y - previousTarget.y).abs() / 5).clamp(0.0, 6.0);
    final forward =
        (target.offset ?? offsetAt(target.gap)) >
        (previousTarget.offset ?? offsetAt(previousTarget.gap));
    final retained = _targetAt(
      position.translate(0, forward ? -tolerance : tolerance),
    );
    return retained != null && _sameDestination(retained, previousTarget)
        ? retained
        : target;
  }

  bool _sameDestination(ComposerDropTarget a, ComposerDropTarget b) =>
      a.gap == b.gap && a.offset == b.offset;

  ComposerDropTarget? _targetAt(Offset position) {
    final line = emptyLineAt?.call(position);
    if (line != null) {
      final following = blocks.indexWhere(
        (block) => block.start >= line.range.end,
      );
      final gap = following < 0 ? blocks.length : following;
      final start = gap == 0 ? 0 : blocks[gap - 1].end;
      final end = gap == blocks.length
          ? index.source.length
          : blocks[gap].start;
      // A single paragraph separator keeps its centered block boundary.
      // Longer runs and outer whitespace expose individual empty lines.
      if (gap == 0 ||
          gap == blocks.length ||
          '\n'.allMatches(index.source.substring(start, end)).length > 2) {
        final newline = index.source.indexOf('\n', line.range.end);
        final after = position.dy >= line.rect.center.dy && newline >= 0;
        return (
          gap: gap,
          offset: after ? newline + 1 : line.range.start,
          y: after ? line.rect.bottom : line.rect.top,
        );
      }
    }
    final gap = gapAt(position);
    final y = gap == null ? null : gapY(gap);
    return gap == null || y == null ? null : (gap: gap, offset: null, y: y);
  }

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
