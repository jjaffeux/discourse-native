import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../shell/emoji.dart';
import '../../shell/shell_scope.dart';
import '../../shell/shell_sheet.dart';
import '../../theme/app_theme.dart';
import 'reaction.dart';

/// Offers the emoji a site allows, so a reader can give one.
///
/// Reached from the post's action menu, which is where the affordance for a
/// post nobody has reacted to lives — the row underneath draws nothing until
/// somebody has, exactly as the like count does.
///
/// Two surfaces. Touch gets a nested sheet, which is the case `nested` was
/// built for: it is opened from inside the action sheet and leaves that one in
/// place behind it. A pointer gets a modal card rather than a popup anchored to
/// the menu button — the menu closes the instant the pointer leaves it, by
/// design and with a comment saying so, and an anchored picker would have to
/// reach in and suspend that. Anchoring it is worth doing; it is not worth
/// doing by making the action menu's close rule conditional.
Future<void> showReactionPicker(BuildContext context, Post post) {
  final isTouch = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  if (isTouch) {
    return showShellSheet<void>(
      context: context,
      title: 'React',
      nested: true,
      builder: (sheetContext) =>
          ReactionGrid(post: post, onPicked: Navigator.of(sheetContext).pop),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Theme.of(dialogContext).shell.floating,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ReactionGrid(
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
  const ReactionGrid({super.key, required this.post, required this.onPicked});

  /// Wide enough to read as a palette rather than a list, narrow enough that
  /// the default six offered reactions fit on one row.
  static const int columns = 6;

  /// Apple's floor and Material's. Every cell here writes.
  static const double cell = 44;

  final Post post;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);
    final siteUrl = controller.currentInstance?.url ?? '';
    final config = controller.currentSiteConfig;
    final held = post.reactions?.mine?.id;

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
            url: config.emojiUrl(id, siteUrl: siteUrl),
            held: id == held,
            onTap: () {
              onPicked();
              _report(context, controller.toggleReaction(post, id));
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

  static void _report(BuildContext context, Future<String?> work) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    work.then((error) {
      if (error == null) return;
      messenger?.showSnackBar(SnackBar(content: Text(error)));
    });
  }
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
        borderRadius: BorderRadius.circular(8),
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
    );
  }
}
