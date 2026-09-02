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

  GroupPageData groupData(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery,
  );

  TopicFeed? topicFeed(GroupPagesOwner owner, String routeId);

  bool canCreateGroup(GroupPagesOwner owner);

  void openGroup(GroupPagesOwner owner, String groupName);

  void createGroup(GroupPagesOwner owner);

  Future<bool> join(GroupPagesOwner owner, Group group);

  Future<bool> leave(GroupPagesOwner owner, Group group);

  Future<bool> requestMembership(
    GroupPagesOwner owner,
    Group group,
    String reason,
  );

  Future<bool> deleteGroup(GroupPagesOwner owner, Group group);

  Future<List<FoundUser>> searchUsers(GroupPagesOwner owner, String query);

  Future<GroupMembershipMutationResult?> addMembers(
    GroupPagesOwner owner,
    Group group,
    List<String> usernames,
    List<String> emails,
    GroupPagesMemberQuery memberQuery,
  );

  Future<GroupInvite?> createInvite(
    GroupPagesOwner owner,
    Group group, {
    String? email,
    String? customMessage,
  });

  Future<bool> memberAction(
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

  Future<void> handleRequest(
    GroupPagesOwner owner,
    Group group,
    GroupRequester requester,
    GroupRequestAction action,
  );

  Future<void> saveManage(
    GroupPagesOwner owner,
    Group group,
    GroupManageUpdate update,
  );
}
