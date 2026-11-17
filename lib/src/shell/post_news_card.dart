import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/bookmark.dart';
import '../models/post.dart';
import '../models/post_mutation_outcome.dart';
import '../theme/app_theme.dart';
import 'bookmark_ui.dart';
import 'post_action_owner.dart';
import 'post_mutation_feedback.dart';
import 'shell_scope.dart';

/// The post remains the unit of reading; its status belongs to that same card.
///
/// What is said about the post (its banners) stands at the card's head as
/// bare lines, under a tint of the news's tone that fades out by the rule
/// where the post itself begins, so the post's own words keep the page's
/// ground. The card's edge holds the whole post together.
class PostNewsCard extends StatelessWidget {
  const PostNewsCard({
    super.key,
    required this.siteUrl,
    required this.topicId,
    required this.post,
    required this.child,
    this.topicBookmark,
    this.heading,
    this.contentExpanded,
    this.notice,
    this.headers = const [],
    this.decorationTone,
    this.margin = const EdgeInsets.symmetric(horizontal: 1, vertical: 18),
  });

  final String siteUrl;
  final int topicId;
  final Post post;
  final Widget child;
  final Bookmark? topicBookmark;
  final Widget? heading;
  final bool? contentExpanded;

  /// The forum's own word on the post (a staff notice or a greeting), said
  /// after the whisper line and before the moderation lines.
  final Widget? notice;

  /// Plugin banner lines, said between the hidden and locked lines.
  final List<Widget> headers;
  final Color? decorationTone;
  final EdgeInsetsGeometry margin;

  /// The fade from the news's tint to nothing, ending at the rule.
  static const double tintFade = 40;

  /// The room between the rule and the post's byline under it.
  static const double ruledGap = 12;

  static bool containsNews(Post post, {Bookmark? topicBookmark}) =>
      post.isWhisper ||
      post.isDeleted ||
      post.hidden ||
      post.notice != null ||
      post.locked ||
      post.bookmark != null ||
      (post.postNumber == 1 && topicBookmark != null);

