import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../models/group_route.dart';
import '../models/search_results.dart';
import '../theme/d_icons.dart';
import 'content_navigation_controls.dart';
import 'global_search_controller.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'global_search_panel.dart';
import 'open_link.dart';
import 'search_presentation.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_search_controller.dart';
import 'site_url.dart';

/// Global search with one editor shared by the navbar and its open surface.
class ForumSearch extends StatefulWidget {
  const ForumSearch({
    super.key,
    this.dense = false,
    this.size = DControlSize.large,
    this.fullScreen = false,
    this.showNavigationControls = true,
  });

  final bool dense;
  final DControlSize size;
  final bool showNavigationControls;

  /// Mobile opens the editor and results on a dedicated navigation page.
  final bool fullScreen;
  static const Key inputKey = ValueKey('forum-search-input');
  static const Key panelKey = ValueKey('forum-search-panel');
  static const Key anchorKey = ValueKey('forum-search-anchor');

  @override
  State<ForumSearch> createState() => _ForumSearchState();
}

class _ForumSearchState extends State<ForumSearch> {
  final Object _field = Object();
  final _editorKey = GlobalKey(debugLabel: 'global-search-shared-editor');
  final _anchorKey = GlobalKey(debugLabel: 'global-search-anchor-footprint');
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'forum search');
  final _clearFocus = FocusNode(debugLabel: 'clear forum search');
  final _popover = DPopoverController();
  MaterialPageRoute<void>? _page;
  final _pageRevision = ValueNotifier(0);
  ShellController? _shell;
  String? _tabId;
  bool _scoped = false;

  ShellTabContext? get _document {
    final shell = _shell;
    if (shell == null) return null;
    return _scoped ? shell.tabContext(_tabId) : shell.focusedTabContext;
  }

  bool _ownsInput(ShellTabContext? tab) =>
      tab != null &&
      tab.isCurrent &&
      identical(tab.shell, _shell) &&
      tab.shell.activeTabId == tab.tabId;

  late ShellSearchController _search;
  late GlobalSearchController _global;
  VoidCallback? _unregisterFocus;
  SearchPresentation? _presentationOwner;
  SearchPresentation get _presentation => _presentationOwner!;
  bool get _open => _presentation.isOpen;
  bool _syncScheduled = false;
  bool _geometryScheduled = false;
  double _anchorHeight = DControlStyle.regularHeight;
  double _anchorLeft = 8;
  double _anchorTop = 6;
  double? _layoutWidth;
  Size? _layoutViewport;
  String? get _selectedResultId => _presentation.selectedResultId;
  final _panelKey = GlobalKey<GlobalSearchPanelState>();

  String get _listExpression {
    final shell = _shell;
    final tab = _document;
    final route = tab?.currentContent;
    if (shell == null || route == null) return '';
    return SearchPresentation.listExpression(
      route,
      shell.search.wordsFor(_search.siteUrl ?? '', tab?.tabId, route.id),
    );
  }

  GlobalSearchExpression get _closedExpression =>
      _presentation.closedExpression(_listExpression);

  bool get _surfaceOpen => widget.fullScreen ? _page != null : _popover.isOpen;

  List<GlobalSearchCondition> get _closedConditions => [
    ..._closedExpression.conditions,
    if (_closedExpression.order case final order? when order != 'relevance')
      GlobalSearchCondition(filterId: 'order', value: [order]),
  ];

  String get _query => (_open ? _global.query : _closedExpression.query);

  void _closeSearch() {
    if (widget.fullScreen) {
      final page = _page;
      if (page != null) {
        _presentation.beginLeaving(page);
        if (page.isCurrent) {
          page.navigator?.pop();
        } else {
          page.navigator?.removeRoute(page);
        }
      }
    } else {
      _popover.close();
    }
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.read(context);
    final tab = ForumTabScope.tabOf(context);
    _scoped = ForumTabScope.panelOf(context) != null;
    _tabId = tab.tabId;
    if (identical(shell, _shell)) return;
    _detach();
    _shell = shell;
    _search = shell.search;
    _global = shell.globalSearch;
    _presentationOwner ??= SearchPresentation(_global);
    _presentation.global = _global;
    _search.addListener(_searchChanged);
    _global.addListener(_globalChanged);
    shell.addListener(_siteChanged);
    _unregisterFocus = _search.registerFocus(_field, _requestShortcutFocus);
    // The shared editor can be mounted in a separate Navigator route, so its
    // listeners must not be notified while this subtree is rebuilding.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_shell, shell)) return;
      _syncSite();
      _syncText();
    });
  }

  void _detach() {
    if (_shell == null) return;
    _search.removeListener(_searchChanged);
    _global.removeListener(_globalChanged);
    _shell!.removeListener(_siteChanged);
    final unregister = _unregisterFocus;
    _unregisterFocus = null;
    if (unregister == null) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // Unregistering an active field closes its old search panel and notifies
      // the separately mounted route that still owns that controller.
      WidgetsBinding.instance.addPostFrameCallback((_) => unregister());
    } else {
      unregister();
    }
  }

  void _syncSite() {
    final shell = _shell!;
    final site = _search.siteUrl;
    final instance = site == null ? null : shell.instanceFor(site);
    _global.configure(
      siteUrl: site,
      capabilities: site == null
          ? const GlobalSearchCapabilities()
          : GlobalSearchCapabilities.fromSite(
              shell.siteConfigFor(site),
              instance?.user,
              contributions: shell.plugins.registry.searchContributions,
            ),
    );
  }

  void _siteChanged() {
    if (!mounted) return;
    _syncSite();
    _retireClosedDraftIfScopeChanged();
    _syncText();

    setState(() {});
  }

  void _retireClosedDraftIfScopeChanged() =>
      _presentation.retireClosedDraft(_listExpression);

  void _searchChanged() {
    if (!mounted) return;
    _syncSite();
    _retireClosedDraftIfScopeChanged();
    _syncText();
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final active = _search.panelOpen && _search.ownsPanel(_field);
      if (active) {
        _openSearch();
      } else if (_surfaceOpen) {
        _closeSearch();
      }
      setState(() {});
    });
  }

  void _selectResult(String? id) => _presentation.selectResult(id);

  void _globalChanged() {
    if (!mounted) return;
    _syncText();
    _presentation.reconcileSelection();
    setState(() {});
  }

  void _syncText() {
    if (_presentation.isLeaving) return;
    final query = _query;
    if (_text.text == query) return;
    _text.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _requestFocus() {
    if (!mounted) return;

    _search.activateField(_field);
    _openSearch();
    _requestEditorFocus();
  }

  void _requestShortcutFocus(SearchFocusRequest request) {
    if (!mounted) return;

    _search.activateField(_field);
    _openSearch(mode: request.mode, context: request.context);
    _requestEditorFocus();
  }

  void _requestEditorFocus() {
    if (widget.fullScreen &&
        (_page == null ||
            !_page!.isCurrent ||
            _page!.offstage ||
            _page!.animation?.status != AnimationStatus.completed)) {
      return;
    }
    _focus.requestFocus();
  }

  void _focusChanged() {
    if (_focus.hasFocus && !_presentation.suppressFocus && !_open) {
      _requestFocus();
    }
  }

  void _clearSubmittedSearch() => _presentation.clearSubmittedSearch();

  void _pageLeft({Object? surface}) {
    if (!_presentation.finishLeaving(surface: surface)) return;
    if (!mounted) return;
    _retireClosedDraftIfScopeChanged();
    _syncText();
  }

  void _openSearch({SearchFocusMode? mode, GlobalSearchContext? context}) {
    if (_presentation.isLeaving) _pageLeft();
    if (!_search.canSearch) return;
    if (!widget.fullScreen) _measureAnchor();
    if (!_surfaceOpen || mode != null) {
      _presentation.prepareOpening(
        source: _ForumSearchSource(this),
        mode: mode,
        context: context,
      );
    }
    if (!_surfaceOpen) {
      if (widget.fullScreen) {
        _openPage();
      } else {
        _popover.open(DPopoverInteraction.keyboard);
      }
    }
  }

  void _measureAnchor() {
    final box = _anchorKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (box is RenderBox && box.hasSize && overlay is RenderBox) {
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(overlay),
        Offset.zero & box.size,
      );
      _anchorHeight = box.size.height;
      _anchorLeft = rect.left;
      _anchorTop = rect.top;
    }
  }

  void _scheduleGeometry() {
    if (_geometryScheduled) return;
    _geometryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryScheduled = false;
      if (!mounted || !_open) return;
      setState(_measureAnchor);
    });
  }

  void _openChanged(bool open, DPopoverChangeReason reason) {
    if (!mounted) return;
    final editingValue = _text.value;
    setState(() => _presentation.surfaceChanged(open, editingValue));
    if (open) {
      _syncText();
      if (_presentation.restoredDraft case final draft?) {
        _text.value = draft;
      }
    }
    if (!open) {
      _search.closePanel();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (open && _presentation.restoredDraft != null) {
        _text.value = _presentation.restoredDraft!;
      }
      if (_text.text == editingValue.text) _text.value = editingValue;
      if (open) {
        _requestEditorFocus();
      } else {
        _focus.unfocus();
      }
      // Focus requests apply in a microtask. Keep restoration suppressed until
      // then, so Escape from a filter or scope button cannot reopen search.
      scheduleMicrotask(() => _presentation.suppressFocus = false);
    });
  }

  void _clear() {
    if (!_open) _requestFocus();
    _selectResult(null);
    _global.clearAllConditions();
    _setQuery('');
    _focus.requestFocus();
  }

  void _setQuery(String value) {
    _panelKey.currentState?.resetSelection();
    {
      _global.setQuery(value);
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_focus.hasFocus) return KeyEventResult.ignored;

    if (!_open) return KeyEventResult.ignored;
    final composing = _text.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        (keyboard.isShiftPressed &&
            event.logicalKey != LogicalKeyboardKey.tab)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_panelKey.currentState?.handleKey(
          key,
          reverse: keyboard.isShiftPressed,
        ) ==
        true) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace &&
        _global.stagedFilter != null &&
        _global.stagedTerm.isEmpty &&
        _text.selection.isCollapsed &&
        _text.selection.extentOffset == _text.text.length) {
      _setQuery(_global.wordsQuery);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace &&
        _text.text.isEmpty &&
        _global.conditions.isNotEmpty) {
      final index = _global.conditions.length - 1;
      final condition = _global.conditions[index];
      final filter = globalSearchFilter(
        condition.filterId,
        _global.capabilities,
      );
      if (filter != null) {
        _global.removeCondition(index);
        _global.setQuery('${filter.id}:');
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final rows = _global.results;
      if (rows.isEmpty) return KeyEventResult.ignored;
      final current = rows.indexWhere((row) => row.id == _selectedResultId);
      final down = key == LogicalKeyboardKey.arrowDown;
      final next = current < 0
          ? (down ? 0 : rows.length - 1)
          : (current + (down ? 1 : -1) + rows.length) % rows.length;
      setState(() => _selectResult(rows[next].id));
      _pageRevision.value++;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final selected = _global.results
          .where((row) => row.id == _selectedResultId)
          .firstOrNull;
      if (selected != null) {
        unawaited(_openResult(selected));
      } else {
        _apply();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openResult(GlobalSearchResult result) async {
    final shell = _shell!;
    final owner = _document;
    if (!_ownsInput(owner)) return;
    final site = _global.siteUrl;
    if (site == null) return;
    final activation = SearchResultActivation(
      host: shell,
      lease: shell.lifecycle.capture(site),
      site: site,
      sourceRoute: owner!.currentContent,
      words: _global.wordsQuery,
      result: result,
    );
    unawaited(_global.recordSelection(result));
    final page = _page;
    _closeSearch();
    if (page != null) await page.completed;
    if (!mounted ||
        !activation.canNavigate(
          currentHost: _shell,
          contextHost: ShellScope.maybeRead(context),
          sourceOwnsInput: _ownsInput(owner),
          currentRoute: owner.currentContent,
          searchSite: _global.siteUrl,
          activeSite: shell.currentInstance?.url,
        )) {
      return;
    }
    _global.setQuery('');
    _global.clearAllConditions();
    if (result.source case final SearchPostHit hit) {
      shell.openSearchResult(hit, words: activation.words);
    } else {
      final previousRoute = owner.currentContent;
      ({ShellTabContext owner, ForumTab tab})? destination;
      await openLink(
        context,
        resolveSiteRootPath(site, result.path),
        title: result.title,
        siteUrl: site,
        onNavigated: () {
          final opened = shell.focusedTabContext;
          final tab = opened.tab;
          if (tab != null && opened.siteUrl == site) {
            destination = (owner: opened, tab: tab);
          }
        },
      );
      final opened = destination;
      if (!mounted || opened == null) return;
      final route = opened.tab.currentContent;
      final words = activation.wordsForDestination(
        ownsInput: _ownsInput(opened.owner),
        capturedTab: opened.tab,
        currentTab: opened.owner.tab,
        route: route,
        previousRoute: previousRoute,
      );
      if (words != null) {
        shell.search.setPageWords(site, opened.owner.tabId, route.id, words);
      }
    }
  }

  void _apply() {
    if (!_ownsInput(_document)) return;
    _global.submit();
    if (_global.phase == GlobalSearchPhase.failed) return;
    final words = _global.wordsQuery.trim();
    final conditions = [
      ..._global.conditions,
      if (_global.hasOrderFilter)
        GlobalSearchCondition(filterId: 'order', value: [_global.order]),
    ];
    _global.rememberSearch();
    _closeSearch();
    _shell!.applySearchToList(
      words,
      conditions,
      clearFilters: words.isEmpty && conditions.isEmpty,
    );
    _clearSubmittedSearch();
  }

  void _openSection(GlobalSearchSection section) {
    final shell = _shell!;
    final owner = _document;
    if (!_ownsInput(owner)) return;
    final site = _global.siteUrl;
    if (site == null) return;
    if (section.scope == GlobalSearchScope.users &&
            !_global.capabilities.userDirectory ||
        section.scope == GlobalSearchScope.groups &&
            !_global.capabilities.groupDirectory) {
      _global.rememberSearch();
      _global.setScope(section.scope);
      return;
    }
    if (section.topicId != null && section.results.isNotEmpty) {
      unawaited(_openResult(section.results.first));
      return;
    }
    if (section.scope == GlobalSearchScope.forum) {
      _apply();
      return;
    }
    final words = _global.wordsQuery.trim();
    _global.rememberSearch();
    _closeSearch();
    final route = section.scope == GlobalSearchScope.messages
        ? ContentRoute.searchList(
            '$words in:personal',
            messageMode: MessageListMode.inbox,
          )
        : section.scope == GlobalSearchScope.categories
        ? ContentRoute.allCategories()
        : section.scope == GlobalSearchScope.tags
        ? ContentRoute(
            destination: const PageDestination(CorePage.tags),
            title: appL10n.tags,
            icon: DIcons.tag,
          )
        : section.scope == GlobalSearchScope.users
        ? ContentRoute(
            destination: const PageDestination(CorePage.users),
            title: appL10n.users,
            icon: DIcons.users,
          )
        : section.scope == GlobalSearchScope.groups
        ? ContentRoute.group(const GroupRoute.directory())
        : ContentRoute(
            destination: ExtensionDestination('${section.scope.owner}-search'),
            title: section.scope.label,
            icon: DIcons.magnifyingGlass,
          );
    shell.pushContent(route);
    shell.search.setPageWords(site, shell.activeTabId, route.id, words);
    if (route.isMessages) unawaited(shell.loadFeed(route.id));
    if (route.isUsers) unawaited(shell.focusedTabContext.loadUsers());
    _clearSubmittedSearch();
  }

  Widget _editor(double width, {required bool expanded}) {
    final hasConditions = expanded
        ? _global.conditions.isNotEmpty ||
              _global.hasOrderFilter ||
              !_global.scope.isCore
        : _closedConditions.isNotEmpty;
    return Focus(
      key: _editorKey,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: DInputGroup(
        size: widget.size,
        variant: DInputGroupVariant.search,
        borderless: expanded,
        children: [
          DInputGroupInput(
            key: ForumSearch.inputKey,
            controller: _text,
            focusNode: _focus,
            semanticLabel: appL10n.searchThisForum,
            hintText: hasConditions
                ? appL10n.addWordsOrFilters
                : appL10n.searchThisForum,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onTap: _requestFocus,
            onChanged: (value) {
              _selectResult(null);
              _setQuery(value);
            },
            onSubmitted: (_) {
              _apply();
            },
          ),
          if (width >= 140)
            const DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineStart,
              child: DIcon(DIcons.magnifyingGlass, size: 16),
            ),
          if (hasConditions)
            DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineStart,
              child: LayoutBuilder(
                builder: (context, constraints) => DScrollArea(
                  axes: DScrollAxes.horizontal,
                  showScrollbar: false,
                  child: expanded
                      ? GlobalSearchChips(
                          controller: _global,
                          maxWidth: constraints.maxWidth,
                          onRefocus: _focus.requestFocus,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 4,
                          children: [
                            for (final condition in _closedConditions)
                              SearchFilterChip(
                                controller: _global,
                                condition: condition,
                                maxWidth: constraints.maxWidth,
                                onEdit: () {
                                  _requestFocus();
                                  _global.beginFilter(
                                    globalSearchFilter(
                                      condition.filterId,
                                      _global.capabilities,
                                    )!,
                                  );
                                  _focus.requestFocus();
                                },
                                onRemove: () {
                                  _requestFocus();
                                  final index = _global.conditions.indexWhere(
                                    (item) =>
                                        item.filterId == condition.filterId,
                                  );
                                  _global.removeCondition(index);
                                  _focus.requestFocus();
                                },
                              ),
                          ],
                        ),
                ),
              ),
            ),
          DInputGroupAddon(
            alignment: DInputGroupAddonAlignment.inlineEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_query.isNotEmpty || hasConditions)
                  DInputGroupButton.icon(
                    key: const ValueKey('forum-search-clear'),
                    focusNode: _clearFocus,
                    icon: const DIcon(DIcons.xmark, size: 12),
                    tooltip: appL10n.clearSearch,
                    onPressed: _clear,
                  )
                else if (!DControlStyle.isTouch(context) &&
                    !widget.fullScreen &&
                    width >=
                        280 * MediaQuery.textScalerOf(context).scale(14) / 14)
                  DShortcutKeycaps(
                    shortcut: DShortcut(
                      searchShortcutForPlatform(defaultTargetPlatform),
                    ),
                    listenToKeyboard: false,
                    compact: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_search.canSearch) return const SizedBox.shrink();
    if (widget.fullScreen) return _buildPageTrigger();
    final platform = Theme.of(context).platform;
    final mobile =
        (platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android) &&
        MediaQuery.sizeOf(context).width < 768;
    final field = LayoutBuilder(
      builder: (context, constraints) {
        final anchorWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 420.0;
        final viewport = MediaQuery.sizeOf(context);
        final safe = MediaQuery.paddingOf(context);
        if (_open &&
            (_layoutWidth != anchorWidth || _layoutViewport != viewport)) {
          _scheduleGeometry();
        }
        _layoutWidth = anchorWidth;
        _layoutViewport = viewport;
        final width = mobile
            ? viewport.width
            : math.min(
                math.max(374.0, anchorWidth),
                viewport.width - safe.horizontal - 8,
              );
        final surfaceLeft = _anchorLeft
            .clamp(
              safe.left + 4,
              math.max(safe.left + 4, viewport.width - safe.right - width - 4),
            )
            .toDouble();
        final editorLeft = math.max(0.0, _anchorLeft - surfaceLeft);
        final surfaceTop = math.max(safe.top + 2, _anchorTop - 5);
        final height = mobile
            ? math.max(
                160.0,
                viewport.height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    MediaQuery.paddingOf(context).vertical -
                    8,
              )
            : math.min(
                654.0,
                math.max(
                  100.0,
                  viewport.height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      MediaQuery.paddingOf(context).bottom -
                      surfaceTop -
                      8,
                ),
              );
        return DPopover(
          controller: _popover,
          restoreFocus: false,
          focusContentOnOpen: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          onOpenChange: _openChanged,
          content: DPopoverContent(
            key: ForumSearch.panelKey,
            semanticLabel: context.l10n.globalSearch,
            width: width,
            constraints: BoxConstraints(maxHeight: height),
            padding: EdgeInsets.zero,
            scrollable: false,
            cornerRadius: DRadius.panel,
            collisionPadding: mobile ? 4 : 0,
            sideCollision: DPopoverCollision.shift,
            alignCollision: DPopoverCollision.shift,
            placementResolver: (placement) => mobile
                ? placement.boundary.topLeft
                : Offset(surfaceLeft, surfaceTop),
            child: SizedBox(
              height: height,
              child: Column(
                children: [
                  Transform.translate(
                    offset: mobile
                        ? Offset.zero
                        : Offset(0, math.min(0, _anchorTop - surfaceTop)),
                    child: Padding(
                      padding: mobile
                          ? const EdgeInsets.symmetric(vertical: 8)
                          : EdgeInsets.fromLTRB(
                              editorLeft,
                              math.max(0, _anchorTop - surfaceTop),
                              math.max(0.0, width - editorLeft - anchorWidth),
                              5,
                            ),
                      child: Row(
                        children: [
                          if (mobile)
                            DButton.iconOnly(
                              key: const ValueKey('global-search-back'),
                              icon: const DIcon(DIcons.arrowLeft),
                              tooltip: context.l10n.back,
                              variant: DButtonVariant.ghost,
                              onPressed: _popover.close,
                            ),
                          Expanded(
                            child: _open
                                ? _editor(
                                    mobile ? width - 32 : anchorWidth,
                                    expanded: true,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const DSeparator(),
                  Expanded(
                    child: GlobalSearchPanel(
                      key: _panelKey,
                      showConditions: false,
                      showClearFilters:
                          _listExpression.isNotEmpty &&
                          _global.wordsQuery.isEmpty &&
                          _global.conditions.isEmpty,
                      controller: _global,
                      onApply: _apply,
                      onOpenSection: _openSection,
                      onRefocus: _focus.requestFocus,
                      selectedResultId: _selectedResultId,
                      onSelect: (id) => setState(() => _selectResult(id)),
                      onOpen: _openResult,
                    ),
                  ),
                  if (!DControlStyle.isTouch(context)) ...[
                    const DSeparator(),
                    Padding(
                      key: const ValueKey('global-search-footer'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DTokens.of(context).mutedForeground,
                        ),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [Text(context.l10n.searchNavigationHelp)],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          child: DPopoverAnchor(
            child: SizedBox(
              key: _anchorKey,
              width: anchorWidth,
              child: _open
                  ? SizedBox(key: ForumSearch.anchorKey, height: _anchorHeight)
                  : _editor(anchorWidth, expanded: false),
            ),
          ),
        );
      },
    );
    if (mobile) {
      return PopScope(
        canPop: !_open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _open) _popover.close();
        },
        child: field,
      );
    }
    if (!ContentNavigationControls.isSupported ||
        !widget.showNavigationControls) {
      return field;
    }
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          // Count capsules need their own width. Keep the search editor and
          // its keyboard shortcut available when title-bar space is tight.
          if (!widget.dense ||
              constraints.maxWidth >=
                  180 * MediaQuery.textScalerOf(context).scale(14) / 14) ...[
            const ContentNavigationControls(),
            const SizedBox(width: 4),
          ],
          Expanded(child: field),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _detach();
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _clearFocus.dispose();
    _text.dispose();
    _popover.dispose();
    _pageRevision.dispose();
    super.dispose();
  }

  Widget _buildPageTrigger() => DButton.iconOnly(
    key: const ValueKey('mobile-search-button'),
    icon: const DIcon(DIcons.magnifyingGlass, size: 20),
    tooltip: appL10n.search,
    variant: DButtonVariant.ghost,
    onPressed: _requestFocus,
  );

  void _openPage() {
    final content = ListenableBuilder(
      listenable: Listenable.merge([_global, _pageRevision]),
      builder: (context, _) => Column(
        key: ForumSearch.panelKey,
        children: [
          Padding(
            padding: const EdgeInsets.all(DSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        _editor(constraints.maxWidth, expanded: true),
                  ),
                ),
                DButton(
                  key: const ValueKey('mobile-search-back'),
                  label: Text(appL10n.cancel),
                  variant: DButtonVariant.ghost,
                  onPressed: _closeSearch,
                ),
              ],
            ),
          ),
          const DSeparator(),
          Expanded(
            child: GlobalSearchPanel(
              key: _panelKey,
              showConditions: false,
              showClearFilters:
                  _listExpression.isNotEmpty &&
                  _global.wordsQuery.isEmpty &&
                  _global.conditions.isEmpty,
              controller: _global,
              onApply: _apply,
              onOpenSection: _openSection,
              onRefocus: _focus.requestFocus,
              selectedResultId: _selectedResultId,
              onSelect: (id) {
                _selectResult(id);
                _pageRevision.value++;
              },
              onOpen: _openResult,
            ),
          ),
        ],
      ),
    );
    final page = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/search'),
      builder: (_) => InheritedTheme.captureAll(
        context,
        ShellScope(
          controller: _shell!,
          // Keep the search subtree stable as the keyboard animates its insets.
          // Its LayoutBuilder still responds to the changing available height.
          child: Builder(
            builder: (context) => Material(
              color: DTokens.of(context).background,
              child: SafeArea(
                child: Builder(
                  builder: (context) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _page = page;
    _openChanged(true, DPopoverChangeReason.imperative);
    final popped = Navigator.of(context).push(page);
    final animation = page.animation!;
    void focusAfterTransition(AnimationStatus status) {
      if (status != AnimationStatus.completed || page.offstage) return;
      animation.removeStatusListener(focusAfterTransition);
      if (!mounted || _page != page || !_search.ownsPanel(_field)) return;
      // Keep keyboard resizing and editor focus work out of the page slide.
      _requestEditorFocus();
    }

    animation.addStatusListener(focusAfterTransition);
    // A zero-duration transition may already have completed during push.
    focusAfterTransition(animation.status);
    unawaited(
      popped.then((_) {
        animation.removeStatusListener(focusAfterTransition);
        if (!mounted || _page != page) return;
        _page = null;
        _presentation.beginLeaving(page);
        _openChanged(false, DPopoverChangeReason.imperative);
      }),
    );
    unawaited(
      page.completed.then((_) {
        _pageLeft(surface: page);
      }),
    );
  }
}

final class _ForumSearchSource implements SearchPresentationSource {
  _ForumSearchSource(this.state);
  final _ForumSearchState state;

  @override
  String get expression => state._listExpression;

  @override
  ContentRoute? get route => state._document?.currentContent;

  @override
  GlobalSearchContext? get pluginContext =>
      state._shell!.plugins.registry.contentSearchContext(state.context);
}
