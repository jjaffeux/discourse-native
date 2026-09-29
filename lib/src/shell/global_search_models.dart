import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../models/discourse_user.dart';
import '../models/search_results.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../plugin_api/global_search.dart';

@immutable
final class GlobalSearchScope {
  const GlobalSearchScope.plugin({
    required this.owner,
    required this.name,
    required String this._label,
    this.showAvatar = false,
    this.singletonFilters = false,
    this.displayProperties = const {GlobalSearchDisplayProperty.excerpt},
  });
  const GlobalSearchScope._core(
    this.name, {
    this.showAvatar = false,
    this.singletonFilters = false,
  }) : _label = null,
       owner = 'core',
       displayProperties = const {GlobalSearchDisplayProperty.excerpt};
  static const all = GlobalSearchScope._core('all');
  static const forum = GlobalSearchScope._core('forum');
  static const users = GlobalSearchScope._core(
    'users',
    showAvatar: true,
    singletonFilters: true,
  );
  static const groups = GlobalSearchScope._core(
    'groups',
    singletonFilters: true,
  );
  static const values = [all, forum, users, groups];
  final String owner, name;
  final String? _label;
  String get label =>
      _label ??
      switch (name) {
        'all' => appL10n.all,
        'forum' => appL10n.topicsPosts,
        'users' => appL10n.users,
        'groups' => appL10n.groups,
        _ => name,
      };
  final bool showAvatar, singletonFilters;
  final Set<GlobalSearchDisplayProperty> displayProperties;
  bool get isCore => owner == 'core';
  String get keyName => isCore ? name : '$owner/$name';
  @override
  bool operator ==(Object other) =>
      other is GlobalSearchScope && other.owner == owner && other.name == name;
  @override
  int get hashCode => Object.hash(owner, name);
}

enum GlobalSearchPhase { idle, tooShort, loading, results, empty, failed }

enum GlobalSearchDisplayProperty {
  excerpt,
  category,
  tags,
  author,
  likes,
  replies,
}

enum GlobalSearchFilterKind { choice, multi, text, number, date }

/// Defaults supplied by the visible surface when global search opens.
@immutable
class GlobalSearchContext {
  const GlobalSearchContext({required this.scope, this.condition, this.label});

  final GlobalSearchScope scope;
  final GlobalSearchCondition? condition;
  final String? label;
}

@immutable
class GlobalSearchCapabilities {
  const GlobalSearchCapabilities({
    this.contributions = const [],
    this.enabledContributions = const {},
    this.authenticated = false,
    this.username,
    this.tagging = true,
    this.userDirectory = true,
    this.groupDirectory = true,
    this.staff = false,
    this.admin = false,
    this.whispers = false,
    this.unlisted = false,
    this.minimumLength = 3,
    this.logSearchQueries = true,
    this.userOrders = const ['username'],
    this.groupMemberOrder = false,
  });
  factory GlobalSearchCapabilities.fromSite(
    SiteConfig config,
    DiscourseUser? user, {
    List<GlobalSearchContribution> contributions = const [],
  }) => GlobalSearchCapabilities(
    contributions: contributions,
    authenticated: user != null,
    username: user?.username,
    tagging: config.taggingEnabled,
    userDirectory: config.userDirectoryEnabled,
    groupDirectory:
        config.groupDirectoryEnabled ||
        user?.staff == true ||
        user?.admin == true,
    staff: user?.staff == true || user?.admin == true,
    admin: user?.admin == true,
    whispers: user?.whisperer == true,
    unlisted: user?.staff == true || user?.admin == true,
    minimumLength: config.minSearchTermLength,
    logSearchQueries: config.logSearchQueries,
  );
  final bool authenticated,
      tagging,
      userDirectory,
      groupDirectory,
      staff,
      admin,
      whispers,
      unlisted,
      logSearchQueries,
      groupMemberOrder;
  final List<GlobalSearchContribution> contributions;
  final Set<String> enabledContributions;
  List<GlobalSearchScope> get scopes => [
    ...GlobalSearchScope.values,
    for (final contribution in contributions)
      if (enabledContributions.contains(contribution.owner))
        ...contribution.scopes,
  ];
  List<GlobalSearchFilter> get contributedFilters => [
    for (final contribution in contributions) ...contribution.filters,
  ];
  bool eligible(GlobalSearchScope scope) =>
      contributions.any((c) => c.scopes.contains(scope));
  final String? username;
  final int minimumLength;
  final List<String> userOrders;
  String get fingerprint => [
    ...contributions.map((c) => c.owner),
    ...(enabledContributions.toList()..sort()),
    authenticated,
    username,
    tagging,
    userDirectory,
    groupDirectory,
    staff,
    admin,
    whispers,
    unlisted,
    minimumLength,
    logSearchQueries,
    ...userOrders,
    groupMemberOrder,
  ].join('|');
  GlobalSearchCapabilities copyWith({
    Set<String>? enabledContributions,
    bool? unlisted,
    List<String>? userOrders,
    bool? groupMemberOrder,
  }) => GlobalSearchCapabilities(
    contributions: contributions,
    enabledContributions: enabledContributions ?? this.enabledContributions,
    authenticated: authenticated,
    username: username,
    tagging: tagging,
    userDirectory: userDirectory,
    groupDirectory: groupDirectory,
    staff: staff,
    admin: admin,
    whispers: whispers,
    unlisted: unlisted ?? this.unlisted,
    minimumLength: minimumLength,
    logSearchQueries: logSearchQueries,
    userOrders: userOrders ?? this.userOrders,
    groupMemberOrder: groupMemberOrder ?? this.groupMemberOrder,
  );
}

