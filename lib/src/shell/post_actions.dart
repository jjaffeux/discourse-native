import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

/// What can be done with one post, kept out of the way until it is wanted.
///
/// Nothing is drawn per post until the pointer is over it, which is what keeps
/// a long topic from reading as a column of buttons. On a touch screen there is
/// no pointer to hover, so the same actions arrive as a sheet on long press.
///
/// Built on [OverlayPortal] rather than a package: the overlay is tied to this
/// widget's lifetime, so it cannot outlive the row it belongs to when the list
/// recycles it.
///
/// The menu is positioned from the post's *visible* rectangle rather than being
/// pinned to its top edge. A long post is usually taller than the viewport, and
/// pinning would leave the menu above the fold — drawn over the header, or off
/// the window entirely.
class PostActions extends StatefulWidget {
  const PostActions({super.key, required this.post, required this.child});

  final Post post;
  final Widget child;

  @override
  State<PostActions> createState() => _PostActionsState();
}

class _PostActionsState extends State<PostActions> {
  static const double _inset = 8;

  final OverlayPortalController _portal = OverlayPortalController();

  /// Where the menu should sit, in global coordinates. Null once the post has
  /// scrolled out of sight.
  final ValueNotifier<Rect?> _anchor = ValueNotifier(null);

  ScrollPosition? _scroll;

  /// Set when the list moves under a stationary pointer.
  ///
  /// Rows slide beneath the cursor as you scroll, and each one entering it
  /// would pop its own menu open — so after a scroll a *closed* menu stays
  /// closed until the pointer is actually moved. An open one keeps following
  /// its post instead.
  bool _suppressed = false;

