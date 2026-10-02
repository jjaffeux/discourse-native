import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../plugin_api/reaction_presentation.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'emoji_picker.dart';
import 'platform.dart';
import 'site_emoji_image.dart';
import 'skeleton_fill.dart';
import 'user_card.dart';

class ReactionPills extends Padding {
  ReactionPills({
    super.key,
    required List<Widget> children,
    super.padding = const EdgeInsets.only(top: DSpacing.xs),
  }) : super(
         child: Align(
           alignment: Alignment.centerLeft,
           child: Wrap(
             spacing: 6,
             runSpacing: 6,
             crossAxisAlignment: WrapCrossAlignment.center,
             children: children,
           ),
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
    return EmojiPickerAnchor(
      child: Builder(
        builder: (buttonContext) => DButton.iconOnly(
          key: const ValueKey('reaction-picker-surface'),
          tooltip: context.l10n.addReaction,
          icon: const DIcon(DIcons.farFaceSmile),
          variant: DButtonVariant.transparentBackground,
          size: DButtonSize.post,
          onPressed: widget.enabled && !_opening
              ? () => _open(buttonContext)
              : null,
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
    required this.interactionOwner,
    required this.loadReactors,
    required this.reactorsBuilder,
    this.enabled = true,
    this.onTapHint,
    this.onToggle,
    this.visualKey,
    this.size = DToggleSize.regular,
    this.density = DToggleDensity.standard,
  });

  // Retained for the legacy post reaction-picker adapter. Native controls
  // determine their own platform-appropriate target size.

  final String siteUrl;
  final String reaction;
  final int count;
  final bool selected;
  final String? onTapHint;

  final Object interactionOwner;

  final bool enabled;

  final Future<String?> Function()? onToggle;

  final Future<void> Function() loadReactors;
  final WidgetBuilder reactorsBuilder;

  final Key? visualKey;
  final DToggleSize size;
  final DToggleDensity density;

  @override
  State<ReactionPill> createState() => _ReactionPillState();
}

class _ReactionPillState extends State<ReactionPill> {
  static const double _panelWidth = 260;

  final DHoverCardController _panel = DHoverCardController();
  bool _toggling = false;

  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  void _load() => unawaited(widget.loadReactors());

  Future<void> _openSheet() async {
    _load();
    final title = widget.count == 1
        ? appL10n.message1Reaction
        : appL10n.reactionsReactionpresentation((widget.count).toString());
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
          DSheetBody(child: Builder(builder: widget.reactorsBuilder)),
        ],
      ),
    );
  }

  Future<void> _toggle() async {
    if (_toggling || !widget.enabled) return;
    final toggle = widget.onToggle;
    if (toggle == null) return;

    setState(() => _toggling = true);
    final owner = widget.interactionOwner;
    try {
      final error = await toggle();
      if (!mounted || !identical(widget.interactionOwner, owner)) return;

      if (_panel.isOpen) _load();
      if (error != null) {
        DToast.show(context, error, type: DToastType.error);
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.count == 1
        ? context.l10n.message1ReactionReactionpresentation(
            (widget.reaction).toString(),
          )
        : context.l10n.reactionsReactionpresentationValue(
            (widget.count).toString(),
            (widget.reaction).toString(),
          );
    return DHoverCard(
      controller: _panel,
      enabled: widget.enabled && !context.isTouch,
      onOpenChange: (open, _) {
        if (open) _load();
      },
      content: DHoverCardContent(
        width: _panelWidth,
        child: Builder(builder: widget.reactorsBuilder),
      ),
      trigger: DHoverCardTrigger(
        delay: const Duration(milliseconds: 250),
        closeDelay: const Duration(milliseconds: 500),
        builder: (context, state) => DToggle(
          key: widget.visualKey,
          size: widget.size,
          density: widget.density,
          focusNode: state.focusNode,
          pressed: widget.selected,
          enabled: widget.enabled && !_toggling,
          readOnly: widget.onToggle == null,
          onPressedChanged: (_) => _toggle(),
          onLongPress: context.isTouch ? _openSheet : null,
          semanticLabel: label,
          semanticHint: widget.onToggle != null ? widget.onTapHint : null,
          semanticLongPressHint: context.l10n.showWhoReacted,
          variant: DToggleVariant.outline,
          icon: Builder(
            builder: (context) => SiteEmojiImage(
              siteUrl: widget.siteUrl,
              name: widget.reaction,
              size: widget.density == DToggleDensity.chatReaction
                  ? 12
                  : widget.size == DToggleSize.post
                  ? 16
                  : IconTheme.of(context).size!,
              alt: ':${widget.reaction}:',
            ),
          ),
          child: Text('${widget.count}'),
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
  Widget build(BuildContext context) {
    final body = _body(context);
    // Mobile sheets own the scrolling; the desktop hover card stays compact.
    if (context.isTouch) return body;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: ReactionUsersList._maxHeight,
      ),
      child: SingleChildScrollView(child: body),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final held = _snapshot.reactors;

    if (held == null) {
      final error = _snapshot.error;
      if (error == null) {
        return DSkeletonRegion(
          semanticsLabel: context.l10n.loadingReactions,
          color: skeletonFill(context, on: SkeletonSurface.floating),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final width in [120.0, 96.0, 136.0])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const DSkeleton.circle(diameter: 24),
                      const SizedBox(width: 8),
                      Flexible(child: DSkeleton(width: width, height: 14)),
                    ],
                  ),
                ),
            ],
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
            DButton(
              key: const ValueKey('reactor-list-retry'),
              onPressed: _retry,
              variant: DButtonVariant.ghost,
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      );
    }

    final hidden = held.total - held.reactors.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final reactor in held.reactors)
          _ReactorRow(reactor: reactor, siteUrl: widget.siteUrl),
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
            DAvatar.frame(
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
