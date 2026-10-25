import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

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
  final _horizontal = ScrollController();
  final _vertical = <int, ScrollController>{};
  final _lists = <int, ListController>{};
  final _cardKeys = <int, GlobalKey>{};
  int? _highlighted;
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
    setState(() {
      _directoryLoading = true;
      _directoryError = null;
    });
    try {
      await widget.controller.loadDirectory(widget.site);
    } catch (error) {
      if (mounted) _directoryError = error.toString();
    }
    if (mounted) setState(() => _directoryLoading = false);
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
                if (card.notes.isNotEmpty)
                  Text(
                    card.notes,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (card.tags.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final tag in card.tags) DBadge(child: Text(tag)),
                    ],
                  ),
                if (card.assignee.isNotEmpty) Text(card.assignee),
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
          column.order == BoardColumnOrder.priority,
      onMove: (_, _) {},
      onLeave: () {},
      onDrop: (data, _) => _move(data.cardId, column.id, PlaceAfter(card.id)),
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
        child: item,
      ),
    );
  }

  Widget _menu(BoardSnapshot board, BoardColumn column, BoardCard card) =>
      DDropdownMenu(
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
            DDropdownMenuItem(
              onPressed: () async {
                final confirmed = await _confirm(context.l10n.boardsRemoveCard);
                if (confirmed) _report(await _handle!.removeCard(card.id));
              },
              child: Text(context.l10n.delete),
            ),
          ],
        ),
        child: DDropdownMenuTrigger.button(label: Text(context.l10n.edit)),
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
                  label: Text(context.l10n.save),
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
    final selection = await showDDialog<(int, CardPlacement)>(
      context: context,
      builder: (context, dialog) => _MovePicker(
        board: board,
        card: card,
        onChosen: (id, placement) => dialog.close((id, placement)),
      ),
    );
    if (selection != null && mounted) {
      await _move(card.id, selection.$1, selection.$2);
    }
  }

  Future<BoardRepair?> _review(
    BoardSnapshot board,
    BoardColumn column,
    BoardConstraintCheck check,
  ) => showDDialog<BoardRepair>(
    context: context,
    builder: (context, dialog) => _MoveReview(
      board: board,
      column: column,
      check: check,
      controller: widget.controller,
      site: widget.site,
      onChosen: dialog.close,
    ),
  );
  Future<void> _edit(BoardColumn column, {BoardCard? card}) async {
    final handle = _handle;
    if (handle == null) return;
    final result = await showDDialog<BoardWriteResult>(
      context: context,
      builder: (context, dialog) => _CardEditor(
        handle: handle,
        column: column,
        card: card,
        onSaved: dialog.close,
      ),
    );
    if (result != null) _report(result);
  }

  Future<void> _addTopic(BoardColumn column) async {
    final input = TextEditingController();
    final value = await showDDialog<String>(
      context: context,
      builder: (context, dialog) => DDialogContent(
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
    );
    input.dispose();
    if (value == null || !mounted) return;
    final id =
        int.tryParse(value.trim()) ??
        int.tryParse(
          RegExp(r'/t/(?:[^/]+/)?([0-9]+)').firstMatch(value)?.group(1) ?? '',
        );
    if (id == null) {
      _report(const BoardWriteResult(BoardWriteState.refused));
      return;
    }
    _report(await _handle!.addTopic(id, column.id, review: _review));
  }
}

final class _BoardDrag {
  const _BoardDrag(this.site, this.boardId, this.cardId);
  final String site;
  final int boardId, cardId;
}

