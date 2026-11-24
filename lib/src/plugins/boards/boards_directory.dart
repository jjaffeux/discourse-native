import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'boards_data.dart';

const _directoryGutter = EdgeInsets.symmetric(horizontal: 16);
const _activeRowPadding = EdgeInsetsDirectional.fromSTEB(3, 12, 0, 12);
const _rowTextSpacing = 3.0;

class BoardsDirectory extends StatefulWidget {
  const BoardsDirectory({
    super.key,
    required this.site,
    required this.boards,
    required this.loaded,
    required this.error,
    required this.onRefresh,
    required this.onOpen,
  });

  final String site;
  final List<BoardSnapshot> boards;

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
  _BoardStatus _status = _BoardStatus.active;

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
      return words.every(board.name.toLowerCase().contains);
    }).toList();
    return DPageSurface.headed(
      identity: widget.site,
      title: Text(l10n.boardsTitle),
      controls: DControlWrap(
        wrap: false,
        children: [
          DControlExpanded(
            child: DInputGroup(
              variant: DInputGroupVariant.quiet,
              size: DControlSize.filter,
              children: [
                DInput(
                  value: _query,
                  hintText: l10n.boardsFilter,
                  semanticLabel: l10n.boardsFilter,
                  onChanged: (value) => setState(() => _query = value),
                ),
                const DInputGroupAddon(child: DIcon(DIcons.magnifyingGlass)),
                if (_query.isNotEmpty)
                  DInputGroupAddon(
                    alignment: DInputGroupAddonAlignment.inlineEnd,
                    child: DInputGroupButton.icon(
                      icon: const DIcon(DIcons.xmark),
                      tooltip: l10n.clearSearch,
                      onPressed: () => setState(() => _query = ''),
                    ),
                  ),
              ],
            ),
          ),
          DDropdownMenu(
            sheetOnMobile: true,
            mobileSheetVariant: DSheetVariant.adaptiveMenu,
            content: DDropdownMenuContent(
              width: 240,
              semanticLabel: l10n.boardsStatus,
              children: [
                DDropdownMenuRadioGroup<_BoardStatus>(
                  value: _status,
                  onChanged: (value) => setState(() => _status = value),
                  children: [
                    for (final status in _BoardStatus.values)
                      DDropdownMenuRadioItem(
                        value: status,
                        closeOnSelect: true,
                        child: Text(_statusLabel(status)),
                      ),
                  ],
                ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, state) => DButton(
                size: DControlSize.filter,
                variant: DButtonVariant.quiet,
                label: Text(_statusLabel(_status)),
                semanticLabel: '${l10n.boardsStatus}: ${_statusLabel(_status)}',
                focusNode: state.focusNode,
                hasPopup: true,
                expanded: state.open,
                onPressed: state.toggle,
              ),
            ),
          ),
        ],
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
                  EdgeInsets.only(
                    bottom: 16 + DScrollChrome.bottomInsetOf(context),
                  ),
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    if (loading)
                      SliverPadding(
                        padding: _directoryGutter,
                        sliver: SliverList.builder(
                          itemCount: 6,
                          itemBuilder: (context, index) => DSkeletonRegion(
                            semanticsLabel: l10n.loading,
                            liveRegion: index == 0,
                            color: skeletonFill(context),
                            child: const DItem(
                              padding: _activeRowPadding,
                              children: [
                                DItemContent(
                                  spacing: _rowTextSpacing,
                                  children: [
                                    DSkeleton(width: 136, height: 14),
                                    DSkeleton(width: 190, height: 12),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (widget.error case final error? when !widget.loaded)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: _directoryGutter,
                            child: DEmpty(
                              children: [
                                Text(error),
                                DButton(
                                  label: Text(l10n.retry),
                                  onPressed: () =>
                                      unawaited(widget.onRefresh()),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else ...[
                      if (widget.error case final error?)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: _directoryGutter.copyWith(bottom: 12),
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
                            child: Padding(
                              padding: _directoryGutter,
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
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: boards.length,
                          itemBuilder: (context, index) => _BoardDirectoryRow(
                            key: ValueKey(boards[index].id),
                            board: boards[index],
                            hasPrevious: index > 0,
                            nextArchived: index + 1 < boards.length
                                ? boards[index + 1].archived
                                : null,
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

class _BoardDirectoryRow extends StatelessWidget {
  const _BoardDirectoryRow({
    super.key,
    required this.board,
    required this.hasPrevious,
    required this.nextArchived,
    required this.onPressed,
  });

  final BoardSnapshot board;
  final bool hasPrevious;
  final bool? nextArchived;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: board.archived
        ? const EdgeInsets.symmetric(horizontal: 4)
        : _directoryGutter,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DItem(
          shape: DItemShape.fullWidth,
          padding: board.archived
              ? const EdgeInsetsDirectional.fromSTEB(15, 12, 12, 12)
              : _activeRowPadding,
          closed: board.archived,
          closedRuleAbove: board.archived && hasPrevious,
          closedRuleBelow: board.archived && nextArchived == false,
          onPressed: onPressed,
          children: [
            DItemContent(
              spacing: _rowTextSpacing,
              children: [
                DItemTitle(
                  child: Row(
                    spacing: 5,
                    children: [
                      if (board.archived)
                        DIcon(
                          DIcons.lock,
                          size: 11,
                          semanticLabel: context.l10n.boardsArchived,
                        ),
                      Flexible(child: Text(board.name)),
                    ],
                  ),
                ),
                if (board.columns.isNotEmpty)
                  DItemDescription(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        for (final column in board.columns)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 5,
                            children: [
                              if (boardColumnColor(column.color)
                                  case final color?)
                                DIcon(
                                  DNativeIcons.square,
                                  size: 8,
                                  color: color,
                                ),
                              Flexible(child: Text(column.title)),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (!board.archived && nextArchived == false) const DSeparator(),
      ],
    ),
  );
}
