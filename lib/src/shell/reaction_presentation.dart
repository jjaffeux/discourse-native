import 'dart:async';

import 'package:flutter/material.dart';

import '../plugin_api/reaction_presentation.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'emoji_picker.dart';
import 'hover_panel.dart';
import 'platform.dart';
import 'shell_sheet.dart';
import 'site_emoji_image.dart';
import 'user_card.dart';

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

class ReactionPickerButton extends StatefulWidget {
  const ReactionPickerButton({
    super.key,
    required this.onOpenPicker,
    this.enabled = true,
  });

  final Future<void> Function(BuildContext) onOpenPicker;
  final bool enabled;

  @override
  State<ReactionPickerButton> createState() => _ReactionPickerButtonState();
}

class _ReactionPickerButtonState extends State<ReactionPickerButton> {
  bool _opening = false;

  Future<void> _open(BuildContext context) async {
    if (_opening || !widget.enabled) return;
    setState(() => _opening = true);
    try {
      await widget.onOpenPicker(context);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.enabled && !_opening;
    return EmojiPickerAnchor(
      child: Builder(
        builder: (buttonContext) => Semantics(
          container: true,
          button: true,
          enabled: enabled,
          label: 'Add reaction',
          child: Tooltip(
            message: 'Add reaction',
            excludeFromSemantics: true,
            child: SizedBox.square(
              dimension: ReactionPill.minTarget,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  mouseCursor: enabled
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  onTap: enabled ? () => _open(buttonContext) : null,
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedOpacity(
                    opacity: enabled ? 1 : 0.5,
                    duration: const Duration(milliseconds: 100),
                    child: Center(
                      child: DIcon(
                        DIcons.farFaceSmile,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
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
    this.enabled = true,
    this.onToggle,
    this.visualKey,
  });

  static const double minTarget = 44;

  final String siteUrl;
  final String reaction;
  final int count;
  final bool selected;
  final String onTapHint;

  final Object interactionOwner;

  final bool enabled;

  final Future<String?> Function()? onToggle;

  final Future<void> Function() loadReactors;
  final WidgetBuilder reactorsBuilder;

  final Key? visualKey;

  @override
  State<ReactionPill> createState() => _ReactionPillState();
}

class _ReactionPillState extends State<ReactionPill> {
  static const double _panelWidth = 260;

  final GlobalKey<HoverPanelState> _panel = GlobalKey<HoverPanelState>();
  bool _hovered = false;
  bool _focused = false;
  bool _toggling = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

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
    if (_toggling || !widget.enabled) return;
    final toggle = widget.onToggle;
    if (toggle == null) {
      await _openSheet();
      return;
    }

    setState(() => _toggling = true);
    final owner = widget.interactionOwner;
    try {
      final error = await toggle();
      if (!mounted || !identical(widget.interactionOwner, owner)) return;

      if (_panel.currentState?.isShowing ?? false) _load();
      if (error != null) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.count == 1
        ? '1 ${widget.reaction} reaction'
        : '${widget.count} ${widget.reaction} reactions';
    final enabled = widget.enabled && !_toggling;
    final background = enabled && (_hovered || _focused)
        ? Color.alphaBlend(
            theme.colorScheme.onSurface.withValues(alpha: 0.08),
            theme.shell.floating,
          )
        : theme.shell.floating;

    return HoverPanel(
      key: _panel,
      maxWidth: _panelWidth,
      onOpen: _load,
      panelBuilder: (context) =>
          ReactionUsersPanel(child: widget.reactorsBuilder(context)),
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled,
        selected: widget.selected,
        label: label,
        onTapHint: enabled ? widget.onTapHint : null,
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
                onEnter: enabled ? (_) => _setHovered(true) : null,
                onExit: enabled ? (_) => _setHovered(false) : null,
                child: InkWell(
                  mouseCursor: enabled
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  onTap: enabled ? _toggle : null,
                  onLongPress: enabled && context.isTouch ? _openSheet : null,
                  onFocusChange: _setFocused,
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedOpacity(
                    opacity: enabled ? 1 : 0.5,
                    duration: const Duration(milliseconds: 100),
                    child: ExcludeSemantics(
                      child: Container(
                        key: widget.visualKey,
                        padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
                        decoration: BoxDecoration(
                          color: background,
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
      ),
    );
  }
}

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

typedef ReactionUsersSnapshot = ({ReactionUsersPage? reactors, String? error});

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

  final ReactionUser reactor;
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
