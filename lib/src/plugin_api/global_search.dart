import 'package:discourse_native/l10n/strings.dart';
import '../shell/global_search_models.dart';

export '../shell/global_search_filters.dart';
export '../shell/global_search_models.dart';

enum GlobalSearchLookup { none, users, groups, contributed }

/// A bounded authenticated read; no credentials or concrete host escape.
final class GlobalSearchReadContext {
  const GlobalSearchReadContext({
    required this.siteUrl,
    required this.authenticated,
    required this.get,
  });
  final String siteUrl;
  final bool authenticated;
  final Future<Map<String, dynamic>> Function(String path) get;
}

abstract interface class GlobalSearchPlugin {
  List<GlobalSearchContribution> get searchContributions;
}

abstract class GlobalSearchContribution {
  const GlobalSearchContribution(this.owner);
  final String owner;
  List<GlobalSearchFilter> get filters => const [];
  List<GlobalSearchScope> get scopes => const [];
  List<GlobalSearchOrder> orders(GlobalSearchScope scope) => const [];
  bool available(
    Map<String, dynamic> settings,
    Map<String, dynamic> user,
    bool authenticated,
  );
  Future<GlobalSearchPage> search(
    GlobalSearchReadContext context,
    GlobalSearchRequest request,
  ) => Future.error(FormatException(appL10n.searchIsUnavailable));
  Future<List<GlobalSearchFilterChoice>> lookup(
    GlobalSearchReadContext context,
    GlobalSearchFilter filter,
    String term,
  ) async => const [];
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
      );
