import 'dart:async';

import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_tables.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

void main() {
  ComposerTableBlock parse(String source) => parseComposerTables(source).single;

  test('recognizes every table when a body row omits its final cells', () {
    const tuesday =
        '| **Teams** | **# ppl** | **Delegate(s)** | **People** | **Activity** |\n'
        '|:---|:---|:---|:---|:---|\n'
        '| Group One | 2 | @delegate | @one, @two | Walk |\n'
        '| Group Two| 3| @delegate| @one, @two, @three|';
    const source =
        '## Tuesday\n\n$tuesday\n\n## Wednesday\n\n| Team | Activity |\n|:--|:--|\n| Group | |';
    final tables = parseComposerTables(source);
    expect(tables, hasLength(2));
    final table = tables.first;
    expect(table.source, tuesday);
    expect(table.columnCount, 5);
    expect(table.rowCount, 2);
    expect(table.cell(2, 4), '');
    expect(table.editCell(2, 4, ''), tuesday);
    final edited = parse(table.editCell(2, 4, 'Coffee'));
    expect(edited.cell(2, 4), 'Coffee');
    expect(edited.cell(2, 3), '@one, @two, @three');
    expect(edited.source.split('\n').take(3), tuesday.split('\n').take(3));
    final moved = parse(table.moveColumn(4, 0));
    expect(moved.cell(0, 0), '**Activity**');
    expect(moved.cell(1, 0), 'Walk');
    expect(moved.cell(2, 0), '');
    expect(parse(table.insertColumn(4)).columnCount, 6);
    expect(parse(table.removeColumn(4)).cell(2, 3), '@one, @two, @three');
  });

  test('extra body cells remain in source without hiding the table', () {
    const source = '| A | B |\n| --- | --- |\n| x | y | extra |';
    final table = parse(source);
    expect(table.columnCount, 2);
    expect(table.cell(1, 1), 'y');
    expect(
      table.editCell(1, 1, 'changed'),
      source.replaceFirst(' y ', ' changed '),
    );
    expect(table.moveColumn(0, 1), contains('| y | x | extra |'));
  });

  test(
    'edits only the selected cell and retains offsets, whitespace and CRLF',
    () {
      const source =
          'Before\r\n\r\n | Name | Cost | \r\n | :--- | ---: |\r\n | **Tea**  |  12 |\r\n\r\nAfter';
      final table = parse(source);
      expect(table.start, 10);
      expect(table.columnCount, 2);
      expect(table.rowCount, 1);
      expect(table.cell(1, 0), '**Tea**');
      expect(
        source.replaceRange(table.start, table.end, table.editCell(1, 1, '30')),
        source.replaceFirst('12', '30'),
      );
    },
  );

  test(
    'escaped pipes and code cells survive column movement with alignment',
    () {
      final table = parse(
        r'| A | B |'
        '\n'
        '| :--- | ---: |'
        '\n'
        r'| `a\|b` | **two** |',
      );
      expect(table.columnCount, 2);
      final moved = parse(table.moveColumn(0, 1));
      expect(moved.cell(0, 0), 'B');
      expect(moved.cell(1, 1), r'`a\|b`');
      expect(moved.source, contains('| ---: | :--- |'));
      expect(parse(moved.moveColumn(1, 0)).source, table.source);
    },
  );

  test(
    'inserts and moves rows without moving the header or changing cell source',
    () {
      const source = '| A | B |\n| --- | --- |\n| **one** | 1 |\n| two | 2 |';
      final moved = parse(parse(source).moveRow(1, 0));
      expect(moved.cell(0, 0), 'A');
      expect(moved.cell(1, 0), 'two');
      expect(moved.cell(2, 0), '**one**');
      final inserted = parse(moved.insertRow(1));
      expect(inserted.rowCount, 3);
      expect(inserted.cell(2, 0), '');
      expect(inserted.cell(3, 0), '**one**');
      expect(parse(inserted.removeRow(1)).source, moved.source);
    },
  );

  test(
    'inserts and removes columns across header, delimiter and every row',
    () {
      final table = parse('A | B\n:--- | ---:\nx | y');
      final inserted = parse(table.insertColumn(1));
      expect(inserted.columnCount, 3);
      expect(inserted.cell(0, 1), '');
      expect(inserted.cell(1, 2), 'y');
      final removed = parse(inserted.removeColumn(0));
      expect(removed.columnCount, 2);
      expect(removed.cell(0, 1), 'B');
      expect(removed.source, contains('---:'));
      final only = parse(removed.removeColumn(0));
      expect(only.removeColumn(0), only.source);
    },
  );

  test(
    'new cell pipes, newlines and trailing slashes remain a valid table',
    () {
      final table = parse('| A | B |\n| --- | --- |\n|  |  |');
      final changed = parse(table.editCell(1, 0, 'one | two\nthree\\'));
      expect(changed.columnCount, 2);
      expect(changed.cell(1, 0), r'one \| two<br>three\\');
      expect(changed.cell(1, 1), '');
    },
  );

  test(
    'leaves mismatched headers, code, list, quote and HTML tables untouched',
    () {
      for (final source in [
        '| A | B |\n| --- |\n| x | y |',
        '```md\n| A | B |\n| --- | --- |\n| x | y |\n```',
        '    | A | B |\n    | --- | --- |\n    | x | y |',
        '> | A | B |\n> | --- | --- |\n> | x | y |',
        '- A | B\n- --- | ---\n- x | y',
        '<table><tr><td>A</td></tr></table>',
      ]) {
        expect(parseComposerTables(source), isEmpty, reason: source);
      }
    },
  );

  test('a fenced table stays code beside tables outside the fence', () {
    const table = '| A | B |\n| --- | --- |\n| x | y |';
    const source = '$table\n\n```md\n$table\n```\n\n$table';
    expect(parseComposerTables(source).map((block) => block.start), [
      0,
      source.length - table.length,
    ]);
  });

  test('a stray pipe in prose costs a keystroke no markdown scan', () {
    // Both the table projection and its input formatter parse every edit.
    // Prose with a pipe but no header and delimiter pair has no table, so
    // neither may scan the draft for code blocks or images on its behalf.
    for (final paragraphs in [60, 480]) {
      final prose = List.filled(paragraphs, _paragraph).join('\n\n');
      final (small: plain, large: piped) = measureScaling(
        _keystrokes(prose),
        _keystrokes('$prose\n\nx | y'),
      );
      expect(
        piped,
        lessThan(plain * 1.5),
        reason:
            'one pipe made a keystroke ${piped / plain} times as long over '
            '${prose.length} characters',
      );
    }
  });

  test('supports header-only, single-column and multiple tables', () {
    expect(parse('| A |\n| --- |').rowCount, 0);
    const source = '| A |\n| --- |\n\ntext\n\n| B |\n| --- |\n| x |';
    expect(parseComposerTables(source).map((table) => table.rowCount), [0, 1]);
  });

  test(
    'atomic formatter allows complete replacement but rejects partial edits',
    () {
      const source = 'Before\n\n| A | B |\n| --- | --- |\n| x | y |\n\nAfter';
      final table = parse(source);
      final old = TextEditingValue(
        text: source,
        selection: TextSelection(
          baseOffset: table.start,
          extentOffset: table.end,
        ),
      );
      const formatter = ComposerTableInputFormatter();
      final partial = TextEditingValue(text: source.replaceFirst('x', 'z'));
      final caret = old.copyWith(
        selection: TextSelection.collapsed(offset: table.end),
      );
      expect(formatter.formatEditUpdate(caret, partial), caret);
      final deleted = TextEditingValue(
        text: source.replaceRange(table.start, table.end, ''),
      );
      expect(formatter.formatEditUpdate(old, deleted), deleted);
    },
  );
}

