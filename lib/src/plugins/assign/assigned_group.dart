import 'package:flutter/foundation.dart';

import '../../models/json.dart';

/// Which slice of a group's active assignments is being shown.
sealed class AssignedGroupFilter {
  const AssignedGroupFilter();

  const factory AssignedGroupFilter.everyone() = AssignedGroupEveryoneFilter;

  const factory AssignedGroupFilter.directGroup() = AssignedGroupDirectFilter;

  factory AssignedGroupFilter.member(String usernameLower) =
      AssignedGroupMemberFilter;

  /// The route segment used below `/g/:group/assigned`.
  String routeSegment(String groupName);
}

final class AssignedGroupEveryoneFilter extends AssignedGroupFilter {
  const AssignedGroupEveryoneFilter();

  @override
  String routeSegment(String groupName) => 'everyone';

  @override
  bool operator ==(Object other) => other is AssignedGroupEveryoneFilter;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class AssignedGroupDirectFilter extends AssignedGroupFilter {
  const AssignedGroupDirectFilter();

  @override
  String routeSegment(String groupName) => groupName;

  @override
  bool operator ==(Object other) => other is AssignedGroupDirectFilter;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class AssignedGroupMemberFilter extends AssignedGroupFilter {
  factory AssignedGroupMemberFilter(String usernameLower) {
    final username = usernameLower.trim().toLowerCase();
    if (username.isEmpty || username.length > maximumUsernameLength) {
      throw ArgumentError.value(
        usernameLower,
        'usernameLower',
        'An assigned-group member must have a valid username.',
      );
    }
    return AssignedGroupMemberFilter._(username);
  }

  const AssignedGroupMemberFilter._(this.usernameLower);

  static const int maximumUsernameLength = 255;

  final String usernameLower;

  @override
  String routeSegment(String groupName) => usernameLower;

  @override
  bool operator ==(Object other) =>
      other is AssignedGroupMemberFilter &&
      other.usernameLower == usernameLower;

  @override
  int get hashCode => usernameLower.hashCode;
}

/// Sorts supported by discourse-assign's group topic lists.
enum AssignedGroupOrder {
  activity('activity'),
  views('views'),
  posts('posts');

  const AssignedGroupOrder(this.wireName);

  final String wireName;
}

/// A topic-list query, and therefore part of the assignment-feed cache key.
@immutable
final class AssignedGroupTopicQuery {
  const AssignedGroupTopicQuery({
    this.order,
    this.ascending = false,
    this.search = '',
  });

  final AssignedGroupOrder? order;
  final bool ascending;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is AssignedGroupTopicQuery &&
      other.order == order &&
      other.ascending == ascending &&
      other.search == search;

  @override
  int get hashCode => Object.hash(order, ascending, search);
}

/// One member returned by `/assign/members/:group`.
@immutable
final class AssignedGroupMember {
  const AssignedGroupMember({
    required this.id,
    required this.username,
    required this.usernameLower,
    this.name,
    this.avatarUrl,
    this.assignmentsCount,
  });

  static AssignedGroupMember? fromJson(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final id = jsonIntOrNull(json['id']);
    final username = jsonText(json['username']);
    if (id == null || id <= 0 || username == null) return null;

    final lower = jsonText(json['username_lower'])?.trim().toLowerCase();
    final count = jsonIntOrNull(json['assignments_count']);
    return AssignedGroupMember(
      id: id,
      username: username,
      usernameLower: lower == null || lower.isEmpty
          ? username.toLowerCase()
          : lower,
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      assignmentsCount: count == null || count < 0 ? null : count,
    );
  }

  final int id;
  final String username;
  final String usernameLower;
  final String? name;
  final String? avatarUrl;

  /// Nullable because the plugin serializer conditionally omits this field.
  final int? assignmentsCount;

  @override
  bool operator ==(Object other) =>
      other is AssignedGroupMember &&
      other.id == id &&
      other.username == username &&
      other.usernameLower == usernameLower &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.assignmentsCount == assignmentsCount;

  @override
  int get hashCode => Object.hash(
    id,
    username,
    usernameLower,
    name,
    avatarUrl,
    assignmentsCount,
  );
}

/// One offset page of assigned members and the counts shown beside its filters.
@immutable
final class AssignedGroupMembersPage {
  AssignedGroupMembersPage({
    required List<AssignedGroupMember> members,
    required this.assignmentCount,
    required this.groupAssignmentCount,
    required this.offset,
    required this.limit,
    required this.hasMore,
  }) : members = List.unmodifiable(members);

  factory AssignedGroupMembersPage.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    required int offset,
    required int limit,
  }) {
    final rawMembers = jsonArray(json['members']).take(limit).toList();
    final assignmentCount = jsonIntOrNull(json['assignment_count']);
    final groupAssignmentCount = jsonIntOrNull(json['group_assignment_count']);
    return AssignedGroupMembersPage(
      members: [
        for (final value in rawMembers)
          if (value is Map<String, dynamic>)
            ?AssignedGroupMember.fromJson(value, siteUrl),
      ],
      assignmentCount: assignmentCount == null || assignmentCount < 0
          ? 0
          : assignmentCount,
      groupAssignmentCount:
          groupAssignmentCount == null || groupAssignmentCount < 0
          ? 0
          : groupAssignmentCount,
      offset: offset,
      limit: limit,
      // Use the wire row count rather than the number of valid parsed rows. A
      // malformed row must not make the client skip a later valid page.
      hasMore: rawMembers.length >= limit,
    );
  }

