import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'voice_controller.dart';
import 'voice_reactions.dart';
import 'voice_services.dart';

const _usage = EmojiUsageContext(
  owner: PluginId('voice'),
  name: 'call-reactions',
);

class VoiceReactionStage extends StatelessWidget {
  const VoiceReactionStage({
    super.key,
    required this.controller,
    required this.child,
    required this.siteUrl,
    required this.roomId,
  });
  final VoiceController controller;
  final Widget child;
  final String siteUrl;
  final int roomId;

  @override
  Widget build(BuildContext context) {
    final emoji = PluginUiScope.maybe(context, voiceEmojiHostService);
    if (emoji == null) return child;
    final session = controller.reactionsForCall(siteUrl, roomId);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (session != null)
          VoiceReactionOverlay(
            key: ObjectKey(session),
            session: session,
            emoji: emoji,
          ),
      ],
    );
  }
}

class VoiceCallReactionButton extends StatelessWidget {
  const VoiceCallReactionButton({super.key, required this.controller});
  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    final emoji = PluginUiScope.maybe(context, voiceEmojiHostService);
    if (emoji == null) return const SizedBox.shrink();
    final session = controller.callReactions;
    if (session == null) return const SizedBox.shrink();
    return VoiceReactionButton(
      key: ObjectKey(session),
      session: session,
      emoji: emoji,
    );
  }
}

class VoiceReactionOverlay extends StatefulWidget {
  const VoiceReactionOverlay({
    super.key,
    required this.session,
    required this.emoji,
  });

  final VoiceReactionSession session;
  final PluginEmojiHost emoji;

  @override
  State<VoiceReactionOverlay> createState() => _VoiceReactionOverlayState();
}

class _VoiceReactionOverlayState extends State<VoiceReactionOverlay> {
  SiteEmojiCatalog? _catalog;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VoiceReactionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.emoji != widget.emoji) {
      _catalog = null;
      _load();
    }
  }

  void _load() {
    final session = widget.session;
    unawaited(
      widget.emoji
          .loadCatalog(session.siteUrl)
          .then((catalog) {
            if (mounted &&
                identical(widget.session, session) &&
                session.isCurrent) {
              setState(() => _catalog = catalog);
            }
          })
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => DReactionOverlay(
      entries: [
        for (final reaction in widget.session.reactions)
          DReactionOverlayEntry(
            id: reaction.id,
            label: reaction.username,
            artwork: DAnimatedEmoji(
              url: widget.emoji.resolveUrl(
                widget.session.siteUrl,
                reaction.emoji,
              ),
              animatedUrl: _catalog?.animatedUrlFor(
                reaction.emoji,
                staticUrl: widget.emoji.resolveUrl(
                  widget.session.siteUrl,
                  reaction.emoji,
                ),
              ),
              alt: ':${reaction.emoji}:',
            ),
          ),
      ],
    ),
  );
}

class VoiceReactionButton extends StatefulWidget {
  const VoiceReactionButton({
    super.key,
    required this.session,
    required this.emoji,
  });

  final VoiceReactionSession session;
  final PluginEmojiHost emoji;

  @override
  State<VoiceReactionButton> createState() => _VoiceReactionButtonState();
}

class _VoiceReactionButtonState extends State<VoiceReactionButton> {
  final _popover = DPopoverController();
  bool _picking = false;

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  Future<void> _more(BuildContext anchor) async {
    _popover.close();
    setState(() => _picking = true);
    final session = widget.session;
    try {
      // Replace the small popover instead of nesting two outside-click
      // surfaces. Its exit must finish before the full picker opens.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted || !session.canSend || !anchor.mounted) return;
      final picked = await showEmojiPicker(
        context: anchor,
        siteUrl: session.siteUrl,
        pickerContext: _usage,
        store: widget.emoji.preferences,
        loadCatalog: ({refresh = false}) =>
            widget.emoji.loadCatalog(session.siteUrl, refresh: refresh),
        loadSearchAliases: ({refresh = false}) =>
            widget.emoji.loadSearchAliases(session.siteUrl, refresh: refresh),
      );
      if (picked == null || !mounted || !session.canSend) return;
      unawaited(
        widget.emoji.preferences.trackEmoji(
          siteUrl: session.siteUrl,
          context: _usage,
          emoji: picked,
        ),
      );
      await session.send(picked);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final settings = session.settings;
      if (settings?.supported != true) return const SizedBox.shrink();
      return EmojiPickerAnchor(
        child: Builder(
          builder: (anchor) => DPopover(
            controller: _popover,
            sheetOnMobile: true,
            content: DPopoverContent(
              semanticLabel: context.l10n.chooseAReaction,
              width: 320,
              child: Wrap(
                spacing: DSpacing.controlGap,
                runSpacing: DSpacing.controlGap,
                children: [
                  for (final code in settings!.emojis)
                    DButton.iconOnly(
                      tooltip: code,
                      variant: DButtonVariant.ghost,
                      icon: DAnimatedEmoji(
                        url: widget.emoji.resolveUrl(session.siteUrl, code),
                        alt: ':$code:',
                        size: 24,
                      ),
                      onPressed: !session.canSend
                          ? null
                          : () {
                              _popover.close();
                              unawaited(session.send(code));
                            },
                    ),
                  if (settings.allowAnyEmoji)
                    DButton.iconOnly(
                      tooltip: context.l10n.moreEmojis,
                      icon: const DIcon(DIcons.faceSmile),
                      variant: DButtonVariant.ghost,
                      onPressed: session.canSend ? () => _more(anchor) : null,
                    ),
                ],
              ),
            ),
            child: DPopoverTrigger(
              builder: (context, state) => DButton.iconOnly(
                tooltip: context.l10n.addReaction,
                icon: const DIcon(DIcons.faceSmile),
                variant: DButtonVariant.secondary,
                focusNode: state.focusNode,
                expanded: state.open,
                onPressed: session.canSend && !_picking ? state.toggle : null,
              ),
            ),
          ),
        ),
      );
    },
  );
}
