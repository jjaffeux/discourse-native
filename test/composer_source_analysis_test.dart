import 'package:discourse_native/src/plugin_api/composer_syntax.dart';
import 'package:discourse_native/src/shell/composer/blocks.dart';
import 'package:discourse_native/src/shell/composer/components/details.dart';
import 'package:discourse_native/src/shell/composer/components/gallery_source.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/components/todo_source.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/composer/source_analysis.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final spacingFirst in [false, true]) {
    test(
      'compatible block structures share in either order: $spacingFirst',
      () {
        const source = 'Before\r\n\r\n![Photo](upload://photo)\r\n\r\nAfter';
        final controller = MarkdownEditingController(
          text: source,
          enableBlockSeparators: true,
        );
        final other = MarkdownEditingController(text: source);
        addTearDown(controller.dispose);
        addTearDown(other.dispose);
        final first = controller.blockStructure(forSpacing: spacingFirst);
        expect(
          controller.blockStructure(forSpacing: !spacingFirst),
          same(first),
        );
        expect(other.blockStructure(), isNot(same(first)));
        expect(
          ComposerBlockIndex.fromStructure(first).blocks[1].label,
          'Image',
        );
        controller.blockGaps;
        controller.text = '$source!';
        final edited = controller.blockStructure(forSpacing: !spacingFirst);
        expect(edited, isNot(same(first)));
        expect(edited.source, '$source!');
        expect(
          controller.blockStructure(forSpacing: spacingFirst),
          same(edited),
        );
        expect(first.source, source);
        expect(() => first.atoms.clear(), throwsUnsupportedError);
      },
    );
  }

  test('list spacing and block controls retain their different atoms', () {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);
    composer.text.text = 'Before\n\n- First\n- Second\n\nAfter';
    final full = composer.text.blockStructure();
    final spacing = composer.text.blockStructure(forSpacing: true);
    expect(full, isNot(same(spacing)));
    expect(full.atoms, hasLength(2));
    expect(spacing.atoms, isEmpty);
    for (final structure in [full, spacing]) {
      expect(
        _blockState(ComposerBlockIndex.fromStructure(structure)),
        _blockState(
          ComposerBlockIndex.parse(structure.source, atoms: structure.atoms),
        ),
      );
    }
    expect(composer.text.blockStructure(), same(full));
    expect(composer.text.blockStructure(forSpacing: true), same(spacing));
    expect(composer.text.blockSeparators, [
      const TextRange(start: 6, end: 8),
      const TextRange(start: 24, end: 26),
    ]);
  });

  test('same-source syntax invalidation updates structures and spacing', () {
    final host = ComposerController(_target);
    addTearDown(host.dispose);
    final policy = _SwitchablePolicy(ComposerDetailsPolicy(host));
    const source = 'Before\n\n[details]\nBody\n[/details]\n\nAfter';
    final controller = MarkdownEditingController(
      text: source,
      syntaxPolicies: [policy],
      enableBlockSeparators: true,
    );
    addTearDown(controller.dispose);
    final full = controller.blockStructure();
    expect(full.atoms, hasLength(1));
    expect(controller.blockSeparators, isEmpty);
    policy.enabled = false;
    controller.updateMarkdownLinkify(enabled: false, tlds: []);
    final changed = controller.blockStructure();
    expect(changed, isNot(same(full)));
    expect(changed.atoms, isEmpty);
    expect(controller.blockSeparators, hasLength(2));
    expect(controller.blockStructure(forSpacing: true), same(changed));
    controller.rawMarkdown = true;
    expect(controller.blockSeparators, isEmpty);
    expect(controller.blockGaps, isEmpty);
    controller.rawMarkdown = false;
    expect(controller.blockSeparators, hasLength(2));
    expect(controller.text, source);
  });

  for (final newline in ['\n', '\r\n']) {
    test(
      'compact spacing updates with unchanged source: ${newline.length}',
      () {
        final controller = MarkdownEditingController(
          text: 'Before$newline- First',
          enableBlockSeparators: true,
        );
        addTearDown(controller.dispose);
        final expected = TextRange(start: 6, end: 6 + newline.length);
        expect(controller.blockGaps, [expected]);
        controller.compactListSpacing = true;
        expect(controller.blockGaps, isEmpty);
        controller.compactListSpacing = false;
        expect(controller.blockGaps, [expected]);
      },
    );
  }

  test('shared structures preserve IDs when reconciled after edits', () {
    final controller = MarkdownEditingController(text: 'One\n\nTwo\n\nThree');
    addTearDown(controller.dispose);
    final previous = ComposerBlockIndex.fromStructure(
      controller.blockStructure(),
    );
    controller.text = 'One\n\nTwo edited\n\nThree';
    final shared = ComposerBlockIndex.fromStructure(
      controller.blockStructure(forSpacing: true),
      previous: previous,
      revision: 9,
    );
    final standalone = ComposerBlockIndex.parse(
      controller.text,
      previous: previous,
      revision: 9,
    );
    expect(shared.revision, 9);
    expect(_blockState(shared), _blockState(standalone));
    expect(
      shared.blocks.map((block) => block.id),
      previous.blocks.map((block) => block.id),
    );
  });

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

const _target = ReplyComposerTarget(
  privateMessageTopic: false,
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);

final class _SwitchablePolicy implements ComposerSyntaxPolicy {
  _SwitchablePolicy(this.delegate);
  final ComposerSyntaxPolicy delegate;
  bool enabled = true;
  @override
  ComposerSyntaxKind get kind => delegate.kind;
  @override
  Object? get projectionState => enabled;
  @override
  TextInputFormatter? get inputFormatter => null;
  @override
  List<ComposerSyntaxProjection> parse(String source) =>
      enabled ? delegate.parse(source) : [];
}