  bool get _isTouch => switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A menu pinned to a row that is moving reads as broken, and the follower
    // would drag it across the screen. Closing is the honest response.
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scroll)) return;
    _scroll?.removeListener(_onScroll);
    _scroll = position?..addListener(_onScroll);
  }

  /// Follows the post it belongs to, rather than being left behind by it.
  void _onScroll() {
    if (_portal.isShowing) {
      _updateAnchor();
    } else {
      _suppressed = true;
    }
  }

  /// The part of the post actually on screen, which is what the menu hangs off.
  void _updateAnchor() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) {
      _anchor.value = null;
      return;
    }
    final post = box.localToGlobal(Offset.zero) & box.size;

    final viewport =
        Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) {
      _anchor.value = post;
      return;
    }

    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    final visible = post.intersect(bounds);
    // Scrolled past entirely: there is nothing to point at any more.
    _anchor.value = visible.height <= 0 || visible.width <= 0 ? null : visible;
  }

  void _open() {
    if (_suppressed) return;
    _updateAnchor();
    if (_anchor.value == null) return;
    if (!_portal.isShowing) _portal.show();
  }

  /// A real pointer movement, as opposed to a row arriving under a still one.
  void _pointerMoved() {
    _suppressed = false;
    _open();
  }

  /// Instant, with nothing to wait out.
  ///
  /// The menu sits inside the post's own rectangle, and moving onto it exits
  /// the post and enters the menu within a single pointer update — the hide
  /// and the show land in the same frame, so there is no gap to bridge and no
  /// reason to make leaving feel slow.
  void _closeNow() {
    if (_portal.isShowing) _portal.hide();
  }

  /// What this reader may do with this post, in the order they are offered.
  ///
  /// Every entry is gated on an answer the site gave — `can_edit`, `can_delete`
  /// and `can_recover` come from the guardian that already weighed ownership,
  /// staff, the edit window and the state of the topic. None of it is worked
  /// out here, because none of it can be.
  List<_PostAction> _actions(ShellController controller) {
    final post = widget.post;
    return [
      // First, and furthest from Delete: it is the one thing here people do
      // over and over while reading, and the only one they do without meaning
      // to change anything.
      //
      // Offered only while it would do something. A post already liked past
      // the site's undo window keeps its filled heart in the count underneath,
      // which says the same thing without a button that refuses.
      if (post.canToggleLike)
        _PostAction(
          icon: post.liked ? DIcons.heart : DIcons.farHeart,
          label: post.liked ? 'Remove like' : 'Like',
          tooltip: post.liked ? 'Remove your like' : 'Like this post',
          tint: post.liked ? discourseLove : null,
          onInvoke: () => _report(controller.toggleLike(post)),
        ),
      if (controller.canReplyHere)
        _PostAction(
          icon: DIcons.reply,
          label: 'Reply',
          tooltip: 'Reply to this post',
          onInvoke: () => controller.openReply(
            replyToPostNumber: post.postNumber,
            replyToUsername: post.username,
          ),
        ),
      if (post.canEdit)
        _PostAction(
          icon: DIcons.pencil,
          label: 'Edit',
          tooltip: 'Edit this post',
          onInvoke: () => controller.openEdit(post),
        ),
      if (post.canRecover)
        _PostAction(
          icon: DIcons.arrowRotateLeft,
          label: 'Undelete',
          tooltip: 'Put this post back',
          onInvoke: () => _report(controller.recoverPost(post)),
        )
      else if (post.canDelete)
        _PostAction(
          icon: DIcons.trashCan,
          label: 'Delete',
          tooltip: 'Delete this post',
          destructive: true,
          // Unconfirmed: a deleted post stays in the stream with Undelete in
          // place of Delete, so the undo is one click away in the same menu —
          // which is a better answer to a misclick than a dialog on every
          // deliberate one.
          onInvoke: () => _report(controller.deletePost(post)),
        ),
    ];
  }

  /// Surfaces a refusal. Success says nothing — the post itself changes, which
  /// is the only confirmation worth showing.
  Future<void> _report(Future<String?> work) async {
    final error = await work;
    if (error == null || !mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _openSheet(List<_PostAction> actions) async {
    await showShellSheet<void>(
      context: context,
      title: widget.post.displayName,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            ListTile(
              leading: DIcon(
                action.icon,
                color:
                    action.tint ??
                    (action.destructive
                        ? Theme.of(sheetContext).colorScheme.error
                        : null),
              ),
              title: Text(action.label),
              contentPadding: EdgeInsets.zero,
              onTap: () {
                // Closed first: the composer an action opens must not arrive
                // under the sheet it was reached from.
                Navigator.of(sheetContext).pop();
                action.onInvoke();
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scroll?.removeListener(_onScroll);
    _anchor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(ShellScope.of(context));
    // Nothing this reader may do: no menu, and no hover target for one.
    if (actions.isEmpty) return widget.child;

    // Hover is wired unconditionally: a MouseRegion simply never fires without
    // a pointer, so a touch screen falls through to the long press below
    // without needing to ask what it is running on.
    final Widget hoverable = MouseRegion(
      onEnter: (_) => _open(),
      onHover: (_) => _pointerMoved(),
      onExit: (_) => _closeNow(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
          valueListenable: _anchor,
          builder: (context, anchor, child) {
            if (anchor == null) return const SizedBox.shrink();
            return Positioned(
              // Clamped to the visible rectangle, so a post taller than the
              // viewport keeps its menu on screen instead of above the fold.
              top: anchor.top + _inset,
              left: anchor.right - _PostActionsMenu.widthFor(actions) - _inset,
              child: child!,
            );
          },
          child: MouseRegion(
            onEnter: (_) => _open(),
            onHover: (_) => _pointerMoved(),
            onExit: (_) => _closeNow(),
            child: _PostActionsMenu(
              actions: actions,
              onInvoke: (action) {
                _closeNow();
                action.onInvoke();
              },
            ),
          ),
        ),
        child: widget.child,
      ),
    );

    // Long press is gated, though: on a desktop, holding the mouse down should
    // not open a sheet.
    if (!_isTouch) return hoverable;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _openSheet(actions),
      child: hoverable,
    );
  }
}

/// One thing that can be done with a post, in whichever surface is offering it.
///
/// The hover menu and the long-press sheet draw the same list rather than each
/// deciding for itself what a post allows — two answers to that question is one
/// too many.
@immutable
class _PostAction {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onInvoke,
    this.destructive = false,
    this.tint,
  });

  final DIconData icon;

  /// For the sheet, which has room for words.
  final String label;

  /// For the menu, which does not.
  final String tooltip;

  final bool destructive;

  /// Overrides the icon's color where the state of the post is worth saying in
  /// the icon itself — a heart already given, rather than one on offer.
  final Color? tint;

  final VoidCallback onInvoke;
}

class _PostActionsMenu extends StatelessWidget {
  const _PostActionsMenu({required this.actions, required this.onInvoke});

  static const double _button = 32;
  static const double _padding = 2;

  /// The follower needs a width to align its right edge against, and it has to
  /// be known before the menu is laid out — so it is computed rather than
  /// measured.
  static double widthFor(List<_PostAction> actions) =>
      actions.length * _button + _padding * 2;

  final List<_PostAction> actions;
  final void Function(_PostAction action) onInvoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: theme.shell.floating,
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _padding,
            vertical: _padding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                IconButton(
                  onPressed: () => onInvoke(action),
                  icon: DIcon(action.icon, size: 17),
                  tooltip: action.tooltip,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: _button,
                    height: _button,
                  ),
                  padding: EdgeInsets.zero,
                  color:
                      action.tint ??
                      (action.destructive
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
