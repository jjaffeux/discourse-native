import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import '../foundation/icons/d_icons.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../models/group_route.dart';
import '../models/search_results.dart';
import '../models/topic_filter.dart';
import '../plugin_api/global_search_filters.dart';
import '../plugin_api/global_search_models.dart';
import '../theme/discourse_typography.dart';
import 'content_navigation_controls.dart';
import 'forum_tab_scope.dart';
import 'global_search_api.dart';
import 'global_search_controller.dart';
import 'global_search_panel.dart';
import 'open_link.dart';
import 'search_presentation.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_search_controller.dart';
import 'site_url.dart';
import 'topic_filter_controller.dart';
import 'topic_filter_input.dart';
import 'topic_filter_scope.dart';

/// Global search with one editor shared by the navbar and its open surface.
typedef _FieldLayout = ({
  double? openWidth,
  bool showsInlineConditions,
  bool showsShortcut,
});

/// The shell state that [_ForumSearchState.build] draws.
typedef _ShellReads = ({bool canSearch, bool open, String listExpression});

/// What the field draws from the search controller outside its chips, which
/// listen for themselves.
typedef _GlobalReads = ({
  bool hasConditions,
  bool hasOrderFilter,
  GlobalSearchScope scope,
  int configurationRevision,
  bool hasQuery,
  bool hasWords,
  String? selectedResultId,
  bool browsingCategories,
});

class ForumSearch extends StatefulWidget {
  const ForumSearch({
    super.key,
    this.dense = false,
    this.size = DControlSize.large,
    this.fullScreen = false,
    this.showNavigationControls = true,
  }) : _pageContent = false;

  const ForumSearch.page({super.key})
    : dense = false,
      size = DControlSize.large,
      fullScreen = true,
      showNavigationControls = false,
      _pageContent = true;

  final bool _pageContent;
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
  final _showFeedPicker = ValueNotifier(false);
  ShellController? _shell;
  String? _tabId;
  bool _scoped = false;
  _ShellReads? _builtReads;
  _GlobalReads? _builtGlobalReads;

  ShellTabContext? get _document {
    final shell = _shell;
    if (shell == null) return null;
    return _scoped ? shell.tabContext(_tabId) : shell.focusedTabContext;
  }

  ContentRoute? get _sourceRoute =>
      _scoped ? _document?.currentContent : _shell?.currentContent;

  bool _ownsInput(ShellTabContext? tab) =>
      tab != null &&
      tab.isCurrent &&
      identical(tab.shell, _shell) &&
      tab.shell.activeTabId == tab.tabId;

  bool _ownsSearchAction(
    ShellController shell,
    ShellTabContext owner,
    String site,
    ContentRoute? sourceRoute, {
    bool requireSourceRoute = true,
  }) =>
      mounted &&
      owner.lease?.isCurrent == true &&
      owner.accountIdentity == shell.currentAccountIdentity &&
      (!requireSourceRoute || _ownsInput(owner)) &&
      identical(shell, _shell) &&
      identical(shell, ShellScope.maybeRead(context)) &&
      _global.siteUrl == site &&
      shell.currentInstance?.url == site &&
      (!requireSourceRoute ||
          sourceRoute?.sameDestinationAs(owner.currentContent) == true);

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
  List<TopicFilterOption> _feedOptions = const [];
  final _feedClauses = <String>[];
  List<TopicFilterSuggestion> _feedChoices = const [];
  String? _feedMenuField;
  Timer? _feedLookup;
  int _feedRevision = 0;
  int _feedChoiceRevision = 0;
  String? _feedSourceWords;
  String? _publishedFeedExpression;
  bool _editedFeedSource = false;
  bool _loadingFeedDraft = false;

  ({ShellTabContext owner, String site, String words, String filters})?
  _filterVisit;

  void _openFeedPicker() {
    final owner = _document;
    final site = owner?.siteUrl;
    if (!_usesFeedFilters ||
        owner == null ||
        site == null ||
        !_ownsInput(owner)) {
      return;
    }
    _focus.unfocus();
    _filterVisit = (
      owner: owner,
      site: site,
      words: _global.query,
      filters: _feedFilterExpression(words: ''),
    );
    _showFeedPicker.value = true;
    _pageRevision.value++;
  }

