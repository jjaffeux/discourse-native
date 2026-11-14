import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/calendar_day.dart';
import '../foundation/count_label.dart';
import '../foundation/icons/d_icons.dart';
import '../models/search_results.dart';
import '../models/topic.dart';
import '../plugin_api/global_search_filters.dart';
import '../plugin_api/global_search_models.dart';
import '../plugin_api/plugin_scope.dart';
import '../utils/pagination.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'global_search_api.dart';
import 'global_search_controller.dart';
import 'open_link.dart';
import 'search_words.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';
import 'site_url.dart';
import 'skeleton_fill.dart';

part 'global_search_category_editor.dart';
part 'global_search_filter_picker.dart';

final RegExp _whitespace = RegExp(r'\s+');

class _PreparedSearchResult {
  _PreparedSearchResult({required this.result, required this.open});

  final GlobalSearchResult result;
  final VoidCallback open;

  /// The row widget and the reads it was drawn from, kept while the result
  /// stays in the list so a later source's answer does not redraw it.
  List<Object?>? reads;
  Widget? row;
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
    this.footerControls = false,
  });

  final GlobalSearchController controller;
  final ValueChanged<GlobalSearchResult> onOpen;
  final String? selectedResultId;
  final ValueChanged<String>? onSelect;
  final ValueChanged<GlobalSearchSection>? onOpenSection;
  final VoidCallback? onApply, onRefocus;

  /// Includes the standalone condition toolbar; shell chips live in its input.
  final bool showConditions;
  final bool showClearFilters;

  /// Phone search keeps scope and condition controls at the sheet foot.
  final bool footerControls;

  @override
  State<GlobalSearchPanel> createState() => GlobalSearchPanelState();
}

class GlobalSearchPanelState extends State<GlobalSearchPanel> {
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _resultKeys = {};
  final _preparedResults =
      Map<GlobalSearchResult, _PreparedSearchResult>.identity();
  final _resultSelection = ValueNotifier<String?>(null);
  final _scopeKeys = <GlobalSearchScope, GlobalKey>{};
  GlobalSearchScope? _revealedScope;
  final _actions =
      <
        ({
          String id,
          VoidCallback open,
          VoidCallback? into,
          VoidCallback? back,
          GlobalSearchResult? result,
        })
      >[];
  bool _filtersOpen = false;
  String? _selected;
  bool _initialSectionPending = true;
  Object? _selectedNavigationIdentity;
  final _drill = <int>[];
  Object? _lookupKey;
  Timer? _lookupTimer;
  int _lookupRevision = 0;
  List<GlobalSearchFilterChoice> _choices = const [];
  bool _loadingChoices = false;
  String? _choiceError;
  Object? _navigationSignature;
  int _categoryPage = 0;
  bool _hasMoreChoices = false;
  List<Object?>? _scopeBarReads, _skeletonReads;
  Widget? _builtScopeBar, _builtSkeleton;
  List<Object?> _rowReads = const [];

  Object? _targetFor(String? id) => widget.controller.results
      .where((result) => result.id == id)
      .firstOrNull
      ?.navigationIdentity;

  void _checkSelectionTarget() {
    if (_selectedNavigationIdentity != null &&
        _targetFor(_selected) != _selectedNavigationIdentity) {
      _selected = null;
      _selectedNavigationIdentity = null;
      _initialSectionPending = false;
    }
    _publishSelection();
  }

  /// Rows kept across builds read the selection through [_resultSelection],
  /// and only a result id draws one of them selected.
  void _publishSelection() =>
      _resultSelection.value = _targetFor(_selected) == null ? null : _selected;