const _target = ComposerTarget(
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);

const _paragraph =
    'The quick brown fox jumps over the **lazy** dog, then naps in the '
    '_shade_ of an old oak by the river.';

/// Types a character at the end of [document] and deletes it again the way
/// the editor applies an edit: input formatters, the new value, then the
/// microtasks the edit queued, so that everything a keystroke pays is timed.
int Function() _keystrokes(String document) {
  final composer = ComposerController(_target);
  addTearDown(composer.dispose);
  composer.text.text = document;
  composer.text.selection = TextSelection.collapsed(offset: document.length);
  final microtasks = <void Function()>[];
  final zone = Zone.current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, task) => microtasks.add(task),
    ),
  );
  void apply(TextEditingValue next) {
    final before = composer.text.value;
    for (final formatter in composer.text.syntaxInputFormatters) {
      next = formatter.formatEditUpdate(before, next);
    }
    composer.text.value = next;
    while (microtasks.isNotEmpty) {
      microtasks.removeAt(0)();
    }
  }

  return () => zone.run(() {
    final value = composer.text.value;
    apply(
      TextEditingValue(
        text: '${value.text}a',
        selection: TextSelection.collapsed(offset: value.text.length + 1),
      ),
    );
    apply(value);
    return composer.raw.length;
  });
}
