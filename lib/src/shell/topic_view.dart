import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/post.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'post_actions.dart';
import 'post_likes.dart';
import 'user_card.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'small_action.dart';

/// A topic and its posts.
class TopicView extends StatelessWidget {
  const TopicView({super.key});

  /// Start fetching the next batch about a screen before the end.
  static const double _loadMoreThreshold = 900;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);
    final topic = controller.currentTopic;

    if (topic == null) {
      if (controller.currentTopicLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DIcon(
                DIcons.triangleExclamation,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                "Couldn't load this topic.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // The footer is a spinner, so it may only appear while actually loading —
    // otherwise it spins forever at the bottom of a topic with more to fetch.
    final showFooter = controller.loadingMorePosts;

    // Which posts are on screen, and in what order. The posts themselves are
    // in the store; each tile watches its own, so an edit or a deletion redraws
    // one tile rather than walking the whole stream.
    final postIds = controller.currentPostIds;
    final siteUrl = controller.currentInstance!.url;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < _loadMoreThreshold) {
          controller.loadMorePosts();
        }
        return false;
      },
      // A plain ListView estimates how tall the unbuilt posts are by averaging
      // the ones currently laid out. Post heights swing from a one-line small
      // action to a screenful of quotes and images, so that average — and with
      // it maxScrollExtent — lurches as you scroll, and the scrollbar thumb
      // jumps. SuperListView remembers each post's real height once measured,
      // so the estimate only ever tightens.
      //
      // Its extentPrecalculationPolicy would make the scrollbar exact rather
      // than merely stable, but precalculating builds every post — including
      // the last, whose builder asks for the next page. That would walk the
      // whole topic on open.
      child: SuperListView.separated(
        // Lazy, like the topic list: a 500-post topic builds only what shows.
        itemCount: postIds.length + (showFooter ? 1 : 0),
        separatorBuilder: (context, _) =>
            Divider(height: 1, color: theme.shell.divider),
        itemBuilder: (context, index) {
          if (index >= postIds.length) {
            return const _LoadingPostsRow();
          }

          // Building the last post means the end is in view. Scrolling alone
          // is not enough: twenty short posts may not fill the window, leaving
          // nothing to scroll and the rest never fetched.
          if (index == postIds.length - 1 && controller.currentTopicHasMore) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => controller.loadMorePosts(),
            );
          }
          return _StoredPost(siteUrl: siteUrl, postId: postIds[index]);
        },
      ),
    );
  }
}

/// Draws whichever post the store holds under [postId].
///
/// The indirection is the point: rewriting a post, deleting it, or fetching its
/// markdown for the composer all write one record, and only the tile watching
/// that record is rebuilt.
class _StoredPost extends StatelessWidget {
  const _StoredPost({required this.siteUrl, required this.postId});

  final String siteUrl;
  final int postId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Post?>(
      valueListenable: ShellScope.of(context).postRef(siteUrl, postId),
      builder: (context, post, _) {
        // Gone for good — deleted outright rather than soft-deleted — in the
        // frame before the stream that named it is rewritten without it.
        if (post == null) return const SizedBox.shrink();
        return post.isSmallAction
            ? SmallActionTile(post: post)
            : _PostTile(post: post);
      },
    );
  }
}

class _PostTile extends StatefulWidget {
  const _PostTile({required this.post});

  final Post post;

  @override
  State<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<_PostTile> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.post;

    // Transparent rather than [ShellColors.content] when idle, so the tile
    // takes whichever surface the column it is in happens to paint.
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: ColoredBox(
        color: switch ((post.isDeleted, _hovered)) {
          (true, final hovered) => theme.colorScheme.error.withValues(
            alpha: hovered ? 0.12 : 0.07,
          ),
          (false, true) => theme.shell.hover,
          (false, false) => Colors.transparent,
        },
        child: PostActions(
          post: post,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserCardTarget(
                      username: post.username,
                      child: ClipOval(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: AvatarImage(
                            url: post.avatarUrl,
                            size: 32,
                            fallback: ColoredBox(
                              color: theme.shell.floating,
                              child: Center(
                                child: Text(
                                  post.username.isEmpty
                                      ? '?'
                                      : post.username.characters.first
                                            .toUpperCase(),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: UserCardTarget(
                              username: post.username,
                              child: Text(
                                post.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (post.isStaff) ...[
                            const SizedBox(width: 6),
                            _Tag(
                              label: 'staff',
                              color: theme.colorScheme.primary,
                            ),
                          ] else if (post.userTitle case final title?) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                          // Only the people who can undo a deletion are shown
                          // one at all, so saying so is worth the room.
                          if (post.isDeleted) ...[
                            const SizedBox(width: 6),
                            _Tag(
                              label: 'deleted',
                              color: theme.colorScheme.error,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (post.createdAt case final createdAt?)
                      Text(
                        relativeTime(createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                CookedHtml(
                  html: post.cooked,
                  textStyle: theme.textTheme.bodyMedium,
                ),
                PostLikes(post: post),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _LoadingPostsRow extends StatelessWidget {
  const _LoadingPostsRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
