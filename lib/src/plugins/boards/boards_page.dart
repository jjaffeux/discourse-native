import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart' show SiteImage;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'board_card_editor.dart';
import 'board_move_dialog.dart';
import 'boards_controller.dart';
import 'boards_data.dart';
import 'boards_navigation.dart';

class BoardsPage extends StatefulWidget {
  const BoardsPage({
    super.key,
    required this.site,
    required this.route,
    required this.controller,
    required this.navigation,
  });
  final String site;
  final BoardsRoute route;
  final BoardsController controller;
  final BoardsNavigation navigation;
  @override
  State<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends State<BoardsPage> {
  BoardHandle? _handle;
  int? _column;
  String? _directoryError;
  bool _directoryLoading = false;
  Object? _directoryToken;
  final _horizontal = ScrollController();
  final _vertical = <int, ScrollController>{};
  final _lists = <int, ListController>{};
  final _cardKeys = <int, GlobalKey>{};
  int? _highlighted;
  int? _dropCard;
  void _setDrop(int? id) {
    if (mounted && _dropCard != id) setState(() => _dropCard = id);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _load();
  }

  @override
  void didUpdateWidget(BoardsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        oldWidget.route.boardId != widget.route.boardId) {
      _handle?.release();
      _handle = null;
      _column = null;
      _highlighted = null;
      _directoryToken = null;
      _directoryLoading = false;
      _directoryError = null;
      _load();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _load() {
    if (!widget.controller.enabled(widget.site)) return;
    if (widget.route.boardId case final id?) {
      _handle = widget.controller.acquire(widget.site, id);
    } else {
      unawaited(_directory());
    }
  }

  Future<void> _directory() async {
    if (_directoryLoading) return;
    final token = Object();
    final site = widget.site;
    _directoryToken = token;
    setState(() {
      _directoryLoading = true;
      _directoryError = null;
    });
    try {
      await widget.controller.loadDirectory(site);
    } catch (error) {
      if (mounted && identical(token, _directoryToken)) {
        _directoryError = error.toString();
      }
    }
    if (mounted && identical(token, _directoryToken)) {
      setState(() => _directoryLoading = false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _handle?.release();
    _horizontal.dispose();
    for (final controller in _vertical.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!widget.controller.enabled(widget.site)) {
      return Center(child: DEmpty(children: [Text(l10n.boardsDisabled)]));
    }
    final handle = _handle;
    if (handle == null) {
      return DPageSurface.headed(
        title: Text(l10n.boardsTitle),
        controls: DButton(
          label: Text(l10n.refresh),
          onPressed: _directoryLoading ? null : _directory,
        ),
        child: _directoryLoading
            ? const Center(child: DSpinner())
            : _directoryError != null
            ? Center(
                child: DEmpty(
                  children: [
                    Text(_directoryError!),
                    DButton(label: Text(l10n.retry), onPressed: _directory),
                  ],
                ),
              )
            : _directoryList(),
      );
    }
    final board = handle.snapshot;
    if (board == null) {
      return DPageSurface.headed(
        title: Text(l10n.boardsTitle),
        controls: DButton(
          label: Text(l10n.refresh),
          onPressed: handle.reading ? null : handle.refresh,
        ),
        child: handle.reading
            ? const Center(child: DSpinner())
            : Center(
                child: DEmpty(
                  children: [Text(handle.error ?? l10n.boardsNoBoards)],
                ),
              ),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 700;
    final column = board.column(_column ?? -1) ?? board.columns.firstOrNull;
    _column = column?.id;
    final linkedCard = board.card(widget.route.cardId ?? -1);
    if (_highlighted != widget.route.cardId && linkedCard != null) {
      _column = linkedCard.columnId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _highlighted = linkedCard.id;
        final column = board.column(linkedCard.columnId)!;
        if (_horizontal.hasClients) {
          _horizontal.jumpTo(
            (board.columns.indexOf(column) * 330.0).clamp(
              0.0,
              _horizontal.position.maxScrollExtent,
            ),
          );
        }
        final list = _lists[column.id];
        final scroll = _vertical[column.id];
        if (list != null &&
            list.isAttached &&
            scroll != null &&
            scroll.hasClients) {
          list.jumpToItem(
            index: column.cards.indexWhere((card) => card.id == linkedCard.id),
            scrollController: scroll,
            alignment: .3,
          );
        }
        setState(() {});
      });
    }
    return DPageSurface.headed(
      title: Text(board.name),
      controls: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (board.archived) DBadge(child: Text(l10n.boardsArchived)),
          if (compact && board.columns.isNotEmpty)
            DSelect<int>.controlled(
              value: _column,
              semanticLabel: l10n.boardsColumn,
              entries: [
                for (final value in board.columns)
                  DSelectItem(
                    value: value.id,
                    child: Text('${value.title} (${value.cards.length})'),
                    textValue: value.title,
                  ),
              ],
              onChanged: (value) => setState(() => _column = value),
            ),
          DButton(
            label: Text(l10n.refresh),
            onPressed: handle.reading || handle.writing ? null : handle.refresh,
          ),
          if (board.canManage)
            DButton(
              label: Text(l10n.openInBrowser),
              onPressed: () => widget.navigation.configure(widget.site, board),
            ),
          if (handle.reading || handle.writing) const DSpinner(),
        ],
      ),
      child: Column(
        children: [
          if (handle.error case final error?)
            Padding(padding: const EdgeInsets.all(8), child: Text(error)),
          if (widget.route.cardId != null && linkedCard == null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(l10n.boardsUnavailableCard),
            ),
          Expanded(
            child: board.columns.isEmpty
                ? Center(child: DEmpty(children: [Text(l10n.boardsNoCards)]))
                : compact
                ? _columnView(board, board.column(_column!)!)
                : LayoutBuilder(
                    builder: (context, constraints) => DScrollArea(
                      axes: DScrollAxes.horizontal,
                      controller: _horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final value in board.columns)
                            SizedBox(
                              width: 330,
                              height: constraints.maxHeight,
                              child: _columnView(board, value),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _directoryList() {
    final boards = widget.controller.directory(widget.site);
    if (boards.isEmpty) {
      return Center(
        child: DEmpty(children: [Text(context.l10n.boardsNoBoards)]),
      );
    }
    return ListView.builder(
      itemCount: boards.length,
      itemBuilder: (context, index) {
        final board = boards[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: DItem(
            onPressed: () => widget.navigation.open(board: board),
            children: [
              DItemContent(
                children: [
                  DItemTitle(child: Text(board.name)),
                  if (board.archived)
                    DItemDescription(child: Text(context.l10n.boardsArchived)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _columnView(BoardSnapshot board, BoardColumn column) {
    final handle = _handle!;
    final scroll = _vertical.putIfAbsent(column.id, ScrollController.new);
    final list = _lists.putIfAbsent(column.id, ListController.new);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  column.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              DBadge(child: Text('${column.cards.length}')),
            ],
          ),
          if (handle.canWrite && column.order != BoardColumnOrder.unsupported)
            Wrap(
              spacing: 8,
              children: [
                DButton(
                  label: Text(context.l10n.boardsNewCard),
                  onPressed: () => _edit(column),
                ),
                DButton(
                  label: Text(context.l10n.boardsAddTopic),
                  onPressed: () => _addTopic(column),
                ),
                if (widget.controller.composer != null)
                  DButton(
                    label: Text(
                      handle.createdTopic(column.id) == null
                          ? context.l10n.boardsNewTopic
                          : context.l10n.boardsAttachTopic,
                    ),
                    onPressed: handle.composing(column.id)
                        ? null
                        : () async {
                            if (handle.createdTopic(column.id) != null) {
                              _report(
                                await handle.attachCreatedTopic(column.id),
                              );
                            } else {
                              await handle.createTopic(
                                widget.route.id,
                                column.id,
                              );
                            }
                          },
                  ),
              ],
            ),
          if (column.order == BoardColumnOrder.unsupported)
            Text(context.l10n.boardsUnsupported),
          const SizedBox(height: 8),
          Expanded(
            child: column.cards.isEmpty
                ? DDragRegion<_BoardDrag>(
                    accepts: _accepts,
                    onMove: (_, _) {},
                    onDrop: (drag, _) =>
                        _move(drag.cardId, column.id, const PlaceFirst()),
                    onLeave: () {},
                    child: DCard(
                      child: DEmpty(
                        children: [Text(context.l10n.boardsNoCards)],
                      ),
                    ),
                  )
                : DScrollBar(
                    controller: scroll,
                    child: SuperListView.builder(
                      listController: list,
                      controller: scroll,
                      key: PageStorageKey(
                        'boards-${widget.site}-${board.id}-${column.id}',
                      ),
                      itemCount: column.cards.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _card(board, column, column.cards[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _accepts(_BoardDrag drag) =>
      _handle?.canWrite == true &&
      drag.site == widget.site &&
      drag.boardId == _handle?.id;
  Widget _card(BoardSnapshot board, BoardColumn column, BoardCard card) {
    final item = DItem(
      key: _cardKeys.putIfAbsent(card.id, GlobalKey.new),
      shape: DItemShape.card,
      variant: DItemVariant.outline,
      selected: widget.route.cardId == card.id,
      onPressed: card.kind == BoardCardKind.topic && card.topicId != null
          ? () => widget.navigation.openTopic(widget.site, card)
          : () => _edit(column, card: card),
      children: [
        DItemContent(
          children: [
            DItemTitle(
              child: Text(
                card.title.isEmpty
                    ? context.l10n.boardsUnsupported
                    : card.title,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (board.showThumbnail && card.imageUrl.isNotEmpty)
                  DItemMedia(
                    child: SiteImage(
                      siteUrl: widget.site,
                      url: card.imageUrl,
                      width: 260,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (board.detailed && card.notes.isNotEmpty)
                  Text(
                    card.notes,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (board.showTags && card.tags.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final tag in card.tags) DBadge(child: Text(tag)),
                    ],
                  ),
                if (board.detailed && card.assignee.isNotEmpty)
                  Text(card.assignee),
                if (card.closed) Text(context.l10n.closed),
              ],
            ),
          ],
        ),
        if (_handle!.canWrite && card.kind != BoardCardKind.unsupported)
          _menu(board, column, card),
      ],
    );
    if (!_handle!.canWrite ||
        card.kind == BoardCardKind.unsupported ||
        column.order == BoardColumnOrder.unsupported) {
      return item;
    }
    final drag = _BoardDrag(widget.site, board.id, card.id);
    return DDragRegion<_BoardDrag>(
      accepts: (data) =>
          _accepts(data) &&
          data.cardId != card.id &&
          (column.order == BoardColumnOrder.priority ||
              board.card(data.cardId)?.columnId != column.id),
      onMove: (_, _) => _setDrop(card.id),
      onLeave: () => _setDrop(null),
      onDrop: (data, _) {
        _setDrop(null);
        unawaited(
          _move(
            data.cardId,
            column.id,
            column.order == BoardColumnOrder.recency
                ? const PlaceLast()
                : PlaceAfter(card.id),
          ),
        );
      },
      child: DContentDrag(
        data: drag,
        feedback: SizedBox(
          width: 290,
          child: DCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(card.title),
            ),
          ),
        ),
        onDragEnd: () => _setDrop(null),
        child: Stack(
          children: [
            item,
            if (_dropCard == card.id)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DDropIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _menu(
    BoardSnapshot board,
    BoardColumn column,
    BoardCard card,
  ) => DDropdownMenu(
    sheetOnMobile: true,
    content: DDropdownMenuContent(
      children: [
        DDropdownMenuItem(
          onPressed: () => _moveDialog(board, card),
          child: Text(context.l10n.boardsMoveTo),
        ),
        if (card.kind == BoardCardKind.standalone)
          DDropdownMenuItem(
            onPressed: () => _edit(column, card: card),
            child: Text(context.l10n.edit),
          ),
        if (card.kind == BoardCardKind.standalone &&
            widget.controller.composer != null)
          DDropdownMenuItem(
            onPressed: _handle!.composing(column.id, cardId: card.id)
                ? null
                : () async {
                    if (_handle!.createdTopic(column.id, cardId: card.id) !=
                        null) {
                      _report(
                        await _handle!.attachCreatedTopic(
                          column.id,
                          cardId: card.id,
                        ),
                      );
                    } else {
                      await _handle!.createTopic(
                        widget.route.id,
                        column.id,
                        cardId: card.id,
                      );
                    }
                  },
            child: Text(
              _handle!.createdTopic(column.id, cardId: card.id) == null
                  ? context.l10n.boardsConvertTopic
                  : context.l10n.boardsAttachTopic,
            ),
          ),
        DDropdownMenuItem(
          onPressed: () async {
            final handle = _handle!;
            final lease = widget.controller.requests.capture(widget.site);
            final revision = widget.controller.accountRevision(widget.site);
            final confirmed = await _confirm(context.l10n.boardsRemoveCard);
            if (confirmed &&
                identical(handle, _handle) &&
                widget.controller.sourceCurrent(widget.site, lease, revision)) {
              _report(await handle.removeCard(card.id));
            }
          },
          child: Text(context.l10n.delete),
        ),
      ],
    ),
    child: DDropdownMenuTrigger.button(label: Text(context.l10n.moreActions)),
  );
  Future<bool> _confirm(String message) async =>
      await showDDialog<bool>(
        context: context,
        builder: (context, dialog) => DDialogContent(
          children: [
            Text(message),
            DDialogFooter(
              children: [
                DButton(
                  label: Text(context.l10n.cancel),
                  onPressed: () => dialog.close(false),
                ),
                DButton(
                  label: Text(context.l10n.delete),
                  variant: DButtonVariant.destructive,
                  onPressed: () => dialog.close(true),
                ),
              ],
            ),
          ],
        ),
      ) ??
      false;
  void _report(BoardWriteResult result) {
    if (!mounted ||
        result.state == BoardWriteState.saved ||
        result.state == BoardWriteState.cancelled) {
      return;
    }
    DToast.show(
      context,
      result.error ??
          switch (result.state) {
            BoardWriteState.refreshNeeded => context.l10n.boardsSavedRefresh,
            BoardWriteState.unknown => context.l10n.boardsUnknownWrite,
            _ => context.l10n.boardsRefused,
          },
    );
  }

  Future<void> _move(int cardId, int columnId, CardPlacement placement) async {
    final handle = _handle;
    if (handle != null) {
      _report(await handle.move(cardId, columnId, placement, review: _review));
    }
  }

  Future<void> _moveDialog(BoardSnapshot board, BoardCard card) async {
    final handle = _handle!;
    final lease = widget.controller.requests.capture(widget.site);
    final revision = widget.controller.accountRevision(widget.site);
    final selection = await showDDialog<(int, CardPlacement)>(
      context: context,
      builder: (context, dialog) => boardDialogGuard(
        widget.controller,
        widget.site,
        lease,
        revision,
        BoardMovePicker(
          board: board,
          card: card,
          onChosen: (id, placement) => dialog.close((id, placement)),
        ),
        sourceCurrent: () => handle.enabled && handle.snapshot != null,
      ),
    );
    if (selection != null &&
        mounted &&
        identical(handle, _handle) &&
        widget.controller.sourceCurrent(widget.site, lease, revision)) {
      _report(
        await handle.move(card.id, selection.$1, selection.$2, review: _review),
      );
    }
  }

  Future<BoardRepair?> _review(
    BoardSnapshot board,
    BoardColumn column,
    BoardConstraintCheck check,
  ) {
    final lease = widget.controller.requests.capture(widget.site);
    final revision = widget.controller.accountRevision(widget.site);
    return showDDialog<BoardRepair>(
      context: context,
      builder: (context, dialog) => boardDialogGuard(
        widget.controller,
        widget.site,
        lease,
        revision,
        BoardMoveReview(
          board: board,
          column: column,
          check: check,
          controller: widget.controller,
          site: widget.site,
          onChosen: dialog.close,
        ),
        sourceCurrent: () =>
            _handle?.enabled == true && _handle?.snapshot != null,
      ),
    );
  }

  Future<void> _edit(BoardColumn column, {BoardCard? card}) async {
    final handle = _handle;
    if (handle == null) return;
    final lease = widget.controller.requests.capture(widget.site);
    final revision = widget.controller.accountRevision(widget.site);
    final result = await showDDialog<BoardWriteResult>(
      context: context,
      builder: (context, dialog) => boardDialogGuard(
        widget.controller,
        widget.site,
        lease,
        revision,
        BoardCardEditor(
          handle: handle,
          column: column,
          card: card,
          onSaved: dialog.close,
        ),
        sourceCurrent: () => handle.enabled && handle.snapshot != null,
      ),
    );
    if (result != null) _report(result);
  }

  Future<void> _addTopic(BoardColumn column) async {
    final handle = _handle!;
    final lease = widget.controller.requests.capture(widget.site);
    final revision = widget.controller.accountRevision(widget.site);
    final input = TextEditingController();
    final value = await showDDialog<String>(
      context: context,
      builder: (context, dialog) => boardDialogGuard(
        widget.controller,
        widget.site,
        lease,
        revision,
        DDialogContent(
          children: [
            Text(context.l10n.boardsAddTopic),
            DInput(
              controller: input,
              labelText: context.l10n.boardsTopicId,
              autofocus: true,
            ),
            DDialogFooter(
              children: [
                DButton(
                  label: Text(context.l10n.cancel),
                  onPressed: () => dialog.close(),
                ),
                DButton(
                  label: Text(context.l10n.save),
                  onPressed: () => dialog.close(input.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (value == null ||
        !mounted ||
        !identical(handle, _handle) ||
        !widget.controller.sourceCurrent(widget.site, lease, revision)) {
      return;
    }
    final id =
        int.tryParse(value.trim()) ??
        int.tryParse(
          RegExp(r'/t/(?:[^/]+/)?([0-9]+)').firstMatch(value)?.group(1) ?? '',
        );
    if (id == null) {
      _report(const BoardWriteResult(BoardWriteState.refused));
      return;
    }
    _report(await handle.addTopic(id, column.id, review: _review));
  }
}

final class _BoardDrag {
  const _BoardDrag(this.site, this.boardId, this.cardId);
  final String site;
  final int boardId, cardId;
}
