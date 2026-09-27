import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/src/shell/composer_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

void main() {
  ComposerBlockIndex parse(String raw) => ComposerBlockIndex.parse(raw);

  test('indexes semantic paragraphs, headings and soft line breaks', () {
    final index = parse(
      'First\nsoft break\n\n# Heading\nNext paragraph\n\nLast',
    );
    expect(index.blocks.map((b) => b.source), [
      'First\nsoft break',
      '# Heading',
      'Next paragraph',
      'Last',
    ]);
    expect(index.blocks[1].kind, ComposerBlockKind.heading);
  });

  test('setext headings include their underline', () {
    final index = parse('Heading\n=======\n\nParagraph\n\n---');
    expect(index.blocks.map((b) => b.kind), [
      ComposerBlockKind.heading,
      ComposerBlockKind.paragraph,
      ComposerBlockKind.divider,
    ]);
    expect(index.blocks.first.source, 'Heading\n=======');
  });

  test('code fences retain blank lines and apparent block markers', () {
    final index = parse(
      'Before\n\n````md\n# not a heading\n\n```\n- item\n````\n\nAfter',
    );
    expect(index.blocks, hasLength(3));
    expect(index.blocks[1].kind, ComposerBlockKind.code);
    expect(
      index.blocks[1].source,
      '````md\n# not a heading\n\n```\n- item\n````',
    );
    expect(index.blocks[1].movable, isTrue);
  });

  test('unclosed fences cannot swallow content through a move', () {
    final index = parse('Before\n\n```\nunfinished');
    expect(index.blocks.last.movable, isFalse);
    expect(index.move(index.blocks.first.id, 2), isNull);
    expect(index.move(index.blocks.last.id, 0), isNull);
  });

  test('whole lists contain nested items and continuation paragraphs', () {
    const list = '- First\n  - Nested\n\n  Continuation\n\n- Second';
    final index = parse('Before\n\n$list\n\nAfter');
    expect(index.blocks, hasLength(3));
    expect(index.blocks[1].kind, ComposerBlockKind.list);
    expect(index.blocks[1].source, list);
    expect(index.move(index.blocks[1].id, 0)?.after.blocks.first.source, list);
  });

  test('quote lazy continuation stays in the quote', () {
    final index = parse('> Quote\nlazy continuation\n> More\n\nAfter');
    expect(index.blocks, hasLength(2));
    expect(index.blocks.first.kind, ComposerBlockKind.quote);
    expect(index.blocks.first.source, '> Quote\nlazy continuation\n> More');
  });

  test('each standalone to-do is a block, including an empty final item', () {
    final index = parse('Before\n[ ] First\n[x] Second\n[] \nAfter');
    expect(index.blocks.map((block) => block.source), [
      'Before',
      '[ ] First',
      '[x] Second',
      '[] ',
      'After',
    ]);
    expect(index.blocks.map((block) => block.kind), [
      ComposerBlockKind.paragraph,
      ComposerBlockKind.todo,
      ComposerBlockKind.todo,
      ComposerBlockKind.todo,
      ComposerBlockKind.paragraph,
    ]);
    expect(index.blocks.every((block) => block.movable), isTrue);
    expect(index.blocks[1].label, 'To-do');
  });

  test(
    'nested checklists and literal markers keep their container boundaries',
    () {
      const nested = '- [ ] Parent\n  - [x] Child\n\n- Plain';
      expect(parse(nested).blocks.map((block) => block.source), [
        '- [ ] Parent\n  - [x] Child',
        '- Plain',
      ]);
      expect(parse(nested).blocks.first.kind, ComposerBlockKind.todo);
      for (final source in [
        '```\n[ ] Code\n[x] Code\n```',
        '\\[ ] Escaped\n\\[x] Escaped',
        '[x] Link\n\n[x]: https://example.com',
        '> [ ] Quoted\n> [x] Quoted',
      ]) {
        expect(
          parse(
            source,
          ).blocks.any((block) => block.kind == ComposerBlockKind.todo),
          isFalse,
        );
      }
    },
  );

  for (final newline in ['\n', '\r\n']) {
    test('to-do moves preserve single row separators (${newline.length})', () {
      final rows = ['[ ] First', '[x] Same', '[ ] Same', '[] '];
      final index = parse(rows.join(newline));
      final move = index.move(index.blocks[1].id, 4)!;
      expect(
        move.after.source,
        [rows[0], rows[2], rows[3], rows[1]].join(newline),
      );
      expect(move.after.blocks.map((block) => block.id), [
        index.blocks[0].id,
        index.blocks[2].id,
        index.blocks[3].id,
        index.blocks[1].id,
      ]);
      expect(
        move.mapOffset(index.blocks[1].start + 5),
        move.after.blocks.last.start + 5,
      );
    });
  }

  test(
    'inline BBCode spanning paragraphs remains one protected source block',
    () {
      const raw = 'Intro [spoiler]first\n\nsecond[/spoiler]';
      final index = parse('$raw\n\nAfter');
      expect(index.blocks, hasLength(2));
      expect(index.blocks.first.source, raw);
      expect(index.blocks.first.movable, isFalse);
      expect(index.move(index.blocks.first.id, 2), isNull);
    },
  );

  test('inline date tags do not split a soft-wrapped paragraph', () {
    final index = parse('Meet on\n[date=2026-09-21]\nfor lunch');
    expect(index.blocks, hasLength(1));
    expect(index.blocks.single.kind, ComposerBlockKind.paragraph);
  });

  test('unknown and nested BBCode is opaque instead of draggable fragments', () {
    final index = parse(
      'Before\n\n[custom]\nText\n\n[custom]\nNested\n[/custom]\n[/custom]\n\nAfter',
    );
    expect(index.blocks, hasLength(3));
    expect(index.blocks[1].kind, ComposerBlockKind.opaque);
    expect(index.blocks[1].movable, isFalse);
  });

  test('unclosed HTML and reference definitions are not move handles', () {
    expect(parse('<div>\n\nBody\n\nAfter').blocks.single.movable, isFalse);
    expect(
      parse('[example]: https://example.com').blocks.single.movable,
      isFalse,
    );
  });

  test('registered rich block content moves without rewriting its payload', () {
    const component = '[poll]\n* Tea\n* Coffee\n[/poll]';
    const source = 'Before\n\n$component\n\nAfter';
    final index = ComposerBlockIndex.parse(
      source,
      atoms: [const ComposerBlockAtom(8, 8 + component.length, label: 'Poll')],
    );
    expect(index.blocks[1].label, 'Poll');
    final move = index.move(index.blocks[1].id, 0)!;
    expect(move.after.source, '$component\n\nBefore\n\nAfter');
    expect(move.after.blocks.first.id, index.blocks[1].id);
    expect(move.after.blocks.first.label, 'Poll');
  });

  for (final newline in ['\n', '\r\n']) {
    for (final separation in [1, 2]) {
      for (final from in [0, 2]) {
        test(
          'moving component $from between components preserves $separation separators of ${newline.length} characters',
          () {
            const components = [
              '![First](upload://first)',
              '[details="Second"]\nBody\n[/details]',
              '[poll]\n* Third\n* Fourth\n[/poll]',
            ];
            final separator = newline * separation;
            final source = components.join(separator);
            final index = ComposerBlockIndex.parse(
              source,
              atoms: [
                for (final component in components)
                  ComposerBlockAtom(
                    source.indexOf(component),
                    source.indexOf(component) + component.length,
                  ),
              ],
            );
            final moved = index.move(index.blocks[from].id, from == 0 ? 2 : 1)!;
            final expected = from == 0 ? [1, 0, 2] : [0, 2, 1];
            expect(
              moved.after.source,
              expected.map((i) => components[i]).join(separator),
            );
            expect(
              moved.after.blocks.map((block) => block.id),
              expected.map((i) => index.blocks[i].id),
            );
          },
        );
      }
    }
  }

  test('moving retains exact CRLF, Unicode, and outer whitespace', () {
    const source = '\r\nFirst 😀  \r\n\r\n\r\nSecond אבג\r\n';
    final index = parse(source);
    final move = index.move(index.blocks.last.id, 0)!;
    expect(move.after.source, '\r\nSecond אבג\r\n\r\n\r\nFirst 😀  \r\n');
    expect(
      move.mapOffset(source.indexOf('אבג')),
      move.after.source.indexOf('אבג'),
    );
  });

  test(
    'changed boundaries cannot join paragraphs or turn dividers into headings',
    () {
      final index = parse('# Heading\nOne\n\n---\nTwo');
      final move = index.move(index.blocks.first.id, index.blocks.length)!;
      expect(move.after.blocks.map((b) => b.kind), [
        ComposerBlockKind.paragraph,
        ComposerBlockKind.divider,
        ComposerBlockKind.paragraph,
        ComposerBlockKind.heading,
      ]);
    },
  );

  test('moves that would merge two lists are rejected', () {
    final index = parse('- One\n\nSeparator\n\n- Two');
    expect(index.move(index.blocks[1].id, 3), isNull);
  });

  test('same-position and invalid moves do not generate mutations', () {
    final index = parse('One\n\nTwo');
    expect(index.move(index.blocks.first.id, 0), isNull);
    expect(index.move(index.blocks.first.id, 1), isNull);
    expect(index.move(index.blocks.first.id, -1), isNull);
    expect(index.move(index.blocks.first.id, 3), isNull);
    expect(index.move(999, 0), isNull);
  });

  for (final newline in ['\n', '\r\n']) {
    test(
      'moves within trailing empty lines without reordering blocks (${newline.length})',
      () {
        const block = 'Move 😀  ';
        final source = '$block${newline * 4}';
        final index = parse(source);
        final move = index.move(
          index.blocks.single.id,
          1,
          offset: block.length + newline.length * 3,
        )!;
        expect(move.after.source, '${newline * 2}$block${newline * 2}');
        expect(move.after.blocks.single.id, index.blocks.single.id);
        expect(move.mapOffset(5), newline.length * 2 + 5);
      },
    );

    test(
      'moves upward between leading whitespace-only lines (${newline.length})',
      () {
        final source = ' $newline\t$newline$newline## Move';
        final index = parse(source);
        final move = index.move(
          index.blocks.single.id,
          0,
          offset: 1 + newline.length,
        )!;
        expect(move.after.source, ' $newline## Move$newline\t$newline');
      },
    );

    for (final from in [0, 2]) {
      test(
        'inserts from block $from into an exact empty-line boundary (${newline.length})',
        () {
          final source = from == 0
              ? 'Move${newline * 2}Before${newline * 5}After'
              : 'Before${newline * 5}After${newline * 2}Move';
          final index = parse(source);
          final offset =
              source.indexOf('Before') + 'Before'.length + newline.length * 3;
          final move = index.move(
            index.blocks[from].id,
            from == 0 ? 2 : 1,
            offset: offset,
          )!;
          expect(
            move.after.source,
            from == 0
                ? '${newline}Before${newline * 3}Move${newline * 3}After'
                : 'Before${newline * 3}Move${newline * 3}After$newline',
          );
          for (final block in index.blocks) {
            expect(
              move.mapOffset(block.start + 1),
              move.after.byId(block.id)!.start + 1,
            );
          }
        },
      );
    }
  }

  test(
    'registered components retain their atoms at an empty-line destination',
    () {
      const component = '[poll]\n* Tea\n* Coffee\n[/poll]';
      const source = '$component\n\n\n\n';
      final index = ComposerBlockIndex.parse(
        source,
        atoms: [const ComposerBlockAtom(0, component.length, label: 'Poll')],
      );
      final move = index.move(
        index.blocks.single.id,
        1,
        offset: component.length + 3,
      )!;
      expect(move.after.source, '\n\n$component\n\n');
      expect(move.after.blocks.single.label, 'Poll');
      expect(move.after.atoms.single.start, 2);
      expect(move.after.atoms.single.end, component.length + 2);
    },
  );

  test(
    'empty-line moves retain Markdown separation and reject unsafe destinations',
    () {
      final index = parse('Move\n\nBefore\n\n\nAfter');
      final move = index.move(
        index.blocks.first.id,
        2,
        offset: index.blocks.last.start,
      )!;
      expect(move.after.blocks.map((block) => block.source), [
        'Before',
        'Move',
        'After',
      ]);
      expect(index.move(index.blocks.first.id, 2, offset: -1), isNull);
      expect(
        index.move(index.blocks.first.id, 2, offset: index.source.length + 1),
        isNull,
      );
      expect(
        index.move(index.blocks.first.id, 2, offset: index.blocks[1].start + 2),
        isNull,
      );
      expect(index.move(index.blocks.first.id, 0, offset: 0), isNull);

      final lists = parse('- One\n\nSeparator\n\n- Two\n\n\n');
      expect(
        lists.move(lists.blocks[1].id, 3, offset: lists.source.length - 1),
        isNull,
      );
      final fence = parse('Before\n\n```\n\nunfinished');
      expect(fence.move(fence.blocks.first.id, 1, offset: 12), isNull);
    },
  );

  test('duplicate paragraphs retain distinct identities during movement', () {
    final index = parse('Same\n\nDifferent\n\nSame');
    final ids = index.blocks.map((b) => b.id).toList();
    final move = index.move(ids[2], 0)!;
    expect(move.after.blocks.map((b) => b.id), [ids[2], ids[0], ids[1]]);
  });

  test('empty-line destinations retain single separators between to-dos', () {
    const source = '[ ] First\n\n\n[x] Second\n[ ] Move';
    final index = parse(source);
    final move = index.move(
      index.blocks.last.id,
      1,
      offset: source.indexOf('[x]'),
    )!;
    expect(move.after.source, '[ ] First\n\n\n[ ] Move\n[x] Second');
    expect(
      move.after.blocks.map((block) => block.kind),
      everyElement(ComposerBlockKind.todo),
    );
  });

  test('an ordinary edit retains the edited and shifted block identities', () {
    final before = parse('First\n\nSecond\n\nThird');
    final after = ComposerBlockIndex.parse(
      'First longer\n\nSecond\n\nThird',
      previous: before,
    );
    expect(after.blocks.map((b) => b.id), before.blocks.map((b) => b.id));
  });

  group('block IDs after an edit', () {
    List<int> ids(ComposerBlockIndex index) => [
      for (final block in index.blocks) block.id,
    ];
    ComposerBlockIndex edit(ComposerBlockIndex previous, String source) =>
        ComposerBlockIndex.parse(source, previous: previous);

    test('are fresh only for an inserted block', () {
      final before = parse('Alpha\n\nBeta\n\nGamma');
      expect(ids(edit(before, 'Alpha\n\nBeta\n\nNew\n\nGamma')), [0, 1, 3, 2]);
    });

    test('survive on both sides of a deleted block', () {
      final before = parse('Alpha\n\nBeta\n\nGamma');
      expect(ids(edit(before, 'Alpha\n\nGamma')), [0, 2]);
    });

    test('survive typing anywhere inside a block', () {
      final before = parse('Alpha\n\nBeta\n\nGamma');
      expect(ids(edit(before, 'Alpha\n\nxBeta\n\nGamma')), [0, 1, 2]);
      expect(ids(edit(before, 'Alpha\n\nBe-ta\n\nGamma')), [0, 1, 2]);
      expect(ids(edit(before, 'Alpha\n\nBeta and more\n\nGamma')), [0, 1, 2]);
    });

    test('are fresh for every pasted block, in document order', () {
      final before = parse('Alpha\n\nOmega');
      final pasted = [for (var i = 0; i < 5; i++) 'Pasted $i'].join('\n\n');
      final after = edit(before, 'Alpha\n\n$pasted\n\nOmega');
      expect(ids(after), [0, 2, 3, 4, 5, 6, 1]);
    });

    test('are fresh for both halves of a split block', () {
      final before = parse('Alpha\n\nBetaGamma\n\nDelta');
      final after = edit(before, 'Alpha\n\nBeta\n\nGamma\n\nDelta');
      expect(ids(after), [0, 3, 4, 2]);
    });

    test('are fresh for two blocks joined into one', () {
      final before = parse('Alpha\n\nBeta\n\nGamma\n\nDelta');
      expect(ids(edit(before, 'Alpha\n\nBetaGamma\n\nDelta')), [0, 4, 3]);
    });

    test('are fresh for a block whose kind changes', () {
      final before = parse('Alpha\n\nBeta\n\nGamma');
      final after = edit(before, 'Alpha\n\n# Beta\n\nGamma');
      expect(after.blocks[1].kind, ComposerBlockKind.heading);
      expect(ids(after), [0, 3, 2]);
    });

    test('follow duplicate blocks by position', () {
      final before = parse('Same\n\nSame');
      expect(ids(edit(before, 'New\n\nSame\n\nSame')), [2, 0, 1]);
      expect(ids(edit(before, 'Same\n\nSame\n\nSame')), [0, 1, 2]);
      expect(ids(edit(before, 'Same\n\nNew\n\nSame')), [0, 2, 1]);
    });

    test('keep an order a move gave them, above which fresh IDs start', () {
      final moved = parse('Alpha\n\nBeta\n\nGamma').move(2, 0)!.after;
      expect(ids(moved), [2, 0, 1]);
      expect(ids(edit(moved, 'Gamma\n\nAlpha\n\nNew\n\nBeta')), [2, 0, 3, 1]);
    });

    test('match a search of every previous block for generated edits', () {
      // Retention is positional: a block keeps an ID when it is unchanged but
      // shifted by the edit, or when it contains the whole edit and starts
      // where it did. The corpus mixes every block kind and duplicates, moves
      // put IDs out of document order, and it must reach both rules and
      // fresh IDs.
      const blocks = [
        'Paragraph',
        'Same',
        '# Heading',
        '- item\n- item',
        '> quote',
        '```\ncode\n```',
        '[ ] to-do',
        '---',
        '[details]\nhidden\n[/details]',
      ];
      const pieces = [
        '',
        'x',
        '\n',
        '\n\n',
        '\n\nSame\n\n',
        '# ',
        '- ',
        '> ',
        '```',
        '[ ] ',
        '[wrap]',
        '[/wrap]',
        '<div>',
        '\r\n',
      ];
      final random = Random(2718);
      final reached = <_Retention, int>{
        for (final rule in _Retention.values) rule: 0,
      };
      var outOfOrder = 0;
      ComposerBlockIndex? previous;
      for (var round = 0; round < 4000; round++) {
        if (previous == null || round % 25 == 0) {
          previous = parse(
            [
              for (var i = random.nextInt(12); i >= 0; i--)
                blocks[random.nextInt(blocks.length)],
            ].join('\n\n'),
          );
        }
        if (random.nextInt(4) == 0 && previous.blocks.isNotEmpty) {
          final id = previous.blocks[random.nextInt(previous.blocks.length)].id;
          final gap = random.nextInt(previous.blocks.length + 1);
          previous = previous.move(id, gap)?.after ?? previous;
        }
        final order = ids(previous);
        for (var i = 1; i < order.length; i++) {
          if (order[i] < order[i - 1]) {
            outOfOrder++;
            break;
          }
        }
        final source = previous.source;
        final first = random.nextInt(source.length + 1);
        final second = random.nextInt(source.length + 1);
        final start = min(first, second);
        final end = random.nextInt(3) == 0 ? max(first, second) : start;
        final replacement = random.nextInt(4) == 0
            ? source.substring(start, end)
            : pieces[random.nextInt(pieces.length)];
        final edited = source.replaceRange(start, end, replacement);
        final next = edit(previous, edited);
        expect(
          ids(next),
          _searchedIds(previous, next, reached),
          reason: 'from ${jsonEncode(source)} to ${jsonEncode(edited)}',
        );
        previous = next;
      }
      expect(
        reached.values,
        everyElement(greaterThan(100)),
        reason: '$reached',
      );
      expect(outOfOrder, greaterThan(100));
    });

    test('cost the block count, not its square', () {
      // Every keystroke parses against the previous index. This is timed at
      // the parse, where no snapshot cache can answer a repeated text, and an
      // eightfold document separates one walk from a search per new block.
      (ComposerBlockIndex, String) typing(int count) {
        final source = [
          for (var i = 0; i < count; i++) 'Paragraph $i',
        ].join('\n\n');
        final middle = source.indexOf('Paragraph ${count ~/ 2}');
        return (parse(source), source.replaceRange(middle, middle, 'x'));
      }

      final (smallPrevious, smallSource) = typing(1000);
      final (largePrevious, largeSource) = typing(8000);
      final (:small, :large) = measureScaling(
        () => edit(smallPrevious, smallSource).blocks.length,
        () => edit(largePrevious, largeSource).blocks.length,
      );

      expect(
        large,
        lessThan(small * 25),
        reason: 'eight times the blocks took ${large / small} times as long',
      );
    });
  });
}

