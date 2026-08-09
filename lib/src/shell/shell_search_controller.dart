import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/discourse_api.dart';
import '../data/site_lifecycle.dart';
import '../models/search_results.dart';

enum SearchSessionPhase {
  idle,
  tooShort,
  waiting,
  loading,
  results,
  empty,
  refused,
  failed,
}

enum SearchMode { facets, topics }

typedef _SearchRequest = ({
  String siteUrl,
  String term,
  SearchMode mode,
  int revision,
});

/// One transient search interaction, independent from shell navigation.
///
/// The session bounds remote work the same way composer autocomplete does: two
/// requests may be finishing, and any further typing replaces one queued
/// request rather than creating an unbounded tail of stale searches.
class ShellSearchController extends ChangeNotifier {
  ShellSearchController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.debounceDuration = const Duration(milliseconds: 400),
  });

  static const int maxConcurrentSearches = 2;

  static final RegExp _minimumLengthBypass = RegExp(
    r'^(l|r)$|order:|category:|categories:|tags?:|before:|after:|status:|user:|group:|badge:|in:|with:|#|@',
    caseSensitive: false,
  );

  final DiscourseApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Duration debounceDuration;

  String? _siteUrl;
  int _minimumLength = 3;
  String _query = '';
  bool _panelOpen = false;
  SearchMode _mode = SearchMode.facets;
  SearchSessionPhase _phase = SearchSessionPhase.idle;
  List<SearchPostHit> _hits = const [];
  List<SearchResultSection> _sections = const [];
  List<SearchResult> _results = const [];
  String? _message;
  int _selectedIndex = -1;
  int _revision = 0;
  int _remoteSearches = 0;
  _SearchRequest? _queued;
  Timer? _debounce;
  VoidCallback? _focusField;
  Object? _focusRegistration;
  Object? _activeField;
  bool _disposed = false;

  String? get siteUrl => _siteUrl;
  String get query => _query;
  bool get panelOpen => _panelOpen;
  SearchMode get mode => _mode;
  SearchSessionPhase get phase => _phase;
  List<SearchPostHit> get hits => _hits;
  List<SearchResultSection> get sections => _sections;
  List<SearchResult> get results => _results;
  String? get message => _message;
  int get selectedIndex => _selectedIndex;
  int get minimumLength => _minimumLength;
  bool get topicsActionSelected =>
      _mode == SearchMode.facets && _selectedIndex == -1;
  SearchResult? get selectedResult =>
      _selectedIndex >= 0 && _selectedIndex < _results.length
      ? _results[_selectedIndex]
      : null;
  bool ownsPanel(Object field) => identical(_activeField, field);

  /// Selects the forum this global input searches. A changed forum is a hard
  /// boundary: neither its text nor a late private result may cross it.
  void selectSite(String? siteUrl, {int minimumLength = 3}) {
    final boundedMinimum = minimumLength.clamp(1, 100);
    if (_siteUrl != siteUrl) {
      _siteUrl = siteUrl;
      _minimumLength = boundedMinimum;
      clear(notify: true);
      return;
    }
    if (_minimumLength == boundedMinimum) return;
    _minimumLength = boundedMinimum;
    if (_query.trim().isNotEmpty) {
      _schedule(_query, immediate: _mode == SearchMode.topics);
    } else {
      _notify();
    }
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _panelOpen = value.trim().isNotEmpty;
    _schedule(value, immediate: _mode == SearchMode.topics);
  }

  void _schedule(String value, {bool immediate = false}) {
    _debounce?.cancel();
    _queued = null;
    _revision++;
    _hits = const [];
    _sections = const [];
    _results = const [];
    _selectedIndex = -1;
    _message = null;

    final validatedTerm = value.trim();
    final siteUrl = _siteUrl;
    if (validatedTerm.isEmpty || siteUrl == null) {
      _phase = SearchSessionPhase.idle;
      _panelOpen = false;
      _notify();
      return;
    }
    _panelOpen = true;
    if (!_isValid(validatedTerm)) {
      _phase = SearchSessionPhase.tooShort;
      _notify();
      return;
    }

    _phase = SearchSessionPhase.waiting;
    final request = (
      siteUrl: siteUrl,
      term: value,
      mode: _mode,
      revision: _revision,
    );
    _debounce = Timer(immediate ? Duration.zero : debounceDuration, () {
      _enqueue(request);
    });
    _notify();
  }

  /// Switches from core's debounced facet suggestions to its topic search.
  ///
  /// The web search does this when the first assistant row or Enter is used:
  /// it removes `exclude_topics`, searches immediately, then only renders the
  /// topic facet from the broader response.
  void showTopics() {
    if (_mode == SearchMode.topics || _query.trim().isEmpty) return;
    _mode = SearchMode.topics;
    _schedule(_query, immediate: true);
  }

  bool _isValid(String term) =>
      term.length >= _minimumLength || _minimumLengthBypass.hasMatch(term);

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
      final results = await api.searchPosts(
        siteUrl: request.siteUrl,
        term: request.term,
        typeFilter: request.mode == SearchMode.facets ? 'exclude_topics' : null,
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
      // The topic-search action is the first keyboard target in facet mode.
      // Topic mode has no action row, so its first result starts selected.
      _selectedIndex = _results.isEmpty || request.mode == SearchMode.facets
          ? -1
          : 0;
      _message = results.error;
      _phase = results.error != null
          ? SearchSessionPhase.refused
          : (_results.isEmpty && request.mode == SearchMode.topics
                ? SearchSessionPhase.empty
                : SearchSessionPhase.results);
      _notify();
    } catch (_) {
      if (!lease.isCurrent || !_isCurrent(request)) return;
      _hits = const [];
      _sections = const [];
      _results = const [];
      _selectedIndex = -1;
      _message = "Couldn't search ${Uri.parse(request.siteUrl).host}.";
      _phase = SearchSessionPhase.failed;
      _notify();
    }
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
      request.mode == _mode;

  void openPanel() {
    if (_query.trim().isEmpty || _panelOpen) return;
    _panelOpen = true;
    _notify();
  }

  void closePanel() {
    if (!_panelOpen) return;
    _panelOpen = false;
    _notify();
  }

  void clear({bool notify = true}) {
    _debounce?.cancel();
    _queued = null;
    _revision++;
    _query = '';
    _panelOpen = false;
    _mode = SearchMode.facets;
    _phase = SearchSessionPhase.idle;
    _hits = const [];
    _sections = const [];
    _results = const [];
    _message = null;
    _selectedIndex = -1;
    if (notify) _notify();
  }

  bool moveSelection(int delta) {
    if (_results.isEmpty || delta == 0) return false;

    final firstIndex = _mode == SearchMode.facets ? -1 : 0;
    final targetCount = _results.length + (_mode == SearchMode.facets ? 1 : 0);
    final currentPosition = _selectedIndex - firstIndex;
    _selectedIndex = firstIndex + (currentPosition + delta) % targetCount;
    _notify();
    return true;
  }

  void selectTopicsAction() {
    if (_mode != SearchMode.facets || _selectedIndex == -1) return;
    _selectedIndex = -1;
    _notify();
  }

  void select(int index) {
    if (index < 0 || index >= _results.length || _selectedIndex == index) {
      return;
    }
    _selectedIndex = index;
    _notify();
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
      if (_query.trim().isNotEmpty) _panelOpen = true;
      _notify();
    } else {
      openPanel();
    }
  }

  void requestFocus() {
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
