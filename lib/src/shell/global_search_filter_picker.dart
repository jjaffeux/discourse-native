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
        width: editor?.id == 'tags' ? 430 : 350,
        align: DPopoverAlign.end,
        padding: EdgeInsets.zero,
        semanticLabel: editor == null
            ? 'Add search filter'
            : 'Edit ${editor.label} condition',
        child: editor == null
            ? _catalogue(context)
            : _GlobalSearchConditionEditor(
                key: ValueKey((
                  editor.id,
                  widget.conditionIndex,
                  widget.controller.configurationRevision,
                )),
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
              icon: DIcon(widget.addOnly ? DIcons.plus : DIcons.filter),
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
                    icon: const DIcon(DIcons.xmark),
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
  final _tagSearchFocus = FocusNode();
  String? _error;
  String? _lookupError;
  bool _loading = false;
  int _generation = 0;
  bool get _tags => widget.filter.id == 'tags';
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
    _tagSearchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadChoices(String query) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _lookupError = null;
      if (_tags) _choices = widget.controller.cachedTagChoices(query);
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
        _lookupError = _tags
            ? widget.controller.cachedTagChoices('').isEmpty
                  ? 'Couldn’t load tags'
                  : 'Couldn’t refresh tags'
            : 'Suggestions could not load.';
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
    if (_tags) _tagSearchFocus.requestFocus();
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
                    icon: const DIcon(DIcons.chevronLeft),
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
            if (!_tags) ...[_operatorPicker(), const SizedBox(height: 8)],
            if (!_tags && _multiple && _values.isNotEmpty) ...[
              _selectedChoices(context),
              const SizedBox(height: 8),
            ],
            if (_tags)
              _tagChoiceList(context)
            else if (_searchable)
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
            if (_tags) ...[
              const SizedBox(height: 16),
              const DLabel(child: Text('Match topics that')),
              const SizedBox(height: 6),
              _operatorPicker(),
            ],
            if (!_tags && filter.help.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                filter.help,
                style: TextStyle(
                  fontSize: DiscourseTypography.xs,
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
                    fontSize: DiscourseTypography.xs,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_tags) ...[const DSeparator(), const SizedBox(height: 12)],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DButton(
                key: const ValueKey('global-search-filter-apply'),
                label: Text(
                  widget.initial != null
                      ? 'Apply changes'
                      : _tags
                      ? 'Add filter'
                      : 'Add condition',
                ),
                onPressed: _tags && _values.isEmpty ? null : _apply,
                size: _tags ? DButtonSize.regular : DButtonSize.small,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _operatorPicker() {
    String label(GlobalSearchFilterOperator op) => _tags
        ? switch (op.value) {
            'any' => 'Include any selected tag',
            'all' => 'Include every selected tag',
            'none' => 'Exclude any selected tag',
            'notAll' => 'Exclude this combination',
            _ => op.label,
          }
        : op.label;
    return DSelect<String>.controlled(
      key: const ValueKey('global-search-filter-operator'),
      value: _operator,
      onChanged: (value) {
        if (value != null) setState(() => _operator = value);
      },
      semanticLabel: _tags
          ? 'Match topics that'
          : '${widget.filter.label} condition',
      width: double.infinity,
      entries: [
        for (final op in widget.filter.operators)
          DSelectItem(
            value: op.value,
            textValue: label(op),
            child: Text(label(op)),
          ),
      ],
    );
  }

  Widget _selectedChoices(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final value in _values)
        DBadge.action(
          trailing: const DIcon(DIcons.xmark, size: 10),
          variant: DBadgeVariant.secondary,
          semanticLabel:
              'Remove ${_searchChoiceLabel(context, widget.controller, widget.filter, value)}',
          onPressed: () => _choose(value),
          child: Text(
            _searchChoiceLabel(
              context,
              widget.controller,
              widget.filter,
              value,
            ),
          ),
        ),
    ],
  );

  void _clearTagSearch() {
    _text.clear();
    _tagSearchFocus.requestFocus();
  }

  Widget _tagChoiceList(BuildContext context) {
    final query = _text.text.trim();
    final saved = _lookupError != null;
    final hasSavedTags = widget.controller.cachedTagChoices('').isNotEmpty;
    final showCounts = _choices.any((choice) => choice.topicCount != null);
    final mutedStyle = TextStyle(
      fontSize: DiscourseTypography.xs,
      color: DTokens.of(context).mutedForeground,
    );
    return DCommand<String>(
      query: _text.text,
      onQueryChanged: (value) {
        setState(() => _error = null);
        unawaited(_loadChoices(value));
      },
      onSelected: _choose,
      shouldFilter: false,
      loading: _loading,
      semanticLabel: 'Available tags',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DCommandInput<String>(
                  key: const ValueKey('global-search-filter-value'),
                  controller: _text,
                  focusNode: _tagSearchFocus,
                  placeholder: 'Search available tags…',
                  semanticLabel: 'Search available tags',
                ),
              ),
              if (query.isNotEmpty) ...[
                const SizedBox(width: 4),
                DButton.iconOnly(
                  icon: const DIcon(DIcons.xmark),
                  tooltip: 'Clear search',
                  variant: DButtonVariant.ghost,
                  onPressed: _clearTagSearch,
                ),
              ],
            ],
          ),
          if (_values.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('Selected · ${_values.length}', style: mutedStyle),
                DButton(
                  label: const Text('Clear selection', softWrap: true),
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  onPressed: () {
                    setState(() => _values.clear());
                    _tagSearchFocus.requestFocus();
                  },
                ),
              ],
            ),
            _selectedChoices(context),
            const SizedBox(height: 8),
          ],
          if (saved) ...[
            DAlert(
              title: DAlertTitle(child: Text(_lookupError!)),
              description: DAlertDescription(
                child: Text(
                  hasSavedTags
                      ? 'Showing saved tags. More may be available.'
                      : 'Try again to see available tags.',
                ),
              ),
              action: DAlertAction(
                child: DButton(
                  label: const Text('Retry'),
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  onPressed: () => _loadChoices(_text.text),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_choices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${saved
                          ? 'Saved tags'
                          : query.isEmpty
                          ? 'Available tags'
                          : 'Matching tags'} · ${_choices.length}',
                      style: mutedStyle,
                    ),
                  ),
                  if (showCounts) Text('Topics', style: mutedStyle),
                  const SizedBox(width: 24),
                ],
              ),
            ),
          DCommandList<String>(
            maxHeight: 240,
            semanticLabel: 'Tag suggestions',
            children: [
              for (final choice in _choices)
                DCommandItem<String>(
                  value: choice.value,
                  checked: _values.contains(choice.value),
                  semanticLabel:
                      '${choice.label}${choice.topicCount == null ? '' : ', ${choice.topicCount} topics'}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (choice.topicCount case final count?)
                        Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatDecimal(count),
                          style: mutedStyle,
                        ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 16,
                        child: _values.contains(choice.value)
                            ? const DIcon(DIcons.check, size: 16)
                            : null,
                      ),
                    ],
                  ),
                  child: _highlightTag(context, choice.label, query),
                ),
              const DCommandLoading(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      DSpinner(size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text('Finding tags…')),
                    ],
                  ),
                ),
              ),
              if (!saved || hasSavedTags)
                DCommandEmpty(
                  child: Column(
                    children: [
                      Text(
                        query.isEmpty
                            ? 'No tags available.'
                            : '${saved ? 'No saved tags match' : 'No tags match'} “$query”',
                      ),
                      if (query.isNotEmpty)
                        DButton(
                          label: const Text('Clear search'),
                          variant: DButtonVariant.ghost,
                          onPressed: _clearTagSearch,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _highlightTag(BuildContext context, String label, String query) {
    final index = label.toLowerCase().indexOf(query.toLowerCase());
    if (query.isEmpty || index < 0) return Text(label);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label.substring(0, index)),
          TextSpan(
            text: label.substring(index, index + query.length),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              backgroundColor: DTokens.of(context).selected,
            ),
          ),
          TextSpan(text: label.substring(index + query.length)),
        ],
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
      loading: _loading,
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
                      fontSize: DiscourseTypography.xs,
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
