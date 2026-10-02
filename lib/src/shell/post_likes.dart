import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/post_likers.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'hover_panel.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_card.dart';

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

  void _load() => unawaited(
    ShellScope.read(
      context,
    ).loadLikers(widget.post.id, siteUrl: widget.siteUrl),
  );

  void _openPanel() => _panel.currentState?.open();

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
      DToast.show(context, error, type: DToastType.error);
    }
  }

  Future<void> _openSheet() async {
    final controller = ShellScope.read(context);
    final count = widget.post.likeCount;
    unawaited(controller.loadLikers(widget.post.id, siteUrl: widget.siteUrl));

    final title = count == 1
        ? appL10n.message1Like
        : appL10n.likesPostlikes((count).toString());
    await showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      inset: true,
      fillAvailableHeight: true,
      builder: (context, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: title,
        topBottomMaxHeightFactor: 1,
        scrollWholeSheet: false,
        children: [
          DSheetHeader(children: [DSheetTitle(child: Text(title))]),
          DSheetBody(
            child: _Likers(siteUrl: widget.siteUrl, post: widget.post),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
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
            enabled: !context.isTouch,
            maxWidth: _panelWidth,
            onOpen: _load,
            panelBuilder: (context) =>
                _LikersPanel(siteUrl: widget.siteUrl, post: post),
            child: _LikeCount(
              post: post,
              onOpen: context.isTouch ? _openSheet : _openPanel,
              onToggle: post.canToggleLike ? _toggle : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _LikeCount extends StatelessWidget {
  const _LikeCount({
    required this.post,
    required this.onOpen,
    required this.onToggle,
  });

  final Post post;
  final VoidCallback onOpen;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggle = onToggle;

    return DToggle(
      pressed: post.liked,
      size: DToggleSize.post,
      variant: DToggleVariant.outline,
      semanticLabel: post.likeCount == 1
          ? context.l10n.message1LikeFrom((post.liked).toString())
          : context.l10n.likesPostlikesValue((post.likeCount).toString()),
      semanticHint: toggle == null
          ? context.l10n.showWhoLikedThisPost
          : (post.liked
                ? context.l10n.removeYourLikePostlikes
                : context.l10n.likeThisPostPostlikes),
      onPressedChanged: (_) => (toggle ?? onOpen)(),
      icon: DIcon(DIcons.heart, color: theme.discourse.love),
      child: Text('${post.likeCount}'),
    );
  }
}

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
      // A `Container`, not a `DecoratedBox`: a bordered decoration's
      // dimensions are padding a `Container` applies and a `DecoratedBox`
      // does not, so the panel's contents would sit under its own border and
      // be clipped by the rounded `Material` around it.
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

class _Likers extends StatelessWidget {
  const _Likers({required this.siteUrl, required this.post});

  static const double _maxHeight = 220;

  final String siteUrl;
  final Post post;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({ShellController controller, Object session})>(
        select: (controller) => (
          controller: controller,
          // Account replacement also needs a reload when both snapshots are
          // empty, and starts from new store refs.
          session: controller.lifecycle.capture(siteUrl).session,
        ),
        // Each fetch of the likers and its result are announced here, not on
        // the shell.
        builder: (context, owner, _) => ListenableBuilder(
          listenable: Listenable.merge([
            owner.controller.likerRequests,
            owner.controller.store.ref<PostLikers>(siteUrl, post.id),
          ]),
          builder: (context, _) => _LikersView(
            maxHeight: _maxHeight,
            siteUrl: siteUrl,
            post: post,
            snapshot: (
              controller: owner.controller,
              session: owner.session,
              likers: owner.controller.likers(post.id, siteUrl: siteUrl),
              error: owner.controller.likersError(post.id, siteUrl: siteUrl),
            ),
          ),
        ),
      );
}

typedef _LikersSnapshot = ({
  ShellController controller,
  Object session,
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
        !identical(oldWidget.snapshot.session, widget.snapshot.session) ||
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
    final lease = controller.lifecycle.capture(siteUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_reloadToken, token)) return;
      _reloadToken = null;
      if (!lease.isCurrent ||
          !identical(widget.snapshot.controller, controller) ||
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
  Widget build(BuildContext context) {
    final body = _body(context);
    if (context.isTouch) return body;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: SingleChildScrollView(child: body),
    );
  }

  Widget _body(BuildContext context) {
    final post = widget.post;
    final siteUrl = widget.siteUrl;
    final snapshot = widget.snapshot;
    final theme = Theme.of(context);
    final likers = snapshot.likers?.likers;

    if (likers == null) {
      final error = snapshot.error;
      if (error == null) {
        return const SizedBox.shrink();
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

    final hidden = post.likeCount - likers.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final liker in likers) _LikerRow(siteUrl: siteUrl, liker: liker),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              hidden == 1
                  ? context.l10n.and1Other
                  : context.l10n.andOthers((hidden).toString()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
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
            DAvatar.frame(
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