  void _closeFeedPicker() {
    _filterVisit = null;
    _showFeedPicker.value = false;
    _pageRevision.value++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _surfaceOpen) _requestEditorFocus();
    });
  }

  void _acceptFeedPicker(
    ({ShellTabContext owner, String site, String words, String filters}) visit,
    String query,
  ) {
    if (!identical(_filterVisit, visit) ||
        !_surfaceOpen ||
        !_ownsInput(visit.owner)) {
      return;
    }
    final clauses = splitTopicFilterQuery(query).where((token) {
      final key = topicFilterClauseKey(token);
      return key != null && key != token;
    }).toList();
    if (clauses.join(' ') == _feedFilterExpression(words: '')) return;
    _loadingFeedDraft = true;
    _global.setScope(GlobalSearchScope.forum);
    _global.clearConditions();
    if (_global.hasOrderFilter) _global.setOrder('relevance');
    _feedClauses
      ..clear()
      ..addAll(clauses);
    _global.setQuery(visit.words);
    _global.setTopicFilterClauses(clauses.isEmpty ? null : clauses.join(' '));
    _pageRevision.value++;
    _loadingFeedDraft = false;
    _syncFeedSourceFilters();
  }

  Widget _buildFeedPicker(BuildContext context) {
    final visit = _filterVisit!;
    final shell = _shell!;
    final categories = shell.filterCategoriesFor(visit.site);
    final scope = parseTopicFilterScope(
      visit.filters.replaceAll('=category:', 'category:'),
      categories,
    );
    return DReferenceTextScale(
      child: DMenuContentScale(
        child: TopicFilterInput(
          siteUrl: visit.site,
          initialQuery: visit.filters,
          categories: categories,
          categoryContextId: scope.categoryId,
          options: _feedOptions,
          tokenized: true,
          embedded: true,
          focusOnOpen: false,
          hintText: context.l10n.addAFilter,
          padding: EdgeInsets.zero,
          returnToSearch: _closeFeedPicker,
          onScopeChanged: (query) => _acceptFeedPicker(visit, query),
          onSubmitted: (query) async {
            _acceptFeedPicker(visit, query);
            if (identical(_filterVisit, visit)) _closeFeedPicker();
          },
        ),
      ),
    );
  }

  ContentRoute? get _filterFeed {
    final route = _document?.contentStack.reversed
        .where((route) => !route.isGlobalSearch)
        .firstOrNull;
    return route?.isTopicList == true && route?.isMessages != true
        ? route
        : null;
  }

  bool get _usesFeedFilters =>
      widget.fullScreen &&
      DControlStyle.isTouch(context) &&
      _filterFeed != null;

  bool get _showsFeedFilters =>
      _usesFeedFilters &&
      (_global.scope == GlobalSearchScope.all ||
          _global.scope == GlobalSearchScope.forum);

  TopicFilterOption? _feedOption(String token) {
    if (token.contains('://')) return null;
    final key = topicFilterClauseKey(
      token,
    )?.replaceFirst(RegExp(r'^[-=]+'), '').toLowerCase();
    if (key == null) return null;
    return _feedOptions
        .where((option) => option.name == key || option.alias == key)
        .firstOrNull;
  }

  void _loadFeedOptions() {
    if (!_usesFeedFilters) return;
    final shell = _shell!;
    final owner = _document;
    final site = owner?.siteUrl;
    if (site == null || !_ownsInput(owner)) return;
    final revision = ++_feedRevision;
    final route = _filterFeed!;
    final seed = splitTopicFilterQuery(route.topicFilterQuery);
    _editedFeedSource = route.isAdvancedTopicFilter;
    _feedSourceWords = [
      for (final token in seed)
        if (topicFilterClauseKey(token) == null) token,
      if (!route.isSearchList && route.topicListSearch.isNotEmpty)
        route.topicListSearch,
    ].join(' ');
    _feedOptions = [
      for (final token in seed)
        if (topicFilterClauseKey(token) case final key?)
          TopicFilterOption(name: key.replaceFirst(RegExp(r'^[-=]+'), '')),
    ];
    _feedClauses.clear();
    final retained = splitTopicFilterQuery(_global.query).toSet();
    for (final token in seed) {
      final key = topicFilterClauseKey(token);
      if (key != null && key != token && !retained.contains(token)) {
        final parsed = _presentation.closedExpression(token);
        if (parsed.conditions.isEmpty && parsed.order == null) {
          _feedClauses.add(token);
        }
      }
    }
    _loadingFeedDraft = true;
    _setQuery(_global.query);
    _publishedFeedExpression = _feedFilterExpression(words: _feedSourceWords!);
    _loadingFeedDraft = false;
    unawaited(
      shell.topicFilterLookups.loadOptions(site).then((options) {
        if (!mounted ||
            !_open ||
            revision != _feedRevision ||
            !_ownsInput(owner)) {
          return;
        }
        final names = {for (final option in options) option.name};
        _feedOptions = [
          ...options,
          for (final option in _feedOptions)
            if (!names.contains(option.name)) option,
        ];
        _loadingFeedDraft = true;
        _setQuery(_global.query);
        _loadingFeedDraft = false;
        _pageRevision.value++;
      }),
    );
  }

  void _suggestFeedFilters(String query) {
    final revision = ++_feedChoiceRevision;
    _feedLookup?.cancel();
    _feedChoices = const [];
    if (!_showsFeedFilters ||
        _feedOptions.isEmpty ||
        topicFilterQueryEndsWithSeparator(query)) {
      return;
    }
    final tail = splitTopicFilterQuery(query).lastOrNull ?? '';
    final typedKey = topicFilterClauseKey(tail);
    final menuFields = topicFilterMenuFields(_feedOptions);
    final field = menuFields
        .where(
          (field) =>
              _feedMenuField == field.id && field.keys.contains(typedKey),
        )
        .firstOrNull;
    final named = typedKey == null
        ? menuFields
              .where(
                (field) =>
                    field.label.toLowerCase().startsWith(tail.toLowerCase()),
              )
              .toList()
        : const <TopicFilterMenuField>[];

    if (tail.length < 2 || _global.stagedFilter != null && field == null) {
      return;
    }
    if (named.isNotEmpty) {
      _feedChoices = [
        for (final field in named)
          TopicFilterSuggestion(
            name: field.draft,
            displayName: field.label,
            description: field.hint,
            menuField: field.id,
            menuIcon: field.icon,
          ),
      ];
      _pageRevision.value++;
      return;
    }
    final key = topicFilterClauseKey(tail);
    final prefix = tail.toLowerCase().replaceFirst(RegExp(r'^[-=]+'), '');
    if (key == null
        ? !_feedOptions.any(
            (option) =>
                option.name.startsWith(prefix) ||
                option.alias?.startsWith(prefix) == true,
          )
        : _feedOption(tail) == null) {
      return;
    }
    final shell = _shell!;
    final owner = _document;
    final site = owner?.siteUrl;
    if (site == null || !_ownsInput(owner)) return;
    final engine = TopicFilterSuggestions(
      allOptions: field != null,
      menuField: field?.id,
      options: _feedOptions,
      categories: shell.filterCategoriesFor(site),
      categoryLookup: (term) =>
          shell.searchFilterCategories(siteUrl: site, term: term),
      tags: (term) => shell.searchFilterTags(siteUrl: site, term: term),
      tagGroups: (term) =>
          shell.topicFilterLookups.searchTagGroups(siteUrl: site, term: term),
      users: (term) =>
          shell.topicFilterLookups.searchUsers(siteUrl: site, term: term),
      groups: (term) =>
          shell.topicFilterLookups.searchGroups(siteUrl: site, term: term),
    );
    _feedLookup = Timer(const Duration(milliseconds: 150), () async {
      final choices = await engine.suggestions(tail);
      if (!mounted ||
          !_open ||
          revision != _feedChoiceRevision ||
          _global.query != query ||
          !_showsFeedFilters ||
          !_ownsInput(owner)) {
        return;
      }
      _feedChoices = key != null
          ? choices
          : choices.where((choice) {
              final name = choice.name.toLowerCase().replaceFirst(
                RegExp(r'^[-=]+'),
                '',
              );
              return name.startsWith(prefix) ||
                  _feedOption(choice.name)?.alias?.startsWith(prefix) == true;
            }).toList();
      _pageRevision.value++;
    });
  }

  void _pickFeedFilter(TopicFilterSuggestion choice) {
    final token = choice.name;
    _feedMenuField = choice.menuField ?? _feedMenuField;
    if (choice.replaceKeys.isNotEmpty) {
      _feedClauses.removeWhere(
        (clause) => choice.replaceKeys.contains(topicFilterClauseKey(clause)),
      );
    }
    final query = _text.text;
    final tail = splitTopicFilterQuery(query).lastOrNull;
    final prefix = tail == null || topicFilterQueryEndsWithSeparator(query)
        ? query
        : query.substring(0, query.lastIndexOf(tail));
    _setQuery('$prefix$token${token.endsWith(':') ? '' : ' '}');
    _focus.requestFocus();
  }

  List<Widget> _feedFilterChips(BuildContext context) => [
    for (final clause in _feedClauses)
      if (topicFilterClauseKey(clause) case final key?)
        DFilterToken(
          label: key.substring(0, key.length - 1),
          value: clause.substring(key.length),
          editLabel: context.l10n.editCondition(clause),
          removeLabel: context.l10n.removeCondition(clause),
          editKey: ValueKey('search-edit-feed-clause:$clause'),
          removeKey: ValueKey('search-remove-feed-clause:$clause'),
          onEdited: () {
            _feedClauses.remove(clause);
            _pageRevision.value++;
            final words = _global.query.trimRight();
            _setQuery([if (words.isNotEmpty) words, clause].join(' '));
            _focus.requestFocus();
          },
          onRemoved: () {
            _feedClauses.remove(clause);
            _pageRevision.value++;
            _setQuery(_global.query);
            _focus.requestFocus();
          },
        ),
  ];

  String get _listExpression {
    final shell = _shell;
    final tab = _document;
    final route = _sourceRoute;
    if (shell == null || route == null) return '';
    return SearchPresentation.listExpression(
      route,
      shell.search.wordsFor(_search.siteUrl ?? '', tab?.tabId, route.id),
    );
  }

  int get _listFilterCount {
    final route = _sourceRoute;
    if (route == null || route.isMessages || !route.isTopicList) return 0;
    final extra = splitTopicFilterQuery(_listExpression).where((clause) {
      final key = topicFilterClauseKey(clause)?.toLowerCase();
      if (key == null || key == 'category:') return false;
      if (key != 'tags:' && key != 'tag:') return true;
      final value = clause.substring(key.length);
      return value.contains(RegExp(r'[+,]'));
    });
    return topicFilterMenuCount(extra.join(' '));
  }

  GlobalSearchExpression get _closedExpression =>
      _presentation.closedExpression(_listExpression);

  _ShellReads get _shellReads => (
    canSearch: _search.canSearch,
    open: _open,
    listExpression: _listExpression,
  );

  _GlobalReads get _globalReads => (
    hasConditions: _global.conditions.isNotEmpty,
    hasOrderFilter: _global.hasOrderFilter,
    scope: _global.scope,
    configurationRevision: _global.configurationRevision,
    hasQuery: _query.isNotEmpty,
    hasWords: _global.wordsQuery.isNotEmpty,
    selectedResultId: _selectedResultId,
    browsingCategories:
        _global.stagedFilter?.id == 'category' && _global.stagedTerm.isEmpty,
  );

  bool get _shellPage => widget.fullScreen && _shell!.mobileNavigationEnabled;

  bool get _surfaceOpen => widget._pageContent
      ? _sourceRoute?.isGlobalSearch == true
      : widget.fullScreen
      ? _page != null
      : _popover.isOpen;

  List<GlobalSearchCondition> get _closedConditions => [
    ..._closedExpression.conditions,
    if (_closedExpression.order case final order? when order != 'relevance')
      GlobalSearchCondition(filterId: 'order', value: [order]),
  ];

  String get _query => (_open ? _global.query : _closedExpression.query);

  void _closeSearch() {
    if (widget._pageContent) {
      if (_sourceRoute?.isGlobalSearch == true) {
        _openChanged(false, DPopoverChangeReason.imperative);
        _shell!.handleBack();
      }
      return;
    }
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
    final tab = ShellScope.tabOf(context);
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
      if (widget._pageContent) {
        _search.activateField(_field);
        _openChanged(true, DPopoverChangeReason.imperative);
        _requestEditorFocus();
      }
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
    // A closed field parses its list's expression, which may name a filter
    // only discovery can enable.
    if (_open || _listExpression.isNotEmpty) {
      _global.ensureCapabilities(retryUnanswered: false);
    }
  }

  void _siteChanged() {
    if (!mounted) return;
    _syncSite();
    if (_shellPage &&
        !widget._pageContent &&
        _open &&
        (_sourceRoute == null ||
            !_shell!.focusedTabContext.contentStack.any(
              (route) => route.isGlobalSearch,
            ))) {
      _presentation.surfaceChanged(false, _text.value);
    }
    if (widget._pageContent &&
        _sourceRoute?.isGlobalSearch == true &&
        !_search.ownsPanel(_field)) {
      _search.activateField(_field);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sourceRoute?.isGlobalSearch == true) {
          _requestEditorFocus();
        }
      });
    }
    _retireClosedDraftIfScopeChanged();
    _syncText();

    if (widget._pageContent && !_surfaceOpen) return;
    // Most notifications concern other state; capabilities and the query reach
    // this field through the search controller's own listener.
    if (_shellReads != _builtReads) setState(() {});
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
      if (_shellPage && !widget._pageContent) {
        setState(() {});
        return;
      }
      final active = _search.panelOpen && _search.ownsPanel(_field);
      if (active && !widget._pageContent) {
        _openSearch();
      } else if (!active && _surfaceOpen) {
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
    if (_open &&
        _showsFeedFilters &&
        !_loadingFeedDraft &&
        _feedSourceWords != null) {
      _syncFeedSourceFilters();
    }
    // Every keystroke and result delivery notifies; the panel and the chips
    // listen for themselves, so the field redraws only for its own reads.
    if (_globalReads == _builtGlobalReads) return;
    _pageRevision.value++;
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
    if (_filterVisit != null) return;
    if (widget._pageContent && !_focus.canRequestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sourceRoute?.isGlobalSearch == true) {
          _focus.requestFocus();
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    if (widget.fullScreen &&
        !widget._pageContent &&
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
    if (_shellPage) {
      if (_sourceRoute?.isGlobalSearch == true) {
        if (widget._pageContent && mode != null) {
          _presentation.prepareOpening(
            source: _ForumSearchSource(this),
            mode: mode,
            context: context,
          );
        }
        return;
      }
      _presentation.prepareOpening(
        source: _ForumSearchSource(this),
        mode: mode,
        context: context,
      );
      _presentation.surfaceChanged(true, _text.value);
      _focus.unfocus();
      _shell!.pushContent(ContentRoute.search());
      return;
    }
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
      _global.ensureCapabilities();
      _loadFeedOptions();
      _syncText();
      if (_presentation.restoredDraft case final draft?) {
        _text.value = draft;
      }
    }
    if (!open) {
      _filterVisit = null;
      _showFeedPicker.value = false;
      _feedLookup?.cancel();
      _feedChoiceRevision++;
      _feedChoices = const [];
      _feedMenuField = null;
      _feedSourceWords = null;
      _global.setTopicFilterClauses(null);
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
    if (_feedClauses.isNotEmpty) _pageRevision.value++;
    _feedClauses.clear();
    _setQuery('');
    _focus.requestFocus();
  }

  void _setQuery(String value) {
    _panelKey.currentState?.resetSelection();
    final composing = _text.value.composing;
    if (_showsFeedFilters &&
        _feedOptions.isNotEmpty &&
        (!composing.isValid || composing.isCollapsed)) {
      final tokens = splitTopicFilterQuery(value);
      final completed = topicFilterQueryEndsWithSeparator(value)
          ? tokens.length
          : tokens.isEmpty
          ? 0
          : tokens.length - 1;
      final consumed = <int>{};
      for (var i = 0; i < completed; i++) {
        final token = tokens[i];
        final key = topicFilterClauseKey(token);
        if (key == null || key == token || _feedOption(token) == null) continue;
        final expression = _presentation.closedExpression(token);
        if (expression.conditions.isNotEmpty || expression.order != null) {
          continue;
        }
        _feedClauses.removeWhere(
          (clause) => topicFilterClauseKey(clause) == key,
        );
        _feedClauses.add(token);
        consumed.add(i);
      }
      if (consumed.isNotEmpty) {
        _pageRevision.value++;
        value = [
          for (var i = 0; i < tokens.length; i++)
            if (!consumed.contains(i)) tokens[i],
        ].join(' ');
        if (value.isNotEmpty && completed == tokens.length) value += ' ';
      }
    }
    _global.setQuery(value);
    if (_usesFeedFilters) {
      if (!_loadingFeedDraft && _showsFeedFilters && _open) {
        _syncFeedSourceFilters();
      }
      _global.setTopicFilterClauses(
        _feedClauses.isEmpty ? null : _feedClauses.join(' '),
      );
      final hadChoices = _feedChoices.isNotEmpty;
      _suggestFeedFilters(_global.query);
      _syncText();
      if (hadChoices && _feedChoices.isEmpty) _pageRevision.value++;
    }
  }

  String _feedFilterExpression({required String words}) => topicFeedSearchQuery(
    words: words,
    clauses: _feedClauses.join(' '),
    conditions: _global.conditions,
    order: _global.order,
    capabilities: _global.capabilities,
  );

  void _syncFeedSourceFilters() {
    final owner = _document;
    final sourceWords = _feedSourceWords;
    if (sourceWords == null || !_ownsInput(owner)) return;
    final expression = _feedFilterExpression(words: sourceWords);
    if (expression == _publishedFeedExpression) return;
    _publishedFeedExpression = expression;
    if (owner!.updateSearchSourceFilters(expression)) _editedFeedSource = true;
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
    if (key == LogicalKeyboardKey.backspace &&
        _text.text.isEmpty &&
        _showsFeedFilters &&
        _feedClauses.isNotEmpty) {
      final previous = _feedClauses.removeLast();
      _pageRevision.value++;
      _setQuery(topicFilterClauseKey(previous)!);
      return KeyEventResult.handled;
    }
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
    if (!_ownsInput(owner) || !_global.ownsResult(result)) return;
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
    bool ownsActivation() =>
        mounted &&
        activation.canNavigate(
          currentHost: _shell,
          contextHost: ShellScope.maybeRead(context),
          sourceOwnsInput: _ownsInput(owner),
          currentRoute: owner.currentContent,
          searchSite: _global.siteUrl,
          activeSite: shell.currentInstance?.url,
        );
    bool ownsAccount() => _ownsSearchAction(
      shell,
      owner,
      site,
      activation.sourceRoute,
      requireSourceRoute: false,
    );
    unawaited(_global.recordSelection(result));
    final resultRoute = result.destination == null
        ? null
        : ContentRoute(
            destination: result.destination!,
            title: result.title,
            icon: DIcons.magnifyingGlass,
          );
    final preserveSearch =
        widget._pageContent &&
        (result.source is SearchPostHit ||
            result.topic != null ||
            resultRoute != null &&
                (resultRoute.isTopic ||
                    shell.plugins.registry.usesMobilePageSheet(
                      context,
                      resultRoute,
                    )));
    if (!ownsActivation()) return;
    final page = _page;
    _focus.unfocus();
    if (!ownsActivation()) return;
    if (!preserveSearch && !widget._pageContent) {
      _closeSearch();
      if (page != null) await page.completed;
    }
    if (!mounted || !ownsActivation()) return;
    if (!preserveSearch) {
      if (widget._pageContent) _closeSearch();
      if (!ownsAccount()) return;
      _global.setQuery('');
      if (!ownsAccount()) return;
      _global.clearAllConditions();
      if (!ownsAccount()) return;
    }
    if (result.source case final SearchPostHit hit) {
      shell.openSearchResult(hit, words: activation.words);
    } else if (result.topic case final topic?) {
      shell.openTopic(topic);
      if (ownsAccount() && shell.currentContent?.topicId == topic.id) {
        shell.search.setPageWords(
          site,
          owner.tabId,
          'topic-${topic.id}',
          activation.words,
        );
      }
    } else {
      final previousRoute = owner.currentContent;
      ({ShellTabContext owner, ForumTab tab})? destination;
      await openLink(
        context,
        resolveSiteRootPath(site, result.path),
        title: result.title,
        siteUrl: site,
        panel: shell.desktopPanelsEnabled ? ForumPanel.main : null,
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

  bool get _hasFeedDraft =>
      _showsFeedFilters &&
      (_feedClauses.isNotEmpty ||
          _editedFeedSource ||
          _feedOption(splitTopicFilterQuery(_global.query).lastOrNull ?? '') !=
              null);

  void _apply() {
    final shell = _shell!;
    final owner = _document;
    final site = _global.siteUrl;
    if (!_ownsInput(owner) || site == null) return;
    final sourceRoute = owner!.currentContent;
    bool ownsAction({bool requireSourceRoute = true}) => _ownsSearchAction(
      shell,
      owner,
      site,
      sourceRoute,
      requireSourceRoute: requireSourceRoute,
    );
    if (_showsFeedFilters) {
      final typed = _global.query;
      final tail = splitTopicFilterQuery(typed).lastOrNull;
      if (tail != null &&
          !topicFilterQueryEndsWithSeparator(typed) &&
          _feedOption(tail) != null &&
          topicFilterClauseKey(tail) != tail) {
        _setQuery('$typed ');
      }
    }
    _global.submit();
    if (!ownsAction() || _global.phase == GlobalSearchPhase.failed) return;
    final words = _global.wordsQuery.trim();
    final conditions = [
      ..._global.conditions,
      if (_global.hasOrderFilter)
        GlobalSearchCondition(filterId: 'order', value: [_global.order]),
    ];
    final feed = _showsFeedFilters ? _filterFeed : null;
    if (feed != null && (_feedClauses.isNotEmpty || _editedFeedSource)) {
      final query = _feedFilterExpression(words: words);
      _global.rememberSearch();
      if (!ownsAction()) return;
      _closeSearch();
      if (!ownsAction(requireSourceRoute: false)) return;
      unawaited(owner.applyTopicListFilterQuery(query));
      _feedClauses.clear();
      _clearSubmittedSearch();
      return;
    }
    _global.rememberSearch();
    if (!ownsAction()) return;
    _closeSearch();
    if (!ownsAction(requireSourceRoute: false)) return;
    shell.applySearchToList(
      words,
      conditions,
      clearFilters: words.isEmpty && conditions.isEmpty,
    );
    if (!ownsAction(requireSourceRoute: false)) return;
    _clearSubmittedSearch();
  }

  void _openSection(GlobalSearchSection section) {
    final shell = _shell!;
    final owner = _document;
    if (!_ownsInput(owner) ||
        !_global.sections.any((held) => identical(held, section))) {
      return;
    }
    final site = _global.siteUrl;
    if (site == null) return;
    final sourceRoute = owner!.currentContent;
    bool ownsAction({bool requireSourceRoute = true}) => _ownsSearchAction(
      shell,
      owner,
      site,
      sourceRoute,
      requireSourceRoute: requireSourceRoute,
    );
    if (section.scope == GlobalSearchScope.users &&
            !_global.capabilities.userDirectory ||
        section.scope == GlobalSearchScope.groups &&
            !_global.capabilities.groupDirectory) {
      _global.rememberSearch();
      if (!ownsAction()) return;
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
    if (!ownsAction()) return;
    _closeSearch();
    if (!ownsAction(requireSourceRoute: false)) return;
    final route = section.scope == GlobalSearchScope.messages
        ? ContentRoute.searchList(
            '$words in:personal',
            messageMode: MessageListMode.inbox,
          )
        : section.scope == GlobalSearchScope.places
        ? ContentRoute.allCategories()
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
    shell.focusPrimarySearchPane();
    if (!ownsAction(requireSourceRoute: false)) return;
    shell.pushContent(route);
    if (!ownsAction(requireSourceRoute: false)) return;
    shell.search.setPageWords(site, shell.activeTabId, route.id, words);
    if (!ownsAction(requireSourceRoute: false)) return;
    if (route.isMessages) unawaited(shell.loadFeed(route.id));
    if (route.isUsers) unawaited(shell.focusedTabContext.loadUsers());
    if (!ownsAction(requireSourceRoute: false)) return;
    _clearSubmittedSearch();
  }

  Widget _editor(double width, {required bool expanded}) {
    final phonePage = widget.fullScreen && DControlStyle.isTouch(context);
    final hasConditions = expanded
        ? _global.conditions.isNotEmpty ||
              _global.hasOrderFilter ||
              _showsFeedFilters && _feedClauses.isNotEmpty ||
              !_global.scope.isCore
        : _closedConditions.isNotEmpty;
    return Focus(
      key: _editorKey,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: DInputGroup(
        size: phonePage
            ? DControlSize.command
            : widget.fullScreen
            ? DControlSize.filter
            : widget.size,
        variant: phonePage
            ? DInputGroupVariant.quiet
            : DInputGroupVariant.search,
        borderless: expanded && !widget.fullScreen,
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
            textInputAction: widget.fullScreen
                ? TextInputAction.done
                : TextInputAction.search,
            onTap: _requestFocus,
            onChanged: (value) {
              _selectResult(null);
              _setQuery(value);
            },
            onSubmitted: (_) {
              if (widget.fullScreen && !_hasFeedDraft) {
                _focus.unfocus();
              } else {
                _apply();
              }
            },
          ),
          if (width >= 140)
            const DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineStart,
              child: DIcon(DIcons.magnifyingGlass, size: 16),
            ),
          if (hasConditions && !phonePage)
            DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineStart,
              child: LayoutBuilder(
                builder: (context, constraints) => DScrollArea(
                  axes: DScrollAxes.horizontal,
                  showScrollbar: false,
                  // Chip labels arrive from lookups that change nothing else
                  // the field reads, so the chips follow the controller.
                  child: ListenableBuilder(
                    listenable: _global,
                    builder: (context, _) => expanded
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
            ),
          if (phonePage && _usesFeedFilters)
            DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineEnd,
              child: _feedPickerButton(context),
            ),
          if (_query.isNotEmpty || hasConditions)
            DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineEnd,
              child: DInputGroupButton.icon(
                key: const ValueKey('forum-search-clear'),
                focusNode: _clearFocus,
                icon: DIcon(DIcons.xmark, size: phonePage ? null : 12),
                size: phonePage
                    ? DInputGroupButtonSize.regular
                    : DInputGroupButtonSize.small,
                tooltip: appL10n.clearSearch,
                onPressed: _clear,
              ),
            )
          else if (!DControlStyle.isTouch(context) &&
              !widget.fullScreen &&
              width >= 280 * MediaQuery.textScalerOf(context).scale(14) / 14)
            DInputGroupAddon(
              alignment: DInputGroupAddonAlignment.inlineEnd,
              child: DShortcutKeycaps(
                shortcut: DShortcut(
                  searchShortcutForPlatform(defaultTargetPlatform),
                ),
                listenToKeyboard: false,
                compact: true,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _builtReads = _shellReads;
    _builtGlobalReads = _globalReads;
    if (!_search.canSearch) return const SizedBox.shrink();
    if (widget._pageContent) {
      return _buildPageSurface(context, _buildPageContent());
    }
    if (widget.fullScreen) return _buildPageTrigger();
    final platform = Theme.of(context).platform;
    final mobile =
        (platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android) &&
        MediaQuery.sizeOf(context).width < 768;
    final field = DLayoutSelector<_FieldLayout>(
      select: (context, constraints) {
        final anchorWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 420.0;
        final viewport = MediaQuery.sizeOf(context);
        if (_open &&
            (_layoutWidth != anchorWidth || _layoutViewport != viewport)) {
          _scheduleGeometry();
        }
        _layoutWidth = anchorWidth;
        _layoutViewport = viewport;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        // While closed, the field depends only on these breakpoints.
        return (
          openWidth: _open ? anchorWidth : null,
          showsInlineConditions: anchorWidth >= 140,
          showsShortcut: anchorWidth >= 280 * scale,
        );
      },
      builder: (context, layout) {
        final anchorWidth = _layoutWidth ?? 420.0;
        final viewport = MediaQuery.sizeOf(context);
        final safe = MediaQuery.paddingOf(context);
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
                        vertical: 7,
                      ),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: DiscourseTypography.metadata,
                          color: DTokens.of(context).mutedForeground,
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            for (final (keys, label) in [
                              (
                                [
                                  LogicalKeyboardKey.arrowUp,
                                  LogicalKeyboardKey.arrowDown,
                                ],
                                context.l10n.move,
                              ),
                              ([LogicalKeyboardKey.enter], context.l10n.open),
                              if (_globalReads.browsingCategories)
                                (
                                  [
                                    LogicalKeyboardKey.arrowLeft,
                                    LogicalKeyboardKey.arrowRight,
                                  ],
                                  context.l10n.intoACategory,
                                )
                              else
                                (
                                  [LogicalKeyboardKey.tab],
                                  context.l10n.nextSearchType,
                                ),
                              ([LogicalKeyboardKey.escape], context.l10n.close),
                            ])
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 4,
                                children: [
                                  for (final key in keys)
                                    DShortcutKeycaps(
                                      shortcut: DShortcut(SingleActivator(key)),
                                      compact: true,
                                      listenToKeyboard: false,
                                    ),
                                  Text(label),
                                ],
                              ),
                          ],
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
              // A closed field fills the width that [DLayoutSelector] tracks.
              width: _open ? anchorWidth : double.infinity,
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
    return DLayoutSelector<bool>(
      // Count capsules need their own width. Keep the search editor and
      // its keyboard shortcut available when title-bar space is tight.
      select: (context, constraints) =>
          !widget.dense ||
          constraints.maxWidth >=
              180 * MediaQuery.textScalerOf(context).scale(14) / 14,
      builder: (context, showControls) => Row(
        children: [
          if (showControls) ...[
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
    _feedLookup?.cancel();
    _focus.dispose();
    _clearFocus.dispose();
    _text.dispose();
    _popover.dispose();
    _pageRevision.dispose();
    _showFeedPicker.dispose();
    super.dispose();
  }

  Widget _feedPickerButton(BuildContext context) {
    final count = topicFilterMenuCount(_feedFilterExpression(words: ''));
    final label = context.l10n.filters;
    const key = ValueKey('search-filters-button');
    const icon = DIcon(DIcons.filter, size: 12);
    if (count == 0) {
      return DInputGroupButton.icon(
        key: key,
        icon: icon,
        tooltip: label,
        onPressed: _openFeedPicker,
      );
    }
    return DInputGroupButton(
      key: key,
      icon: icon,
      label: Text('$count'),
      tooltip: '$label · $count',
      onPressed: _openFeedPicker,
    );
  }

  Widget _buildPageTrigger() {
    final count = _listFilterCount;
    final button = DButton.iconOnly(
      key: const ValueKey('mobile-search-button'),
      icon: const DIcon(DIcons.magnifyingGlass, size: 20),
      tooltip: appL10n.search,
      semanticLabel: count == 0
          ? appL10n.search
          : '${appL10n.search}, ${appL10n.filters}: $count',
      variant: DButtonVariant.ghost,
      onPressed: _requestFocus,
    );
    if (count == 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        PositionedDirectional(
          top: 0,
          end: -2,
          child: ExcludeSemantics(
            child: DBadge.overlay(
              key: const ValueKey('mobile-search-filter-count'),
              child: Text(count > 99 ? '99+' : '$count'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageContent() => ListenableBuilder(
    listenable: _pageRevision,
    builder: (context, _) {
      _builtGlobalReads = _globalReads;
      if (_filterVisit != null) {
        return _buildFeedPicker(context);
      }
      final phone = DControlStyle.isTouch(context);
      final header = Row(
        spacing: 10,
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
            foregroundColor: DTokens.of(context).primary,
            size: phone ? DButtonSize.command : DButtonSize.filter,
            variant: DButtonVariant.inline,
            onPressed: _closeSearch,
          ),
        ],
      );
      return DReferenceTextScale(
        child: Column(
          key: ForumSearch.panelKey,
          children: [
            DSheetHeader(children: [header]),
            Expanded(
              child: GlobalSearchPanel(
                key: _panelKey,
                showConditions: false,
                footerControls: phone,
                feedFilterChips: _showsFeedFilters
                    ? _feedFilterChips(context)
                    : const [],
                feedFilterChoices: _showsFeedFilters ? _feedChoices : const [],
                feedFilterKeys:
                    _showsFeedFilters && _global.query.trim().isEmpty
                    ? [
                        for (final field in topicFilterMenuFields(_feedOptions))
                          if (_global.availableFilters.every(
                            (filter) => filter.label != field.label,
                          ))
                            TopicFilterSuggestion(
                              name: field.draft,
                              displayName: field.label,
                              description: field.hint,
                              menuField: field.id,
                              menuIcon: field.icon,
                            ),
                      ]
                    : const [],
                onFeedFilterChoice: _pickFeedFilter,
                showFeedApply: _hasFeedDraft,
                showClearFilters:
                    _listExpression.isNotEmpty &&
                    _global.wordsQuery.isEmpty &&
                    _global.conditions.isEmpty &&
                    _feedClauses.isEmpty,
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
    },
  );

  Widget _buildPageSurface(
    BuildContext context,
    Widget content,
  ) => ValueListenableBuilder<bool>(
    valueListenable: _showFeedPicker,
    child: content,
    builder: (context, picking, content) =>
        NotificationListener<ScrollNotification>(
          // Search overlays the feed. Its scrolling cannot fold the feed dock.
          onNotification: (_) => true,
          child: DSheetViewport(
            dismissOnBackdrop: picking,
            onDismiss: _surfaceOpen ? _closeSearch : null,
            content: DSheetContent(
              side: DSheetSide.bottom,
              variant: DSheetVariant.adaptiveMenu,
              sizeToContent: false,
              initiallyExpanded: picking,
              showCloseButton: false,
              semanticLabel: context.l10n.globalSearch,
              children: [
                const DSheetHeader(children: []),
                Expanded(child: DMenuContentScale.unscaled(child: content!)),
              ],
            ),
          ),
        ),
  );

  void _openPage() {
    final content = _buildPageContent();
    final page = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/search'),
      builder: (_) => InheritedTheme.captureAll(
        context,
        ShellScope(
          controller: _shell!,
          // Keep the search subtree stable as the keyboard animates its insets.
          child: Builder(
            builder: (context) => _buildPageSurface(context, content),
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
  ContentRoute? get route => state._sourceRoute;

  @override
  GlobalSearchContext? get pluginContext =>
      state._shell!.plugins.registry.contentSearchContext(state.context);
}
