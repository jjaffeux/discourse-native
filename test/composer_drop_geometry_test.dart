import 'dart:ui';

import 'package:discourse_native/src/shell/composer/blocks.dart';
import 'package:discourse_native/src/shell/composer/drop_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('block hits include both edges and retain the first shared edge', () {
    final index = ComposerBlockIndex.parse('First\n\nSecond');
    final rects = {
      index.blocks[0]: const Rect.fromLTWH(10, 20, 200, 40),
      index.blocks[1]: const Rect.fromLTWH(10, 60, 200, 80),
    };
    final geometry = ComposerDropGeometry(index, (block) => rects[block]);
    expect(geometry.blockAt(19), isNull);
    expect(geometry.blockAt(20), index.blocks[0]);
    expect(geometry.blockAt(60), index.blocks[0]);
    expect(geometry.blockAt(61), index.blocks[1]);
    expect(geometry.blockAt(140), index.blocks[1]);
    expect(geometry.blockAt(141), isNull);
    expect(geometry.gapAt(const Offset(-100, 40)), 1);
    expect(geometry.gapAt(const Offset(500, 100)), 2);
  });

  test('empty geometry has no hit, gap or target', () {
    final geometry = ComposerDropGeometry(ComposerBlockIndex.parse(''), (_) {
      fail('Empty geometry must not request a block rectangle');
    });
    expect(geometry.blockAt(0), isNull);
    expect(geometry.gapAt(Offset.zero), isNull);
    expect(geometry.targetAt(Offset.zero), isNull);
    expect(geometry.gapY(0), isNull);
  });

  test('overlapping fractional bounds preserve equal-center ordering', () {
    final index = ComposerBlockIndex.parse('First\n\nSecond\n\nThird');
    final rects = {
      index.blocks[0]: const Rect.fromLTWH(0, 0.25, 200, 20.5),
      index.blocks[1]: const Rect.fromLTWH(0, 0.25, 200, 20.5),
      index.blocks[2]: const Rect.fromLTWH(0, 20.5, 200, 20.5),
    };
    final geometry = ComposerDropGeometry(index, (block) => rects[block]);
    expect(geometry.blockAt(20.625), index.blocks[0]);
    expect(geometry.blockAt(20.875), index.blocks[2]);
    expect(geometry.gapAt(const Offset(100, 10.49)), 0);
    expect(geometry.gapAt(const Offset(100, 10.5)), 2);
  });

  test('missing rectangles are also reused during one target query', () {
    final index = ComposerBlockIndex.parse(
      List.generate(8, (i) => 'Paragraph $i').join('\n\n'),
    );
    final positions = {for (final (i, block) in index.blocks.indexed) block: i};
    final queries = <ComposerBodyBlock, int>{};
    final geometry = ComposerDropGeometry(index, (block) {
      queries.update(block, (count) => count + 1, ifAbsent: () => 1);
      final position = positions[block]!;
      return position == 3 || position == 4
          ? null
          : Rect.fromLTWH(0, position * 100, 200, 80);
    });
    expect(
      geometry
          .targetAt(
            const Offset(100, 350),
            previousTarget: (gap: 2, offset: null, y: 190),
            touch: true,
          )
          ?.gap,
      5,
    );
    expect(queries[index.blocks[3]], 1);
    expect(queries[index.blocks[4]], 1);
    expect(queries.values, everyElement(1));
  });

  test('missing rectangles preserve visible block and gap lookup', () {
    final index = ComposerBlockIndex.parse(
      List.generate(8, (i) => 'Paragraph $i').join('\n\n'),
    );
    for (final missing in [
      <int>{},
      {0, 1},
      {3, 4},
      {6, 7},
      {0, 2, 4, 7},
      {0, 1, 2, 3, 4, 5, 6, 7},
    ]) {
      final rects = {
        for (final (i, block) in index.blocks.indexed)
          block: missing.contains(i)
              ? null
              : Rect.fromLTWH(0, i * 100, 200, 80),
      };
      final geometry = ComposerDropGeometry(index, (block) => rects[block]);
      for (var y = -20.0; y <= 820; y += 10) {
        ComposerBodyBlock? expectedBlock;
        for (final block in index.blocks) {
          final rect = rects[block];
          if (rect == null) continue;
          if (expectedBlock == null && y >= rect.top && y <= rect.bottom) {
            expectedBlock = block;
          }
        }
        final expectedGap = () {
          int? afterLastVisible;
          for (final (i, block) in index.blocks.indexed) {
            final rect = rects[block];
            if (rect == null) continue;
            if (y < rect.center.dy) return i;
            afterLastVisible = i + 1;
          }
          return afterLastVisible;
        }();
        expect(geometry.blockAt(y), expectedBlock, reason: '$missing at $y');
        expect(
          geometry.gapAt(Offset(100, y)),
          expectedGap,
          reason: '$missing at $y',
        );
      }
    }
  });

  test('long draft target reuses each rectangle within one pointer query', () {
    final index = ComposerBlockIndex.parse(
      List.generate(128, (i) => 'Paragraph $i').join('\n\n'),
    );
    final positions = {for (final (i, block) in index.blocks.indexed) block: i};
    final queries = <ComposerBodyBlock, int>{};
    final geometry = ComposerDropGeometry(index, (block) {
      queries.update(block, (count) => count + 1, ifAbsent: () => 1);
      return Rect.fromLTWH(0, positions[block]! * 100, 200, 80);
    });
    var target = geometry.targetAt(const Offset(100, 12500), touch: true)!;
    expect(target.gap, 125);
    queries.clear();
    target = geometry.targetAt(
      const Offset(100, 12545),
      previousTarget: target,
      touch: true,
    )!;
    expect(target.gap, 125);
    expect(queries.values, everyElement(1));
    expect(queries.length, lessThanOrEqualTo(12));
    queries.clear();
    expect(geometry.blockAt(12545), index.blocks[125]);
    expect(queries.length, lessThanOrEqualTo(8));
  });

  test('target refreshes dimensions and translation on the same geometry', () {
    final index = ComposerBlockIndex.parse('First\n\nSecond');
    var height = 80.0;
    var translation = 0.0;
    final positions = {for (final (i, block) in index.blocks.indexed) block: i};
    final geometry = ComposerDropGeometry(
      index,
      (block) =>
          Rect.fromLTWH(0, positions[block]! * 160 + translation, 200, height),
    );
    expect(geometry.targetAt(const Offset(100, 45)), (
      gap: 1,
      offset: null,
      y: 120.0,
    ));
    height = 120;
    expect(geometry.targetAt(const Offset(100, 45)), (
      gap: 0,
      offset: null,
      y: 0.0,
    ));
    translation = -200;
    expect(geometry.targetAt(const Offset(100, 45)), (
      gap: 2,
      offset: null,
      y: 80.0,
    ));
  });

  test('touch retains a boundary through jitter in both directions', () {
    final index = ComposerBlockIndex.parse('First\n\nSecond\n\nThird');
    final rects = [
      const Rect.fromLTWH(0, 0, 200, 40),
      const Rect.fromLTWH(0, 80, 200, 100),
      const Rect.fromLTWH(0, 220, 200, 40),
    ];
    final geometry = ComposerDropGeometry(
      index,
      (block) => rects[index.blocks.indexOf(block)],
    );
    var target = geometry.targetAt(const Offset(100, 100), touch: true)!;
    expect(target.gap, 1);
    for (final y in [125.0, 140.0, 122.0, 138.0]) {
      target = geometry.targetAt(
        Offset(100, y),
        previousTarget: target,
        touch: true,
      )!;
      expect(target.gap, 1);
    }
    target = geometry.targetAt(
      const Offset(100, 145),
      previousTarget: target,
      touch: true,
    )!;
    expect(target.gap, 2);
    for (final y in [135.0, 120.0, 138.0, 122.0]) {
      target = geometry.targetAt(
        Offset(100, y),
        previousTarget: target,
        touch: true,
      )!;
      expect(target.gap, 2);
    }
    expect(
      geometry
          .targetAt(const Offset(100, 115), previousTarget: target, touch: true)
          ?.gap,
      1,
    );
    expect(
      geometry
          .targetAt(const Offset(100, 280), previousTarget: target, touch: true)
          ?.gap,
      3,
    );
    // A fresh drag has no retained destination.
    expect(geometry.targetAt(const Offset(100, 132), touch: true)?.gap, 2);
  });

  test('scrolling refreshes the retained block boundary and its tolerance', () {
    final index = ComposerBlockIndex.parse('First\n\nSecond\n\nThird');
    var scroll = 0.0;
    final geometry = ComposerDropGeometry(
      index,
      (block) =>
          Rect.fromLTWH(0, index.blocks.indexOf(block) * 100 - scroll, 200, 80),
    );
    final target = geometry.targetAt(const Offset(100, 100), touch: true)!;
    scroll = 100;
    final retained = geometry.targetAt(
      const Offset(100, 48),
      previousTarget: target,
      touch: true,
    )!;
    expect(retained.gap, target.gap);
    expect(retained.y, target.y - scroll);
    expect(
      geometry
          .targetAt(
            const Offset(100, 60),
            previousTarget: retained,
            touch: true,
          )
          ?.gap,
      2,
    );
  });

  test('short outer blocks remain reachable beside a large gap', () {
    final index = ComposerBlockIndex.parse('First\n\nSecond');
    final geometry = ComposerDropGeometry(
      index,
      (block) => Rect.fromLTWH(0, index.blocks.indexOf(block) * 100, 200, 20),
    );
    final middle = geometry.targetAt(const Offset(100, 60), touch: true)!;
    expect(middle.gap, 1);
    expect(
      geometry
          .targetAt(const Offset(100, 1), previousTarget: middle, touch: true)
          ?.gap,
      0,
    );
    expect(
      geometry
          .targetAt(const Offset(100, 119), previousTarget: middle, touch: true)
          ?.gap,
      2,
    );
  });

  test('nearby blank lines stay reachable and stable after scrolling', () {
    final index = ComposerBlockIndex.parse('\n\n\nMove');
    var scroll = 0.0;
    final geometry = ComposerDropGeometry(
      index,
      (_) => Rect.fromLTWH(0, 60 - scroll, 200, 20),
      emptyLineAt: (position) {
        final line = ((position.dy + scroll) / 20).floor();
        return line < 0 || line > 2
            ? null
            : (
                range: TextRange.collapsed(line),
                rect: Rect.fromLTWH(0, line * 20 - scroll, 200, 20),
              );
      },
    );
    var target = geometry.targetAt(const Offset(100, 22), touch: true)!;
    expect(target.offset, 1);
    scroll = 20;
    for (final y in [14.0, 6.0, 16.0, 4.0]) {
      target = geometry.targetAt(
        Offset(100, y),
        previousTarget: target,
        touch: true,
      )!;
      expect(target.offset, 1);
      expect(target.y, 0);
    }
    target = geometry.targetAt(
      const Offset(100, 19),
      previousTarget: target,
      touch: true,
    )!;
    expect(target.offset, 2);
    expect(target.y, 20);
    for (final y in [14.0, 6.0, 16.0, 4.0]) {
      target = geometry.targetAt(
        Offset(100, y),
        previousTarget: target,
        touch: true,
      )!;
      expect(target.offset, 2);
    }
    expect(
      geometry
          .targetAt(const Offset(100, 1), previousTarget: target, touch: true)
          ?.offset,
      1,
    );
  });
}
