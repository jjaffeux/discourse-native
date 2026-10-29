part of 'topic_filter_input.dart';

/// The list sheet keeps its editor and results in one Native command surface.
/// Its vocabulary and comparison operators still come from the forum.
extension _TopicFilterSheet on _TopicFilterInputState {
  int _categoryCount(TopicCategory category, {bool exact = false}) {
    if (exact) return category.topicCount;
    final visited = <int>{};
    int count(TopicCategory item) {
      if (!visited.add(item.id)) return 0;
      return item.topicCount +
          widget.categories
              .where((child) => child.parentCategoryId == item.id)
              .fold<int>(0, (total, child) => total + count(child));
    }

    return count(category);
  }

  bool get _canFinishTags =>
      _sheetTags.isNotEmpty ||
      _tokens.any(_isTagScopeToken) ||
      splitTopicFilterQuery(widget.initialQuery).any(_isTagScopeToken);
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
          if (!_isTagScopeToken(token)) token,
        if (tags.isNotEmpty)
          '${_tagMode == 'none' || _tagMode == 'notAll' ? '-' : ''}tag:${topicFilterScopeValue(tags.join(_tagMode == 'all' || _tagMode == 'notAll' ? '+' : ','))}',
      ];
    });
    widget.onScopeChanged?.call(_tokens.join(' '));
  }

  Future<void> _toggleSheetTag(String tag) async {
    final tags = _sheetTags;
    if (!tags.remove(tag)) tags.add(tag);
    _setSheetTags(tags);
    _setTokenDraft('tag:');
    _focus.requestFocus();
    await filter.openSuggestions();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selected = filter.suggestions
          .where(
            (item) =>
                item.term != null &&
                _unquoteTopicFilterValue(item.term!) == tag,
          )
          .firstOrNull;
      if (selected != null) _sheetCommand.highlight(_commandValue(selected));
    });
  }

  void _stepBackScope() {
    if (widget.onlyKey == 'tag') {
      final tags = _sheetTags;
      _setSheetTags(tags.isEmpty ? [] : (tags..removeLast()));
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
      } else if (category?.parentCategoryId case final parent?) {
        next[index] = 'category:$parent';
      } else {
        next.removeAt(index);
      }
      _tokens = next;
    });
    widget.onScopeChanged?.call(_tokens.join(' '));
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
                size: DCheckboxSize.compact,
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
        else if (suggestion.categoryUp)
          DIcon(
            Directionality.of(context) == TextDirection.rtl
                ? DIcons.chevronRight
                : DIcons.chevronLeft,
            size: 12,
          )
        else if (suggestion.category case final category?)
          CategoryIcon(
            category: category,
            size: 14,
            squareSize: 9,
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
                      (suggestion.name.startsWith('=category:')
                          ? suggestion.category?.name
                          : null) ??
                      suggestion.displayName ??
                      suggestion.category?.name ??
                      (suggestion.term != null
                          ? _unquoteTopicFilterValue(suggestion.term!)
                          : _sentenceCaseTopicFilterValue(
                              suggestion.name
                                  .replaceFirst(RegExp(r'^-'), '− ')
                                  .replaceAll(RegExp(r':$'), '')
                                  .replaceAll(':', ': '),
                            )),
                  style: suggestion.categoryUp
                      ? TextStyle(color: DTokens.of(context).mutedForeground)
                      : null,
                ),
                if (suggestion.name.startsWith('=category:'))
                  TextSpan(
                    text: context.l10n
                        .filterCategoryOnly(suggestion.category!.name)
                        .substring(suggestion.category!.name.length),
                    style: TextStyle(
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
                if (suggestion.category != null &&
                    !suggestion.categoryUp &&
                    (suggestion.description?.contains(' › ') ?? false))
                  TextSpan(
                    text:
                        '  ${context.l10n.filterCategoryIn(suggestion.description!.split(' › ').reversed.skip(1).toList().reversed.join(' › '))}',
                    style: TextStyle(
                      fontSize: DiscourseTypography.metadata,
                      color: DTokens.of(context).mutedForeground,
                    ),
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
        if (suggestion.category case final category?
            when !suggestion.categoryUp)
          Text(
            '${_categoryCount(category, exact: suggestion.name.startsWith('='))}',
            style: TextStyle(
              fontSize: DiscourseTypography.metadata,
              color: DTokens.of(context).mutedForeground,
            ),
          ),
        if (suggestion.hasChildren)
          DButton.iconOnly(
            key: ValueKey(
              'topic-filter-category-into-${suggestion.category!.id}',
            ),
            icon: DIcon(
              Directionality.of(context) == TextDirection.rtl
                  ? DIcons.chevronLeft
                  : DIcons.chevronRight,
              size: 12,
            ),
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
          wrap: true,
          spacing: 1,
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
      query: widget.onlyKey == null
          ? filter.text.text
          : filter.text.text.replaceFirst('${widget.onlyKey}:', ''),
      shouldFilter: false,
      onValueChanged: (value) {
        final index = filter.suggestions.indexWhere(
          (item) => _commandValue(item) == value,
        );
        if (index >= 0) _selectSheetSuggestion(index);
      },
      onQueryChanged: (value) {
        if (widget.onlyKey != null) _setTokenDraft('${widget.onlyKey}:$value');
        filter.inputChanged(filter.text.text);
      },
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
          RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onKey,
                child: KeyedSubtree(
                  key: const ValueKey('topic-filter-token-field'),
                  child: DCommandInput<String>(
                    density: DCommandInputDensity.menuFilter,
                    tokens: _buildTokenChips(),
                    autofocus: widget.focusOnOpen,
                    key: widget.inputKey,
                    controller: widget.onlyKey == null ? filter.text : null,
                    onEmptyBackspace: widget.onlyKey == null
                        ? null
                        : _stepBackScope,
                    focusNode: _focus,
                    placeholder: widget.hintText,
                    semanticLabel: context.l10n.topicFilterQuery,
                  ),
                ),
              ),
            ),
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
                      showGuide: true,
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
                      showGuide: group.key.isNotEmpty,
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
