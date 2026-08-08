import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../shell/avatar_image.dart';
import '../../shell/hover_panel.dart';
import '../../shell/platform.dart';
import '../../shell/shell_scope.dart';
import '../../shell/shell_sheet.dart';
import '../../shell/site_emoji_image.dart';
import '../../shell/user_card.dart';
import '../../theme/app_theme.dart';
import 'post_reactors.dart';
import 'reaction.dart';
import 'reactions_controller.dart';

/// What people gave a post, under the post itself.
///
/// The reactions plugin's answer to the likes count, and drawn on the same
/// terms: nothing at all until somebody has reacted, because an untouched post
/// is offered the picker in its action menu instead. This is a record of what
/// happened rather than an invitation.
///
/// One pill per emoji, each its own way in to who gave it. There is no grand
/// total beside them: `Reactions.userCount` is not their sum and can exceed it,
/// and a total that does not add up is worse than none.
class ReactionsRow extends StatelessWidget {
  const ReactionsRow({super.key, required this.siteUrl, required this.post});

  final String siteUrl;
  final Post post;

  @override
  Widget build(BuildContext context) {
    final reactions = post.reactions;
    // Nobody has reacted, so there is nothing to say and no room taken up
    // saying it. Also the state a post whose only reaction used a since-deleted
    // emoji is left in — the site drops it from the row and still counts it.
    if (reactions == null || reactions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in reactions.entries)
              ReactionPill(
                siteUrl: siteUrl,
                post: post,
                reaction: entry,
                mine: reactions.mine?.id == entry.id,
              ),
          ],
        ),
      ),
    );
  }
}

/// One emoji and how many gave it.
///
/// Sized for a finger rather than for a pointer, unlike the like count it
/// replaces: eight of these sit side by side and every one of them writes, so
/// the incidental-target rules that applied to a single heart do not.
class ReactionPill extends StatefulWidget {
  const ReactionPill({
    super.key,
    required this.siteUrl,
    required this.post,
    required this.reaction,
    required this.mine,
  });

  /// Apple's floor, and Material's. Reached by padding rather than by drawing
  /// a taller pill, so the row keeps the density Discourse's own has.
  static const double minTarget = 44;

  final String siteUrl;
  final Post post;
  final Reaction reaction;

  /// Whether this is the one the reader gave.
  final bool mine;

  @override
  State<ReactionPill> createState() => _ReactionPillState();
}

class _ReactionPillState extends State<ReactionPill> {
  static const double _panelWidth = 260;

  final GlobalKey<HoverPanelState> _panel = GlobalKey<HoverPanelState>();

  void _load() {
    final controller = ShellScope.read(context);
    unawaited(
      controller.reactions.load(
        siteUrl: widget.siteUrl,
        postId: widget.post.id,
        filter: widget.reaction.id,
      ),
    );
  }

  /// The touch equivalent of the panel: the same names, in a sheet.
  Future<void> _openSheet() async {
    final count = widget.reaction.count;
    _load();

    await showShellSheet<void>(
      context: context,
      title: count == 1 ? '1 reaction' : '$count reactions',
      builder: (sheetContext) => ReactorList(
        siteUrl: widget.siteUrl,
        post: widget.post,
        filter: widget.reaction.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      // Long press is the touch way in. The post underneath opens its own
      // action sheet on a long press, and this one wins the gesture arena by
      // being the nearer of the two.
      onLongPress: context.isTouch ? _openSheet : null,
      child: HoverPanel(
        key: _panel,
        maxWidth: _panelWidth,
        onOpen: _load,
        panelBuilder: (context) => _ReactorPanel(
          siteUrl: widget.siteUrl,
          post: widget.post,
          filter: widget.reaction.id,
        ),
        child: Semantics(
          label: widget.reaction.count == 1
              ? '1 ${widget.reaction.id} reaction'
              : '${widget.reaction.count} ${widget.reaction.id} reactions',
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: ReactionPill.minTarget,
              minHeight: ReactionPill.minTarget,
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
                decoration: BoxDecoration(
                  color: theme.shell.floating,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.mine
                        ? theme.colorScheme.primary
                        : theme.shell.divider,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SiteEmojiImage(
                      siteUrl: widget.siteUrl,
                      name: widget.reaction.id,
                      size: 16,
                      alt: ':${widget.reaction.id}:',
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${widget.reaction.count}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: widget.mine
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
        ),
      ),
    );
  }
}

/// The floating version of the list, for a pointer.
class _ReactorPanel extends StatelessWidget {
  const _ReactorPanel({
    required this.siteUrl,
    required this.post,
    required this.filter,
  });

  final String siteUrl;
  final Post post;
  final String? filter;

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
          child: ReactorList(siteUrl: siteUrl, post: post, filter: filter),
        ),
      ),
    );
  }
}

