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
        : globalSearchFilter(
            condition.filterId,
            widget.controller.capabilities,
          );
    final editor = _editing ?? definition;
    return DPopover(
      controller: _popover,
      onOpenChange: (open, _) {
        if (!open && mounted) setState(() => _editing = null);
      },
      content: DPopoverContent(
        width: switch (editor?.id) {
          'tags' => 430,
          'category' => 420,
          _ => 350,
        },
        align: DPopoverAlign.end,
        padding: EdgeInsets.zero,
        semanticLabel: editor == null
            ? context.l10n.addSearchFilter
            : context.l10n.editCondition((editor.label).toString()),
        child: editor == null
            ? _catalogue(context)
            : editor.id == 'category'
            ? _GlobalSearchCategoryEditor(
                key: ValueKey((
                  widget.conditionIndex,
                  widget.controller.siteUrl,
                  widget.controller.capabilities.username,
                  widget.controller.categoryLookupSession,
                )),
                controller: widget.controller,
                initial: condition,
                onBack: condition == null
                    ? () => setState(() => _editing = null)
                    : null,
                onCancel: _popover.close,
                onApply: (value) {
                  final index = widget.conditionIndex;
                  if (index == null) {
                    widget.controller.addCondition(value);
                  } else {
                    widget.controller.updateCondition(index, value);
                  }
                  _popover.close();
                },
              )
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
              tooltip: context.l10n.addFilter,
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
            context: context,
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
                    tooltip: context.l10n.removeCondition(
                      (definition.label).toString(),
                    ),
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
      semanticLabel: context.l10n.searchFilters,
      onSelected: (id) => setState(
        () => _editing = globalSearchFilter(id, widget.controller.capabilities),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DCommandInput<String>(
            placeholder: context.l10n.addFilterGlobalsearchfilterpicker,
            semanticLabel: context.l10n.findASearchFilter,
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
                        leading: DIcon(
                          _filterIcon(context, filter.icon),
                          size: 15,
                        ),
                        trailing: const DIcon(DIcons.chevronRight, size: 12),
                        child: Text(filter.label),
                      ),
                  ],
                ),
              DCommandEmpty(child: Text(context.l10n.noFiltersMatchYourSearch)),
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
  String? _choicesQuery;
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
      widget.filter.lookup != GlobalSearchLookup.none;
  bool get _choicesCurrent =>
      widget.filter.choices.isNotEmpty || _choicesQuery == _text.text;
  bool _isTypedValue(String value) =>
      !_tags && !_choicesOnly && value == _text.text.trim();

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
      if (_tags) {
        _choices = widget.controller.cachedTagChoices(query);
        _choicesQuery = query;
      }
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
        _choicesQuery = query;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _lookupError = _tags
            ? widget.controller.cachedTagChoices('').isEmpty
                  ? appL10n.couldnTLoadTagsGlobalsearchfilterpicker
                  : appL10n.couldnTRefreshTags
            : appL10n.suggestionsCouldNotLoad;
      });
    }
  }

  void _choose(String value) {
    if (!(_multiple && _values.contains(value)) &&
        !_isTypedValue(value) &&
        !(_choicesCurrent && _choices.any((choice) => choice.value == value))) {
      return;
    }
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
                    tooltip: context.l10n.backToFilters,
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
            if (!_tags && filter.operators.length > 1) ...[
              _operatorPicker(),
              const SizedBox(height: 8),
            ],
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
                semanticLabel: context.l10n.valueGlobalsearchfilterpicker(
                  (filter.label).toString(),
                ),
                hintText: filter.placeholder,
                autofocus: true,
                keyboardType: filter.kind == GlobalSearchFilterKind.number
                    ? TextInputType.number
                    : TextInputType.text,
                onSubmitted: (_) => _apply(),
              ),
            if (_tags) ...[
              const SizedBox(height: 16),
              DLabel(child: Text(context.l10n.matchTopicsThat)),
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
                      ? context.l10n.applyChanges
                      : _tags
                      ? context.l10n.addFilter
                      : context.l10n.addCondition,
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
            'any' => appL10n.includeAnySelectedTag,
            'all' => appL10n.includeEverySelectedTag,
            'none' => appL10n.excludeAnySelectedTag,
            'notAll' => appL10n.excludeThisCombination,
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
          ? appL10n.matchTopicsThat
          : appL10n.condition((widget.filter.label).toString()),
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
          semanticLabel: context.l10n.removeGlobalsearchfilterpicker(
            (_searchChoiceLabel(
              context,
              widget.controller,
              widget.filter,
              value,
            )).toString(),
          ),
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
      semanticLabel: context.l10n.availableTags,
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
                  placeholder: context.l10n.searchAvailableTags,
                  semanticLabel:
                      context.l10n.searchAvailableTagsGlobalsearchfilterpicker,
                ),
              ),
              if (query.isNotEmpty) ...[
                const SizedBox(width: 4),
                DButton.iconOnly(
                  icon: const DIcon(DIcons.xmark),
                  tooltip: context.l10n.clearSearch,
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
                Text(
                  context.l10n.selectedGlobalsearchfilterpicker(
                    (_values.length).toString(),
                  ),
                  style: mutedStyle,
                ),
                DButton(
                  label: Text(context.l10n.clearSelection, softWrap: true),
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
                      ? context.l10n.showingSavedTagsMoreMayBeAvailable
                      : context.l10n.tryAgainToSeeAvailableTags,
                ),
              ),
              action: DAlertAction(
                child: DButton(
                  label: Text(context.l10n.retry),
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
                      context.l10n.messageGlobalsearchfilterpicker(
                        (saved).toString(),
                        ((saved) ? (context.l10n.savedTags) : '').toString(),
                        (_choices.length).toString(),
                        ((!(saved)) ? (query.isEmpty) : '').toString(),
                        (((!(saved)) && (query.isEmpty))
                                ? (context.l10n.availableTags)
                                : '')
                            .toString(),
                        (((!(saved)) && (query.isNotEmpty))
                                ? (context.l10n.matchingTags)
                                : '')
                            .toString(),
                      ),
                      style: mutedStyle,
                    ),
                  ),
                  if (showCounts) Text(context.l10n.topics, style: mutedStyle),
                  const SizedBox(width: 24),
                ],
              ),
            ),
          DCommandList<String>(
            maxHeight: 240,
            semanticLabel: context.l10n.tagSuggestions,
            children: [
              for (final choice in _choices)
                DCommandItem<String>(
                  value: choice.value,
                  checked: _values.contains(choice.value),
                  semanticLabel: switch (choice.topicCount) {
                    final count? =>
                      '${choice.label}, ${countLabel(count, CountNoun.topic)}',
                    null => choice.label,
                  },
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
              DCommandLoading(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [Expanded(child: Text(context.l10n.findingTags))],
                  ),
                ),
              ),
              if (!saved || hasSavedTags)
                DCommandEmpty(
                  child: Column(
                    children: [
                      Text(
                        query.isEmpty
                            ? context.l10n.noTagsAvailable
                            : context.l10n.messageGlobalsearchfilterpickerValue(
                                (saved).toString(),
                                ((saved) ? (context.l10n.noSavedTagsMatch) : '')
                                    .toString(),
                                (query).toString(),
                                ((!(saved)) ? (context.l10n.noTagsMatch) : '')
                                    .toString(),
                              ),
                      ),
                      if (query.isNotEmpty)
                        DButton(
                          label: Text(context.l10n.clearSearch),
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
                ? context.l10n.findAnOption
                : widget.filter.placeholder,
            semanticLabel: context.l10n.valueGlobalsearchfilterpicker(
              (widget.filter.label).toString(),
            ),
          ),
          DCommandList<String>(
            maxHeight: 190,
            children: [
              for (final choice in _choices)
                DCommandItem<String>(
                  value: choice.value,
                  searchValue: '${choice.label} ${choice.value}',
                  enabled: _choicesCurrent || _isTypedValue(choice.value),
                  checked: _values.contains(choice.value),
                  child: Text(choice.label),
                ),
              if (!_choicesOnly &&
                  query.trim().isNotEmpty &&
                  !_choices.any((choice) => choice.value == query.trim()))
                DCommandItem<String>(
                  value: query.trim(),
                  forceMount: true,
                  child: Text(context.l10n.use((query.trim()).toString())),
                ),
              if (_loading) const DCommandLoading(child: SizedBox.shrink()),
              if (!_loading && _lookupError == null)
                DCommandEmpty(child: Text(context.l10n.noMatchingOptions)),
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
                  label: Text(context.l10n.retry),
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

DIconData _filterIcon(BuildContext context, String name) => switch (name) {
  'search' => DIcons.magnifyingGlass,
  'mail' => DIcons.envelope,
  'hash' => DIcons.tag,
  'status' => DIcons.circleCheck,
  'topics' || 'post' => DIcons.comments,
  'calendar' => pluginIconNamed(context, 'calendar-days') ?? DIcons.filter,
  _ => pluginIconNamed(context, name) ?? DIcons.filter,
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
