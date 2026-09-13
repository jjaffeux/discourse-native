part of 'global_search_panel.dart';

class _GlobalSearchFilterPicker extends StatefulWidget {
  const _GlobalSearchFilterPicker({
    super.key,
    required this.controller,
    this.conditionIndex,
    this.addOnly = false,
    this.maxChipWidth = 350,
  });
  final GlobalSearchController controller;
  final int? conditionIndex;
  final bool addOnly;
  final double maxChipWidth;
  @override
  State<_GlobalSearchFilterPicker> createState() =>
      _GlobalSearchFilterPickerState();
}

class _GlobalSearchFilterPickerState extends State<_GlobalSearchFilterPicker> {
  final _popover = DPopoverController();
  GlobalSearchFilter? _editing;

  GlobalSearchCondition? get _condition {
    final index = widget.conditionIndex;
    if (index == null || index >= widget.controller.conditions.length) {
      return null;
    }
    return widget.controller.conditions[index];
  }

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final condition = _condition;
    final definition = condition == null
        ? null
        : globalSearchFilter(condition.filterId);
    final editor = _editing ?? definition;
    return DPopover(
      controller: _popover,
      onOpenChange: (open, _) {
        if (!open && mounted) setState(() => _editing = null);
      },
      content: DPopoverContent(
        width: 350,
        align: DPopoverAlign.end,
        padding: EdgeInsets.zero,
        semanticLabel: editor == null
            ? 'Add search filter'
            : 'Edit ${editor.label} condition',
        child: editor == null
            ? _catalogue(context)
            : _GlobalSearchConditionEditor(
                key: ValueKey('${editor.id}-${widget.conditionIndex}'),
                controller: widget.controller,
                filter: editor,
                initial: condition,
                onBack: condition == null
                    ? () => setState(() => _editing = null)
                    : null,
                onApply: (value) {
                  final index = widget.conditionIndex;
                  if (index == null) {
                    widget.controller.addCondition(value);
                  } else {
                    widget.controller.updateCondition(index, value);
                  }
                  _popover.close();
                },
              ),
      ),
      child: DPopoverTrigger(
        builder: (context, state) {
          if (condition == null || definition == null) {
            return DButton.iconOnly(
              key: widget.addOnly
                  ? null
                  : const ValueKey('global-search-filter-trigger'),
              icon: DIcon(
                widget.addOnly ? DIcons.plus : DIcons.filter,
                size: 14,
              ),
              tooltip: 'Add filter',
              variant: widget.addOnly
                  ? DButtonVariant.ghost
                  : DButtonVariant.outline,
              size: DButtonSize.small,
              expanded: state.open,
              hasPopup: true,
              focusNode: state.focusNode,
              onPressed: state.toggle,
            );
          }
          final operator =
              definition.operators
                  .where((op) => op.value == condition.operator)
                  .firstOrNull
                  ?.label ??
              condition.operator;
          final value = condition.value
              .map(
                (value) => _searchChoiceLabel(
                  context,
                  widget.controller,
                  definition,
                  value,
                ),
              )
              .join(', ');
          final maxWidth = widget.maxChipWidth.clamp(180.0, 350.0);
          final removeWidth = DControlStyle.scaledHeight(
            DControlSize.small,
            MediaQuery.textScalerOf(context),
          );
          // Preserve room for the value while the label and operator keep
          // their natural width until the complete joined control is bounded.
          final textBudget = (maxWidth - removeWidth - 104).clamp(
            0.0,
            maxWidth,
          );
          Widget part(
            String text, {
            FocusNode? focusNode,
            double? maxTextWidth,
          }) => DButton(
            label: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxTextWidth ?? double.infinity,
              ),
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            tooltip: text,
            onPressed: state.openPopover,
            focusNode: focusNode,
            expanded: state.open,
            hasPopup: true,
            variant: DButtonVariant.outline,
            size: DButtonSize.small,
          );
          return IntrinsicWidth(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: DButtonGroup(
                mainAxisSize: MainAxisSize.max,
                semanticLabel: '${definition.label} $operator $value',
                children: [
                  part(
                    definition.label,
                    focusNode: state.focusNode,
                    maxTextWidth: textBudget * .45,
                  ),
                  part(operator, maxTextWidth: textBudget * .55),
                  DButtonGroupExpanded(child: part(value)),
                  DButton.iconOnly(
                    icon: const DIcon(DIcons.xmark, size: 12),
                    tooltip: 'Remove ${definition.label} condition',
                    onPressed: () => widget.controller.removeCondition(
                      widget.conditionIndex!,
                    ),
                    variant: DButtonVariant.outline,
                    size: DButtonSize.small,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _catalogue(BuildContext context) {
    final filters = widget.controller.availableFilters;
    final groups = <String, List<GlobalSearchFilter>>{};
    for (final filter in filters) {
      final group = widget.controller.scope == GlobalSearchScope.all
          ? filter.scope.label
          : filter.group;
      groups.putIfAbsent(group, () => []).add(filter);
    }
    return DCommand<String>(
      semanticLabel: 'Search filters',
      onSelected: (id) => setState(() => _editing = globalSearchFilter(id)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DCommandInput<String>(
            placeholder: 'Add filter…',
            semanticLabel: 'Find a search filter',
          ),
          const DSeparator(),
          DCommandList<String>(
            maxHeight: 360,
            children: [
              for (final entry in groups.entries)
                DCommandGroup<String>(
                  heading: Text(entry.key),
                  items: [
                    for (final filter in entry.value)
                      DCommandItem<String>(
                        key: ValueKey('global-search-filter-${filter.id}'),
                        value: filter.id,
                        searchValue:
                            '${filter.label} ${filter.group} ${filter.scope.label}',
                        keywords: [filter.token ?? '', filter.help],
                        leading: DIcon(_filterIcon(filter.icon), size: 15),
                        trailing: const DIcon(DIcons.chevronRight, size: 12),
                        child: Text(filter.label),
                      ),
                  ],
                ),
              const DCommandEmpty(child: Text('No filters match your search.')),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlobalSearchConditionEditor extends StatefulWidget {
  const _GlobalSearchConditionEditor({
    super.key,
    required this.controller,
    required this.filter,
    required this.onApply,
    this.initial,
    this.onBack,
  });
  final GlobalSearchController controller;
  final GlobalSearchFilter filter;
  final GlobalSearchCondition? initial;
  final ValueChanged<GlobalSearchCondition> onApply;
  final VoidCallback? onBack;
  @override
  State<_GlobalSearchConditionEditor> createState() =>
      _GlobalSearchConditionEditorState();
}

class _GlobalSearchConditionEditorState
    extends State<_GlobalSearchConditionEditor> {
  late String _operator =
      widget.initial?.operator ?? widget.filter.operators.first.value;
  late final TextEditingController _text = TextEditingController(
    text: _multiple || _choicesOnly
        ? ''
        : widget.initial?.value.join(',') ?? '',
  );
  late List<String> _values = List.of(widget.initial?.value ?? const []);
  List<GlobalSearchFilterChoice> _choices = const [];
  String? _error;
  String? _lookupError;
  bool _loading = false;
  int _generation = 0;
  bool get _multiple => widget.filter.kind == GlobalSearchFilterKind.multi;
  bool get _choicesOnly => widget.filter.kind == GlobalSearchFilterKind.choice;
  bool get _searchable =>
      _multiple ||
      _choicesOnly ||
      widget.filter.choices.isNotEmpty ||
      const [
        'author',
        'topicAuthor',
        'authorGroup',
        'groupInbox',
        'chatAuthor',
        'chatChannel',
        'adminUserMessages',
        'assignee',
        'groupMember',
        'userName',
        'userGroup',
      ].contains(widget.filter.id);

  @override
  void initState() {
    super.initState();
    if (_searchable) unawaited(_loadChoices(_text.text));
  }

  @override
  void dispose() {
    _generation++;
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadChoices(String query) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _lookupError = null;
    });
    try {
      if (query.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted || generation != _generation) return;
      }
      final values = await widget.controller.lookupChoices(
        widget.filter,
        query,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _choices = values;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _lookupError = 'Suggestions could not load.';
      });
    }
  }

  void _choose(String value) {
    setState(() {
      _error = null;
      if (_multiple) {
        if (_values.contains(value)) {
          _values.remove(value);
        } else {
          _values.add(value);
        }
      } else {
        _values = [value];
        if (!_choicesOnly) _text.text = value;
      }
    });
  }

  void _apply() {
    final values = _multiple || _choicesOnly
        ? _values
        : _text.text
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
    final condition = GlobalSearchCondition(
      filterId: widget.filter.id,
      operator: _operator,
      value: List.of(values),
    );
    final error = validateGlobalSearchCondition(
      condition,
      widget.controller.capabilities,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    try {
      widget.onApply(condition);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.onBack != null) ...[
                  DButton.iconOnly(
                    icon: const DIcon(DIcons.chevronLeft, size: 14),
                    tooltip: 'Back to filters',
                    onPressed: widget.onBack,
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(child: DLabel(child: Text(filter.label))),
              ],
            ),
            const SizedBox(height: 12),
            DSelect<String>.controlled(
              key: const ValueKey('global-search-filter-operator'),
              value: _operator,
              onChanged: (value) {
                if (value != null) setState(() => _operator = value);
              },
              semanticLabel: '${filter.label} condition',
              width: double.infinity,
              entries: [
                for (final op in filter.operators)
                  DSelectItem(
                    value: op.value,
                    textValue: op.label,
                    child: Text(op.label),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_multiple && _values.isNotEmpty) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final value in _values)
                    DBadge.action(
                      trailing: const DIcon(DIcons.xmark, size: 10),
                      variant: DBadgeVariant.secondary,
                      semanticLabel:
                          'Remove ${_searchChoiceLabel(context, widget.controller, filter, value)}',
                      onPressed: () => _choose(value),
                      child: Text(
                        _searchChoiceLabel(
                          context,
                          widget.controller,
                          filter,
                          value,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (_searchable)
              _choiceList(context)
            else if (filter.kind == GlobalSearchFilterKind.date)
              DDatePicker.controlled(
                key: const ValueKey('global-search-filter-value'),
                value: switch (DateTime.tryParse(_text.text)) {
                  final date? => DCalendarDate.fromDateTime(date),
                  null => null,
                },
                onChanged: (value) =>
                    setState(() => _text.text = value?.toString() ?? ''),
                semanticLabel: filter.label,
                width: double.infinity,
                closeBehavior: DDatePickerCloseBehavior.onSelection,
              )
            else
              DInput(
                key: const ValueKey('global-search-filter-value'),
                controller: _text,
                semanticLabel: '${filter.label} value',
                hintText: filter.placeholder,
                autofocus: true,
                keyboardType: filter.kind == GlobalSearchFilterKind.number
                    ? TextInputType.number
                    : TextInputType.text,
                onSubmitted: (_) => _apply(),
              ),
            if (filter.help.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                filter.help,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: DTokens.of(context).mutedForeground,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: DTokens.of(context).destructive,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DButton(
                key: const ValueKey('global-search-filter-apply'),
                label: Text(
                  widget.initial == null ? 'Add condition' : 'Apply changes',
                ),
                onPressed: _apply,
                size: DButtonSize.small,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceList(BuildContext context) {
    final query = _choicesOnly ? '' : _text.text;
    return DCommand<String>(
      query: _text.text,
      onQueryChanged: (value) {
        setState(() {
          _error = null;
          if (!_multiple && !_choicesOnly) _values = [value];
        });
        unawaited(_loadChoices(value));
      },
      onSelected: _choose,
      shouldFilter: widget.filter.choices.isNotEmpty,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DCommandInput<String>(
            key: const ValueKey('global-search-filter-value'),
            controller: _text,
            placeholder: widget.filter.placeholder.isEmpty
                ? 'Find an option…'
                : widget.filter.placeholder,
            semanticLabel: '${widget.filter.label} value',
          ),
          DCommandList<String>(
            maxHeight: 190,
            children: [
              for (final choice in _choices)
                DCommandItem<String>(
                  value: choice.value,
                  searchValue: '${choice.label} ${choice.value}',
                  checked: _values.contains(choice.value),
                  child: Text(choice.label),
                ),
              if (!_choicesOnly &&
                  query.trim().isNotEmpty &&
                  !_choices.any((choice) => choice.value == query.trim()))
                DCommandItem<String>(
                  value: query.trim(),
                  forceMount: true,
                  child: Text('Use “${query.trim()}”'),
                ),
              if (_loading)
                const DCommandLoading(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: DSpinner(size: 16),
                  ),
                ),
              if (!_loading && _lookupError == null)
                const DCommandEmpty(child: Text('No matching options.')),
            ],
          ),
          if (_lookupError != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _lookupError!,
                    style: TextStyle(
                      color: DTokens.of(context).mutedForeground,
                      fontSize: 12,
                    ),
                  ),
                ),
                DButton(
                  label: const Text('Retry'),
                  onPressed: () => _loadChoices(_text.text),
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

DIconData _filterIcon(String name) => switch (name) {
  'search' => DIcons.magnifyingGlass,
  'mail' => DIcons.envelope,
  'hash' => DIcons.tag,
  'status' => DIcons.circleCheck,
  'topics' || 'post' => DIcons.comments,
  'calendar' => DIcons.byName['calendar-days'] ?? DIcons.filter,
  _ => DIcons.byName[name] ?? DIcons.filter,
};

String _searchChoiceLabel(
  BuildContext context,
  GlobalSearchController controller,
  GlobalSearchFilter filter,
  String value,
) {
  final cached = controller.choiceLabel(filter.id, value);
  if (cached != null) return cached;
  final choice = filter.choices
      .where((choice) => choice.value == value)
      .firstOrNull;
  if (choice != null) return choice.label;
  if (filter.id == 'category') {
    final category = ShellScope.maybeOf(
      context,
    )?.categoryFor(int.tryParse(value), siteUrl: controller.siteUrl);
    if (category != null) return category.name;
  }
  return value;
}
