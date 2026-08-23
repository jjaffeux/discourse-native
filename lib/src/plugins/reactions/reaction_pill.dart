import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/avatar_image.dart';
import '../../shell/hover_panel.dart';
import '../../shell/platform.dart';
import '../../shell/shell_sheet.dart';
import '../../shell/site_emoji_image.dart';
import '../../shell/user_card.dart';
import '../../theme/app_theme.dart';
import 'post_reactors.dart';

/// The shared layout for reaction pills under either a post or chat message.
///
/// Feature owners supply the pills because their reaction records and write
/// semantics differ. Padding, wrapping and density live here so those details
/// cannot drift apart again.
class ReactionPills extends Padding {
  ReactionPills({super.key, required List<Widget> children})
    : super(
        padding: const EdgeInsets.only(top: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 6, runSpacing: 6, children: children),
        ),
      );
}

/// One emoji/count reaction and the people behind it.
///
/// This owns every visual and interaction detail shared by topic and chat:
/// touch target, selected treatment, click error reporting, hover panel and
/// long-press sheet. Callbacks are the intentional boundary between them — a
/// topic and a chat message use different read and write endpoints.
class ReactionPill extends StatefulWidget {
  const ReactionPill({
    super.key,
    required this.siteUrl,
    required this.reaction,
    required this.count,
    required this.selected,
    required this.onTapHint,
    required this.interactionOwner,
    required this.loadReactors,
    required this.reactorsBuilder,
    this.onToggle,
    this.visualKey,
  });

  /// Apple's floor, and Material's. Reached by padding rather than by drawing
  /// a taller pill, so the row keeps the density Discourse's own has.
  static const double minTarget = 44;

  final String siteUrl;
  final String reaction;
  final int count;
  final bool selected;
  final String onTapHint;

  /// Identifies the controller that owns asynchronous callbacks. A response
  /// from a controller replaced under this state must not report into the new
  /// account's scaffold.
  final Object interactionOwner;

  /// Null makes a tap open the reactor list, for a read-only reaction.
  final Future<String?> Function()? onToggle;

  /// Refreshes the names whenever their hover panel or sheet opens.
  final Future<void> Function() loadReactors;
  final WidgetBuilder reactorsBuilder;

  /// An optional key for tests and callers that address the painted pill.
  final Key? visualKey;

  @override
  State<ReactionPill> createState() => _ReactionPillState();
}

class _ReactionPillState extends State<ReactionPill> {
  static const double _panelWidth = 260;

  final GlobalKey<HoverPanelState> _panel = GlobalKey<HoverPanelState>();

  void _load() => unawaited(widget.loadReactors());

  Future<void> _openSheet() async {
    _load();
    await showShellSheet<void>(
      context: context,
      title: widget.count == 1 ? '1 reaction' : '${widget.count} reactions',
      builder: widget.reactorsBuilder,
    );
  }

  Future<void> _toggle() async {
    final toggle = widget.onToggle;
    if (toggle == null) {
      await _openSheet();
      return;
    }

    final owner = widget.interactionOwner;
    final error = await toggle();
    if (!mounted || !identical(widget.interactionOwner, owner)) return;

    if (_panel.currentState?.isShowing ?? false) _load();
    if (error != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.count == 1
        ? '1 ${widget.reaction} reaction'
        : '${widget.count} ${widget.reaction} reactions';

    return HoverPanel(
      key: _panel,
      maxWidth: _panelWidth,
      onOpen: _load,
      panelBuilder: (context) =>
          ReactionUsersPanel(child: widget.reactorsBuilder(context)),
      child: Semantics(
        container: true,
        button: true,
        selected: widget.selected,
        label: label,
        onTapHint: widget.onTapHint,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: ReactionPill.minTarget,
            minHeight: ReactionPill.minTarget,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Material(
              type: MaterialType.transparency,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: _toggle,
                  onLongPress: context.isTouch ? _openSheet : null,
                  borderRadius: BorderRadius.circular(14),
                  child: ExcludeSemantics(
                    child: Container(
                      key: widget.visualKey,
                      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
                      decoration: BoxDecoration(
                        color: theme.shell.floating,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: widget.selected
                              ? theme.colorScheme.primary
                              : theme.shell.divider,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SiteEmojiImage(
                            siteUrl: widget.siteUrl,
                            name: widget.reaction,
                            size: 16,
                            alt: ':${widget.reaction}:',
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${widget.count}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: widget.selected
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
          ),
        ),
      ),
    );
  }
}

/// The common floating surface around a reactor list.
class ReactionUsersPanel extends StatelessWidget {
  const ReactionUsersPanel({super.key, required this.child});

  final Widget child;

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
          child: child,
        ),
      ),
    );
  }
}

typedef ReactionUsersSnapshot = ({ReactorsPage? reactors, String? error});

/// Who reacted, with loading, retry and user rows shared by topic and chat.
///
/// [source] is the owning feature controller. [select] and [load] are the only
/// feature-specific code paths: topic delegates them to `ReactionsController`,
/// while chat delegates them to `ChatController`.
class ReactionUsersList extends StatefulWidget {
  const ReactionUsersList({
    super.key,
    required this.siteUrl,
    required this.source,
    required this.query,
    required this.select,
    required this.load,
  });

  static const double _maxHeight = 220;

  final String siteUrl;
  final Listenable source;

  /// Stable value identity for the target and optional emoji filter.
  final Object query;
  final ReactionUsersSnapshot Function() select;
  final Future<void> Function() load;

  @override
  State<ReactionUsersList> createState() => _ReactionUsersListState();
}

class _ReactionUsersListState extends State<ReactionUsersList> {
  late ReactionUsersSnapshot _snapshot;
  Object? _reloadToken;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.select();
    widget.source.addListener(_onSourceChanged);
  }

  @override
  void didUpdateWidget(ReactionUsersList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = !identical(oldWidget.source, widget.source);
    final queryChanged = oldWidget.query != widget.query;

    if (sourceChanged) {
      oldWidget.source.removeListener(_onSourceChanged);
      widget.source.addListener(_onSourceChanged);
    }
    if (sourceChanged || queryChanged) {
      _snapshot = widget.select();
      _reloadAfterLayout();
    }
  }

  void _onSourceChanged() {
    final next = widget.select();
    if (next == _snapshot) return;
    setState(() => _snapshot = next);
  }

  void _retry() => unawaited(widget.load());

  void _reloadAfterLayout() {
    final token = Object();
    _reloadToken = token;
    final source = widget.source;
    final query = widget.query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_reloadToken, token)) return;
      _reloadToken = null;
      if (!identical(widget.source, source) || widget.query != query) return;
      unawaited(widget.load());
    });
  }

  @override
  void dispose() {
    _reloadToken = null;
    widget.source.removeListener(_onSourceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: ReactionUsersList._maxHeight),
    child: _body(context),
  );

  Widget _body(BuildContext context) {
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
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                error,
                key: const ValueKey('reactor-list-error'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('reactor-list-retry'),
              onPressed: _retry,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final hidden = held.total - held.reactors.length;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reactor in held.reactors)
            _ReactorRow(reactor: reactor, siteUrl: widget.siteUrl),
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
          ],
        ),
      ),
    );
  }
}
