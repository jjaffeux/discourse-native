import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/shell/composer_list_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import 'composer_list_items_test.dart' show pumpEditor, bodies, editable;

const _cases = [
  (
    name: 'nested task',
    source: '- [ ] Parent\n  - [x] Child\nTail',
    depth: 1,
    body: 'Child\nTail',
  ),
  (
    name: 'deep tasks',
    source: '- [ ] Parent\n  - [ ] Middle\n    - [x] Child\nTail',
    depth: 2,
    body: 'Child\nTail',
  ),
  (
    name: 'mixed ordered and bullet lists',
    source: '1. [ ] Parent\n   + Middle\n     1) [x] Child\nTail',
    depth: 2,
    body: 'Child\nTail',
  ),
  (
    name: 'indented paragraph before lazy text',
    source: '- [ ] Parent\n  - Middle\n    - [x] Child\n      Continued\nTail',
    depth: 2,
    body: 'Child\nContinued\nTail',
  ),
  (
    name: 'partially indented lazy lines',
    source: '- [ ] Parent\n  1. Middle\n     * [x] Child\n   Partial\nTail',
    depth: 2,
    body: 'Child\nPartial\nTail',
  ),
];

Future<String> _cook(OfflineCookingService service, String source) async {
  final result = await service.cook(
    CookingRequest(
      raw: source,
      configuration: CookingConfiguration(
        modules: [
          CookingModule(id: 'checklist', owner: 'cooking', version: '1'),
          CookingModule(id: 'details', owner: 'cooking', version: '1'),
        ],
      ),
      snapshot: CookingSnapshot(
        siteId: 'test-site',
        accountId: 'test-account',
        pluginContext: {
          'cooking': {
            'settings': {'checklist_enabled': true},
          },
        },
      ),
    ),
  );
  expect(result.failure, isNull);
  return result.html;
}

