import 'dart:async';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/topic_filter_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _design = TopicCategory(
  id: 1,
  name: 'Design',
  slug: 'design',
  color: '123456',
);
const _bugs = TopicCategory(
  id: 2,
  name: 'Bugs',
  slug: 'bugs',
  parentCategoryId: 1,
  color: '123456',
);
const _features = TopicCategory(
  id: 3,
  name: 'Features',
  slug: 'features',
  parentCategoryId: 1,
  color: '123456',
);
const _remote = TopicCategory(
  id: 4,
  name: 'Remote Bugs',
  slug: 'remote-bugs',
  color: '123456',
);

TopicFilterSuggestions _engine(TopicFilterCategoryLookup lookup) =>
    TopicFilterSuggestions(
      options: const [
        TopicFilterOption(name: 'category:', type: 'category'),
        TopicFilterOption(name: 'tag:', type: 'tag'),
      ],
      categories: const [_design, _bugs, _features],
      categoryLookup: lookup,
      tags: (_) async => const [],
      tagGroups: (_) async => const [],
      users: (_) async => const [],
      groups: (_) async => const [],
    );

TopicFilterController _controller(TopicFilterCategoryLookup lookup) {
  final controller = TopicFilterController(
    initialQuery: 'category:bugs',
    submitQuery: (_) async {},
    engine: _engine(lookup),
  );
  addTearDown(controller.dispose);
  return controller;
}

List<String> _names(TopicFilterController controller) =>
    controller.suggestions.map((suggestion) => suggestion.name).toList();

void main() {
  test('latest local categories bypass a held obsolete lookup', () async {
    final old = Completer<List<TopicCategory>>();
    final current = Completer<List<TopicCategory>>();
    final terms = <String>[];
    final controller = _controller((term) {
      terms.add(term);
      return term == 'bugs' ? old.future : current.future;
    });
    final first = controller.refreshSuggestions();
    expect(_names(controller), ['category:design:bugs']);
    controller.text.text = 'category:features';
    controller.inputChanged(controller.text.text);
    expect(_names(controller), ['category:design:features']);
    final second = controller.refreshSuggestions();
    expect(await controller.ensureFreshSuggestions(), isTrue);
    expect(terms, ['bugs']);

    old.complete(const [_remote]);
    await first;
    expect(_names(controller), ['category:design:features']);
    expect(terms, ['bugs', 'features']);
    current.complete(const []);
    await second;
    expect(_names(controller), ['category:design:features']);
  });

  test('remote enrichment preserves the highlighted local category', () async {
    final remote = Completer<List<TopicCategory>>();
    final controller = _controller((_) => remote.future);
    controller.text.text = 'category:design';
    final pending = controller.refreshSuggestions();
    controller.select(2);
    expect(controller.selected?.category, _features);

    remote.complete(const [
      TopicCategory(
        id: 5,
        name: 'Design team',
        slug: 'design-team',
        color: '123456',
      ),
    ]);
    await pending;
    expect(_names(controller), [
      'category:design-team',
      'category:design',
      'category:design:bugs',
      'category:design:features',
    ]);
    expect(controller.selected?.category, _features);
  });

  test('category refresh preserves the highlight for the same input', () async {
    final remote = Completer<List<TopicCategory>>();
    final controller = _controller((_) => remote.future);
    controller.text.text = 'category:design';
    await controller.openSuggestions();
    controller.select(2);
    expect(controller.selected?.category?.id, 3);

    controller.updateEngine(_engine((_) => remote.future));
    expect(controller.selected?.category?.id, 3);
    remote.complete(const []);
    await pumpEventQueue();
    expect(controller.selected?.category?.id, 3);
  });

  test('a failed remote lookup keeps local category choices', () async {
    final remote = Completer<List<TopicCategory>>();
    final controller = _controller((_) => remote.future);
    final pending = controller.refreshSuggestions();
    expect(_names(controller), ['category:design:bugs']);
    remote.completeError(StateError('offline'));
    await pending;
    expect(_names(controller), ['category:design:bugs']);
    expect(await controller.ensureFreshSuggestions(), isTrue);
  });

  test('empty local matches wait for remotely discovered categories', () async {
    final remote = Completer<List<TopicCategory>>();
    final controller = _controller((_) => remote.future);
    await controller.openSuggestions();
    controller.text.text = 'category:remote';
    controller.inputChanged(controller.text.text);
    expect(controller.suggestions, isEmpty);
    var settled = false;
    final fresh = controller.ensureFreshSuggestions().then((value) {
      settled = true;
      return value;
    });
    await pumpEventQueue();
    expect(settled, isFalse);
    remote.complete(const [_remote]);
    expect(await fresh, isTrue);
    expect(_names(controller), ['category:remote-bugs']);
  });

  test(
    'engine replacement rejects the old category snapshot and response',
    () async {
      final remote = Completer<List<TopicCategory>>();
      final controller = _controller((_) => remote.future);
      await controller.openSuggestions();
      final old = controller.refreshSuggestions();
      controller.updateEngine(
        TopicFilterSuggestions(
          options: const [
            TopicFilterOption(name: 'category:', type: 'category'),
          ],
          categories: const [],
          categoryLookup: (_) async => const [],
          tags: (_) async => const [],
          tagGroups: (_) async => const [],
          users: (_) async => const [],
          groups: (_) async => const [],
        ),
      );
      expect(controller.suggestions, isEmpty);
      remote.complete(const [_remote]);
      await old;
      await pumpEventQueue();
      expect(controller.suggestions, isEmpty);
    },
  );

  test(
    'dismissal invalidates local category acceptance and late responses',
    () async {
      final remote = Completer<List<TopicCategory>>();
      final controller = _controller((_) => remote.future);
      final pending = controller.refreshSuggestions();
      expect(_names(controller), ['category:design:bugs']);
      controller.dismiss();
      remote.complete(const [_remote]);
      await pending;
      expect(controller.suggestions, isEmpty);
      expect(controller.menuRequested, isFalse);
    },
  );
}
