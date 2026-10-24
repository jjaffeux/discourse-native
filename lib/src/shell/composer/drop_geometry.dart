import 'dart:ui';

import 'blocks.dart';

typedef ComposerEmptyLine = ({TextRange range, Rect rect});
typedef ComposerDropTarget = ({int gap, int? offset, double y});

/// Shared hit testing and insertion-line geometry for blocks and media.
class ComposerDropGeometry {
  const ComposerDropGeometry(this.index, this.blockRect, {this.emptyLineAt});

  final ComposerBlockIndex index;

  /// Rendered bounds with top edges, centers and bottom edges in document order.
  /// Returns null when a block's layout is unavailable.
  final Rect? Function(ComposerBodyBlock block) blockRect;
  final ComposerEmptyLine? Function(Offset position)? emptyLineAt;

  List<ComposerBodyBlock> get blocks => index.blocks;

  ComposerDropTarget? targetAt(
    Offset position, {
    ComposerDropTarget? previousTarget,
    bool touch = false,
  }) {
    final rects = <ComposerBodyBlock, Rect?>{};
    final query = ComposerDropGeometry(
      index,
      (block) => rects.putIfAbsent(block, () => blockRect(block)),
      emptyLineAt: emptyLineAt,
    );
    return query._targetWithHysteresis(
      position,
      previousTarget: previousTarget,
      touch: touch,
    );
  }

  ComposerDropTarget? _targetWithHysteresis(
    Offset position, {
    ComposerDropTarget? previousTarget,
    required bool touch,
  }) {
    final target = _targetAt(position);
    if (target == null ||
        previousTarget == null ||
        _sameDestination(target, previousTarget)) {
      return target;
    }

    // Touch needs a wider dead band than a mouse: crossing a midpoint by a
    // few pixels should not send the indicator to the other side of a block.
    // Keep it smaller than half the distance between destinations so every
    // empty line remains reachable without a delay or a velocity threshold.
    // Refresh block boundaries first; scrolling must not shrink the dead band
    // just because the previous target still has its old screen coordinate.
    final previousY = previousTarget.offset == null
        ? gapY(previousTarget.gap) ?? previousTarget.y
        : previousTarget.y;
    final lineHeight = target.offset == null
        ? null
        : emptyLineAt?.call(position)?.rect.height;
    // A large gap around a short block must not make its outer edge
    // unreachable, especially at the beginning or end of a mobile editor.
    final crossedBlock =
        touch &&
            target.offset == null &&
            previousTarget.offset == null &&
            (target.gap - previousTarget.gap).abs() == 1
        ? blockRect(
            blocks[target.gap > previousTarget.gap
                ? previousTarget.gap
                : target.gap],
          )
        : null;
    final distance = (lineHeight ?? (target.y - previousY).abs()).clamp(
      0.0,
      crossedBlock?.height ?? double.infinity,
    );
    final tolerance = (distance * (touch ? .4 : .2)).clamp(
      0.0,
      touch ? 14.0 : 6.0,
    );
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
      var gap = 0;
      var endBlock = blocks.length;
      while (gap < endBlock) {
        final middle = (gap + endBlock) ~/ 2;
        if (blocks[middle].start < line.range.end) {
          gap = middle + 1;
        } else {
          endBlock = middle;
        }
      }
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

  /// Finds the first block containing [y], including both vertical edges.
  ComposerBodyBlock? blockAt(double y) {
    Rect? candidate;
    var start = 0;
    var end = blocks.length;
    while (start < end) {
      final middle = (start + end) ~/ 2;
      final rect = blockRect(blocks[middle]);
      if (rect == null) {
        for (final block in blocks) {
          final visible = blockRect(block);
          if (visible != null && y >= visible.top && y <= visible.bottom) {
            return block;
          }
        }
        return null;
      }
      if (rect.bottom < y) {
        start = middle + 1;
      } else {
        candidate = rect;
        end = middle;
      }
    }
    return candidate != null && y >= candidate.top ? blocks[start] : null;
  }

  int? gapAt(Offset position) {
    if (blocks.isEmpty) return null;
    var start = 0;
    var end = blocks.length;
    while (start < end) {
      final middle = (start + end) ~/ 2;
      final rect = blockRect(blocks[middle]);
      if (rect == null) return _visibleGapAt(position);
      if (position.dy < rect.center.dy) {
        end = middle;
      } else {
        start = middle + 1;
      }
    }
    return start;
  }

  int? _visibleGapAt(Offset position) {
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
