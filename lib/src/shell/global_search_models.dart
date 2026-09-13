import 'package:flutter/foundation.dart';

import '../models/discourse_user.dart';
import '../models/search_results.dart';
import '../models/site_config.dart';

enum GlobalSearchScope {
  all('All'),
  forum('Topics & posts'),
  users('Users'),
  groups('Groups'),
  chat('Chat');

  const GlobalSearchScope(this.label);
  final String label;
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
    this.authenticated = false,
    this.username,
    this.chat = false,
    this.chatEligible = false,
    this.tagging = true,
    this.userDirectory = true,
    this.groupDirectory = true,
    this.staff = false,
    this.admin = false,
    this.whispers = false,
    this.unlisted = false,
    this.solved = false,
    this.assign = false,
    this.poll = false,
    this.voting = false,
    this.minimumLength = 3,
    this.logSearchQueries = true,
    this.userOrders = const ['username'],
    this.groupMemberOrder = false,
  });
  factory GlobalSearchCapabilities.fromSite(
    SiteConfig config,
    DiscourseUser? user, {
    bool chat = false,
    Set<String> enabledPlugins = const {},
    bool canAssign = false,
  }) => GlobalSearchCapabilities(
    authenticated: user != null,
    username: user?.username,
    chat: false,
    chatEligible: chat && user != null,
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
    solved: enabledPlugins.contains('solved'),
    assign: enabledPlugins.contains('assign') && canAssign,
    poll: enabledPlugins.contains('poll'),
    voting: enabledPlugins.contains('voting'),
    minimumLength: config.minSearchTermLength,
    logSearchQueries: config.logSearchQueries,
  );
  final bool authenticated,
      chat,
      chatEligible,
      tagging,
      userDirectory,
      groupDirectory,
      staff,
      admin,
      whispers,
      unlisted,
      solved,
      assign,
      poll,
      voting,
      logSearchQueries,
      groupMemberOrder;
  final String? username;
  final int minimumLength;
  final List<String> userOrders;
  String get fingerprint => [
    authenticated,
    username,
    chat,
    chatEligible,
    tagging,
    userDirectory,
    groupDirectory,
    staff,
    admin,
    whispers,
    unlisted,
    solved,
    assign,
    poll,
    voting,
    minimumLength,
    logSearchQueries,
    ...userOrders,
    groupMemberOrder,
  ].join('|');
  GlobalSearchCapabilities copyWith({
    bool? chat,
    bool? solved,
    bool? assign,
    bool? poll,
    bool? voting,
    bool? unlisted,
    List<String>? userOrders,
    bool? groupMemberOrder,
  }) => GlobalSearchCapabilities(
    authenticated: authenticated,
    username: username,
    chat: chat ?? this.chat,
    chatEligible: chatEligible,
    tagging: tagging,
    userDirectory: userDirectory,
    groupDirectory: groupDirectory,
    staff: staff,
    admin: admin,
    whispers: whispers,
    unlisted: unlisted ?? this.unlisted,
    solved: solved ?? this.solved,
    assign: assign ?? this.assign,
    poll: poll ?? this.poll,
    voting: voting ?? this.voting,
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
  });
  final String value, label;
  final String? token;
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
  });
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
    this.channelId,
    this.messageId,
    this.threadId,
    this.channelTitle,
    this.searchLogId,
    this.privateMessage = false,
    this.closed = false,
    this.archived = false,
  });
  final String id, title, path, excerpt;
  final GlobalSearchScope scope;
  final String? username, avatarUrl, channelTitle;
  final int? categoryId,
      likes,
      replies,
      memberCount,
      channelId,
      messageId,
      threadId,
      searchLogId;
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
