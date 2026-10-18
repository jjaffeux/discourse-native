import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bookmark.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'anonymous_flag_dialog.dart';
import 'bookmark_ui.dart';
import 'hover_action_toolbar.dart';
import 'platform.dart';
import 'post_action.dart';
import 'post_action_owner.dart';
import 'post_flag_editor.dart';
import 'post_notice_editor.dart';
import 'post_permanent_delete.dart';
import 'post_quote.dart';
import 'post_revision_history.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_change_owner.dart';
import 'topic_share.dart';

class PostActions extends StatefulWidget {
  const PostActions({
    super.key,
    required this.siteUrl,
    required this.post,
    required this.child,
    this.persistent = false,
  });

  final String siteUrl;
  final Post post;
  final Widget child;
  final bool persistent;

  /// Keeps body gestures separate from the post's action controls.
  static Widget reactOnDoubleTap(BuildContext context, Widget child) {
    final onReact = context
        .dependOnInheritedWidgetOfExactType<_PostQuickReactionScope>()
        ?.onReact;
    return onReact == null
        ? child
        : GestureDetector(onDoubleTap: onReact, child: child);
  }

  @override
  State<PostActions> createState() => _PostActionsState();
}

enum _PostActionsHoverTarget { post, toolbar }

class _PostActionsState extends State<PostActions> {
  static const double _inset = 8;

  final DDropdownMenuController _menu = DDropdownMenuController();
  final OverlayPortalController _portal = OverlayPortalController();
  final FocusNode _firstActionFocus = FocusNode(
    debugLabel: 'First post action',
  );

  final ValueNotifier<Rect?> _anchor = ValueNotifier(null);

  ScrollPosition? _scroll;

  bool _suppressed = false;

  bool _overflowOpen = false;

  final Set<_PostActionsHoverTarget> _hoveredTargets = {};

