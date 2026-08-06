import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/post_likers.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'avatar_image.dart';
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
  const PostLikes({super.key, required this.post});

  final Post post;

  @override
  State<PostLikes> createState() => _PostLikesState();
}

class _PostLikesState extends State<PostLikes> {
  /// How long the pointer has to rest on the count before the panel opens.
  ///
  /// Long enough that crossing the pill on the way somewhere else does not
  /// open it, and does not spend a request finding out who liked a post
  /// nobody asked about. Discourse's reactions plugin waits the same 250ms.
  static const Duration _openDelay = Duration(milliseconds: 250);

  /// And how long it stays open after the pointer leaves.
  ///
  /// The panel is separated from the pill by a gap, so moving onto it means
  /// leaving both for a moment. This is what bridges that; entering the panel
  /// cancels it.
  static const Duration _closeDelay = Duration(milliseconds: 500);

  static const double _panelWidth = 260;

  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _pill = GlobalKey();

  /// Where the panel should sit, in the overlay's coordinates.
  final ValueNotifier<Rect?> _anchor = ValueNotifier(null);

  Timer? _opening;
  Timer? _closing;
  ScrollPosition? _scroll;

  bool get _isTouch => switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scroll)) return;
    _scroll?.removeListener(_onScroll);
    _scroll = position?..addListener(_onScroll);
  }

  /// A panel pinned to a row that is moving reads as broken. Discourse's own
  /// closes on scroll for the same reason.
  void _onScroll() {
    _cancelOpen();
    _close();
  }

  /// Cancelling and forgetting go together everywhere: a cancelled timer left
  /// in [_opening] reads as one still counting down, and [_scheduleOpen]
  /// declines to arm another while it is there.
  void _cancelOpen() {
    _opening?.cancel();
    _opening = null;
  }

  void _scheduleOpen() {
    _closing?.cancel();
    _closing = null;
    if (_portal.isShowing || _opening != null) return;
    _opening = Timer(_openDelay, _open);
  }

  void _open() {
    _opening = null;
    final anchor = _anchorRect();
    if (anchor == null) return;

    _anchor.value = anchor;
    if (!_portal.isShowing) _portal.show();
    // Every open, not only the first: this is a list of what other people have
    // just done, and it is cheap to ask again. Whatever was fetched last time
    // stays on screen while the answer is on its way.
    unawaited(ShellScope.of(context).loadLikers(widget.post.id));
  }

  void _scheduleClose() {
    _cancelOpen();
    if (!_portal.isShowing) return;
    _closing?.cancel();
    _closing = Timer(_closeDelay, _close);
  }

  /// Cancels the pending close as well as closing, since this is also reached
  /// from a scroll rather than only from the timer itself — an orphaned one
  /// would come back 500ms later and shut a panel reopened in the meantime.
  void _close() {
    _closing?.cancel();
    _closing = null;
    if (_portal.isShowing) _portal.hide();
  }

  /// The pill's rectangle, in the coordinates the overlay lays its children
  /// out in. Null before it has been laid out, or once it no longer is.
  Rect? _anchorRect() {
    final box = _pill.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize || !box.attached) {
      return null;
    }
    return Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
  }

  /// Adds or removes this reader's like.
  Future<void> _toggle() async {
    final controller = ShellScope.of(context);
    final error = await controller.toggleLike(widget.post);
    if (!mounted) return;

    // Either way, and before the failure is reported: the names on screen are
    // one out if the like went through, and worth confirming if it did not.
    // The panel is only open because somebody asked to see it, which is what
    // makes another request worth spending.
    if (_portal.isShowing) unawaited(controller.loadLikers(widget.post.id));

    if (error != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// The touch equivalent of the panel: the same names, in a sheet.
  Future<void> _openSheet() async {
    final controller = ShellScope.of(context);
    final count = widget.post.likeCount;
    unawaited(controller.loadLikers(widget.post.id));

    await showShellSheet<void>(
      context: context,
      title: count == 1 ? '1 like' : '$count likes',
      builder: (sheetContext) => _Likers(post: widget.post),
    );
  }

  @override
  void dispose() {
    _opening?.cancel();
    _closing?.cancel();
    _scroll?.removeListener(_onScroll);
    _anchor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    // Nobody has liked it, so there is nothing to say and no room taken up
    // saying it.
    if (post.likeCount <= 0) return const SizedBox.shrink();

    final pill = _LikeCount(
      key: _pill,
      post: post,
      onTap: post.canToggleLike ? _toggle : null,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          // Long press is the touch way in. The post underneath opens its own
          // action sheet on a long press, and this one wins the gesture arena
          // by being the nearer of the two.
          onLongPress: _isTouch ? _openSheet : null,
          child: MouseRegion(
            onEnter: (_) => _scheduleOpen(),
            onExit: (_) => _scheduleClose(),
            child: OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
                valueListenable: _anchor,
                builder: (context, anchor, child) => CustomSingleChildLayout(
                  delegate: AnchoredLayout(
                    anchor: anchor,
                    maxWidth: _panelWidth,
                  ),
                  child: child!,
                ),
                child: MouseRegion(
                  onEnter: (_) => _closing?.cancel(),
                  onExit: (_) => _scheduleClose(),
                  child: _LikersPanel(post: post),
                ),
              ),
              child: pill,
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
  const _LikeCount({super.key, required this.post, required this.onTap});

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
                const DIcon(DIcons.heart, size: 15, color: discourseLove),
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
  const _LikersPanel({required this.post});

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
          child: _Likers(post: post),
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
  const _Likers({required this.post});

  /// Enough for a handful of names before the list starts scrolling, without
  /// the panel ever growing taller than the post it hangs off.
  static const double _maxHeight = 220;

  final Post post;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        child: _body(context, controller),
      ),
    );
  }

  Widget _body(BuildContext context, ShellController controller) {
    final theme = Theme.of(context);
    final likers = controller.likers(post.id)?.likers;

    if (likers == null) {
      final error = controller.likersError(post.id);
      if (error == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
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
          for (final liker in likers) _LikerRow(liker: liker),
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
  const _LikerRow({required this.liker});

  final PostLiker liker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return UserCardTarget(
      username: liker.username,
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
