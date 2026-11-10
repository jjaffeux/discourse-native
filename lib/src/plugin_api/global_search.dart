import 'global_search_models.dart';

export 'global_search_filters.dart';
export 'global_search_models.dart';

abstract interface class GlobalSearchPlugin {
  List<GlobalSearchContribution> get searchContributions;
}

/// Installation snapshots the schema while retaining the contributor's behavior.
final class InstalledGlobalSearchContribution extends GlobalSearchContribution {
  InstalledGlobalSearchContribution(GlobalSearchContribution source)
    : _source = source,
      filters = List.unmodifiable(source.filters.map(_freezeFilter)),
      scopes = List.unmodifiable(source.scopes.map(_freezeScope)),
      _orders = {
        for (final scope in [...GlobalSearchScope.values, ...source.scopes])
          scope: List.unmodifiable(source.orders(scope)),
      },
      super(source.owner);
  final GlobalSearchContribution _source;
  @override
  final List<GlobalSearchFilter> filters;
  @override
  final List<GlobalSearchScope> scopes;
  final Map<GlobalSearchScope, List<GlobalSearchOrder>> _orders;
  @override
  List<GlobalSearchOrder> orders(GlobalSearchScope scope) =>
      _orders[scope] ?? const [];
  @override
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  ) => _source.available(settings, user, authenticated);
  @override
  Future<GlobalSearchPage> search(
    GlobalSearchReadContext context,
    GlobalSearchRequest request,
  ) => _source.search(context, request);
  @override
  Future<List<GlobalSearchFilterChoice>> lookup(
    GlobalSearchReadContext context,
    GlobalSearchFilter filter,
    String term,
  ) => _source.lookup(context, filter, term);
}

GlobalSearchFilter _freezeFilter(GlobalSearchFilter value) =>
    GlobalSearchFilter(
      id: value.id,
      label: value.label,
      scope: _freezeScope(value.scope),
      kind: value.kind,
      icon: value.icon,
      group: value.group,
      operators: List.unmodifiable(value.operators),
      choices: List.unmodifiable(value.choices),
      token: value.token,
      opTokens: Map.unmodifiable(value.opTokens),
      placeholder: value.placeholder,
      help: value.help,
      optional: value.optional,
      lookup: value.lookup,
      singleIdentifier: value.singleIdentifier,
      rejectQuotes: value.rejectQuotes,
    );

GlobalSearchScope _freezeScope(GlobalSearchScope scope) => scope.isCore
    ? scope
    : GlobalSearchScope.plugin(
        owner: scope.owner,
        name: scope.name,
        label: scope.label,
        showAvatar: scope.showAvatar,
        singletonFilters: scope.singletonFilters,
        displayProperties: Set.unmodifiable(scope.displayProperties),
        layout: scope.layout,
      );
