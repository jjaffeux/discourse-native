import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_blocks.dart';
import 'package:discourse_native/src/shell/composer_list_source.dart';
import 'package:discourse_native/src/shell/composer_lists.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_list_items_test.dart' show pumpEditor, bodies, editable;

Future<void> focusLast(WidgetTester tester) async {
  final body = bodies(tester).last;
  body.text.selection = TextSelection.collapsed(offset: body.text.text.length);
  body.requestFocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'nested and mixed rows preserve compact spacing and task padding',
    (tester) async {
      await pumpEditor(tester, '- Parent\n  - Child\n- [ ] Task\n- Sibling');
      final items = bodies(tester);
      expect(items, hasLength(4));
      final tops = items
          .map((item) => tester.getTopLeft(editable(item)).dy)
          .toList();
      for (var i = 1; i < tops.length; i++) {
        final height = i == 3
            ? tester.getSize(find.byType(DCheckbox)).height + DSpacing.sm
            : 24.0;
        expect(tops[i] - tops[i - 1], closeTo(height, 1));
      }
      expect(tester.takeException(), isNull);
    },
  );
  test('numbering follows Markdown list boundaries without changing source', () {
    const source =
        '3. First\n1. Second\n\n1. Third\n\nParagraph\n\n7) New\n2) Next\n- Bullet\n2. Restart';
    expect(composerListItems(source).map((item) => item.number), [
      3,
      4,
      5,
      7,
      8,
      null,
      2,
    ]);
    expect(
      composerListItems(
        '1. Parent\n   4. Child\n   1. Sibling',
      ).single.children.map((item) => item.number),
      [4, 5],
    );
  });

  for (final newline in ['\n', '\r\n']) {
    test('a closed BBCode block bounds list items (${newline.length})', () {
      List<String> items(List<String> lines) => [
        for (final item in composerListItems(lines.join(newline)))
          item.source.replaceAll(newline, '\n'),
      ];

      // Discourse cooks a block's content between its tags, so an item inside
      // one ends at the closing tag instead of continuing lazily past it.
      const poll = ['[poll]', '* Tea', '* Coffee', '[/poll]'];
      expect(items([...poll, 'After']), ['* Tea', '* Coffee']);
      expect(items([...poll, '| Name | Cost |', '| --- | --- |']), [
        '* Tea',
        '* Coffee',
      ]);
      expect(items(['[poll]', '* Tea', '  [/poll]', 'After']), ['* Tea']);
      expect(
        items(['[quote="sam, post:1, topic:1"]', '- Quoted', '[/quote]']),
        ['- Quoted'],
      );
      // The closing tag ends the block the way the end of a document would.
      expect(items(['[poll]', '* Tea', '  ', '[/poll]']), ['* Tea\n  ']);
      expect(items(['[poll]', '* Tea', '  * Green', '[/poll]']), [
        '* Tea\n  * Green',
      ]);
      expect(
        composerListItems(
          ['1. First', '[poll]', '1. Tea', '[/poll]', '2. Next'].join(newline),
        ).map((item) => item.number),
        [1, 1, 2],
      );

      // Its opening tag interrupts a lazy continuation as it does a paragraph.
      expect(items(['* Before', ...poll]), ['* Before', '* Tea', '* Coffee']);
      expect(
        items([
          '* Before',
          '[details="Summary"]',
          'Body',
          '[/details]',
          'After',
        ]),
        ['* Before'],
      );

      // Unclosed or unmatched tags, a tag inside a fence and a block indented
      // into an item leave Markdown's ordinary continuation alone.
      expect(items(['* Item', '[details]', 'more']), [
        '* Item\n[details]\nmore',
      ]);
      expect(items(['* Item', '[/poll]', 'more']), ['* Item\n[/poll]\nmore']);
      expect(items(['* Item', '[poll]', '[/details]']), [
        '* Item\n[poll]\n[/details]',
      ]);
      expect(items(['* Item', '  [details]', '  Body', '  [/details]']), [
        '* Item\n  [details]\n  Body\n  [/details]',
      ]);
      expect(items(['```', '[poll]', '```', '* Item', '[/poll]']), [
        '* Item\n[/poll]',
      ]);
    });
  }

  test(
    'converting a heading or list preserves text, descendants and caret',
    () {
      TextEditingValue value(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      expect(
        insertComposerList(value('## Heading'), ordered: false),
        value('- Heading'),
      );
      expect(
        insertComposerList(value('- Parent\n  - Child'), ordered: true),
        value('- Parent\n  1. Child'),
      );
      final source = value(
        '- Parent\n  continuation\n  - Child',
      ).copyWith(selection: const TextSelection.collapsed(offset: 5));
      final converted = insertComposerList(source, ordered: true);
      expect(converted.text, '1. Parent\n   continuation\n   - Child');
      expect(converted.selection.extentOffset, 6);
    },
  );

  for (final (marker, next) in [
    ('- ', '- '),
    ('1. ', '2. '),
    ('9) ', '10) '),
  ]) {
    testWidgets(
      '$marker renders, continues, exits and undoes with Native inputs',
      (tester) async {
        final root = await pumpEditor(tester, '${marker}First');
        expect(bodies(tester), hasLength(1));
        expect(find.byType(DCheckbox), findsNothing);
        expect(find.byType(DInput), findsNWidgets(2));
        await focusLast(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(root.text.text, '${marker}First\n$next');
        expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
        expect(find.text('List'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(root.text.text, '${marker}First\n\n');
        expect(root.focus.hasPrimaryFocus, isTrue);
        root.history.undo();
        await tester.pumpAndSettle();
        expect(root.text.text, '${marker}First\n$next');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (query, label, source) in [
    ('/bullet', 'Bulleted list', '- '),
    ('/number', 'Numbered list', '1. '),
  ]) {
    testWidgets('$label inserts from the production slash menu', (
      tester,
    ) async {
      final root = await pumpEditor(tester, '');
      await tester.enterText(editable(root), query);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(root.text.text, source);
      expect(bodies(tester).single.focus.hasPrimaryFocus, isTrue);
      await tester.enterText(editable(bodies(tester).single), 'Item');
      await tester.pumpAndSettle();
      expect(root.text.text, '${source}Item');
      expect(tester.takeException(), isNull);
    });
  }

  for (final marker in ['- ', '* ', '+ ', '1. ']) {
    testWidgets('typing $marker transfers the caret into the list', (
      tester,
    ) async {
      final root = await pumpEditor(tester, '');
      await tester.enterText(editable(root), marker.trim());
      await tester.pumpAndSettle();
      expect(bodies(tester), isEmpty);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: marker,
          selection: TextSelection.collapsed(offset: marker.length),
        ),
      );
      await tester.pumpAndSettle();
      expect(bodies(tester).single.focus.hasPrimaryFocus, isTrue);
      await tester.enterText(editable(bodies(tester).single), 'Typed');
      await tester.pumpAndSettle();
      expect(root.text.text, '${marker}Typed');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Shift Return continues and Tab indents a complete item', (
    tester,
  ) async {
    final root = await pumpEditor(tester, '1. First\n2. Second');
    await focusLast(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(root.text.text, '1. First\n2. Second\n   ');
    await tester.enterText(editable(bodies(tester).last), 'Second\ncontinued');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(root.text.text, '1. First\n   2. Second\n      continued');
    expect(bodies(tester).last.focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(root.text.text, '1. First\n2. Second\n   continued');
    root.history.undo();
    await tester.pumpAndSettle();
    expect(root.text.text, '1. First\n   2. Second\n      continued');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty nested bullet outdents and Backspace unwraps a later item',
    (tester) async {
      final root = await pumpEditor(tester, '- Parent\n  - ');
      await focusLast(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(root.text.text, '- Parent\n- ');
      await tester.enterText(editable(bodies(tester).last), 'Second');
      await tester.pumpAndSettle();
      bodies(tester).last.text.selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(root.text.text, '- Parent\n\nSecond');
      expect(bodies(tester), hasLength(1));
      expect(root.focus.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'moving a numbered item retains its subtree and recalculates ordinals',
    (tester) async {
      final root = await pumpEditor(
        tester,
        '1. First\n   - Child\n2. Second\n3. Third',
      );
      final index = root.blocks.index;
      expect(
        index.blocks.map((block) => block.kind),
        everyElement(ComposerBlockKind.list),
      );
      expect(
        root.blocks.moveTo(
          1,
          blockId: index.blocks.last.id,
          expectedRevision: root.blocks.revision,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(root.text.text, '1. First\n   - Child\n3. Third\n2. Second');
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.text.text, '1. First\n   - Child\n2. Second\n3. Third');
    },
  );

  testWidgets('code and composing markers stay literal', (tester) async {
    final root = await pumpEditor(
      tester,
      '```md\n- Literal\n1. Literal\n```\n\n    - Code',
    );
    expect(bodies(tester), isEmpty);
    // Clear the document before addressing its native field: the fenced code
    // editor is itself an EditableText descendant of the document field.
    root.text.clear();
    root.requestFocus();
    await tester.pumpAndSettle();
    await tester.showKeyboard(editable(root));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '- ',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(bodies(tester), isEmpty);
    expect(root.value.composing, const TextRange(start: 0, end: 2));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '- ',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pumpAndSettle();
    expect(bodies(tester).single.focus.hasPrimaryFocus, isTrue);
  });

  testWidgets('typing after an empty-item exit remains a paragraph', (
    tester,
  ) async {
    final root = await pumpEditor(tester, '- First\n- ');
    await focusLast(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '${root.text.text}Paragraph',
        selection: TextSelection.collapsed(offset: root.text.text.length + 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(root.text.text, '- First\n\nParagraph');
    expect(bodies(tester).single.text.text, 'First');
    expect(root.focus.hasPrimaryFocus, isTrue);
  });

  testWidgets(
    'slash command changes the current list type without nesting it',
    (tester) async {
      final root = await pumpEditor(tester, '- First');
      await tester.enterText(editable(bodies(tester).single), 'First /number');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(root.text.text, '1. First ');
      expect(bodies(tester), hasLength(1));
      expect(bodies(tester).single.focus.hasPrimaryFocus, isTrue);
      root.history.undo();
      await tester.pumpAndSettle();
      expect(root.text.text, '- First ');
    },
  );

  testWidgets('Return retains CRLF and splits an item at the caret', (
    tester,
  ) async {
    final root = await pumpEditor(tester, '1. First\r\n2. Second');
    final body = bodies(tester).first;
    body.text.selection = const TextSelection.collapsed(offset: 2);
    body.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(root.text.text, '1. Fi\r\n2. rst\r\n2. Second');
    expect(find.text('3.'), findsOneWidget);
  });

  testWidgets('mixed lists fit a narrow editor at 200% text size', (
    tester,
  ) async {
    final root = await pumpEditor(
      tester,
      '- A longer line of text wraps beside the bullet\n  1. Numbered child\n  1. Second child\n- [ ] Task\n\n10. Numbered\n1. ',
      scale: 2,
    );
    expect(bodies(tester), hasLength(6));
    expect(find.byType(DCheckbox), findsOneWidget);
    expect(find.text('11.'), findsOneWidget);
    expect(root.text.text, contains('1. Second child'));
    expect(tester.takeException(), isNull);
  });
}
