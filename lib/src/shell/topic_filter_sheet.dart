part of 'topic_filter_input.dart';

/// The list sheet keeps its editor and results in one Native command surface.
/// Its vocabulary and comparison operators still come from the forum.
extension _TopicFilterSheet on _TopicFilterInputState {
  bool get _canFinishTags =>
      _sheetTags.isNotEmpty ||
      splitTopicFilterQuery(
        widget.initialQuery,
      ).any((t) => RegExp(r'^-?tags?:').hasMatch(t));
  List<({List<int> indices, List<String> tokens, String? label})>
  _displayTokens() {
    final result =
        <({List<int> indices, List<String> tokens, String? label})>[];
    final consumed = <int>{};
    final fields = topicFilterMenuFields(filter.engine.options);
    for (var i = 0; i < _tokens.length; i++) {
      if (consumed.contains(i)) continue;
      final raw = _tokens[i];
      final key = topicFilterClauseKey(
        raw,
      )?.replaceFirst(RegExp(r'^[-=]+'), '');
      final field = fields
          .where(
            (f) =>
                f.keys.contains(key) &&
                (key != 'in:' || f.options.any((o) => o.name == raw)),
          )
          .firstOrNull;
      var value = _topicFilterTokenLabel(raw, widget.categories);
      value = value.contains(':')
          ? value.substring(value.indexOf(':') + 1).trim()
          : value;
      final indices = [i];
      final tokens = [raw];
      if (widget.embedded && field != null) {
        final n = int.tryParse(raw.substring(raw.indexOf(':') + 1));
        if (field.number && n != null && n >= 0) {
          final number = field.id == 'replies' ? (n - 1).clamp(0, n) : n;
          value =
              '${key!.endsWith('-max:') ? _sentenceCaseTopicFilterValue(appL10n.atMost) : _sentenceCaseTopicFilterValue(appL10n.atLeast)} $number';
          final counterpart =
              '${key.replaceFirst(key.endsWith('-max:') ? '-max:' : '-min:', key.endsWith('-max:') ? '-min:' : '-max:')}$n';
          final pair = _tokens.indexOf(counterpart);
          if (pair >= 0 && pair != i && !consumed.contains(pair)) {
            indices.add(pair);
            tokens.add(_tokens[pair]);
            value = '${appL10n.filterExactly} $number';
          }
        } else if (field.id == 'tags' && RegExp(r'^-?tags?:').hasMatch(raw)) {
          final all = raw.contains('+');
          final negative = raw.startsWith('-');
          value = value.replaceAll(RegExp('[,+]'), ', ');
          if (all || negative || value.contains(', ')) {
            value =
                '${negative ? (all ? appL10n.filterNotAll : appL10n.none) : (all ? appL10n.filterAll : appL10n.filterAny)} $value';
          }
        } else if (field.date) {
          value =
              '${key!.contains('-before:') ? appL10n.filterBefore : appL10n.filterAfter} $value';
        }
      }
      consumed.addAll(indices);
      result.add((
        indices: indices,
        tokens: tokens,
        label: widget.embedded && field != null
            ? '${field.label}: $value'
            : null,
      ));
    }
    return result;
  }

  void _editDisplayToken(
    ({List<int> indices, List<String> tokens, String? label}) group,
  ) {
    if (!widget.embedded || group.indices.length == 1) {
      _editToken(group.indices.first);
      return;
    }
    _changeSheet(
      () => _tokens = [
        for (var i = 0; i < _tokens.length; i++)
          if (!group.indices.contains(i)) _tokens[i],
      ],
    );
    final key = topicFilterClauseKey(group.tokens.first)!;
    _activeMenuField = topicFilterMenuFields(
      widget.options,
    ).where((f) => f.keys.contains(key)).firstOrNull?.id;
    _setTokenDraft(key);
    filter.updateEngine(_engine(_shell!));
    _focus.requestFocus();
    widget.onChanged?.call(_composeTokenQuery());
    unawaited(filter.openSuggestions());
  }

  Future<bool> _sheetAction(String? value) async {
    if (value == '@apply' || value == '@clear') {
      await widget.onSubmitted(value == '@clear' ? '' : _composeTokenQuery());
      return true;
    }
    if (value == '@done-tags') {
      if (!_canFinishTags) return true;
      if (widget.onlyKey == 'tag') {
        await widget.onSubmitted(_tokens.join(' '));
      } else {
        _setTokenDraft('');
        _focus.requestFocus();
        unawaited(filter.openSuggestions());
      }
      return true;
    }
    return value == '@tag-mode';
  }

