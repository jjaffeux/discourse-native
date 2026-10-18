import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import '../theme/discourse_typography.dart';
import 'category_icon.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_filter_controller.dart';
import 'topic_filter_scope.dart';

part 'topic_filter_sheet.dart';

bool _isTagScopeToken(String token) =>
    RegExp(r'^-?(?:tags?|tag-group|tag_group):').hasMatch(token) ||
    const {'in:tagged', 'in:untagged'}.contains(token);

class TopicFilterInputController {
  bool Function()? _handleEscape;
  bool handleEscape() => _handleEscape?.call() ?? false;
}

class TopicFilterInput extends StatefulWidget {
  const TopicFilterInput({
    super.key,
    required this.siteUrl,
    required this.initialQuery,
    required this.options,
    required this.categories,
    required this.onSubmitted,
    this.onChanged,
    this.inputKey = const ValueKey('topic-filter-input'),
    this.clearKey = const ValueKey('clear-topic-filter'),
    this._hintText,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.enabled = true,
    this.tokenized = false,
    this.multiline = false,
    this.onDismiss,
    this.embedded = false,
    this.focusOnOpen = true,
    this.onlyKey,
    this.categoryParentId,
    this.categoryContextId,
    this.onScopeChanged,
    this.controller,
    this.onSuggestionsReady,
  });

  final String siteUrl;
  final String initialQuery;
  final List<TopicFilterOption> options;
  final List<TopicCategory> categories;
  final Future<void> Function(String query) onSubmitted;
  final ValueChanged<String>? onChanged;
  final Key inputKey;
  final Key clearKey;
  final String? _hintText;
  String get hintText =>
      _hintText ?? appL10n.filterTopicsByCategoryTagOrOtherCriteria;
  final EdgeInsetsGeometry padding;
  final bool enabled;
  final bool tokenized;
  final bool multiline;
  final VoidCallback? onDismiss;
  final bool embedded;
  final bool focusOnOpen;
  final String? onlyKey;
  final int? categoryParentId;
  final int? categoryContextId;
  final ValueChanged<String>? onScopeChanged;
  final TopicFilterInputController? controller;
  final VoidCallback? onSuggestionsReady;

  @override
  State<TopicFilterInput> createState() => _TopicFilterInputState();
}

class _TopicFilterInputState extends State<TopicFilterInput> {
  final FocusNode _focus = FocusNode();
  final _combobox = DComboboxController<TopicFilterSuggestion>();
  final _sheetCommand = DCommandController<String>();
  final _sheetCommandKey = GlobalKey();

  ShellController? _shell;
  TopicFilterController? _filter;
  List<String> _tokens = const [];
  bool _updatingTokenDraft = false;
  bool _selectingSheetSuggestion = false;
  int? _categoryParentId;
  bool _visible = true;
  bool _visibilityDismissScheduled = false;
  String _tagMode = 'any';
  String? _activeMenuField;
  bool _menuDateSelected = false;
  void _changeSheet(VoidCallback update) => setState(update);

