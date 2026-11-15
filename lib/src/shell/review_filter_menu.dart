part of 'review_page.dart';

/// The filters that narrow a queue beyond its status, behind one control: a
/// popover beside the pointer and a sheet under a thumb.
class _ReviewFilterMenu extends StatelessWidget {
  const _ReviewFilterMenu({
    required this.filters,
    required this.types,
    required this.categories,
    required this.onFilters,
  });

  final ReviewFilters filters;
  final List<String> types;
  final List<ReviewCategoryOption> categories;
  final ValueChanged<ReviewFilters> onFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final count = filters.narrowing;
    return DPopover(
      sheetOnMobile: true,
      mobileSheetVariant: DSheetVariant.adaptiveMenu,
      content: DPopoverContent(
        width: 300,
        align: DPopoverAlign.start,
        padding: const EdgeInsets.all(DSpacing.lg),
        semanticLabel: l10n.filters,
        child: _ReviewFilterPanel(
          filters: filters,
          types: types,
          categories: categories,
          onFilters: onFilters,
        ),
      ),
      child: DPopoverTrigger(
        builder: (context, trigger) => DButton(
          key: const ValueKey('review-filters'),
          label: Text(count == 0 ? l10n.filters : '${l10n.filters} · $count'),
          icon: const DIcon(DIcons.filter),
          variant: count == 0
              ? DButtonVariant.quiet
              : DButtonVariant.quietSelected,
          size: DButtonSize.filter,
          focusNode: trigger.focusNode,
          expanded: trigger.open,
          hasPopup: true,
          onPressed: trigger.toggle,
        ),
      ),
    );
  }
}

class _ReviewFilterPanel extends StatefulWidget {
  const _ReviewFilterPanel({
    required this.filters,
    required this.types,
    required this.categories,
    required this.onFilters,
  });

  final ReviewFilters filters;
  final List<String> types;
  final List<ReviewCategoryOption> categories;
  final ValueChanged<ReviewFilters> onFilters;

  @override
  State<_ReviewFilterPanel> createState() => _ReviewFilterPanelState();
}

class _ReviewFilterPanelState extends State<_ReviewFilterPanel> {
  late final _username = TextEditingController(text: widget.filters.username);

  ReviewFilters get filters => widget.filters;

  @override
  void didUpdateWidget(_ReviewFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final username = filters.username;
    if (username != oldWidget.filters.username && username != _username.text) {
      _username.text = username;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Widget _select<T>({
    required String label,
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T> onChanged,
  }) => DSelect<T>.controlled(
    label: Text(label),
    isExpanded: true,
    value: value,
    entries: [
      for (final (option, text) in options)
        DSelectOption(value: option, label: text, child: Text(text)),
    ],
    onChanged: (selected) {
      if (selected != null && selected != value) onChanged(selected);
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The site lists its own types once a page has loaded; until then the
    // three every site has are offered.
    final types = {
      ...widget.types.isEmpty
          ? const [
              'ReviewableFlaggedPost',
              'ReviewableQueuedPost',
              'ReviewableUser',
            ]
          : widget.types,
      ?filters.type,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.md,
      children: [
        _select<String>(
          label: l10n.reviewFilterType,
          value: filters.type ?? '',
          options: [
            ('', l10n.reviewAllTypes),
            for (final type in types) (type, reviewTypeLabel(type)),
          ],
          onChanged: (type) => widget.onFilters(
            type.isEmpty
                ? filters.copyWith(clearType: true)
                : filters.copyWith(type: type),
          ),
        ),
        _select<ReviewPriorityFilter>(
          label: l10n.reviewFilterPriority,
          value: filters.priority,
          options: [
            for (final priority in ReviewPriorityFilter.values)
              (priority, _priorityLabel(priority)),
          ],
          onChanged: (priority) =>
              widget.onFilters(filters.copyWith(priority: priority)),
        ),
        if (widget.categories.isNotEmpty)
          _select<int>(
            label: l10n.reviewFilterCategory,
            value: filters.categoryId ?? 0,
            options: [
              (0, l10n.reviewAllCategories),
              for (final category in widget.categories)
                (category.id, category.name),
            ],
            onChanged: (id) => widget.onFilters(
              id == 0
                  ? filters.copyWith(clearCategory: true)
                  : filters.copyWith(categoryId: id),
            ),
          ),
        DInput(
          controller: _username,
          labelText: l10n.reviewFilterUsername,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) =>
              widget.onFilters(filters.copyWith(username: value.trim())),
        ),
        _select<ReviewSortOrder>(
          label: l10n.reviewFilterOrder,
          value: filters.sortOrder,
          options: [
            for (final order in ReviewSortOrder.values)
              (order, _orderLabel(order)),
          ],
          onChanged: (order) =>
              widget.onFilters(filters.copyWith(sortOrder: order)),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: DButton(
            key: const ValueKey('review-clear-filters'),
            label: Text(l10n.reviewClearFilters),
            variant: DButtonVariant.ghost,
            onPressed: filters.narrowing == 0
                ? null
                : () => widget.onFilters(filters.cleared),
          ),
        ),
      ],
    );
  }
}
