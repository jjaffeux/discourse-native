import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/post_likers.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'hover_panel.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'user_card.dart';

/// The likes a post has collected, under the post itself.
///
/// Nothing is drawn until somebody has liked it: an unliked post is offered
/// the heart in its action menu instead, which is out of the way until the
/// post is pointed at. So this is a record of what happened rather than an
/// invitation, and it only exists once there is something to record.
///
/// Shaped for what comes next. The reactions plugin puts a row of emoji here
/// with a count beside them, a picker next to it, and the same panel of who
/// did what behind all of it — a like is that row with one entry in it, and
/// the entry is always a heart, so the emoji and the panel's header are the
/// two things left out.
class PostLikes extends StatefulWidget {
  const PostLikes({super.key, required this.siteUrl, required this.post});

  final String siteUrl;
  final Post post;

  @override
  State<PostLikes> createState() => _PostLikesState();
}

class _PostLikesState extends State<PostLikes> {
  static const double _panelWidth = 260;

  final GlobalKey<HoverPanelState> _panel = GlobalKey<HoverPanelState>();

  /// Every open, not only the first: this is a list of what other people have
  /// just done, and it is cheap to ask again. Whatever was fetched last time
  /// stays on screen while the answer is on its way.
  void _load() => unawaited(
    ShellScope.read(
      context,
    ).loadLikers(widget.post.id, siteUrl: widget.siteUrl),
  );

