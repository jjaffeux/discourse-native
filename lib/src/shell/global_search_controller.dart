import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../plugin_api/global_search.dart' show GlobalSearchLookup;
import 'global_search_api.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'recent_search_history.dart';

part 'global_search_execution.dart';

/// Owns a search session independently of the editor and its presentation.
/// Scope banks survive tab changes; requests only receive the active bank.
class GlobalSearchController extends ChangeNotifier {
  GlobalSearchController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    RecentSearchHistory? history,
    this.debounceDuration = const Duration(milliseconds: 350),
  }) : history =
           history ??
           RecentSearchHistory(
             api: api,
             credentials: credentials,
             lifecycle: lifecycle,
           ),
       _ownsHistory = history == null {
    _execution = _GlobalSearchExecution(
      api: api,
      credentials: credentials,
      currentSite: () => siteUrl,
      notify: _notify,
      updateCapabilities: (page) {
        _capabilities = capabilities.copyWith(
          groupMemberOrder: page.groupMemberOrder,
          userOrders: page.userOrders,
        );
        _sanitize();
      },
    );
    this.history.addListener(_notify);
  }

  final GlobalSearchApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final RecentSearchHistory history;
  final bool _ownsHistory;
  final Duration debounceDuration;
  String? _siteUrl;
  SiteLease? _lease;
  String _baseFingerprint = '';
  GlobalSearchCapabilities _capabilities = const GlobalSearchCapabilities();
  GlobalSearchScope _scope = GlobalSearchScope.all;
  GlobalSearchContext? _context, _pendingContext;
  String _query = '';
  AppLocalizations? _filterL10n;
  List<GlobalSearchFilter> _coreFilters = const [];
  _SearchQueryTail? _queryTail;

  GlobalSearchScope? _preferredScope;
  int? _contextTopicId;
  String? _contextTopicTitle;
  final _banks = <GlobalSearchScope, List<GlobalSearchCondition>>{};
  final _orders = <GlobalSearchScope, String>{};
  final _ascending = <GlobalSearchScope, bool>{};
  final _properties = {
    GlobalSearchDisplayProperty.excerpt,
    GlobalSearchDisplayProperty.category,
    GlobalSearchDisplayProperty.replies,
  };
  final _choiceLabels = <String, Map<String, GlobalSearchFilterChoice>>{};
  final _tagChoices = <String, GlobalSearchFilterChoice>{};
  final _choiceLookups =
      _PendingFilterLookups<
        (GlobalSearchCapabilities, String, String),
        List<GlobalSearchFilterChoice>
      >();
  final _categoryLookups =
      _PendingFilterLookups<
        (GlobalSearchCapabilities, String, int),
        GlobalSearchCategoryPage
      >();
  final _lookupAborts = <Completer<void>>{};
  late final _GlobalSearchExecution _execution;
  bool _disposed = false;
  int _configuration = 0;

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
  List<GlobalSearchFilter> get _filterDefinitions {
    final l10n = appL10n;
    if (!identical(_filterL10n, l10n)) {
      _coreFilters = globalSearchDefinitions(const GlobalSearchCapabilities());
      _filterL10n = l10n;
    }
    return [..._coreFilters, ...capabilities.contributedFilters];
  }

  _SearchQueryTail get _tail {
    final cached = _queryTail;
    if (cached != null && cached.query == query) return cached;
    final tail = query.endsWith(' ') ? '' : query.split(RegExp(r'\s+')).last;
    final colon = tail.indexOf(':');
    final key = colon < 0 ? null : tail.substring(0, colon);
    final boundary = query.lastIndexOf(RegExp(r'\s'));
    return _queryTail = (
      query: query,
      tail: tail,
      lowerTail: tail.toLowerCase(),
      key: key,
      lowerKey: key?.toLowerCase(),
      term: colon < 0 ? '' : tail.substring(colon + 1),
      prefix: query.substring(0, boundary < 0 ? 0 : boundary).trim(),
    );
  }

  List<GlobalSearchFilter> get availableFilters => List.unmodifiable([
    if (scope == GlobalSearchScope.all || scope == GlobalSearchScope.forum)
      globalSearchOrderFilter(capabilities),
    for (final filter in _filterDefinitions)
      if ((filter.scope ==
              (scope == GlobalSearchScope.all
                  ? GlobalSearchScope.forum
                  : scope)) &&
          globalSearchFilterAvailable(filter, capabilities))
        filter,
  ]);
  List<GlobalSearchOrder> get orders => globalSearchOrders(scope, capabilities);

  List<int> get orderedConditionIndices {
    final current = conditions;
    final indices = List.generate(current.length, (index) => index);
    if (indices.length < 2) return indices;
    final labels = {
      'order': globalSearchOrderFilter(capabilities).label.toLowerCase(),
    };
    for (final filter in _filterDefinitions) {
      labels.putIfAbsent(filter.id, () => filter.label.toLowerCase());
    }
    return indices..sort((a, b) {
      final compared = labels[current[a].filterId]!.compareTo(
        labels[current[b].filterId]!,
      );
      return compared == 0 ? a.compareTo(b) : compared;
    });
  }

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
    final ordered = _execution.sections.toList();
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
    final key = _tail.lowerKey;
    if (key == null) return null;
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

  String get stagedTerm => stagedFilter == null ? '' : _tail.term;
  String get stagedOperator {
    final filter = stagedFilter;
    if (filter == null) return 'is';
    final key = _tail.key;
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
    final tail = _tail.lowerTail;
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

  String get wordsQuery =>
      stagedFilter == null && hintedFilters.isEmpty ? query : _tail.prefix;

  void beginFilter(GlobalSearchFilter filter, {String value = ''}) {
    final tail = _tail.tail;
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
  GlobalSearchPhase get phase => _execution.phase;
  String? get error => _execution.error;
  bool get hasMore => _execution.hasMore;
  bool get loadingMore => _execution.loadingMore;
  List<String> get recentSearches => history.terms;

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
    _invalidateLookups();
    _tagChoices.clear();
    _baseFingerprint = capabilities.fingerprint;
    _siteUrl = siteUrl;
    _lease = lease;
    _capabilities = capabilities;
    history.configure(
      siteUrl: siteUrl,
      username: capabilities.username,
      authenticated: capabilities.authenticated,
      logSearchQueries: capabilities.logSearchQueries,
    );
    if (changedSite) {
      _query = '';
      _contextTopicId = null;
      _contextTopicTitle = null;
      _preferredScope = null;
      _scope = GlobalSearchScope.all;
      _banks.clear();
      _orders.clear();
      _ascending.clear();
      _choiceLabels.clear();
      _context = null;
      _pendingContext = null;
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
      final auth = await AccountRequestSession(
        site,
        lease,
      ).credentials(credentials);
      final key = auth.apiKey;
      if (!current()) return;
      final client = key == null ? null : auth.clientId;
      if (!current()) return;
      final loaded = await auth.run(
        () => api.capabilities(
          siteUrl: site,
          apiKey: key,
          clientId: client,
          base: base,
        ),
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
    _banks[filter.scope] = _normalizedConditions(
      conditionsFor(filter.scope),
      condition,
      index: scope == filter.scope ? index : null,
    );
    _scope = filter.scope;
    _schedule();
  }

  List<GlobalSearchCondition> _normalizedConditions(
    List<GlobalSearchCondition> current,
    GlobalSearchCondition condition, {
    int? index,
  }) {
    final filter = globalSearchFilter(condition.filterId, capabilities)!;
    final next = current.toList();
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
    if (index != null && index < next.length) {
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
    return List.unmodifiable(next);
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
        final target = scope == GlobalSearchScope.all
            ? GlobalSearchScope.forum
            : scope;
        var next = conditionsFor(target);
        for (final condition in expression.conditions) {
          next = _normalizedConditions(next, condition);
        }
        _banks[target] = next;
        _scope = target;
        _query = expression.query;
        if (expression.order != null) _orders[scope] = expression.order!;
      }
      _remember();
      _schedule(immediate: true);
    } on FormatException catch (exception) {
      _execution.failQuery(exception.message);
      _notify();
    }
  }

  void useRecentSearch(String value) {
    _pendingContext = null;
    final saved = history.savedRequest(value);
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

  void _remember() => history.remember(_request());

  void rememberSearch() => _remember();

  GlobalSearchExpression recentExpression(String term) {
    final saved = history.savedRequest(term);
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

  void removeRecentSearch(String term) => history.remove(term);

  Future<void> clearHistory() async {
    final epoch = _configuration;
    _execution.error = null;
    _notify();
    final outcome = await history.clear();
    if (_disposed ||
        epoch != _configuration ||
        outcome != RecentSearchClearOutcome.failed) {
      return;
    }
    _execution.error = appL10n.recentSearchesCouldNotBeClearedPleaseTryAgain;
    _notify();
  }

  Future<void> recordSelection(GlobalSearchResult result) async {
    if (!results.any((item) => identical(item, result))) return;
    _remember();
    final site = siteUrl, lease = _lease, epoch = _configuration;
    if (site == null || lease == null || !capabilities.logSearchQueries) return;
    bool current() => !_disposed && lease.isCurrent && epoch == _configuration;
    try {
      final auth = await AccountRequestSession(
        site,
        lease,
      ).credentials(credentials);
      final key = auth.apiKey;
      if (key == null || !current()) return;
      final client = auth.clientId;
      if (!current()) return;
      await auth.run(
        () => api.logClick(
          siteUrl: site,
          apiKey: key,
          clientId: client,
          result: result,
        ),
      );
    } catch (_) {
      /* Selection succeeds even if analytics are unavailable. */
    }
  }

  Future<List<GlobalSearchFilterChoice>> lookupChoices(
    GlobalSearchFilter filter,
    String term,
  ) {
    final query = filter.id == 'tags' ? term.trim() : term;
    return _choiceLookups.run((
      capabilities,
      filter.id,
      query,
    ), () => _lookupChoices(filter, query));
  }

  Future<List<GlobalSearchFilterChoice>> _lookupChoices(
    GlobalSearchFilter filter,
    String term,
  ) async {
    final site = siteUrl, lease = _lease, epoch = _configuration;
    if (_disposed ||
        site == null ||
        lease == null ||
        !globalSearchFilterAvailable(filter, capabilities)) {
      return const [];
    }
    final abort = Completer<void>();
    _lookupAborts.add(abort);
    bool current() => !_disposed && lease.isCurrent && epoch == _configuration;
    try {
      final auth = await AccountRequestSession(
        site,
        lease,
      ).credentials(credentials);
      final key = auth.apiKey;
      if (!current()) return const [];
      final client = key == null ? null : auth.clientId;
      if (!current()) return const [];
      final values = await auth.run(
        () => api.lookupChoices(
          capabilities: capabilities,
          siteUrl: site,
          apiKey: key,
          clientId: client,
          filter: filter,
          term: term,
          abortTrigger: abort.future,
        ),
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
    } catch (_) {
      if (!current()) return const [];
      rethrow;
    } finally {
      _lookupAborts.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<GlobalSearchCategoryPage> lookupCategoryChoices(
    String term, {
    int page = 1,
  }) => _categoryLookups.run((
    capabilities,
    term.trim(),
    page,
  ), () => _lookupCategoryChoices(term.trim(), page: page));

  Future<GlobalSearchCategoryPage> _lookupCategoryChoices(
    String term, {
    required int page,
  }) async {
    final site = siteUrl, lease = _lease, epoch = _configuration;
    if (_disposed || site == null || lease == null) {
      return const GlobalSearchCategoryPage();
    }
    bool current() => !_disposed && lease.isCurrent && epoch == _configuration;
    try {
      final auth = await AccountRequestSession(
        site,
        lease,
      ).credentials(credentials);
      final key = auth.apiKey;
      if (!current()) return const GlobalSearchCategoryPage();
      final client = key == null ? null : auth.clientId;
      if (!current()) return const GlobalSearchCategoryPage();
      final result = await auth.run(
        () => api.lookupCategoryChoices(
          siteUrl: site,
          apiKey: key,
          clientId: client,
          term: term,
          page: page,
        ),
      );
      if (!current()) return const GlobalSearchCategoryPage();
      _rememberChoices('category', result.choices);
      return result;
    } catch (_) {
      if (!current()) return const GlobalSearchCategoryPage();
      rethrow;
    }
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

  void loadMore() => _execution.loadMore();

  GlobalSearchRequest _request({int page = 0, int offset = 0}) {
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
      page: page,
      offset: offset,
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
    _execution.reset();
    if (siteUrl == null || !_hasInput) {
      _execution.phase = GlobalSearchPhase.idle;
    } else if (query.length > 2048 ||
        globalSearchTerm(_request()).length > 2048) {
      _execution.phase = GlobalSearchPhase.failed;
      _execution.error = appL10n.searchesCanBeAtMost2048Characters;
    } else if (_tooShort) {
      _execution.phase = GlobalSearchPhase.tooShort;
    } else {
      _execution.start(
        siteUrl!,
        _lease!,
        (page, offset) => _request(page: page, offset: offset),
        delay: immediate ? null : debounceDuration,
      );
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _invalidateLookups() {
    for (final abort in _lookupAborts) {
      if (!abort.isCompleted) abort.complete();
    }
    _lookupAborts.clear();
    _choiceLookups.clear();
    _categoryLookups.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _configuration++;
    _invalidateLookups();
    _execution.dispose();
    history.removeListener(_notify);
    if (_ownsHistory) history.dispose();
    super.dispose();
  }
}

class _PendingFilterLookups<K, V> {
  final _pending = <K, Future<V>>{};

  Future<V> run(K key, Future<V> Function() load) {
    final existing = _pending[key];
    if (existing != null) return existing;
    late final Future<V> future;
    future = Future<V>.sync(load).whenComplete(() {
      if (identical(_pending[key], future)) {
        final _ = _pending.remove(key);
      }
    });
    _pending[key] = future;
    if (_pending.length > 32) {
      final _ = _pending.remove(_pending.keys.first);
    }
    return future;
  }

  void clear() => _pending.clear();
}

typedef _SearchQueryTail = ({
  String query,
  String tail,
  String lowerTail,
  String? key,
  String? lowerKey,
  String term,
  String prefix,
});
