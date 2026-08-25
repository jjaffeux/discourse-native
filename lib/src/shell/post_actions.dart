import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bookmark.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../plugins/plugin_scope.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anonymous_flag_dialog.dart';
import 'bookmark_ui.dart';
import 'hover_action_toolbar.dart';
import 'platform.dart';
import 'post_action.dart';
import 'post_flag_editor.dart';
import 'post_notice_editor.dart';
import 'post_permanent_delete.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'topic_change_owner.dart';
import 'topic_share.dart';

/// What can be done with one post, kept out of the way until it is wanted.
///
/// Nothing is drawn per post until the pointer is over it, which is what keeps
/// a long topic from reading as a column of buttons. On a touch screen there is
/// no pointer to hover, so the same actions arrive as a sheet when a
/// non-selectable part of the post is held. Holding the body belongs to text
/// selection and its quote toolbar.
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
  const PostActions({
    super.key,
    required this.siteUrl,
    required this.post,
    required this.child,
  });

  final String siteUrl;
  final Post post;
  final Widget child;

  @override
  State<PostActions> createState() => _PostActionsState();
}

class _PostActionsState extends State<PostActions> {
  static const double _inset = 8;

  final OverlayPortalController _portal = OverlayPortalController();
  final FocusNode _firstActionFocus = FocusNode(
    debugLabel: 'First post action',
  );

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

  /// A menu opened from the toolbar lives in a separate overlay. Keep the
  /// toolbar alive while the pointer travels between those two overlays.
  bool _overflowOpen = false;

