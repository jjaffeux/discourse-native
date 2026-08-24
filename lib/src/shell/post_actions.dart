import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/post.dart';
import '../models/post_flag.dart';
import '../plugins/plugin_scope.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'anonymous_flag_dialog.dart';
import 'platform.dart';
import 'post_action.dart';
import 'post_flag_editor.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

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
  void _closeNow() {
    if (_portal.isShowing) _portal.hide();
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
          label: post.liked ? 'Remove like' : 'Like',
          tooltip: post.liked ? 'Remove your like' : 'Like this post',
          tint: post.liked ? Theme.of(context).discourse.love : null,
          onInvoke: () => _report(
            controller,
            controller.toggleLike(post, siteUrl: widget.siteUrl),
          ),
        ),
      if (_postShareUrl(controller) case final url?)
        PostAction(
          icon: DIcons.link,
          label: 'Copy link',
          tooltip: 'Copy a link to this post to clipboard',
          onInvoke: () => _copyLink(controller, url),
        ),
      if (controller.canReplyHere)
        PostAction(
          icon: DIcons.reply,
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
          label: 'Edit',
          tooltip: 'Edit this post',
          onInvoke: () => controller.openEdit(post),
        ),
      if (availableFlags.isNotEmpty)
        PostAction(
          icon: DIcons.flag,
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
          label: 'Report illegal content',
          tooltip: 'Report illegal content by email',
          onInvoke: () => showAnonymousIllegalContentDialog(
            context: context,
            email: anonymousReportEmail,
            topicTitle: topicTitle,
            postUrl: postUrl,
          ),
        ),
      if (post.postNumber == 1 &&
          controller.currentTopic?.canEdit != true &&
          controller.currentTopic?.canEditTags == true)
        PostAction(
          icon: DIcons.tag,
          label: 'Edit tags',
          tooltip: 'Edit topic tags',
          onInvoke: controller.openTagsEdit,
        ),
      if (post.canRecover)
        PostAction(
          icon: DIcons.arrowRotateLeft,
          label: 'Undelete',
          tooltip: 'Put this post back',
          onInvoke: () => _report(controller, controller.recoverPost(post)),
        )
      else if (post.canDelete)
        PostAction(
          icon: DIcons.trashCan,
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

    final slug = route?.slug?.isNotEmpty == true ? route!.slug! : 'topic';
    final postNumber = widget.post.postNumber > 1
        ? '/${widget.post.postNumber}'
        : '';
    final url = '${widget.siteUrl}/t/$slug/${topic.id}$postNumber';
    return instance!.config.shareUrl(url, username: instance.user?.username);
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
    _firstActionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellSelector<
      ({bool canReply, Object presentation, Object flagCatalog})
    >(
      select: (controller) => (
        canReply: controller.canReplyHere,
        presentation: controller.presentationTokenFor(widget.siteUrl),
        flagCatalog: controller.postFlagTypesFor(widget.siteUrl),
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
              firstActionFocus: _firstActionFocus,
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
    required this.onInvoke,
  });

  static const double _button = 44;
  static const double _padding = 2;

  /// The follower needs a width to align its right edge against, and it has to
  /// be known before the menu is laid out — so it is computed rather than
  /// measured.
  static double widthFor(List<PostAction> actions) =>
      actions.length * _button + _padding * 2;

  final List<PostAction> actions;
  final FocusNode firstActionFocus;
  final void Function(PostAction action) onInvoke;

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
              for (final (index, action) in actions.indexed)
                IconButton(
                  focusNode: index == 0 ? firstActionFocus : null,
                  onPressed: () => onInvoke(action),
                  icon: action.leading(context, size: 17),
                  tooltip: action.tooltip,
                  constraints: const BoxConstraints.tightFor(
                    width: _button,
                    height: _button,
                  ),
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
