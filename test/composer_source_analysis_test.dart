import 'package:discourse_native/src/shell/composer/blocks.dart';
import 'package:discourse_native/src/shell/composer/components/gallery_source.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/components/todo_source.dart';
import 'package:discourse_native/src/shell/composer/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/composer/source_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'marker sets reuse matching results and retain a structural default',
    () {
      const source = '- [x] Linked\n\n[x] Standalone';
      final analysis = ComposerSourceAnalysis(source);
      final structural = analysis.listItems();
      final markers = {'[x]', '[other]'};
      final configured = analysis.listItems(referenceMarkers: markers);
      expect(structural.single.isTask, isTrue);
      expect(configured.single.isTask, isFalse);
      expect(
        analysis.listItems(referenceMarkers: {'[other]', '[x]'}),
        same(configured),
      );
      markers.clear();
      expect(
        analysis.listItems(referenceMarkers: {'[x]', '[other]'}),
        same(configured),
      );
      expect(analysis.listItems(), same(structural));
      expect(analysis.todos(referenceMarkers: {'[x]'}), isEmpty);
      expect(analysis.todos(), hasLength(2));
      expect(analysis.listItems().single.isTask, isTrue);
      expect(() => structural.clear(), throwsUnsupportedError);
      expect(() => analysis.todos().clear(), throwsUnsupportedError);
    },
  );

  test(
    'complete todo derivation retains standalone and nested source offsets',
    () {
      const source =
          '[ ] Standalone\r\n\r\n'
          '- [x] Parent\r\n  - [ ] Child\r\n\r\n'
          '<!-- [ ] Hidden -->\r\n\r\n'
          '```\r\n[ ] Code\r\n```';
      final todos = ComposerSourceAnalysis(source).todos();
      expect(
        todos.map((todo) => source.substring(todo.contentStart, todo.end)),
        ['Standalone', 'Parent', 'Child'],
      );
      expect(todos.map((todo) => todo.checked), [false, true, false]);
      expect(todos.map((todo) => todo.parentStart), [
        null,
        null,
        source.indexOf('- [x]'),
      ]);
      expect(_todoState(todos), _todoState(composerTodos(source)));
    },
  );

  test('shared and standalone parsing agree across structural edits', () {
    for (final source in [
      'Before\n\n- [ ] Parent\n  - [x] Child\n\n[ ] Standalone\nAfter',
      'Before\r\n\r\n- [ ] Parent\r\n  - [x] Child\r\n\r\n[x] Done',
      '[x] Reference\n\n- [x] Linked\n\n[x]: https://example.com',
      '<!--\n- [ ] Hidden\n[ ] Hidden\n-->\n\n- Visible',
      '```\n- [ ] Code\n```\n\n[ ] After',
      '```\n- [ ] Unclosed\n\n[ ] Still code',
      '[quote]\n- [ ] Nested\n[/quote]\n\nAfter',
    ]) {
      final analysis = ComposerSourceAnalysis(source);
      expect(_todoState(analysis.todos()), _todoState(composerTodos(source)));
      expect(
        _todoState(composerTodos(source, listItems: analysis.listItems())),
        _todoState(composerTodos(source)),
      );
      expect(
        _blockState(ComposerBlockIndex.parse(source, analysis: analysis)),
        _blockState(ComposerBlockIndex.parse(source)),
      );
    }
  });

  test(
    'a mismatched structural analysis falls back to the requested source',
    () {
      final analysis = ComposerSourceAnalysis('- [ ] Previous');
      const source = '# Heading\n\n[ ] Current';
      final index = ComposerBlockIndex.parse(source, analysis: analysis);
      expect(index.blocks.map((block) => block.source), [
        '# Heading',
        '[ ] Current',
      ]);
      expect(index.blocks.map((block) => block.kind), [
        ComposerBlockKind.heading,
        ComposerBlockKind.todo,
      ]);
    },
  );

  test('controller analyses follow explicit sources and reference changes', () {
    const source = '- [x] Current\n\n[x] Standalone';
    final controller = MarkdownEditingController(text: source);
    final other = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    addTearDown(other.dispose);
    final original = controller.sourceAnalysisFor(source);
    expect(controller.todos, hasLength(2));
    expect(other.sourceAnalysisFor(source), isNot(same(original)));
    final markers = {'[x]'};
    controller.todoReferenceMarkers = markers;
    markers.clear();
    expect(controller.todos, isEmpty);
    expect(controller.todoReferenceMarkers, {'[x]'});
    expect(
      ComposerBlockIndex.parse(source, analysis: original).blocks.first.kind,
      ComposerBlockKind.todo,
    );
    const candidate = '- [ ] Candidate';
    expect(
      controller.sourceAnalysisFor(candidate).listItems().single.source,
      candidate,
    );
    expect(controller.text, source);
    expect(controller.todos, isEmpty);
    controller.todoReferenceMarkers = {};
    expect(controller.todos, hasLength(2));
    controller.text = candidate;
    expect(controller.todos.single.checked, isFalse);
    expect(controller.sourceAnalysisFor(controller.text).source, candidate);
  });

  test(
    'gallery parser retains supplied canonical images and standalone parity',
    () {
      const source =
          '![Outside](upload://outside[grid])\n\n'
          '[grid]\n![First](upload://first)\n![Second](upload://second)\n[/grid]';
      final images = parseComposerImages(source);
      final shared = parseComposerImageGalleries(source, images: images).single;
      final standalone = parseComposerImageGalleries(source).single;
      expect(images, hasLength(3));
      expect(shared.source, standalone.source);
      expect(shared.start, standalone.start);
      expect(shared.end, standalone.end);
      expect(shared.mode, standalone.mode);
      expect(shared.images.first, same(images[1]));
      expect(shared.images.last, same(images[2]));
      expect(
        shared.images.map((image) => image.source),
        standalone.images.map((image) => image.source),
      );
    },
  );

  test(
    'controller gallery members keep canonical identity after source changes',
    () {
      const source = '[grid]\n![First](upload://first)\n[/grid]';
      final controller = MarkdownEditingController(text: source);
      addTearDown(controller.dispose);
      final original = controller.galleryBlocks.single.images.single;
      expect(original, same(controller.imageBlocks.single));
      controller.text = source.replaceFirst('First', 'Changed');
      final current = controller.galleryBlocks.single.images.single;
      expect(current, same(controller.imageBlocks.single));
      expect(current, isNot(same(original)));
      expect(current.alt, 'Changed');
      expect(controller.imageAtOffset(current.start), same(current));
    },
  );
}

List<Object> _todoState(Iterable<ComposerTodo> todos) => [
  for (final todo in todos)
    (
      todo.start,
      todo.markerStart,
      todo.contentStart,
      todo.end,
      todo.checked,
      todo.itemEnd,
      todo.continuationIndent,
      todo.parentStart,
    ),
];

List<Object> _blockState(ComposerBlockIndex index) => [
  for (final block in index.blocks)
    (
      block.id,
      block.start,
      block.end,
      block.kind,
      block.source,
      block.movable,
      block.componentLabel,
    ),
];