enum _Retention { shifted, containsEdit, fresh }

/// The retention rule stated as a search of every previous block, in document
/// order, for each new block.
List<int> _searchedIds(
  ComposerBlockIndex previous,
  ComposerBlockIndex next,
  Map<_Retention, int> reached,
) {
  final before = previous.source;
  final after = next.source;
  var prefix = 0;
  while (prefix < before.length &&
      prefix < after.length &&
      before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var oldSuffix = before.length;
  var newSuffix = after.length;
  while (oldSuffix > prefix &&
      newSuffix > prefix &&
      before.codeUnitAt(oldSuffix - 1) == after.codeUnitAt(newSuffix - 1)) {
    oldSuffix--;
    newSuffix--;
  }
  var fresh = previous.blocks.fold(0, (id, block) => max(id, block.id + 1));
  final used = <int>{};
  final ids = <int>[];
  for (final block in next.blocks) {
    int? retained;
    for (final old in previous.blocks) {
      if (used.contains(old.id) || old.kind != block.kind) continue;
      final shifted = old.start >= oldSuffix
          ? old.start + newSuffix - oldSuffix
          : old.start;
      if ((old.end <= prefix || old.start >= oldSuffix) &&
          shifted == block.start &&
          old.source == block.source) {
        reached.update(_Retention.shifted, (n) => n + 1);
        retained = old.id;
        break;
      }
      if (old.start <= prefix &&
          old.end >= oldSuffix &&
          block.start == old.start &&
          block.end >= newSuffix) {
        reached.update(_Retention.containsEdit, (n) => n + 1);
        retained = old.id;
        break;
      }
    }
    if (retained == null) reached.update(_Retention.fresh, (n) => n + 1);
    final id = retained ?? fresh++;
    used.add(id);
    ids.add(id);
  }
  return ids;
}