  /// Whether the pointer is over the post or its compact toolbar. This lets an
  /// overflow menu closed with Escape leave the toolbar visible when the post
  /// is still hovered, and dismiss it when the pointer has moved elsewhere.
  bool _pointerInside = false;

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
    _pointerInside = true;
    _suppressed = false;
    _open();
  }

  void _pointerEntered() {
    _pointerInside = true;
    _open();
  }

  void _pointerExited() {
    _pointerInside = false;
    _closeNow();
  }

  /// Opens the same compact menu as hover and puts keyboard focus inside it.
  ///
  /// A post always has focusable content in its header, so the standard context
  /// menu keys can be handled by this ancestor without adding another tab stop
  /// for every post in a long topic.
  void _openFromKeyboard() {
    _suppressed = false;
    _open();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_portal.isShowing) return;
      _firstActionFocus.requestFocus();
    });
  }

  /// Instant, with nothing to wait out.
  ///
  /// The menu sits inside the post's own rectangle, and moving onto it exits
  /// the post and enters the menu within a single pointer update — the hide
  /// and the show land in the same frame, so there is no gap to bridge and no
  /// reason to make leaving feel slow.
  void _closeNow({bool force = false}) {
    if (_overflowOpen && !force) return;
    if (_portal.isShowing) _portal.hide();
  }

  void _overflowChanged(bool open) {
    _overflowOpen = open;
    if (!open && !_pointerInside) _closeNow();
  }

  /// What this reader may do with this post, in the order they are offered.
  ///
  /// Every core entry is gated on an answer the site gave — `can_edit`,
  /// `can_delete` and `can_recover` come from the guardian that already weighed
  /// ownership, staff, the edit window and the state of the topic. None of that
  /// is worked out here, because none of it can be.
  ///
  /// An optional site feature can add its own, and can take the place of Like
  /// where it has taken over what liking means. That is gated on the post's own
  /// payload, so it too is an answer the site gave.
  List<PostAction> _actions(BuildContext context, ShellController controller) {
    final post = widget.post;
    final topic = controller.currentTopic;
    final registry = PluginScope.maybeOf(context)?.registry ?? pluginRegistry;
    final contribution = registry.postMenu(context, widget.siteUrl, post);
    final instance = controller.currentInstance;
    final availableFlags =
        instance?.url == widget.siteUrl && instance?.isConnected == true
        ? controller.availablePostFlagTypes(widget.siteUrl, post)
        : const <PostFlagType>[];
    final config = controller.siteConfigFor(widget.siteUrl);
    final anonymousReportEmail =
        instance?.url == widget.siteUrl &&
            instance?.isConnected == false &&
            config.allowAllUsersToFlagIllegalContent &&
            !post.hidden &&
            !post.isDeleted
        ? config.anonymousFlagReportEmail
        : null;
    final postUrl = _postShareUrl(controller);
    final topicTitle = controller.currentTopic?.title;
    final currentUser = instance?.url == widget.siteUrl ? instance?.user : null;
    final ownsPost =
        currentUser != null &&
        ((post.userId != null && post.userId == currentUser.id) ||
            post.username.toLowerCase() == currentUser.username.toLowerCase());

    return [
      // First, and furthest from Delete: it is the one thing here people do
      // over and over while reading, and the only one they do without meaning
      // to change anything.
      ...contribution.entries,
      // Offered only while it would do something. A post already liked past
      // the site's undo window keeps its filled heart in the count underneath,
      // which says the same thing without a button that refuses.
      if (!contribution.replacesLike && post.canToggleLike)
        PostAction(
          icon: post.liked ? DIcons.heart : DIcons.farHeart,
          placement: PostActionPlacement.toolbar,
          label: post.liked ? 'Remove like' : 'Like',
          tooltip: post.liked ? 'Remove your like' : 'Like this post',
          tint: post.liked ? Theme.of(context).discourse.love : null,
          onInvoke: () => _report(
            controller,
            controller.toggleLike(post, siteUrl: widget.siteUrl),
          ),
        ),
      if (controller.currentInstance?.url == widget.siteUrl &&
          controller.currentInstance?.user != null &&
          topic != null)
        PostAction(
          icon: switch (post.bookmark?.reminderAt) {
            final DateTime _ => DIcons.discourseBookmarkClock,
            null when post.bookmark != null => DIcons.bookmark,
            null => DIcons.farBookmark,
          },
          label: post.bookmark == null ? 'Bookmark' : 'Edit bookmark',
          // Core promotes an existing bookmark out of its collapsed set.
          placement: post.bookmark == null
              ? PostActionPlacement.overflow
              : PostActionPlacement.toolbar,
          tooltip: post.bookmark == null
              ? 'Bookmark this post'
              : 'Edit this post bookmark',
          enabled: !controller.bookmarkWriteInFlight(
            siteUrl: widget.siteUrl,
            topicId: topic.id,
            targetType: BookmarkTargetType.post,
            targetId: post.id,
          ),
          onInvoke: () => unawaited(
            showPostBookmarkMenu(
              context: context,
              controller: controller,
              siteUrl: widget.siteUrl,
              topicId: topic.id,
              post: post,
            ),
          ),
        ),
      if (postUrl case final url?)
        PostAction(
          icon: DIcons.upRightFromSquare,
          // Share is not in Core's default post_menu (Copy link is), but keep
          // the native sharing surface available through More actions.
          placement: PostActionPlacement.overflow,
          label: 'Share',
          tooltip: 'Share this post',
          onInvoke: () => unawaited(
            showPostShareSheet(
              context: context,
              topicTitle: topicTitle!,
              url: url,
              postNumber: post.postNumber,
              onReplyAsNewTopic: topic?.canReplyAsNewTopic == true
                  ? () => controller.openReplyAsNewTopic(
                      topicContinuationMarkdown(
                        title: topic!.title,
                        url: _postCanonicalUrl(controller)!,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      if (postUrl case final url?)
        PostAction(
          icon: DIcons.link,
          placement: PostActionPlacement.toolbar,
          label: 'Copy link',
          tooltip: 'Copy a link to this post to clipboard',
          onInvoke: () => _copyLink(controller, url),
        ),
      if (controller.canReplyHere)
        PostAction(
          icon: DIcons.reply,
          placement: PostActionPlacement.trailing,
          label: 'Reply',
          tooltip: 'Reply to this post',
          onInvoke: () => controller.openReply(
            replyToPostNumber: post.postNumber,
            replyToUsername: post.username,
          ),
        ),
      if (post.canEdit)
        PostAction(
          icon: DIcons.pencil,
          // Core keeps an author's own Edit button visible and also promotes
          // Edit for wiki posts; staff editing somebody else's post expand it.
          placement: ownsPost || post.wiki
              ? PostActionPlacement.toolbar
              : PostActionPlacement.overflow,
          label: 'Edit',
          tooltip: 'Edit this post',
          onInvoke: () => controller.openEdit(post),
        ),
      if (post.canWiki)
        PostAction(
          icon: DIcons.farPenToSquare,
          placement: PostActionPlacement.overflow,
          label: post.wiki ? 'Remove wiki' : 'Make wiki',
          tooltip: post.wiki
              ? 'Return this to ordinary post editing'
              : 'Allow community members to edit this post',
          onInvoke: () =>
              _report(controller, controller.setPostWiki(post, !post.wiki)),
        ),
      if (controller.canLockPost(post))
        PostAction(
          icon: post.locked ? DIcons.unlock : DIcons.lock,
          placement: PostActionPlacement.overflow,
          label: post.locked ? 'Unlock post' : 'Lock post',
          tooltip: post.locked
              ? 'Allow this post to be edited again'
              : 'Prevent further edits to this post',
          onInvoke: () =>
              _report(controller, controller.setPostLocked(post, !post.locked)),
        ),
      if (availableFlags.isNotEmpty)
        PostAction(
          icon: DIcons.flag,
          placement: PostActionPlacement.overflow,
          label: 'Flag',
          tooltip: 'Privately flag this post for attention',
          onInvoke: () => showPostFlagEditor(
            context: context,
            siteUrl: widget.siteUrl,
            post: post,
            flagTypes: availableFlags,
          ),
        )
      else if (anonymousReportEmail != null &&
          postUrl != null &&
          topicTitle != null)
        PostAction(
          icon: DIcons.flag,
          placement: PostActionPlacement.overflow,
          label: 'Report illegal content',
          tooltip: 'Report illegal content by email',
          onInvoke: () => showAnonymousIllegalContentDialog(
            context: context,
            email: anonymousReportEmail,
            topicTitle: topicTitle,
            postUrl: postUrl,
          ),
        ),
      if (controller.canUnhidePost(post))
        PostAction(
          icon: DIcons.farEye,
          placement: PostActionPlacement.overflow,
          label: 'Unhide post',
          tooltip: 'Restore this hidden post',
          onInvoke: () => _report(controller, controller.unhidePost(post)),
        ),
      if (controller.canTogglePostType(post))
        PostAction(
          icon: DIcons.flag,
          placement: PostActionPlacement.overflow,
          label: post.isModeratorAction
              ? 'Revert to regular post'
              : 'Convert to moderator post',
          tooltip: post.isModeratorAction
              ? 'Remove the moderator styling from this post'
              : 'Mark this as an official moderator post',
          onInvoke: () => _report(controller, controller.togglePostType(post)),
        ),
      if (controller.canEditPostNotice(post))
        PostAction(
          icon: DIcons.user,
          placement: PostActionPlacement.overflow,
          label: post.notice == null ? 'Add post notice' : 'Change post notice',
          tooltip: post.notice == null
              ? 'Add a staff notice above this post'
              : 'Change or remove the staff notice',
          onInvoke: () => showPostNoticeEditor(
            context: context,
            controller: controller,
            post: post,
          ),
        ),
      if (controller.canChangeTopicPostOwner(post))
        PostAction(
          icon: DIcons.user,
          placement: PostActionPlacement.overflow,
          label: 'Change owner',
          tooltip: 'Assign this post to another account',
          onInvoke: () {
            final topic = controller.currentTopic;
            if (topic == null) return;
            unawaited(
              showTopicChangeOwner(
                context: context,
                controller: controller,
                siteUrl: widget.siteUrl,
                topicId: topic.id,
                selectedPosts: [post],
                usesTopicSelection: false,
              ),
            );
          },
        ),
      if (post.postNumber == 1 &&
          controller.currentTopic?.canEdit != true &&
          controller.currentTopic?.canEditTags == true)
        PostAction(
          icon: DIcons.tag,
          placement: PostActionPlacement.overflow,
          label: 'Edit tags',
          tooltip: 'Edit topic tags',
          onInvoke: controller.openTagsEdit,
        ),
      if (controller.canPermanentlyDeletePost(post))
        PostAction(
          icon: DIcons.trashCan,
          placement: PostActionPlacement.overflow,
          label: 'Permanently delete',
          tooltip: 'Permanently delete this post',
          destructive: true,
          onInvoke: () => unawaited(
            showPostPermanentDelete(
              context: context,
              controller: controller,
              post: post,
            ),
          ),
        ),
      if (post.canRecover)
        PostAction(
          icon: DIcons.arrowRotateLeft,
          placement: PostActionPlacement.overflow,
          label: 'Undelete',
          tooltip: 'Put this post back',
          onInvoke: () => _report(controller, controller.recoverPost(post)),
        )
      else if (post.canDelete)
        PostAction(
          icon: DIcons.trashCan,
          placement: PostActionPlacement.overflow,
          label: 'Delete',
          tooltip: 'Delete this post',
          destructive: true,
          // Unconfirmed: a deleted post stays in the stream with Undelete in
          // place of Delete, so the undo is one click away in the same menu —
          // which is a better answer to a misclick than a dialog on every
          // deliberate one.
          onInvoke: () => _report(controller, controller.deletePost(post)),
        ),
    ];
  }

  /// Core's canonical post URL. The opening post names the topic itself;
  /// numbered replies append their post number.
  String? _postShareUrl(ShellController controller) {
    final instance = controller.currentInstance;
    final topic = controller.currentTopic;
    final route = controller.currentContent;
    if (instance?.url != widget.siteUrl ||
        topic == null ||
        route?.topicId != topic.id) {
      return null;
    }

    return postShareUrl(
      siteUrl: widget.siteUrl,
      topicId: topic.id,
      postNumber: widget.post.postNumber,
      slug: route?.slug,
      config: instance!.config,
      username: instance.user?.username,
    );
  }

  String? _postCanonicalUrl(ShellController controller) {
    final topic = controller.currentTopic;
    final route = controller.currentContent;
    if (controller.currentInstance?.url != widget.siteUrl ||
        topic == null ||
        route?.topicId != topic.id) {
      return null;
    }
    return postCanonicalUrl(
      siteUrl: widget.siteUrl,
      topicId: topic.id,
      postNumber: widget.post.postNumber,
      slug: route?.slug,
    );
  }

  Future<void> _copyLink(ShellController controller, String url) async {
    String message;
    try {
      await Clipboard.setData(ClipboardData(text: url));
      message = 'Link copied!';
    } catch (_) {
      message = "Couldn't copy link.";
    }
    if (!mounted || !identical(ShellScope.maybeRead(context), controller)) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Surfaces a refusal. Success says nothing — the post itself changes, which
  /// is the only confirmation worth showing.
  Future<void> _report(ShellController controller, Future<String?> work) async {
    final error = await work;
    if (error == null ||
        !mounted ||
        !identical(ShellScope.maybeRead(context), controller)) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _openSheet(List<PostAction> actions) async {
    await showShellSheet<void>(
      context: context,
      title: widget.post.displayName,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            ListTile(
              leading: action.leading(
                sheetContext,
                size: 24,
                color:
                    action.tint ??
                    (action.destructive
                        ? Theme.of(sheetContext).colorScheme.error
                        : null),
              ),
              title: Text(action.label),
              contentPadding: EdgeInsets.zero,
              enabled: action.enabled,
              onTap: action.enabled
                  ? () {
                      // Closed first: the composer an action opens must not arrive
                      // under the sheet it was reached from.
                      Navigator.of(sheetContext).pop();
                      action.onInvoke();
                    }
                  : null,
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scroll?.removeListener(_onScroll);
    _anchor.dispose();
    _firstActionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellSelector<
      ({
        bool canReply,
        Object presentation,
        Object flagCatalog,
        bool bookmarkBusy,
        bool postBusy,
      })
    >(
      select: (controller) => (
        canReply: controller.canReplyHere,
        presentation: controller.presentationTokenFor(widget.siteUrl),
        flagCatalog: controller.postFlagTypesFor(widget.siteUrl),
        bookmarkBusy: switch (controller.currentTopic) {
          final topic? => controller.bookmarkWriteInFlight(
            siteUrl: widget.siteUrl,
            topicId: topic.id,
            targetType: BookmarkTargetType.post,
            targetId: widget.post.id,
          ),
          null => false,
        },
        postBusy: controller.postWriteInFlight(
          widget.post.id,
          siteUrl: widget.siteUrl,
        ),
      ),
      builder: (context, _, child) => _buildActions(context),
    );
  }

  Widget _buildActions(BuildContext context) {
    final actions = _actions(context, ShellScope.read(context));
    // Nothing this reader may do: no menu, and no hover target for one.
    if (actions.isEmpty) return widget.child;

    // Hover is wired unconditionally: a MouseRegion simply never fires without
    // a pointer, so a touch screen falls through to the long press below
    // without needing to ask what it is running on.
    final Widget hoverable = MouseRegion(
      onEnter: (_) => _pointerEntered(),
      onHover: (_) => _pointerMoved(),
      onExit: (_) => _pointerExited(),
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
            onEnter: (_) => _pointerEntered(),
            onHover: (_) => _pointerMoved(),
            onExit: (_) => _pointerExited(),
            child: _PostActionsMenu(
              actions: actions,
              firstActionFocus: _firstActionFocus,
              onOverflowChanged: _overflowChanged,
              onInvoke: (action) {
                _closeNow(force: true);
                action.onInvoke();
              },
            ),
          ),
        ),
        child: widget.child,
      ),
    );

    final keyboardReachable = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu):
            _openFromKeyboard,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true):
            _openFromKeyboard,
      },
      child: hoverable,
    );

    // Long press is gated, though: on a desktop, holding the mouse down should
    // not open a sheet.
    if (!context.isTouch) return keyboardReachable;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _openSheet(actions),
      child: keyboardReachable,
    );
  }
}

