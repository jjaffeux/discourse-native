import 'package:discourse_native/src/shell/composer_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('an ordinary edit retains the edited and shifted block identities', () {
    final before = parse('First\n\nSecond\n\nThird');
    final after = ComposerBlockIndex.parse(
      'First longer\n\nSecond\n\nThird',
      previous: before,
    );
    expect(after.blocks.map((b) => b.id), before.blocks.map((b) => b.id));
  });
}
