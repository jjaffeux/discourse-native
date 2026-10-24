import 'package:flutter/widgets.dart';

import '../models/found_user.dart';
import '../models/group.dart';
import '../models/group_route.dart';
import '../models/topic_feed.dart';
import 'group_page.dart';
import 'group_pages_coordinator.dart';
import 'groups_controller.dart';

abstract interface class GroupPagesPort implements GroupPagesCoordinatorPort {
  Listenable get changes;

  GroupDirectoryState directoryState(
    GroupPagesOwner owner,
    GroupPagesDirectoryQuery query,
  );

  Future<List<GroupMember>> loadMemberPreview(
    GroupPagesOwner owner,
    Group group,
  );

  GroupPageData groupData(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery,
  );

  TopicFeed? topicFeed(GroupPagesOwner owner, String routeId);

  bool canCreateGroup(GroupPagesOwner owner);

  void openGroup(GroupPagesOwner owner, String groupName);

  void createGroup(GroupPagesOwner owner);

  Future<GroupWriteOutcome<void>> join(GroupPagesOwner owner, Group group);

  Future<GroupWriteOutcome<void>> leave(GroupPagesOwner owner, Group group);

  Future<GroupWriteOutcome<String?>> requestMembership(
    GroupPagesOwner owner,
    Group group,
    String reason,
  );

  /// Opens the private message a membership request produced, as the web
  /// client does once the request is sent.
  void openMembershipRequest(GroupPagesOwner owner, String messageUrl);

  Future<GroupWriteOutcome<void>> deleteGroup(
    GroupPagesOwner owner,
    Group group,
  );

  Future<List<FoundUser>> searchUsers(GroupPagesOwner owner, String query);

  Future<GroupWriteOutcome<GroupMembershipMutationResult>> addMembers(
    GroupPagesOwner owner,
    Group group,
    GroupAddMembersCommand command,
    GroupPagesMemberQuery memberQuery,
  );

  Future<GroupWriteOutcome<GroupInvite>> createInvite(
    GroupPagesOwner owner,
    Group group, {
    String? email,
    String? customMessage,
  });

  Future<GroupWriteOutcome<void>> memberAction(
    GroupPagesOwner owner,
    Group group,
    GroupMember member,
    GroupMemberAction action,
  );

  void messageGroup(GroupPagesOwner owner, Group group);

  void openMember(
    BuildContext context,
    GroupPagesOwner owner,
    GroupMember member,
  );

  void openActivityPost(GroupPagesOwner owner, GroupActivityPost post);

  Future<GroupWriteOutcome<void>> handleRequest(
    GroupPagesOwner owner,
    Group group,
    GroupRequester requester,
    GroupRequestAction action,
  );

  Future<GroupWriteOutcome<void>> saveManage(
    GroupPagesOwner owner,
    Group group,
    GroupManageUpdate update,
  );

  Future<GroupWriteOutcome<void>> confirmManage(
    GroupPagesOwner owner,
    GroupUpdateConfirmation confirmation, {
    required bool applyToExistingUsers,
  });

  void cancelManage(GroupUpdateConfirmation confirmation);
}
