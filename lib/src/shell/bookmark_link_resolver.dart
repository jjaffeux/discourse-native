import 'package:discourse_native/l10n/strings.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/store.dart';
import '../models/bookmark.dart';
import '../models/discourse_instance.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../models/topic_link.dart';
import '../plugin_api/bookmark_host.dart';
import '../plugin_api/shell_extensions.dart';
import 'bookmark_transactions.dart';

final class BookmarkLinkResolver {
  BookmarkLinkResolver({
    required this.bookmarks,
    required this.store,
    required this.api,
    required this.credentials,
    required this.servingForum,
    required this.pluginResolvers,
  });

  final BookmarkTransactions bookmarks;
  final Store store;
  final TopicContentApi api;
  final SiteApiKeyReader credentials;
  final DiscourseInstance? Function(Uri) servingForum;
  final Iterable<PluginBookmarkLinkResolver> Function() pluginResolvers;

  /// Builds a topic-list action without waiting for the topic request.
  BookmarkLinkAction? cachedTopicBookmarkLink(String url) {
    final target = Uri.tryParse(url);
    if (target == null || !{'http', 'https'}.contains(target.scheme)) {
      return null;
    }
    final instance = servingForum(target);
    if (instance == null || !instance.isConnected || instance.user == null) {
      return null;
    }
    final siteUrl = instance.url;
    final link = TopicLink.parse(url, siteUrl: siteUrl);
    if (link == null || link.postNumber != null) return null;
    final account = bookmarks.forSite(siteUrl);
    final topic = store.read<Topic>(siteUrl, link.topicId);
    if (topic == null ||
        account.bookmarkWriteInFlight(
          topicId: link.topicId,
          targetType: BookmarkTargetType.topic,
          targetId: link.topicId,
        )) {
      return null;
    }
    final detail = store.read<TopicDetail>(siteUrl, link.topicId);
    if (topic.bookmarked && detail == null) {
      // The list's flag also includes post bookmarks, so it cannot tell us
      // whether this topic bookmark exists or supply its deletion ID.
      final resolution = resolveBookmarkLink(url);
      return BookmarkLinkAction(
        bookmark: null,
        resolution: resolution,
        invoke: () async {
          final action = await resolution;
          return action == null
              ? BookmarkWriteResult.refused(appL10n.bookmarkChangedRefreshMenu)
              : action.invoke();
        },
      );
    }
    return _bookmarkLinkAction(
      account: account,
      bookmarkCurrent: account.guard(link.topicId),
      topicId: link.topicId,
      type: BookmarkTargetType.topic,
      targetId: link.topicId,
      bookmark: topic.bookmarked ? detail?.topicBookmark : null,
    );
  }

  BookmarkLinkAction _bookmarkLinkAction({
    required BookmarkAccountSession account,
    required bool Function() bookmarkCurrent,
    required int topicId,
    required BookmarkTargetType type,
    required int targetId,
    required Bookmark? bookmark,
  }) {
    final siteUrl = account.siteUrl;
    return BookmarkLinkAction(
      bookmark: bookmark,
      invoke: () async {
        if (!bookmarkCurrent()) {
          return BookmarkWriteResult.refused(
            appL10n.bookmarkChangedRefreshMenu,
          );
        }
        final host = bookmarks.bookmarkTarget(type);
        return bookmark == null
            ? host.createBookmark(
                siteUrl: siteUrl,
                topicId: topicId,
                targetId: targetId,
              )
            : host.deleteBookmark(
                siteUrl: siteUrl,
                topicId: topicId,
                bookmark: bookmark,
              );
      },
    );
  }

  /// Resolves the clicked link without selecting its forum, tab, or topic.
  Future<BookmarkLinkAction?> resolveBookmarkLink(
    String url, {
    Bookmark? targetBookmark,
  }) async {
    final target = Uri.tryParse(url);
    if (target == null || !{'http', 'https'}.contains(target.scheme)) {
      return null;
    }
    final instance = servingForum(target);
    if (instance == null || !instance.isConnected || instance.user == null) {
      return null;
    }
    final siteUrl = instance.url;
    try {
      final account = bookmarks.forSite(siteUrl);
      final lease = account.lease;
      final link = TopicLink.parse(url, siteUrl: siteUrl);
      if (link == null) {
        for (final resolver in pluginResolvers()) {
          final action = await resolver.resolveBookmarkLink(siteUrl, url);
          if (!account.isCurrent) return null;
          if (action != null) return action;
        }
        return null;
      }
      if (targetBookmark?.bookmarkableType != null &&
          targetBookmark!.coreTargetType == null) {
        return null;
      }
      final bookmarkCurrent = account.guard(link.topicId);
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).keyCredentials(credentials);
      if (credential.apiKey == null || !lease.isCurrent) return null;
      final payload = await credential.run(
        () => api.topic(
          siteUrl: siteUrl,
          slug: link.slug,
          id: link.topicId,
          postNumber: link.postNumber,
          apiKey: credential.apiKey,
        ),
      );
      if (!lease.isCurrent ||
          payload.detail.id != link.topicId ||
          !bookmarkCurrent()) {
        return null;
      }
      // Core's user menu serializes neither the target type nor its id; the
      // topic's own bookmark list names which target holds this bookmark.
      final target =
          targetBookmark == null || targetBookmark.bookmarkableType != null
          ? targetBookmark
          : payload.detail.bookmarks
                .where((bookmark) => bookmark.id == targetBookmark.id)
                .firstOrNull;
      if (targetBookmark != null && target == null) return null;
      final topicTarget =
          target?.coreTargetType == BookmarkTargetType.topic ||
          (target == null && link.postNumber == null);
      final post = topicTarget
          ? null
          : payload.posts
                .where(
                  (post) => target?.bookmarkableId != null
                      ? post.id == target!.bookmarkableId
                      : post.postNumber == link.postNumber,
                )
                .firstOrNull;
      if (!topicTarget && (post == null || post.isDeleted || post.hidden)) {
        return null;
      }
      if (topicTarget &&
          target?.bookmarkableId != null &&
          target!.bookmarkableId != link.topicId) {
        return null;
      }
      final type = topicTarget
          ? BookmarkTargetType.topic
          : BookmarkTargetType.post;
      final targetId = topicTarget ? link.topicId : post!.id;
      final bookmark = topicTarget
          ? payload.detail.topicBookmark
          : post!.bookmark;
      if (account.bookmarkWriteInFlight(
        topicId: link.topicId,
        targetType: type,
        targetId: targetId,
      )) {
        return null;
      }
      return _bookmarkLinkAction(
        account: account,
        bookmarkCurrent: bookmarkCurrent,
        topicId: link.topicId,
        type: type,
        targetId: targetId,
        bookmark: bookmark,
      );
    } catch (error) {
      return null;
    }
  }
}
