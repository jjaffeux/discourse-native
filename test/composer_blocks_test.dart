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
      expect(parse(nested).blocks.single.source, nested);
      expect(parse(nested).blocks.single.kind, ComposerBlockKind.list);
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
