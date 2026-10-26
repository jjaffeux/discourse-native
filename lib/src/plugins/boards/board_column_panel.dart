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
    this.linkedCardId,
    this.hiddenCardId,
    this.placeholder,
    this.menu,
    this.footer,
  });
  final BoardColumn column;
  final Widget Function(BuildContext, BoardCard) cardBuilder;
  final int? linkedCardId;

  /// A card in the air or settling after a drop. It leaves the list entirely.
  final int? hiddenCardId;

  /// Where a dragged card would land, as an index among the column's cards
  /// with the hidden card left out, and the height it takes there.
  final ({int index, double height})? placeholder;
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

  /// The list index the placeholder takes: before its anchor card when that
  /// card is shown, otherwise after the last shown card.
  int? _placeholderIndex(List<BoardCard> shown) {
    final placeholder = widget.placeholder;
    if (placeholder == null) return null;
    final others = [
      for (final card in widget.column.cards)
        if (card.id != widget.hiddenCardId) card,
    ];
    final anchor = placeholder.index < others.length
        ? others[placeholder.index].id
        : null;
    final index = shown.indexWhere((card) => card.id == anchor);
    return index < 0 ? shown.length : index;
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
    final shown = [
      for (final card in visible.cards)
        if (card.id != widget.hiddenCardId) card,
    ];
    final placeholder = _placeholderIndex(shown);
    int item(int cardIndex) => placeholder != null && cardIndex >= placeholder
        ? cardIndex + 1
        : cardIndex;
    final linkedIndex = shown.indexWhere((card) => card.id == linkedId);
    if (linkedId != null && linkedId != _positioned && linkedIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_list.isAttached || !_scroll.hasClients) return;
        _list.jumpToItem(
          index: item(linkedIndex),
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
        if (shown.isEmpty && visible.hiddenCount == 0 && placeholder == null)
          // Large text can outgrow a short column, so the empty state yields
          // to the footer and scrolls, as the card list does.
          Flexible(
            fit: FlexFit.loose,
            child: DCardContent(
              child: DScrollArea(
                child: DEmpty(
                  padding: const EdgeInsets.all(12),
                  children: [Text(context.l10n.boardsNoCards)],
                ),
              ),
            ),
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
                      shown.length +
                      (placeholder == null ? 0 : 1) +
                      (visible.hiddenCount > 0 ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == placeholder) {
                      return _Placeholder(
                        height: widget.placeholder!.height,
                        color: color ?? DTokens.of(context).primary,
                      );
                    }
                    final cardIndex = placeholder != null && index > placeholder
                        ? index - 1
                        : index;
                    if (cardIndex < shown.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: widget.cardBuilder(context, shown[cardIndex]),
                      );
                    }
                    return Align(
                      alignment: Alignment.center,
                      child: DButton(
                        variant: DButtonVariant.link,
                        label: Text(
                          context.l10n.boardsShowOlder(visible.hiddenCount),
                        ),
                        onPressed: () => setState(() => _showOlder = true),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        if (widget.footer case final footer?) DCardContent(child: footer),
      ],
    );
  }
}

/// The slot a dragged card would fill, drawn as the web client draws it: the
/// card's own height, outlined and tinted in the column colour.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.height, required this.color});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          key: const ValueKey('board-drop-placeholder'),
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: .25),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(DTokens.of(context).radius),
            ),
          ),
        ),
      ),
    ),
  );
}