  /// Whether the card says anything at its head, which rules the post off.
  static bool saysNews(
    Post post, {
    Bookmark? topicBookmark,
    bool notice = false,
    bool headers = false,
  }) =>
      post.isWhisper ||
      post.isDeleted ||
      post.hidden ||
      post.locked ||
      notice ||
      headers ||
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
    final says = saysNews(
      post,
      topicBookmark: openingBookmark,
      notice: notice != null,
      headers: headers.isNotEmpty,
    );
    final theme = Theme.of(context);
    final tone = post.isWhisper
        ? theme.colorScheme.onSurface
        : post.isDeleted
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
    Widget disclosure(Widget child) => contentExpanded == null
        ? child
        : DCollapsible(
            open: contentExpanded,
            child: DCollapsibleContent(duration: DMotion.change, child: child),
          );
    final ruled = heading == null;
    final news = DCardTint(
      key: ValueKey('post-news-head-${post.id}'),
      color: says ? tone.withValues(alpha: .08) : Colors.transparent,
      fade: tintFade,
      child: DReveal(
        visible: says,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, ruled ? ruledGap : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: ruledGap,
            children: [
              if (post.isWhisper)
                DAlert.postNotice(
                  key: ValueKey('post-whisper-${post.id}'),
                  icon: const DIcon(DIcons.farEyeSlash),
                  message: Text(context.l10n.whisperOnlyStaffCanSee),
                ),
              ?notice,
              ..._PostNewsLines(
                siteUrl: siteUrl,
                topicId: topicId,
                post: post,
                topicBookmark: openingBookmark,
              ).moderation(context),
              ...headers,
              ..._PostNewsLines(
                siteUrl: siteUrl,
                topicId: topicId,
                post: post,
                topicBookmark: openingBookmark,
              ).standing(context),
            ],
          ),
        ),
      ),
    );
    final rule = DReveal(
      visible: says,
      child: DSeparator(
        key: ValueKey('post-news-rule-${post.id}'),
        space: 1,
        indent: 16,
        endIndent: 16,
        color: theme.shell.divider,
      ),
    );
    return ShellSelector<bool>(
      select: (shell) =>
          shell.isTopicPostHighlighted(siteUrl, topicId, post.postNumber),
      builder: (context, highlighted, _) => Padding(
        padding: margin,
        child: !hasNews && !highlighted
            ? heading == null
                  ? disclosure(child)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [heading!, disclosure(child)],
                    )
            : DCard(
                key: ValueKey('post-news-card-${post.id}'),
                duration: DMotion.duration(context, DMotion.change),
                spacing: 0,
                backgroundColor: Colors.transparent,
                borderColor: highlighted
                    ? theme.colorScheme.primary.withValues(alpha: .65)
                    : hasNews
                    ? tone.withValues(alpha: post.isWhisper ? .3 : .26)
                    : Colors.transparent,
                dashedBorder: post.isWhisper,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?heading,
                    if (contentExpanded == null) ...[
                      news,
                      if (ruled) rule,
                      child,
                    ] else
                      disclosure(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [news, child],
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A news line's quiet action, at its end.
DAlertAction postNewsAction(String label, VoidCallback? onPressed) =>
    DAlertAction(
      child: DButton(
        size: DButtonSize.chip,
        variant: DButtonVariant.ghost,
        onPressed: onPressed,
        label: Text(label),
      ),
    );

/// The core moderation and standing lines of a post's news.
class _PostNewsLines {
  const _PostNewsLines({
    required this.siteUrl,
    required this.topicId,
    required this.post,
    this.topicBookmark,
  });
  final String siteUrl;
  final int topicId;
  final Post post;
  final Bookmark? topicBookmark;

  Future<void> Function(Future<PostMutationOutcome> Function()) _reporter(
    BuildContext context,
  ) {
    final owner = PostActionOwner.capture(
      context,
      siteUrl: siteUrl,
      postId: post.id,
    );
    bool current() =>
        owner.isCurrent(context, siteUrl: siteUrl, postId: post.id);
    return (action) async {
      if (!current()) return;
      final outcome = await action();
      if (context.mounted) {
        showPostMutationFeedback(context, outcome, isCurrent: current);
      }
    };
  }

  /// Deleted and hidden: said before any plugin's news.
  List<Widget> moderation(BuildContext context) {
    if (!post.isDeleted && !post.hidden) return const [];
    final shell = ShellScope.read(context);
    final report = _reporter(context);
    final tokens = DTokens.of(context);
    return [
      if (post.isDeleted)
        DAlert.postNotice(
          key: ValueKey('post-deleted-${post.id}'),
          icon: const DIcon(DIcons.trashCan),
          tone: tokens.destructive,
          message: Text(context.l10n.postDeleted),
          action: post.canRecover
              ? postNewsAction(
                  context.l10n.undelete,
                  () => unawaited(report(() => shell.recoverPost(post))),
                )
              : null,
        ),
      if (post.hidden)
        DAlert.postNotice(
          key: ValueKey('post-hidden-${post.id}'),
          icon: const DIcon(DIcons.farEyeSlash),
          tone: Theme.of(context).colorScheme.secondary,
          message: Text(switch (post.hiddenReasonId) {
            1 => context.l10n.postHiddenAfterFlags,
            2 => context.l10n.postHiddenAgainAfterFlags,
            3 => context.l10n.postHiddenNewUserSpam,
            4 => context.l10n.postHiddenByRegular,
            6 => context.l10n.postHiddenByLeader,
            _ => context.l10n.postHidden,
          }),
          action: shell.canUnhidePost(post)
              ? postNewsAction(
                  context.l10n.unhidePost,
                  () => unawaited(report(() => shell.unhidePost(post))),
                )
              : null,
        ),
    ];
  }

  /// Locked and bookmarked: said after any plugin's news.
  List<Widget> standing(BuildContext context) {
    final bookmark = topicBookmark ?? post.bookmark;
    if (!post.locked && bookmark == null) return const [];
    final shell = ShellScope.read(context);
    final report = _reporter(context);
    final owner = PostActionOwner.capture(
      context,
      siteUrl: siteUrl,
      postId: post.id,
    );
    final bookmarkLabel = topicBookmark != null
        ? context.l10n.topicBookmarked
        : context.l10n.postBookmarked;
    return [
      if (post.locked)
        DAlert.postNotice(
          key: ValueKey('post-locked-${post.id}'),
          icon: const DIcon(DIcons.lock),
          message: Text(context.l10n.postLocked),
          action: shell.canLockPost(post)
              ? postNewsAction(
                  context.l10n.unlockPost,
                  () =>
                      unawaited(report(() => shell.setPostLocked(post, false))),
                )
              : null,
        ),
      if (bookmark != null)
        DAlert.postNotice(
          key: ValueKey('post-bookmarked-${post.id}'),
          icon: const DIcon(DIcons.bookmark),
          tone: Theme.of(context).colorScheme.primary,
          message: Text(
            bookmark.name?.isNotEmpty == true
                ? '$bookmarkLabel · ${bookmark.name}'
                : bookmarkLabel,
          ),
          action: postNewsAction(context.l10n.editBookmark, () {
            if (!owner.isCurrent(context, siteUrl: siteUrl, postId: post.id)) {
              return;
            }
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
          }),
        ),
    ];
  }
}