  /// Adds or removes this reader's like.
  Future<void> _toggle() async {
    final controller = ShellScope.read(context);
    final error = await controller.toggleLike(
      widget.post,
      siteUrl: widget.siteUrl,
    );
    if (!mounted || !identical(ShellScope.read(context), controller)) return;

    // Either way, and before the failure is reported: the names on screen are
    // one out if the like went through, and worth confirming if it did not.
    // The panel is only open because somebody asked to see it, which is what
    // makes another request worth spending.
    if (_panel.currentState?.isShowing ?? false) _load();

    if (error != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// The touch equivalent of the panel: the same names, in a sheet.
  Future<void> _openSheet() async {
    final controller = ShellScope.read(context);
    final count = widget.post.likeCount;
    unawaited(controller.loadLikers(widget.post.id, siteUrl: widget.siteUrl));

    await showShellSheet<void>(
      context: context,
      title: count == 1 ? '1 like' : '$count likes',
      builder: (sheetContext) =>
          _Likers(siteUrl: widget.siteUrl, post: widget.post),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    // Nobody has liked it, so there is nothing to say and no room taken up
    // saying it.
    if (post.likeCount <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          // Long press is the touch way in. The post underneath opens its own
          // action sheet on a long press, and this one wins the gesture arena
          // by being the nearer of the two.
          onLongPress: context.isTouch ? _openSheet : null,
          child: HoverPanel(
            key: _panel,
            maxWidth: _panelWidth,
            onOpen: _load,
            panelBuilder: (context) =>
                _LikersPanel(siteUrl: widget.siteUrl, post: post),
            child: _LikeCount(
              post: post,
              onTap: post.canToggleLike ? _toggle : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The heart and the number beside it.
///
/// Highlighted when the like is this reader's own, which is the only thing
/// distinguishing "one person liked this" from "you liked this" — the heart
/// itself is the same either way, because the count includes them.
class _LikeCount extends StatelessWidget {
  const _LikeCount({required this.post, required this.onTap});

  final Post post;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: onTap != null,
      label: post.likeCount == 1
          ? '1 like, from ${post.liked ? 'you' : 'someone else'}'
          : '${post.likeCount} likes',
      // The count is what it says; what pressing it does is a different
      // question, and the answer changes with the state of the post.
      onTapHint: onTap == null
          ? null
          : (post.liked ? 'remove your like' : 'like this post'),
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
            decoration: BoxDecoration(
              color: theme.shell.floating,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: post.liked
                    ? theme.colorScheme.primary
                    : theme.shell.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DIcon(DIcons.heart, size: 15, color: theme.discourse.love),
                const SizedBox(width: 5),
                Text(
                  '${post.likeCount}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: post.liked
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating version of the list, for a pointer.
class _LikersPanel extends StatelessWidget {
  const _LikersPanel({required this.siteUrl, required this.post});

  final String siteUrl;
  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.shell.floating,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.shell.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: _Likers(siteUrl: siteUrl, post: post),
        ),
      ),
    );
  }
}

/// Who liked the post, drawn the same way wherever it is being shown.
///
/// The panel and the sheet are the same list on two different surfaces, so
/// there is one answer to what a liker's row looks like rather than two that
/// have to be kept in step.
class _Likers extends StatelessWidget {
  const _Likers({required this.siteUrl, required this.post});

  /// Enough for a handful of names before the list starts scrolling, without
  /// the panel ever growing taller than the post it hangs off.
  static const double _maxHeight = 220;

  final String siteUrl;
  final Post post;

  @override
  Widget build(BuildContext context) => ShellSelector<_LikersSnapshot>(
    select: (controller) => (
      controller: controller,
      likers: controller.likers(post.id, siteUrl: siteUrl),
      error: controller.likersError(post.id, siteUrl: siteUrl),
    ),
    builder: (context, snapshot, _) => _LikersView(
      maxHeight: _maxHeight,
      siteUrl: siteUrl,
      post: post,
      snapshot: snapshot,
    ),
  );
}

typedef _LikersSnapshot = ({
  ShellController controller,
  PostLikers? likers,
  String? error,
});

class _LikersView extends StatefulWidget {
  const _LikersView({
    required this.maxHeight,
    required this.siteUrl,
    required this.post,
    required this.snapshot,
  });

  final double maxHeight;
  final String siteUrl;
  final Post post;
  final _LikersSnapshot snapshot;

  @override
  State<_LikersView> createState() => _LikersViewState();
}

class _LikersViewState extends State<_LikersView> {
  Object? _reloadToken;

  @override
  void didUpdateWidget(_LikersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot.controller, widget.snapshot.controller) ||
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.post.id != widget.post.id) {
      _reloadAfterLayout();
    }
  }

  void _reloadAfterLayout() {
    final token = Object();
    _reloadToken = token;
    final controller = widget.snapshot.controller;
    final siteUrl = widget.siteUrl;
    final postId = widget.post.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_reloadToken, token)) return;
      _reloadToken = null;
      if (!identical(widget.snapshot.controller, controller) ||
          widget.siteUrl != siteUrl ||
          widget.post.id != postId) {
        return;
      }
      unawaited(controller.loadLikers(postId, siteUrl: siteUrl));
    });
  }

  @override
  void dispose() {
    _reloadToken = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: widget.maxHeight),
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    final post = widget.post;
    final siteUrl = widget.siteUrl;
    final snapshot = widget.snapshot;
    final theme = Theme.of(context);
    final likers = snapshot.likers?.likers;

    if (likers == null) {
      final error = snapshot.error;
      if (error == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          error,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // More liked it than the route was asked for. Saying so is better than
    // quietly showing a list that does not add up to the count beside it.
    final hidden = post.likeCount - likers.length;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final liker in likers) _LikerRow(siteUrl: siteUrl, liker: liker),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text(
                hidden == 1 ? 'and 1 other' : 'and $hidden others',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LikerRow extends StatelessWidget {
  const _LikerRow({required this.siteUrl, required this.liker});

  final String siteUrl;
  final PostLiker liker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return UserCardTarget(
      username: liker.username,
      siteUrl: siteUrl,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 24,
                height: 24,
                child: AvatarImage(
                  url: liker.avatarUrl,
                  size: 24,
                  fallback: ColoredBox(
                    color: theme.shell.panel,
                    child: Center(
                      child: Text(
                        liker.username.isEmpty
                            ? '?'
                            : liker.username.characters.first.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                liker.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
