part of 'topic_filter_input.dart';

/// The list sheet keeps its editor and results in one Native command surface.
/// Its vocabulary and comparison operators still come from the forum.
extension _TopicFilterSheet on _TopicFilterInputState {
  bool get _isTagStage => RegExp(r'^-?tags?:').hasMatch(filter.text.text);

  List<String> get _sheetTags {
    final token = _tokens
        .where((value) => RegExp(r'^-?tags?:').hasMatch(value))
        .lastOrNull;
    if (token == null) return [];
    return _unquoteTopicFilterValue(
      token.substring(token.indexOf(':') + 1),
    ).split(RegExp('[,+]'));
  }

  void _setSheetTags(List<String> tags) {
    _changeSheet(() {
      _tokens = [
        for (final token in _tokens)
          if (!RegExp(r'^-?tags?:').hasMatch(token)) token,
        if (tags.isNotEmpty)
          '${_tagMode == 'none' || _tagMode == 'notAll' ? '-' : ''}tag:${topicFilterScopeValue(tags.join(_tagMode == 'all' || _tagMode == 'notAll' ? '+' : ','))}',
      ];
    });
    widget.onChanged?.call(_tokens.join(' '));
  }

  void _toggleSheetTag(String tag) {
    final tags = _sheetTags;
    if (!tags.remove(tag)) tags.add(tag);
    _setSheetTags(tags);
    _setTokenDraft('tag:');
    _focus.requestFocus();
    unawaited(filter.openSuggestions());
  }

  void _stepBackScope() {
    if (widget.onlyKey == 'tag') {
      final tags = _sheetTags;
      if (tags.isNotEmpty) _setSheetTags(tags..removeLast());
      return;
    }
    final index = _tokens.lastIndexWhere(
      (token) => RegExp(r'^=?category:').hasMatch(token),
    );
    if (index < 0) return;
    final token = _tokens[index];
    final id = parseTopicFilterScope(
      token.replaceFirst(RegExp(r'^='), ''),
      widget.categories,
    ).categoryId;
    final category = widget.categories
        .where((item) => item.id == id)
        .firstOrNull;
    _changeSheet(() {
      final next = _tokens.toList();
      if (token.startsWith('=')) {
        next[index] = token.substring(1);
        _categoryExact = false;
      } else if (category?.parentCategoryId case final parent?) {
        next[index] = 'category:$parent';
      } else {
        next.removeAt(index);
      }
      _tokens = next;
    });
    widget.onChanged?.call(_tokens.join(' '));
  }

  String _sheetGroup(TopicFilterSuggestion item) {
    final name = item.name.replaceAll(RegExp(r'^[-=]+'), '');
    final type = widget.options
        .where((option) => name.startsWith(option.name))
        .firstOrNull
        ?.type;
    if (type == 'date' || type == 'number') return appL10n.datesCounts;
    if (const {'username', 'username_group_list', 'group'}.contains(type)) {
      return appL10n.people;
    }
    if (name.startsWith('category:') ||
        name.startsWith('tag:') ||
        name.startsWith('topic:')) {
      return appL10n.where;
    }
    return appL10n.content;
  }

