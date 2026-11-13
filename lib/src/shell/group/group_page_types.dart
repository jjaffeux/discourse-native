import 'package:flutter/foundation.dart';

import '../../models/group.dart';
import '../../models/plugin_data.dart';
import '../group_write.dart';

export '../group_write.dart';

enum GroupMembershipAction { join, leave, request }

enum GroupRequestAction { accept, deny }

enum GroupMemberAction {
  remove,
  makeOwner,
  removeOwner,
  makePrimary,
  removePrimary,
}

typedef GroupMemberSortChanged = void Function(String order, bool ascending);
typedef GroupAddMembers =
    Future<GroupMembershipMutationResult?> Function(
      List<String> usernames,
      List<String> emails,
    );
typedef GroupCreateInvite =
    Future<GroupInvite?> Function({String? email, String? customMessage});
typedef GroupMemberActionCallback =
    Future<bool> Function(GroupMember member, GroupMemberAction action);
typedef GroupManageSubmit =
    Future<GroupWriteOutcome<void>> Function(GroupManageUpdate update);

@immutable
final class GroupManageUpdate {
  GroupManageUpdate({
    required this.subsection,
    required Map<String, Object?> values,
  }) : values = freezeGroupValues(values);

  final String subsection;
  final Map<String, Object?> values;
}

@immutable
final class GroupPageData {
  const GroupPageData({
    this.detail,
    this.members,
    this.requesters,
    this.activity,
    this.permissions = const [],
    this.logs,
    this.currentUserData = PluginData.none,
    this.canSendPrivateMessages = false,
    this.canInviteToForum = false,
    this.currentUserStaff = false,
    this.isAdmin = false,
    this.memberFilter = '',
    this.memberOrder = 'last_seen_at',
    this.memberAscending = false,
    this.mentionsEnabled = true,
    this.smtpEnabled = false,
    this.taggingEnabled = true,
    this.sectionLoading = false,
    this.loadingMore = false,
    this.mutating = false,
    this.error,
    this.sectionError,
    this.hasMore = false,
  });

  final GroupDetail? detail;
  final GroupMembersPage? members;
  final GroupRequestersPage? requesters;
  final GroupActivityPage? activity;
  final List<GroupPermission> permissions;
  final GroupLogsPage? logs;
  final PluginData currentUserData;
  final bool canSendPrivateMessages;
  final bool canInviteToForum;
  final bool currentUserStaff;
  final bool isAdmin;
  final String memberFilter;
  final String memberOrder;
  final bool memberAscending;
  final bool mentionsEnabled;
  final bool smtpEnabled;
  final bool taggingEnabled;
  final bool sectionLoading;
  final bool loadingMore;
  final bool mutating;
  final String? error;
  final String? sectionError;
  final bool hasMore;
}
