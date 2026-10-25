import 'package:discourse_native/discourse_plugin_sdk.dart'
    show PluginSiteLease;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'boards_controller.dart';
import 'boards_data.dart';

Widget boardDialogGuard(
  BoardsController controller,
  String site,
  PluginSiteLease lease,
  int revision,
  Widget child, {
  bool Function()? sourceCurrent,
}) => AnimatedBuilder(
  animation: controller,
  builder: (context, _) =>
      controller.sourceCurrent(site, lease, revision) &&
          (sourceCurrent?.call() ?? true)
      ? child
      : DDialogContent(children: [Text(context.l10n.boardsRefused)]),
);

Future<void> addTopicToBoard(
  BuildContext context,
  BoardsController controller,
  String site,
  int topicId,
  List<BoardSnapshot> boards,
) async {
  final lease = controller.requests.capture(site);
  final revision = controller.accountRevision(site);
  final selected = await showDDialog<(int, int)>(
    context: context,
    builder: (context, dialog) => boardDialogGuard(
      controller,
      site,
      lease,
      revision,
      DDialogContent(
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
    ),
  );
  if (selected == null ||
      !context.mounted ||
      !controller.sourceCurrent(site, lease, revision)) {
    return;
  }
  final handle = controller.acquire(site, selected.$1);
  try {
    await handle.refresh();
    if (!context.mounted ||
        !handle.canWrite ||
        !controller.sourceCurrent(site, lease, revision)) {
      return;
    }
    final result = await handle.addTopic(
      topicId,
      selected.$2,
      review: (board, column, check) => showDDialog<BoardRepair>(
        context: context,
        builder: (context, dialog) => boardDialogGuard(
          controller,
          site,
          lease,
          revision,
          BoardMoveReview(
            board: board,
            column: column,
            check: check,
            controller: controller,
            site: site,
            onChosen: dialog.close,
          ),
          sourceCurrent: () => handle.enabled && handle.snapshot != null,
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

class BoardMovePicker extends StatefulWidget {
  const BoardMovePicker({
    super.key,
    required this.board,
    required this.card,
    required this.onChosen,
  });
  final BoardSnapshot board;
  final BoardCard card;
  final void Function(int, CardPlacement) onChosen;
  @override
  State<BoardMovePicker> createState() => BoardMovePickerState();
}

class BoardMovePickerState extends State<BoardMovePicker> {
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

class BoardMoveReview extends StatefulWidget {
  const BoardMoveReview({
    super.key,
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
  State<BoardMoveReview> createState() => BoardMoveReviewState();
}

class BoardMoveReviewState extends State<BoardMoveReview> {
  int? _category;
  String? _tag;
  @override
  Widget build(BuildContext context) => DDialogContent(
    children: [
      Text(context.l10n.boardsMoveReview),
      Text(widget.column.title),
      Text(context.l10n.boardsMoveEffects),
      if (widget.column.tagName.isNotEmpty) Text('#${widget.column.tagName}'),
      if (widget.column.moveCategoryId case final categoryId?)
        Text(
          widget.controller.siteState.categoryFor
                  ?.call(widget.site, categoryId)
                  ?.name ??
              '#$categoryId',
        ),
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
