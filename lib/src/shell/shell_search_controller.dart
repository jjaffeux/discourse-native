import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../models/found_group.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/search_results.dart';
import '../models/user_status.dart';

enum SearchSessionPhase {
  idle,
  tooShort,
  waiting,
  loading,
  suggestions,
  results,
  empty,
  refused,
  failed,
}

enum SearchMode { facets, topics }

enum SearchSuggestionKind { shortcut, category, tag, user }

@immutable
class SearchSuggestion {
  const SearchSuggestion({
    required this.kind,
    required this.completion,
    required this.label,
    this.detail,
    this.avatarUrl,
    this.colorValues = const [],
    this.siteUrl,
    this.userId,
    this.userStatus,
  });

  final SearchSuggestionKind kind;
  final String completion;
  final String label;
  final String? detail;
  final String? avatarUrl;
  final List<int> colorValues;
  final String? siteUrl;
  final int? userId;
  final UserStatus? userStatus;
}

typedef SearchQuickTip = ({String label, String description, bool clickable});

enum _SuggestionSource { hashtag, user, shortcut }

typedef _SuggestionMatch = ({
  _SuggestionSource source,
  String query,
  int start,
});

typedef _SearchRequest = ({
  String siteUrl,
  String term,
  SearchMode mode,
  int? topicId,
  _SuggestionMatch? suggestion,
  int revision,
});

typedef _RecentSearchRequest = ({String siteUrl, int revision});

