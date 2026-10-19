import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'reaction.dart';
import 'reaction_toggle_presentation.dart';
import 'reaction_toggle_result.dart';
import 'reactions_controller.dart';
import 'reactions_emoji_usage.dart';
import 'reactions_services.dart';
import 'reactions_settings.dart';

class PostReactionButton extends StatefulWidget {
  const PostReactionButton({
    super.key,
    required this.controller,
    required this.emoji,
    required this.siteUrl,
    required this.post,
    this.session,
  });

  final ReactionsController controller;
  final PluginEmojiHost emoji;
  final String siteUrl;
  final Post post;
  final ReactionPickerSession? session;

  @override
  State<PostReactionButton> createState() => _PostReactionButtonState();
}

class _PostReactionButtonState extends State<PostReactionButton> {
  final GlobalKey<HoverPanelState> _panel = GlobalKey();
  Object? _operation;
  late Listenable _changes = _listenable();

  bool get _busy => _operation != null;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  @override
  void didUpdateWidget(PostReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.post.id != widget.post.id ||
        oldWidget.session != widget.session) {
      _operation = null;
      _changes = _listenable();
      unawaited(_loadSettings());
    }
  }

  /// Not the controller: every post's reactor load and reaction write
  /// notifies it, and a topic holds one button per post. The site's catalog
  /// decides where a held reaction's emoji is drawn from.
  Listenable _listenable() => Listenable.merge([
    widget.controller.postChanges(widget.siteUrl, widget.post.id),
    widget.controller.emojiCatalogChanges(widget.siteUrl),
  ]);

  bool _isCurrent(ReactionPickerSession session) =>
      mounted &&
      session.siteUrl == widget.siteUrl &&
      session.postId == widget.post.id &&
      widget.controller.isPickerCurrent(session) &&
      _stillOwnsUi(context, widget.controller);

  ReactionPickerSession _session() =>
      widget.session ??
      widget.controller.beginPicker(widget.siteUrl, widget.post);

  Future<void> _loadSettings() async {
    final session = _session();
    if (!widget.controller.isPickerCurrent(session)) return;
    await widget.controller.allowsAnyEmoji(widget.siteUrl);
    if (_isCurrent(session)) setState(() {});
  }

  Future<void> _openEmojiPicker(BuildContext buttonContext) async {
    if (_busy) return;
    final operation = Object();
    _panel.currentState?.close();
    setState(() => _operation = operation);
    try {
      await showPostReactionPicker(
        buttonContext,
        widget.controller,
        widget.emoji,
        widget.siteUrl,
        widget.post,
        session: _session(),
      );
    } finally {
      if (mounted && identical(_operation, operation)) {
        setState(() => _operation = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) {
      final controller = widget.controller;
      final current =
          controller.post(widget.siteUrl, widget.post.id) ?? widget.post;
      final enabled =
          current.canReact &&
          (widget.session == null || _isCurrent(widget.session!)) &&
          !_busy &&
          !controller.writeInFlight(widget.siteUrl, widget.post.id);
      return EmojiPickerAnchor(
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Builder(
            builder: (buttonContext) => HoverPanel(
              key: _panel,
              enabled: enabled,
              preferAbove: true,
              maxWidth: ReactionGrid.maxWidth,
              panelBuilder: (context) => FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: DPopoverContent(
                  semanticLabel: context.l10n.chooseAReaction,
                  width: ReactionGrid.maxWidth,
                  padding: const EdgeInsets.all(DSpacing.xs),
                  child: ReactionGrid._withSession(
                    _session(),
                    buttonContext,
                    controller: controller,
                    siteUrl: widget.siteUrl,
                    post: widget.post,
                    onPicked: () => _panel.currentState?.close(),
                    onMore: () => unawaited(_openEmojiPicker(buttonContext)),
                  ),
                ),
              ),
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(0),
                child: DButton.iconOnly(
                  size: DButtonSize.post,
                  density: DButtonDensity.postReaction,
                  tooltip: context.l10n.addReaction,
                  tooltipSide: DTooltipSide.bottom,
                  onPressed: enabled ? () => _panel.currentState?.open() : null,
                  icon: const DIcon(DIcons.faceSmile),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> showPostReactionPicker(
  BuildContext context,
  ReactionsController controller,
  PluginEmojiHost emoji,
  String siteUrl,
  Post post, {
  Rect? anchor,
  ReactionPickerSession? session,
}) async {
  final pickerSession = session ?? controller.beginPicker(siteUrl, post);
  if (!controller.isPickerCurrent(pickerSession)) return;
  final toast = DToast.maybeOf(context);
  bool stillOwnsUi() => !context.mounted || _stillOwnsUi(context, controller);
  final allowAnyEmoji = await controller.allowsAnyEmoji(siteUrl);
  if (!context.mounted ||
      !controller.isPickerCurrent(pickerSession) ||
      !_stillOwnsUi(context, controller)) {
    return;
  }
  final current = controller.pickerPost(pickerSession, post);
  if (current == null || !current.canReact) return;
  if (!allowAnyEmoji) {
    return showReactionPicker(
      context,
      controller,
      siteUrl,
      current,
      nested: false,
      session: pickerSession,
    );
  }

  final picked = await showEmojiPicker(
    context: context,
    anchor: anchor,
    siteUrl: siteUrl,
    pickerContext: reactionsEmojiUsageContext,
    store: emoji.preferences,
    loadCatalog: ({refresh = false}) =>
        emoji.loadCatalog(siteUrl, refresh: refresh),
    loadSearchAliases: ({refresh = false}) =>
        emoji.loadSearchAliases(siteUrl, refresh: refresh),
  );
  if (picked == null || !controller.isPickerCurrent(pickerSession)) {
    return;
  }

  unawaited(
    emoji.preferences.trackEmoji(
      siteUrl: siteUrl,
      context: reactionsEmojiUsageContext,
      emoji: picked,
    ),
  );
  _report(
    toast,
    controller,
    pickerSession,
    controller.toggleFromPicker(pickerSession, current, picked),
    stillOwnsUi: stillOwnsUi,
  );
}

Future<void> showReactionPicker(
  BuildContext context,
  ReactionsController controller,
  String siteUrl,
  Post post, {
  bool nested = true,
  ReactionPickerSession? session,
}) {
  final pickerSession = session ?? controller.beginPicker(siteUrl, post);
  final isTouch = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  if (isTouch) {
    return showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      inset: true,
      fillAvailableHeight: true,
      builder: (_, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: appL10n.react,
        showCloseButton: false,
        topBottomMaxHeightFactor: 1,
        scrollWholeSheet: false,
        children: [
          ComposerSheetHeader(title: appL10n.react),
          DSheetBody(
            child: ReactionGrid._withSession(
              pickerSession,
              context,
              controller: controller,
              siteUrl: siteUrl,
              post: post,
              onPicked: sheet.close,
            ),
          ),
        ],
      ),
    );
  }

  return showDDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext, dialog) => DDialogContent(
      maxWidth: 340,
      showCloseButton: false,
      semanticLabel: appL10n.react,
      children: [
        ReactionGrid._withSession(
          pickerSession,
          context,
          controller: controller,
          siteUrl: siteUrl,
          post: post,
          onPicked: dialog.close,
        ),
      ],
    ),
  );
}

class ReactionGrid extends StatelessWidget {
  ReactionGrid({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.post,
    required this.onPicked,
  }) : _ownerContext = null,
       onMore = null,
       _session = controller.beginPicker(siteUrl, post);

  const ReactionGrid._withSession(
    this._session,
    this._ownerContext, {
    required this.controller,
    required this.siteUrl,
    required this.post,
    required this.onPicked,
    this.onMore,
  });

  static double get maxWidth =>
      DToggle.visualDimensionFor(DToggleSize.post) * 8 +
      DSpacing.controlGap * 7 +
      DSpacing.xs * 2;

  final ReactionsController controller;
  final BuildContext? _ownerContext;
  final String siteUrl;
  final Post post;
  final VoidCallback onPicked;
  final VoidCallback? onMore;
  final ReactionPickerSession _session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _buildGrid(context),
  );

  Widget _buildGrid(BuildContext context) {
    final theme = Theme.of(context);
    final config = controller.siteConfigFor(siteUrl);
    final current = controller.pickerPost(_session, post);
    final held = current?.reactions?.mine?.id;
    final enabled =
        current?.canReact == true &&
        !controller.writeInFlight(siteUrl, post.id);

    final settings = config.reactionsSettings;
    final more = settings.allowAnyEmoji ? onMore : null;
    if (settings.offeredReactions.isEmpty && more == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          context.l10n.stillFindingOutWhichReactionsThisSiteAllows,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final grid = Wrap(
      spacing: DSpacing.controlGap,
      runSpacing: DSpacing.controlGap,
      children: [
        for (final id in settings.offeredReactions)
          _ReactionCell(
            id: id,
            url: controller.emojiUrlFor(siteUrl, id),
            held: id == held,
            onTap: !enabled
                ? null
                : () {
                    final toast = DToast.maybeOf(context);
                    final ownerContext = _ownerContext ?? context;
                    final canAct =
                        controller.isPickerCurrent(_session) &&
                        (!ownerContext.mounted ||
                            _stillOwnsUi(ownerContext, controller));
                    onPicked();
                    if (!canAct) return;
                    final target = controller.pickerPost(_session, post);
                    if (target == null || !target.canReact) return;
                    _report(
                      toast,
                      controller,
                      _session,
                      controller.toggleFromPicker(_session, target, id),
                      stillOwnsUi: () =>
                          !ownerContext.mounted ||
                          _stillOwnsUi(ownerContext, controller),
                    );
                  },
          ),
        if (more != null)
          DButton.iconOnly(
            onPressed: enabled ? more : null,
            size: DButtonSize.post,
            variant: DButtonVariant.ghost,
            tooltip: context.l10n.moreEmojis,
            icon: const DIcon(DIcons.farFaceSmile),
          ),
      ],
    );

    if (!settings.desaturatedPanel) return grid;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      child: grid,
    );
  }
}

bool _stillOwnsUi(BuildContext context, ReactionsController controller) {
  if (PluginUiScope.maybeOwnerOf(context) == null) return true;
  return identical(
    PluginUiScope.maybe(context, reactionsControllerService),
    controller,
  );
}

void _report(
  DToastController? toast,
  ReactionsController controller,
  ReactionPickerSession session,
  Future<ReactionToggleResult> work, {
  required bool Function() stillOwnsUi,
}) {
  unawaited(
    work.then((result) {
      final error = result.message;
      if (error == null ||
          !controller.isPickerCurrent(session) ||
          toast?.isDisposed != false ||
          !stillOwnsUi()) {
        return;
      }
      toast!.add(DToastOptions(description: error, type: DToastType.error));
    }),
  );
}

class _ReactionCell extends StatelessWidget {
  const _ReactionCell({
    required this.id,
    required this.url,
    required this.held,
    required this.onTap,
  });

  final String id;
  final String url;
  final bool held;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => DToggle.iconOnly(
    semanticLabel: id,
    pressed: held,
    enabled: onTap != null,
    size: DToggleSize.post,
    onPressedChanged: (_) => onTap?.call(),
    icon: Builder(
      builder: (context) => SizedBox.square(
        dimension: 16,
        child: EmojiImage(
          url: url,
          size: 16,
          alt: ':$id:',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    ),
  );
}
