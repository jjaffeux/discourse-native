import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/calendar_day.dart';
import '../foundation/count_label.dart';
import '../models/search_results.dart';
import '../models/topic.dart';
import '../plugin_api/global_search.dart' show GlobalSearchLookup;
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'global_search_api.dart';
import 'global_search_controller.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'open_link.dart';
import 'search_words.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';
import 'site_url.dart';

part 'global_search_category_editor.dart';
part 'global_search_filter_picker.dart';

final RegExp _whitespace = RegExp(r'\s+');

class _PreparedSearchResult {
  const _PreparedSearchResult({required this.result, required this.open});

  final GlobalSearchResult result;
  final VoidCallback open;
}

/// Search scopes, conditions and results below the shell's persistent input.
/// The caller owns the anchored surface and result navigation.
class GlobalSearchPanel extends StatefulWidget {
  const GlobalSearchPanel({
    super.key,
    required this.controller,
    required this.onOpen,
    this.selectedResultId,
    this.onSelect,
    this.onOpenSection,
    this.onApply,
    this.onRefocus,
    this.showConditions = true,
    this.showClearFilters = false,
  });

  final GlobalSearchController controller;
  final ValueChanged<GlobalSearchResult> onOpen;
  final String? selectedResultId;
  final ValueChanged<String>? onSelect;
  final ValueChanged<GlobalSearchSection>? onOpenSection;
  final VoidCallback? onApply, onRefocus;
  final bool showConditions;
  final bool showClearFilters;

  @override
  State<GlobalSearchPanel> createState() => GlobalSearchPanelState();
}

class GlobalSearchPanelState extends State<GlobalSearchPanel> {
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _resultKeys = {};
  final _preparedResults =
      Map<GlobalSearchResult, _PreparedSearchResult>.identity();
  final _actions = <({String id, VoidCallback open, VoidCallback? into})>[];
  String? _selected;
  Object? _selectedNavigationIdentity;
  final _drill = <int>[];
  Object? _lookupKey;
  int _lookupRevision = 0;
  List<GlobalSearchFilterChoice> _choices = const [];
  bool _loadingChoices = false;
  String? _choiceError;
  Object? _navigationSignature;
  int _categoryPage = 0;
  bool _hasMoreChoices = false;

  Object? _targetFor(String? id) => widget.controller.results
      .where((result) => result.id == id)
      .firstOrNull
      ?.navigationIdentity;

  void _checkSelectionTarget() {
    if (_selectedNavigationIdentity != null &&
        _targetFor(_selected) != _selectedNavigationIdentity) {
      _selected = null;
      _selectedNavigationIdentity = null;
    }
  }

