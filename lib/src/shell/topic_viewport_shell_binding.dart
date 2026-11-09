import '../models/post.dart';
import '../models/site_config.dart';
import 'shell_controller.dart';
import 'topic_viewport_coordinator.dart';

/// Captures the shell operations one topic viewport generation needs, so the
/// coordinator itself never depends on the shell.
TopicViewportBinding topicViewportBindingFromShell(
  ShellController controller,
  TopicViewportSnapshot snapshot, {
  String? tabId,
}) {
  final tab = tabId == null
      ? controller.focusedTabContext
      : controller.tabContext(tabId);
  final ownerTabId = tab.tabId;
  final identity = (
    siteUrl: snapshot.siteUrl!,
    topicId: snapshot.topicId!,
    navigationRevision: snapshot.navigationRevision,
  );
  final lease = controller.lifecycle.capture(identity.siteUrl);
  return TopicViewportBinding(
    owner: controller,
    identity: identity,
    tabId: ownerTabId,
    session: lease.session,
    isCurrent: () {
      return lease.isCurrent &&
          tab.isCurrent &&
          controller.isTabVisible(ownerTabId) &&
          tab.siteUrl == identity.siteUrl &&
          tab.currentTopic?.id == identity.topicId &&
          tab.topicNavigationRevision == identity.navigationRevision;
    },
    currentSnapshot: () => topicViewportSnapshotFrom(controller, tab: tab),
    forumActive: () => controller.forumActive,
    forumActiveChanges: controller.changes,
    loadMore: tab.loadMorePosts,
    loadEarlier: tab.loadEarlierPosts,
    markRead:
        ({
          required String siteUrl,
          required int topicId,
          required int postNumber,
          required bool caughtUp,
          required List<int> readPostNumbers,
        }) {
          // Departing topics still credit their reader, but a queued dwell
          // callback must never acquire a replacement account's credentials.
          if (!lease.isCurrent) return Future<void>.value();
          return controller.markTopicRead(
            siteUrl,
            topicId,
            postNumber,
            caughtUp: caughtUp,
            readPostNumbers: readPostNumbers,
          );
        },
    saveAnchor: (topicId, postNumber, viewportOffset) =>
        controller.saveTopicScrollPost(
          topicId,
          postNumber,
          viewportOffset: viewportOffset,
          tabId: ownerTabId,
        ),
    flushAnchorPersist: controller.flushAnchorPersist,
    savedPostNumber: () =>
        controller.topicScrollPostNumber(identity.topicId, tabId: ownerTabId),
    savedPostOffset: () =>
        controller.topicScrollPostOffset(identity.topicId, tabId: ownerTabId),
    postNumberFor: (postId) =>
        controller.store.read<Post>(identity.siteUrl, postId)?.postNumber,
  );
}

/// Reads what one tab shows of its current topic, for the viewport to diff.
TopicViewportSnapshot topicViewportSnapshotFrom(
  ShellController controller, {
  ShellTabContext? tab,
}) {
  tab ??= controller.focusedTabContext;
  final postIds = tab.currentPostIds;
  final siteUrl = tab.isCurrent ? tab.siteUrl : null;
  final topicId = tab.currentContent?.topicId;
  final target = topicId == null
      ? null
      : controller.topicScrollPostNumber(topicId, tabId: tab.tabId);
  final hasEarlier = tab.currentTopicHasEarlier;
  final initialPostIndex = siteUrl != null && target != null
      ? tab.initialPostIndexFor(postIds, target, hasEarlier: hasEarlier)
      : null;

  return TopicViewportSnapshot(
    topicId: tab.currentTopic?.id,
    topic: tab.currentTopic,
    siteUrl: siteUrl,
    postIds: postIds,
    streamIds: tab.currentTopicStreamIds,
    loading: tab.currentTopicLoading,
    loadingMore: tab.loadingMorePosts,
    loadingEarlier: tab.loadingEarlierPosts,
    hasMore: tab.currentTopicHasMore,
    hasEarlier: hasEarlier,
    initialPostIndex: initialPostIndex,
    recommendations: tab.currentTopic?.recommendations,
    summary: tab.currentTopicSummary,
    summaryLoading: tab.currentTopicSummaryLoading,
    readTimeWordCount: controller.currentSiteConfig.readTimeWordCount,
    showTimeGapDays: siteUrl == null
        ? SiteConfig.defaultShowTimeGapDays
        : controller.siteConfigFor(siteUrl).showTimeGapDays,
    navigationRevision: tab.topicNavigationRevision,
  );
}
