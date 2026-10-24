import 'package:flutter/foundation.dart';

import '../../models/group.dart';
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