  final List<AssignedGroupMember> members;
  final int assignmentCount;
  final int groupAssignmentCount;
  final int offset;
  final int limit;
  final bool hasMore;
}

/// Cached member-filter state for one site, group, and name search.
@immutable
final class AssignedGroupMembersState {
  const AssignedGroupMembersState({
    this.members = const [],
    this.assignmentCount = 0,
    this.groupAssignmentCount = 0,
    this.nextOffset = 0,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.pageError = false,
  });

  final List<AssignedGroupMember> members;
  final int assignmentCount;
  final int groupAssignmentCount;
  final int nextOffset;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final String? error;
  final bool pageError;

  bool get isEmpty => loaded && error == null && members.isEmpty;

  AssignedGroupMembersState loadingFirst() => AssignedGroupMembersState(
    members: members,
    assignmentCount: assignmentCount,
    groupAssignmentCount: groupAssignmentCount,
    nextOffset: nextOffset,
    hasMore: hasMore,
    loading: true,
    loaded: loaded,
  );

  AssignedGroupMembersState loadingNextPage() => AssignedGroupMembersState(
    members: members,
    assignmentCount: assignmentCount,
    groupAssignmentCount: groupAssignmentCount,
    nextOffset: nextOffset,
    hasMore: hasMore,
    loadingMore: true,
    loaded: loaded,
  );

  AssignedGroupMembersState withPage(AssignedGroupMembersPage page) {
    final first = page.offset == 0;
    final next = first ? <AssignedGroupMember>[] : [...members];
    final seen = {for (final member in next) member.id};
    for (final member in page.members) {
      if (seen.add(member.id)) next.add(member);
    }
    return AssignedGroupMembersState(
      members: List.unmodifiable(next),
      assignmentCount: first ? page.assignmentCount : assignmentCount,
      groupAssignmentCount: first
          ? page.groupAssignmentCount
          : groupAssignmentCount,
      nextOffset: page.offset + page.limit,
      hasMore: page.hasMore,
      loaded: true,
    );
  }

  AssignedGroupMembersState withError(String message, {bool page = false}) =>
      AssignedGroupMembersState(
        members: members,
        assignmentCount: assignmentCount,
        groupAssignmentCount: groupAssignmentCount,
        nextOffset: nextOffset,
        hasMore: hasMore,
        loaded: true,
        error: message,
        pageError: page,
      );
}