  bool handleKey(LogicalKeyboardKey key, {bool reverse = false}) {
    _checkSelectionTarget();
    if (key == LogicalKeyboardKey.tab ||
        (widget.controller.query.isEmpty &&
            (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowRight))) {
      final scopes = widget.controller.scopes;
      final next =
          (scopes.indexOf(widget.controller.scope) +
              (reverse || key == LogicalKeyboardKey.arrowLeft ? -1 : 1) +
              scopes.length) %
          scopes.length;
      widget.controller.setScope(scopes[next]);
      return true;
    }
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.backspace) &&
        _drill.isNotEmpty &&
        widget.controller.stagedTerm.isEmpty) {
      _backCategory();
      return true;
    }
    // Unselected results must leave Enter available to apply the search.
    final current = _actions.indexWhere((action) => action.id == _selected);
    final into = current >= 0
        ? _actions[current].into
        : _actions.firstOrNull?.into;
    if (key == LogicalKeyboardKey.arrowRight && into != null) {
      into();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (_actions.isEmpty) return true;
      final down = key == LogicalKeyboardKey.arrowDown;
      final next = current < 0
          ? (down ? 0 : _actions.length - 1)
          : (current + (down ? 1 : -1) + _actions.length) % _actions.length;
      setState(() {
        _selected = _actions[next].id;
        _selectedNavigationIdentity = _targetFor(_selected);
      });
      _revealSelection(
        _actions[next].id,
        _navigationSignature,
        forward: current < 0 ? !down : next > current,
      );
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (current < 0 &&
          (widget.controller.stagedFilter != null ||
              widget.controller.hintedFilters.isNotEmpty)) {
        if (_actions.isNotEmpty) _actions.first.open();
        return true;
      }
      if (current >= 0) {
        _actions[current].open();
      } else if (widget.onApply != null &&
          widget.controller.stagedFilter == null) {
        widget.onApply!();
      } else {
        return false;
      }
      return true;
    }
    return false;
  }

  void _revealSelection(String id, Object? signature, {required bool forward}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _selected != id ||
          _navigationSignature != signature ||
          !_scroll.hasClients) {
        return;
      }
      final target = _resultKeys[id]?.currentContext;
      if (target != null) {
        unawaited(
          _scroll.position.ensureVisible(
            target.findRenderObject()!,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
        unawaited(
          _scroll.position.ensureVisible(
            target.findRenderObject()!,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          ),
        );
        return;
      }
      // Keyboard actions include rows that the lazy viewport has not mounted.
      // Advance a viewport at a time until the target can be made visible,
      // without assuming fixed heights (large text can wrap any row).
      final index = _actions.indexWhere((action) => action.id == id);
      final firstMounted = _actions.indexWhere(
        (action) => _resultKeys[action.id]?.currentContext != null,
      );
      if (index < 0) return;
      final position = _scroll.position;
      final direction = firstMounted < 0
          ? (forward ? 1 : -1)
          : (index < firstMounted ? -1 : 1);
      final offset = (position.pixels + direction * position.viewportDimension)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (offset == position.pixels) return;
      position.jumpTo(offset);
      _revealSelection(id, signature, forward: forward);
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  void resetSelection() {
    _selected = null;
    _selectedNavigationIdentity = null;
    _drill.clear();
  }

  void _intoCategory(int id) {
    setState(() {
      _drill.add(id);
      _selected = null;
    });
    widget.onRefocus?.call();
  }

  void _backCategory() {
    setState(() {
      _drill.removeLast();
      _selected = null;
    });
    widget.onRefocus?.call();
  }

  Widget _action(
    String id,
    VoidCallback open,
    Widget child, {
    VoidCallback? into,
  }) {
    _actions.add((id: id, open: open, into: into));
    return KeyedSubtree(
      key: _resultKeys.putIfAbsent(id, GlobalKey.new),
      child: child,
    );
  }

  void _stage(GlobalSearchFilter filter) {
    resetSelection();
    widget.controller.beginFilter(filter);
    widget.onRefocus?.call();
  }

  List<Widget> _filterRows(BuildContext context) {
    final controller = widget.controller;
    final tail = controller.query.endsWith(' ')
        ? ''
        : controller.query.split(_whitespace).last.toLowerCase();
    final filters = controller.availableFilters
        .where(
          (filter) =>
              tail.length < 2 ||
              filter.id.toLowerCase().startsWith(tail) ||
              (filter.token?.startsWith(tail) ?? false) ||
              filter.label.toLowerCase().contains(tail),
        )
        .toList();
    final groups = <String, List<GlobalSearchFilter>>{};
    for (final filter in filters) {
      (groups[filter.group] ??= []).add(filter);
    }
    for (final group in groups.values) {
      group.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    }
    // Keep each filter as a sliver child: a Column mounts and lays out the
    // entire catalogue even when only its first few rows are visible.
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(
          context.l10n.addFilter,
          style: TextStyle(color: DTokens.of(context).mutedForeground),
        ),
      ),
      for (final group in groups.entries) ...[
        if (group.key.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              group.key,
              style: TextStyle(color: DTokens.of(context).mutedForeground),
            ),
          ),
        for (final filter in group.value)
          _action(
            'filter:${filter.id}',
            () => _stage(filter),
            DItem(
              key: ValueKey('global-search-offered-${filter.id}'),
              size: DItemSize.sm,
              selected:
                  _selected == 'filter:${filter.id}' ||
                  (_selected == null && _actions.isEmpty),
              showSelectionIndicator: false,
              onPressed: () => _stage(filter),
              children: [
                DItemMedia(
                  child: DIcon(_filterIcon(context, filter.icon), size: 16),
                ),
                DItemContent(
                  children: [
                    DItemTitle(
                      child: Text(
                        filter.label,
                        style: TextStyle(color: DTokens.of(context).primary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ];
  }

  void _loadStage(GlobalSearchFilter filter) {
    final controller = widget.controller;
    final key = (
      controller,
      controller.categoryLookupSession,
      controller.siteUrl,
      controller.configurationRevision,
      filter.id,
      controller.stagedTerm,
    );
    if (_lookupKey == key) return;
    _lookupKey = key;
    _choices = const [];
    _hasMoreChoices = false;
    _categoryPage = 0;
    _choiceError = null;
    _loadingChoices = true;
    final revision = ++_lookupRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final categoryPage = filter.id == 'category'
            ? await controller.lookupCategoryChoices(controller.stagedTerm)
            : null;
        final choices = filter.choices.isNotEmpty
            ? filter.choices
            : filter.id == 'category'
            ? categoryPage!.choices
            : await controller.lookupChoices(filter, controller.stagedTerm);
        if (!mounted || revision != _lookupRevision) return;
        setState(() {
          _choices = choices;
          _categoryPage = categoryPage == null ? 0 : 1;
          _hasMoreChoices = categoryPage?.hasMore ?? false;
          _loadingChoices = false;
        });
      } catch (error) {
        if (!mounted || revision != _lookupRevision) return;
        setState(() {
          _loadingChoices = false;
          _choiceError = GlobalSearchApi.failureMessage(error);
        });
      }
    });
  }

  Widget _stageBody(BuildContext context, GlobalSearchFilter filter) {
    final controller = widget.controller;
    if (filter.id == 'tags' ||
        filter.kind == GlobalSearchFilterKind.date ||
        filter.kind == GlobalSearchFilterKind.number) {
      return DScrollArea(
        child: _GlobalSearchConditionEditor(
          key: ValueKey((filter.id, controller.configurationRevision)),
          controller: controller,
          filter: filter,
          initial:
              controller.conditions
                  .where((condition) => condition.filterId == filter.id)
                  .firstOrNull ??
              (controller.stagedTerm.isEmpty
                  ? null
                  : GlobalSearchCondition(
                      filterId: filter.id,
                      operator: controller.stagedOperator,
                      value: [controller.stagedTerm],
                    )),
          actionLabel: context.l10n.done,
          onBack: () {
            controller.setQuery(controller.wordsQuery);
            widget.onRefocus?.call();
          },
          onApply: (condition) {
            controller.completeFilter(condition);
            resetSelection();
            widget.onRefocus?.call();
          },
        ),
      );
    }
    _loadStage(filter);
    final tree = filter.id == 'category' && controller.stagedTerm.isEmpty;
    final parent = _drill.lastOrNull;
    final knownIds = _choices.map((choice) => choice.category?.id).toSet();
    final choices = _choices.where(
      (choice) => tree
          ? (choice.category?.parentCategoryId == parent ||
                parent == null &&
                    !knownIds.contains(choice.category?.parentCategoryId))
          : choice.label.toLowerCase().contains(
              controller.stagedTerm.toLowerCase(),
            ),
    );
    void pick(GlobalSearchFilterChoice choice) {
      final value =
          filter.kind == GlobalSearchFilterKind.date &&
              RegExp(r'^\d{1,3}$').hasMatch(choice.value)
          ? DateTime.now()
                .toUtc()
                .subtract(Duration(days: int.parse(choice.value)))
                .toIso8601String()
                .substring(0, 10)
          : choice.value;
      final condition = GlobalSearchCondition(
        filterId: filter.id,
        operator: controller.stagedOperator,
        value: [value],
      );
      final error = validateGlobalSearchCondition(
        condition,
        controller.capabilities,
      );
      if (error != null) {
        setState(() => _choiceError = error);
        return;
      }
      controller.completeFilter(condition);
      resetSelection();
      widget.onRefocus?.call();
    }

    return DScrollBar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        children: [
          if (tree && parent != null)
            _action(
              'category:back',
              () => _backCategory(),
              DItem(
                size: DItemSize.sm,
                onPressed: () => _backCategory(),
                children: [
                  const DItemMedia(child: DIcon(DIcons.arrowLeft)),
                  DItemContent(
                    children: [DItemTitle(child: Text(context.l10n.back))],
                  ),
                ],
              ),
            ),
          if (_loadingChoices) const Center(child: DSpinner()),
          if (_choiceError != null)
            Text(
              _choiceError!,
              style: TextStyle(color: DTokens.of(context).destructive),
            ),
          if (_choiceError != null)
            DButton(
              label: Text(context.l10n.retry),
              variant: DButtonVariant.ghost,
              onPressed: () => setState(() => _lookupKey = null),
            ),
          if (_hasMoreChoices)
            DButton(
              label: Text(context.l10n.loadMore),
              loading: _loadingChoices,
              onPressed: () async {
                final revision = _lookupRevision;
                setState(() => _loadingChoices = true);
                try {
                  final page = await controller.lookupCategoryChoices(
                    controller.stagedTerm,
                    page: _categoryPage + 1,
                  );
                  if (!mounted || revision != _lookupRevision) return;
                  setState(() {
                    _choices = {
                      for (final choice in [..._choices, ...page.choices])
                        choice.value: choice,
                    }.values.toList();
                    _categoryPage++;
                    _hasMoreChoices = page.hasMore;
                    _loadingChoices = false;
                  });
                } catch (error) {
                  if (!mounted || revision != _lookupRevision) return;
                  setState(() {
                    _loadingChoices = false;
                    _choiceError = GlobalSearchApi.failureMessage(error);
                  });
                }
              },
            ),
          for (final choice in choices)
            _action(
              'value:${choice.value}',
              () => pick(choice),
              DItem(
                key: ValueKey('global-search-staged-${choice.value}'),
                size: DItemSize.sm,
                selected:
                    _selected == 'value:${choice.value}' ||
                    (_selected == null && _actions.isEmpty),
                showSelectionIndicator: false,
                onPressed: () => pick(choice),
                children: [
                  if (choice.category != null)
                    DItemMedia(
                      child: CategoryIcon(
                        category: choice.category!,
                        size: 12,
                        siteUrl: controller.siteUrl,
                      ),
                    ),
                  if (filter.lookup == GlobalSearchLookup.users)
                    DItemMedia(
                      child: DAvatar(
                        size: DAvatarSize.sm,
                        child: AvatarImage(
                          url: choice.avatarUrl,
                          size: 24,
                          fallback: Text(
                            choice.value.substring(0, 1).toUpperCase(),
                          ),
                        ),
                      ),
                    ),
                  DItemContent(
                    children: [
                      DItemTitle(child: Text(choice.label)),
                      if (choice.parentLabel != null)
                        DItemDescription(child: Text(choice.parentLabel!)),
                    ],
                  ),
                  if (choice.topicCount != null)
                    DItemActions(
                      children: [
                        Text(countLabel(choice.topicCount!, CountNoun.topic)),
                      ],
                    ),
                  if (tree &&
                      _choices.any(
                        (item) =>
                            item.category?.parentCategoryId ==
                            choice.category?.id,
                      ))
                    DItemActions(
                      children: [
                        DButton.iconOnly(
                          icon: const DIcon(DIcons.chevronRight),
                          tooltip: choice.label,
                          variant: DButtonVariant.ghost,
                          size: DButtonSize.small,
                          onPressed: () => _intoCategory(choice.category!.id),
                        ),
                      ],
                    ),
                ],
              ),
              into:
                  tree &&
                      choice.category != null &&
                      _choices.any(
                        (item) =>
                            item.category?.parentCategoryId ==
                            choice.category!.id,
                      )
                  ? () => _intoCategory(choice.category!.id)
                  : null,
            ),
          if (filter.choices.isEmpty &&
              filter.id != 'category' &&
              controller.stagedTerm.isNotEmpty)
            _action(
              'value:typed',
              () => pick(
                GlobalSearchFilterChoice(
                  value: controller.stagedTerm,
                  label: controller.stagedTerm,
                ),
              ),
              DItem(
                size: DItemSize.sm,
                selected: _selected == 'value:typed',
                showSelectionIndicator: false,
                onPressed: () => pick(
                  GlobalSearchFilterChoice(
                    value: controller.stagedTerm,
                    label: controller.stagedTerm,
                  ),
                ),
                children: [
                  DItemContent(
                    children: [DItemTitle(child: Text(controller.stagedTerm))],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(GlobalSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedResultId != widget.selectedResultId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _resultKeys[widget.selectedResultId]?.currentContext;
        if (target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final signature = (
        controller,
        controller.categoryLookupSession,
        controller.configurationRevision,
        controller.query,
        controller.scope,
      );
      if (signature != _navigationSignature) {
        resetSelection();
        _navigationSignature = signature;
      }
      _checkSelectionTarget();
      _actions.clear();
      final liveResults = Set<GlobalSearchResult>.identity();
      final liveIds = <String>{};
      for (final result in controller.results) {
        liveResults.add(result);
        liveIds.add(result.id);
      }
      _preparedResults.removeWhere(
        (result, _) => !liveResults.contains(result),
      );
      _resultKeys.removeWhere(
        (id, _) =>
            !liveIds.contains(id) &&
            !id.startsWith('section:') &&
            !id.startsWith('filter:') &&
            !id.startsWith('recent:') &&
            !id.startsWith('value:') &&
            !id.startsWith('category:') &&
            id != 'clear-filters',
      );
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .55,
              ),
              child: DScrollArea(
                thumbVisibility: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final tools = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _GlobalSearchFilterPicker(controller: controller),
                              const SizedBox(width: 4),
                              _GlobalSearchDisplay(controller: controller),
                            ],
                          );
                          final scopes = constraints.maxWidth < 530
                              ? DSelect<GlobalSearchScope>.controlled(
                                  key: const ValueKey(
                                    'global-search-scope-select',
                                  ),
                                  value: controller.scope,
                                  onChanged: (scope) {
                                    if (scope != null) {
                                      controller.setScope(scope);
                                    }
                                  },
                                  size: DSelectSize.small,
                                  isExpanded: true,
                                  semanticLabel: context.l10n
                                      .searchGlobalsearchpanel(
                                        controller.scope.label,
                                      ),
                                  entries: [
                                    for (final scope in controller.scopes)
                                      DSelectItem(
                                        value: scope,
                                        textValue: scope.label,
                                        child: Text(scope.label),
                                      ),
                                  ],
                                )
                              : DScrollArea(
                                  axes: DScrollAxes.horizontal,
                                  showScrollbar: false,
                                  child: Row(
                                    spacing: DSpacing.controlGap,
                                    children: [
                                      for (final scope in controller.scopes)
                                        DToggle(
                                          key: ValueKey(
                                            'global-search-scope-${scope.keyName}',
                                          ),
                                          pressed: controller.scope == scope,
                                          onPressedChanged: (_) =>
                                              controller.setScope(scope),
                                          variant: DToggleVariant.outline,
                                          size: DToggleSize.small,
                                          selectedIcon: const DIcon(
                                            DIcons.check,
                                          ),
                                          semanticLabel: context.l10n
                                              .searchGlobalsearchpanel(
                                                (scope.label).toString(),
                                              ),
                                          child: Text(scope.label),
                                        ),
                                    ],
                                  ),
                                );
                          return Row(
                            children: [
                              Expanded(child: scopes),
                              const SizedBox(width: 8),
                              tools,
                            ],
                          );
                        },
                      ),
                    ),
                    if (widget.showConditions &&
                        controller.conditions.isNotEmpty)
                      _conditions(context),
                  ],
                ),
              ),
            ),
            const DSeparator(),
            Expanded(child: _body(context)),
          ],
        ),
      );
    },
  );

  Widget _conditions(BuildContext context) {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DTokens.of(context).muted,
          borderRadius: BorderRadius.circular(DRadius.panel),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (
                  var index = 0;
                  index < controller.conditions.length;
                  index++
                )
                  _GlobalSearchFilterPicker(
                    key: ValueKey('global-search-condition-$index'),
                    controller: controller,
                    conditionIndex: index,
                    maxChipWidth: constraints.maxWidth,
                  ),
                _GlobalSearchFilterPicker(
                  controller: controller,
                  addOnly: true,
                ),
                DButton(
                  key: const ValueKey('global-search-clear-conditions'),
                  label: Text(context.l10n.clear),
                  onPressed: controller.clearConditions,
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  semanticLabel: context.l10n.clearAllSearchConditions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final controller = widget.controller;
    if (controller.stagedFilter case final filter?) {
      return _stageBody(context, filter);
    }
    final phase = controller.phase;
    if (phase == GlobalSearchPhase.idle) return _history(context);
    if (phase == GlobalSearchPhase.tooShort) {
      if (controller.availableFilters.any(
        (filter) =>
            filter.id.toLowerCase().startsWith(controller.query.toLowerCase()),
      )) {
        return _history(context);
      }
      return _status(
        context.l10n.keepTyping,
        context.l10n.enterAtLeastCharactersToSearch(
          (controller.capabilities.minimumLength).toString(),
        ),
      );
    }
    final results = controller.results;
    if (phase == GlobalSearchPhase.loading && results.isEmpty) {
      return const SizedBox.shrink();
    }
    if (phase == GlobalSearchPhase.failed && results.isEmpty) {
      return _status(
        context.l10n.searchCouldNotLoad,
        controller.error ?? context.l10n.pleaseTryAgain,
        error: true,
      );
    }
    if (phase == GlobalSearchPhase.empty) {
      return _status(
        context.l10n.noResultsFound,
        context.l10n.tryDifferentWordsOrRemoveACondition,
        clear: controller.conditions.isNotEmpty,
      );
    }
    final children = <Object>[
      if (controller.hintedFilters.isNotEmpty) ..._filterRows(context),
      for (final section in controller.sections.where(
        (section) =>
            controller.scope != GlobalSearchScope.all ||
            section.results.isNotEmpty ||
            section.error != null,
      )) ...[
        if (controller.scope == GlobalSearchScope.all)
          _sectionHeader(context, section),
        if (section.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.error!,
                  style: TextStyle(color: DTokens.of(context).destructive),
                ),
                DButton(
                  label: Text(context.l10n.retry),
                  onPressed: controller.retry,
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                ),
              ],
            ),
          ),
        for (final result
            in controller.scope == GlobalSearchScope.all
                ? section.results.take(3)
                : section.results)
          _prepareResult(result),
      ],
      if (controller.error != null &&
          results.isNotEmpty &&
          !controller.sections.any(
            (section) => section.error == controller.error,
          ))
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            controller.error!,
            style: TextStyle(color: DTokens.of(context).destructive),
          ),
        ),
      if (controller.hasMore || controller.loadingMore)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: DButton(
              key: const ValueKey('global-search-load-more'),
              label: Text(context.l10n.loadMore),
              loading: controller.loadingMore,
              onPressed: controller.loadMore,
              variant: DButtonVariant.outline,
            ),
          ),
        ),
      if (controller.wordsQuery.trim().isEmpty &&
          controller.hintedFilters.isEmpty)
        ..._filterRows(context),
    ];
    final ids = {for (final result in results) result.id};
    _resultKeys.removeWhere(
      (id, _) =>
          !ids.contains(id) &&
          !id.startsWith('section:') &&
          !id.startsWith('filter:'),
    );
    final childIndices = <Key, int>{};
    for (var index = 0; index < children.length; index++) {
      final child = children[index];
      final key = child is _PreparedSearchResult
          ? _resultKeys[child.result.id]
          : (child as Widget).key;
      if (key != null) childIndices[key] = index;
    }
    final content = DScrollBar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        itemCount: children.length,
        findChildIndexCallback: (key) => childIndices[key],
        itemBuilder: (context, index) {
          final child = children[index];
          return child is _PreparedSearchResult
              ? _result(child)
              : child as Widget;
        },
      ),
    );
    return DScrollChromePagination(
      hasMore: controller.hasMore,
      loading: controller.loadingMore,
      child: content,
    );
  }

  Widget _sectionHeader(BuildContext context, GlobalSearchSection section) {
    void open() {
      if (section.topicId != null && section.results.isNotEmpty) {
        widget.onOpen(section.results.first);
      } else if (widget.onOpenSection != null) {
        widget.onOpenSection!(section);
      } else {
        widget.controller.setScope(section.scope);
      }
    }

    final id = 'section:${section.scope.keyName}:${section.topicId ?? ""}';
    return _action(
      id,
      open,
      DItem(
        key: ValueKey(id),
        size: DItemSize.sm,
        selected: _selected == id,
        showSelectionIndicator: false,
        onPressed: section.results.isEmpty ? null : open,
        children: [
          DItemMedia(
            child: SizedBox.square(
              dimension: 32,
              child: Center(
                child: DIcon(
                  section.topicId != null
                      ? DIcons.comments
                      : section.scope == GlobalSearchScope.messages
                      ? DIcons.inbox
                      : section.scope == GlobalSearchScope.users
                      ? DIcons.users
                      : section.scope == GlobalSearchScope.groups
                      ? DIcons.userGroup
                      : section.scope == GlobalSearchScope.categories
                      ? DIcons.folder
                      : section.scope == GlobalSearchScope.tags
                      ? DIcons.tag
                      : DIcons.magnifyingGlass,
                  size: 16,
                ),
              ),
            ),
          ),
          DItemContent(
            children: [
              DItemTitle(
                child: Text(
                  section.topicId != null
                      ? '${context.l10n.inThisTopicSearch} · ${section.topicTitle ?? ""}'
                      : section.scope.label,
                ),
              ),
            ],
          ),
          if (section.results.isNotEmpty)
            DItemActions(
              children: [
                DButton.iconOnly(
                  icon: const DIcon(DIcons.chevronRight),
                  tooltip: context.l10n.viewAllResults(section.scope.label),
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  onPressed: open,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _history(BuildContext context) {
    final controller = widget.controller;
    return DScrollBar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        children: [
          if (widget.showClearFilters)
            _action(
              'clear-filters',
              () => widget.onApply?.call(),
              DItem(
                size: DItemSize.sm,
                onPressed: widget.onApply,
                selected: _selected == 'clear-filters',
                showSelectionIndicator: false,
                children: [
                  const DItemMedia(child: DIcon(DIcons.filter, size: 16)),
                  DItemContent(
                    children: [
                      DItemTitle(
                        child: Text(context.l10n.clearSearchListFilters),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (controller.recentSearches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.recentSearches,
                      style: TextStyle(
                        color: DTokens.of(context).mutedForeground,
                      ),
                    ),
                  ),
                  DButton(
                    key: const ValueKey('global-search-clear-history'),
                    label: Text(context.l10n.clearHistory),
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                    onPressed: controller.clearHistory,
                  ),
                ],
              ),
            ),
          for (final query in controller.recentSearches)
            _action(
              'recent:$query',
              () {
                controller.useRecentSearch(query);
                widget.onRefocus?.call();
              },
              DItem(
                size: DItemSize.sm,
                onPressed: () => controller.useRecentSearch(query),
                children: [
                  DItemContent(
                    children: [
                      DItemTitle(child: _RecentQuery(controller, query)),
                    ],
                  ),
                  DItemActions(
                    children: [
                      DButton.iconOnly(
                        icon: const DIcon(DIcons.xmark),
                        tooltip: context.l10n.remove(query),
                        variant: DButtonVariant.ghost,
                        size: DButtonSize.small,
                        onPressed: () => controller.removeRecentSearch(query),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  controller.error!,
                  style: TextStyle(color: DTokens.of(context).destructive),
                ),
              ),
            ),
          ..._filterRows(context),
        ],
      ),
    );
  }

  Widget _status(
    String title,
    String description, {
    bool error = false,
    bool clear = false,
  }) => SingleChildScrollView(
    child: DEmpty(
      padding: const EdgeInsets.all(24),
      children: [
        DEmptyHeader(
          children: [
            DEmptyMedia(
              variant: DEmptyMediaVariant.icon,
              child: DIcon(
                error ? DIcons.triangleExclamation : DIcons.magnifyingGlass,
              ),
            ),
            DEmptyTitle(title),
            DEmptyDescription(description),
          ],
        ),
        if (error)
          DButton(
            label: Text(appL10n.tryAgain),
            onPressed: widget.controller.retry,
            variant: DButtonVariant.outline,
          ),
        if (clear)
          DButton(
            label: Text(appL10n.clearConditions),
            onPressed: widget.controller.clearConditions,
            variant: DButtonVariant.outline,
          ),
      ],
    ),
  );

  _PreparedSearchResult _prepareResult(GlobalSearchResult result) {
    var row = _preparedResults[result];
    if (row == null) {
      row = _PreparedSearchResult(
        result: result,
        open: () => widget.onOpen(result),
      );
      _preparedResults[result] = row;
    }
    _actions.add((id: result.id, open: row.open, into: null));
    return row;
  }

  Widget _result(_PreparedSearchResult row) {
    final result = row.result;
    final controller = widget.controller;
    final site = controller.siteUrl;
    return KeyedSubtree(
      key: _resultKeys.putIfAbsent(result.id, GlobalKey.new),
      child: KeyedSubtree(
        child: LinkTarget(
          url: site == null
              ? result.path
              : resolveSiteRootPath(site, result.path),
          siteUrl: site,
          title: result.title,
          child: Focus(
            canRequestFocus: false,
            onFocusChange: (focused) {
              if (focused) widget.onSelect?.call(result.id);
            },
            // The shell notifies for every navigation and tracking event; only
            // this row's category may change what the row draws.
            child: ShellSelector<TopicCategory?>(
              select: (shell) => shell.categoryFor(
                result.categoryId,
                siteUrl: controller.siteUrl,
              ),
              builder: (context, category, _) =>
                  _resultItem(context, result, category),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultItem(
    BuildContext context,
    GlobalSearchResult result,
    TopicCategory? category,
  ) {
    final controller = widget.controller;
    final properties = controller.properties;
    final tokens = DTokens.of(context);
    final source = result.source;
    if (source is SearchCategoryHit || source is SearchTagHit) {
      final swatch = source is SearchCategoryHit
          ? TopicCategory.fromJson({
              'id': source.categoryId,
              'name': source.name,
              'slug': source.slug,
              'color': source.color,
              'style_type': source.styleType,
              'icon': source.icon,
              'emoji': source.emoji,
              'read_restricted': source.readRestricted,
            })
          : null;
      final count = source is SearchCategoryHit
          ? source.topicCount
          : (source as SearchTagHit).topicCount;
      final parent = source is SearchCategoryHit
          ? ShellScope.maybeRead(
              context,
            )?.categoryFor(source.parentCategoryId, siteUrl: controller.siteUrl)
          : null;
      return DItem(
        key: ValueKey('global-search-result-${result.id}'),
        size: DItemSize.sm,
        selected: _selected == result.id,
        showSelectionIndicator: false,
        onPressed: () => widget.onOpen(result),
        children: [
          DItemMedia(
            child: swatch != null
                ? CategoryIcon(
                    category: swatch,
                    size: 12,
                    siteUrl: controller.siteUrl,
                  )
                : const Text('#'),
          ),
          DItemContent(
            children: [
              DItemTitle(
                child: _SearchHighlight(
                  siteUrl: controller.siteUrl!,
                  text: result.title,
                  query: controller.query,
                ),
              ),
              if (parent != null) DItemDescription(child: Text(parent.name)),
            ],
          ),
          if (count != null)
            DItemActions(children: [Text(countLabel(count, CountNoun.topic))]),
        ],
      );
    }
    final metadata = <Widget>[
      if (properties.contains(GlobalSearchDisplayProperty.author) &&
          result.username?.isNotEmpty == true)
        Text('@${result.username}'),
      if (result.contextLabel?.isNotEmpty == true) Text(result.contextLabel!),
      if ((properties.contains(GlobalSearchDisplayProperty.category) ||
              result.scope == GlobalSearchScope.forum) &&
          category != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIcon(
              category: category,
              size: 12,
              siteUrl: controller.siteUrl,
            ),
            const SizedBox(width: 4),
            Text(category.name),
          ],
        ),
      if (properties.contains(GlobalSearchDisplayProperty.tags))
        for (final tag in result.tags) Text('#$tag'),
      if (result.likes case final likes?
          when properties.contains(GlobalSearchDisplayProperty.likes))
        Text(countLabel(likes, CountNoun.like)),
      if (result.replies case final replies?
          when properties.contains(GlobalSearchDisplayProperty.replies) ||
              result.scope == GlobalSearchScope.forum ||
              result.privateMessage)
        Text(countLabel(replies, CountNoun.reply)),
      if (result.memberCount case final members?)
        Text(countLabel(members, CountNoun.member)),
      if (result.createdAt != null) Text(_searchDate(result.createdAt!)),
      if (result.privateMessage) Text(context.l10n.personalMessage),
      if (result.closed) Text(context.l10n.closed),
      if (result.archived) Text(context.l10n.archived),
    ];
    return DItem(
      key: ValueKey('global-search-result-${result.id}'),
      size: DItemSize.sm,
      onPressed: () {
        widget.onSelect?.call(result.id);
        widget.onOpen(result);
      },
      link: true,
      selected: _selected == result.id || widget.selectedResultId == result.id,
      showSelectionIndicator: false,
      children: [
        if (result.scope.showAvatar ||
            result.id.startsWith('in-topic:') ||
            result.source is SearchCategoryHit ||
            result.source is SearchTagHit)
          DItemMedia(
            child: result.scope.showAvatar || result.id.startsWith('in-topic:')
                ? DAvatar(
                    size: DAvatarSize.standard,
                    decorative: true,
                    child: AvatarImage(
                      url: result.avatarUrl,
                      size: 32,
                      fallback: DAvatarFallback(
                        child: Text(
                          (result.username ?? result.title).characters
                              .take(1)
                              .toString()
                              .toUpperCase(),
                        ),
                      ),
                    ),
                  )
                : result.source is SearchCategoryHit && category != null
                ? CategoryIcon(
                    category: category,
                    size: 12,
                    siteUrl: controller.siteUrl,
                  )
                : DIcon(
                    result.scope == GlobalSearchScope.groups
                        ? DIcons.users
                        : DIcons.comments,
                    size: 18,
                    color: tokens.mutedForeground,
                  ),
          ),
        if (!result.scope.showAvatar && !result.id.startsWith('in-topic:'))
          const DItemMedia(child: SizedBox.square(dimension: 32)),
        DItemContent(
          children: [
            DItemTitle(
              maxLines: 1,
              child: _SearchHighlight(
                siteUrl: controller.siteUrl!,
                text: result.title,
                query: controller.query,
              ),
            ),
            if (properties.contains(GlobalSearchDisplayProperty.excerpt) &&
                result.excerpt.isNotEmpty)
              DItemDescription(
                maxLines: 1,
                child: _SearchHighlight(
                  siteUrl: controller.siteUrl!,
                  text: searchSnippet(result.excerpt, controller.query),
                  query: controller.query,
                ),
              ),
            if (metadata.isNotEmpty)
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: DiscourseTypography.xs,
                  color: tokens.mutedForeground,
                ),
                child: Wrap(spacing: 10, runSpacing: 3, children: metadata),
              ),
          ],
        ),
      ],
    );
  }
}

class GlobalSearchChips extends StatelessWidget {
  const GlobalSearchChips({
    super.key,
    required this.controller,
    required this.maxWidth,
    this.onRefocus,
  });
  final GlobalSearchController controller;
  final double maxWidth;
  final VoidCallback? onRefocus;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      for (final index in controller.orderedConditionIndices)
        SearchFilterChip(
          key: ValueKey('global-search-condition-$index'),
          controller: controller,
          condition: controller.conditions[index],
          maxWidth: maxWidth,
          onEdit: () {
            final condition = controller.conditions[index];
            final filter = globalSearchFilter(
              condition.filterId,
              controller.capabilities,
            )!;
            controller.beginFilter(filter);
            onRefocus?.call();
          },
          onRemove: () {
            controller.removeCondition(index);
            onRefocus?.call();
          },
        ),
      if (controller.hasOrderFilter)
        SearchFilterChip(
          controller: controller,
          condition: GlobalSearchCondition(
            filterId: 'order',
            value: [controller.order],
          ),
          maxWidth: maxWidth,
          onEdit: () {
            controller.beginFilter(
              globalSearchOrderFilter(controller.capabilities),
              value: controller.order,
            );
            onRefocus?.call();
          },
          onRemove: () {
            controller.setOrder('relevance');
            onRefocus?.call();
          },
        ),
    ],
  );
}

class SearchFilterChip extends StatelessWidget {
  const SearchFilterChip({
    super.key,
    required this.controller,
    required this.condition,
    required this.maxWidth,
    required this.onEdit,
    this.onRemove,
    this.focusNode,
    this.expanded = false,
    this.hasPopup = false,
  });
  final GlobalSearchController controller;
  final GlobalSearchCondition condition;
  final double maxWidth;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;
  final FocusNode? focusNode;
  final bool expanded, hasPopup;
  @override
  Widget build(BuildContext context) {
    final filter = globalSearchFilter(
      condition.filterId,
      controller.capabilities,
    )!;
    final operator =
        filter.operators
            .where((op) => op.value == condition.operator)
            .firstOrNull
            ?.label ??
        condition.operator;
    final prefix = filter.operators.length > 1 ? '$operator ' : '';
    final value =
        prefix +
        condition.value
            .map(
              (value) => _searchChoiceLabel(context, controller, filter, value),
            )
            .join(', ');
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DButtonGroup(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: DButton(
              label: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${filter.label}: ',
                      style: TextStyle(color: DTokens.of(context).primary),
                    ),
                    TextSpan(text: value),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              shape: DButtonShape.pill,
              size: DButtonSize.small,
              variant: DButtonVariant.secondary,
              onPressed: onEdit,
              focusNode: focusNode,
              expanded: expanded,
              hasPopup: hasPopup,
            ),
          ),
          if (onRemove != null)
            DButton.iconOnly(
              icon: const DIcon(DIcons.xmark),
              tooltip: context.l10n.removeCondition(filter.label),
              size: DButtonSize.small,
              variant: DButtonVariant.secondary,
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

class _RecentQuery extends StatelessWidget {
  const _RecentQuery(this.controller, this.term);
  final GlobalSearchController controller;
  final String term;
  @override
  Widget build(BuildContext context) {
    final expression = controller.recentExpression(term);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final condition in expression.conditions)
          DBadge(
            variant: DBadgeVariant.secondary,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${condition.filterId}: ',
                    style: TextStyle(color: DTokens.of(context).primary),
                  ),
                  TextSpan(text: condition.text),
                ],
              ),
            ),
          ),
        if (expression.query.isNotEmpty)
          Text(expression.query, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (expression.order != null)
          DBadge(
            variant: DBadgeVariant.secondary,
            child: Text('${context.l10n.ordering}: ${expression.order}'),
          ),
      ],
    );
  }
}

String _searchDate(DateTime value) {
  final day = calendarDay(value)!;
  return '${day.day} ${shortMonthName(day.month)} ${day.year}';
}

class _SearchHighlight extends StatelessWidget {
  const _SearchHighlight({
    required this.siteUrl,
    required this.text,
    required this.query,
  });
  final String siteUrl, text, query;
  @override
  Widget build(BuildContext context) {
    final words = searchWords(query);
    if (words.isEmpty) return SiteEmojiText.plain(text, siteUrl: siteUrl);
    final expression = RegExp(
      words.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    final runs = <SiteEmojiTextRun>[];
    var cursor = 0;
    for (final match in expression.allMatches(text)) {
      if (match.start > cursor) {
        runs.add(SiteEmojiTextRun(text.substring(cursor, match.start)));
      }
      runs.add(
        SiteEmojiTextRun(
          match.group(0)!,
          style: TextStyle(
            color: DTokens.of(context).primary,
            backgroundColor: DTokens.of(context).primary.withValues(alpha: .13),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      runs.add(SiteEmojiTextRun(text.substring(cursor)));
    }
    return SiteEmojiText(runs, siteUrl: siteUrl);
  }
}

class _GlobalSearchDisplay extends StatelessWidget {
  const _GlobalSearchDisplay({required this.controller});
  final GlobalSearchController controller;
  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 320,
      align: DPopoverAlign.end,
      semanticLabel: context.l10n.orderingAndDisplay,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DLabel(child: Text(context.l10n.ordering)),
            const SizedBox(height: 8),
            DSelect<String>.controlled(
              key: const ValueKey('global-search-order'),
              value: controller.order,
              onChanged: (value) {
                if (value != null) controller.setOrder(value);
              },
              width: double.infinity,
              semanticLabel: context.l10n.orderSearchResults,
              entries: [
                for (final order in controller.orders)
                  DSelectItem(
                    value: order.value,
                    textValue: order.label,
                    child: Text(order.label),
                  ),
              ],
            ),
            if (controller.canOrderAscending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(context.l10n.ascending)),
                  DSwitch(
                    value: controller.ascending,
                    onChanged: (value) =>
                        controller.setOrder(controller.order, ascending: value),
                    semanticLabel: context.l10n.ascendingOrder,
                  ),
                ],
              ),
            ],
            const DSeparator(space: 25),
            DLabel(child: Text(context.l10n.displayProperties)),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final property in GlobalSearchDisplayProperty.values.where(
                  (property) =>
                      controller.scope == GlobalSearchScope.all ||
                      controller.scope == GlobalSearchScope.forum ||
                      controller.scope.displayProperties.contains(property),
                ))
                  DCheckbox(
                    key: ValueKey('global-search-property-${property.name}'),
                    value: controller.properties.contains(property),
                    onChanged: (value) =>
                        controller.setDisplayProperty(property, value == true),
                    title: Text(switch (property) {
                      GlobalSearchDisplayProperty.excerpt =>
                        context.l10n.excerpt,
                      GlobalSearchDisplayProperty.category =>
                        context.l10n.category,
                      GlobalSearchDisplayProperty.tags => context.l10n.tags,
                      GlobalSearchDisplayProperty.author => context.l10n.author,
                      GlobalSearchDisplayProperty.likes => context.l10n.likes,
                      GlobalSearchDisplayProperty.replies =>
                        context.l10n.replies,
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, state) => DButton.iconOnly(
        key: const ValueKey('global-search-display-trigger'),
        icon: const DIcon(DIcons.gear),
        tooltip: context.l10n.orderingAndDisplay,
        variant: DButtonVariant.outline,
        size: DButtonSize.small,
        expanded: state.open,
        hasPopup: true,
        focusNode: state.focusNode,
        onPressed: state.toggle,
      ),
    ),
  );
}
