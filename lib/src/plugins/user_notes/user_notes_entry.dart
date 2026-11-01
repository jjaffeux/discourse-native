import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'user_notes_controller.dart';
import 'user_notes_data.dart';
import 'user_notes_sheet.dart';

class UserNotesEntry extends StatefulWidget {
  const UserNotesEntry({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.userId,
    this.username,
    this.count,
    this.postId,
    this.placement,
  });
  final UserNotesController controller;
  final String siteUrl;
  final int userId;
  final String? username;
  final int? count;
  final int? postId;
  final PostAuthorDecorationPlacement? placement;
  @override
  State<UserNotesEntry> createState() => _UserNotesEntryState();
}

class _UserNotesEntryState extends State<UserNotesEntry> {
  @override
  void initState() {
    super.initState();
    widget.controller.observe(widget.siteUrl);
  }

  @override
  void didUpdateWidget(UserNotesEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.siteUrl != widget.siteUrl) {
      widget.controller.observe(widget.siteUrl);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (!controller.canOpen(widget.siteUrl)) return const SizedBox.shrink();
      final count = controller.count(
        widget.siteUrl,
        widget.userId,
        fallback: widget.count,
      );
      if (count == null || count <= 0) return const SizedBox.shrink();
      if (widget.placement case final placement?) {
        final target =
            controller.settings(widget.siteUrl).placement ==
                UserNotesPlacement.avatar
            ? PostAuthorDecorationPlacement.afterAvatar
            : context.isTouch
            ? PostAuthorDecorationPlacement.beforeName
            : PostAuthorDecorationPlacement.afterName;
        if (placement != target) return const SizedBox.shrink();
      }
      final emoji = controller.emoji;
      return DButton.iconOnly(
        tooltip: context.l10n.userNotesCount(count),
        icon:
            controller.site.siteConfigFor(widget.siteUrl).emojiEnabled &&
                emoji != null
            ? EmojiImage(
                url: emoji.resolveUrl(widget.siteUrl, 'memo'),
                size: 16,
                alt: context.l10n.userNotesTitle,
              )
            : const DIcon(DIcons.penToSquare),
        density: DButtonDensity.inlineMetadata,
        variant: DButtonVariant.inline,
        onPressed: () => unawaited(
          showUserNotes(
            context: context,
            controller: controller,
            siteUrl: widget.siteUrl,
            userId: widget.userId,
            username: widget.username,
            postId: widget.postId,
          ),
        ),
      );
    },
  );
}