/// Who reacted, drawn the same way wherever it is being shown.
///
/// The panel and the sheet are the same list on two different surfaces, so
/// there is one answer to what a row looks like rather than two that have to be
/// kept in step.
class ReactorList extends StatelessWidget {
  const ReactorList({
    super.key,
    required this.siteUrl,
    required this.post,
    this.filter,
  });

  /// Enough for a handful of names before the list starts scrolling, without
  /// the panel ever growing taller than the post it hangs off.
  static const double _maxHeight = 220;

  final String siteUrl;
  final Post post;

  /// The emoji this list is narrowed to, or null for everyone.
  final String? filter;

  @override
  Widget build(BuildContext context) => ShellSelector<ReactionsController>(
    select: (controller) => controller.reactions,
    builder: (context, reactions, _) => _ReactorListView(
      reactions: reactions,
      siteUrl: siteUrl,
      post: post,
      filter: filter,
    ),
  );
}

typedef _ReactorListSnapshot = ({PostReactors? reactors, String? error});

class _ReactorListView extends StatefulWidget {
  const _ReactorListView({
    required this.reactions,
    required this.siteUrl,
    required this.post,
    required this.filter,
  });

  final ReactionsController reactions;
  final String siteUrl;
  final Post post;
  final String? filter;

  @override
  State<_ReactorListView> createState() => _ReactorListViewState();
}

class _ReactorListViewState extends State<_ReactorListView> {
  late _ReactorListSnapshot _snapshot;
  Object? _reloadToken;

  @override
  void initState() {
    super.initState();
    _snapshot = _select();
    widget.reactions.addListener(_onReactionsChanged);
  }

  @override
  void didUpdateWidget(_ReactorListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(oldWidget.reactions, widget.reactions);
    final queryChanged =
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.post.id != widget.post.id ||
        oldWidget.filter != widget.filter;

    if (controllerChanged) {
      oldWidget.reactions.removeListener(_onReactionsChanged);
      widget.reactions.addListener(_onReactionsChanged);
    }
    if (controllerChanged || queryChanged) {
      _snapshot = _select();
      _reloadAfterLayout();
    }
  }

  _ReactorListSnapshot _select() => (
    reactors: widget.reactions.reactors(
      widget.siteUrl,
      widget.post.id,
      filter: widget.filter,
    ),
    error: widget.reactions.error(
      widget.siteUrl,
      widget.post.id,
      filter: widget.filter,
    ),
  );

  void _onReactionsChanged() {
    final next = _select();
    if (next == _snapshot) return;
    setState(() => _snapshot = next);
  }

  void _reloadAfterLayout() {
    final token = Object();
    _reloadToken = token;
    final reactions = widget.reactions;
    final siteUrl = widget.siteUrl;
    final postId = widget.post.id;
    final filter = widget.filter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_reloadToken, token)) return;
      _reloadToken = null;
      if (!identical(widget.reactions, reactions) ||
          widget.siteUrl != siteUrl ||
          widget.post.id != postId ||
          widget.filter != filter) {
        return;
      }
      unawaited(
        reactions.load(siteUrl: siteUrl, postId: postId, filter: filter),
      );
    });
  }

  @override
  void dispose() {
    _reloadToken = null;
    widget.reactions.removeListener(_onReactionsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: ReactorList._maxHeight),
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    final siteUrl = widget.siteUrl;
    final theme = Theme.of(context);
    final held = _snapshot.reactors;

    if (held == null) {
      final error = _snapshot.error;
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

    // More reacted than the route was asked for. Counted against the route's
    // own total rather than against `Reactions.userCount`, which comes from a
    // different query and legitimately disagrees with what is on screen.
    final hidden = held.total - held.reactors.length;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reactor in held.reactors)
            _ReactorRow(reactor: reactor, siteUrl: siteUrl),
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

class _ReactorRow extends StatelessWidget {
  const _ReactorRow({required this.reactor, required this.siteUrl});

  final PostReactor reactor;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return UserCardTarget(
      username: reactor.username,
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
                  url: reactor.avatarUrl,
                  size: 24,
                  fallback: ColoredBox(
                    color: theme.shell.panel,
                    child: Center(
                      child: Text(
                        reactor.username.isEmpty
                            ? '?'
                            : reactor.username.characters.first.toUpperCase(),
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
                reactor.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            // Which emoji they gave. Drawn even in a list already narrowed to
            // one, because the sheet's title is a count rather than a picture.
            const SizedBox(width: 8),
            SiteEmojiImage(
              siteUrl: siteUrl,
              name: reactor.reaction,
              size: 14,
              alt: ':${reactor.reaction}:',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
