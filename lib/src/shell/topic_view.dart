import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/post.dart';
import '../theme/app_theme.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
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
              Icon(
                Icons.cloud_off,
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
        itemCount: topic.posts.length + (showFooter ? 1 : 0),
        separatorBuilder: (context, _) =>
            Divider(height: 1, color: theme.shell.divider),
        itemBuilder: (context, index) {
          if (index >= topic.posts.length) {
            return const _LoadingPostsRow();
          }

          // Building the last post means the end is in view. Scrolling alone
          // is not enough: twenty short posts may not fill the window, leaving
          // nothing to scroll and the rest never fetched.
          if (index == topic.posts.length - 1 && topic.hasMore) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => controller.loadMorePosts(),
            );
          }
          final post = topic.posts[index];
          return post.isSmallAction
              ? SmallActionTile(post: post)
              : _PostTile(post: post);
        },
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
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
                                : post.username.characters.first.toUpperCase(),
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
                      _Tag(label: 'staff', color: theme.colorScheme.primary),
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
          CookedHtml(html: post.cooked, textStyle: theme.textTheme.bodyMedium),
          if (ShellScope.of(context).canReplyHere) _PostActions(post: post),
        ],
      ),
    );
  }
}

/// What can be done with a single post.
///
/// Always drawn rather than revealed on hover: a pointer is not the only way
/// people use this, and a reply button nobody can reach is not a reply button.
class _PostActions extends StatelessWidget {
  const _PostActions({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: TextButton.icon(
          onPressed: () => controller.openReply(
            replyToPostNumber: post.postNumber,
            replyToUsername: post.username,
          ),
          icon: const Icon(Icons.reply, size: 15),
          label: const Text('Reply'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            textStyle: theme.textTheme.labelSmall,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
