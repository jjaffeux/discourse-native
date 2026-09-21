import 'package:discourse_native/src/shell/composer_block_controller.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_edit_history.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ComposerController composer;
  late ComposerEditHistory history;
  late ComposerBlockController blocks;
  setUp(() {
    composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://example.test',
        topicId: 1,
        slug: 'topic',
        topicTitle: 'Topic',
      ),
    );
    composer.text.value = const TextEditingValue(
      text: 'One\n\nTwo\n\nThree',
      selection: TextSelection.collapsed(offset: 7),
    );
    history = composer.history;
    blocks = composer.blocks;
  });
  tearDown(() {
    composer.dispose();
  });

  test('move restores exact source and caret through undo/redo', () {
    final original = composer.text.value;
    final id = blocks.index.blocks[1].id;
    blocks.select(id);
    expect(blocks.moveTo(0, expectedRevision: blocks.revision), isTrue);
    expect(composer.text.text, 'Two\n\nOne\n\nThree');
    expect(composer.text.selection.extentOffset, 2);
    final moved = composer.text.value;
    history.undo();
    expect(composer.text.value, original);
    expect(blocks.index.blocks[1].id, id);
    history.redo();
    expect(composer.text.value, moved);
    expect(blocks.index.blocks.first.id, id);
  });

  test(
    'moving between adjacent components preserves spacing through undo and redo',
    () {
      const image = '![Photo|100x100](upload://photo)';
      const quote = '[quote="sam, post:1, topic:1"]\nQuoted text\n[/quote]';
      const details = '[details="Summary"]\nBody\n[/details]';
      const original = '$image\n$quote\n$details';
      const moved = '$image\n$details\n$quote';
      composer.text.value = const TextEditingValue(
        text: original,
        selection: TextSelection.collapsed(offset: original.length),
      );
      expect(blocks.index.blocks, hasLength(3));
      expect(
        blocks.moveTo(
          1,
          blockId: blocks.index.blocks.last.id,
          expectedRevision: blocks.revision,
        ),
        isTrue,
      );
      expect(composer.text.text, moved);
      expect(blocks.index.blocks.map((block) => block.label), [
        'Image',
        'Details',
        'Quote',
      ]);
      history.undo();
      expect(composer.text.text, original);
      history.redo();
      expect(composer.text.text, moved);
    },
  );

  test('an edit-undo cycle still rejects a drag captured before the edit', () {
    final index = blocks.index;
    final revision = blocks.revision;
    history.transact(() => composer.text.text = 'Different');
    history.undo();
    expect(composer.text.text, index.source);
    expect(
      blocks.moveTo(
        0,
        blockId: index.blocks.last.id,
        expectedRevision: revision,
      ),
      isFalse,
    );
    expect(composer.notice, 'The draft changed. Move the block again.');
  });

  test('submitting prevents structural mutations', () {
    final id = blocks.index.blocks[1].id;
    composer.beginSubmit();
    expect(
      blocks.moveTo(0, blockId: id, expectedRevision: blocks.revision),
      isFalse,
    );
    expect(blocks.startArranging(), isFalse);
  });

  test('composing input prevents rearranging and source mutations', () {
    composer.text.value = composer.text.value.copyWith(
      composing: const TextRange(start: 0, end: 3),
    );
    final before = composer.text.value;
    expect(
      blocks.moveTo(
        0,
        blockId: blocks.index.blocks.last.id,
        expectedRevision: blocks.revision,
      ),
      isFalse,
    );
    expect(blocks.startArranging(), isFalse);
    expect(composer.text.value, before);
  });

  test(
    'Arrange and Done do not change source, selection or draft revision',
    () {
      final original = composer.text.value;
      final revision = composer.draftRevision;
      expect(blocks.startArranging(), isTrue);
      blocks.select(blocks.index.blocks.last.id);
      blocks.finishArranging();
      expect(composer.text.value, original);
      expect(composer.draftRevision, revision);
    },
  );

  test('quote ranges with owned trailing separators remain movable', () {
    const quote = '[quote="sam, post:1, topic:1"]\nQuoted text\n[/quote]';
    composer.text.value = const TextEditingValue(
      text: 'Before\n\n$quote\n\nAfter',
      selection: TextSelection.collapsed(offset: 1),
    );
    final block = blocks.index.blocks[1];
    expect(block.label, 'Quote');
    expect(
      blocks.moveTo(0, blockId: block.id, expectedRevision: blocks.revision),
      isTrue,
    );
    expect(composer.text.text, '$quote\n\nBefore\n\nAfter');
  });

  test('tables and details move as complete registered components', () {
    const table = '| A | B |\n| --- | --- |\n| 1 | 2 |';
    const details = '[details="Summary"]\nContent\n\nMore content\n[/details]';
    composer.text.value = const TextEditingValue(
      text: '$table\n\nText\n\n$details',
      selection: TextSelection.collapsed(offset: 0),
    );
    expect(blocks.index.blocks.map((b) => b.label), [
      'Table',
      'Paragraph',
      'Details',
    ]);
    expect(
      blocks.moveTo(
        0,
        blockId: blocks.index.blocks.last.id,
        expectedRevision: blocks.revision,
      ),
      isTrue,
    );
    expect(composer.text.text, '$details\n\n$table\n\nText');
  });
}
