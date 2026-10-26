import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart' show DIcons;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'board_card_drag.dart';
import 'board_card_editor.dart';
import 'board_column_dialog.dart';
import 'board_column_panel.dart';
import 'board_move_dialog.dart';
import 'board_reader_card.dart';
import 'boards_controller.dart';
import 'boards_data.dart';
import 'boards_directory.dart';
import 'boards_navigation.dart';

/// How much of each neighbouring column a phone shows beside a full-width one.
const _columnPeek = 10.0;

/// Narrower boards show one column at a time. Tablets also use mobile
/// navigation but keep several fixed-width columns in view.
const _singleColumnWidth = 600.0;

/// The distance between neighbouring columns when a board shows one at a time.
/// Column widths and snapping both derive from it so they cannot disagree.
double _singleColumnStride(double viewport) => viewport - 12 - 2 * _columnPeek;

/// Where a one-column board rests to show column [index] between slivers of
/// both neighbours. The first and last columns clamp against the padding, so
/// they show their one neighbour's sliver twice over.
double _singleColumnOffset(int index, double stride) =>
    index * stride - _columnPeek;

/// Room for a column's heading, a card and its footer at unscaled text.
const _minimumColumnHeight = 200.0;

/// The position dots under a one-column board and their gap above the bottom.
const _columnDotsExtent = DCarouselDot.diameter + DSpacing.sm;

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
  ({
    BoardsController controller,
    String site,
    int? boardId,
    bool enabled,
    int? directoryRevision,
  })?
  _identity;
  String? _directoryError;
  Object? _directoryToken;
  final _horizontal = ScrollController();
  (int, int, double, int)? _horizontalTarget;
  late final _drag = BoardCardDrag(board: () => _handle?.snapshot);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _reconcile();
  }

  @override
  void didUpdateWidget(BoardsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    _reconcile();
  }

  void _changed() {
    if (!mounted) return;
    _reconcile();
    _drag.boardChanged();
    setState(() {});
  }

  void _reconcile() {
    final identity = (
      controller: widget.controller,
      site: widget.site,
      boardId: widget.route.boardId,
      enabled: widget.controller.enabled(widget.site),
      directoryRevision: widget.route.boardId == null
          ? widget.controller.accountRevision(widget.site)
          : null,
    );
    if (_identity == identity) return;
    _identity = identity;
    final previous = _handle;
    _handle = null;
    previous?.release();
    _horizontalTarget = null;
    _drag.cancel();
    _directoryToken = null;
    _directoryError = null;
    if (!identity.enabled) return;
    if (identity.boardId case final id?) {
      _handle = identity.controller.acquire(identity.site, id);
    } else {
      unawaited(_directory());
    }
  }

  Future<void> _directory({bool force = false}) async {
    final token = Object();
    final site = widget.site;
    _directoryToken = token;
    setState(() => _directoryError = null);
    try {
      await widget.controller.loadDirectory(site, force: force);
    } catch (error) {
      if (mounted && identical(token, _directoryToken)) {
        setState(() => _directoryError = error.toString());
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _handle?.release();
    _horizontal.dispose();
    _drag.dispose();
    super.dispose();
  }

  bool _singleColumn(double width) =>
      widget.navigation.mobileNavigationEnabled && width < _singleColumnWidth;

  bool _columnDots(double width, int columns) =>
      columns > 1 && _singleColumn(width);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!widget.controller.enabled(widget.site)) {
      return Center(child: DEmpty(children: [Text(l10n.boardsDisabled)]));
    }
    final handle = _handle;
    if (handle == null) {
      final boards = widget.controller.directory(widget.site);
      return BoardsDirectory(
        key: PageStorageKey(_identity),
        site: widget.site,
        boards: boards ?? const [],
        categories: {
          for (final board in boards ?? const <BoardSnapshot>[])
            for (final id in board.categoryIds)
              id: ?widget.controller.siteState.categoryFor
                  ?.call(widget.site, id)
                  ?.name,
        },
        loaded: boards != null,
        error: _directoryError,
        onRefresh: () => _directory(force: true),
        onOpen: (board) => widget.navigation.open(board: board),
      );
    }
    final board = handle.snapshot;
    // The home indicator and a minimized composer cover the bottom of the
    // page. Columns scroll individually, so the board stops above them rather
    // than under them.
    // When the header leaves the board less than a column needs, as on a
    // landscape phone or with large text, the page scrolls as a whole instead.
    Widget page(
      String title, {
      List<Widget> badges = const [],
      required Widget action,
      required Widget body,
      int columns = 0,
    }) => DPageSurface(
      framed: false,
      border: false,
      limitContentSize: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _BoardHeader(
              title: title,
              badges: badges,
              action: action,
              sheet: widget.navigation.mobileNavigationEnabled,
              onBack: () => widget.navigation.open(),
            ),
          ),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final dock = DScrollChrome.bottomInsetOf(context);
              final dots = _columnDots(constraints.crossAxisExtent, columns)
                  ? _columnDotsExtent
                  : 0.0;
              return SliverToBoxAdapter(
                child: SizedBox(
                  height: math.max(
                    constraints.viewportMainAxisExtent -
                        constraints.precedingScrollExtent,
                    24 +
                        MediaQuery.textScalerOf(
                          context,
                        ).scale(_minimumColumnHeight) +
                        dots +
                        dock,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: dock),
                    child: body,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
    if (board == null) {
      return page(
        l10n.boardsTitle,
        action: DButton(
          size: DButtonSize.filter,
          variant: DButtonVariant.outline,
          label: Text(l10n.refresh),
          onPressed: handle.reading ? null : handle.refresh,
        ),
        body: handle.reading
            ? const Center(child: DSpinner())
            : Center(
                child: DEmpty(
                  children: [Text(handle.error ?? l10n.boardsNoBoards)],
                ),
              ),
      );
    }
    final linkedCard = board.card(widget.route.cardId ?? -1);
    final showCategories =
        {
          for (final column in board.columns)
            for (final card in column.cards) ?card.categoryId,
        }.length >
        1;
    return page(
      board.name,
      columns: board.columns.length,
      badges: [
        for (final id in board.categoryIds)
          if (widget.controller.siteState.categoryFor?.call(widget.site, id)
              case final category?)
            _categoryBadge(category.name, category.colorValue),
        for (final tag in board.tagNames)
          DBadge(
            variant: DBadgeVariant.secondary,
            size: DBadgeSize.control,
            child: Text('# $tag', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        if (board.archived)
          DBadge(size: DBadgeSize.control, child: Text(l10n.boardsArchived)),
      ],
      action: DDropdownMenu(
        content: DDropdownMenuContent(
          children: [
            DDropdownMenuItem(
              leading: const DIcon(DIcons.arrowRotateRight),
              onPressed: handle.reading || handle.writing
                  ? null
                  : handle.refresh,
              child: Text(l10n.refresh),
            ),
            if (board.canManage)
              DDropdownMenuItem(
                leading: const DIcon(DIcons.gear),
                onPressed: () =>
                    widget.navigation.configure(widget.site, board),
                child: Text(l10n.openInBrowser),
              ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton.iconOnly(
            key: const ValueKey('board-controls'),
            size: DButtonSize.filter,
            variant: DButtonVariant.outline,
            icon: const DIcon(DIcons.ellipsis),
            tooltip: l10n.moreActions,
            // Busy state stays inside the button so the header never reflows.
            loading: handle.reading || handle.writing,
            onPressed: state.toggle,
            focusNode: state.focusNode,
            hasPopup: true,
            expanded: state.open,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                // Slot changes redraw the columns, never the header above.
                : ListenableBuilder(
                    listenable: _drag,
                    builder: (context, _) =>
                        NotificationListener<ScrollNotification>(
                          onNotification: (_) {
                            _drag.scrolled();
                            return false;
                          },
                          child: DDragRegion<_BoardDrag>(
                            accepts: _accepts,
                            onMove: (_, pointer) => _drag.move(pointer),
                            onLeave: _drag.leave,
                            onDrop: (_, _) => unawaited(_drop()),
                            child: _columns(board, linkedCard, showCategories),
                          ),
                        ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _columns(
    BoardSnapshot board,
    BoardCard? linkedCard,
    bool showCategories,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final single = _singleColumn(constraints.maxWidth);
      final dots = _columnDots(constraints.maxWidth, board.columns.length);
      final width = single
          ? (_singleColumnStride(constraints.maxWidth) - 12).clamp(
              0.0,
              double.infinity,
            )
          : (constraints.maxWidth - 24).clamp(240.0, 300.0);
      final stride = width + 12;
      if (linkedCard != null) {
        final target = (
          linkedCard.id,
          linkedCard.columnId,
          stride,
          widget.controller.accountRevision(widget.site),
        );
        if (_horizontalTarget != target) {
          _horizontalTarget = target;
          final identity = _identity;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _identity != identity ||
                _horizontalTarget != target ||
                !_horizontal.hasClients) {
              return;
            }
            final index = board.columns.indexWhere(
              (column) => column.id == linkedCard.columnId,
            );
            _horizontal.jumpTo(
              (single ? _singleColumnOffset(index, stride) : index * stride)
                  .clamp(0, _horizontal.position.maxScrollExtent),
            );
          });
        }
      }
      final scroller = DScrollArea(
        key: PageStorageKey((
          'board-reader',
          _identity,
          widget.controller.accountRevision(widget.site),
        )),
        axes: DScrollAxes.horizontal,
        controller: _horizontal,
        showScrollbar: !widget.navigation.mobileNavigationEnabled,
        physics: single ? const _ColumnSnapPhysics() : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              for (final column in board.columns)
                SizedBox(
                  key: PageStorageKey((
                    _identity,
                    widget.controller.accountRevision(widget.site),
                    column.id,
                  )),
                  width: width,
                  child: _drag.column(
                    column.id,
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            (constraints.maxHeight -
                                    24 -
                                    (dots ? _columnDotsExtent : 0))
                                .clamp(0, double.infinity),
                      ),
                      child: BoardColumnPanel(
                        column: column,
                        linkedCardId: widget.route.cardId,
                        hiddenCardId: _drag.hiddenCardId,
                        placeholder: _drag.placeholderIn(column.id),
                        menu: board.canManage
                            ? _columnMenu(board, column)
                            : null,
                        footer:
                            _handle!.canWrite &&
                                column.order != BoardColumnOrder.unsupported
                            ? _addMenu(column)
                            : null,
                        cardBuilder: (_, card) =>
                            _card(board, column, card, showCategories),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      // One shape with and without dots: rotating a phone crosses the
      // one-column width, and a reshaped tree would rebuild every column and
      // lose its state.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: scroller),
          if (dots)
            _ColumnDots(
              controller: _horizontal,
              count: board.columns.length,
              stride: stride,
            ),
        ],
      );
    },
  );

  Widget _categoryBadge(String name, int color) {
    final surface = DTokens.of(context).categoryControlSurface(Color(color));
    return DBadge(
      size: DBadgeSize.control,
      backgroundColor: surface.background,
      foregroundColor: surface.foreground,
      borderColor: surface.border,
      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _addMenu(BoardColumn column) => DDropdownMenu(
    sheetOnMobile: true,
    content: DDropdownMenuContent(
      children: [
        DDropdownMenuItem(
          leading: const DIcon(DIcons.plus),
          onPressed: () => _edit(column),
          child: Text(context.l10n.boardsAddCard),
        ),
        DDropdownMenuItem(
          leading: const DIcon(DIcons.link),
          onPressed: () => _addTopic(column),
          child: Text(context.l10n.boardsAddTopicAsCard),
        ),
        if (widget.controller.composer != null)
          DDropdownMenuItem(
            onPressed: _handle!.composing(column.id)
                ? null
                : () async {
                    final handle = _handle!;
                    if (handle.createdTopic(column.id) != null) {
                      _report(await handle.attachCreatedTopic(column.id));
                    } else {
                      await handle.createTopic(widget.route.id, column.id);
                    }
                  },
            child: Text(
              _handle!.createdTopic(column.id) == null
                  ? context.l10n.boardsNewTopic
                  : context.l10n.boardsAttachTopic,
            ),
          ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton(
        key: ValueKey('board-add-${column.id}'),
        alignment: AlignmentDirectional.centerStart,
        variant: DButtonVariant.ghost,
        icon: const DIcon(DIcons.plus),
        label: Text(context.l10n.boardsAddCard),
        onPressed: state.toggle,
        focusNode: state.focusNode,
        hasPopup: true,
        expanded: state.open,
      ),
    ),
  );

  Widget _columnMenu(BoardSnapshot board, BoardColumn column) {
    final index = board.columns.indexOf(column);
    final handle = _handle!;
    return DDropdownMenu(
      sheetOnMobile: true,
      content: DDropdownMenuContent(
        children: [
          DDropdownMenuItem(
            leading: const DIcon(DIcons.pen),
            onPressed:
                handle.canManage && column.order != BoardColumnOrder.unsupported
                ? () => _editColumn(column)
                : null,
            child: Text(context.l10n.boardsEditColumn),
          ),
          DDropdownMenuItem(
            leading: const DIcon(DIcons.arrowLeft),
            onPressed: handle.canManage && index > 0
                ? () async => _report(await handle.moveColumn(column.id, -1))
                : null,
            child: Text(context.l10n.boardsMoveLeft),
          ),
          DDropdownMenuItem(
            leading: const DIcon(DIcons.chevronRight),
            onPressed: handle.canManage && index < board.columns.length - 1
                ? () async => _report(await handle.moveColumn(column.id, 1))
                : null,
            child: Text(context.l10n.boardsMoveRight),
          ),
          DDropdownMenuItem(
            leading: const DIcon(DIcons.xmark),
            onPressed: handle.canManage && column.cards.isNotEmpty
                ? () => _removeColumn(column, delete: false)
                : null,
            child: Text(context.l10n.boardsClearColumn),
          ),
          DDropdownMenuItem(
            variant: DDropdownMenuItemVariant.destructive,
            leading: const DIcon(DIcons.trashCan),
            onPressed: handle.canManage
                ? () => _removeColumn(column, delete: true)
                : null,
            child: Text(context.l10n.boardsDeleteColumn),
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, state) => DButton.iconOnly(
          key: ValueKey('board-column-menu-${column.id}'),
          variant: DButtonVariant.ghost,
          icon: const DIcon(DIcons.ellipsis),
          tooltip: context.l10n.boardsColumnControls,
          onPressed: state.toggle,
          focusNode: state.focusNode,
          hasPopup: true,
          expanded: state.open,
        ),
      ),
    );
  }

  Future<void> _editColumn(BoardColumn column) async {
    final handle = _handle!;
    final lease = widget.controller.requests.capture(widget.site);
    final revision = widget.controller.accountRevision(widget.site);
    final result = await showDDialog<BoardWriteResult>(
      context: context,
      builder: (context, dialog) => boardDialogGuard(
        widget.controller,
        widget.site,
        lease,
        revision,
        BoardColumnEditor(
          handle: handle,
          column: column,
          onSaved: dialog.close,
        ),
        sourceCurrent: () =>
            identical(handle, _handle) &&
            handle.enabled &&
            handle.snapshot?.column(column.id) != null,
      ),
    );
    if (result != null &&
        mounted &&
        identical(handle, _handle) &&
        widget.controller.sourceCurrent(widget.site, lease, revision)) {
      _report(result);
    }
  }

  Future<void> _removeColumn(BoardColumn column, {required bool delete}) async {
    final handle = _handle!;
    final lease = widget.controller.requests.capture(widget.site);
    final revision = widget.controller.accountRevision(widget.site);
    final confirmed = await showDDialog<bool>(
      context: context,
      builder: (context, dialog) => boardDialogGuard(
        widget.controller,
        widget.site,
        lease,
        revision,
        BoardColumnRemovalDialog(
          handle: handle,
          columnId: column.id,
          delete: delete,
          onConfirm: () => dialog.close(true),
          onCancel: () => dialog.close(false),
        ),
        sourceCurrent: () =>
            identical(handle, _handle) &&
            handle.enabled &&
            handle.snapshot?.column(column.id) != null,
      ),
    );
    if (confirmed == true &&
        mounted &&
        identical(handle, _handle) &&
        widget.controller.sourceCurrent(widget.site, lease, revision)) {
      _report(
        await (delete
            ? handle.deleteColumn(column.id)
            : handle.clearColumn(column.id)),
      );
    }
  }

  bool _accepts(_BoardDrag drag) =>
      _handle?.canWrite == true &&
      drag.site == widget.site &&
      drag.boardId == _handle?.id;

  /// The card stays hidden at its drop slot through the constraint check, a
  /// review dialog, the write and the refresh that follows it.
  Future<void> _drop() async {
    final drop = _drag.drop();
    if (drop == null) return;
    await _move(drop.card.id, drop.slot.columnId, drop.placement);
    // The board can close while the move is still in flight.
    if (mounted) _drag.settle(drop.token);
  }

  Widget _card(
    BoardSnapshot board,
    BoardColumn column,
    BoardCard card,
    bool showCategories,
  ) {
    final category = showCategories && card.categoryId != null
        ? widget.controller.siteState.categoryFor?.call(
            widget.site,
            card.categoryId!,
          )
        : null;
    final item = BoardReaderCard(
      key: ValueKey('board-card-${card.id}'),
      site: widget.site,
      board: board,
      card: card,
      category: category == null
          ? null
          : (name: category.name, color: category.colorValue),
      selected: widget.route.cardId == card.id,
      onPressed: card.kind == BoardCardKind.topic && card.topicId != null
          ? () => widget.navigation.openTopic(widget.site, card)
          : () => _edit(column, card: card),
      menu: _handle!.canWrite && card.kind != BoardCardKind.unsupported
          ? _menu(board, column, card)
          : null,
    );
    if (!_handle!.canWrite ||
        card.kind == BoardCardKind.unsupported ||
        column.order == BoardColumnOrder.unsupported) {
      return _drag.card(card.id, item);
    }
    return _drag.card(
      card.id,
      DContentDrag(
        data: _BoardDrag(widget.site, board.id, card.id),
        // A finger would hide the pointer corner and push most of the preview
        // off a phone's edge, so touch boards centre it under the finger. Only
        // the painting moves: drop targets still read the pointer as the
        // drag offset.
        feedback: FractionalTranslation(
          translation: widget.navigation.mobileNavigationEnabled
              ? const Offset(-.5, -.5)
              : Offset.zero,
          child: SizedBox(
            width: 290,
            child: DCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(card.title),
              ),
            ),
          ),
        ),
        onDragStarted: () => _drag.start(card),
        onDragEnd: _drag.end,
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
                    widget.controller.sourceCurrent(
                      widget.site,
                      lease,
                      revision,
                    )) {
                  _report(await handle.removeCard(card.id));
                }
              },
              child: Text(context.l10n.delete),
            ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton.iconOnly(
            variant: DButtonVariant.ghost,
            icon: const DIcon(DIcons.ellipsis),
            tooltip: context.l10n.moreActions,
            onPressed: state.toggle,
            focusNode: state.focusNode,
            hasPopup: true,
            expanded: state.open,
          ),
        ),
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
    var input = '';
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
              onChanged: (value) => input = value,
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
                  onPressed: () => dialog.close(input),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

/// The topic reader's heading. In the mobile page sheet, whose dismissal goes
/// back, the badges and [action] follow the title on its line and wrap below
/// it when they do not fit. Elsewhere a back link leads to the directory and
/// the controls follow the title on their own row.
class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.title,
    required this.badges,
    required this.action,
    required this.sheet,
    required this.onBack,
  });
  final String title;
  final List<Widget> badges;
  final Widget action;
  final bool sheet;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      headingLevel: 1,
      child: Text(
        title,
        key: const ValueKey('board-title'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
    if (sheet) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: DControlWrap(children: [heading, ...badges, action]),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DButton(
              key: const ValueKey('board-back'),
              icon: const DIcon(DIcons.chevronLeft),
              label: Text(context.l10n.boardsTitle),
              variant: DButtonVariant.inline,
              density: DButtonDensity.backLink,
              onPressed: onBack,
            ),
          ),
          heading,
          const SizedBox(height: 16),
          DControlWrap(children: [...badges, action]),
        ],
      ),
    );
  }
}

/// Marks the column a one-column board shows. The dots sit below the column
/// area rather than under its content, so they stay at the bottom however
/// short the column is. Only they rebuild while the columns scroll.
class _ColumnDots extends StatelessWidget {
  const _ColumnDots({
    required this.controller,
    required this.count,
    required this.stride,
  });
  final ScrollController controller;
  final int count;
  final double stride;

  void _show(BuildContext context, int index) {
    if (!controller.hasClients) return;
    final target = _singleColumnOffset(
      index,
      stride,
    ).clamp(0.0, controller.position.maxScrollExtent);
    final duration = DMotion.duration(
      context,
      const Duration(milliseconds: 300),
    );
    if (duration == Duration.zero) {
      controller.jumpTo(target);
    } else {
      unawaited(
        controller.animateTo(target, duration: duration, curve: Curves.easeOut),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: DSpacing.sm),
    child: SizedBox(
      height: DCarouselDot.diameter,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            // A column area rebuilt under a new key attaches before the one
            // it replaces detaches, so read the newest position.
            final offset = controller.positions.lastOrNull?.pixels ?? 0;
            final current = ((offset + _columnPeek) / stride).round().clamp(
              0,
              count - 1,
            );
            return Row(
              spacing: DSpacing.sm,
              children: [
                for (var index = 0; index < count; index++)
                  DCarouselDot(
                    key: ValueKey('board-column-dot-$index'),
                    selected: index == current,
                    semanticLabel: context.l10n.boardsGoToColumn(
                      '${index + 1}',
                      '$count',
                    ),
                    onPressed: () => _show(context, index),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Settles a one-column board on a column after each swipe. The stride is read
/// from the viewport on every fling: Scrollable keeps physics of an unchanged
/// type, so a stored stride would go stale after rotation or resizing.
class _ColumnSnapPhysics extends ScrollPhysics {
  const _ColumnSnapPhysics({super.parent});

  @override
  _ColumnSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _ColumnSnapPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final stride = _singleColumnStride(position.viewportDimension);
    final tolerance = toleranceFor(position);
    var column = (position.pixels + _columnPeek) / stride;
    if (velocity < -tolerance.velocity) {
      column -= .5;
    } else if (velocity > tolerance.velocity) {
      column += .5;
    }
    final target = _singleColumnOffset(
      column.round(),
      stride,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

final class _BoardDrag {
  const _BoardDrag(this.site, this.boardId, this.cardId);
  final String site;
  final int boardId, cardId;
}
