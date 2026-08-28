import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/emoji.dart';
import '../../shell/emoji_picker.dart';
import '../../shell/shell_sheet.dart';
import 'reaction.dart';
import 'reactions_controller.dart';
import 'reactions_emoji_usage.dart';
import 'reactions_services.dart';
import 'reactions_settings.dart';

/// Opens the policy-aware chooser for a post reaction affordance.
Future<void> showPostReactionPicker(
  BuildContext context,
  ReactionsController controller,
  PluginEmojiHost emoji,
  String siteUrl,
  Post post,
) async {
  final session = controller.beginPicker(siteUrl, post);
  final messenger = ScaffoldMessenger.maybeOf(context);
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
    messenger,
    controller,
    session,
    controller.toggleFromPicker(session, current, picked),
    stillOwnsUi: stillOwnsUi,
  );
}

/// Offers the emoji a site allows, so a reader can give one.
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
      title: 'React',
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

/// The emoji themselves, drawn the same way on touch and pointer surfaces.
class ReactionGrid extends StatelessWidget {
  ReactionGrid({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.post,
    required this.onPicked,
  }) : _ownerContext = null,
       _session = controller.beginPicker(siteUrl, post);

  const ReactionGrid._withSession(
    this._session,
    this._ownerContext, {
    required this.controller,
    required this.siteUrl,
    required this.post,
    required this.onPicked,
  });

  static const int columns = 6;
  static const double cell = 44;

  final ReactionsController controller;
  final BuildContext? _ownerContext;
  final String siteUrl;
  final Post post;
  final VoidCallback onPicked;
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

    final settings = config.reactionsSettings;
    if (settings.offeredReactions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Still finding out which reactions this site allows.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final grid = Wrap(
      children: [
        for (final id in settings.offeredReactions)
          _ReactionCell(
            id: id,
            url: controller.emojiUrlFor(siteUrl, id),
            held: id == held,
            onTap: () {
              final messenger = ScaffoldMessenger.maybeOf(context);
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
                messenger,
                controller,
                _session,
                controller.toggleFromPicker(_session, target, id),
                stillOwnsUi: () =>
                    !ownerContext.mounted ||
                    _stillOwnsUi(ownerContext, controller),
              );
            },
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
  ScaffoldMessengerState? messenger,
  ReactionsController controller,
  ReactionPickerSession session,
  Future<String?> work, {
  required bool Function() stillOwnsUi,
}) {
  unawaited(
    work.then((error) {
      if (error == null ||
          !controller.isPickerCurrent(session) ||
          messenger == null ||
          !messenger.mounted ||
          !stillOwnsUi()) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error)));
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: held,
      label: id,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(8),
        child: ExcludeSemantics(
          child: Container(
            width: ReactionGrid.cell,
            height: ReactionGrid.cell,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: held ? theme.colorScheme.primary : Colors.transparent,
              ),
            ),
            child: Center(
              child: EmojiImage(
                url: url,
                size: 22,
                alt: ':$id:',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
