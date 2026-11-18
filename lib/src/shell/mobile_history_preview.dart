import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import 'cooked_html.dart';
import 'directory_skeleton.dart';
import 'forum_theme_surfaces.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'topic_list_view.dart';
import 'topic_view.dart';

DHistoryPagePreview? buildMobileHistoryPreview(
  BuildContext context, {
  required ShellController shell,
  required PluginRegistry registry,
  required Object entry,
  required String? panelLabel,
}) {
  final visit = shell.mobileNavigation.adjacentVisit(entry);
  final siteUrl = shell.currentInstance?.url;
  if (visit == null || siteUrl == null) return null;
  final route = visit.location?.contentStack.last;
  final raised = route?.isTopic == true;
  final search = route?.isGlobalSearch == true;
  final overlaysHeader =
      search || raised && visit.previousRoute?.isGlobalSearch == true;
  final sheet =
      route != null &&
      (raised || search || registry.usesMobilePageSheet(context, route));
  final title = route?.title ?? panelLabel ?? context.l10n.loading;
  final content = switch (route?.destination) {
    TopicDestination(:final topicId) => _topicBody(
      shell,
      siteUrl,
      route!,
      topicId,
    ),
    FeedDestination() ||
    MessagesDestination() => _feedBody(shell, siteUrl, route!),
    BadgeDestination() => const DirectorySkeleton(
      kind: DirectorySkeletonKind.badges,
    ),
    GroupDestination() => const DirectorySkeleton(
      kind: DirectorySkeletonKind.groups,
    ),
    PageDestination(page: CorePage.bookmarks) => const DirectorySkeleton(
      kind: DirectorySkeletonKind.bookmarks,
    ),
    PageDestination(page: CorePage.categories) => const DirectorySkeleton(
      kind: DirectorySkeletonKind.categories,
    ),
    PageDestination(page: CorePage.tags) => const DirectorySkeleton(
      kind: DirectorySkeletonKind.tags,
    ),
    PageDestination(page: CorePage.users) => const DirectorySkeleton(
      kind: DirectorySkeletonKind.users,
    ),
    _ => Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (search)
            Padding(
              padding: const EdgeInsets.all(16),
              child: DText(title, variant: DTextVariant.h3),
            ),
          const Expanded(
            child: TopicListLoadingSkeleton(destination: 'latest'),
          ),
        ],
      ),
    ),
  };

  return DHistoryPagePreview(
    frameTop: overlaysHeader
        ? 0
        : raised
        ? mobileRaisedPageTop
        : DSheetDragScope.topBarExtentOf(context),
    child: DPageHeaderHost.exclude(
      child: Padding(
        padding: EdgeInsets.only(top: sheet ? 0 : mobilePageTopGap),
        child: ForumMobileSurface(
          sheet: raised
              ? ForumMobileSheet.raised
              : sheet
              ? ForumMobileSheet.page
              : ForumMobileSheet.none,
          child: sheet
              ? Builder(
                  builder: (context) => DSheetContent(
                    side: DSheetSide.bottom,
                    variant: DSheetVariant.page,
                    showCloseButton: false,
                    backgroundColor: ForumWindowBackground.panelColor(context),
                    children: [Expanded(child: content)],
                  ),
                )
              : content,
        ),
      ),
    ),
  );
}

Widget _feedBody(ShellController shell, String siteUrl, ContentRoute route) {
  final feed =
      route.isAdvancedTopicFilter &&
          shell.filterQueryFor(siteUrl) != route.topicFilterQuery
      ? null
      : shell.topicFeeds.feedFor(siteUrl, route.id);
  if (feed == null || !feed.loaded || feed.error != null) {
    return TopicListLoadingSkeleton(destination: route.id);
  }
  final firstRow = shell.feedScrollRow(route.id);
  final firstIndex = feed.topicRows.isEmpty
      ? firstRow
      : feed.topicRows.indexWhere((row) => row >= firstRow);
  if (firstIndex < 0) return TopicListLoadingSkeleton(destination: route.id);
  final topics = feed.topicIds
      .skip(firstIndex.clamp(0, feed.topicIds.length))
      .take(12)
      .map((id) => shell.store.read<Topic>(siteUrl, id))
      .whereType<Topic>()
      .toList(growable: false);
  if (topics.isEmpty) {
    if (feed.topicIds.isNotEmpty) {
      return TopicListLoadingSkeleton(destination: route.id);
    }
    return Builder(
      builder: (context) => Center(
        child: DEmpty(
          children: [
            DEmptyHeader(children: [DEmptyTitle(context.l10n.noTopicsFound)]),
          ],
        ),
      ),
    );
  }
  return ListView.separated(
    primary: false,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: topics.length,
    separatorBuilder: (_, _) => const DSeparator(),
    itemBuilder: (_, index) =>
        TopicListRow(topic: topics[index], siteUrl: siteUrl, onTap: () {}),
  );
}

Widget _topicBody(
  ShellController shell,
  String siteUrl,
  ContentRoute route,
  int topicId,
) {
  final detail = shell.store.read<TopicDetail>(siteUrl, topicId);
  final anchor = shell.activeTab?.anchors[route.id];
  final start =
      (anchor?.kind == 'topic' ? anchor?.itemId : null) ??
      route.postNumber ??
      1;
  final posts = <Post>[];
  if (detail != null && detail.deletedAt == null) {
    var reachedAnchor = false;
    for (final id in detail.stream) {
      final post = shell.store.read<Post>(siteUrl, id);
      if (post == null) continue;
      reachedAnchor |= post.postNumber == start;
      if (!reachedAnchor || post.hidden || post.isDeleted) continue;
      posts.add(post);
      if (posts.length == 4) break;
    }
  }
  if (posts.isEmpty) {
    return DPageSurface.scrollable(
      border: false,
      bodyBuilder: (_, header) => TopicLoadingSkeleton(header: header),
    );
  }
  return ListView(
    primary: false,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    children: [
      if (start == 1) DText(detail!.displayTitle, variant: DTextVariant.h3),
      for (final post in posts) ...[
        const SizedBox(height: 12),
        DText(post.username, variant: DTextVariant.small),
        CookedHtml(html: post.cooked, siteUrl: siteUrl, transient: true),
        const DSeparator(),
      ],
    ],
  );
}