/// One transient search interaction, independent from shell navigation.
///
/// Core's search menu has three distinct stages: initial options, modifier
/// assistance, and grouped search results. Keeping those stages here prevents
/// a suffix such as `@sa` from being sent to `/search/query`, and gives pointer
/// and keyboard activation one authoritative selection model.
class ShellSearchController extends ChangeNotifier {
  ShellSearchController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.debounceDuration = const Duration(milliseconds: 400),
  });

  static const int maxConcurrentSearches = 2;
  static const int maximumSuggestions = 8;
  static const int maximumHashtagSuggestions = 5;

  static const List<SearchQuickTip> quickTips = [
    (label: '#', description: 'Search by category or tag', clickable: true),
    (label: '@', description: 'Search by author', clickable: true),
    (label: 'in:', description: 'Choose where to search', clickable: true),
    (label: 'status:', description: 'Filter by topic status', clickable: true),
    (
      label: 'Ctrl Enter',
      description: 'Open the full search page',
      clickable: false,
    ),
    (label: '@me', description: 'Search your own posts', clickable: false),
  ];

  static const List<String> _baseShortcuts = [
    'in:title',
    'in:pinned',
    'status:open',
    'status:closed',
    'status:public',
    'status:noreplies',
    'order:latest',
    'order:views',
    'order:likes',
    'order:latest_topic',
  ];

  static const List<String> _authenticatedShortcuts = [
    'in:likes',
    'in:bookmarks',
    'in:mine',
    'in:messages',
    'in:seen',
    'in:tracking',
    'in:unseen',
    'in:watching',
  ];

  static const List<String> _taggingShortcuts = ['in:tagged', 'in:untagged'];

  static final RegExp _minimumLengthBypass = RegExp(
    r'^(l|r)$|order:|category:|categories:|tags?:|before:|after:|status:|user:|group:|badge:|in:|with:|#|@',
    caseSensitive: false,
  );
  static final RegExp _categorySuffix = RegExp(
    r'(#[a-zA-Z0-9\-:]*)$',
    caseSensitive: false,
  );
  static final RegExp _usernameSuffix = RegExp(
    r'(@[a-zA-Z0-9\-_]*)$',
    caseSensitive: false,
  );
  static final RegExp _shortcutSuffix = RegExp(
    r'(in:|status:|order:|:)([a-zA-Z]*)$',
    caseSensitive: false,
  );
  static final RegExp _zeroWidthCharacters = RegExp(r'[\u200B-\u200D\uFEFF]');
  static final RegExp _privateMessageScope = RegExp(
    r'\bin:(personal|messages|personal-direct|all-pms)\b',
    caseSensitive: false,
  );

  final DiscourseApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Duration debounceDuration;

  String? _siteUrl;
  int _minimumLength = 3;
  bool _logSearchQueries = true;
  bool _taggingEnabled = true;
  bool _usePgHeadlinesForExcerpt = false;
  int? _topicId;
  String _query = '';
  bool _panelOpen = false;
  SearchMode _mode = SearchMode.facets;
  SearchSessionPhase _phase = SearchSessionPhase.idle;
  List<SearchPostHit> _hits = const [];
  List<SearchResultSection> _sections = const [];
  List<SearchResult> _results = const [];
  List<SearchSuggestion> _suggestions = const [];
  List<String> _recentSearches = const [];
  String? _message;
  int? _searchLogId;
  int _selectedIndex = -1;
  int _selectedSuggestionIndex = -1;
  bool _topicsActionSelected = false;
  bool _moreActionSelected = false;
  int _revision = 0;
  int _remoteSearches = 0;
  _SearchRequest? _queued;
  Timer? _debounce;
  VoidCallback? _focusField;
  Object? _focusRegistration;
  Object? _activeField;
  String? _recentSearchesLoadedFor;
  int _recentSearchesRevision = 0;
  _RecentSearchRequest? _recentSearchesRequest;
  bool _disposed = false;

  String? get siteUrl => _siteUrl;
  int? get topicId => _topicId;
  String get query => _query;
  bool get panelOpen => _panelOpen;
  SearchMode get mode => _mode;
  SearchSessionPhase get phase => _phase;
  List<SearchPostHit> get hits => _hits;
  List<SearchResultSection> get sections => _sections;
  List<SearchResult> get results => _results;
  List<SearchSuggestion> get suggestions => _suggestions;
  List<String> get recentSearches => _recentSearches;
  String? get message => _message;
  int get selectedIndex => _selectedIndex;
  int get selectedSuggestionIndex => _selectedSuggestionIndex;
  int get minimumLength => _minimumLength;
  bool get taggingEnabled => _taggingEnabled;
  bool get usePgHeadlinesForExcerpt => _usePgHeadlinesForExcerpt;
  bool get isPrivateMessageOnly => _privateMessageScope.hasMatch(_query);
  bool get topicsActionSelected => _topicsActionSelected;
  bool get moreActionSelected => _moreActionSelected;
  bool get hasMoreTopics =>
      _mode == SearchMode.topics &&
      _sections.any(
        (section) => section.kind == SearchResultKind.topic && section.hasMore,
      );
  SearchResult? get selectedResult =>
      _selectedIndex >= 0 && _selectedIndex < _results.length
      ? _results[_selectedIndex]
      : null;
  SearchSuggestion? get selectedSuggestion =>
      _selectedSuggestionIndex >= 0 &&
          _selectedSuggestionIndex < _suggestions.length
      ? _suggestions[_selectedSuggestionIndex]
      : null;
  SearchQuickTip get quickTip {
    final site = _siteUrl;
    if (site == null) return quickTips.first;
    return quickTips[site.hashCode.abs() % quickTips.length];
  }

  bool ownsPanel(Object field) => identical(_activeField, field);

  void _report(
    Object error,
    StackTrace stackTrace, {
    String operation = 'search.load',
    bool degraded = true,
  }) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'search',
      handled: true,
      degraded: degraded,
    );
  }

  /// Selects the forum this global input searches. A changed forum is a hard
  /// boundary: neither its text nor a late private result may cross it.
  void selectSite(
    String? siteUrl, {
    int minimumLength = 3,
    bool logSearchQueries = true,
    bool taggingEnabled = true,
    bool usePgHeadlinesForExcerpt = false,
  }) {
    final boundedMinimum = minimumLength.clamp(1, 100);
    if (_siteUrl != siteUrl) {
      _siteUrl = siteUrl;
      _minimumLength = boundedMinimum;
      _logSearchQueries = logSearchQueries;
      _taggingEnabled = taggingEnabled;
      _usePgHeadlinesForExcerpt = usePgHeadlinesForExcerpt;
      _recentSearches = const [];
      _recentSearchesLoadedFor = null;
      _recentSearchesRevision++;
      clear(notify: true);
      return;
    }

    final searchRulesChanged =
        _minimumLength != boundedMinimum || _taggingEnabled != taggingEnabled;
    final presentationChanged =
        _usePgHeadlinesForExcerpt != usePgHeadlinesForExcerpt;
    final recentSearchRuleChanged = _logSearchQueries != logSearchQueries;
    _minimumLength = boundedMinimum;
    _logSearchQueries = logSearchQueries;
    _taggingEnabled = taggingEnabled;
    _usePgHeadlinesForExcerpt = usePgHeadlinesForExcerpt;
    if (recentSearchRuleChanged) {
      _recentSearches = const [];
      _recentSearchesLoadedFor = null;
      _recentSearchesRevision++;
    }
    if (searchRulesChanged && _query.trim().isNotEmpty) {
      _schedule(_query, immediate: _mode == SearchMode.topics);
    } else if (searchRulesChanged ||
        recentSearchRuleChanged ||
        presentationChanged) {
      _notify();
    }
    if (recentSearchRuleChanged &&
        _logSearchQueries &&
        _panelOpen &&
        _query.trim().isEmpty) {
      unawaited(_loadRecentSearches());
    }
  }

  void setQuery(String value) {
    final parsed = value.replaceAll(_zeroWidthCharacters, '');
    if (_query == parsed) return;
    _query = parsed;
    // Global input edits reset core's `typeFilter` to `exclude_topics`. A
    // topic-scoped field already searches posts, so it stays in topic mode.
    _mode = _topicId == null ? SearchMode.facets : SearchMode.topics;
    _panelOpen = _activeField != null || parsed.trim().isNotEmpty;
    _schedule(parsed);
  }

  void _schedule(String value, {bool immediate = false}) {
    _debounce?.cancel();
    _queued = null;
    _revision++;
    _hits = const [];
    _sections = const [];
    _results = const [];
    _suggestions = const [];
    _clearSelection();
    _message = null;
    _searchLogId = null;

    final validatedTerm = value.trim();
    final siteUrl = _siteUrl;
    if (validatedTerm.isEmpty || siteUrl == null) {
      _phase = SearchSessionPhase.idle;
      _panelOpen = siteUrl != null && _activeField != null;
      _notify();
      if (_panelOpen) unawaited(_loadRecentSearches());
      return;
    }
    _panelOpen = true;
    if (validatedTerm.length > DiscourseApi.maximumSearchTermLength) {
      _phase = SearchSessionPhase.refused;
      _message =
          'Searches can be at most '
          '${DiscourseApi.maximumSearchTermLength} characters.';
      _notify();
      return;
    }

    final suggestion = _mode == SearchMode.facets
        ? _suggestionMatch(validatedTerm)
        : null;
    if (suggestion == null && !_isValid(validatedTerm)) {
      _phase = SearchSessionPhase.tooShort;
      _notify();
      return;
    }

    _phase = SearchSessionPhase.waiting;
    final request = (
      siteUrl: siteUrl,
      term: value,
      mode: _mode,
      topicId: _topicId,
      suggestion: suggestion,
      revision: _revision,
    );
    _debounce = Timer(immediate ? Duration.zero : debounceDuration, () {
      _enqueue(request);
    });
    _notify();
  }

  /// Switches from core's debounced facet suggestions to its topic search.
  void showTopics() {
    if (_mode == SearchMode.topics || _query.trim().isEmpty) return;
    _mode = SearchMode.topics;
    _schedule(_query, immediate: true);
  }

  void refreshTopics() {
    if (_mode != SearchMode.topics || _query.trim().isEmpty) return;
    _schedule(_query, immediate: true);
  }

  void acceptSuggestion(SearchSuggestion suggestion) {
    if (!_suggestions.contains(suggestion)) return;
    _query = suggestion.completion;
    _mode = SearchMode.topics;
    _schedule(_query, immediate: true);
  }

  void useRecentSearch(String term) {
    if (!_recentSearches.contains(term)) return;
    _query = term;
    _mode = SearchMode.topics;
    _schedule(term, immediate: true);
  }

  void useQuickTip() {
    final tip = quickTip;
    if (!tip.clickable) return;
    setQuery(tip.label);
  }

  bool _isValid(String term) =>
      term.length >= _minimumLength || _minimumLengthBypass.hasMatch(term);

  _SuggestionMatch? _suggestionMatch(String term) {
    final category = _categorySuffix.firstMatch(term);
    if (category != null) {
      return (
        source: _SuggestionSource.hashtag,
        query: category.group(1)!.substring(1),
        start: category.start,
      );
    }
    final username = _usernameSuffix.firstMatch(term);
    if (username != null) {
      return (
        source: _SuggestionSource.user,
        query: username.group(1)!.substring(1),
        start: username.start,
      );
    }
    final shortcut = _shortcutSuffix.firstMatch(term);
    if (shortcut != null) {
      return (
        source: _SuggestionSource.shortcut,
        query: shortcut.group(0)!,
        start: shortcut.start,
      );
    }
    return null;
  }

  void _enqueue(_SearchRequest request) {
    if (!_isCurrent(request)) return;
    if (_remoteSearches >= maxConcurrentSearches) {
      _queued = request;
      return;
    }
    _remoteSearches++;
    _phase = SearchSessionPhase.loading;
    _notify();
    unawaited(_search(request).whenComplete(_searchFinished));
  }

  Future<void> _search(_SearchRequest request) async {
    final lease = lifecycle.capture(request.siteUrl);
    try {
      final apiKey = await credentials.apiKeyFor(request.siteUrl);
      if (!lease.isCurrent || !_isCurrent(request)) return;
      final clientId = await credentials.clientId();
      if (!lease.isCurrent || !_isCurrent(request)) return;

      if (request.suggestion case final match?) {
        final suggestions = await _searchSuggestions(
          request,
          match,
          apiKey: apiKey,
          clientId: clientId,
        );
        if (!lease.isCurrent || !_isCurrent(request)) return;
        _suggestions = List.unmodifiable(suggestions);
        _phase = SearchSessionPhase.suggestions;
        _notify();
        return;
      }

      final results = await api.searchPosts(
        siteUrl: request.siteUrl,
        term: request.term,
        typeFilter: request.mode == SearchMode.facets ? 'exclude_topics' : null,
        topicId: request.topicId,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (!lease.isCurrent || !_isCurrent(request)) return;

      _hits = results.hits;
      _sections = List.unmodifiable(
        results.effectiveSections.where(
          (section) => request.mode == SearchMode.facets
              ? section.kind != SearchResultKind.topic
              : section.kind == SearchResultKind.topic,
        ),
      );
      _results = List.unmodifiable([
        for (final section in _sections) ...section.results,
      ]);
      _clearSelection();
      _message = results.error;
      _searchLogId = results.searchLogId;
      _phase = results.error != null
          ? SearchSessionPhase.refused
          : (_results.isEmpty && request.mode == SearchMode.topics
                ? SearchSessionPhase.empty
                : SearchSessionPhase.results);
      if (apiKey != null && request.mode == SearchMode.topics) {
        _rememberRecent(request.term);
      }
      _notify();
    } catch (error, stackTrace) {
      if (!lease.isCurrent || !_isCurrent(request)) return;
      _report(error, stackTrace);
      _hits = const [];
      _sections = const [];
      _results = const [];
      _suggestions = const [];
      _clearSelection();
      _message = "Couldn't search ${Uri.parse(request.siteUrl).host}.";
      _phase = SearchSessionPhase.failed;
      _notify();
    }
  }

  Future<List<SearchSuggestion>> _searchSuggestions(
    _SearchRequest request,
    _SuggestionMatch match, {
    required String? apiKey,
    required String clientId,
  }) async {
    final term = request.term.trim();
    return switch (match.source) {
      _SuggestionSource.shortcut => _shortcutSuggestions(
        term,
        match,
        authenticated: apiKey != null,
      ),
      _SuggestionSource.hashtag => _hashtagSuggestions(
        term,
        match,
        await api.searchHashtags(
          siteUrl: request.siteUrl,
          term: match.query,
          order: _taggingEnabled
              ? DiscourseApi.hashtagOrder
              : const ['category'],
          apiKey: apiKey,
          clientId: clientId,
        ),
      ),
      _SuggestionSource.user => _userSuggestions(
        term,
        match,
        await api.searchUsersAndGroups(
          siteUrl: request.siteUrl,
          term: match.query,
          limit: 6,
          apiKey: apiKey,
          clientId: clientId,
        ),
        siteUrl: request.siteUrl,
      ),
    };
  }

  List<SearchSuggestion> _shortcutSuggestions(
    String term,
    _SuggestionMatch match, {
    required bool authenticated,
  }) {
    final shortcuts = [
      ..._baseShortcuts,
      if (authenticated) ..._authenticatedShortcuts,
      if (_taggingEnabled) ..._taggingShortcuts,
    ];
    return [
      for (final shortcut in shortcuts)
        if (shortcut.contains(match.query.toLowerCase()))
          SearchSuggestion(
            kind: SearchSuggestionKind.shortcut,
            completion: _replaceSuffix(term, match.start, shortcut),
            label: shortcut,
          ),
    ].take(maximumSuggestions).toList(growable: false);
  }

  List<SearchSuggestion> _hashtagSuggestions(
    String term,
    _SuggestionMatch match,
    List<FoundHashtag> found,
  ) => [
    for (final hashtag
        in found
            .where(
              (item) =>
                  item.type == 'category' ||
                  (_taggingEnabled && item.type == 'tag'),
            )
            .take(maximumHashtagSuggestions))
      SearchSuggestion(
        kind: hashtag.type == 'category'
            ? SearchSuggestionKind.category
            : SearchSuggestionKind.tag,
        completion: _replaceSuffix(
          term,
          match.start,
          '#${hashtag.type == 'category' ? hashtag.ref : hashtag.text}',
        ),
        label: hashtag.text,
        detail: hashtag.secondaryText ?? hashtag.description,
        colorValues: hashtag.colorValues,
      ),
  ];

  List<SearchSuggestion> _userSuggestions(
    String term,
    _SuggestionMatch match,
    FoundUsersAndGroups found, {
    required String siteUrl,
  }) {
    final query = match.query.toLowerCase();
    bool contains(String? value) =>
        query.isNotEmpty && (value?.toLowerCase().contains(query) ?? false);
    bool exactly(String? value) => value?.toLowerCase() == query;

    final ordered = <Object>[];
    final seenUsers = <String>{};
    final seenGroups = <String>{};

    void usersWhere(bool Function(FoundUser) test) {
      for (final user in found.users) {
        if (seenUsers.contains(user.username) || !test(user)) continue;
        seenUsers.add(user.username);
        ordered.add(user);
      }
    }

    void groupsWhere(bool Function(FoundGroup) test) {
      for (final group in found.groups) {
        if (seenGroups.contains(group.name) || !test(group)) continue;
        seenGroups.add(group.name);
        ordered.add(group);
      }
    }

    // Core deliberately interleaves exact and partial username/group matches
    // before matches that only occur in a person's display name.
    usersWhere((user) => exactly(user.username));
    groupsWhere((group) => exactly(group.name));
    usersWhere((user) => contains(user.username));
    groupsWhere((group) => query.isEmpty || contains(group.name));
    usersWhere((user) => exactly(user.name));
    usersWhere((user) => contains(user.name));
    usersWhere((_) => true);

    // The header asks user-search to include groups so they participate in
    // ranking, but its assistant renders only the `users` projection of that
    // six-item result. Names are likewise reserved for grouped search hits;
    // the `@` assistant itself displays the username.
    return [
      for (final result in ordered.take(6))
        if (result is FoundUser)
          SearchSuggestion(
            kind: SearchSuggestionKind.user,
            completion: _replaceSuffix(
              term,
              match.start,
              '@${result.username}',
            ),
            label: result.username,
            avatarUrl: result.avatarUrl,
            siteUrl: siteUrl,
            userId: result.id,
            userStatus: result.status,
          ),
    ];
  }

  static String _replaceSuffix(String term, int start, String replacement) {
    final prefix = term.substring(0, start).trimRight();
    return prefix.isEmpty ? replacement : '$prefix $replacement';
  }

  void _searchFinished() {
    _remoteSearches--;
    if (_disposed) return;
    final queued = _queued;
    _queued = null;
    if (queued != null && _isCurrent(queued)) _enqueue(queued);
  }

  bool _isCurrent(_SearchRequest request) =>
      !_disposed &&
      request.revision == _revision &&
      request.siteUrl == _siteUrl &&
      request.term == _query &&
      request.mode == _mode &&
      request.topicId == _topicId;

  void openPanel() {
    if (_siteUrl == null) return;
    if (!_panelOpen) {
      _panelOpen = true;
      _notify();
    }
    if (_query.trim().isEmpty) unawaited(_loadRecentSearches());
  }

  void closePanel() {
    if (!_panelOpen) return;
    if (_topicId != null) {
      clear();
      return;
    }
    _panelOpen = false;
    _clearSelection();
    _notify();
  }

  /// Clears only the field. Core keeps the focused menu open and returns to
  /// its quick tip and recent searches.
  void clearQuery() {
    _debounce?.cancel();
    _queued = null;
    _revision++;
    _query = '';
    _panelOpen = _siteUrl != null && _activeField != null;
    _resetResultState();
    _notify();
    if (_panelOpen) unawaited(_loadRecentSearches());
  }

  /// Ends the whole search interaction, used by navigation and site changes.
  void clear({bool notify = true}) {
    _debounce?.cancel();
    _queued = null;
    _revision++;
    _query = '';
    _panelOpen = false;
    _topicId = null;
    _resetResultState();
    if (notify) _notify();
  }

  void _resetResultState() {
    _mode = _topicId == null ? SearchMode.facets : SearchMode.topics;
    _phase = SearchSessionPhase.idle;
    _hits = const [];
    _sections = const [];
    _results = const [];
    _suggestions = const [];
    _message = null;
    _searchLogId = null;
    _clearSelection();
  }

  void _clearSelection() {
    _selectedIndex = -1;
    _selectedSuggestionIndex = -1;
    _topicsActionSelected = false;
    _moreActionSelected = false;
  }

  bool moveSelection(int delta) {
    if (delta == 0) return false;
    if (_phase == SearchSessionPhase.suggestions) {
      return _moveSuggestionSelection(delta);
    }

    final count =
        _results.length +
        (_mode == SearchMode.facets ? 1 : 0) +
        (hasMoreTopics ? 1 : 0);
    if (count == 0) return false;

    var position = _selectionPosition;
    if (position == -1) {
      if (delta < 0) return false;
      position = 0;
    } else {
      final next = position + delta.sign;
      if (next < 0) {
        _clearSelection();
        _notify();
        return true;
      }
      if (next >= count) return false;
      position = next;
    }
    _selectPosition(position);
    _notify();
    return true;
  }

  int get _selectionPosition {
    if (_topicsActionSelected) return 0;
    if (_selectedIndex >= 0) {
      return _selectedIndex + (_mode == SearchMode.facets ? 1 : 0);
    }
    if (_moreActionSelected) {
      return _results.length + (_mode == SearchMode.facets ? 1 : 0);
    }
    return -1;
  }

  void _selectPosition(int position) {
    _clearSelection();
    if (_mode == SearchMode.facets && position == 0) {
      _topicsActionSelected = true;
      return;
    }
    final resultIndex = position - (_mode == SearchMode.facets ? 1 : 0);
    if (resultIndex < _results.length) {
      _selectedIndex = resultIndex;
    } else if (hasMoreTopics) {
      _moreActionSelected = true;
    }
  }

  bool _moveSuggestionSelection(int delta) {
    if (_suggestions.isEmpty) return false;
    if (_selectedSuggestionIndex == -1) {
      if (delta < 0) return false;
      _selectedSuggestionIndex = 0;
    } else {
      final next = _selectedSuggestionIndex + delta.sign;
      if (next < 0) {
        _selectedSuggestionIndex = -1;
      } else if (next >= _suggestions.length) {
        return false;
      } else {
        _selectedSuggestionIndex = next;
      }
    }
    _notify();
    return true;
  }

  void selectTopicsAction() {
    if (_mode != SearchMode.facets || _topicsActionSelected) return;
    _clearSelection();
    _topicsActionSelected = true;
    _notify();
  }

  void selectMoreAction() {
    if (!hasMoreTopics || _moreActionSelected) return;
    _clearSelection();
    _moreActionSelected = true;
    _notify();
  }

  void select(int index) {
    if (index < 0 || index >= _results.length || _selectedIndex == index) {
      return;
    }
    _clearSelection();
    _selectedIndex = index;
    _notify();
  }

  void selectSuggestion(int index) {
    if (index < 0 ||
        index >= _suggestions.length ||
        _selectedSuggestionIndex == index) {
      return;
    }
    _clearSelection();
    _selectedSuggestionIndex = index;
    _notify();
  }

  Future<void> _loadRecentSearches() async {
    final siteUrl = _siteUrl;
    final pending = _recentSearchesRequest;
    if (siteUrl == null ||
        !_logSearchQueries ||
        (pending?.siteUrl == siteUrl &&
            pending?.revision == _recentSearchesRevision) ||
        _recentSearchesLoadedFor == siteUrl) {
      return;
    }
    final request = (siteUrl: siteUrl, revision: ++_recentSearchesRevision);
    _recentSearchesRequest = request;
    bool ownsRequest() =>
        !_disposed &&
        request.revision == _recentSearchesRevision &&
        request.siteUrl == _siteUrl &&
        _logSearchQueries;
    final lease = lifecycle.capture(siteUrl);
    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (!lease.isCurrent || !ownsRequest()) return;
      if (apiKey == null) {
        _recentSearchesLoadedFor = siteUrl;
        return;
      }
      final clientId = await credentials.clientId();
      final recent = await api.recentSearches(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
      if (!lease.isCurrent || !ownsRequest()) return;
      _recentSearches = recent;
      _recentSearchesLoadedFor = siteUrl;
      _notify();
    } catch (error, stackTrace) {
      if (lease.isCurrent && ownsRequest()) {
        _recentSearchesLoadedFor = siteUrl;
        _report(
          error,
          stackTrace,
          operation: 'search.loadRecent',
          degraded: false,
        );
      }
    } finally {
      if (_recentSearchesRequest == request) _recentSearchesRequest = null;
    }
  }

  Future<void> resetRecentSearches() async {
    final siteUrl = _siteUrl;
    if (siteUrl == null || _recentSearches.isEmpty) return;
    final previous = _recentSearches;
    final revision = ++_recentSearchesRevision;
    _recentSearches = const [];
    _notify();
    final lease = lifecycle.capture(siteUrl);
    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (apiKey == null || !lease.isCurrent) return;
      final clientId = await credentials.clientId();
      await api.resetRecentSearches(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      );
    } catch (error, stackTrace) {
      if (!lease.isCurrent ||
          siteUrl != _siteUrl ||
          revision != _recentSearchesRevision) {
        return;
      }
      _recentSearches = previous;
      _report(error, stackTrace, operation: 'search.clearRecent');
      _notify();
    }
  }

  void _rememberRecent(String term) {
    if (!_logSearchQueries || term.isEmpty) return;
    final recent = _recentSearches.where((item) => item != term).toList();
    _recentSearches = List.unmodifiable([term, ...recent].take(5));
    _recentSearchesRevision++;
  }

  void recordSelection(SearchResult result) {
    final siteUrl = _siteUrl;
    final searchLogId = _searchLogId;
    if (siteUrl == null || searchLogId == null) return;
    unawaited(_recordSelection(siteUrl, searchLogId, result));
  }

  Future<void> _recordSelection(
    String siteUrl,
    int searchLogId,
    SearchResult result,
  ) async {
    final lease = lifecycle.capture(siteUrl);
    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (apiKey == null || !lease.isCurrent) return;
      final clientId = await credentials.clientId();
      await api.logSearchClick(
        siteUrl: siteUrl,
        apiKey: apiKey,
        searchLogId: searchLogId,
        resultId: result.id,
        resultKind: result.kind,
        clientId: clientId,
      );
    } catch (error, stackTrace) {
      if (lease.isCurrent) {
        _report(
          error,
          stackTrace,
          operation: 'search.logSelection',
          degraded: false,
        );
      }
    }
  }

  /// The currently mounted field registers the callback a global shortcut
  /// should use. The returned callback removes only that registration.
  VoidCallback registerFocus(Object field, VoidCallback focus) {
    _focusRegistration = field;
    _focusField = focus;
    return () {
      if (identical(_focusRegistration, field)) {
        _focusRegistration = null;
        _focusField = null;
      }
      if (identical(_activeField, field)) {
        _activeField = null;
        closePanel();
      }
    };
  }

  void activateField(Object field) {
    if (!identical(_activeField, field)) {
      _activeField = field;
      _panelOpen = true;
      _notify();
      if (_query.trim().isEmpty) unawaited(_loadRecentSearches());
    } else {
      openPanel();
    }
  }

  void requestFocus() {
    if (_siteUrl == null) return;
    _setTopicScope(null);
    _focusSearchField();
  }

  void requestTopicFocus(int topicId) {
    if (topicId <= 0) {
      throw ArgumentError.value(topicId, 'topicId', 'must be positive');
    }
    if (_siteUrl == null) return;
    _setTopicScope(topicId);
    _focusSearchField();
  }

  void _setTopicScope(int? topicId) {
    if (_topicId == topicId) return;
    _topicId = topicId;
    _mode = topicId == null ? SearchMode.facets : SearchMode.topics;
    _schedule(_query, immediate: topicId != null && _query.trim().isNotEmpty);
  }

  void _focusSearchField() {
    _focusField?.call();
    openPanel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _queued = null;
    _focusField = null;
    _focusRegistration = null;
    _activeField = null;
    super.dispose();
  }
}
