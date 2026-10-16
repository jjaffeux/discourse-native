import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/recent_search_store.dart';
import '../data/site_lifecycle.dart';
import '../plugin_api/global_search.dart' show GlobalSearchLookup;
import 'global_search_api.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'shell_search_controller.dart';

/// Owns a search session independently of the editor and its presentation.
/// Scope banks survive tab changes; requests only receive the active bank.
class GlobalSearchController extends ChangeNotifier {
  GlobalSearchController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.recentSource,
    this.debounceDuration = const Duration(milliseconds: 350),
    this.recentStore = const RecentSearchStore(),
  }) {
    recentSource?.addListener(_recentChanged);
  }

  final GlobalSearchApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final ShellSearchController? recentSource;
  final Duration debounceDuration;
  final RecentSearchStore recentStore;
  String? _siteUrl;
  SiteLease? _lease;
  String _baseFingerprint = '';
  GlobalSearchCapabilities _capabilities = const GlobalSearchCapabilities();
  GlobalSearchScope _scope = GlobalSearchScope.all;
  GlobalSearchContext? _context, _pendingContext;
  String _query = '';
  GlobalSearchScope? _preferredScope;
  int? _contextTopicId;
  String? _contextTopicTitle;
  final Set<String> _removedRecent = {};
  final _banks = <GlobalSearchScope, List<GlobalSearchCondition>>{};
  final _orders = <GlobalSearchScope, String>{};
  final _ascending = <GlobalSearchScope, bool>{};
  final _properties = {
    GlobalSearchDisplayProperty.excerpt,
    GlobalSearchDisplayProperty.category,
    GlobalSearchDisplayProperty.replies,
  };
  List<GlobalSearchSection> _sections = const [];
  List<String> _localRecent = const [];
  final _recentStates = <String, GlobalSearchRequest>{};
  final _choiceLabels = <String, Map<String, GlobalSearchFilterChoice>>{};
  final _tagChoices = <String, GlobalSearchFilterChoice>{};
  int _historyRevision = 0;
  bool _historyCleared = false;
  GlobalSearchPhase _phase = GlobalSearchPhase.idle;
  String? _error;
  bool _hasMore = false, _loadingMore = false, _disposed = false;
  int _revision = 0, _configuration = 0, _page = 0, _offset = 0;
  final _inFlight = <Object, Set<Completer<void>>>{};
  Timer? _debounce;
  VoidCallback? _queued;

  String? get siteUrl => _siteUrl;
  Object? get categoryLookupSession => _lease?.session;

  /// Invalidates open filter editors when their account or capabilities change.
  int get configurationRevision => _configuration;

  /// Tags returned by successful lookups in the current site/account session.
  List<GlobalSearchFilterChoice> cachedTagChoices(String query) {
    if (_disposed || _lease?.isCurrent != true || !capabilities.tagging) {
      return const [];
    }
    final term = query.trim().toLowerCase();
    return List.unmodifiable(
      _tagChoices.values
          .where((choice) => choice.value.toLowerCase().contains(term))
          .take(30),
    );
  }

  /// Display text for a stable filter value returned in this site session.
  String? choiceLabel(String filterId, String value) =>
      choice(filterId, value)?.label;

  GlobalSearchFilterChoice? choice(String filterId, String value) =>
      _choiceLabels[filterId]?[value];

  /// Retains draft category metadata before applying its stable IDs.
  void rememberCategorySelection(List<GlobalSearchFilterChoice> choices) =>
      _rememberChoices('category', choices);

  String get query => _query;
  GlobalSearchScope get scope => _scope;
  GlobalSearchCapabilities get capabilities => _capabilities;
  List<GlobalSearchScope> get scopes => List.unmodifiable(capabilities.scopes);
  List<GlobalSearchCondition> conditionsFor(GlobalSearchScope value) =>
      value == GlobalSearchScope.all ? const [] : _banks[value] ?? const [];
  List<GlobalSearchCondition> get conditions => conditionsFor(scope);
  List<GlobalSearchFilter> get availableFilters => List.unmodifiable([
    if (scope == GlobalSearchScope.all || scope == GlobalSearchScope.forum)
      globalSearchOrderFilter(capabilities),
    for (final filter in globalSearchDefinitions(capabilities))
      if ((filter.scope ==
              (scope == GlobalSearchScope.all
                  ? GlobalSearchScope.forum
                  : scope)) &&
          globalSearchFilterAvailable(filter, capabilities))
        filter,
  ]);
  List<GlobalSearchOrder> get orders => globalSearchOrders(scope, capabilities);

  List<int> get orderedConditionIndices =>
      List.generate(conditions.length, (index) => index)..sort((a, b) {
        final left = globalSearchFilter(
          conditions[a].filterId,
          capabilities,
        )!.label;
        final right = globalSearchFilter(
          conditions[b].filterId,
          capabilities,
        )!.label;
        final compared = left.toLowerCase().compareTo(right.toLowerCase());
        return compared == 0 ? a.compareTo(b) : compared;
      });
  String get order => _orders[scope] ?? orders.first.value;
  bool get hasOrderFilter =>
      scope == GlobalSearchScope.forum && order != 'relevance';
  bool get ascending =>
      _ascending[scope] ??
      (scope == GlobalSearchScope.groups ||
          scope == GlobalSearchScope.users && order == 'username');
  bool get canOrderAscending =>
      (scope == GlobalSearchScope.groups && capabilities.groupDirectory) ||
      (scope == GlobalSearchScope.users && capabilities.userDirectory);
  Set<GlobalSearchDisplayProperty> get properties =>
      Set.unmodifiable(_properties);
  List<GlobalSearchSection> get sections {
    final ordered = _sections.toList();
    int rank(GlobalSearchSection section) => section.topicId != null
        ? -2
        : section.scope == _preferredScope
        ? -1
        : scopes.indexOf(section.scope);
    ordered.sort((a, b) => rank(a).compareTo(rank(b)));
    return List.unmodifiable(ordered);
  }

  void setPageContext({
    GlobalSearchScope? preferredScope,
    int? topicId,
    String? topicTitle,
  }) {
    final changed = _contextTopicId != topicId;
    _preferredScope = preferredScope;
    _contextTopicId = topicId;
    _contextTopicTitle = topicTitle;
    if (changed && query.trim().isNotEmpty) {
      _schedule();
    } else {
      _notify();
    }
  }

  GlobalSearchFilter? get stagedFilter {
    final tail = query.endsWith(' ') ? '' : query.split(RegExp(r'\s+')).last;
    final colon = tail.indexOf(':');
    if (colon < 0) return null;
    final key = tail.substring(0, colon).toLowerCase();
    return availableFilters
        .where(
          (filter) =>
              filter.id.toLowerCase() == key ||
              filter.token == key ||
              filter.opTokens.values.contains(key) ||
              key == 'tag' && filter.id == 'tags' ||
              (key == '-tags' || key == '-tag') && filter.id == 'tags' ||
              key == 'user' && filter.id == 'author',
        )
        .firstOrNull;
  }

  String get stagedTerm => stagedFilter == null
      ? ''
      : query.split(RegExp(r'\s+')).last.split(':').skip(1).join(':');
  String get stagedOperator {
    final filter = stagedFilter;
    if (filter == null) return 'is';
    final key = query.split(RegExp(r'\s+')).last.split(':').first;
    if (key == '-tags' || key == '-tag') return 'none';
    return filter.opTokens.entries
            .where((entry) => entry.value == key)
            .firstOrNull
            ?.key ??
        conditions
            .where((condition) => condition.filterId == filter.id)
            .firstOrNull
            ?.operator ??
        filter.operators.first.value;
  }

  List<GlobalSearchFilter> get hintedFilters {
    final tail = query.endsWith(' ')
        ? ''
        : query.split(RegExp(r'\s+')).last.toLowerCase();
    if (tail.length < 2 || tail.contains(':')) return const [];
    return availableFilters
        .where(
          (filter) =>
              filter.id != 'searchIn' &&
              (filter.id.toLowerCase().startsWith(tail) ||
                  (filter.token?.startsWith(tail) ?? false)),
        )
        .toList();
  }

  String get wordsQuery => stagedFilter == null && hintedFilters.isEmpty
      ? query
      : query
            .substring(
              0,
              query.lastIndexOf(RegExp(r'\s')) < 0
                  ? 0
                  : query.lastIndexOf(RegExp(r'\s')),
            )
            .trim();

  void beginFilter(GlobalSearchFilter filter, {String value = ''}) {
    final tail = query.endsWith(' ') ? '' : query.split(RegExp(r'\s+')).last;
    final replacing =
        stagedFilter != null ||
        hintedFilters.any((item) => item.id == filter.id);
    final prefix = replacing
        ? (tail.isEmpty
              ? query
              : query.substring(0, query.length - tail.length))
        : query.trim().isEmpty
        ? ''
        : '${query.trim()} ';
    setQuery('$prefix${filter.id}:${value.replaceAll(' ', '_')}');
  }

  void completeFilter(GlobalSearchCondition condition) {
    final words = wordsQuery;
    if (condition.filterId == 'order') {
      setScope(GlobalSearchScope.forum);
      setOrder(condition.text);
      setQuery(words.isEmpty ? '' : '$words ');
      return;
    }
    final old = conditions.indexWhere(
      (item) => item.filterId == condition.filterId,
    );
    if (old >= 0) {
      updateCondition(old, condition);
    } else {
      addCondition(condition);
    }
    setQuery(words.isEmpty ? '' : '$words ');
  }

  List<GlobalSearchResult> get results =>
      List.unmodifiable([for (final section in sections) ...section.results]);
  GlobalSearchPhase get phase => _phase;
  String? get error => _error;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;
  List<String> get recentSearches {
    if (!capabilities.authenticated || !capabilities.logSearchQueries) {
      return const [];
    }
    final source = recentSource;
    return List.unmodifiable(
      {
        ..._localRecent,
        if (!_historyCleared && source?.siteUrl == siteUrl)
          ...source!.recentSearches,
      }.where((term) => !_removedRecent.contains(term)).take(5),
    );
  }

  void configure({
    String? siteUrl,
    required GlobalSearchCapabilities capabilities,
  }) {
    if (_disposed) return;
    final lease = siteUrl == null ? null : lifecycle.capture(siteUrl);
    final changedSite =
        _siteUrl != siteUrl ||
        _lease?.session != lease?.session ||
        _capabilities.username != capabilities.username;
    if (!changedSite && _baseFingerprint == capabilities.fingerprint) return;
    _configuration++;
    _tagChoices.clear();
    _baseFingerprint = capabilities.fingerprint;
    _siteUrl = siteUrl;
    _lease = lease;
    _capabilities = capabilities;
    if (changedSite) {
      _query = '';
      _contextTopicId = null;
      _contextTopicTitle = null;
      _preferredScope = null;
      _removedRecent.clear();
      _scope = GlobalSearchScope.all;
      _banks.clear();
      _orders.clear();
      _ascending.clear();
      _localRecent = const [];
      _recentStates.clear();
      _choiceLabels.clear();
      _context = null;
      _pendingContext = null;
      _historyRevision++;
      _historyCleared = false;
    }
    _sanitize();
    _schedule();
    if (siteUrl != null && lease != null) {
      if (changedSite &&
          capabilities.authenticated &&
          capabilities.username != null) {
        unawaited(
          _restoreRemovedRecent(
            siteUrl,
            capabilities.username!,
            lease,
            _configuration,
          ),
        );
      }
      unawaited(
        _loadCapabilities(siteUrl, lease, _configuration, capabilities),
      );
    }
  }

  Future<void> _restoreRemovedRecent(
    String site,
    String username,
    SiteLease lease,
    int configuration,
  ) async {
    try {
      final saved = await recentStore.read(site, username);
      if (_disposed || !lease.isCurrent || configuration != _configuration) {
        return;
      }
      _removedRecent.addAll(
        saved.where((term) => !_localRecent.contains(term)),
      );
      _notify();
    } catch (_) {
      /* History still works when local preferences are unavailable. */
    }
  }

  void _saveRemovedRecent() {
    final site = siteUrl, username = capabilities.username, lease = _lease;
    if (site == null || username == null || lease?.isCurrent != true) return;
    final terms = Set<String>.of(_removedRecent);
    unawaited(
      recentStore.write(site, username, terms).catchError((Object _) {}),
    );
  }

  Future<void> _loadCapabilities(
    String site,
    SiteLease lease,
    int epoch,
    GlobalSearchCapabilities base,
  ) async {
    bool current() => !_disposed && lease.isCurrent && epoch == _configuration;
    try {
      final key = await credentials.apiKeyFor(site);
      if (!current()) return;
      final client = key == null ? null : await credentials.clientId();
      if (!current()) return;
      final loaded = await api.capabilities(
        siteUrl: site,
        apiKey: key,
        clientId: client,
        base: base,
      );
      if (!current() || loaded.fingerprint == capabilities.fingerprint) return;
      _capabilities = loaded;
      _sanitize();
      if (_pendingContext case final pending?) setContext(pending);
      _schedule();
    } catch (_) {
      // Optional discovery does not prevent core search.
    }
  }

  void _sanitize() {
    for (final entry in _banks.entries.toList()) {
      _banks[entry.key] = List.unmodifiable(
        entry.value.where(
          (condition) =>
              validateGlobalSearchCondition(condition, capabilities) == null,
        ),
      );
    }
    for (final value in scopes) {
      final allowed = globalSearchOrders(value, capabilities);
      if (!allowed.any((item) => item.value == _orders[value])) {
        _orders.remove(value);
      }
    }
    if (!scopes.contains(scope)) {
      _scope = GlobalSearchScope.all;
    }
  }

  void setQuery(String value) {
    if (_disposed || _query == value) return;
    _query = value;
    final tokens = RegExp(r'(?:[^\s"]+|"[^"]*")+').allMatches(value).toList();
    final remaining = <String>[];
    var converted = false;
    for (final token in tokens) {
      if (token.end == value.length && !value.endsWith(' ')) {
        remaining.add(token.group(0)!);
        continue;
      }
      try {
        final parsed = parseGlobalSearchExpression(
          token.group(0)!,
          scope,
          capabilities,
        );
        if (parsed.conditions.isNotEmpty || parsed.order != null) {
          converted = true;
          for (final condition in parsed.conditions) {
            final old = conditions.indexWhere(
              (item) => item.filterId == condition.filterId,
            );
            _putCondition(condition, index: old < 0 ? null : old);
          }
          if (parsed.order != null) {
            _scope = GlobalSearchScope.forum;
            _orders[_scope] = parsed.order!;
          }
        } else {
          remaining.add(token.group(0)!);
        }
      } on FormatException {
        remaining.add(token.group(0)!);
      }
    }
    if (converted) {
      _query = remaining.join(' ');
      if (_query.isNotEmpty && value.endsWith(' ')) _query += ' ';
    }
    _schedule();
  }

  void setScope(GlobalSearchScope value) {
    _pendingContext = null;
    if (_disposed || !scopes.contains(value) || value == scope) return;
    _scope = value;
    _schedule();
  }

  void addCondition(GlobalSearchCondition condition) {
    _putCondition(condition);
  }

  void updateCondition(int index, GlobalSearchCondition condition) {
    if (index < 0 || index >= conditions.length) return;
    _putCondition(condition, index: index);
  }

  void _putCondition(GlobalSearchCondition condition, {int? index}) {
    _pendingContext = null;
    final validation = validateGlobalSearchCondition(condition, capabilities);
    if (validation != null) throw FormatException(validation);
    final filter = globalSearchFilter(condition.filterId, capabilities)!;
    if (condition.filterId == 'order') {
      setScope(GlobalSearchScope.forum);
      setOrder(condition.text);
      return;
    }
    final next = conditionsFor(filter.scope).toList();
    final copy = GlobalSearchCondition(
      filterId: condition.filterId,
      operator: condition.operator,
      value: List.unmodifiable(condition.value),
    );
    final token = globalSearchConditionToken(
      copy,
      capabilities: capabilities,
      username: capabilities.username,
    );
    if (index != null && scope == filter.scope && index < next.length) {
      next[index] = copy;
    } else {
      final duplicate = next.indexWhere(
        (item) =>
            globalSearchConditionToken(
              item,
              capabilities: capabilities,
              username: capabilities.username,
            ) ==
            token,
      );
      if (duplicate >= 0) {
        next[duplicate] = copy;
      } else {
        next.add(copy);
      }
    }
    // Normalize after inserting or editing: changing an exclusion into a
    // singleton must remove the old singleton too. Exclusions remain additive.
    if (filter.scope.singletonFilters ||
        filter.singleIdentifier ||
        filter.kind == GlobalSearchFilterKind.choice) {
      final key = token.split('=').first;
      next.removeWhere((item) {
        if (identical(item, copy)) return false;
        if (!filter.scope.isCore || !filter.scope.singletonFilters) {
          return item.filterId == copy.filterId;
        }
        if (['exclude_groups', 'exclude_usernames'].contains(key)) return false;
        return globalSearchConditionToken(
              item,
              capabilities: capabilities,
              username: capabilities.username,
            ).split('=').first ==
            key;
      });
    }
    if (next.length > 30) {
      throw FormatException(appL10n.useAtMost30Conditions);
    }
    _banks[filter.scope] = List.unmodifiable(next);
    _scope = filter.scope;
    _schedule();
  }

  void removeCondition(int index) {
    _pendingContext = null;
    if (index < 0 || index >= conditions.length) return;
    _banks[scope] = List.unmodifiable(conditions.toList()..removeAt(index));
    _schedule();
  }

  void clearConditions() {
    _pendingContext = null;
    if (conditions.isEmpty) return;
    _banks[scope] = const [];
    _schedule();
  }

  /// Clears the completed session's filters, ordering and opening context.
  void clearAllConditions() {
    _context = null;
    _pendingContext = null;
    final ordered = _orders.isNotEmpty;
    _orders.clear();
    _ascending.clear();
    if (!ordered && _banks.values.every((conditions) => conditions.isEmpty)) {
      return;
    }
    _banks.clear();
    _schedule();
  }

  /// Applies the visible surface's defaults once when search opens.
  void setContext(GlobalSearchContext? context) {
    if (_disposed) return;
    final previous = _context;
    _context = context;
    _pendingContext = null;
    if (context != null && !scopes.contains(context.scope)) {
      if (capabilities.eligible(context.scope)) {
        _pendingContext = context;
      }
      context = null;
    }
    final condition = context?.condition;
    var changed = false;
    for (final bank in {previous?.scope, context?.scope}.nonNulls) {
      final held = conditionsFor(bank);
      final next = held
          .where(
            (item) =>
                !(previous?.scope == bank &&
                    item.filterId == previous?.condition?.filterId) &&
                !(context?.scope == bank &&
                    item.filterId == condition?.filterId),
          )
          .toList();
      if (context?.scope == bank && condition != null) next.add(condition);
      String token(GlobalSearchCondition item) => globalSearchConditionToken(
        item,
        capabilities: capabilities,
        username: capabilities.username,
      );
      if (!listEquals(held.map(token).toList(), next.map(token).toList())) {
        _banks[bank] = List.unmodifiable(next);
        changed = true;
      }
    }
    final label = context?.label;
    if (condition != null && label != null) {
      final labels = _choiceLabels.putIfAbsent(condition.filterId, () => {});
      if (labels[condition.text]?.label != label) {
        labels[condition.text] = GlobalSearchFilterChoice(
          value: condition.text,
          label: label,
        );
        changed = true;
      }
    }
    if (context != null && scope != context.scope) {
      _scope = context.scope;
      changed = true;
    }
    if (changed) _schedule();
  }

  void setOrder(String value, {bool? ascending}) {
    if (!orders.any((item) => item.value == value)) return;
    _orders[scope] = value;
    if (ascending != null && canOrderAscending) _ascending[scope] = ascending;
    _schedule();
  }

  void setDisplayProperty(GlobalSearchDisplayProperty property, bool enabled) {
    if (enabled) {
      _properties.add(property);
    } else {
      _properties.remove(property);
    }
    _notify();
  }

  void submit() {
    if (_disposed) return;
    try {
      final expression = parseGlobalSearchExpression(
        query,
        scope,
        capabilities,
      );
      if (expression.conditions.isNotEmpty || expression.order != null) {
        if (scope == GlobalSearchScope.all) _scope = GlobalSearchScope.forum;
        _query = expression.query;
        final next = [...conditions];
        for (final condition in expression.conditions) {
          final token = globalSearchConditionToken(
            condition,
            capabilities: capabilities,
            username: capabilities.username,
          );
          if (!next.any(
            (item) =>
                globalSearchConditionToken(
                  item,
                  capabilities: capabilities,
                  username: capabilities.username,
                ) ==
                token,
          )) {
            next.add(condition);
          }
        }
        _banks[scope] = List.unmodifiable(next);
        if (expression.order != null) _orders[scope] = expression.order!;
      }
      _remember();
      _schedule(immediate: true);
    } on FormatException catch (exception) {
      _revision++;
      _debounce?.cancel();
      _queued = null;
      _cancelSearches();
      _error = exception.message;
      _phase = GlobalSearchPhase.failed;
      _notify();
    }
  }

  void useRecentSearch(String value) {
    _pendingContext = null;
    final saved = _recentStates[value];
    if (saved != null && scopes.contains(saved.scope)) {
      _scope = saved.scope;
      _query = saved.query;
      _banks[scope] = List.unmodifiable(saved.conditions);
      _orders[scope] = saved.order;
      _ascending[scope] = saved.ascending;
      _sanitize();
    } else {
      // A server history entry is a complete core search expression, not an
      // amendment to the retained forum bank from a different search.
      _banks[GlobalSearchScope.forum] = const [];
      _orders.remove(GlobalSearchScope.forum);
      _ascending.remove(GlobalSearchScope.forum);
      _scope = GlobalSearchScope.all;
      _query = value;
    }
    submit();
  }

  void _remember() {
    if (!capabilities.authenticated || !capabilities.logSearchQueries) return;
    if (_request().query.trim().isEmpty) return;
    final term = globalSearchTerm(_request()).trim();
    if (term.isEmpty) return;
    _removedRecent.remove(term);
    _saveRemovedRecent();
    _localRecent = List.unmodifiable({term, ...recentSearches}.take(5));
    _recentStates[term] = _request();
    _recentStates.removeWhere((key, _) => !_localRecent.contains(key));
    _historyRevision++;
    _notify();
  }

  void rememberSearch() => _remember();

  GlobalSearchExpression recentExpression(String term) {
    final saved = _recentStates[term];
    if (saved != null) {
      return GlobalSearchExpression(
        saved.query,
        saved.conditions,
        saved.scope == GlobalSearchScope.forum && saved.order != 'relevance'
            ? saved.order
            : null,
      );
    }
    try {
      return parseGlobalSearchExpression(
        term,
        GlobalSearchScope.all,
        capabilities,
      );
    } on FormatException {
      return GlobalSearchExpression(term, const [], null);
    }
  }

  void removeRecentSearch(String term) {
    _removedRecent.add(term);
    _saveRemovedRecent();
    _localRecent = List.unmodifiable(
      _localRecent.where((value) => value != term),
    );
    _recentStates.remove(term);
    _historyRevision++;
    _notify();
  }

  Future<void> clearHistory() async {
    final site = siteUrl, lease = _lease, epoch = _configuration;
    final previous = _localRecent, wasCleared = _historyCleared;
    final historyRevision = ++_historyRevision;
    _error = null;
    _localRecent = const [];
    _historyCleared = true;
    _notify();
    if (site == null || lease == null || !capabilities.authenticated) return;
    bool current() => !_disposed && lease.isCurrent && epoch == _configuration;
    try {
      final key = await credentials.apiKeyFor(site);
      if (key == null || !current()) return;
      final client = await credentials.clientId();
      if (!current()) return;
      await api.clearRecentSearches(
        siteUrl: site,
        apiKey: key,
        clientId: client,
      );
    } catch (_) {
      if (!current()) return;
      if (historyRevision != _historyRevision) return;
      _localRecent = previous;
      _historyCleared = wasCleared;
      _error = appL10n.recentSearchesCouldNotBeClearedPleaseTryAgain;
      _notify();
    }
  }

  Future<void> recordSelection(GlobalSearchResult result) async {
    if (!results.any((item) => identical(item, result))) return;
    _remember();
    final site = siteUrl, lease = _lease, epoch = _configuration;
    if (site == null || lease == null || !capabilities.logSearchQueries) return;
    bool current() => !_disposed && lease.isCurrent && epoch == _configuration;
    try {
      final key = await credentials.apiKeyFor(site);
      if (key == null || !current()) return;
      final client = await credentials.clientId();
      if (!current()) return;
      await api.logClick(
        siteUrl: site,
        apiKey: key,
        clientId: client,
        result: result,
      );
    } catch (_) {
      /* Selection succeeds even if analytics are unavailable. */
    }
  }

  Future<List<GlobalSearchFilterChoice>> lookupChoices(
    GlobalSearchFilter filter,
    String term,
  ) async {
    final site = siteUrl, lease = _lease, epoch = _configuration;
    if (site == null ||
        lease == null ||
        !globalSearchFilterAvailable(filter, capabilities)) {
      return const [];
    }
    bool current() => !_disposed && lease.isCurrent && epoch == _configuration;
    final key = await credentials.apiKeyFor(site);
    if (!current()) return const [];
    final client = key == null ? null : await credentials.clientId();
    if (!current()) return const [];
    final values = await api.lookupChoices(
      capabilities: capabilities,
      siteUrl: site,
      apiKey: key,
      clientId: client,
      filter: filter,
      term: term,
    );
    if (!current()) return const [];
    if (filter.id == 'tags') {
      for (final choice in values) {
        _tagChoices.remove(choice.value);
        _tagChoices[choice.value] = choice;
      }
      while (_tagChoices.length > 512) {
        _tagChoices.remove(_tagChoices.keys.first);
      }
    }
    final ordered = values.toList();
    if (filter.lookup == GlobalSearchLookup.users) {
      ordered.sort((a, b) {
        final mine = a.value == capabilities.username
            ? -1
            : b.value == capabilities.username
            ? 1
            : 0;
        return mine != 0
            ? mine
            : a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    }
    _rememberChoices(filter.id, ordered);
    return ordered;
  }

  Future<GlobalSearchCategoryPage> lookupCategoryChoices(
    String term, {
    int page = 1,
  }) async {
    final site = siteUrl, lease = _lease, epoch = _configuration;
    if (site == null || lease == null) return const GlobalSearchCategoryPage();
    bool current() => !_disposed && lease.isCurrent && epoch == _configuration;
    final key = await credentials.apiKeyFor(site);
    if (!current()) return const GlobalSearchCategoryPage();
    final client = key == null ? null : await credentials.clientId();
    if (!current()) return const GlobalSearchCategoryPage();
    final result = await api.lookupCategoryChoices(
      siteUrl: site,
      apiKey: key,
      clientId: client,
      term: term,
      page: page,
    );
    if (!current()) return const GlobalSearchCategoryPage();
    _rememberChoices('category', result.choices);
    return result;
  }

  void _rememberChoices(
    String filterId,
    List<GlobalSearchFilterChoice> values,
  ) {
    final labels = _choiceLabels.putIfAbsent(filterId, () => {});
    var changed = false;
    for (final choice in values) {
      if (labels[choice.value] != choice) changed = true;
      labels.remove(choice.value);
      labels[choice.value] = choice;
    }
    final selected = {
      for (final bank in _banks.values)
        for (final condition in bank)
          if (condition.filterId == filterId) ...condition.value,
    };
    for (final key in labels.keys.toList()) {
      if (labels.length <= 512) break;
      if (!selected.contains(key)) labels.remove(key);
    }
    if (changed) _notify();
  }

  void retry() => _schedule(immediate: true);

  void loadMore() {
    if (_disposed ||
        !_hasMore ||
        _loadingMore ||
        _phase == GlobalSearchPhase.loading) {
      return;
    }
    _loadingMore = true;
    _error = null;
    _notify();
    _dispatch(_revision, append: true);
  }

  GlobalSearchRequest _request({bool append = false}) {
    GlobalSearchExpression parsed;
    try {
      parsed = parseGlobalSearchExpression(wordsQuery, scope, capabilities);
    } on FormatException {
      parsed = GlobalSearchExpression(wordsQuery, const [], null);
    }
    final effectiveScope =
        scope == GlobalSearchScope.all &&
            (parsed.conditions.isNotEmpty || parsed.order != null)
        ? GlobalSearchScope.forum
        : scope;
    final merged = conditions.toList();
    for (final condition in parsed.conditions) {
      merged.removeWhere((item) => item.filterId == condition.filterId);
      merged.add(condition);
    }
    return GlobalSearchRequest(
      scope: effectiveScope,
      query: parsed.query.trim(),
      capabilities: capabilities,
      conditions: merged,
      order: parsed.order ?? order,
      ascending: ascending,
      page: append ? _page + 1 : 0,
      offset: append ? _offset : 0,
      contextTopicId: _contextTopicId,
      contextTopicTitle: _contextTopicTitle,
    );
  }

  bool get _hasInput =>
      wordsQuery.trim().isNotEmpty ||
      conditions.isNotEmpty ||
      scope == GlobalSearchScope.forum && order != 'relevance';
  bool get _tooShort {
    if (query.trim().isEmpty ||
        query.trim().length >= capabilities.minimumLength ||
        conditions.isNotEmpty ||
        ![GlobalSearchScope.all, GlobalSearchScope.forum].contains(scope)) {
      return false;
    }
    // Discourse accepts a short advanced expression without ordinary words.
    try {
      final parsed = parseGlobalSearchExpression(query, scope, capabilities);
      if (parsed.conditions.isNotEmpty || parsed.order != null) return false;
    } on FormatException {
      /* The server error remains a normal invalid query. */
    }
    return true;
  }

  void _schedule({bool immediate = false}) {
    if (_disposed) return;
    _debounce?.cancel();
    _queued = null;
    final revision = ++_revision;
    _cancelSearches();
    _page = 0;
    _offset = 0;
    _loadingMore = false;
    _hasMore = false;
    _error = null;
    _sections = const [];
    if (siteUrl == null || !_hasInput) {
      _phase = GlobalSearchPhase.idle;
    } else if (query.length > 2048 ||
        globalSearchTerm(_request()).length > 2048) {
      _phase = GlobalSearchPhase.failed;
      _error = appL10n.searchesCanBeAtMost2048Characters;
    } else if (_tooShort) {
      _phase = GlobalSearchPhase.tooShort;
    } else {
      _phase = GlobalSearchPhase.loading;
      if (immediate) {
        _dispatch(revision);
      } else {
        _debounce = Timer(debounceDuration, () => _dispatch(revision));
      }
    }
    _notify();
  }

  void _dispatch(int revision, {bool append = false}) {
    if (_disposed || revision != _revision) return;
    final site = siteUrl, lease = _lease;
    if (site == null || lease == null || !lease.isCurrent) return;
    final active = _inFlight.putIfAbsent(lease.session, () => {});
    if (active.length >= 2) {
      _queued = () => _dispatch(revision, append: append);
      return;
    }
    final request = _request(append: append);
    final abort = Completer<void>();
    active.add(abort);
    unawaited(_execute(site, lease, revision, request, append, abort));
  }

  void _cancelSearches() {
    for (final active in _inFlight.values) {
      for (final abort in active) {
        if (!abort.isCompleted) abort.complete();
      }
    }
  }

  Future<void> _execute(
    String site,
    SiteLease lease,
    int revision,
    GlobalSearchRequest request,
    bool append,
    Completer<void> abort,
  ) async {
    bool current() =>
        !_disposed &&
        lease.isCurrent &&
        revision == _revision &&
        site == siteUrl;
    try {
      final key = await credentials.apiKeyFor(site);
      if (!current()) return;
      final client = key == null ? null : await credentials.clientId();
      if (!current()) return;
      final page = await api.search(
        siteUrl: site,
        apiKey: key,
        clientId: client,
        request: request,
        abortTrigger: abort.future,
      );
      if (!current()) return;
      if (append) {
        final all = <GlobalSearchScope, GlobalSearchSection>{
          for (final s in _sections) s.scope: s,
        };
        for (final section in page.sections) {
          final previous =
              all[section.scope]?.results ?? const <GlobalSearchResult>[];
          final rows = {
            for (final row in previous) row.id: row,
            for (final row in section.results) row.id: row,
          };
          all[section.scope] = GlobalSearchSection(
            scope: section.scope,
            results: List.unmodifiable(rows.values),
            hasMore: section.hasMore,
            error: section.error,
          );
        }
        _sections = List.unmodifiable(all.values);
      } else {
        _sections = List.unmodifiable(page.sections);
      }
      _page = request.page;
      _offset = request.offset + page.consumedCount;
      _hasMore = page.hasMore && (!append || page.consumedCount > 0);
      _loadingMore = false;
      if (page.groupMemberOrder != null || page.userOrders != null) {
        _capabilities = capabilities.copyWith(
          groupMemberOrder: page.groupMemberOrder,
          userOrders: page.userOrders,
        );
        _sanitize();
      }
      _error = _sections
          .where((s) => s.error != null)
          .map((s) => s.error)
          .firstOrNull;
      _phase = results.isNotEmpty
          ? GlobalSearchPhase.results
          : _error != null
          ? GlobalSearchPhase.failed
          : GlobalSearchPhase.empty;
      _notify();
    } catch (exception) {
      if (!current()) return;
      _error = GlobalSearchApi.failureMessage(exception);
      _phase = results.isEmpty
          ? GlobalSearchPhase.failed
          : GlobalSearchPhase.results;
      _loadingMore = false;
      _notify();
    } finally {
      final active = _inFlight[lease.session];
      active?.remove(abort);
      if (active?.isEmpty == true) {
        _inFlight.remove(lease.session);
      }
      final queued = _queued;
      _queued = null;
      if (!_disposed) queued?.call();
    }
  }

  void _recentChanged() => _notify();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _configuration++;
    _revision++;
    _debounce?.cancel();
    _queued = null;
    _cancelSearches();
    recentSource?.removeListener(_recentChanged);
    super.dispose();
  }
}
