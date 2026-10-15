import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/post.dart';
import '../theme/d_icons.dart';
import 'bookmark_ui.dart';
import 'post_action_owner.dart';
import 'shell_scope.dart';

/// The post remains the unit of reading; its status belongs to that same card.
class PostNewsCard extends StatelessWidget {
  const PostNewsCard({
    super.key,
    required this.siteUrl,
    required this.topicId,
    required this.post,
    required this.child,
    this.topicBookmark,
    this.headers = const [],
    this.decorationTone,
  });

  final String siteUrl;
  final int topicId;
  final Post post;
  final Widget child;
  final Bookmark? topicBookmark;
  final List<Widget> headers;
  final Color? decorationTone;

  static bool containsNews(Post post, {Bookmark? topicBookmark}) =>
      post.isWhisper ||
      post.isDeleted ||
      post.hidden ||
      post.notice != null ||
      post.locked ||
      post.bookmark != null ||
      (post.postNumber == 1 && topicBookmark != null);

  @override
  Widget build(BuildContext context) {
    final openingBookmark = post.postNumber == 1 ? topicBookmark : null;
    final bookmark = openingBookmark ?? post.bookmark;
    final hasNews =
        containsNews(post, topicBookmark: openingBookmark) ||
        headers.isNotEmpty ||
        decorationTone != null;
    final theme = Theme.of(context);
    final tone = post.isDeleted
        ? theme.colorScheme.error
        : post.hidden
        ? theme.colorScheme.secondary
        : post.notice != null
        ? theme.colorScheme.primary
        : decorationTone ??
              (post.locked || headers.isNotEmpty
                  ? theme.colorScheme.onSurface
                  : bookmark != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface);
    return ShellSelector<bool>(
      select: (shell) =>
          shell.isTopicPostHighlighted(siteUrl, topicId, post.postNumber),
      builder: (context, highlighted, _) => Padding(
        // The enclosing post highlight reserves its 1px outline. Leave one
        // more pixel clear between this card and the topic's outer outline.
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 18),
        child: !hasNews && !highlighted
            ? child
            : DCard(
                key: ValueKey('post-news-card-${post.id}'),
                duration: DMotion.duration(context, DMotion.change),
                spacing: 0,
                backgroundColor: !hasNews || post.isWhisper
                    ? Colors.transparent
                    : tone.withValues(alpha: .08),
                borderColor: highlighted
                    ? theme.colorScheme.primary.withValues(alpha: .65)
                    : hasNews
                    ? tone.withValues(alpha: .26)
                    : Colors.transparent,
                dashedBorder: post.isWhisper,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DReveal(
                      visible:
                          post.isDeleted ||
                          post.hidden ||
                          post.locked ||
                          bookmark != null ||
                          headers.isNotEmpty,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PostNewsHeader(
                            siteUrl: siteUrl,
                            topicId: topicId,
                            post: post,
                            topicBookmark: openingBookmark,
                          ),
                          ...headers,
                        ],
                      ),
                    ),
                    child,
                  ],
                ),
              ),
      ),
    );
  }
}

class PostNewsHeader extends StatelessWidget {
  const PostNewsHeader({
    super.key,
    required this.siteUrl,
    required this.topicId,
    required this.post,
    this.topicBookmark,
  });
  final String siteUrl;
  final int topicId;
  final Post post;
  final Bookmark? topicBookmark;

  @override
  Widget build(BuildContext context) {
    final bookmark = topicBookmark ?? post.bookmark;
    final bookmarkLabel = topicBookmark != null
        ? context.l10n.topicBookmarked
        : context.l10n.postBookmarked;
    final shell = ShellScope.read(context);
    final owner = PostActionOwner.capture(
      context,
      siteUrl: siteUrl,
      postId: post.id,
    );
    bool current() =>
        owner.isCurrent(context, siteUrl: siteUrl, postId: post.id);
    Future<void> report(Future<String?> Function() action) async {
      if (!current()) return;
      final error = await action();
      if (context.mounted && error != null && current()) {
        DToast.show(context, error, type: DToastType.error);
      }
    }

    Widget row(
      Widget icon,
      String label, {
      String? action,
      VoidCallback? onPressed,
    }) => DAlert(
      liveRegion: false,
      backgroundColor: Colors.transparent,
      borderColor: Colors.transparent,
      icon: icon,
      descriptionColor: DTokens.of(context).foreground,
      description: DAlertDescription(child: Text(label)),
      action: action != null && onPressed != null
          ? DAlertAction(
              child: DButton(
                size: DButtonSize.chip,
                variant: DButtonVariant.ghost,
                onPressed: onPressed,
                label: Text(action),
              ),
            )
          : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (post.isDeleted)
          row(
            const DIcon(DIcons.trashCan),
            context.l10n.postDeleted,
            action: context.l10n.undelete,
            onPressed: post.canRecover
                ? () => unawaited(report(() => shell.recoverPost(post)))
                : null,
          ),
        if (post.hidden)
          row(
            const DIcon(DIcons.farEyeSlash),
            switch (post.hiddenReasonId) {
              1 => context.l10n.postHiddenAfterFlags,
              2 => context.l10n.postHiddenAgainAfterFlags,
              3 => context.l10n.postHiddenNewUserSpam,
              4 => context.l10n.postHiddenByRegular,
              6 => context.l10n.postHiddenByLeader,
              _ => context.l10n.postHidden,
            },
            action: context.l10n.unhidePost,
            onPressed: shell.canUnhidePost(post)
                ? () => unawaited(report(() => shell.unhidePost(post)))
                : null,
          ),
        if (post.locked)
          row(
            const DIcon(DIcons.lock),
            context.l10n.postLocked,
            action: context.l10n.unlockPost,
            onPressed: shell.canLockPost(post)
                ? () =>
                      unawaited(report(() => shell.setPostLocked(post, false)))
                : null,
          ),
        if (bookmark != null)
          row(
            const DIcon(DIcons.bookmark),
            bookmark.name?.isNotEmpty == true
                ? '$bookmarkLabel · ${bookmark.name}'
                : bookmarkLabel,
            action: context.l10n.editBookmark,
            onPressed: () {
              if (!current()) return;
              unawaited(
                showBookmarkEditor(
                  context: context,
                  controller: shell.bookmarkTarget(
                    topicBookmark != null
                        ? BookmarkTargetType.topic
                        : BookmarkTargetType.post,
                  ),
                  siteUrl: siteUrl,
                  topicId: topicId,
                  bookmark: bookmark,
                  cooked: post.cooked,
                ),
              );
            },
          ),
      ],
    );
  }
}
