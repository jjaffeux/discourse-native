import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/topic_list_transitions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final panels in [false, true]) {
    for (final reading in [false, true]) {
      test(
        'sort preserves the source search with panels=$panels reader=$reading',
        () {
          final source = ContentRoute.topicList(
            TopicListMode.topWeekly,
          ).withTopicListSearch('café');
          final reader = ContentRoute.topic(
            topicId: 7,
            slug: 'seven',
            title: 'Seven',
          );
          final tab = ForumTab(
            id: 'source',
            rootDestinationId: 'original-root',
            contentStack: [source, if (reading) reader],
          );
          final plan = _facts(
            tab,
            source,
            panels: panels,
          ).plan(const SortTopicList('posts'))!;
          expect(plan.route.topicListSearch, 'café');
          expect(plan.route.topicListOrder, 'posts');
          expect(TopicListMode.fromRoute(plan.route), TopicListMode.topWeekly);
          expect(plan.replacement.rootDestinationId, 'latest');
          expect(plan.replacement.currentContent.isTopic, reading && !panels);
          expect(plan.replacement.contentStack.first.topicListOrder, 'posts');
          expect(
            plan.mobileLocation?.contentStack.single.topicListOrder,
            reading ? null : 'posts',
          );
          expect(plan.replacement.backHistory.last, tab.location);
          expect(plan.presentation, TopicListPresentation.preserve);
        },
      );
    }
  }

  test('a mode change leaves advanced server clauses behind', () {
    final source = ContentRoute.topicFilter(
      'status:open',
      categoryId: 42,
      tags: const ['design'],
    );
    final tab = ForumTab(
      id: 'source',
      rootDestinationId: 'latest',
      contentStack: [source],
    );
    final plan = _facts(
      tab,
      source,
    ).plan(const SelectTopicListMode(TopicListMode.latest))!;
    expect(plan.route.isAdvancedTopicFilter, isFalse);
    expect(plan.route.topicFilterQuery, isEmpty);
    expect(plan.route.tagNames, ['design']);
    expect(plan.presentation, TopicListPresentation.content);
  });

  test('mobile root scope chooses Latest independently of the source mode', () {
    final source = ContentRoute.topicList(TopicListMode.topWeekly);
    final tab = ForumTab(
      id: 'source',
      rootDestinationId: 'latest',
      contentStack: [source],
    );
    final scoped = _facts(
      tab,
      source,
      sidebarSource: source,
    ).plan(const ApplyTopicListFilterQuery(''))!;
    final root = _facts(tab, source).plan(const ApplyTopicListFilterQuery(''))!;
    expect(TopicListMode.fromRoute(scoped.route), TopicListMode.topWeekly);
    expect(TopicListMode.fromRoute(root.route), TopicListMode.latest);
    expect(root.presentation, TopicListPresentation.scopeList);
  });
}

TopicListTransitions _facts(
  ForumTab tab,
  ContentRoute source, {
  bool panels = false,
  ContentRoute? sidebarSource,
}) => TopicListTransitions(
  tab: tab,
  source: source,
  mode: TopicListMode.fromRoute(source) ?? TopicListMode.latest,
  sidebarSource: sidebarSource,
  categories: const [],
  canonicalCategories: const {},
  resolvedTags: source.tagNames,
  signedIn: true,
  unifiedNewEnabled: true,
  desktopPanelsEnabled: panels,
  mobileNavigationEnabled: true,
);
