import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'boards_data.dart';
import 'boards_navigation.dart';

class BoardsDirectory extends StatefulWidget {
  const BoardsDirectory({
    super.key,
    required this.site,
    required this.boards,
    required this.categories,
    required this.loaded,
    required this.error,
    required this.onRefresh,
    required this.onOpen,
  });

  final String site;
  final List<BoardSnapshot> boards;
  final Map<int, String> categories;

  /// Whether a read has finished for this account. Later reads keep the
  /// boards in place and report a failure above them.
  final bool loaded;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<BoardSnapshot> onOpen;

  @override
  State<BoardsDirectory> createState() => _BoardsDirectoryState();
}

enum _BoardStatus { all, active, archived }

class _BoardsDirectoryState extends State<BoardsDirectory> {
  String _query = '';
  _BoardStatus _status = _BoardStatus.all;

  String _statusLabel(_BoardStatus status) => switch (status) {
    _BoardStatus.all => context.l10n.boardsAll,
    _BoardStatus.active => context.l10n.boardsActive,
    _BoardStatus.archived => context.l10n.boardsArchivedFilter,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loading = !widget.loaded && widget.error == null;
    final words = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty);
    final boards = widget.boards.where((board) {
      if (_status == _BoardStatus.active && board.archived ||
          _status == _BoardStatus.archived && !board.archived) {
        return false;
      }
      final text = [
        board.name,
        ...board.tagNames,
        ...board.columns.map((column) => column.title),
        for (final id in board.categoryIds) widget.categories[id] ?? '',
      ].join(' ').toLowerCase();
      return words.every(text.contains);
    }).toList();
    return DPageSurface.headed(
      identity: widget.site,
      title: Text(l10n.boardsTitle),
      controls: LayoutBuilder(
        builder: (context, constraints) {
          final wrap =
              constraints.maxWidth < 520 ||
              MediaQuery.textScalerOf(context).scale(14) > 21;
          final search = DInput(
            size: DControlSize.field,
            value: _query,
            hintText: l10n.boardsFilter,
            semanticLabel: l10n.boardsFilter,
            prefix: const DIcon(DIcons.magnifyingGlass, size: 14),
            onChanged: (value) => setState(() => _query = value),
          );
          return DControlWrap(
            spacing: 8,
            runSpacing: 8,
            wrap: wrap,
            children: [
              if (wrap)
                SizedBox(width: constraints.maxWidth, child: search)
              else
                DControlExpanded(child: search),
              DSelect<_BoardStatus>.controlled(
                size: DControlSize.filter,
                value: _status,
                semanticLabel: l10n.boardsStatus,
                entries: [
                  for (final status in _BoardStatus.values)
                    DSelectOption(
                      value: status,
                      label: _statusLabel(status),
                      child: Text(_statusLabel(status)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
            ],
          );
        },
      ),
      bodyBuilder: (context, header) => DPullToRefresh(
        onRefresh: loading ? null : widget.onRefresh,
        child: ContentReadingLane(
          builder: (context, lane) => CustomScrollView(
            key: const PageStorageKey('boards-directory'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: header.spacer),
              SliverPadding(
                padding: lane.padding.add(
                  EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    16 + DScrollChrome.bottomInsetOf(context),
                  ),
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    if (loading)
                      DPlaceCardGrid(
                        itemCount: 6,
                        itemBuilder: (context, index) => DSkeletonRegion(
                          semanticsLabel: l10n.loading,
                          liveRegion: index == 0,
                          color: skeletonFill(context),
                          child: const DPlaceCardSkeleton(),
                        ),
                      )
                    else if (widget.error case final error? when !widget.loaded)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: DEmpty(
                            children: [
                              Text(error),
                              DButton(
                                label: Text(l10n.retry),
                                onPressed: () => unawaited(widget.onRefresh()),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      if (widget.error case final error?)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DAlert(
                              variant: DAlertVariant.destructive,
                              icon: const DIcon(DIcons.triangleExclamation),
                              description: DAlertDescription(
                                child: Text(error),
                              ),
                              action: DAlertAction(
                                child: DButton(
                                  label: Text(l10n.retry),
                                  variant: DButtonVariant.link,
                                  onPressed: () =>
                                      unawaited(widget.onRefresh()),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (boards.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: DEmpty(
                              children: [
                                Text(
                                  widget.boards.isEmpty
                                      ? l10n.boardsNoBoards
                                      : l10n.boardsNoMatches,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        DPlaceCardGrid(
                          itemCount: boards.length,
                          itemBuilder: (context, index) => _BoardDirectoryCard(
                            key: ValueKey(boards[index].id),
                            site: widget.site,
                            board: boards[index],
                            categories: widget.categories,
                            onPressed: () => widget.onOpen(boards[index]),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardDirectoryCard extends StatelessWidget {
  const _BoardDirectoryCard({
    super.key,
    required this.site,
    required this.board,
    required this.categories,
    required this.onPressed,
  });

  final String site;
  final BoardSnapshot board;
  final Map<int, String> categories;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final creator = board.createdBy;
    final avatar = resolveAvatarUrl(creator?.avatarTemplate, site, size: 40);
    return DPlaceCard(
      onPressed: onPressed,
      leading: DPlaceCardMark(
        color: DTokens.of(context).primary,
        child: const DIcon(boardsIcon, size: 13),
      ),
      title: Text(board.name),
      description:
          board.columns.isEmpty &&
              board.tagNames.isEmpty &&
              board.categoryIds.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                if (board.tagNames.isNotEmpty ||
                    board.categoryIds.any(categories.containsKey))
                  Text(
                    [
                      for (final id in board.categoryIds) ?categories[id],
                      ...board.tagNames,
                    ].join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (board.columns.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final column in board.columns)
                        DBadge(
                          variant: DBadgeVariant.secondary,
                          size: DBadgeSize.compact,
                          leading: DIcons.byName.containsKey(column.icon)
                              ? DIcon(DIcons.byName[column.icon]!, size: 12)
                              : null,
                          child: Text(
                            column.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
      footer: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (creator != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                DAvatar(
                  dimension: 16,
                  decorative: true,
                  fallback: const DAvatarFallback(
                    child: DIcon(DIcons.user, size: 12),
                  ),
                  child: avatar == null
                      ? null
                      : SiteImage(
                          siteUrl: site,
                          url: avatar,
                          width: 16,
                          height: 16,
                          fit: BoxFit.cover,
                        ),
                ),
                Flexible(
                  child: Text(
                    l10n.boardsCreatedBy(creator.username),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          Text(l10n.boardsColumnCount(board.columns.length)),
          if (!board.detailed) Text(l10n.boardsSimple),
          if (board.archived) Text(l10n.boardsArchived),
          if (board.anonymousCanRead == false)
            DIcon(DIcons.lock, size: 13, semanticLabel: l10n.boardsPrivate),
        ],
      ),
    );
  }
}