  bool handleKey(LogicalKeyboardKey key, {bool reverse = false}) {
    _checkSelectionTarget();
    final current = _actions.indexWhere((action) => action.id == _selected);
    final action = current >= 0 ? _actions[current] : _actions.firstOrNull;
    // A row's own way sideways comes before switching search types.
    if (key == LogicalKeyboardKey.arrowRight && action?.into != null) {
      action!.into!();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft && action?.back != null) {
      action!.back!();
      return true;
    }
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
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (_actions.isEmpty) return true;
      final down = key == LogicalKeyboardKey.arrowDown;
      final next = current < 0
          ? (down ? 0 : _actions.length - 1)
          : (current + (down ? 1 : -1) + _actions.length) % _actions.length;
      void select() {
        _selected = _actions[next].id;
        _selectedNavigationIdentity = _targetFor(_selected);
      }

      final updatesOnlyResultSelection =
          current >= 0 &&
          _actions[current].result != null &&
          _actions[next].result != null;
      if (updatesOnlyResultSelection) {
        select();
      } else {
        setState(select);
      }
      _publishSelection();
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
        final row = target.findRenderObject()! as RenderBox;
        final position = _scroll.position;
        if (row.size.height > position.viewportDimension) {
          unawaited(position.ensureVisible(row, alignment: .5));
          return;
        }
        unawaited(
          position.ensureVisible(
            row,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
        unawaited(
          position.ensureVisible(
            row,
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
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void resetSelection() {
    _selected = null;
    _initialSectionPending = true;
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
    VoidCallback? back,
  }) {
    _actions.add((id: id, open: open, into: into, back: back, result: null));
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

  /// A label over a list, at the height of the rows under it: its mark in
  /// their mark column, so its words start where theirs do.
  Widget _heading(
    BuildContext context,
    DIconData icon,
    String label, {
    Key? key,
    Widget? trailing,
  }) {
    final muted = DTokens.of(context).mutedForeground;
    final phone = DControlStyle.isTouch(context);
    return ConstrainedBox(
      key: key,
      constraints: const BoxConstraints(minHeight: 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(
          spacing: 10,
          children: [
            if (!phone)
              SizedBox(width: 30, child: DIcon(icon, size: 16, color: muted)),
            Expanded(
              // Large text moves the trailing action under the label rather
              // than squeezing either.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: DiscourseTypography.control,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The filters under an empty field wait folded, as a sidebar section
  /// does, so past searches are what is in sight.
  Widget _filtersFold(BuildContext context) {
    const id = 'fold:filters';
    final muted = DTokens.of(context).mutedForeground;
    void turn(bool open) => setState(() => _filtersOpen = open);
    return _action(
      id,
      () => turn(!_filtersOpen),
      into: _filtersOpen ? null : () => turn(true),
      back: _filtersOpen ? () => turn(false) : null,
      DItem(
        key: const ValueKey('global-search-filters-fold'),
        size: DItemSize.artwork,
        shape: DItemShape.menu,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        selected: _selected == id,
        selectionStyle: DItemSelectionStyle.strongNeutral,
        showSelectionIndicator: false,
        onPressed: () => turn(!_filtersOpen),
        children: [
          DItemContent(
            children: [
              Semantics(
                expanded: _filtersOpen,
                child: Row(
                  spacing: 10,
                  children: [
                    SizedBox(
                      width: 30,
                      child: DIcon(DIcons.filter, size: 16, color: muted),
                    ),
                    Expanded(
                      child: Text(
                        context.l10n.filters,
                        style: TextStyle(
                          fontSize: DiscourseTypography.control,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _filtersOpen ? 0 : -.25,
                      duration: DMotion.duration(
                        context,
                        const Duration(milliseconds: 150),
                      ),
                      child: DIcon(DIcons.chevronDown, size: 11, color: muted),
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

  List<Widget> _filterRows(BuildContext context, {bool folded = false}) {
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
    final tokens = DTokens.of(context);
    if (filters.isEmpty) return const [];
    if (folded && !_filtersOpen) return [_filtersFold(context)];
    // Keep each filter as a sliver child: a Column mounts and lays out the
    // entire catalogue even when only its first few rows are visible.
    return [
      if (folded)
        _filtersFold(context)
      else
        _heading(context, DIcons.filter, context.l10n.filters),
      for (final group in groups.entries) ...[
        if (group.key.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(49, 10, 9, 4),
            child: Text(
              group.key,
              style: TextStyle(
                fontSize: DiscourseTypography.metadata,
                fontWeight: FontWeight.w600,
                color: tokens.mutedForeground,
              ),
            ),
          ),
        for (final filter in group.value)
          _action(
            'filter:${filter.id}',
            () => _stage(filter),
            DItem(
              key: ValueKey('global-search-offered-${filter.id}'),
              size: DItemSize.artwork,
              shape: DItemShape.menu,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              selected:
                  _selected == 'filter:${filter.id}' ||
                  (_selected == null && _actions.isEmpty),
              selectionStyle: DItemSelectionStyle.strongNeutral,
              showSelectionIndicator: false,
              onPressed: () => _stage(filter),
              children: [
                DItemContent(
                  children: [
                    Row(
                      spacing: 10,
                      children: [
                        SizedBox.square(
                          dimension: 30,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.raisedBackground,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: DIcon(
                                _filterIcon(context, filter.icon),
                                size: 12,
                                color: tokens.mutedForeground,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: DItemTitle(
                            child: Text.rich(
                              TextSpan(
                                text: filter.label,
                                children: [
                                  if (filter.help.isNotEmpty) ...[
                                    const WidgetSpan(child: SizedBox(width: 8)),
                                    TextSpan(
                                      text: filter.help,
                                      style: TextStyle(
                                        fontSize: DiscourseTypography.metadata,
                                        color: tokens.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              style: const TextStyle(
                                fontSize: DiscourseTypography.control,
                                height: 1.35,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ],
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
    final term = controller.stagedTerm;
    final key = (
      controller,
      controller.categoryLookupSession,
      controller.siteUrl,
      controller.configurationRevision,
      filter.id,
      term,
    );
    if (_lookupKey == key) return;
    _lookupKey = key;
    _choices = filter.id == 'category'
        ? controller.cachedCategoryChoices(term)
        : const [];
    _hasMoreChoices = false;
    _categoryPage = 0;
    _choiceError = null;
    _loadingChoices = true;
    final revision = ++_lookupRevision;
    bool current() =>
        mounted &&
        revision == _lookupRevision &&
        identical(widget.controller, controller) &&
        key ==
            (
              controller,
              controller.categoryLookupSession,
              controller.siteUrl,
              controller.configurationRevision,
              controller.stagedFilter?.id,
              controller.stagedTerm,
            );
    Future<void> load() async {
      if (!current()) return;
      try {
        final categoryPage = filter.id == 'category'
            ? await controller.lookupCategoryChoices(term)
            : null;
        final choices = filter.choices.isNotEmpty
            ? filter.choices
            : filter.id == 'category'
            ? categoryPage!.choices
            : await controller.lookupChoices(filter, term);
        if (!current()) return;
        setState(() {
          _choices = choices;
          _categoryPage = categoryPage == null ? 0 : 1;
          _hasMoreChoices = categoryPage?.hasMore ?? false;
          _loadingChoices = false;
        });
      } catch (error) {
        if (!current()) return;
        setState(() {
          _loadingChoices = false;
          _choiceError = GlobalSearchApi.failureMessage(error);
        });
      }
    }

    _lookupTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!current()) return;
      if (filter.choices.isEmpty && term.isNotEmpty) {
        _lookupTimer = Timer(const Duration(milliseconds: 180), load);
      } else {
        unawaited(load());
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

    Future<void> loadChoices() async {
      if (_loadingChoices || !_hasMoreChoices) return;
      final revision = _lookupRevision;
      setState(() {
        _loadingChoices = true;
        _choiceError = null;
      });
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
          if (_loadingChoices)
            DSkeletonRegion(
              semanticsLabel: context.l10n.loading,
              color: skeletonFill(context, on: SkeletonSurface.floating),
              child: Column(
                children: [
                  for (var index = 0; index < 3; index++)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: DSpacing.sm),
                      child: DSkeleton(height: 16),
                    ),
                ],
              ),
            ),
          if (_choiceError != null)
            Text(
              _choiceError!,
              style: TextStyle(color: DTokens.of(context).destructive),
            ),
          if (_choiceError != null)
            DButton(
              label: Text(context.l10n.retry),
              variant: DButtonVariant.ghost,
              onPressed: _hasMoreChoices
                  ? loadChoices
                  : () => setState(() => _lookupKey = null),
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
          ScrollPageTrigger(
            enabled:
                _hasMoreChoices && !_loadingChoices && _choiceError == null,
            onLoad: loadChoices,
            child: const SizedBox.shrink(),
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
    _lookupTimer?.cancel();
    _scroll.dispose();
    _resultSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final phone = DControlStyle.isTouch(context);
      if (_revealedScope != controller.scope) {
        _revealedScope = controller.scope;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final target = _scopeKeys[widget.controller.scope]?.currentContext;
          final scroll = target == null
              ? null
              : Scrollable.maybeOf(target, axis: Axis.horizontal);
          final renderObject = target?.findRenderObject();
          if (scroll == null || renderObject == null) return;
          scroll.position.ensureVisible(renderObject, alignment: .5);
        });
      }
      final signature = (
        controller,
        controller.categoryLookupSession,
        controller.configurationRevision,
        controller.query,
        controller.scope,
      );
      if (signature != _navigationSignature) {
        _lookupTimer?.cancel();
        _lookupTimer = null;
        _lookupKey = null;
        _lookupRevision++;
        resetSelection();
        _navigationSignature = signature;
      }
      _checkSelectionTarget();
      _rowReads = [
        controller,
        controller.siteUrl,
        controller.query,
        controller.conditions.any(
          (condition) => condition.filterId == 'author',
        ),
        for (final property in GlobalSearchDisplayProperty.values)
          controller.properties.contains(property),
      ];
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
        builder: (context, constraints) {
          final body = _body(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.footerControls)
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
                        _scopeBar(context),
                        if (widget.showConditions)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Row(
                              spacing: 4,
                              children: [
                                _GlobalSearchFilterPicker(
                                  controller: controller,
                                ),
                                _GlobalSearchDisplay(controller: controller),
                              ],
                            ),
                          ),
                        if (widget.showConditions &&
                            controller.conditions.isNotEmpty)
                          _conditions(context),
                      ],
                    ),
                  ),
                ),
              if (!widget.footerControls) const DSeparator(),
              Expanded(child: phone ? DMenuContentScale(child: body) : body),
              if (widget.footerControls) _phoneFooter(context),
            ],
          );
        },
      );
    },
  );

  Widget _phoneFooter(BuildContext context) {
    final controller = widget.controller;
    final narrowed = controller.conditions.isNotEmpty;
    return DSheetFooter(
      key: const ValueKey('global-search-phone-footer'),
      padding: EdgeInsets.zero,
      children: [
        const DSeparator(),
        if (!narrowed) _scopeBar(context),
        if (narrowed || controller.hasOrderFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: LayoutBuilder(
              builder: (context, constraints) => DScrollArea(
                axes: DScrollAxes.horizontal,
                showScrollbar: false,
                child: GlobalSearchChips(
                  controller: controller,
                  maxWidth: constraints.maxWidth,
                  onRefocus: widget.onRefocus,
                ),
              ),
            ),
          ),
      ],
    );
  }

  int _scopeCount(GlobalSearchScope scope) => widget.controller.sections
      .where((section) => section.scope == scope && section.topicId == null)
      .fold(0, (count, section) => count + section.results.length);

  /// The scope bar is drawn again only when a scope, its count or the
  /// selection changes; every keystroke and result delivery notifies.
  Widget _scopeBar(BuildContext context) {
    final controller = widget.controller;
    final phone = DControlStyle.isTouch(context);
    final scopes = widget.footerControls
        ? [
            GlobalSearchScope.all,
            GlobalSearchScope.forum,
            GlobalSearchScope.messages,
            ...controller.scopes.where((scope) => !scope.isCore),
            GlobalSearchScope.places,
            GlobalSearchScope.users,
            GlobalSearchScope.groups,
          ].where(controller.scopes.contains).toList()
        : controller.scopes;
    final counts = {for (final scope in scopes) scope: _scopeCount(scope)};
    final knownCounts =
        widget.footerControls &&
        controller.scope == GlobalSearchScope.all &&
        (controller.phase == GlobalSearchPhase.results ||
            controller.phase == GlobalSearchPhase.empty);
    final reads = <Object?>[
      controller,
      context.l10n,
      phone,
      widget.footerControls,
      controller.scope,
      knownCounts,
      for (final scope in scopes) ...[scope, counts[scope]],
    ];
    if (_builtScopeBar == null || !listEquals(reads, _scopeBarReads)) {
      _scopeBarReads = reads;
      _builtScopeBar = DToggleGroup<GlobalSearchScope>(
        values: [controller.scope],
        onChanged: (values) => controller.setScope(values.single),
        allowEmptySelection: false,
        density: phone && !widget.footerControls
            ? DToggleDensity.standard
            : DToggleDensity.menuFilter,
        variant: phone && !widget.footerControls
            ? DToggleVariant.standard
            : DToggleVariant.outline,
        size: widget.footerControls
            ? DToggleSize.filter
            : phone
            ? DToggleSize.segment
            : DToggleSize.regular,
        inset: phone && !widget.footerControls,
        spacing: 1.5,
        semanticLabel: context.l10n.globalSearch,
        items: [
          for (final scope in scopes)
            DToggleGroupItem(
              value: scope,
              semanticLabel: scope.label,
              child: KeyedSubtree(
                key: _scopeKeys.putIfAbsent(scope, GlobalKey.new),
                child: Opacity(
                  opacity:
                      knownCounts &&
                          scope != controller.scope &&
                          counts[scope] == 0
                      ? .5
                      : 1,
                  child: Row(
                    key: ValueKey('global-search-scope-${scope.keyName}'),
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Text(scope.label),
                      if (scope != GlobalSearchScope.all && counts[scope]! > 0)
                        Text(
                          counts[scope]! > 99 ? '99+' : '${counts[scope]}',
                          style: TextStyle(
                            fontSize: phone
                                ? DiscourseTypography.metadata
                                : DiscourseTypography.micro,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return phone
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: _builtScopeBar!,
          )
        : _builtScopeBar!;
  }

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
      return _loadingResults(context);
    }
    if (phase == GlobalSearchPhase.failed &&
        results.isEmpty &&
        !controller.hasMore) {
      return _status(
        context.l10n.searchCouldNotLoad,
        controller.error ?? context.l10n.pleaseTryAgain,
        error: true,
      );
    }
    if (phase == GlobalSearchPhase.empty && !controller.hasMore) {
      return _status(
        context.l10n.noResultsFound,
        context.l10n.tryDifferentWordsOrRemoveACondition,
        clear: controller.conditions.isNotEmpty,
      );
    }
    final all = controller.scope == GlobalSearchScope.all;
    final phone = DControlStyle.isTouch(context);
    final phoneSheet = widget.footerControls;
    var sectionIndex = 0;
    final children = <Object>[
      if (controller.hintedFilters.isNotEmpty) ..._filterRows(context),
      for (final section in controller.sections.where(
        (section) =>
            !all || section.results.isNotEmpty || section.error != null,
      )) ...[
        if (sectionIndex++ > 0) SizedBox(height: phone ? 16 : 8),
        if (!phoneSheet ||
            section.topicId != null ||
            all && section.scope != GlobalSearchScope.forum)
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
        if (_inLine(context, section)) ...[
          const SizedBox(height: 2),
          _resultLine(context, section),
        ] else
          for (final result
              in all
                  ? section.results.take(_sectionLimit(section))
                  : section.results) ...[
            const SizedBox(height: 2),
            _prepareResult(result),
          ],
      ],
      if (controller.error != null &&
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
      if (controller.wordsQuery.trim().isEmpty &&
          controller.hintedFilters.isEmpty)
        ..._filterRows(context),
      if (controller.hasMore || controller.loadingMore)
        ScrollPageTrigger(
          enabled:
              controller.hasMore &&
              !controller.loadingMore &&
              controller.error == null &&
              phase != GlobalSearchPhase.loading,
          onLoad: controller.loadMore,
          child: controller.loadingMore
              ? DSkeletonRegion(
                  semanticsLabel: context.l10n.loading,
                  color: skeletonFill(context, on: SkeletonSurface.floating),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: DSkeleton(height: 16),
                  ),
                )
              : controller.error != null
              ? DButton(
                  label: Text(context.l10n.tryAgain),
                  onPressed: controller.loadMore,
                  variant: DButtonVariant.ghost,
                )
              : const SizedBox.shrink(),
        ),
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
          ? ValueKey('search-row:${child.result.id}')
          : (child as Widget).key == null
          ? null
          : ValueKey(child.key);
      if (key != null) childIndices[key] = index;
    }
    final content = DScrollBar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: children.length,
        findChildIndexCallback: (key) => childIndices[key],
        itemBuilder: (context, index) {
          final child = children[index];
          final widget = child is _PreparedSearchResult
              ? _result(child)
              : child as Widget;
          return Padding(
            key: child is _PreparedSearchResult
                ? ValueKey('search-row:${child.result.id}')
                : widget.key == null
                ? null
                : ValueKey(widget.key),
            padding:
                widget is SingleChildScrollView &&
                    widget.scrollDirection == Axis.horizontal
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 6),
            child: widget,
          );
        },
      ),
    );
    return DScrollChromePagination(
      hasMore: controller.hasMore,
      loading: controller.loadingMore,
      child: content,
    );
  }

  /// The skeleton is shaped by the scope and the theme alone, while every
  /// keystroke of a pending search notifies.
  Widget _loadingResults(BuildContext context) {
    final showAvatar = widget.controller.scope.showAvatar;
    final fill = skeletonFill(context, on: SkeletonSurface.floating);
    final reads = <Object?>[context.l10n, showAvatar, fill];
    if (_builtSkeleton == null || !listEquals(reads, _skeletonReads)) {
      _skeletonReads = reads;
      _builtSkeleton = _buildLoadingResults(context, showAvatar: showAvatar);
    }
    return _builtSkeleton!;
  }

  Widget _buildLoadingResults(
    BuildContext context, {
    required bool showAvatar,
  }) => SingleChildScrollView(
    padding: const EdgeInsets.all(6),
    child: DSkeletonRegion(
      semanticsLabel: context.l10n.loading,
      color: skeletonFill(context, on: SkeletonSurface.floating),
      child: Column(
        children: [
          for (var index = 0; index < 8; index++)
            DItem(
              size: DItemSize.artwork,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              children: [
                DItemContent(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        if (showAvatar)
                          const DSkeleton.circle(diameter: 30)
                        else
                          const SizedBox(width: 30),
                        Expanded(
                          child: DItemContent(
                            spacing: 3,
                            alignment: CrossAxisAlignment.stretch,
                            children: [
                              FractionallySizedBox(
                                widthFactor: index.isEven ? .75 : .6,
                                alignment: AlignmentDirectional.centerStart,
                                child: const DSkeleton(height: 16),
                              ),
                              const DSkeleton(height: 14),
                              const FractionallySizedBox(
                                widthFactor: .45,
                                alignment: AlignmentDirectional.centerStart,
                                child: DSkeleton(height: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    ),
  );

  int _sectionLimit(GlobalSearchSection section) =>
      section.scope == GlobalSearchScope.forum ? 3 : 2;

  bool _inLine(BuildContext context, GlobalSearchSection section) =>
      widget.controller.scope == GlobalSearchScope.all &&
      DControlStyle.isTouch(context) &&
      const [
        GlobalSearchScope.places,
        GlobalSearchScope.users,
        GlobalSearchScope.groups,
      ].contains(section.scope);

  Widget _resultLine(BuildContext context, GlobalSearchSection section) =>
      SingleChildScrollView(
        key: ValueKey('global-search-line-${section.scope.keyName}'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(55, 2, 12, 4),
        child: Row(
          spacing: 8,
          children: [
            for (final result in section.results)
              Builder(
                builder: (context) => Focus(
                  canRequestFocus: false,
                  onFocusChange: (focused) {
                    if (focused) _revealResultPill(context);
                  },
                  child: _resultPill(context, result),
                ),
              ),
          ],
        ),
      );

  void _revealResultPill(BuildContext context) {
    final position = Scrollable.of(context, axis: Axis.horizontal).position;
    final target = context.findRenderObject()!;
    final width = (target as RenderBox).size.width;
    // CSS scroll-padding-left keeps a focused pill aligned with result text.
    final available = position.viewportDimension - width;
    position.ensureVisible(
      target,
      alignment: available > 0 ? (55 / available).clamp(0, 1) : 0,
    );
  }

  Widget _resultPill(BuildContext context, GlobalSearchResult result) {
    final tokens = DTokens.of(context);
    final source = result.source;
    final label = source is SearchGroupHit ? source.name : result.title;
    final color = source is SearchCategoryHit ? Color(source.colorValue) : null;
    final surface = color == null ? null : tokens.categoryControlSurface(color);
    return DButton(
      key: ValueKey('global-search-result-${result.id}'),
      variant: DButtonVariant.outline,
      density: DButtonDensity.filterPill,
      backgroundColor:
          surface?.background ?? tokens.quietControlSurface().background,
      foregroundColor:
          surface?.foreground ?? tokens.quietControlSurface().foreground,
      borderColor: surface?.border ?? Colors.transparent,
      interactiveBackgroundColor:
          surface?.hover ?? tokens.quietControlSurface().hover,
      semanticLabel: label,
      tooltip: label,
      icon: result.scope == GlobalSearchScope.users
          ? DAvatar(
              dimension: 18,
              border: false,
              child: AvatarImage(
                url: result.avatarUrl,
                size: 18,
                fallback: DAvatarFallback(
                  child: Text(result.title.characters.first),
                ),
              ),
            )
          : color != null
          ? SizedBox.square(
              dimension: 9,
              child: DCard(
                backgroundColor: color,
                spacing: 0,
                border: false,
                borderRadius: BorderRadius.circular(2),
                child: const SizedBox(height: 9),
              ),
            )
          : DIcon(
              result.scope == GlobalSearchScope.groups
                  ? DIcons.userGroup
                  : DIcons.tag,
              size: 11,
            ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: _SearchHighlight(
          siteUrl: widget.controller.siteUrl!,
          text: label,
          query: widget.controller.query,
        ),
      ),
      onPressed: () => widget.onOpen(result),
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

    final phoneSheet = widget.footerControls;
    final id = 'section:${section.scope.keyName}:${section.topicId ?? ""}';
    if (_initialSectionPending &&
        _selected == null &&
        _actions.isEmpty &&
        section.results.isNotEmpty) {
      _selected = id;
      _initialSectionPending = false;
    }
    return _action(
      id,
      open,
      DItem(
        key: ValueKey(id),
        size: DItemSize.artwork,
        shape: DItemShape.menu,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        selected: _selected == id && !phoneSheet,
        selectionStyle: DItemSelectionStyle.strongNeutral,
        showSelectionIndicator: false,
        onPressed: section.results.isEmpty ? null : open,
        children: [
          DItemContent(
            children: [
              Row(
                spacing: 10,
                children: [
                  if (!phoneSheet || section.topicId != null)
                    SizedBox(
                      width: 30,
                      child: DIcon(
                        section.topicId != null
                            ? DIcons.comment
                            : section.scope == GlobalSearchScope.forum
                            ? DIcons.comments
                            : section.scope == GlobalSearchScope.messages
                            ? DIcons.envelope
                            : section.scope == GlobalSearchScope.users
                            ? DIcons.users
                            : section.scope == GlobalSearchScope.groups
                            ? DIcons.userGroup
                            : section.scope == GlobalSearchScope.places
                            ? DIcons.layerGroup
                            : DIcons.comment,
                        size: 16,
                        color: DTokens.of(context).mutedForeground,
                      ),
                    ),
                  Expanded(
                    child: Text.rich(
                      section.topicId != null
                          ? TextSpan(
                              text: context.l10n.inThisTopicSearch,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: DTokens.of(context).foreground,
                              ),
                              children: [
                                // Which topic, for two open side by side.
                                TextSpan(
                                  text: '  ${section.topicTitle ?? ''}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: DTokens.of(context).mutedForeground,
                                  ),
                                ),
                              ],
                            )
                          : TextSpan(text: section.scope.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DiscourseTypography.control,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: DTokens.of(context).mutedForeground,
                      ),
                    ),
                  ),
                  if (section.topicId != null && section.results.isNotEmpty)
                    const DNavigationPill()
                  else if (widget.controller.scope == GlobalSearchScope.all &&
                      !_inLine(context, section) &&
                      section.results.length > _sectionLimit(section))
                    ExcludeSemantics(
                      child: Row(
                        spacing: 6,
                        children: [
                          Text(
                            context.l10n.seeAllSearchResults,
                            style: TextStyle(
                              fontSize: DiscourseTypography.xs,
                              color: DTokens.of(context).mutedForeground,
                            ),
                          ),
                          DIcon(
                            DIcons.chevronRight,
                            size: 9,
                            color: DTokens.of(context).mutedForeground,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _history(BuildContext context) {
    final controller = widget.controller;
    final phone = DControlStyle.isTouch(context);
    // The word still being typed narrows past searches; while there is one,
    // the filters it could start stand open.
    final needle = controller.query.endsWith(' ')
        ? ''
        : controller.query.split(_whitespace).last.toLowerCase();
    final recents = needle.isEmpty
        ? controller.recentSearches
        : controller.recentSearches
              .where((query) => query.toLowerCase().contains(needle))
              .toList();
    return DScrollBar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(6),
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

          if (recents.isNotEmpty) ...[
            _heading(
              context,
              DIcons.farClock,
              context.l10n.recentSearches,
              key: const ValueKey('global-search-recent-heading'),
              trailing: needle.isNotEmpty
                  ? null
                  : DButton(
                      key: const ValueKey('global-search-clear-history'),
                      tooltip: context.l10n.clearHistory,
                      label: Text(
                        phone ? context.l10n.clear : context.l10n.clearHistory,
                        softWrap: true,
                        maxLines: 2,
                      ),
                      variant: DButtonVariant.inline,
                      density: DButtonDensity.inlineMetadata,
                      foregroundColor: DTokens.of(context).mutedForeground,
                      onPressed: controller.clearHistory,
                    ),
            ),
            for (final query in recents)
              _action(
                'recent:$query',
                () {
                  controller.useRecentSearch(query);
                  widget.onRefocus?.call();
                },
                DItem(
                  key: ValueKey('global-search-recent-$query'),
                  size: DItemSize.xs,
                  shape: DItemShape.menu,
                  padding: EdgeInsetsDirectional.fromSTEB(
                    phone ? 9 : 49,
                    4,
                    6,
                    4,
                  ),
                  selected: _selected == 'recent:$query',
                  selectionStyle: DItemSelectionStyle.strongNeutral,
                  showSelectionIndicator: false,
                  onPressed: () {
                    controller.useRecentSearch(query);
                    widget.onRefocus?.call();
                  },
                  children: [
                    if (phone)
                      const DItemMedia(child: DIcon(DIcons.farClock, size: 12)),
                    DItemContent(
                      children: [
                        DefaultTextStyle.merge(
                          style: const TextStyle(
                            fontSize: DiscourseTypography.control,
                            height: 1.35,
                          ),
                          child: _RecentQuery(controller, query),
                        ),
                      ],
                    ),
                    DItemActions(
                      children: [
                        DButton.iconOnly(
                          icon: const DIcon(DIcons.xmark, size: 11),
                          tooltip: context.l10n.remove(query),
                          variant: DButtonVariant.ghost,
                          shape: DButtonShape.pill,
                          size: DButtonSize.chip,
                          foregroundColor: DTokens.of(context).mutedForeground,
                          onPressed: () => controller.removeRecentSearch(query),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
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
          if (recents.isNotEmpty && controller.availableFilters.isNotEmpty)
            SizedBox(height: DControlStyle.isTouch(context) ? 16 : 8),
          ..._filterRows(
            context,
            folded: needle.isEmpty && !DControlStyle.isTouch(context),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        DItem(
          size: DItemSize.artwork,
          children: [
            DItemContent(
              spacing: 4,
              alignment: CrossAxisAlignment.stretch,
              children: [
                DEmptyDescription.child(
                  child: Text(
                    title,
                    textAlign: TextAlign.start,
                    style: const TextStyle(
                      fontSize: DiscourseTypography.control,
                      height: 1.35,
                    ),
                  ),
                ),
                DEmptyDescription.child(
                  child: Text(
                    description,
                    textAlign: TextAlign.start,
                    style: const TextStyle(
                      fontSize: DiscourseTypography.preview,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
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
    _actions.add((
      id: result.id,
      open: row.open,
      into: null,
      back: null,
      result: result,
    ));
    return row;
  }

  Widget _result(_PreparedSearchResult row) {
    final reads = [..._rowReads, widget.selectedResultId == row.result.id];
    if (row.row == null || !listEquals(reads, row.reads)) {
      row.reads = reads;
      row.row = _buildResult(row);
    }
    return row.row!;
  }

  Widget _buildResult(_PreparedSearchResult row) {
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
                  ValueListenableBuilder<String?>(
                    valueListenable: _resultSelection,
                    builder: (context, _, _) =>
                        _resultItem(context, result, category),
                  ),
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
      final parents = <String>[];
      final seen = <int>{};
      var parentId = source is SearchCategoryHit
          ? source.parentCategoryId
          : null;
      while (parentId != null && seen.add(parentId)) {
        final parent = ShellScope.maybeRead(
          context,
        )?.categoryFor(parentId, siteUrl: controller.siteUrl);
        if (parent == null) break;
        parents.insert(0, parent.name);
        parentId = parent.parentCategoryId;
      }
      return DItem(
        key: ValueKey('global-search-result-${result.id}'),
        size: DItemSize.artwork,
        shape: DItemShape.menu,
        padding: const EdgeInsetsDirectional.fromSTEB(49, 6, 9, 6),
        selected: _selected == result.id,
        selectionStyle: DItemSelectionStyle.strongNeutral,
        showSelectionIndicator: false,
        onPressed: () => widget.onOpen(result),
        children: [
          DItemContent(
            children: [
              Row(
                spacing: 10,
                children: [
                  SizedBox(
                    width: 16,
                    child: Center(
                      child: swatch != null
                          ? CategoryIcon(
                              category: swatch,
                              size: 9,
                              siteUrl: controller.siteUrl,
                            )
                          : DIcon(
                              DIcons.hashtag,
                              size: 12,
                              color: tokens.mutedForeground,
                            ),
                    ),
                  ),
                  Expanded(
                    child: DItemContent(
                      spacing: 1,
                      children: [
                        DItemTitle(
                          child: _SearchHighlight(
                            siteUrl: controller.siteUrl!,
                            text: result.title,
                            query: controller.query,
                            style: const TextStyle(
                              fontSize: DiscourseTypography.control,
                              height: 1.35,
                            ),
                          ),
                        ),
                        if (parents.isNotEmpty)
                          DItemDescription(
                            maxLines: 1,
                            child: Text(
                              parents.join(' › '),
                              style: const TextStyle(
                                fontSize: DiscourseTypography.metadata,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (count != null)
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: DiscourseTypography.metadata,
                        color: tokens.mutedForeground,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      );
    }
    final inTopic = result.id.startsWith('in-topic:');
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 19.5;
    // When it was said stands beside a message, unless large text would
    // leave the message too little of the row.
    final message = result.scope.layout == GlobalSearchResultLayout.message;
    final timeAside = message && !largeText;
    final individualPost =
        inTopic ||
        source is SearchPostHit &&
            controller.conditions.any(
              (condition) => condition.filterId == 'author',
            );
    final metadata = <Widget>[
      if ((individualPost ||
              properties.contains(GlobalSearchDisplayProperty.author)) &&
          result.username?.isNotEmpty == true)
        Text('@${result.username}'),
      if (individualPost && source is SearchPostHit)
        Text('#${source.postNumber}'),
      if (result.contextLabel?.isNotEmpty == true)
        Text(result.contextLabel!)
      else if (result.privateMessage)
        Text(context.l10n.personalMessage),
      if ((properties.contains(GlobalSearchDisplayProperty.category) ||
              result.scope == GlobalSearchScope.forum) &&
          !individualPost &&
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
          when !individualPost &&
              (properties.contains(GlobalSearchDisplayProperty.replies) ||
                  result.scope == GlobalSearchScope.forum ||
                  result.privateMessage))
        Text(countLabel(replies, CountNoun.reply)),
      if (result.memberCount case final members?)
        Text(countLabel(members, CountNoun.member)),
      if (result.createdAt != null && !timeAside)
        Text(_searchDate(result.createdAt!)),
    ];
    return DItem(
      key: ValueKey('global-search-result-${result.id}'),
      size: DItemSize.artwork,
      shape: DItemShape.menu,
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: message ? 11 : 8),
      onPressed: () {
        widget.onSelect?.call(result.id);
        widget.onOpen(result);
      },
      link: true,
      selected: _selected == result.id || widget.selectedResultId == result.id,
      selectionStyle: DItemSelectionStyle.strongNeutral,
      showSelectionIndicator: false,
      children: [
        DItemContent(
          children: [
            Row(
              // A post in the open topic has one line under its author, so
              // its smaller face centres beside both.
              crossAxisAlignment: inTopic
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              spacing: 10,
              children: [
                if (result.scope.showAvatar || individualPost)
                  SizedBox(
                    width: 30,
                    child: Center(
                      child: DAvatar(
                        dimension: inTopic ? 22 : 30,
                        border: false,
                        decorative: true,
                        child: AvatarImage(
                          url: result.avatarUrl,
                          size: inTopic ? 22 : 30,
                          fallback: DAvatarFallback(
                            child: Text(
                              (result.username ?? result.title).characters
                                  .take(1)
                                  .toString()
                                  .toUpperCase(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 30),
                Expanded(
                  child: DItemContent(
                    spacing: 1,
                    alignment: CrossAxisAlignment.stretch,
                    children: [
                      DItemTitle(
                        child: inTopic && source is SearchPostHit
                            ? SiteEmojiText(
                                [
                                  SiteEmojiTextRun(
                                    result.username ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SiteEmojiTextRun(
                                    '  #${source.postNumber}${result.createdAt == null ? '' : ' · ${_searchDate(result.createdAt!)}'}',
                                    style: TextStyle(
                                      color: tokens.mutedForeground,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                                siteUrl: controller.siteUrl!,
                                style: const TextStyle(
                                  fontSize: DiscourseTypography.control,
                                  height: 1.35,
                                ),
                              )
                            : _SearchHighlight(
                                siteUrl: controller.siteUrl!,
                                text: result.title,
                                query: controller.query,
                                style: const TextStyle(
                                  fontSize: DiscourseTypography.control,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      if (properties.contains(
                            GlobalSearchDisplayProperty.excerpt,
                          ) &&
                          result.excerpt.isNotEmpty)
                        DItemDescription(
                          maxLines: message ? 2 : 1,
                          child: _SearchHighlight(
                            siteUrl: controller.siteUrl!,
                            text: searchSnippet(
                              result.excerpt,
                              controller.query,
                            ),
                            query: controller.query,
                            style: TextStyle(
                              fontSize: DiscourseTypography.preview,
                              height: 1.35,
                              fontWeight: FontWeight.w400,
                              color: tokens.mutedForeground,
                            ),
                          ),
                        ),
                      if (!inTopic && metadata.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(
                              fontSize: DiscourseTypography.metadata,
                              height: 1.35,
                              color: tokens.mutedForeground,
                            ),
                            child: largeText
                                ? Wrap(
                                    spacing: 10,
                                    runSpacing: 3,
                                    children: metadata,
                                  )
                                : ClipRect(
                                    child: SizedBox(
                                      height:
                                          (MediaQuery.textScalerOf(
                                                    context,
                                                  ).scale(11.5) *
                                                  1.35)
                                              .ceilToDouble(),
                                      child: OverflowBox(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        minWidth: 0,
                                        maxWidth: double.infinity,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          spacing: 10,
                                          children: [
                                            for (
                                              var i = 0;
                                              i < metadata.length;
                                              i++
                                            ) ...[
                                              if (i > 0)
                                                ExcludeSemantics(
                                                  child: Text(
                                                    '·',
                                                    style: TextStyle(
                                                      color: tokens
                                                          .mutedForeground
                                                          .withValues(
                                                            alpha:
                                                                tokens
                                                                    .mutedForeground
                                                                    .a *
                                                                .5,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              metadata[i],
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (timeAside && result.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _searchDate(result.createdAt!),
                      style: TextStyle(
                        fontSize: DiscourseTypography.micro,
                        height: 1.35,
                        color: tokens.mutedForeground,
                      ),
                    ),
                  ),
              ],
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
      if (!controller.scope.isCore && controller.conditions.isEmpty)
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DButton(
            key: const ValueKey('global-search-remove-scope'),
            label: Text(
              controller.scope.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            icon: const DIcon(DIcons.xmark),
            iconPosition: DButtonIconPosition.end,
            tooltip: context.l10n.removeCondition(controller.scope.label),
            size: DControlStyle.isTouch(context)
                ? DButtonSize.filter
                : DButtonSize.chip,
            variant: DButtonVariant.secondary,
            onPressed: () {
              controller.setContext(null);
              controller.setScope(GlobalSearchScope.all);
              onRefocus?.call();
            },
          ),
        ),
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
    final size = DControlStyle.usesTouchGeometry(context)
        ? DButtonSize.filter
        : DButtonSize.chip;
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
      child: IntrinsicWidth(
        child: DButtonGroup(
          mainAxisSize: MainAxisSize.min,
          children: [
            DButtonGroupExpanded(
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
                size: size,
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
                size: size,
                variant: DButtonVariant.secondary,
                onPressed: onRemove,
              ),
          ],
        ),
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
    this.style,
  });
  final String siteUrl, text, query;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final words = searchWords(query).where((word) => word.length > 1).toList();
    if (words.isEmpty) {
      return SiteEmojiText.plain(text, siteUrl: siteUrl, style: style);
    }
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
            backgroundColor: DTokens.of(context).primary.withValues(alpha: .18),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      runs.add(SiteEmojiTextRun(text.substring(cursor)));
    }
    return SiteEmojiText(runs, siteUrl: siteUrl, style: style);
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