  String _commandValue(TopicFilterSuggestion item) =>
      item.menuField == null ? item.name : '${item.menuField}|${item.name}';
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
    if (item.menuGroup != null) return item.menuGroup!;
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
      (groups[suggestion.menuGroup ??
                  (clauseKey == null ? _sheetGroup(suggestion) : '')] ??=
              [])
          .add(suggestion);
    }
    Widget row(TopicFilterSuggestion suggestion) => Row(
      children: [
        if (_isTagStage &&
            RegExp(r'^tags?:').hasMatch(suggestion.name) &&
            suggestion.term != null)
          IgnorePointer(
            child: ExcludeSemantics(
              child: DCheckbox(
                value: _sheetTags.contains(
                  _unquoteTopicFilterValue(suggestion.term!),
                ),
                readOnly: true,
                onChanged: (_) {},
              ),
            ),
          )
        else if (suggestion.menuIcon case final icon?)
          DIcon(
            DIcons.byName[icon] ?? DNativeIcons.byName[icon] ?? DIcons.filter,
            size: 14,
          )
        else if (suggestion.category case final category?)
          CategoryIcon(
            category: category,
            parentCategory: suggestion.parentCategory,
            size: 16,
            siteUrl: widget.siteUrl,
          )
        else if (suggestion.term != null &&
            const {'username', 'username_group_list'}.contains(option?.type))
          DAvatar(
            dimension: 20,
            border: false,
            fallback: DAvatarFallback(
              child: Text(suggestion.term!.characters.first.toUpperCase()),
            ),
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
    final tagModes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DToggleGroup<String>(
          values: [_tagMode],
          allowEmptySelection: false,
          density: DToggleDensity.menuFilter,
          semanticLabel: context.l10n.matchTopicsThat,
          items: [
            for (final (value, label) in [
              ('any', context.l10n.filterAny),
              ('all', context.l10n.filterAll),
              ('none', context.l10n.none),
              ('notAll', context.l10n.filterNotAll),
            ])
              DToggleGroupItem(value: value, child: Text(label)),
          ],
          onChanged: _sheetTags.isEmpty
              ? null
              : (values) {
                  _tagMode = values.single;
                  _setSheetTags(_sheetTags);
                },
        ),
        Text(switch (_tagMode) {
          'all' => context.l10n.filterAllHint,
          'none' => context.l10n.filterNoneHint,
          'notAll' => context.l10n.filterNotAllHint,
          _ => context.l10n.filterAnyHint,
        }, style: TextStyle(color: DTokens.of(context).mutedForeground)),
      ],
    );
    final command = DCommand<String>(
      key: _sheetCommandKey,
      backgroundColor: Colors.transparent,
      controller: _sheetCommand,
      query: filter.text.text,
      shouldFilter: false,
      onValueChanged: (value) {
        final index = filter.suggestions.indexWhere(
          (item) => _commandValue(item) == value,
        );
        if (index >= 0) filter.select(index);
      },
      onQueryChanged: filter.inputChanged,
      onSelected: (value) {
        if (value.startsWith('@')) {
          unawaited(_sheetAction(value));
          return;
        }
        final suggestion = filter.suggestions
            .where((item) => _commandValue(item) == value)
            .firstOrNull;
        if (suggestion != null) unawaited(_acceptSuggestion(suggestion));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_tokens.isNotEmpty)
                Flexible(
                  flex: 2,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 90),
                    child: DScrollArea(child: _buildTokens()),
                  ),
                ),
              Expanded(
                child: Focus(
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
              ),
            ],
          ),
          const DSeparator(),
          if (option?.type == 'date' &&
              (_activeMenuField == null || _menuDateSelected))
            DCalendar(
              onSelectionChanged: (selection, _) {
                if (selection is! DCalendarSingleSelection ||
                    selection.date == null) {
                  return;
                }
                final value = selection.date!;
                _setTokenDraft('${option!.name}$value');
                _commitTokenDraft();
                _focus.requestFocus();
                unawaited(filter.openSuggestions());
              },
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
                if (_activeMenuField != null) {
                  unawaited(_acceptSelectedOrFallback());
                  return;
                }
                _setTokenDraft('${option.name}$value');
                _commitTokenDraft();
                _focus.requestFocus();
                unawaited(filter.openSuggestions());
              },
            ),
          if (!(option?.type == 'date' &&
              (_activeMenuField == null || _menuDateSelected)))
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
                  if (clauseKey == null &&
                      filter.text.text.isEmpty &&
                      (_tokens.isNotEmpty || widget.initialQuery.isNotEmpty))
                    DCommandItem<String>(
                      key: const ValueKey('topic-filter-apply'),
                      value: _tokens.isEmpty ? '@clear' : '@apply',
                      leading: const DIcon(DIcons.filter, size: 14),
                      trailing: const DIcon(DNativeIcons.arrowRight, size: 12),
                      child: Text(
                        _tokens.isEmpty
                            ? context.l10n.clearFilter
                            : context.l10n.filterApplyCount(
                                _displayTokens().length,
                              ),
                      ),
                    ),
                  if (_isTagStage) ...[
                    DCommandItem<String>(
                      key: const ValueKey('topic-filter-done-tags'),
                      value: '@done-tags',
                      enabled: _canFinishTags,
                      leading: const DIcon(DIcons.tag, size: 14),
                      trailing: const DIcon(DIcons.check, size: 12),
                      child: Text(
                        '${context.l10n.done}  ${_sheetTags.isEmpty ? context.l10n.filterNoTagsYet : _sheetTags.join(', ')}',
                      ),
                    ),
                    DCommandGroup<String>(
                      heading: Text(context.l10n.searchFilterMatch),
                      items: [
                        DCommandItem<String>(
                          value: '@tag-mode',
                          enabled: _sheetTags.isNotEmpty,
                          child: tagModes,
                        ),
                      ],
                    ),
                  ],
                  for (final group in groups.entries)
                    DCommandGroup<String>(
                      heading: group.key.isEmpty ? null : Text(group.key),
                      items: [
                        for (final suggestion in group.value)
                          DCommandItem<String>(
                            key: ValueKey(
                              'topic-filter-suggestion-${filter.suggestions.indexOf(suggestion)}',
                            ),
                            value: _commandValue(suggestion),
                            checked:
                                _isTagStage &&
                                suggestion.term != null &&
                                _sheetTags.contains(
                                  _unquoteTopicFilterValue(suggestion.term!),
                                ),
                            trailing: _isTagStage
                                ? Text(
                                    int.tryParse(
                                              suggestion.description ?? '',
                                            ) !=
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
