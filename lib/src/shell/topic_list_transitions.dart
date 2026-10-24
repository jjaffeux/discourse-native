import '../models/category_sidebar.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../theme/d_icons.dart';
import 'topic_filter_scope.dart';

sealed class TopicListCommand {
  const TopicListCommand();
}

final class SelectTopicListMode extends TopicListCommand {
  const SelectTopicListMode(this.mode, {this.keepTopicOpen = false});
  final TopicListMode mode;
  final bool keepTopicOpen;
}

final class SortTopicList extends TopicListCommand {
  const SortTopicList(this.column);
  final String column;
}

final class SelectTopicListCategory extends TopicListCommand {
  const SelectTopicListCategory(this.category, {this.keepTopicOpen = false});
  final TopicCategory? category;
  final bool keepTopicOpen;
}

final class SelectTopicListTags extends TopicListCommand {
  SelectTopicListTags(List<String> tags, {this.keepTopicOpen = false})
    : tags = List.unmodifiable(tags);
  final List<String> tags;
  final bool keepTopicOpen;
}

final class BrowseTopicListCategory extends TopicListCommand {
  const BrowseTopicListCategory(this.category, {this.keepTopicOpen = false});
  final TopicCategory? category;
  final bool keepTopicOpen;
}

final class SelectTopicListScope extends TopicListCommand {
  const SelectTopicListScope({this.category, this.tagName});
  final TopicCategory? category;
  final String? tagName;
}

final class ApplyTopicListFilterQuery extends TopicListCommand {
  const ApplyTopicListFilterQuery(this.query);
  final String query;
}

final class SubmitTopicListFilter extends TopicListCommand {
  const SubmitTopicListFilter(this.query);
  final String query;
}

enum TopicListPresentation { preserve, content, scopeList, sidebar }

/// A decision for one captured tab. Workspace and mobile history retain ownership
/// of publication; the plan holds no live shell, store, or account authority.
final class TopicListTransition {
  TopicListTransition.replace({
    required ForumTab tab,
    required this.route,
    required bool keepTopicOpen,
    required bool desktopPanelsEnabled,
    required bool mobileNavigationEnabled,
    this.presentation = TopicListPresentation.preserve,
  }) {
    final sourceIndex = tab.contentStack.lastIndexWhere(
      (item) => !item.isTopic,
    );
    final retainReader =
        !desktopPanelsEnabled &&
        keepTopicOpen &&
        tab.currentContent.isTopic &&
        sourceIndex >= 0 &&
        tab.contentStack[sourceIndex].isTopicList;
    final root = route.isMessages ? 'messages' : 'latest';
    replacement = tab.navigate(
      rootDestinationId: root,
      contentStack: retainReader
          ? [
              ...tab.contentStack.take(sourceIndex),
              route,
              ...tab.contentStack.skip(sourceIndex + 1),
            ]
          : [route],
    );
    mobileLocation = mobileNavigationEnabled && tab.currentContent.isTopicList
        ? ForumTabLocation(rootDestinationId: root, contentStack: [route])
        : null;
  }

  final ContentRoute route;
  final TopicListPresentation presentation;
  late final ForumTab replacement;
  late final ForumTabLocation? mobileLocation;
}

/// The route policy for a tab's source list, separate from its current reader
/// and the sidebar scope, which is absent at the mobile navigation root.
final class TopicListTransitions {
  TopicListTransitions({
    required this.tab,
    required this.source,
    required this.mode,
    required this.sidebarSource,
    required List<TopicCategory> categories,
    required this.sourceCategory,
    required List<String> resolvedTags,
    required this.signedIn,
    required this.unifiedNewEnabled,
    required this.desktopPanelsEnabled,
    required this.mobileNavigationEnabled,
  }) : categories = List.unmodifiable(categories),
       resolvedTags = List.unmodifiable(resolvedTags);

  final ForumTab tab;
  final ContentRoute? source;
  final TopicListMode? mode;
  final ContentRoute? sidebarSource;
  final List<TopicCategory> categories;
  final TopicCategory? sourceCategory;
  final List<String> resolvedTags;
  final bool signedIn;
  final bool unifiedNewEnabled;
  final bool desktopPanelsEnabled;
  final bool mobileNavigationEnabled;

