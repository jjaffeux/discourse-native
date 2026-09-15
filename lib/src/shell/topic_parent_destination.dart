import '../models/category_sidebar.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import 'shell_controller.dart';

/// The destination above the Ledger category, with a short visible label and
/// full context for hover and accessibility. The source route stays intact.
typedef TopicParentDestination = ({
  ContentRoute route,
  String label,
  String description,
});

TopicParentDestination topicParentDestination(
  ShellController shell, {
  required String? siteUrl,
  required TopicDetail? topic,
}) {
  final source = shell.contentStack.reversed
      .where((route) => !route.isTopic)
      .firstOrNull;
  final category = siteUrl == null || topic?.privateMessage == true
      ? null
      : shell.categoryFor(topic?.categoryId, siteUrl: siteUrl);
  final route =
      source ??
      (topic?.privateMessage == true
          ? ContentRoute.messages()
          : category == null
          ? ContentRoute.topicList(TopicListMode.latest)
          : ContentRoute.fromDestination(
              buildCategoryDestination(
                category,
                categoriesById: {
                  for (final item in shell.filterCategoriesFor(siteUrl!))
                    item.id: item,
                  category.id: category,
                },
              ),
            ));
  final sourceCategory = shell.categoryFor(route.categoryId, siteUrl: siteUrl);
  final categoryPath = sourceCategory == null
      ? null
      : shell.topicCategoryPathLabel(sourceCategory, siteUrl: siteUrl);
  final tags = route.tagNames.map((tag) => '#$tag').join(', ');
  final search = route.id == 'filter'
      ? shell.filterQueryFor(siteUrl ?? '')
      : route.topicListSearch;
  final mode =
      TopicListMode.fromRoute(route) ??
      (route.isTopicListFilter ? TopicListMode.latest : null);
  final modeLabel = switch (mode) {
    TopicListMode.latest => 'Latest',
    TopicListMode.newActivity => 'New',
    TopicListMode.newTopics => 'New topics',
    TopicListMode.newReplies => 'New replies',
    TopicListMode.unread => 'Unread',
    TopicListMode.unseen => 'Unseen',
    TopicListMode.popular => 'Trending',
    null => null,
    _ => 'Top · ${mode.topPeriod!.label}',
  };
  final label = switch (route) {
    _ when route.isMessages => 'Messages',
    _ when search.isNotEmpty || route.id == 'filter' => 'Search results',
    _ when tags.isNotEmpty => tags,
    _ when sourceCategory != null =>
      source != null && sourceCategory.id == topic?.categoryId
          ? 'Topics'
          : sourceCategory.name,
    _ => modeLabel ?? route.title,
  };
  final context = route.isMessages
      ? ['Messages', ?route.messageGroupName, route.messageListMode.label]
      : [
          ?categoryPath,
          if (tags.isNotEmpty) tags,
          ?modeLabel,
          if (search.isNotEmpty) 'Search: $search',
        ];
  final destination = context.isEmpty ? route.title : context.join(' · ');
  return (
    route: route,
    label: label,
    description: '${source == null ? 'Open' : 'Back to'} $destination',
  );
}