  TopicFilterController get filter => _filter!;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    _focus.onKeyEvent = _onKey;
    widget.controller?._handleEscape = _handleMenuEscape;
  }

  void _onFocusChanged() {
    if (_filter == null) return;
    if (mounted) setState(() {});
    if (_focus.hasFocus) {
      unawaited(filter.openSuggestions());
    } else if (!widget.embedded) {
      filter.dismiss();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.identityOf(context);
    if (!identical(_shell, shell)) _replaceController(shell);
    _visible = Visibility.of(context);
    if (_visible || _visibilityDismissScheduled) return;
    _visibilityDismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityDismissScheduled = false;
      if (!mounted || _visible) return;
      filter.dismiss();
      _focus.unfocus();
    });
  }

  @override
  void didUpdateWidget(TopicFilterInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._handleEscape = null;
      widget.controller?._handleEscape = _handleMenuEscape;
    }
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.tokenized != widget.tokenized) {
      _replaceController(_shell!);
      return;
    }
    if (oldWidget.categoryParentId != widget.categoryParentId) {
      _categoryParentId = widget.categoryParentId;
    }
    filter.updateEngine(_engine(_shell!));
    if (oldWidget.enabled && !widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.enabled) {
          return;
        }

        filter.dismiss();
        _focus.unfocus();
      });
    }
    if (oldWidget.initialQuery != widget.initialQuery) {
      if (widget.tokenized) {
        final previous = splitTopicFilterQuery(
          oldWidget.initialQuery,
        ).join(' ');
        if (_composeTokenQuery() == previous) {
          _tokens = splitTopicFilterQuery(widget.initialQuery);
          _setTokenDraft('');
        }
      } else if (filter.text.text == oldWidget.initialQuery) {
        filter.text.text = widget.initialQuery;
      }
    }
  }

  void _replaceController(ShellController shell) {
    _filter?.removeListener(_onFilterChanged);
    _filter?.text.removeListener(_onTextChanged);
    _filter?.dispose();
    _shell = shell;
    _tokens = widget.tokenized
        ? splitTopicFilterQuery(widget.initialQuery)
        : const [];
    final tag = _tokens
        .where((value) => RegExp(r'^-?tags?:').hasMatch(value))
        .lastOrNull;
    _tagMode = tag?.startsWith('-') == true
        ? (tag!.contains('+') ? 'notAll' : 'none')
        : (tag?.contains('+') == true ? 'all' : 'any');
    _categoryParentId = widget.categoryParentId;
    _filter = TopicFilterController(
      onSuggestionsReady: () => widget.onSuggestionsReady?.call(),
      initialQuery: widget.tokenized
          ? (widget.onlyKey == null ? '' : '${widget.onlyKey}:')
          : widget.initialQuery,
      submitQuery: (query) => widget.onSubmitted(
        widget.tokenized ? _composeTokenQuery(query) : query,
      ),
      engine: _engine(shell),
      debounce: widget.tokenized
          ? const Duration(milliseconds: 75)
          : const Duration(milliseconds: 300),
    );
    filter
      ..addListener(_onFilterChanged)
      ..text.addListener(_onTextChanged);
    if (widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.focusOnOpen) _focus.requestFocus();
          unawaited(filter.openSuggestions());
        }
      });
    }
  }

  TopicFilterSuggestions _engine(ShellController shell) =>
      TopicFilterSuggestions(
        options: [
          if (widget.tokenized &&
              !widget.options.any((item) => item.type == 'category'))
            const TopicFilterOption(
              name: 'category:',
              type: 'category',
              priority: 1,
            ),
          if (widget.tokenized &&
              shell.siteConfigFor(widget.siteUrl).taggingEnabled &&
              !widget.options.any((item) => item.type == 'tag'))
            const TopicFilterOption(name: 'tag:', type: 'tag', priority: 1),
          ...widget.options,
        ],
        hierarchicalCategories: widget.tokenized,
        categoryParentId: _categoryParentId,
        allOptions: widget.embedded,
        menuField:
            _activeMenuField ??
            (widget.onlyKey == 'tag'
                ? 'tags'
                : widget.onlyKey == 'category'
                ? 'category'
                : null),
        menuDateSelected: _menuDateSelected,
        scopedKey: widget.onlyKey,
        categories: widget.categories,
        categoryLookup: (term) =>
            shell.searchFilterCategories(siteUrl: widget.siteUrl, term: term),
        tags: (term) async {
          final categoryId =
              parseTopicFilterScope(
                _tokens.join(' '),
                widget.categories,
              ).categoryId ??
              widget.categoryContextId;
          final remote = await shell.searchFilterTags(
            siteUrl: widget.siteUrl,
            term: term,
            categoryId: categoryId,
          );
          if (!widget.embedded || categoryId != null) return remote;
          return {
            for (final tag in shell.topicListFilterTagsFor(widget.siteUrl))
              if (tag.name.toLowerCase().contains(term.toLowerCase()))
                tag.name: TopicFilterLookupValue(
                  name: tag.name,
                  description: '${tag.count}',
                ),
            for (final tag in remote) tag.name: tag,
          }.values.toList();
        },
        tagGroups: (term) =>
            shell.searchFilterTagGroups(siteUrl: widget.siteUrl, term: term),
        users: (term) =>
            shell.searchFilterUsers(siteUrl: widget.siteUrl, term: term),
        groups: (term) =>
            shell.searchFilterGroups(siteUrl: widget.siteUrl, term: term),
      );

  void _onTextChanged() {
    if (widget.tokenized && !_updatingTokenDraft) {
      _synchronizeTokenDraft();
      return;
    }
    if (_updatingTokenDraft) return;
    widget.onChanged?.call(filter.text.text);
    if (mounted) setState(() {});
  }

  void _synchronizeTokenDraft() {
    final draft = filter.text.text;
    final parsed = splitTopicFilterQuery(draft);
    final endsWithSeparator = topicFilterQueryEndsWithSeparator(draft);
    final completedCount = endsWithSeparator
        ? parsed.length
        : parsed.length > 1
        ? parsed.length - 1
        : 0;

    if (completedCount == 0) {
      if (endsWithSeparator && parsed.isEmpty) _setTokenDraft('');
      widget.onChanged?.call(_composeTokenQuery());
      if (mounted) setState(() {});
      return;
    }

    final completed = parsed.take(completedCount);
    final remaining = endsWithSeparator ? '' : parsed.last;
    if (mounted) {
      setState(
        () =>
            _tokens = replaceTopicFilterScopeTokens([..._tokens, ...completed]),
      );
    } else {
      _tokens = replaceTopicFilterScopeTokens([..._tokens, ...completed]);
    }
    _setTokenDraft(remaining);
    widget.onChanged?.call(_composeTokenQuery());
  }

  String _composeTokenQuery([String? draft]) {
    var currentDraft = (draft ?? filter.text.text).trim();
    if (widget.embedded && _activeMenuField == 'replies') {
      final match = RegExp(
        r'^(posts-(?:min|max):)(\d+)$',
      ).firstMatch(currentDraft);
      if (match != null) {
        currentDraft = '${match[1]}${int.parse(match[2]!) + 1}';
      }
    }
    return [..._tokens, if (currentDraft.isNotEmpty) currentDraft].join(' ');
  }

  void _setTokenDraft(String value) {
    _updatingTokenDraft = true;
    filter.text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _updatingTokenDraft = false;
  }

  void _commitTokenDraft() {
    final additions = splitTopicFilterQuery(filter.text.text);
    if (additions.isEmpty) return;
    setState(
      () => _tokens = replaceTopicFilterScopeTokens([..._tokens, ...additions]),
    );
    _categoryParentId = null;
    _activeMenuField = null;
    _menuDateSelected = false;
    filter.updateEngine(_engine(_shell!));
    _setTokenDraft('');
    widget.onChanged?.call(_composeTokenQuery());
    filter.dismiss();
  }

  void _removeToken(int index) {
    if (!widget.enabled || index < 0 || index >= _tokens.length) return;
    setState(() => _tokens = [..._tokens]..removeAt(index));
    widget.onChanged?.call(_composeTokenQuery());
    widget.onScopeChanged?.call(_tokens.join(' '));
    filter.updateEngine(_engine(_shell!));
    _focus.requestFocus();
    unawaited(filter.openSuggestions());
  }

  void _editToken(int index) {
    if (!widget.enabled || index < 0 || index >= _tokens.length) return;
    final token = _tokens[index];
    if (widget.embedded) {
      _activeMenuField = topicFilterMenuFields(filter.engine.options)
          .where((f) => f.keys.contains(topicFilterClauseKey(token)))
          .firstOrNull
          ?.id;
      _menuDateSelected = false;
    }
    setState(() => _tokens = [..._tokens]..removeAt(index));
    _categoryParentId = null;
    _setTokenDraft(
      widget.onlyKey == null
          ? topicFilterClauseKey(token) ?? token
          : '${widget.onlyKey}:',
    );
    filter.updateEngine(_engine(_shell!));
    widget.onChanged?.call(_composeTokenQuery());
    widget.onScopeChanged?.call(_tokens.join(' '));
    filter.dismiss();
    _focus.requestFocus();
    final staged = filter.text.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && filter.text.text == staged && _focus.hasFocus) {
        filter.text.selection = TextSelection.collapsed(offset: staged.length);
      }
    });
    unawaited(filter.openSuggestions());
  }

  Future<void> _clearTokenQuery() async {
    if (!widget.enabled) return;
    setState(() => _tokens = const []);
    _setTokenDraft('');
    widget.onChanged?.call('');
    await widget.onSubmitted('');
    if (mounted && _focus.hasFocus) unawaited(filter.openSuggestions());
  }

  void _onFilterChanged() {
    // Native command rows own their highlight. Moving between them does not
    // change the query, results, tokens, or other sheet content.
    if (_selectingSheetSuggestion) return;
    if (mounted) setState(() {});
  }

  void _selectSheetSuggestion(int index) {
    _selectingSheetSuggestion = true;
    try {
      filter.select(index);
    } finally {
      _selectingSheetSuggestion = false;
    }
  }

  void _moveSelection(int delta) {
    if (filter.suggestions.isEmpty) return;
    final index = (filter.selectedIndex + delta).clamp(
      0,
      filter.suggestions.length - 1,
    );
    if (widget.embedded) {
      _selectSheetSuggestion(index);
      _sheetCommand.highlight(_commandValue(filter.suggestions[index]));
    } else {
      _combobox.highlight(filter.suggestions[index]);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || !_focus.hasFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowRight
          when widget.embedded &&
              _sheetCommand.value == '@tag-mode' &&
              _sheetTags.isNotEmpty:
        final modes = ['any', 'all', 'none', 'notAll'];
        _tagMode =
            modes[(modes.indexOf(_tagMode) +
                    (event.logicalKey == LogicalKeyboardKey.arrowRight
                        ? 1
                        : -1)) %
                modes.length];
        _setSheetTags(_sheetTags);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown when filter.isOpen:
        if (widget.embedded) return KeyEventResult.ignored;
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when filter.isOpen:
        if (widget.embedded) return KeyEventResult.ignored;
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight
          when widget.tokenized && filter.selected?.hasChildren == true:
        _browseCategory(filter.selected!.category);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft
          when widget.tokenized && _categoryParentId != null:
        _browseCategory(
          widget.categories
              .where((item) => item.id == _categoryParentId)
              .firstOrNull,
          up: true,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape when filter.isOpen:
        if (widget.controller != null) return KeyEventResult.ignored;
        final lead = widget.onlyKey == null ? '' : '${widget.onlyKey}:';
        if (widget.tokenized && filter.text.text != lead) {
          _setTokenDraft(lead);
          filter.updateEngine(_engine(_shell!));
          widget.onChanged?.call(_composeTokenQuery());
        } else {
          filter.dismiss();
          widget.onDismiss?.call();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab when filter.isOpen:
        unawaited(_acceptSelectedOrFallback(allowFallback: false));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace
          when widget.embedded &&
              widget.onlyKey != null &&
              filter.text.text == '${widget.onlyKey}:':
        _stepBackScope();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace
          when widget.tokenized &&
              filter.text.text.isNotEmpty &&
              topicFilterClauseKey(filter.text.text) == filter.text.text &&
              filter.text.selection.isCollapsed &&
              filter.text.selection.baseOffset == filter.text.text.length:
        _setTokenDraft('');
        widget.onChanged?.call(_composeTokenQuery());
        filter.dismiss();
        unawaited(filter.openSuggestions());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace
          when widget.tokenized &&
              filter.text.text.isEmpty &&
              _tokens.isNotEmpty:
        _editToken(_tokens.length - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) {
          unawaited(filter.submit());
          return KeyEventResult.handled;
        }
        if (widget.embedded &&
            (filter.isOpen ||
                (_sheetCommand.value?.startsWith('@') ?? false))) {
          return KeyEventResult.ignored;
        }
        if (widget.multiline) return KeyEventResult.ignored;
        if (widget.tokenized &&
            filter.text.text.isEmpty &&
            _tokens.isNotEmpty) {
          unawaited(widget.onSubmitted(_composeTokenQuery()));
        } else if (filter.isOpen) {
          unawaited(_acceptSelectedOrFallback());
        } else if (widget.tokenized) {
          _commitTokenDraft();
        } else {
          unawaited(filter.submit());
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  bool _handleMenuEscape() {
    final lead = widget.onlyKey == null ? '' : '${widget.onlyKey}:';
    if (filter.text.text == lead) return false;
    _setTokenDraft(lead);
    filter.updateEngine(_engine(_shell!));
    widget.onChanged?.call(_composeTokenQuery());
    setState(() {});
    return true;
  }

  Future<void> _acceptSelectedOrFallback({bool allowFallback = true}) async {
    if (widget.embedded && await _sheetAction(_sheetCommand.value)) return;
    final controller = filter;
    final fresh = await controller.ensureFreshSuggestions();
    if (!mounted ||
        !identical(_filter, controller) ||
        !widget.enabled ||
        !fresh) {
      return;
    }
    if (filter.isOpen) {
      await _acceptSelectedSuggestion();
    } else if (!allowFallback) {
      return;
    } else if (widget.tokenized) {
      _commitTokenDraft();
    } else {
      await filter.submit();
    }
  }

  Future<void> _acceptSelectedSuggestion() async {
    final suggestion =
        filter.selected ??
        (filter.suggestions.isEmpty ? null : filter.suggestions.first);
    if (suggestion != null) await _acceptSuggestion(suggestion);
  }

  void _browseCategory(TopicCategory? category, {bool up = false}) {
    _categoryParentId = up ? category?.parentCategoryId : category?.id;
    filter.updateEngine(_engine(_shell!));
    unawaited(filter.openSuggestions());
  }

  Future<void> _acceptSuggestion(TopicFilterSuggestion suggestion) async {
    if (widget.embedded) {
      if (suggestion.menuField case final field?) {
        _menuDateSelected =
            _activeMenuField == field && suggestion.menuIcon == 'calendar-days';
        _activeMenuField = field;
        filter.updateEngine(_engine(_shell!));
      }
    }
    if (suggestion.categoryUp) {
      _browseCategory(suggestion.category, up: true);
      return;
    }
    if (widget.embedded &&
        _isTagStage &&
        suggestion.term != null &&
        RegExp(r'^tags?:').hasMatch(suggestion.name)) {
      await _toggleSheetTag(_unquoteTopicFilterValue(suggestion.term!));
      return;
    }
    if (widget.embedded && _isTagStage && _isTagScopeToken(suggestion.name)) {
      _tokens = _tokens.where((token) => !_isTagScopeToken(token)).toList();
    }
    if (widget.embedded && suggestion.replaceKeys.isNotEmpty) {
      _tokens = _tokens
          .where(
            (token) =>
                !suggestion.replaceKeys.contains(topicFilterClauseKey(token)),
          )
          .toList();
    }
    if (widget.embedded && suggestion.category != null) {
      _tokens = _tokens
          .where((token) => !RegExp(r'^=?category:').hasMatch(token))
          .toList();
    }
    if (widget.embedded &&
        widget.onlyKey != null &&
        _completesClause(suggestion)) {
      _setTokenDraft(suggestion.name);
      _commitTokenDraft();
      await widget.onSubmitted(_tokens.join(' '));
      return;
    }
    final acceptance = filter.accept(suggestion);
    if (widget.tokenized && _completesClause(suggestion)) {
      _commitTokenDraft();
    }
    await acceptance;
    if (mounted && widget.embedded) _focus.requestFocus();
    if (mounted && widget.tokenized && _completesClause(suggestion)) {
      filter.dismiss();
      if (widget.embedded) {
        if (widget.onlyKey != null) {
          await widget.onSubmitted(_composeTokenQuery());
        } else {
          unawaited(filter.openSuggestions());
        }
      }
    }
  }

  bool _completesClause(TopicFilterSuggestion suggestion) {
    final replacement = suggestion.name.trimRight();
    if (replacement.isEmpty || replacement.endsWith(':')) return false;
    return !suggestion.delimiters.any(
      (delimiter) =>
          delimiter.name.isNotEmpty && replacement.endsWith(delimiter.name),
    );
  }

  @override
  void dispose() {
    widget.controller?._handleEscape = null;
    _filter?.removeListener(_onFilterChanged);
    _filter?.text.removeListener(_onTextChanged);
    _filter?.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _combobox.dispose();
    _sheetCommand.dispose();
    super.dispose();
  }

  Widget _buildTokens() => Wrap(
    key: const ValueKey('topic-filter-token-field'),
    spacing: 5,
    runSpacing: 5,
    children: _buildTokenChips(),
  );

  List<Widget> _buildTokenChips() => [
    for (final group in _displayTokens())
      _TopicFilterTokenChip(
        raw: group.tokens.join(' '),
        label: group.label,
        index: group.indices.first,
        categories: widget.categories,
        enabled: widget.enabled,
        onEdited: () => _editDisplayToken(group),
        onDeleted: () {
          if (group.indices.length == 1) {
            _removeToken(group.indices.first);
            return;
          }
          _changeSheet(
            () => _tokens = [
              for (var i = 0; i < _tokens.length; i++)
                if (!group.indices.contains(i)) _tokens[i],
            ],
          );
          widget.onChanged?.call(_composeTokenQuery());
        },
      ),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildSheet(context);
    return _buildCombobox(context);
  }

  Widget _buildCombobox(BuildContext context) => Padding(
    padding: widget.padding,
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: DCombobox<TopicFilterSuggestion>.controlled(
        controller: _combobox,
        value: null,
        options: [
          for (var i = 0; i < filter.suggestions.length; i++)
            DComboboxOption(
              value: filter.suggestions[i],
              label: filter.suggestions[i].categoryUp
                  ? '${context.l10n.back}: ${filter.suggestions[i].category!.name}'
                  : filter.suggestions[i].category != null
                  ? filter.suggestions[i].description ??
                        filter.suggestions[i].displayName ??
                        filter.suggestions[i].name
                  : filter.suggestions[i].name,
              itemKey: ValueKey('topic-filter-suggestion-$i'),
            ),
        ],
        textController: filter.text,
        focusNode: _focus,
        open: filter.isOpen,
        filterLocally: false,
        loopFocus: false,
        restoreFocus: false,
        closeOnSelect: false,
        highlightedValue: filter.selected,
        highlightControlled: true,
        equals: (a, b) => a.name == b.name,
        enabled: widget.enabled,
        onQueryChanged: (query, reason) {
          if (reason == DComboboxChangeReason.input) {
            filter.inputChanged(query);
          }
        },
        onOpenChanged: (open, reason) {
          if (open) {
            if (!filter.menuRequested) {
              unawaited(filter.openSuggestions());
            }
          } else {
            filter.dismiss();
          }
        },
        onHighlightChanged: (value, reason) {
          final index = filter.suggestions.indexWhere(
            (s) => s.name == value?.name,
          );
          if (index >= 0) filter.select(index);
        },
        onChanged: (choice, reason) {
          if (reason == DComboboxChangeReason.clear) {
            unawaited(widget.tokenized ? _clearTokenQuery() : filter.clear());
          } else if (choice != null) {
            if (reason == DComboboxChangeReason.keyboard) {
              unawaited(_acceptSelectedOrFallback());
            } else {
              unawaited(_acceptSuggestion(choice));
            }
          }
        },
        anchor: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.tokenized && !widget.multiline && _tokens.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildTokens(),
              ),
            if (widget.multiline)
              DPopoverAnchor(
                child: DInputGroup(
                  enabled: widget.enabled,
                  viewportHeight: widget.tokenized ? 104 : null,
                  children: [
                    DInputGroupTextarea(
                      key: widget.inputKey,
                      controller: filter.text,
                      focusNode: _focus,
                      semanticLabel: context.l10n.topicFilterQuery,
                      hintText: widget.hintText,
                      minLines: widget.tokenized ? 1 : 3,
                      maxLines: widget.tokenized ? null : 6,
                      enabled: widget.enabled,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: filter.inputChanged,
                    ),
                    if (widget.tokenized && _tokens.isNotEmpty)
                      DInputGroupAddon(
                        alignment: DInputGroupAddonAlignment.blockStart,
                        child: _buildTokens(),
                      ),
                  ],
                ),
              )
            else
              DComboboxInput<TopicFilterSuggestion>(
                key: widget.inputKey,
                semanticLabel: widget.hintText,
                placeholder: widget.hintText,
                showTrigger: false,
                onSubmitted: (_) => unawaited(_acceptSelectedOrFallback()),
                addons: [
                  if (_tokens.isNotEmpty || filter.text.text.isNotEmpty)
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      child: DButton.iconOnly(
                        key: widget.clearKey,
                        tooltip: context.l10n.clearAllFilters,
                        icon: const DIcon(DIcons.xmark),
                        variant: DButtonVariant.ghost,
                        size: DButtonSize.small,
                        onPressed: widget.enabled
                            ? () => unawaited(
                                widget.tokenized
                                    ? _clearTokenQuery()
                                    : filter.clear(),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
        content: DComboboxContent(
          key: const ValueKey('topic-filter-suggestions'),
          semanticLabel: context.l10n.filterSuggestions,
          side: DPopoverSide.bottom,
          maxHeight: 360,
          children: [
            DComboboxList<TopicFilterSuggestion>(
              itemBuilder: (context, option) {
                final suggestion = option.value;
                final count =
                    suggestion.category == null && suggestion.term != null
                    ? int.tryParse(suggestion.description ?? '')
                    : null;
                return Row(
                  children: [
                    if (suggestion.categoryUp) ...[
                      const DIcon(DIcons.arrowLeft, size: 16),
                      const SizedBox(width: 8),
                    ] else if (suggestion.category case final category?) ...[
                      CategoryIcon(
                        category: category,
                        parentCategory: suggestion.parentCategory,
                        siteUrl: widget.siteUrl,
                        size: 16,
                        squareSize: 12,
                      ),
                      const SizedBox(width: 8),
                    ] else ...[
                      _topicFilterSuggestionIcon(suggestion),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestion.displayName ??
                                (suggestion.category == null
                                    ? suggestion.name
                                    : suggestion.description ??
                                          suggestion.name),
                          ),
                          if (suggestion.category == null &&
                              count == null &&
                              suggestion.description != null)
                            Text(
                              suggestion.description!,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: DTokens.of(context).mutedForeground,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    if (count != null ||
                        (suggestion.category?.topicCount ?? 0) > 0) ...[
                      const SizedBox(width: DSpacing.sm),
                      Text(
                        '${count ?? suggestion.category!.topicCount}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: DTokens.of(context).mutedForeground,
                        ),
                      ),
                    ],
                    if (suggestion.hasChildren)
                      DButton.iconOnly(
                        key: ValueKey(
                          'topic-filter-category-into-${suggestion.category!.id}',
                        ),
                        tooltip: context.l10n.subcategoriesOf(
                          suggestion.category!.name,
                        ),
                        icon: const DIcon(DIcons.chevronRight, size: 12),
                        variant: DButtonVariant.ghost,
                        size: DButtonSize.small,
                        onPressed: () => _browseCategory(suggestion.category),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _topicFilterSuggestionIcon(TopicFilterSuggestion suggestion) {
  final key = topicFilterClauseKey(
    suggestion.name,
  )?.replaceAll(RegExp(r'[-=:]'), '').toLowerCase();
  final icon = switch (key) {
    'category' => DIcons.folder,
    'tag' || 'tags' || 'tag_group' => DIcons.tag,
    'user' || 'username' || 'created_by' => DIcons.user,
    'group' => DIcons.userGroup,
    'in' => DIcons.layerGroup,
    'created' ||
    'updated' => DIcons.byName['clock'] ?? DNativeIcons.filterLines,
    _ => DNativeIcons.filterLines,
  };
  return DIcon(icon, size: 16);
}

class _TopicFilterTokenChip extends StatelessWidget {
  const _TopicFilterTokenChip({
    required this.raw,
    this.label,
    required this.index,
    required this.categories,
    required this.enabled,
    required this.onEdited,
    required this.onDeleted,
  });

  final String raw;
  final String? label;
  final int index;
  final List<TopicCategory> categories;
  final bool enabled;
  final VoidCallback onEdited;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final label = this.label ?? _topicFilterTokenLabel(raw, categories);
    final separator = label.indexOf(':');
    return DTooltip(
      message: raw,
      child: Row(
        key: ValueKey('topic-filter-token-$index'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: DFilterToken(
              label: separator < 0 ? '' : label.substring(0, separator),
              value: separator < 0
                  ? label
                  : label.substring(separator + 1).trimLeft(),
              editKey: ValueKey('topic-filter-token-edit-$index'),
              removeKey: ValueKey('topic-filter-token-remove-$index'),
              editLabel: context.l10n.editTopicFilterToken(label),
              removeLabel: context.l10n.removeTopicfilterinput(label),
              onEdited: enabled ? onEdited : null,
              onRemoved: enabled ? onDeleted : null,
            ),
          ),
        ],
      ),
    );
  }
}

String _topicFilterTokenLabel(String raw, List<TopicCategory> categories) {
  final match = RegExp(r'^(-=|=-|-|=)?([\w-]+):(.*)$').firstMatch(raw);
  if (match == null) return _unquoteTopicFilterValue(raw);

  final prefix = match.group(1) ?? '';
  final name = match.group(2)!;
  final rawValue = _unquoteTopicFilterValue(match.group(3)!);
  final value = name == 'category'
      ? _topicFilterCategoryLabel(rawValue, categories)
      : rawValue;
  final label = '$prefix$name:';
  return value.isEmpty ? label : '$label $value';
}

String _topicFilterCategoryLabel(String value, List<TopicCategory> categories) {
  final id = int.tryParse(value);
  final category = categories.where((item) => item.id == id).firstOrNull;
  if (category != null) return category.name;
  final slugs = value.split(':');
  final byId = {for (final category in categories) category.id: category};
  for (final category in categories) {
    if (category.slug != slugs.last) continue;
    final path = <TopicCategory>[];
    final visited = <int>{};
    TopicCategory? current = category;
    while (current != null && visited.add(current.id)) {
      path.add(current);
      current = byId[current.parentCategoryId];
    }
    final ordered = path.reversed.toList(growable: false);
    if (ordered.map((item) => item.slug).join(':') == value) {
      return ordered.map((item) => item.name).join(' › ');
    }
  }
  return slugs.map(_titleCaseTopicFilterValue).join(' › ');
}

String _unquoteTopicFilterValue(String value) {
  if (value.length < 2) return value;
  final first = value[0];
  final last = value[value.length - 1];
  return (first == '"' && last == '"') || (first == "'" && last == "'")
      ? value.substring(1, value.length - 1)
      : value;
}

String _sentenceCaseTopicFilterValue(String value) {
  final words = value.replaceAll(RegExp('[_-]+'), ' ').trim();
  if (words.isEmpty) return words;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

String _titleCaseTopicFilterValue(String value) => value
    .split(RegExp('[_-]+'))
    .where((word) => word.isNotEmpty)
    .map(_sentenceCaseTopicFilterValue)
    .join(' ');