  TopicListTransition? plan(TopicListCommand command) {
    final ContentRoute route;
    final bool keepTopicOpen;
    final TopicListPresentation presentation;
    switch (command) {
      case SelectTopicListMode():
        final next = command.mode;
        if (mode == null ||
            (!signedIn &&
                (next.isNew ||
                    next == TopicListMode.unread ||
                    next == TopicListMode.unseen)) ||
            (next.isSubset && !unifiedNewEnabled) ||
            (next == mode && source?.isAdvancedTopicFilter != true)) {
          return null;
        }
        route =
            _filterRoute(
              category: sourceCategory,
              tags: resolvedTags,
              mode: next,
            ).withTopicListQueryFrom(
              source?.isAdvancedTopicFilter == true ? null : source,
            );
        keepTopicOpen = command.keepTopicOpen;
        presentation = TopicListPresentation.content;
      case SortTopicList():
        if (source?.canSortTopicList != true ||
            !ContentRoute.topicListSortColumns.contains(command.column)) {
          return null;
        }
        final current = source!;
        final same = current.topicListOrder == command.column;
        route = current.withTopicListSort(
          same && current.topicListAscending ? null : command.column,
          ascending: same && !current.topicListAscending,
        );
        keepTopicOpen = true;
        presentation = TopicListPresentation.preserve;
      case SelectTopicListCategory():
        if (source?.isTopicListFilter != true) return null;
        route = _filterRoute(
          category: command.category,
          tags: resolvedTags,
        ).withTopicListQueryFrom(source);
        if (route.sameDestinationAs(source)) return null;
        keepTopicOpen = command.keepTopicOpen;
        presentation = TopicListPresentation.content;
      case SelectTopicListTags():
        if (source?.isTopicListFilter != true) return null;
        route = _filterRoute(
          category: sourceCategory,
          tags: command.tags,
        ).withTopicListQueryFrom(source);
        if (route.sameDestinationAs(source)) return null;
        keepTopicOpen = command.keepTopicOpen;
        presentation = TopicListPresentation.content;
      case BrowseTopicListCategory():
        route = _filterRoute(
          category: command.category,
          tags: const [],
        ).withTopicListQueryFrom(source);
        if (route.sameDestinationAs(source)) return null;
        keepTopicOpen = command.keepTopicOpen;
        presentation = TopicListPresentation.content;
      case SelectTopicListScope():
        route = _filterRoute(
          category: command.category,
          tags: [?command.tagName],
          mode: TopicListMode.fromRoute(sidebarSource) ?? TopicListMode.latest,
        ).withTopicListQueryFrom(sidebarSource);
        keepTopicOpen = false;
        presentation = TopicListPresentation.sidebar;
      case ApplyTopicListFilterQuery():
        final scope = parseTopicFilterScope(command.query, categories);
        route = scope.query.isEmpty
            ? _filterRoute(
                category: categories
                    .where((item) => item.id == scope.categoryId)
                    .firstOrNull,
                tags: scope.tags,
                mode:
                    TopicListMode.fromRoute(sidebarSource) ??
                    TopicListMode.latest,
              ).withTopicListQueryFrom(
                source?.isAdvancedTopicFilter == true ? null : source,
              )
            : ContentRoute.topicFilter(
                scope.query,
                categoryId: scope.categoryId,
                tags: scope.tags,
              );
        keepTopicOpen = tab.currentContent.isTopic;
        presentation = TopicListPresentation.scopeList;
      case SubmitTopicListFilter():
        route = command.query.trim().isEmpty
            ? ContentRoute.filteredTopicList(
                TopicListMode.latest,
                categoryId: source?.categoryId,
                tags: resolvedTags,
              )
            : ContentRoute.topicFilter(
                command.query,
                categoryId: source?.categoryId,
                tags: resolvedTags,
              );
        keepTopicOpen = tab.currentContent.isTopic;
        presentation = TopicListPresentation.preserve;
    }
    return TopicListTransition.replace(
      tab: tab,
      route: route,
      keepTopicOpen: keepTopicOpen,
      desktopPanelsEnabled: desktopPanelsEnabled,
      mobileNavigationEnabled: mobileNavigationEnabled,
      presentation: presentation,
    );
  }

  ContentRoute _filterRoute({
    required TopicCategory? category,
    required List<String> tags,
    TopicListMode? mode,
  }) {
    final selectedTags =
        tags
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selectedMode = mode ?? this.mode ?? TopicListMode.latest;
    // Core interprets numeric path segments as IDs. Query filters preserve names.
    if (selectedMode != TopicListMode.latest ||
        selectedTags.length > 1 ||
        (selectedTags.length == 1 &&
            RegExp(r'^\d+$').hasMatch(selectedTags.single))) {
      return ContentRoute.filteredTopicList(
        selectedMode,
        categoryId: category?.id,
        tags: selectedTags,
      );
    }
    final tagName = selectedTags.firstOrNull;
    if (category == null && tagName == null) {
      return ContentRoute.topicList(TopicListMode.latest);
    }
    final categoriesById = <int, TopicCategory>{
      for (final item in categories) item.id: item,
      ?category?.id: category!,
    };
    final destination = category == null
        ? null
        : buildCategoryDestination(category, categoriesById: categoriesById);
    if (tagName == null) return ContentRoute.fromDestination(destination!);
    final tagPath = Uri(pathSegments: ['tag', tagName]).toString();
    if (destination == null || category == null) {
      return ContentRoute(
        destination: FeedDestination(
          key: 'topic-list-filter-$tagPath',
          sourcePath: '/$tagPath.json',
        ),
        title: tagName,
        icon: DIcons.tag,
      );
    }
    final feedPath = destination.feedPath!;
    final categoryPath = feedPath.substring(
      0,
      feedPath.length - '.json'.length,
    );
    final combinedPath = Uri(
      pathSegments: ['tags', ...Uri.parse(categoryPath).pathSegments, tagName],
    ).toString();
    return ContentRoute(
      destination: FeedDestination(
        key: 'topic-list-filter-$combinedPath',
        sourcePath: '/$combinedPath.json',
      ),
      title: category.name,
      icon: destination.icon,
      color: destination.routeColor,
    );
  }

  /// A tag list's records outrank taxonomy snapshots after a rename. Unknown
  /// IDs retain the route's spelling until canonical data is available.
  static List<String> tagNames(
    ContentRoute? route, {
    required Iterable<Topic> listedTopics,
    required Iterable<SidebarTag> knownTags,
  }) {
    if (route == null) return const [];
    final id = route.tagId;
    if (id != null) {
      for (final topic in listedTopics) {
        for (final tag in topic.tags) {
          if (tag.id == id) return [tag.name];
        }
      }
      for (final tag in knownTags) {
        if (tag.id == id) return [tag.name];
      }
    }
    return route.tagNames;
  }
}