  bool get _pointerInside => _hoveredTargets.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scroll)) return;
    _detachScroll();
    _scroll = position;
    position?.addListener(_hideForScroll);
    position?.isScrollingNotifier.addListener(_onScrollingChanged);
    if (position?.isScrollingNotifier.value == true) _hideForScroll();
  }

  void _detachScroll() {
    _scroll?.removeListener(_hideForScroll);
    _scroll?.isScrollingNotifier.removeListener(_onScrollingChanged);
  }

  void _onScrollingChanged() {
    if (_scroll?.isScrollingNotifier.value == true) _hideForScroll();
  }

  void _hideForScroll() {
    if (_menu.isOpen) _menu.close();
    _suppressed = true;
    _closeNow(force: true);
  }

  void _updateAnchor() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) {
      _anchor.value = null;
      return;
    }
    final post = box.localToGlobal(Offset.zero) & box.size;
    if (!_hasFiniteEdges(post)) {
      _anchor.value = null;
      return;
    }

    final viewport =
        Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize || !viewport.attached) {
      _anchor.value = post;
      return;
    }

    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    if (!_hasFiniteEdges(bounds)) {
      _anchor.value = null;
      return;
    }
    final visible = post.intersect(bounds);
    _anchor.value = visible.height <= 0 || visible.width <= 0 ? null : visible;
  }

  void _open() {
    if (_suppressed) return;
    _updateAnchor();
    if (_anchor.value == null) return;
    if (!_portal.isShowing) _portal.show();
  }

  void _pointerMoved(_PostActionsHoverTarget target) {
    _hoveredTargets.add(target);
    if (_scroll?.isScrollingNotifier.value == true) return;
    _suppressed = false;
    _open();
  }

  void _pointerEntered(_PostActionsHoverTarget target) {
    _hoveredTargets.add(target);
    // MouseTracker also synthesizes enter when layout moves a new row beneath
    // a stationary device. Opening an OverlayPortal from that post-frame hit
    // test can race with the row being recycled again. A genuine pointer move
    // immediately delivers onHover, which opens through _pointerMoved instead.
  }

  void _pointerExited(_PostActionsHoverTarget target) {
    _hoveredTargets.remove(target);
    // The toolbar is an overlaid mouse region. Its enter can arrive before or
    // after the post's exit, so wait until this pointer update has dispatched
    // both callbacks before deciding that the pointer truly left.
    scheduleMicrotask(() {
      if (!mounted || _pointerInside) return;
      _closeNow();
    });
  }

  void _openFromKeyboard() {
    if (widget.persistent) {
      _menu.open();
      return;
    }
    _suppressed = false;
    _open();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_portal.isShowing) return;
      _firstActionFocus.requestFocus();
    });
  }

  void _closeNow({bool force = false}) {
    if (_overflowOpen && !force) return;
    if (_portal.isShowing) {
      _portal.hide();
      // Removing an overlay does not promise a matching exit callback.
      _hoveredTargets.remove(_PostActionsHoverTarget.toolbar);
    }
  }

  void _overflowChanged(bool open) {
    _overflowOpen = open;
    if (!open && !_pointerInside) _closeNow();
  }

  void _invokeFrom(
    PostAction action,
    BuildContext anchorContext,
    PostActionOwner owner,
  ) {
    if (!owner.isCurrent(
      context,
      siteUrl: widget.siteUrl,
      postId: widget.post.id,
    )) {
      return;
    }
    final anchored = action.onInvokeAnchored;
    final anchor = anchored == null
        ? null
        : anchorRect(
            anchor: anchorContext.findRenderObject() as RenderBox?,
            overlay:
                Navigator.of(
                      anchorContext,
                      rootNavigator: true,
                    ).overlay?.context.findRenderObject()
                    as RenderBox?,
          );
    _closeNow(force: true);
    if (anchored != null && anchor != null) {
      anchored(anchor);
    } else {
      action.onInvoke();
    }
  }

  ({
    List<PostAction> actions,
    Listenable? rebuildOn,
    Future<String?> Function()? quickReaction,
  })
  _actions(BuildContext context, ShellController controller) {
    final post = widget.post;
    final tab = ForumTabScope.tabOf(context);
    final topic = tab.currentTopic;
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    if (post.isSmallAction || registry.isSmallAction(post)) {
      return (
        actions: [
          if (post.canDelete)
            PostAction(
              icon: DIcons.trashCan,
              placement: PostActionPlacement.overflow,
              group: PostActionGroup.report,
              label: appL10n.delete,
              tooltip: appL10n.deleteThisTopicAction,
              destructive: true,
              onInvoke: () => _report(controller, controller.deletePost(post)),
            ),
        ],
        rebuildOn: null,
        quickReaction: null,
      );
    }
    final instance = controller.currentInstance;
    final contribution = registry.postMenu(
      context,
      widget.siteUrl,
      post,
      topic: topic,
      currentUser: instance?.url == widget.siteUrl ? instance?.user : null,
    );
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
    final canonicalUrl = _postCanonicalUrl(controller);
    final topicTitle = topic?.title;

    return (
      actions: [
        if (!contribution.replacesLike && post.canToggleLike)
          PostAction(
            icon: post.liked ? DIcons.heart : DIcons.farHeart,
            showInMenu: false,
            placement: PostActionPlacement.toolbar,
            label: post.liked ? appL10n.removeLike : appL10n.like,
            tooltip: post.liked ? appL10n.removeYourLike : appL10n.likeThisPost,
            tint: post.liked ? Theme.of(context).discourse.love : null,
            onInvoke: () => _report(
              controller,
              controller.toggleLike(post, siteUrl: widget.siteUrl),
            ),
          ),
        if (postUrl case final url?)
          PostAction(
            icon: DIcons.link,
            placement: PostActionPlacement.toolbar,
            group: PostActionGroup.share,
            label: appL10n.copyLink,
            tooltip: appL10n.copyALinkToThisPostToClipboard,
            onInvoke: () => _copyLink(controller, url),
          ),
        if (topic != null && post.cooked.isNotEmpty)
          PostAction(
            icon: DIcons.copy,
            group: PostActionGroup.share,
            placement: PostActionPlacement.overflow,
            label: appL10n.copyText,
            tooltip: appL10n.copyText,
            onInvoke: () => unawaited(
              Clipboard.setData(
                ClipboardData(
                  text: PostQuoteSelectionResolver(post.cooked).plainText,
                ),
              ),
            ),
          ),
        if (postUrl case final url?)
          PostAction(
            icon: DIcons.upRightFromSquare,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.share,
            label: appL10n.share,
            tooltip: appL10n.shareThisPost,
            onInvoke: () => unawaited(
              showPostShareSheet(
                context: context,
                topicTitle: topicTitle!,
                url: url,
                postNumber: post.postNumber,
                privateMessage: topic?.privateMessage == true,
                onReplyAsNewTopic:
                    topic != null &&
                        controller.canReplyAsNewTopic(topic) &&
                        canonicalUrl != null
                    ? captureShareReplyAsNewTopic(
                        context: context,
                        siteUrl: widget.siteUrl,
                        topicId: topic.id,
                        continuation: topicContinuationMarkdown(
                          title: topic.title,
                          url: canonicalUrl,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        if (tab.canReplyHere &&
            topic != null &&
            post.cooked.isNotEmpty &&
            !post.hidden &&
            !post.isDeleted)
          PostAction(
            icon: DIcons.quoteLeft,
            group: PostActionGroup.share,
            placement: PostActionPlacement.overflow,
            label: appL10n.quote,
            tooltip: appL10n.quote,
            onInvoke: () => unawaited(
              tab.openQuote(
                post,
                buildPostQuote(
                  post: post,
                  topicId: topic.id,
                  contents: PostQuoteSelectionResolver(post.cooked).entirePost,
                  config: config,
                ),
              ),
            ),
          ),
        if (topic != null &&
            controller.canReplyAsNewTopic(topic) &&
            canonicalUrl != null &&
            !post.isWhisper &&
            !post.hidden &&
            !post.isDeleted)
          PostAction(
            icon: DIcons.upRightFromSquare,
            group: PostActionGroup.share,
            placement: PostActionPlacement.overflow,
            label: appL10n.replyAsNewTopic,
            tooltip: appL10n.replyAsNewTopic,
            onInvoke: () {
              final reply = captureShareReplyAsNewTopic(
                context: context,
                siteUrl: widget.siteUrl,
                topicId: topic.id,
                continuation: topicContinuationMarkdown(
                  title: topic.title,
                  url: canonicalUrl,
                ),
              );
              if (reply != null) unawaited(reply());
            },
          ),
        if (tab.canReplyHere)
          PostAction(
            icon: DIcons.reply,
            placement: PostActionPlacement.trailing,
            showLabelInFooter: false,
            label: appL10n.reply,
            tooltip: appL10n.replyToThisPost,
            onInvoke: () => tab.openReply(
              replyToPostNumber: post.postNumber,
              replyToUsername: post.username,
              replyingToWhisper: post.isWhisper,
            ),
          ),
        if (post.canEdit)
          PostAction(
            icon: DIcons.pencil,
            placement: PostActionPlacement.overflow,
            showLabelInFooter: false,
            label: appL10n.edit,
            tooltip: appL10n.editThisPost,
            onInvoke: () => tab.openEdit(post),
          ),
        if (post.editCount > 0 && post.canViewEditHistory)
          PostAction(
            icon: DIcons.pencil,
            placement: PostActionPlacement.overflow,
            label: appL10n.viewEditHistory,
            tooltip: appL10n.viewThisPostSEditHistory,
            onInvoke: () => _openRevisionHistory(controller),
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
            label: post.bookmark == null
                ? appL10n.bookmark
                : appL10n.bookmarked,
            placement: PostActionPlacement.overflow,
            showLabelInFooter: false,
            tooltip: post.bookmark == null
                ? appL10n.bookmarkThisPost
                : appL10n.editThisPostBookmark,
            tint: post.bookmark == null
                ? null
                : Theme.of(context).colorScheme.primary,
            enabled: !controller.bookmarkWriteInFlight(
              siteUrl: widget.siteUrl,
              topicId: topic.id,
              targetType: BookmarkTargetType.post,
              targetId: post.id,
            ),
            onInvokeAnchored: (anchor) => unawaited(
              showPostBookmarkMenu(
                context: context,
                controller: controller,
                siteUrl: widget.siteUrl,
                topicId: topic.id,
                post: post,
                anchor: anchor,
              ),
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
        ...contribution.entries,
        if (controller.canUnhidePost(post))
          PostAction(
            icon: DIcons.farEye,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.staff,
            label: appL10n.unhidePost,
            tooltip: appL10n.restoreThisHiddenPost,
            onInvoke: () => _report(controller, controller.unhidePost(post)),
          ),
        if (post.canWiki)
          PostAction(
            icon: DIcons.farPenToSquare,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.staff,
            label: post.wiki ? appL10n.removeWiki : appL10n.makeWiki,
            tooltip: post.wiki
                ? appL10n.returnThisToOrdinaryPostEditing
                : appL10n.allowCommunityMembersToEditThisPost,
            onInvoke: () =>
                _report(controller, controller.setPostWiki(post, !post.wiki)),
          ),
        if (availableFlags.isNotEmpty)
          PostAction(
            icon: DIcons.flag,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.report,
            label: appL10n.flag,
            tooltip: appL10n.privatelyFlagThisPostForAttention,
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
            group: PostActionGroup.report,
            label: appL10n.reportIllegalContent,
            tooltip: appL10n.reportIllegalContentByEmail,
            onInvoke: () => showAnonymousIllegalContentDialog(
              context: context,
              email: anonymousReportEmail,
              topicTitle: topicTitle,
              postUrl: postUrl,
            ),
          ),
        if (instance?.url == widget.siteUrl &&
            topic != null &&
            controller.canEditPostNotice(
              siteUrl: widget.siteUrl,
              topicId: topic.id,
              postId: post.id,
            ))
          PostAction(
            icon: DIcons.user,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.staff,
            label: post.notice == null
                ? appL10n.addPostNotice
                : appL10n.changePostNotice,
            tooltip: post.notice == null
                ? appL10n.addAStaffNoticeAboveThisPost
                : appL10n.changeOrRemoveTheStaffNotice,
            onInvoke: () => showPostNoticeEditor(
              context: context,
              controller: controller,
              siteUrl: widget.siteUrl,
              topicId: topic.id,
              post: post,
            ),
          ),
        if (controller.canLockPost(post))
          PostAction(
            icon: post.locked ? DIcons.unlock : DIcons.lock,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.staff,
            label: post.locked ? appL10n.unlockPost : appL10n.lockPost,
            tooltip: post.locked
                ? appL10n.allowThisPostToBeEditedAgain
                : appL10n.preventFurtherEditsToThisPost,
            onInvoke: () => _report(
              controller,
              controller.setPostLocked(post, !post.locked),
            ),
          ),
        if (controller.canChangeTopicPostOwner(post))
          PostAction(
            icon: DIcons.user,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.staff,
            label: appL10n.changeOwner,
            tooltip: appL10n.assignThisPostToAnotherAccount,
            onInvoke: () {
              final topic = ForumTabScope.tabOf(context).currentTopic;
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
        if (controller.canTogglePostType(post))
          PostAction(
            icon: DIcons.flag,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.staff,
            label: post.isModeratorAction
                ? appL10n.revertToRegularPost
                : appL10n.convertToModeratorPost,
            tooltip: post.isModeratorAction
                ? appL10n.removeTheModeratorStylingFromThisPost
                : appL10n.markThisAsAnOfficialModeratorPost,
            onInvoke: () =>
                _report(controller, controller.togglePostType(post)),
          ),
        if (post.postNumber == 1 &&
            topic?.canEdit != true &&
            topic?.canEditTags == true)
          PostAction(
            icon: DIcons.tag,
            placement: PostActionPlacement.overflow,
            label: appL10n.editTags,
            tooltip: appL10n.editTopicTagsPostactions,
            onInvoke: tab.openTagsEdit,
          ),
        if (topic != null && controller.canPermanentlyDeletePost(post))
          PostAction(
            icon: DIcons.trashCan,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.report,
            label: appL10n.permanentlyDelete,
            tooltip: appL10n.permanentlyDeleteThisPost,
            destructive: true,
            onInvoke: () => unawaited(
              showPostPermanentDelete(
                context: context,
                controller: controller,
                siteUrl: widget.siteUrl,
                topicId: topic.id,
                post: post,
              ),
            ),
          ),
        if (post.canRecover)
          PostAction(
            icon: DIcons.arrowRotateLeft,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.report,
            label: post.postNumber == 1
                ? appL10n.recoverTopic
                : appL10n.undelete,
            tooltip: appL10n.putThisPostBack,
            onInvoke: () => _report(controller, controller.recoverPost(post)),
          )
        else if (post.canDelete)
          PostAction(
            icon: DIcons.trashCan,
            placement: PostActionPlacement.overflow,
            group: PostActionGroup.report,
            label: post.postNumber == 1
                ? appL10n.deleteTopicTopicactions
                : appL10n.delete,
            tooltip: post.postNumber == 1
                ? appL10n.deleteThisTopicAction
                : appL10n.deleteThisPost,
            destructive: true,
            onInvoke: () => _report(controller, controller.deletePost(post)),
          ),
      ],
      rebuildOn: contribution.rebuildOn,
      quickReaction:
          controller.postWriteInFlight(post.id, siteUrl: widget.siteUrl)
          ? null
          : contribution.replacesLike
          ? contribution.quickReaction
          : post.canLike && !post.liked
          ? () {
              final latest =
                  controller.store.read<Post>(widget.siteUrl, post.id) ?? post;
              if (latest.liked || !latest.canLike) return Future.value(null);
              return controller.toggleLike(latest, siteUrl: widget.siteUrl);
            }
          : null,
    );
  }

  void _openRevisionHistory(ShellController controller) {
    final siteUrl = widget.siteUrl;
    final post = widget.post;
    final lease = controller.lifecycle.capture(siteUrl);

    unawaited(
      showPostRevisionHistory(
        context: context,
        siteUrl: siteUrl,
        post: post,
        loadRevision: (revision) async {
          // The dialog can outlive this row and its opening account. Refuse
          // before the controller captures a session or reads credentials.
          if (!lease.isCurrent) return null;
          try {
            final fetched = await controller.loadPostRevision(
              siteUrl: siteUrl,
              postId: post.id,
              revision: revision,
            );
            return lease.isCurrent ? fetched : null;
          } catch (_) {
            if (!lease.isCurrent) return null;
            rethrow;
          }
        },
        categoryLabel: (id) {
          if (id == null) return appL10n.uncategorized;
          return controller.categoryFor(id, siteUrl: siteUrl)?.name ??
              appL10n.categoryPostactions((id).toString());
        },
      ),
    );
  }

  String? _postShareUrl(ShellController controller) {
    final instance = controller.currentInstance;
    final tab = ForumTabScope.tabOf(context);
    final topic = tab.currentTopic;
    final route = tab.currentContent;
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
    final tab = ForumTabScope.tabOf(context);
    final topic = tab.currentTopic;
    final route = tab.currentContent;
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
      message = appL10n.linkCopied;
    } catch (_) {
      message = appL10n.couldnTCopyLink;
    }
    if (!mounted || !identical(ShellScope.maybeRead(context), controller)) {
      return;
    }
    DToast.show(
      context,
      message,
      type: message.startsWith("Couldn't")
          ? DToastType.error
          : DToastType.success,
    );
  }

  Future<void> _report(ShellController controller, Future<String?> work) async {
    final error = await work;
    if (error == null ||
        !mounted ||
        !identical(ShellScope.maybeRead(context), controller)) {
      return;
    }
    DToast.show(context, error, type: DToastType.error);
  }

  Future<void> _openSheet(List<PostAction> actions) async {
    final shell = ShellScope.read(context);
    final siteUrl = widget.siteUrl;
    final lease = shell.lifecycle.capture(siteUrl);
    final tab = ForumTabScope.tabOf(context);
    final routeId = tab.currentContent?.id;
    final postId = widget.post.id;
    final selected = await showDSheet<PostAction>(
      context: context,
      side: DSheetSide.bottom,
      builder: (sheetContext, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: widget.post.displayName,
        topBottomMaxHeightFactor: .85,
        children: [
          DSheetHeader(
            children: [DSheetTitle(child: Text(widget.post.displayName))],
          ),
          DSheetBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final action in actions)
                  DItem(
                    enabled: action.enabled,
                    onPressed: action.enabled
                        ? () => sheet.close(action)
                        : null,
                    children: [
                      DItemMedia(
                        variant: DItemMediaVariant.icon,
                        child: Builder(
                          builder: (context) => action.leading(
                            context,
                            size: IconTheme.of(context).size!,
                            color:
                                action.tint ??
                                (action.destructive
                                    ? DTokens.of(context).destructive
                                    : null),
                          ),
                        ),
                      ),
                      DItemContent(
                        children: [DItemTitle(child: Text(action.label))],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null ||
        !mounted ||
        !identical(ShellScope.maybeRead(context), shell) ||
        !lease.isCurrent ||
        widget.siteUrl != siteUrl ||
        widget.post.id != postId ||
        shell.currentInstance?.url != siteUrl ||
        !tab.isCurrent ||
        ForumTabScope.tabOf(context).tabId != tab.tabId ||
        tab.currentContent?.id != routeId) {
      return;
    }
    // Open any composer only after the sheet has returned its selection.
    selected.onInvoke();
  }

  @override
  void dispose() {
    _menu.dispose();
    _detachScroll();
    _anchor.dispose();
    _firstActionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ForumTabSelector<
      ({
        bool canReply,
        Object presentation,
        Object flagCatalog,
        bool bookmarkBusy,
        bool postBusy,
      })
    >(
      select: (controller, tab) => (
        canReply: tab.canReplyHere,
        presentation: controller.presentationTokenFor(widget.siteUrl),
        flagCatalog: controller.postFlagTypesFor(widget.siteUrl),
        bookmarkBusy: switch (tab.currentTopic) {
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
    final snapshot = _actions(context, ShellScope.read(context));
    if (snapshot.rebuildOn case final rebuildOn?) {
      // Discovering the plugin's rebuild signal already constructed the menu.
      // Reuse that snapshot for this builder's first call, then read fresh
      // actions on notifications. A parent rebuild supplies a new snapshot.
      var initial = true;
      return ListenableBuilder(
        listenable: rebuildOn,
        builder: (context, _) {
          final current = initial
              ? snapshot
              : _actions(context, ShellScope.read(context));
          initial = false;
          return _buildActionList(
            context,
            current.actions,
            current.quickReaction,
          );
        },
      );
    }
    return _buildActionList(context, snapshot.actions, snapshot.quickReaction);
  }

  Widget _buildActionList(
    BuildContext context,
    List<PostAction> actions,
    Future<String?> Function()? quickReaction,
  ) {
    actions = [
      for (final group in PostActionGroup.values)
        ...actions.where((action) => action.group == group),
    ];
    final owner = PostActionOwner.capture(
      context,
      siteUrl: widget.siteUrl,
      postId: widget.post.id,
    );
    void react() {
      if (!owner.isCurrent(
        context,
        siteUrl: widget.siteUrl,
        postId: widget.post.id,
      )) {
        return;
      }
      unawaited(HapticFeedback.selectionClick());
      unawaited(_report(ShellScope.read(context), quickReaction!()));
    }

    void invoke(PostAction action, BuildContext anchorContext) =>
        _invokeFrom(action, anchorContext, owner);
    if (widget.persistent) {
      final child = _PostActionsScope(
        actions: actions,
        menu: _menu,
        firstFocus: _firstActionFocus,
        onInvoke: invoke,
        postNumber: widget.post.postNumber,
        child: _PostQuickReactionScope(
          onReact: context.isTouch && quickReaction != null ? react : null,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.contextMenu):
                  _openFromKeyboard,
              const SingleActivator(LogicalKeyboardKey.f10, shift: true):
                  _openFromKeyboard,
            },
            child: widget.child,
          ),
        ),
      );
      return context.isTouch && actions.isNotEmpty
          ? GestureDetector(
              onLongPress: () => _openSheet(actions),
              child: child,
            )
          : child;
    }
    if (actions.isEmpty) return widget.child;

    // Hover is wired unconditionally: a MouseRegion simply never fires without
    // a pointer, so a touch screen falls through to the long press below
    // without needing to ask what it is running on.
    final Widget hoverable = MouseRegion(
      onEnter: (_) => _pointerEntered(_PostActionsHoverTarget.post),
      onHover: (_) => _pointerMoved(_PostActionsHoverTarget.post),
      onExit: (_) => _pointerExited(_PostActionsHoverTarget.post),
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
            onEnter: (_) => _pointerEntered(_PostActionsHoverTarget.toolbar),
            onHover: (_) => _pointerMoved(_PostActionsHoverTarget.toolbar),
            onExit: (_) => _pointerExited(_PostActionsHoverTarget.toolbar),
            child: _PostActionsMenu(
              actions: actions,
              firstActionFocus: _firstActionFocus,
              onOverflowChanged: _overflowChanged,
              onInvoke: invoke,
            ),
          ),
        ),
        child: _PostQuickReactionScope(
          onReact: context.isTouch && quickReaction != null ? react : null,
          child: widget.child,
        ),
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

class _PostQuickReactionScope extends InheritedWidget {
  const _PostQuickReactionScope({required this.onReact, required super.child});

  final VoidCallback? onReact;

  @override
  bool updateShouldNotify(_PostQuickReactionScope oldWidget) =>
      oldWidget.onReact != onReact;
}

bool _hasFiniteEdges(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite;

class _PostActionsMenu extends StatelessWidget {
  const _PostActionsMenu({
    required this.actions,
    required this.firstActionFocus,
    required this.onOverflowChanged,
    required this.onInvoke,
  });

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
  final void Function(PostAction action, BuildContext anchorContext) onInvoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overflowActions = _overflowActions(actions);
    final collapse = overflowActions.length > 1;
    final leadingActions = _leadingActions(actions, collapse: collapse);
    final trailingActions = _trailingActions(actions);

    return Align(
      alignment: Alignment.centerRight,
      child: HoverActionToolbar(
        children: [
          for (final (index, action) in leadingActions.indexed)
            Builder(
              builder: (buttonContext) => HoverActionButton(
                focusNode: index == 0 ? firstActionFocus : null,
                onPressed: action.enabled
                    ? () => onInvoke(action, buttonContext)
                    : null,
                icon: action.leading(context, size: 16),
                tooltip: action.tooltip,
                color:
                    action.tint ??
                    (action.destructive ? theme.colorScheme.error : null),
              ),
            ),
          if (collapse)
            Semantics(
              container: true,
              explicitChildNodes: true,
              child: DDropdownMenu(
                onOpenChange: (open, reason) {
                  if (open) {
                    onOverflowChanged(true);
                  }
                  if (!open) {
                    onOverflowChanged(false);
                  }
                },
                content: DDropdownMenuContent(
                  semanticLabel: context.l10n.actions,
                  width: 300,
                  constraints: const BoxConstraints(maxHeight: 440),
                  children: [
                    for (final (index, action) in overflowActions.indexed) ...[
                      if (index > 0 &&
                          overflowActions[index - 1].group != action.group)
                        const DSeparator(space: 1),
                      Builder(
                        builder: (buttonContext) => DDropdownMenuItem(
                          onPressed: action.enabled
                              ? () => onInvoke(action, buttonContext)
                              : null,
                          leading: action.leading(
                            context,
                            size: 16,
                            color:
                                action.tint ??
                                (action.destructive
                                    ? theme.colorScheme.error
                                    : null),
                          ),
                          variant: action.destructive
                              ? DDropdownMenuItemVariant.destructive
                              : DDropdownMenuItemVariant.standard,
                          child: Text(action.label),
                        ),
                      ),
                    ],
                  ],
                ),
                child: DDropdownMenuTrigger(
                  focusNode: leadingActions.isEmpty ? firstActionFocus : null,
                  builder: (triggerContext, state) => DButton.iconOnly(
                    focusNode: state.focusNode,
                    hasPopup: true,
                    expanded: state.open,
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.post,
                    key: const ValueKey('post-actions-overflow'),

                    tooltip: context.l10n.moreActions,
                    onPressed: state.toggle,
                    icon: const DIcon(DIcons.ellipsis, size: 16),
                  ),
                ),
              ),
            ),
          for (final (index, action) in trailingActions.indexed)
            Builder(
              builder: (buttonContext) => HoverActionButton(
                focusNode: leadingActions.isEmpty && !collapse && index == 0
                    ? firstActionFocus
                    : null,
                onPressed: action.enabled
                    ? () => onInvoke(action, buttonContext)
                    : null,
                icon: action.leading(context, size: 16),
                tooltip: action.tooltip,
                color:
                    action.tint ??
                    (action.destructive ? theme.colorScheme.error : null),
              ),
            ),
        ],
      ),
    );
  }
}

class _PostActionsScope extends InheritedWidget {
  const _PostActionsScope({
    required this.actions,
    required this.menu,
    required this.firstFocus,
    required this.onInvoke,
    required this.postNumber,
    required super.child,
  });
  final List<PostAction> actions;
  final DDropdownMenuController menu;
  final FocusNode firstFocus;
  final void Function(PostAction, BuildContext) onInvoke;
  final int postNumber;
  @override
  bool updateShouldNotify(_PostActionsScope oldWidget) => true;
}

/// Keeps primary post actions beside engagement without requiring hover.
class PostActionsFooter extends StatelessWidget {
  const PostActionsFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_PostActionsScope>();
    final actions = scope?.actions
        .where((action) => action.placement == PostActionPlacement.trailing)
        .toList(growable: false);
    if (scope == null || actions == null || scope.actions.isEmpty) return child;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: child),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              if (scope.actions.any(
                (action) => action.placement != PostActionPlacement.trailing,
              ))
                const PostMoreActionsButton(),
              for (final action in actions)
                Builder(
                  builder: (buttonContext) {
                    final key = ValueKey((
                      'post-footer-action',
                      scope.postNumber,
                      action.label,
                    ));
                    final icon = action.leading(
                      context,
                      size: DControlStyle.iconDimension(DControlSize.post),
                      color: action.tint,
                    );
                    final onPressed = action.enabled
                        ? () => scope.onInvoke(action, buttonContext)
                        : null;
                    return action.showLabelInFooter
                        ? DButton(
                            key: key,
                            icon: icon,
                            label: Text(action.label),
                            tooltip: action.tooltip,
                            variant: DButtonVariant.ghost,
                            density: DButtonDensity.postAction,
                            size: DButtonSize.post,
                            onPressed: onPressed,
                          )
                        : DButton.iconOnly(
                            key: key,
                            icon: icon,
                            tooltip: action.tooltip,
                            variant: DButtonVariant.ghost,
                            density: DButtonDensity.postAction,
                            size: DButtonSize.post,
                            onPressed: onPressed,
                          );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A permanent, keyboard-reachable entry point to the same guarded actions
/// used by the post toolbar and touch sheet.
class PostMoreActionsButton extends StatelessWidget {
  const PostMoreActionsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_PostActionsScope>();
    if (scope == null) return const SizedBox.shrink();
    final actions = scope.actions
        .where(
          (action) =>
              action.showInMenu &&
              action.placement != PostActionPlacement.trailing,
        )
        .toList(growable: false);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DDropdownMenu(
        controller: scope.menu,
        onOpenChange: (open, reason) {
          if (open) {
            (() => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted && scope.menu.isOpen) {
                scope.firstFocus.requestFocus();
              }
            }))();
          }
        },
        content: DDropdownMenuContent(
          semanticLabel: context.l10n.actions,
          width: 300,
          constraints: const BoxConstraints(maxHeight: 440),
          children: [
            for (final (index, action) in actions.indexed) ...[
              if (index > 0 && actions[index - 1].group != action.group)
                const DDropdownMenuSeparator(),
              if (action.group == PostActionGroup.staff &&
                  (index == 0 || actions[index - 1].group != action.group))
                DDropdownMenuLabel(
                  child: Text(context.l10n.staffChatmessagetile),
                ),
              DDropdownMenuItem(
                focusNode:
                    identical(
                      action,
                      actions.where((item) => item.enabled).firstOrNull,
                    )
                    ? scope.firstFocus
                    : null,
                onPressed: action.enabled
                    ? () => scope.onInvoke(action, context)
                    : null,
                leading: DIcon(
                  action.icon,
                  size: 16,
                  color: action.destructive
                      ? Theme.of(context).colorScheme.error
                      : action.tint,
                ),
                variant: action.destructive
                    ? DDropdownMenuItemVariant.destructive
                    : DDropdownMenuItemVariant.standard,
                child: Text(action.label),
              ),
            ],
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (triggerContext, state) => DButton.iconOnly(
            focusNode: state.focusNode,
            hasPopup: true,
            expanded: state.open,
            key: ValueKey('post-more-actions-${scope.postNumber}'),
            icon: const DIcon(DIcons.ellipsis),
            tooltip: context.l10n.moreActionsForPost(
              (scope.postNumber).toString(),
            ),
            semanticLabel: context.l10n.moreActionsForPost(
              (scope.postNumber).toString(),
            ),
            variant: DButtonVariant.ghost,
            density: DButtonDensity.postAction,
            size: DButtonSize.post,
            onPressed: state.toggle,
          ),
        ),
      ),
    );
  }
}