Future<void> addTopicToBoard(
  BuildContext context,
  BoardsController controller,
  String site,
  int topicId,
  List<BoardSnapshot> boards,
) async {
  final selected = await showDDialog<(int, int)>(
    context: context,
    builder: (context, dialog) => DDialogContent(
      children: [
        Text(context.l10n.boardsAddTopic),
        for (final board in boards) ...[
          Text(board.name),
          for (final column in board.columns)
            DButton(
              label: Text(column.title),
              onPressed: () => dialog.close((board.id, column.id)),
            ),
        ],
        if (boards.isEmpty) Text(context.l10n.boardsNoBoards),
      ],
    ),
  );
  if (selected == null || !context.mounted || !controller.enabled(site)) return;
  final handle = controller.acquire(site, selected.$1);
  try {
    await handle.refresh();
    if (!context.mounted || !handle.canWrite) return;
    final result = await handle.addTopic(
      topicId,
      selected.$2,
      review: (board, column, check) => showDDialog<BoardRepair>(
        context: context,
        builder: (context, dialog) => _MoveReview(
          board: board,
          column: column,
          check: check,
          controller: controller,
          site: site,
          onChosen: dialog.close,
        ),
      ),
    );
    if (context.mounted &&
        result.state != BoardWriteState.saved &&
        result.state != BoardWriteState.cancelled) {
      DToast.show(
        context,
        result.error ??
            (result.saved
                ? context.l10n.boardsSavedRefresh
                : context.l10n.boardsRefused),
      );
    }
  } finally {
    handle.release();
  }
}

class _MovePicker extends StatefulWidget {
  const _MovePicker({
    required this.board,
    required this.card,
    required this.onChosen,
  });
  final BoardSnapshot board;
  final BoardCard card;
  final void Function(int, CardPlacement) onChosen;
  @override
  State<_MovePicker> createState() => _MovePickerState();
}

