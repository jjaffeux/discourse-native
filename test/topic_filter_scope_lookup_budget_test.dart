import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _categoryCount = 500;
const _idReadBudget = 12 * _categoryCount;

void main() {
  testWidgets('a category filter finds its category in one pass over the '
      'site categories', (tester) async {
    final categories = [
      for (var index = 1; index <= _categoryCount; index++)
        _CountingCategory(
          id: index,
          name: 'Category $index',
          color: '0088cc',
          slug: 'slug-$index',
          parentCategoryId: index > 100 ? index % 100 + 1 : null,
        ),
    ];
    final target = categories.last;
    final filterQuery = 'category:${_pathOf(categories, target)}';

    const user = DiscourseUser(id: 7, username: 'sam');
    final shell = ShellController(
      forumTabsEnabled: false,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(user: user, feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();

    _CountingCategory.idReads = 0;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TopicListFilterBar(
              siteUrl: 'https://meta.discourse.org',
              categories: categories,
              knownTags: const [],
              selectedCategoryId: null,
              selectedTagName: null,
              taggingEnabled: true,
              searchTags: (_) async => const <TopicFilterLookupValue>[],
              onCategorySelected: (_) {},
              onTagSelected: (_) {},
              filterQuery: filterQuery,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final reads = _CountingCategory.idReads;
    // ignore: avoid_print
    print('PERF_PROOF topic-filter-scope category_id_reads=$reads');

    expect(find.textContaining(target.name), findsOneWidget);
    expect(reads, lessThanOrEqualTo(_idReadBudget));
  });
}

String _pathOf(List<TopicCategory> categories, TopicCategory category) {
  final slugs = <String>[];
  TopicCategory? current = category;
  while (current != null) {
    slugs.insert(0, current.slug);
    final parent = current.parentCategoryId;
    current = parent == null ? null : categories[parent - 1];
  }
  return slugs.join(':');
}

final class _CountingCategory extends TopicCategory {
  const _CountingCategory({
    required super.id,
    required super.name,
    required super.color,
    required super.slug,
    super.parentCategoryId,
  });

  static int idReads = 0;

  @override
  int get id {
    idReads += 1;
    return super.id;
  }
}