String _prose(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

void main() {
  test(
    'lazy continuation after a nested child remains owned by that child',
    () {
      const source = '- [ ] Parent\n  - [x] Child\nTail';
      final parent = composerListItems(source).single;
      expect(parent.children.single.body.text, 'Child\nTail');
      expect(parent.end, source.length);
    },
  );

  for (final example in _cases) {
    for (final newline in ['\n', '\r\n']) {
      test(
        '${example.name} preserves source and caret maps (${newline.length})',
        () {
          final source = example.source.replaceAll('\n', newline);
          final chain = [composerListItems(source).single];
          for (var i = 0; i < example.depth; i++) {
            chain.add(chain.last.children.single);
          }
          for (final item in chain) {
            expect(item.end, item.document.length);
            expect(item.body.replace(item.body.text), item.source);
            for (var offset = 0; offset <= item.body.text.length; offset++) {
              expect(
                item.body.localOffset(item.body.sourceOffset(offset)),
                offset,
              );
            }
          }
          final leaf = chain.last;
          expect(leaf.body.text, example.body);
          for (var offset = 0; offset <= leaf.body.text.length; offset++) {
            var mapped = offset;
            for (final item in chain.reversed) {
              mapped = item.body.sourceOffset(mapped);
            }
            if (offset < leaf.body.text.length &&
                leaf.body.text[offset] != '\n') {
              expect(source[mapped], leaf.body.text[offset]);
            }
          }
          var replacement = leaf.body.replace(
            leaf.body.text.replaceFirst('Tail', 'Edited tail'),
          );
          for (var i = chain.length - 2; i >= 0; i--) {
            final child = chain[i + 1];
            final parent = chain[i];
            replacement = parent.body.replace(
              parent.body.text.replaceRange(
                child.start,
                child.end,
                replacement,
              ),
            );
          }
          expect(replacement, source.replaceFirst('Tail', 'Edited tail'));
        },
      );
    }

    test('${example.name} agrees with bundled Discourse cooking', () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final cooked = html.parseFragment(await _cook(service, example.source));
      final items = cooked.querySelectorAll('li');
      expect(items, hasLength(example.depth + 1));
      expect(_prose(items.last.text), _prose(example.body));
    });
  }

  for (final boundary in [
    '\nAfter',
    '\n| Name | Count |\n| --- | --- |\n| Item | 1 |',
    '# Heading',
    '```text\nOutside\n```',
    '> Quote',
    '---',
    '<div>Outside</div>',
    '[details="Summary"]\nOutside\n[/details]',
    '- [ ] Sibling',
  ]) {
    test('a following block ends nested lazy ownership: $boundary', () async {
      const prefix = '- [ ] Parent\n  - [x] Child\nTail';
      final source = '$prefix\n$boundary';
      final parent = composerListItems(source).first;
      expect(parent.source, prefix);
      expect(parent.children.single.body.text, 'Child\nTail');
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final cooked = html.parseFragment(await _cook(service, source));
      expect(_prose(cooked.querySelectorAll('li')[1].text), 'Child Tail');
    });
  }

  for (final depth in [1, 2, 3]) {
    for (final block in [
      ['```text', 'Code', '```'],
      ['# Heading'],
      ['---'],
    ]) {
      test('nested ${block.first} ends paragraph state at depth $depth', () {
        final prefix = [
          '- [ ] Parent',
          for (var i = 1; i <= depth; i++) '${'  ' * i}- [x] Child$i',
          for (final line in block) '${'  ' * (depth + 1)}$line',
        ].join('\n');
        final parent = composerListItems('$prefix\nOutside').single;
        expect(parent.source, prefix);
      });
    }
  }

  test(
    'blank lines return paragraph ownership to the appropriate ancestor',
    () {
      const source = '- [ ] Parent\n  - [x] Child\n\n  Parent paragraph\nTail';
      final parent = composerListItems(source).single;
      expect(parent.source, source);
      expect(parent.children.single.body.text, 'Child');
      expect(parent.body.text, endsWith('Parent paragraph\nTail'));
      expect(
        composerListItems(
          '- [ ] Parent\n  - [x] Child\n\nOutside',
        ).single.source,
        '- [ ] Parent\n  - [x] Child',
      );
    },
  );

  test('a nested sibling owns its own lazy continuation', () {
    const source = '- [ ] Parent\n  - [x] Child\nTail\n  1. Sibling\nMore';
    final parent = composerListItems(source).single;
    expect(parent.source, source);
    expect(parent.children.map((child) => child.body.text), [
      'Child\nTail',
      'Sibling\nMore',
    ]);
  });

  for (final block in ['# Heading', '```\n  Code\n  ```']) {
    test('an ancestor block ends the child paragraph: $block', () async {
      const childSource = '- [ ] Parent\n  - [x] Child\nTail';
      final source = '$childSource\n  $block\nOutside';
      final parent = composerListItems(source).single;
      expect(parent.source, '$childSource\n  $block');
      expect(parent.children.single.body.text, 'Child\nTail');
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final cooked = html.parseFragment(await _cook(service, source));
      expect(_prose(cooked.querySelectorAll('li')[1].text), 'Child Tail');
      expect(cooked.children.last.outerHtml, '<p>Outside</p>');
    });
  }

  for (final newline in ['\n', '\r\n']) {
    testWidgets(
      'lazy text renders and edits in the checked child (${newline.length})',
      (tester) async {
        final source = _cases[1].source.replaceAll('\n', newline);
        final root = await pumpEditor(tester, source);
        addTearDown(() async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        });
        final child = bodies(tester).last;
        expect(child.text.text, 'Child\nTail');
        expect(child.item.checked, isTrue);
        final rendered = tester
            .state<EditableTextState>(editable(child))
            .renderEditable
            .text!;
        expect(rendered.toPlainText(), contains('Child\nTail'));
        expect(
          rendered
              .getSpanForPosition(const TextPosition(offset: 8))
              ?.style
              ?.decoration,
          TextDecoration.lineThrough,
        );
        expect(root.raw, source);
        child.text.selection = const TextSelection.collapsed(offset: 8);
        child.requestFocus();
        await tester.pumpAndSettle();
        expect(root.text.selection.extentOffset, source.indexOf('Tail') + 2);
        final before = TextEditingValue.fromJSON(
          tester.testTextInput.editingState!,
        );
        tester.testTextInput.updateEditingValue(
          before.copyWith(
            text: before.text.replaceRange(
              before.selection.start,
              before.selection.end,
              '!',
            ),
            selection: TextSelection.collapsed(
              offset: before.selection.start + 1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(root.raw, source.replaceFirst('Tail', 'Ta!il'));
        expect(root.text.selection.extentOffset, source.indexOf('Tail') + 3);
        expect(bodies(tester).last.text.text, 'Child\nTa!il');
        root.history.undo();
        await tester.pumpAndSettle();
        expect(root.raw, source);
        root.history.redo();
        await tester.pumpAndSettle();
        expect(root.raw, source.replaceFirst('Tail', 'Ta!il'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
