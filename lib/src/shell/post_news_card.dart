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
    final news = PostNewsTint(
      key: ValueKey('post-news-head-${post.id}'),
      tint: says ? tone.withValues(alpha: .08) : Colors.transparent,
      child: DReveal(
        visible: says,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, ruled ? ruledGap : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: ruledGap,
            children: [
              if (post.isWhisper)
                PostBanner(
                  key: ValueKey('post-whisper-${post.id}'),
                  mark: const PostBannerMark(icon: DIcons.farEyeSlash),
                  title: Text(context.l10n.whisperOnlyStaffCanSee),
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

/// The news's tint behind the card's head: full until [PostNewsCard.tintFade]
/// above the head's end, then fading to nothing at it.
class PostNewsTint extends StatelessWidget {
  const PostNewsTint({super.key, required this.tint, required this.child});

  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: tint),
    duration: DMotion.duration(context, DMotion.change),
    builder: (context, tint, child) => CustomPaint(
      painter: _NewsTintPainter(tint ?? Colors.transparent),
      child: child,
    ),
    child: child,
  );
}

class _NewsTintPainter extends CustomPainter {
  const _NewsTintPainter(this.tint);

  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    if (tint.a == 0 || size.isEmpty) return;
    final rect = Offset.zero & size;
    final solid = ((size.height - PostNewsCard.tintFade) / size.height).clamp(
      0.0,
      1.0,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, tint, tint.withValues(alpha: 0)],
          stops: [0, solid, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_NewsTintPainter oldDelegate) => oldDelegate.tint != tint;
}

/// The secondary text colour a post's news is said in.
Color postNewsSecondary(BuildContext context) {
  final tokens = DTokens.of(context);
  return Color.lerp(tokens.background, tokens.foreground, .62)!;
}

/// What has been said about or done to a post, said at its head as one of
/// its bare lines: a mark for who or what, a quiet line saying it, and what
/// can be done about it at the end; anything more under that.
///
/// Plugins supply these through `PostHeaderPlugin.postHeaders`, which places
/// them among the post's other news, with a [PostBannerMark] for the mark.
class PostBanner extends StatelessWidget {
  const PostBanner({
    super.key,
    required this.mark,
    required this.title,
    this.action,
    this.child,
  });

  /// The size of the room a mark stands in, a face's.
  static const double markExtent = 30;

  /// The narrowest a line keeps its action beside it, at unscaled text.
  static const double _rowWidth = 260;

  /// A [PostBannerMark], or a face or artwork in a [markExtent] square.
  final Widget mark;
  final Widget title;

  /// A quiet control at the line's end.
  final Widget? action;

  /// What is said under the line, at the post's own reading size.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.control,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: postNewsSecondary(context),
    );
    final action = this.action;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Too narrow for the line and its action side by side, the
              // action goes under the line rather than squeezing its words.
              final stacked =
                  action != null &&
                  constraints.maxWidth <
                      MediaQuery.textScalerOf(context).scale(_rowWidth);
              final line = Row(
                children: [
                  SizedBox.square(
                    dimension: markExtent,
                    child: Center(child: mark),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: DefaultTextStyle(style: style, child: title),
                  ),
                  if (action != null && !stacked) ...[
                    const SizedBox(width: 8),
                    action,
                  ],
                ],
              );
              if (!stacked) return line;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line,
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: markExtent + 9,
                      top: 4,
                    ),
                    child: action,
                  ),
                ],
              );
            },
          ),
          if (child case final child?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: DiscourseTypography.sm,
                  height: 1.65,
                  letterSpacing: 0,
                  color: DTokens.of(context).foreground,
                ),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

/// A banner's mark where it is a thing rather than someone: its icon alone,
/// standing where a face would, in the banner's tone softened toward the
/// secondary text colour. With no [tone] it is said in that colour itself.
class PostBannerMark extends StatelessWidget {
  const PostBannerMark({super.key, required this.icon, this.tone});

  final DIconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final secondary = postNewsSecondary(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: PostBanner.markExtent,
        child: Center(
          child: DIcon(
            icon,
            size: 15,
            color: tone == null ? secondary : Color.lerp(secondary, tone, .7),
          ),
        ),
      ),
    );
  }
}

/// A banner's quiet action at its line's end.
class PostBannerAction extends StatelessWidget {
  const PostBannerAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => DButton(
    size: DButtonSize.chip,
    variant: DButtonVariant.ghost,
    onPressed: onPressed,
    label: Text(label),
  );
}

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
        PostBanner(
          key: ValueKey('post-deleted-${post.id}'),
          mark: PostBannerMark(icon: DIcons.trashCan, tone: tokens.destructive),
          title: Text(context.l10n.postDeleted),
          action: post.canRecover
              ? PostBannerAction(
                  label: context.l10n.undelete,
                  onPressed: () =>
                      unawaited(report(() => shell.recoverPost(post))),
                )
              : null,
        ),
      if (post.hidden)
        PostBanner(
          key: ValueKey('post-hidden-${post.id}'),
          mark: PostBannerMark(
            icon: DIcons.farEyeSlash,
            tone: Theme.of(context).colorScheme.secondary,
          ),
          title: Text(switch (post.hiddenReasonId) {
            1 => context.l10n.postHiddenAfterFlags,
            2 => context.l10n.postHiddenAgainAfterFlags,
            3 => context.l10n.postHiddenNewUserSpam,
            4 => context.l10n.postHiddenByRegular,
            6 => context.l10n.postHiddenByLeader,
            _ => context.l10n.postHidden,
          }),
          action: shell.canUnhidePost(post)
              ? PostBannerAction(
                  label: context.l10n.unhidePost,
                  onPressed: () =>
                      unawaited(report(() => shell.unhidePost(post))),
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
        PostBanner(
          key: ValueKey('post-locked-${post.id}'),
          mark: const PostBannerMark(icon: DIcons.lock),
          title: Text(context.l10n.postLocked),
          action: shell.canLockPost(post)
              ? PostBannerAction(
                  label: context.l10n.unlockPost,
                  onPressed: () =>
                      unawaited(report(() => shell.setPostLocked(post, false))),
                )
              : null,
        ),
      if (bookmark != null)
        PostBanner(
          key: ValueKey('post-bookmarked-${post.id}'),
          mark: PostBannerMark(
            icon: DIcons.bookmark,
            tone: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            bookmark.name?.isNotEmpty == true
                ? '$bookmarkLabel · ${bookmark.name}'
                : bookmarkLabel,
          ),
          action: PostBannerAction(
            label: context.l10n.editBookmark,
            onPressed: () {
              if (!owner.isCurrent(
                context,
                siteUrl: siteUrl,
                postId: post.id,
              )) {
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
            },
          ),
        ),
    ];
  }
}