  Widget _buildSheet(BuildContext context) {
    final clauseKey = topicFilterClauseKey(filter.text.text);
    final option = widget.options
        .where((option) => option.name == clauseKey)
        .firstOrNull;
    final groups = <String, List<TopicFilterSuggestion>>{};
    for (final suggestion in filter.suggestions) {
      if (_isTagStage && suggestion.term == null) continue;
      (groups[clauseKey == null ? _sheetGroup(suggestion) : ''] ??= []).add(
        suggestion,
      );
    }
    Widget row(TopicFilterSuggestion suggestion) => Row(
      children: [
        if (_isTagStage)
          SizedBox.square(
            dimension: 16,
            child:
                suggestion.term != null &&
                    _sheetTags.contains(
                      _unquoteTopicFilterValue(suggestion.term!),
                    )
                ? const DIcon(DIcons.check, size: 16)
                : null,
          )
        else if (suggestion.category case final category?)
          CategoryIcon(
            category: category,
            parentCategory: suggestion.parentCategory,
            size: 16,
            siteUrl: widget.siteUrl,
          )
        else
          _topicFilterSuggestionIcon(suggestion),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      suggestion.displayName ??
                      (suggestion.category != null
                          ? suggestion.description
                          : null) ??
                      (suggestion.term != null
                          ? _unquoteTopicFilterValue(suggestion.term!)
                          : _sentenceCaseTopicFilterValue(
                              suggestion.name
                                  .replaceFirst(RegExp(r'^-'), '− ')
                                  .replaceAll(RegExp(r':$'), '')
                                  .replaceAll(':', ': '),
                            )),
                ),
                if (suggestion.term == null &&
                    suggestion.category == null &&
                    suggestion.description != null)
                  TextSpan(
                    text: '  ${suggestion.description}',
                    style: TextStyle(
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (suggestion.hasChildren)
          DButton.iconOnly(
            key: ValueKey(
              'topic-filter-category-into-${suggestion.category!.id}',
            ),
            icon: const DIcon(DIcons.chevronRight, size: 12),
            tooltip: context.l10n.subcategoriesOf(suggestion.category!.name),
            size: DButtonSize.small,
            variant: DButtonVariant.ghost,
            onPressed: () => _browseCategory(suggestion.category),
          ),
      ],
    );
    final command = DCommand<String>(
      key: _sheetCommandKey,
      backgroundColor: Colors.transparent,
      controller: _sheetCommand,
      query: filter.text.text,
      value: filter.selected?.name,
      shouldFilter: false,
      onValueChanged: (value) {
        final index = filter.suggestions.indexWhere(
          (item) => item.name == value,
        );
        if (index >= 0) filter.select(index);
      },
      onQueryChanged: filter.inputChanged,
      onSelected: (value) {
        final suggestion = filter.suggestions
            .where((item) => item.name == value)
            .firstOrNull;
        if (suggestion != null) unawaited(_acceptSuggestion(suggestion));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: DCommandInput<String>(
              borderless: true,
              autofocus: widget.focusOnOpen,
              key: widget.inputKey,
              controller: filter.text,
              focusNode: _focus,
              placeholder: widget.hintText,
              semanticLabel: context.l10n.topicFilterQuery,
            ),
          ),
          const DSeparator(),
          if (_isTagStage)
            Row(
              children: [
                DLabel(child: Text(context.l10n.searchFilterMatch)),
                const SizedBox(width: 8),
                Expanded(
                  child: DSelect<String>.controlled(
                    value: _tagMode,
                    semanticLabel: context.l10n.matchTopicsThat,
                    isExpanded: true,
                    size: DSelectSize.small,
                    entries: [
                      for (final (value, label) in [
                        ('any', context.l10n.includeAny),
                        ('all', context.l10n.includeAll),
                        ('none', context.l10n.excludeAny),
                        ('notAll', context.l10n.excludeCombination),
                      ])
                        DSelectItem(
                          value: value,
                          textValue: label,
                          child: Text(label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _tagMode = value;
                      _setSheetTags(_sheetTags);
                    },
                  ),
                ),
              ],
            ),
          if (option?.type == 'date')
            DDatePicker.controlled(
              semanticLabel: option!.description ?? option.name,
              value: null,
              onChanged: (value) {
                if (value == null) return;
                _setTokenDraft('${option.name}$value');
                _commitTokenDraft();
                _focus.requestFocus();
                unawaited(filter.openSuggestions());
              },
            ),
          if (clauseKey == 'category:')
            DToggle(
              pressed: !_categoryExact,
              size: DToggleSize.small,
              onPressedChanged: (value) =>
                  _changeSheet(() => _categoryExact = !value),
              child: Text(context.l10n.includeSubcategories),
            ),
          if (option?.type == 'number')
            DInput(
              key: ValueKey('topic-filter-number-${option!.name}'),
              semanticLabel: option.description ?? option.name,
              hintText: '0',
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _setTokenDraft('${option.name}$value');
                filter.inputChanged(filter.text.text);
              },
              onSubmitted: (value) {
                if (int.tryParse(value) == null || int.parse(value) < 0) return;
                _setTokenDraft('${option.name}$value');
                _commitTokenDraft();
                _focus.requestFocus();
                unawaited(filter.openSuggestions());
              },
            ),
          Flexible(
            child: DCommandList<String>(
              maxHeight:
                  const {
                    TargetPlatform.iOS,
                    TargetPlatform.android,
                    TargetPlatform.fuchsia,
                  }.contains(Theme.of(context).platform)
                  ? MediaQuery.sizeOf(context).height
                  : 360,
              children: [
                for (final group in groups.entries)
                  DCommandGroup<String>(
                    heading: group.key.isEmpty ? null : Text(group.key),
                    items: [
                      for (final suggestion in group.value)
                        DCommandItem<String>(
                          key: ValueKey(
                            'topic-filter-suggestion-${filter.suggestions.indexOf(suggestion)}',
                          ),
                          value: suggestion.name,
                          checked:
                              _isTagStage &&
                              suggestion.term != null &&
                              _sheetTags.contains(
                                _unquoteTopicFilterValue(suggestion.term!),
                              ),
                          trailing: _isTagStage
                              ? Text(
                                  int.tryParse(suggestion.description ?? '') !=
                                          null
                                      ? suggestion.description!
                                      : '',
                                )
                              : null,
                          child: row(suggestion),
                        ),
                    ],
                  ),
                DCommandEmpty(child: Text(context.l10n.noResultsFound)),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tokens.isNotEmpty || _isTagStage)
          SizedBox(height: 90, child: DScrollArea(child: _buildTokens())),
        Flexible(
          child:
              option?.type == 'date' ||
                  option?.type == 'number' ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.5
              ? DScrollArea(child: command)
              : command,
        ),
      ],
    );
  }
}
