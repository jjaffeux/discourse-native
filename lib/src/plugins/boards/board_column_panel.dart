import 'package:discourse_native/discourse_plugin_sdk.dart' show DIcons;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'boards_data.dart';

({List<BoardCard> cards, int hiddenCount}) boardColumnCards(
  BoardColumn column, {
  required DateTime now,
  bool showOlder = false,
  Set<int> linkedCardIds = const {},
}) {
  if (column.order != BoardColumnOrder.recency || showOlder) {
    return (cards: column.cards, hiddenCount: 0);
  }
  final cutoff = now.subtract(const Duration(days: 7));
  final cards = [
    for (final card in column.cards)
      if (linkedCardIds.contains(card.id) ||
          card.recencyAt != null && !card.recencyAt!.isBefore(cutoff))
        card,
  ];
  return (cards: cards, hiddenCount: column.cards.length - cards.length);
}

class BoardColumnPanel extends StatefulWidget {
  const BoardColumnPanel({
    super.key,
    required this.column,
    required this.cardBuilder,
    required this.emptyState,
    this.linkedCardId,
    this.menu,
    this.footer,
  });
  final BoardColumn column;
  final Widget Function(BuildContext, BoardCard) cardBuilder;
  final Widget emptyState;
  final int? linkedCardId;
  final Widget? menu, footer;

  @override
  State<BoardColumnPanel> createState() => _BoardColumnPanelState();
}

class _BoardColumnPanelState extends State<BoardColumnPanel> {
  final _scroll = ScrollController();
  final _list = ListController();
  final _linked = <int>{};
  bool _showOlder = false;
  int? _positioned;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final column = widget.column;
    final linkedId = widget.linkedCardId;
    if (linkedId != null) _linked.add(linkedId);
    final visible = boardColumnCards(
      column,
      now: DateTime.now(),
      showOlder: _showOlder,
      linkedCardIds: _linked,
    );
    final linkedIndex = visible.cards.indexWhere((card) => card.id == linkedId);
    if (linkedId != null && linkedId != _positioned && linkedIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_list.isAttached || !_scroll.hasClients) return;
        _list.jumpToItem(
          index: linkedIndex,
          scrollController: _scroll,
          alignment: .3,
        );
        _positioned = linkedId;
      });
    }
    final icon = DIcons.byName[column.icon];
    final hex = column.color.replaceFirst('#', '');
    final rgb = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    final color = rgb == null ? null : Color(0xff000000 | rgb);
    return DCard(
      key: ValueKey('board-column-${column.id}'),
      size: DCardSize.small,
      spacing: 8,
      children: [
        DCardContent(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: DBadge(
                        variant: DBadgeVariant.secondary,
                        backgroundColor: color,
                        foregroundColor: color == null
                            ? null
                            : color.computeLuminance() > .179
                            ? Colors.black
                            : Colors.white,
                        leading: icon == null ? null : DIcon(icon, size: 13),
                        child: Text(
                          column.title.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${column.cards.length}'),
                  ],
                ),
              ),
              ?widget.menu,
            ],
          ),
        ),
        if (column.order == BoardColumnOrder.unsupported)
          DCardContent(child: Text(context.l10n.boardsUnsupported)),
        if (column.cards.isEmpty)
          // Large text can outgrow a short column, so the empty state yields
          // to the footer and scrolls, as the card list does.
          Flexible(
            fit: FlexFit.loose,
            child: DCardContent(child: DScrollArea(child: widget.emptyState)),
          )
        else
          Flexible(
            fit: FlexFit.loose,
            child: DCardContent(
              child: DScrollBar(
                controller: _scroll,
                child: SuperListView.builder(
                  key: PageStorageKey('board-column-list-${column.id}'),
                  controller: _scroll,
                  listController: _list,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount:
                      visible.cards.length + (visible.hiddenCount > 0 ? 1 : 0),
                  itemBuilder: (context, index) => index < visible.cards.length
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: widget.cardBuilder(
                            context,
                            visible.cards[index],
                          ),
                        )
                      : Align(
                          alignment: Alignment.center,
                          child: DButton(
                            variant: DButtonVariant.link,
                            label: Text(
                              context.l10n.boardsShowOlder(visible.hiddenCount),
                            ),
                            onPressed: () => setState(() => _showOlder = true),
                          ),
                        ),
                ),
              ),
            ),
          ),
        if (widget.footer case final footer?) DCardContent(child: footer),
      ],
    );
  }
}
