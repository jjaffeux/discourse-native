import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'boards_data.dart';

class BoardReaderCard extends StatelessWidget {
  const BoardReaderCard({
    super.key,
    required this.site,
    required this.board,
    required this.card,
    required this.onPressed,
    this.category,
    this.menu,
    this.selected = false,
  });
  final String site;
  final BoardSnapshot board;
  final BoardCard card;
  final ({String name, int color})? category;
  final Widget? menu;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final category = this.category;
    final columnTags = {
      for (final column in board.columns) column.tagName.toLowerCase(),
    };
    final tags = [
      if (card.kind != BoardCardKind.topic || board.showTags)
        for (final tag in card.tags)
          if (!columnTags.contains(tag.toLowerCase())) tag,
    ];
    final author = card.activityUser?.username;
    return DItem(
      shape: DItemShape.card,
      variant: DItemVariant.outline,
      selected: selected,
      selectionStyle: DItemSelectionStyle.outline,
      showSelectionIndicator: false,
      onPressed: onPressed,
      footer:
          board.detailed &&
              (card.activityAt != null ||
                  author != null ||
                  card.assignee.isNotEmpty ||
                  card.assignees.isNotEmpty)
          ? DItemFooter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (card.activityAt case final date?)
                          relativeTime(date),
                        if (author != null) '($author)',
                        if (card.assignees.isEmpty && card.assignee.isNotEmpty)
                          card.assignee,
                      ].join(' '),
                      style: TextStyle(color: tokens.mutedForeground),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (card.assignees.isNotEmpty)
                    DAvatarGroup(
                      children: [
                        for (final user in card.assignees.take(3))
                          _avatar(user),
                      ],
                    ),
                ],
              ),
            )
          : null,
      children: [
        DItemContent(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DItemTitle(
                    maxLines: null,
                    child: Text(
                      card.title.isEmpty
                          ? context.l10n.boardsUnsupported
                          : card.title,
                    ),
                  ),
                ),
                if (menu != null) const SizedBox(width: 4),
                ?menu,
              ],
            ),
            if (board.showThumbnail && card.imageUrl.isNotEmpty)
              SiteImage(
                siteUrl: site,
                url: card.imageUrl,
                width: 260,
                height: 120,
                fit: BoxFit.cover,
              ),
            if (board.detailed && card.notes.isNotEmpty)
              Text(card.notes, maxLines: 3, overflow: TextOverflow.ellipsis),
            if (tags.isNotEmpty)
              Text(
                tags.join(', '),
                style: TextStyle(color: tokens.mutedForeground),
              ),
            if (board.detailed && category != null)
              Row(
                children: [
                  DIcon(DIcons.tag, size: 9, color: Color(category.color)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      category.name,
                      style: TextStyle(color: tokens.mutedForeground),
                    ),
                  ),
                ],
              ),
            if (card.closed) Text(context.l10n.closed),
          ],
        ),
      ],
    );
  }

  Widget _avatar(BoardCreator user) {
    final url = resolveAvatarUrl(user.avatarTemplate, site, size: 44);
    return DAvatar(
      dimension: 22,
      semanticLabel: user.username,
      fallback: DAvatarFallback(
        child: Text(user.username.characters.first.toUpperCase()),
      ),
      child: url == null
          ? null
          : SiteImage(
              siteUrl: site,
              url: url,
              width: 22,
              height: 22,
              fit: BoxFit.cover,
            ),
    );
  }
}
