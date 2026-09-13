part of 'global_search_panel.dart';

class _GlobalSearchCategoryEditor extends StatefulWidget {
  const _GlobalSearchCategoryEditor({
    super.key,
    required this.controller,
    required this.onApply,
    required this.onCancel,
    this.initial,
    this.onBack,
  });

  final GlobalSearchController controller;
  final GlobalSearchCondition? initial;
  final ValueChanged<GlobalSearchCondition> onApply;
  final VoidCallback onCancel;
  final VoidCallback? onBack;

  @override
  State<_GlobalSearchCategoryEditor> createState() =>
      _GlobalSearchCategoryEditorState();
}

class _GlobalSearchCategoryEditorState
    extends State<_GlobalSearchCategoryEditor> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  late final _selected = <String>{...?widget.initial?.value};
  late bool _includeChildren = widget.initial?.operator != 'exactCategory';
  final _known = <String, GlobalSearchFilterChoice>{};
  List<GlobalSearchFilterChoice> _choices = const [];
  int _generation = 0, _page = 0;
  int? _total;
  bool _loading = false, _hasMore = false;
  String? _loadError, _validationError;

  @override
  void initState() {
    super.initState();
    for (final id in _selected) {
      final choice = widget.controller.choice('category', id);
      if (choice != null) _known[id] = choice;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false, bool debounce = false}) async {
    if (append && (_loading || !_hasMore)) return;
    final generation = ++_generation;
    final term = _query.text;
    final page = append ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _loadError = null;
      if (!append) {
        _choices = const [];
        _total = null;
        _hasMore = false;
        _page = 0;
      }
    });
    if (!append && _scroll.hasClients) _scroll.jumpTo(0);
    try {
      if (debounce) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      if (!mounted || generation != _generation) return;
      final result = await widget.controller.lookupCategoryChoices(
        term,
        page: page,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final values = {for (final choice in _choices) choice.value: choice};
        final previousCount = values.length;
        for (final choice in result.choices) {
          values[choice.value] = choice;
          _known[choice.value] = choice;
        }
        _choices = values.values.toList();
        _hasMore = result.hasMore;
        if (append && result.hasMore && values.length == previousCount) {
          _loadError = 'More categories couldn’t load.';
        }
        _total = result.total;
        if (_loadError == null) _page = page;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadError = GlobalSearchApi.failureMessage(
          error,
          fallback: 'Categories couldn’t load.',
        );
      });
    }
  }

  void _toggle(String value) => setState(() {
    _validationError = null;
    if (!_selected.remove(value)) _selected.add(value);
  });

  String _label(String value) =>
      _known[value]?.label ??
      _searchChoiceLabel(
        context,
        widget.controller,
        globalSearchFilter('category')!,
        value,
      );

  void _apply() {
    final condition = GlobalSearchCondition(
      filterId: 'category',
      operator: _includeChildren ? 'any' : 'exactCategory',
      value: _selected.toList(),
    );
    final error = validateGlobalSearchCondition(
      condition,
      widget.controller.capabilities,
    );
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    try {
      widget.controller.rememberCategorySelection([
        for (final value in _selected) ?_known[value],
      ]);
      widget.onApply(condition);
    } on FormatException catch (error) {
      setState(() => _validationError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final muted = TextStyle(
      fontSize: DiscourseTypography.xs,
      color: tokens.mutedForeground,
    );
    final count = _loading && _choices.isEmpty
        ? 'Loading categories…'
        : _loadError != null && _choices.isEmpty
        ? 'Categories unavailable'
        : _hasMore
        ? _total == null
              ? '${_choices.length} categories loaded'
              : '${_choices.length} of $_total categories'
        : _query.text.trim().isEmpty
        ? 'All categories · ${_choices.length}'
        : '${_choices.length} categories found';
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.onBack != null) ...[
                  DButton.iconOnly(
                    icon: const DIcon(DIcons.chevronLeft),
                    tooltip: 'Back to filters',
                    variant: DButtonVariant.ghost,
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 8),
                ],
                const Expanded(
                  child: DLabel(child: Text('Filter by category')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DInput(
              key: const ValueKey('global-search-filter-value'),
              controller: _query,
              focusNode: _focus,
              autofocus: true,
              semanticLabel: 'Search all categories',
              hintText: 'Search all categories…',
              prefix: const DIcon(DIcons.magnifyingGlass, size: 16),
              suffix: _query.text.isEmpty
                  ? null
                  : DButton.iconOnly(
                      icon: const DIcon(DIcons.xmark, size: 12),
                      tooltip: 'Clear category search',
                      size: DButtonSize.small,
                      variant: DButtonVariant.ghost,
                      onPressed: () {
                        _query.clear();
                        unawaited(_load());
                        _focus.requestFocus();
                      },
                    ),
              onChanged: (_) => unawaited(_load(debounce: true)),
            ),
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(count, style: muted)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: DScrollArea(
                key: const ValueKey('global-search-category-list'),
                controller: _scroll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final choice in _choices)
                      DCheckbox(
                        key: ValueKey('global-search-category-${choice.value}'),
                        value: _selected.contains(choice.value),
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        onChanged: (_) => _toggle(choice.value),
                        title: Row(
                          children: [
                            if (choice.category case final category?) ...[
                              CategoryIcon(
                                category: category,
                                size: 12,
                                siteUrl: widget.controller.siteUrl,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                choice.category?.name ?? choice.label,
                              ),
                            ),
                          ],
                        ),
                        subtitle: choice.parentLabel == null
                            ? null
                            : Text(choice.parentLabel!),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: DSpinner(size: 16)),
                      ),
                    if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(_loadError!, style: muted),
                            ),
                            const SizedBox(height: 8),
                            DButton(
                              label: const Text('Try again'),
                              variant: DButtonVariant.outline,
                              onPressed: () =>
                                  unawaited(_load(append: _page > 0)),
                            ),
                          ],
                        ),
                      ),
                    if (!_loading && _loadError == null && _choices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Text(
                              _query.text.trim().isEmpty
                                  ? 'No categories available.'
                                  : 'No matching categories.',
                              style: muted,
                            ),
                            if (_query.text.trim().isNotEmpty)
                              DButton(
                                label: const Text('Show all categories'),
                                variant: DButtonVariant.ghost,
                                onPressed: () {
                                  _query.clear();
                                  unawaited(_load());
                                  _focus.requestFocus();
                                },
                              ),
                          ],
                        ),
                      ),
                    if (_hasMore && !_loading && _loadError == null)
                      DButton(
                        label: const Text('Load more categories'),
                        variant: DButtonVariant.ghost,
                        onPressed: () => unawaited(_load(append: true)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const DSeparator(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text('${_selected.length} selected', style: muted),
                  ),
                ),
                if (_selected.isNotEmpty)
                  DButton(
                    key: const ValueKey('global-search-category-clear'),
                    label: const Text('Clear'),
                    variant: DButtonVariant.ghost,
                    onPressed: () => setState(() {
                      _selected.clear();
                      _validationError = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (_selected.isEmpty)
              Text('Choose one or more categories.', style: muted),
            if (_selected.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 100),
                child: DScrollArea(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final value in _selected)
                        DBadge.action(
                          variant: DBadgeVariant.secondary,
                          semanticLabel: 'Remove ${_label(value)}',
                          leading: switch (_known[value]?.category) {
                            final category? => CategoryIcon(
                              category: category,
                              size: 12,
                              siteUrl: widget.controller.siteUrl,
                            ),
                            null => null,
                          },
                          trailing: const DIcon(DIcons.xmark, size: 10),
                          onPressed: () {
                            _toggle(value);
                            _focus.requestFocus();
                          },
                          child: Text(_label(value)),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const DSeparator(),
            const SizedBox(height: 12),
            DSwitchTile(
              value: _includeChildren,
              onChanged: (value) => setState(() => _includeChildren = value),
              title: const Text('Include subcategories'),
            ),
            const SizedBox(height: 12),
            const DSeparator(),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _validationError!,
                    style: muted.copyWith(color: tokens.destructive),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                DButton(
                  label: const Text('Cancel'),
                  variant: DButtonVariant.ghost,
                  onPressed: widget.onCancel,
                ),
                DButton(
                  key: const ValueKey('global-search-filter-apply'),
                  label: Text(
                    widget.initial == null ? 'Add filter' : 'Apply changes',
                  ),
                  onPressed: _selected.isEmpty ? null : _apply,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
