import 'package:discourse_native/src/shell/composer_details_blocks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes default, quoted, legacy and smart-quoted summaries', () {
    for (final (tag, title, open) in [
      ('[details]', '', false),
      ('[DETAILS="A ] title" open]', 'A ] title', true),
      ("[details='A title' future=keep]", 'A title', false),
      ('[details=Legacy title]', 'Legacy title', false),
      ('[details=“Smart title” open=false]', 'Smart title', false),
    ]) {
      final source = 'Before\n\n$tag\n**Body**\n[/details]\n\nAfter';
      final block = parseComposerDetails(source).single;
      expect(block.summary, title);
      expect(block.open, open);
      expect(block.body, '**Body**');
      expect(source.substring(block.start, block.end), block.source);
      expect(block.withSummary(title), block.source);
      expect(block.withBody(block.body), block.source);
    }
  });

  test('nested details belong to one outer block and siblings stay separate', () {
    const source =
        '[details="Outer"]\nFirst\n[details="Inner"]\nNested\n[/details]\nLast\n[/details]\n\n[details]Sibling[/details]';
    final blocks = parseComposerDetails(source);
    expect(blocks, hasLength(2));
    expect(
      blocks.first.body,
      'First\n[details="Inner"]\nNested\n[/details]\nLast',
    );
    expect(blocks.last.body, 'Sibling');
  });

  test('code examples, escaped tags and incomplete blocks remain text', () {
    for (final source in [
      '```\n[details]\nCode\n[/details]\n```',
      '    [details]\n    Code\n    [/details]',
      '`[details]Code[/details]`',
      r'\[details]Example[/details]',
      'prose [details]Example[/details]',
      '[details]\nUnclosed',
      '[details]\n[details]\nInner\n[/details]',
      '[details]\nBody\n[/details] trailing text',
    ]) {
      expect(parseComposerDetails(source), isEmpty, reason: source);
    }
  });

  test('closing tags inside fences do not end a block', () {
    const source = '[details]\n```\n[/details]\n```\nBody\n[/details]';
    expect(
      parseComposerDetails(source).single.body,
      '```\n[/details]\n```\nBody',
    );
  });

  test('field edits retain other attributes, casing, whitespace and CRLF', () {
    const source =
        '[DETAILS=\'Title\' open future="yes"]  \r\n  **Body**  \r\n[/DETAILS]';
    final block = parseComposerDetails(source).single;
    expect(block.withSummary('New'), source.replaceFirst("='Title'", '="New"'));
    expect(block.withSummary(''), source.replaceFirst("='Title'", ''));
    expect(
      block.withBody('New\nbody'),
      source.replaceFirst('  **Body**  ', 'New\r\nbody'),
    );
    final quoted = block.withSummary('He said "it\'s done"');
    expect(parseComposerDetails(quoted).single.summary, 'He said "it\'s done"');
  });

  test('empty and single-line blocks remain valid when their body changes', () {
    for (final source in [
      '[details][/details]',
      '[details]\n[/details]',
      '[details]\n\n[/details]',
    ]) {
      final block = parseComposerDetails(source).single;
      expect(block.body, '');
      expect(parseComposerDetails(block.withBody('New')).single.body, 'New');
      expect(
        parseComposerDetails(block.withBody('New\nbody')).single.body,
        'New\nbody',
      );
    }
  });

  test('platform edits cannot partially delete hidden delimiters', () {
    const source = 'Before\n[details]\nHidden\n[/details]\nAfter';
    final block = parseComposerDetails(source).single;
    const formatter = ComposerDetailsInputFormatter();
    final old = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: block.start + 1),
    );
    final partial = TextEditingValue(
      text: source.replaceRange(block.start, block.start + 1, ''),
      selection: TextSelection.collapsed(offset: block.start),
    );
    expect(formatter.formatEditUpdate(old, partial), old);
    final selected = old.copyWith(
      selection: TextSelection(
        baseOffset: block.start,
        extentOffset: block.end,
      ),
    );
    final removed = TextEditingValue(
      text: source.replaceRange(block.start, block.end, ''),
      selection: TextSelection.collapsed(offset: block.start),
    );
    expect(formatter.formatEditUpdate(selected, removed), removed);
  });
}
