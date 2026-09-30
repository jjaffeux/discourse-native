import 'dart:ui';

import 'package:discourse_native/src/shell/composer_blocks.dart';
import 'package:discourse_native/src/shell/composer_drop_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
