import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
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
  }) {
    recentSource?.addListener(_recentChanged);
  }

  final GlobalSearchApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final ShellSearchController? recentSource;
  final Duration debounceDuration;
  String? _siteUrl;
  SiteLease? _lease;
  String _baseFingerprint = '';
  GlobalSearchCapabilities _capabilities = const GlobalSearchCapabilities();
  GlobalSearchScope _scope = GlobalSearchScope.all;
  String _query = '';
  final _banks = <GlobalSearchScope, List<GlobalSearchCondition>>{};
  final _orders = <GlobalSearchScope, String>{};
  final _ascending = <GlobalSearchScope, bool>{};
  final _properties = GlobalSearchDisplayProperty.values.toSet();
  List<GlobalSearchSection> _sections = const [];
  List<String> _localRecent = const [];
  final _recentStates = <String, GlobalSearchRequest>{};
  final _choiceLabels = <String, Map<String, String>>{};
  int _historyRevision = 0;
  bool _historyCleared = false;
  GlobalSearchPhase _phase = GlobalSearchPhase.idle;
  String? _error;
  bool _hasMore = false, _loadingMore = false, _disposed = false;
  int _revision = 0, _configuration = 0, _page = 0, _offset = 0;
  final _inFlight = <Object, int>{};
  bool _compact = false;
  Timer? _debounce;
  VoidCallback? _queued;

  String? get siteUrl => _siteUrl;
  bool get compact => _compact;
  void setCompact(bool value) {
    _compact = value;
    _notify();
  }

  /// Display text for a stable filter value returned in this site session.
  String? choiceLabel(String filterId, String value) =>
      _choiceLabels[filterId]?[value];

  String get query => _query;
  GlobalSearchScope get scope => _scope;
  GlobalSearchCapabilities get capabilities => _capabilities;
  List<GlobalSearchScope> get scopes => List.unmodifiable([
    for (final value in GlobalSearchScope.values)
      if (value != GlobalSearchScope.chat || capabilities.chat) value,
  ]);
  List<GlobalSearchCondition> conditionsFor(GlobalSearchScope value) =>
      value == GlobalSearchScope.all ? const [] : _banks[value] ?? const [];
  List<GlobalSearchCondition> get conditions => conditionsFor(scope);
  List<GlobalSearchFilter> get availableFilters => List.unmodifiable([
    for (final filter in globalSearchFilters)
      if ((scope == GlobalSearchScope.all || filter.scope == scope) &&
          globalSearchFilterAvailable(filter, capabilities))
        filter,
  ]);
  List<GlobalSearchOrder> get orders => globalSearchOrders(scope, capabilities);
  String get order => _orders[scope] ?? orders.first.value;
  bool get ascending =>
      _ascending[scope] ??
      (scope == GlobalSearchScope.groups ||
          scope == GlobalSearchScope.users && order == 'username');
  bool get canOrderAscending =>
      (scope == GlobalSearchScope.groups && capabilities.groupDirectory) ||
      (scope == GlobalSearchScope.users && capabilities.userDirectory);
  Set<GlobalSearchDisplayProperty> get properties =>
      Set.unmodifiable(_properties);
  List<GlobalSearchSection> get sections => _sections;
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
      }.take(5),
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
    _baseFingerprint = capabilities.fingerprint;
    _siteUrl = siteUrl;
    _lease = lease;
    _capabilities = capabilities;
    if (changedSite) {
      _query = '';
      _scope = GlobalSearchScope.all;
      _banks.clear();
      _orders.clear();
      _ascending.clear();
      _localRecent = const [];
      _recentStates.clear();
      _choiceLabels.clear();
      _historyRevision++;
      _historyCleared = false;
    }
    _sanitize();
    _schedule();
    if (siteUrl != null && lease != null) {
      unawaited(
        _loadCapabilities(siteUrl, lease, _configuration, capabilities),
      );
    }
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
      final client = await credentials.clientId();
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
    for (final value in GlobalSearchScope.values) {
      final allowed = globalSearchOrders(value, capabilities);
      if (!allowed.any((item) => item.value == _orders[value])) {
        _orders.remove(value);
      }
    }
    if (scope == GlobalSearchScope.chat && !capabilities.chat) {
      _scope = GlobalSearchScope.all;
    }
  }

  void setQuery(String value) {
    if (_disposed || _query == value) return;
    _query = value;
    _schedule();
  }

  void setScope(GlobalSearchScope value) {
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
    final validation = validateGlobalSearchCondition(condition, capabilities);
    if (validation != null) throw FormatException(validation);
    final filter = globalSearchFilter(condition.filterId)!;
    final next = conditionsFor(filter.scope).toList();
    final copy = GlobalSearchCondition(
      filterId: condition.filterId,
      operator: condition.operator,
      value: List.unmodifiable(condition.value),
    );
    final token = globalSearchConditionToken(
      copy,
      username: capabilities.username,
    );
    if (index != null && scope == filter.scope && index < next.length) {
      next[index] = copy;
    } else {
      final duplicate = next.indexWhere(
        (item) =>
            globalSearchConditionToken(item, username: capabilities.username) ==
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
    if ([
      GlobalSearchScope.users,
      GlobalSearchScope.groups,
      GlobalSearchScope.chat,
    ].contains(filter.scope)) {
      final key = token.split('=').first;
      next.removeWhere((item) {
        if (identical(item, copy)) return false;
        if (filter.scope == GlobalSearchScope.chat) {
          return item.filterId == copy.filterId;
        }
        if (['exclude_groups', 'exclude_usernames'].contains(key)) return false;
        return globalSearchConditionToken(
              item,
              username: capabilities.username,
            ).split('=').first ==
            key;
      });
    }
    if (next.length > 30) {
      throw const FormatException('Use at most 30 conditions.');
    }
    _banks[filter.scope] = List.unmodifiable(next);
    _scope = filter.scope;
    _schedule();
  }

  void removeCondition(int index) {
    if (index < 0 || index >= conditions.length) return;
    _banks[scope] = List.unmodifiable(conditions.toList()..removeAt(index));
    _schedule();
  }

  void clearConditions() {
    if (conditions.isEmpty) return;
    _banks[scope] = const [];
    _schedule();
  }

  void setTopicContext(int? topicId, {bool selectForum = false}) {
    if (_disposed || topicId != null && topicId < 2) return;
    final previous = conditionsFor(GlobalSearchScope.forum);
    final topics = previous.where((item) => item.filterId == 'topicId');
    final nextScope = topicId != null || selectForum
        ? GlobalSearchScope.forum
        : scope;
    final sameTopic = topicId == null
        ? topics.isEmpty
        : topics.length == 1 && topics.single.text == '$topicId';
    if (scope == nextScope && sameTopic) return;
    final next = previous.where((item) => item.filterId != 'topicId').toList();
    if (topicId != null) {
      next.add(GlobalSearchCondition(filterId: 'topicId', value: ['$topicId']));
    }
    _scope = nextScope;
    _banks[GlobalSearchScope.forum] = List.unmodifiable(next);
    _schedule();
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
            username: capabilities.username,
          );
          if (!next.any(
            (item) =>
                globalSearchConditionToken(
                  item,
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
      _error = exception.message;
      _phase = GlobalSearchPhase.failed;
      _notify();
    }
  }

  void useRecentSearch(String value) {
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
    final term = globalSearchTerm(_request()).trim();
    if (term.isEmpty) return;
    _localRecent = List.unmodifiable({term, ...recentSearches}.take(5));
    _recentStates[term] = _request();
    _recentStates.removeWhere((key, _) => !_localRecent.contains(key));
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
      _error = 'Recent searches could not be cleared. Please try again.';
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
    final client = await credentials.clientId();
    if (!current()) return const [];
    final values = await api.lookupChoices(
      siteUrl: site,
      apiKey: key,
      clientId: client,
      filter: filter,
      term: term,
    );
    if (!current()) return const [];
    final labels = _choiceLabels.putIfAbsent(
      filter.id,
      () => <String, String>{},
    );
    var changed = false;
    for (final choice in values) {
      if (labels[choice.value] != choice.label) changed = true;
      labels.remove(choice.value);
      labels[choice.value] = choice.label;
    }
    // Search suggestions can be explored indefinitely without an unbounded cache.
    while (labels.length > 512) {
      labels.remove(labels.keys.first);
    }
    if (changed) _notify();
    return values;
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

  GlobalSearchRequest _request({bool append = false}) => GlobalSearchRequest(
    scope: scope,
    query: query.trim(),
    capabilities: capabilities,
    conditions: conditions,
    order: order,
    ascending: ascending,
    page: append ? _page + 1 : 0,
    offset: append ? _offset : 0,
  );

  bool get _hasInput => query.trim().isNotEmpty || conditions.isNotEmpty;
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
      _error = 'Searches can be at most 2048 characters.';
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
    if ((_inFlight[lease.session] ?? 0) >= 2) {
      _queued = () => _dispatch(revision, append: append);
      return;
    }
    final request = _request(append: append);
    _inFlight[lease.session] = (_inFlight[lease.session] ?? 0) + 1;
    unawaited(_execute(site, lease, revision, request, append));
  }

  Future<void> _execute(
    String site,
    SiteLease lease,
    int revision,
    GlobalSearchRequest request,
    bool append,
  ) async {
    bool current() =>
        !_disposed &&
        lease.isCurrent &&
        revision == _revision &&
        site == siteUrl;
    try {
      final key = await credentials.apiKeyFor(site);
      if (!current()) return;
      final client = await credentials.clientId();
      if (!current()) return;
      final page = await api.search(
        siteUrl: site,
        apiKey: key,
        clientId: client,
        request: request,
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
      final remaining = (_inFlight[lease.session] ?? 1) - 1;
      if (remaining == 0) {
        _inFlight.remove(lease.session);
      } else {
        _inFlight[lease.session] = remaining;
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
    recentSource?.removeListener(_recentChanged);
    super.dispose();
  }
}