@immutable
class GlobalSearchFilterOperator {
  const GlobalSearchFilterOperator(this.value, this.label);
  final String value, label;
}

@immutable
class GlobalSearchFilterChoice {
  const GlobalSearchFilterChoice({
    required this.value,
    required this.label,
    this.token,
    this.topicCount,
    this.category,
    this.parentLabel,
  });
  final String value, label;
  final String? token;
  final int? topicCount;
  final TopicCategory? category;
  final String? parentLabel;
}

@immutable
class GlobalSearchCategoryPage {
  const GlobalSearchCategoryPage({
    this.choices = const [],
    this.total,
    this.hasMore = false,
  });
  final List<GlobalSearchFilterChoice> choices;
  final int? total;
  final bool hasMore;
}

@immutable
class GlobalSearchFilter {
  const GlobalSearchFilter({
    required this.id,
    required this.label,
    required this.scope,
    required this.kind,
    this.icon = 'search',
    this.group = '',
    this.operators = const [GlobalSearchFilterOperator('is', 'is')],
    this.choices = const [],
    this.token,
    this.opTokens = const {},
    this.placeholder = '',
    this.help = '',
    this.optional,
    this.lookup = GlobalSearchLookup.none,
    this.singleIdentifier = false,
    this.rejectQuotes = false,
  });
  final GlobalSearchLookup lookup;
  final bool singleIdentifier, rejectQuotes;
  final String id, label, icon, group, placeholder, help;
  final GlobalSearchScope scope;
  final GlobalSearchFilterKind kind;
  final List<GlobalSearchFilterOperator> operators;
  final List<GlobalSearchFilterChoice> choices;
  final String? token, optional;
  final Map<String, String> opTokens;
}

@immutable
class GlobalSearchCondition {
  const GlobalSearchCondition({
    required this.filterId,
    this.operator = 'is',
    required this.value,
  });
  final String filterId, operator;
  final List<String> value;
  String get text => value.join(',');
}

@immutable
class GlobalSearchOrder {
  const GlobalSearchOrder(this.value, this.label);
  final String value, label;
}

@immutable
class GlobalSearchResult {
  const GlobalSearchResult({
    required this.id,
    required this.scope,
    required this.title,
    required this.path,
    this.excerpt = '',
    this.username,
    this.avatarUrl,
    this.categoryId,
    this.tags = const [],
    this.createdAt,
    this.likes,
    this.replies,
    this.memberCount,
    this.source,
    this.contextLabel,
    this.searchLogId,
    this.privateMessage = false,
    this.closed = false,
    this.archived = false,
  });
  final String id, title, path, excerpt;
  final GlobalSearchScope scope;
  final String? username, avatarUrl, contextLabel;
  final int? categoryId, likes, replies, memberCount, searchLogId;
  final List<String> tags;
  final DateTime? createdAt;
  final SearchResult? source;
  final bool privateMessage, closed, archived;
}

@immutable
class GlobalSearchSection {
  const GlobalSearchSection({
    required this.scope,
    this.results = const [],
    this.hasMore = false,
    this.error,
  });
  final GlobalSearchScope scope;
  final List<GlobalSearchResult> results;
  final bool hasMore;
  final String? error;
}

@immutable
class GlobalSearchPage {
  const GlobalSearchPage({
    this.sections = const [],
    this.hasMore = false,
    this.consumedCount = 0,
    this.groupMemberOrder,
    this.userOrders,
  });
  final List<GlobalSearchSection> sections;
  final bool hasMore;
  final int consumedCount;
  final bool? groupMemberOrder;
  final List<String>? userOrders;
  List<GlobalSearchResult> get results => [
    for (final section in sections) ...section.results,
  ];
}

@immutable
class GlobalSearchRequest {
  const GlobalSearchRequest({
    required this.scope,
    required this.query,
    required this.capabilities,
    this.conditions = const [],
    this.order = 'relevance',
    this.ascending = false,
    this.page = 0,
    this.offset = 0,
  });
  final GlobalSearchScope scope;
  final String query, order;
  final List<GlobalSearchCondition> conditions;
  final GlobalSearchCapabilities capabilities;
  final bool ascending;
  final int page, offset;
}
