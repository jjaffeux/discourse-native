import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'reaction.dart';
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
  });

  final ReactionsController controller;
  final PluginEmojiHost emoji;
  final String siteUrl;
  final Post post;

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
        oldWidget.post.id != widget.post.id) {
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

  Future<void> _loadSettings() async {
    final session = widget.controller.beginPicker(widget.siteUrl, widget.post);
    await widget.controller.allowsAnyEmoji(widget.siteUrl);
    if (_isCurrent(session)) setState(() {});
  }

  Future<void> _toggle(BuildContext buttonContext) async {
    if (_busy) return;
    final controller = widget.controller;
    final post = widget.post;
    final siteUrl = widget.siteUrl;
    final session = controller.beginPicker(siteUrl, post);
    final toast = DToast.maybeOf(context);
    final operation = Object();
    _panel.currentState?.close();
    setState(() => _operation = operation);
    try {
      await controller.allowsAnyEmoji(siteUrl);
      if (!_isCurrent(session)) return;
      final current = controller.pickerPost(session, post);
      if (current == null || !current.canReact) return;
      final reaction =
          current.reactions?.mine?.id ??
          controller.siteConfigFor(siteUrl).reactionsSettings.mainReaction;
      if (reaction == null) {
        if (!buttonContext.mounted) return;
        await showPostReactionPicker(
          buttonContext,
          controller,
          widget.emoji,
          siteUrl,
          current,
        );
        return;
      }
      _report(
        toast,
        controller,
        session,
        controller.toggleFromPicker(session, current, reaction),
        stillOwnsUi: () => _isCurrent(session),
      );
    } finally {
      if (mounted && identical(_operation, operation)) {
        setState(() => _operation = null);
      }
    }
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
      final settings = controller
          .siteConfigFor(widget.siteUrl)
          .reactionsSettings;
      final current =
          controller.post(widget.siteUrl, widget.post.id) ?? widget.post;
      final mine = current.reactions?.mine?.id;
      final enabled =
          current.canReact &&
          !_busy &&
          !controller.writeInFlight(widget.siteUrl, widget.post.id);
      final icon =
          DIcons.byName['far-${settings.likeIcon}'] ??
          DIcons.byName[settings.likeIcon] ??
          DIcons.farHeart;
      final label = mine == null
          ? context.l10n.addReaction
          : context.l10n.removeYourReactionReactionpicker((mine).toString());

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
                    controller.beginPicker(widget.siteUrl, widget.post),
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
                child: DToggle.iconOnly(
                  pressed: mine != null,
                  enabled: enabled,
                  size: DToggleSize.post,
                  variant: DToggleVariant.outline,
                  semanticLabel: label,
                  semanticLongPressHint:
                      context.l10n.chooseAReactionReactionpicker,
                  onPressedChanged: (_) => _toggle(buttonContext),
                  onLongPress: () => _panel.currentState?.open(),
                  icon: mine != null
                      ? EmojiImage(
                          url: controller.emojiUrlFor(widget.siteUrl, mine),
                          size: 16,
                          alt: ':$mine:',
                        )
                      : DIcon(icon),
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
}) async {
  final session = controller.beginPicker(siteUrl, post);
  final toast = DToast.maybeOf(context);
  bool stillOwnsUi() => !context.mounted || _stillOwnsUi(context, controller);
  final allowAnyEmoji = await controller.allowsAnyEmoji(siteUrl);
  if (!context.mounted ||
      !controller.isPickerCurrent(session) ||
      !_stillOwnsUi(context, controller)) {
    return;
  }
  final current = controller.pickerPost(session, post);
  if (current == null || !current.canReact) return;
  if (!allowAnyEmoji) {
    return showReactionPicker(
      context,
      controller,
      siteUrl,
      current,
      nested: false,
      session: session,
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
  if (picked == null || !controller.isPickerCurrent(session)) {
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
    session,
    controller.toggleFromPicker(session, current, picked),
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
    return showShellSheet<void>(
      context: context,
      title: appL10n.react,
      nested: nested,
      builder: (sheetContext) => ReactionGrid._withSession(
        pickerSession,
        context,
        controller: controller,
        siteUrl: siteUrl,
        post: post,
        onPicked: Navigator.of(sheetContext).pop,
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ReactionGrid._withSession(
            pickerSession,
            context,
            controller: controller,
            siteUrl: siteUrl,
            post: post,
            onPicked: Navigator.of(dialogContext).pop,
          ),
        ),
      ),
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
      DToggle.visualDimensionFor(DToggleSize.large) * 8 +
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
            size: DButtonSize.large,
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
  Future<String?> work, {
  required bool Function() stillOwnsUi,
}) {
  unawaited(
    work.then((error) {
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
    size: DToggleSize.large,
    onPressedChanged: (_) => onTap?.call(),
    icon: Builder(
      builder: (context) => SizedBox.square(
        dimension: IconTheme.of(context).size!,
        child: EmojiImage(
          url: url,
          size: IconTheme.of(context).size!,
          alt: ':$id:',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    ),
  );
}