class _PostActionsMenu extends StatelessWidget {
  const _PostActionsMenu({
    required this.actions,
    required this.firstActionFocus,
    required this.onOverflowChanged,
    required this.onInvoke,
  });

  /// The follower needs a width to align its right edge against, and it has to
  /// be known before the menu is laid out — so it is computed rather than
  /// measured.
  static double widthFor(List<PostAction> actions) =>
      (actions.length -
          (_overflowActions(actions).length > 1
              ? _overflowActions(actions).length - 1
              : 0)) *
      HoverActionButton.width;

  static List<PostAction> _leadingActions(
    List<PostAction> actions, {
    required bool collapse,
  }) => actions
      .where(
        (action) =>
            action.placement != PostActionPlacement.trailing &&
            (!collapse || action.placement != PostActionPlacement.overflow),
      )
      .toList(growable: false);

  static List<PostAction> _trailingActions(List<PostAction> actions) => actions
      .where((action) => action.placement == PostActionPlacement.trailing)
      .toList(growable: false);

  static List<PostAction> _overflowActions(List<PostAction> actions) => actions
      .where((action) => action.placement == PostActionPlacement.overflow)
      .toList(growable: false);

  final List<PostAction> actions;
  final FocusNode firstActionFocus;
  final ValueChanged<bool> onOverflowChanged;
  final void Function(PostAction action) onInvoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overflowActions = _overflowActions(actions);
    // Core avoids an ellipsis which only hides one action: the indirection
    // would cost more space and effort than the action itself.
    final collapse = overflowActions.length > 1;
    final leadingActions = _leadingActions(actions, collapse: collapse);
    final trailingActions = _trailingActions(actions);