class _MovePickerState extends State<_MovePicker> {
  late int _column = widget.card.columnId;
  int _after = -1;
  @override
  Widget build(BuildContext context) {
    final column = widget.board.column(_column)!;
    return DDialogContent(
      children: [
        Text(context.l10n.boardsMoveTo),
        DSelect<int>.controlled(
          value: _column,
          label: Text(context.l10n.boardsColumn),
          entries: [
            for (final column in widget.board.columns)
              if (column.order != BoardColumnOrder.unsupported)
                DSelectItem(
                  value: column.id,
                  child: Text(column.title),
                  textValue: column.title,
                ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _column = value;
                _after = -1;
              });
            }
          },
        ),
        if (column.order == BoardColumnOrder.priority)
          DSelect<int>.controlled(
            value: _after,
            label: Text(context.l10n.boardsPlacement),
            entries: [
              DSelectItem(
                value: -1,
                child: Text(context.l10n.boardsLast),
                textValue: context.l10n.boardsLast,
              ),
              DSelectItem(
                value: 0,
                child: Text(context.l10n.boardsFirst),
                textValue: context.l10n.boardsFirst,
              ),
              for (final card in column.cards)
                if (card.id != widget.card.id)
                  DSelectItem(
                    value: card.id,
                    child: Text(card.title),
                    textValue: card.title,
                  ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _after = value);
            },
          ),
        DDialogFooter(
          children: [
            DButton(
              label: Text(context.l10n.move),
              onPressed:
                  column.order == BoardColumnOrder.recency &&
                      _column == widget.card.columnId
                  ? null
                  : () => widget.onChosen(
                      _column,
                      _after == -1
                          ? const PlaceLast()
                          : _after == 0
                          ? const PlaceFirst()
                          : PlaceAfter(_after),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MoveReview extends StatefulWidget {
  const _MoveReview({
    required this.board,
    required this.column,
    required this.check,
    required this.controller,
    required this.site,
    required this.onChosen,
  });
  final BoardSnapshot board;
  final BoardColumn column;
  final BoardConstraintCheck check;
  final BoardsController controller;
  final String site;
  final ValueChanged<BoardRepair> onChosen;
  @override
  State<_MoveReview> createState() => _MoveReviewState();
}

class _MoveReviewState extends State<_MoveReview> {
  int? _category;
  String? _tag;
  @override
  Widget build(BuildContext context) => DDialogContent(
    children: [
      Text(context.l10n.boardsMoveReview),
      Text(widget.column.title),
      Text(context.l10n.boardsMoveEffects),
      if (widget.column.tagName.isNotEmpty) Text('#${widget.column.tagName}'),
      if (widget.column.moveStatus.isNotEmpty) Text(widget.column.moveStatus),
      if (widget.column.moveAssigned.isNotEmpty)
        Text(widget.column.moveAssigned),
      if (widget.check.categoryIds.isNotEmpty)
        DSelect<int>.controlled(
          value: _category,
          label: Text(context.l10n.boardsRequiredCategory),
          entries: [
            for (final id in widget.check.categoryIds)
              DSelectItem(
                value: id,
                child: Text(
                  widget.controller.siteState.categoryFor
                          ?.call(widget.site, id)
                          ?.name ??
                      '#$id',
                ),
                textValue:
                    widget.controller.siteState.categoryFor
                        ?.call(widget.site, id)
                        ?.name ??
                    '#$id',
              ),
          ],
          onChanged: (value) => setState(() => _category = value),
        ),
      if (widget.check.tagNames.isNotEmpty)
        DSelect<String>.controlled(
          value: _tag,
          label: Text(context.l10n.boardsRequiredTag),
          entries: [
            for (final tag in widget.check.tagNames)
              DSelectItem(value: tag, child: Text(tag), textValue: tag),
          ],
          onChanged: (value) => setState(() => _tag = value),
        ),
      DDialogFooter(
        children: [
          DButton(
            label: Text(context.l10n.move),
            onPressed:
                (widget.check.categoryIds.isEmpty || _category != null) &&
                    (widget.check.tagNames.isEmpty || _tag != null)
                ? () => widget.onChosen(
                    BoardRepair(
                      categoryId: _category,
                      tagNames: _tag == null ? const [] : [_tag!],
                    ),
                  )
                : null,
          ),
        ],
      ),
    ],
  );
}

class _CardEditor extends StatefulWidget {
  const _CardEditor({
    required this.handle,
    required this.column,
    required this.card,
    required this.onSaved,
  });
  final BoardHandle handle;
  final BoardColumn column;
  final BoardCard? card;
  final ValueChanged<BoardWriteResult> onSaved;
  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  late final _title = TextEditingController(text: widget.card?.title);
  late final _notes = TextEditingController(text: widget.card?.notes);
  late final _tags = TextEditingController(text: widget.card?.tags.join(', '));
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.handle.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.handle.removeListener(_changed);
    _title.dispose();
    _notes.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.handle.enabled || widget.handle.snapshot == null) {
      return DDialogContent(children: [Text(context.l10n.boardsRefused)]);
    }
    final writable =
        widget.handle.canWrite &&
        widget.card?.kind != BoardCardKind.unsupported;
    return DDialogContent(
      children: [
        Text(
          widget.card == null ? context.l10n.boardsNewCard : context.l10n.edit,
        ),
        DInput(
          controller: _title,
          labelText: context.l10n.title,
          enabled: writable && !_saving,
          onChanged: (_) => setState(() {}),
        ),
        DTextarea(
          controller: _notes,
          labelText: context.l10n.boardsNotes,
          minLines: 3,
          maxLines: 8,
          enabled: writable && !_saving,
        ),
        DInput(
          controller: _tags,
          labelText: context.l10n.boardsTags,
          enabled: writable && !_saving,
        ),
        if (_error != null) Text(_error!),
        DDialogFooter(
          children: [
            DButton(
              label: Text(context.l10n.save),
              onPressed: writable && !_saving && _title.text.trim().isNotEmpty
                  ? () async {
                      setState(() => _saving = true);
                      final result = await widget.handle.saveStandalone(
                        widget.column.id,
                        _title.text,
                        _notes.text,
                        cardId: widget.card?.id,
                        tags: _tags.text
                            .split(',')
                            .map((tag) => tag.trim())
                            .where((tag) => tag.isNotEmpty)
                            .toList(),
                      );
                      if (!mounted) return;
                      if (result.saved) {
                        widget.onSaved(result);
                      } else {
                        setState(() {
                          _saving = false;
                          _error = result.error ?? context.l10n.boardsRefused;
                        });
                      }
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
