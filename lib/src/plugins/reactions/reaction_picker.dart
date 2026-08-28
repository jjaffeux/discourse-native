import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/site_lifecycle.dart';
import '../../models/post.dart';
import '../../shell/emoji.dart';
import '../../shell/emoji_picker.dart';
import '../../shell/shell_controller.dart';
import '../../shell/shell_scope.dart';
import '../../shell/shell_sheet.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import 'reaction.dart';
import 'reactions_emoji_usage.dart';
import 'reactions_shell_extension.dart';

/// Opens the policy-aware chooser for a post reaction affordance.
///
/// Most sites permit only their configured reaction set, which remains a
/// compact grid. A site that explicitly permits any emoji gets the complete
/// searchable catalog from both the post toolbar and the reaction-row smile
/// button instead.
Future<void> showPostReactionPicker(
  BuildContext context,
  String siteUrl,
  Post post,
) async {
  final controller = ShellScope.read(context);
  final emoji = PluginScope.require(context, reactionsEmojiHostService);
  final lease = controller.lifecycle.capture(siteUrl);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final config = await controller.resolveSiteConfig(siteUrl);
  if (!lease.isCurrent || !context.mounted) return;
  if (!identical(ShellScope.maybeRead(context), controller)) return;
  final current = controller.store.read<Post>(siteUrl, post.id);
  if (current == null || !current.canReact) return;
  if (config?.allowAnyEmoji != true) {
    return showReactionPicker(context, siteUrl, current, nested: false);
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
  if (picked == null || !lease.isCurrent) return;
  if (context.mounted &&
      !identical(ShellScope.maybeRead(context), controller)) {
    return;
  }
  final latest = controller.store.read<Post>(siteUrl, post.id);
  if (latest == null || !latest.canReact) return;

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
    lease,
    controller.toggleReaction(latest, picked, siteUrl: siteUrl),
  );
}

/// Offers the emoji a site allows, so a reader can give one.
///
/// Reached from the post's action menu, and from a populated row on a site that
/// limits reactions to this configured set. The menu is where the affordance
/// for a post nobody has reacted to lives — the row underneath draws nothing
/// until somebody has, exactly as the like count does.
///
/// Two surfaces. Touch gets a sheet; the menu caller asks for a nested one so
/// the action sheet remains behind it, while the row caller opens a top-level
/// sheet. A pointer gets a modal card rather than a popup anchored to the menu
/// button — the menu closes the instant the pointer leaves it, by design and
/// with a comment saying so, and an anchored picker would have to reach in and
/// suspend that. Anchoring it is worth doing; it is not worth doing by making
/// the action menu's close rule conditional.
Future<void> showReactionPicker(
  BuildContext context,
  String siteUrl,
  Post post, {
  bool nested = true,
}) {
  final controller = ShellScope.read(context);
  final session = _ReactionPickerSession(
    controller: controller,
    lease: controller.lifecycle.capture(siteUrl),
    storeBacked: controller.store.read<Post>(siteUrl, post.id) != null,
  );
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
        session,
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
            session,
            siteUrl: siteUrl,
            post: post,
            onPicked: Navigator.of(dialogContext).pop,
          ),
        ),
      ),
    ),
  );
}

/// The emoji themselves, drawn the same way on both surfaces.
class ReactionGrid extends StatelessWidget {
  const ReactionGrid({
    super.key,
    required this.siteUrl,
    required this.post,
    required this.onPicked,
  }) : _session = null;

  const ReactionGrid._withSession(
    this._session, {
    required this.siteUrl,
    required this.post,
    required this.onPicked,
  });

  /// Wide enough to read as a palette rather than a list, narrow enough that
  /// the default six offered reactions fit on one row.
  static const int columns = 6;

  /// Apple's floor and Material's. Every cell here writes.
  static const double cell = 44;

  final String siteUrl;
  final Post post;
  final VoidCallback onPicked;
  final _ReactionPickerSession? _session;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<Object>(
      select: (controller) => controller.presentationTokenFor(siteUrl),
      builder: (context, _, child) => _buildGrid(context),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final theme = Theme.of(context);
    final presentationController = ShellScope.read(context);
    final interactionController =
        _session?.controller ?? presentationController;
    final config = presentationController.siteConfigFor(siteUrl);
    final storedPost = interactionController.store.read<Post>(siteUrl, post.id);
    final storeBacked = _session?.storeBacked ?? storedPost != null;
    final current = storedPost ?? (storeBacked ? null : post);
    final held = current?.reactions?.mine?.id;

    // Empty until the site's settings have landed, and on a site that would not
    // answer for them. Saying so is better than an empty box that reads as a
    // site with no reactions configured at all.
    if (config.offeredReactions.isEmpty) {
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
        for (final id in config.offeredReactions)
          _ReactionCell(
            id: id,
            url: presentationController.emojiUrlFor(siteUrl, id),
            held: id == held,
            onTap: () {
              final messenger = ScaffoldMessenger.maybeOf(context);
              final lease =
                  _session?.lease ??
                  interactionController.lifecycle.capture(siteUrl);
              final stillOwnsInteraction =
                  lease.isCurrent &&
                  identical(
                    ShellScope.maybeRead(context),
                    interactionController,
                  );
              onPicked();
              if (!stillOwnsInteraction) return;
              final latest = interactionController.store.read<Post>(
                siteUrl,
                post.id,
              );
              // A standalone grid can be handed a post directly. A grid that
              // started from the identity map must not resurrect that post if
              // a live update removes it while the dialog is open.
              final target = latest ?? (storeBacked ? null : post);
              if (target == null || !target.canReact) return;
              _report(
                messenger,
                interactionController,
                lease,
                interactionController.toggleReaction(
                  target,
                  id,
                  siteUrl: siteUrl,
                ),
              );
            },
          ),
      ],
    );

    // The site draws its own picker desaturated when it is asked to; matching
    // that is the difference between the app looking like the site and looking
    // like something else pointed at it.
    if (!config.desaturatedReactionPanel) return grid;
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

void _report(
  ScaffoldMessengerState? messenger,
  ShellController controller,
  SiteLease lease,
  Future<String?> work,
) {
  unawaited(
    work.then((error) {
      if (error == null ||
          !lease.isCurrent ||
          messenger == null ||
          !messenger.mounted) {
        return;
      }
      if (!identical(ShellScope.maybeRead(messenger.context), controller)) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }),
  );
}

final class _ReactionPickerSession {
  const _ReactionPickerSession({
    required this.controller,
    required this.lease,
    required this.storeBacked,
  });

  final ShellController controller;
  final SiteLease lease;
  final bool storeBacked;
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

  /// Whether this is the one the reader already gave.
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