    return Align(
      alignment: Alignment.centerRight,
      child: HoverActionToolbar(
        children: [
          for (final (index, action) in leadingActions.indexed)
            HoverActionButton(
              focusNode: index == 0 ? firstActionFocus : null,
              onPressed: action.enabled ? () => onInvoke(action) : null,
              icon: action.leading(context, size: 16),
              tooltip: action.tooltip,
              color:
                  action.tint ??
                  (action.destructive
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant),
            ),
          if (collapse)
            MenuAnchor(
              alignmentOffset: const Offset(0, 4),
              onOpen: () => onOverflowChanged(true),
              onClose: () => onOverflowChanged(false),
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
                surfaceTintColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                maximumSize: const WidgetStatePropertyAll(Size(300, 440)),
              ),
              menuChildren: [
                for (final (index, action) in overflowActions.indexed) ...[
                  if (action.destructive &&
                      !overflowActions
                          .take(index)
                          .any((candidate) => candidate.destructive))
                    const Divider(height: 1),
                  MenuItemButton(
                    onPressed: action.enabled ? () => onInvoke(action) : null,
                    leadingIcon: action.leading(
                      context,
                      size: 16,
                      color:
                          action.tint ??
                          (action.destructive ? theme.colorScheme.error : null),
                    ),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.disabled)) {
                          return Colors.transparent;
                        }
                        if (states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused) ||
                            states.contains(WidgetState.pressed)) {
                          return theme.shell.hover;
                        }
                        return Colors.transparent;
                      }),
                      foregroundColor: action.destructive
                          ? WidgetStatePropertyAll(theme.colorScheme.error)
                          : null,
                      iconColor: action.destructive
                          ? WidgetStatePropertyAll(theme.colorScheme.error)
                          : null,
                    ),
                    child: Tooltip(
                      message: action.tooltip,
                      child: Text(action.label),
                    ),
                  ),
                ],
              ],
              builder: (context, menu, child) => HoverActionButton(
                key: const ValueKey('post-actions-overflow'),
                focusNode: leadingActions.isEmpty ? firstActionFocus : null,
                tooltip: 'More actions',
                onPressed: menu.isOpen ? menu.close : menu.open,
                icon: const DIcon(DIcons.ellipsis, size: 16),
              ),
            ),
          for (final (index, action) in trailingActions.indexed)
            HoverActionButton(
              focusNode: leadingActions.isEmpty && !collapse && index == 0
                  ? firstActionFocus
                  : null,
              onPressed: action.enabled ? () => onInvoke(action) : null,
              icon: action.leading(context, size: 16),
              tooltip: action.tooltip,
              color:
                  action.tint ??
                  (action.destructive
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
