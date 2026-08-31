import 'package:flutter/foundation.dart';

import '../plugin_api/plugin_data.dart';
import 'json.dart';
import 'topic.dart';

@immutable
final class Group {
  const Group({
    required this.id,
    required this.name,
    this.displayName,
    this.fullName,
    this.automatic = false,
    this.userCount,
    this.mentionableLevel = 0,
    this.messageableLevel = 0,
    this.visibilityLevel = 0,
    this.membersVisibilityLevel = 0,
    this.primaryGroup = false,
    this.title,
    this.grantTrustLevel,
    this.incomingEmail,
    this.hasMessages = false,
    this.messageCount,
    this.flairUrl,
    this.flairIcon,
    this.flairType,
    this.flairBackgroundColor,
    this.flairColor,
    this.bioRaw,
    this.bioCooked,
    this.bioExcerpt,
    this.publicAdmission = false,
    this.publicExit = false,
    this.allowMembershipRequests = false,
    this.defaultNotificationLevel = 0,
    this.membershipRequestTemplate,
    this.isGroupUser = false,
    this.isGroupOwner = false,
    this.isGroupOwnerDisplay = false,
    this.canSeeMembers = false,
    this.canAdminGroup = false,
    this.canEditGroup = false,
    this.mentionable = false,
    this.messageable = false,
    this.publishReadState = false,
    this.automaticMembershipEmailDomains,
    this.associatedGroupIds = const [],
    this.watchingCategoryIds = const [],
    this.trackingCategoryIds = const [],
    this.watchingFirstPostCategoryIds = const [],
    this.regularCategoryIds = const [],
    this.mutedCategoryIds = const [],
    this.watchingTags = const [],
    this.trackingTags = const [],
    this.watchingFirstPostTags = const [],
    this.regularTags = const [],
    this.mutedTags = const [],
    this.smtpServer,
    this.smtpPort,
    this.smtpSslMode,
    this.smtpEnabled = false,
    this.smtpUpdatedAt,
    this.smtpUpdatedBy,
    this.emailUsername,
    this.emailPassword,
    this.emailFromAlias,
    this.allowUnknownSenderTopicReplies = false,
    this.plugins = PluginData.none,
  });

  static const int maximumNotificationDefaults = 1000;

  factory Group.fromWire(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) => Group(
    id: jsonInt(json['id']),
    name: jsonString(json['name']),
    displayName: jsonText(json['display_name']),
    fullName: jsonText(json['full_name']),
    automatic: json['automatic'] == true,
    userCount: json.containsKey('user_count')
        ? jsonIntOrNull(json['user_count'])
        : null,
    mentionableLevel: jsonInt(json['mentionable_level']),
    messageableLevel: jsonInt(json['messageable_level']),
    visibilityLevel: jsonInt(json['visibility_level']),
    membersVisibilityLevel: jsonInt(json['members_visibility_level']),
    primaryGroup: json['primary_group'] == true,
    title: jsonText(json['title']),
    grantTrustLevel: jsonIntOrNull(json['grant_trust_level']),
    incomingEmail: jsonText(json['incoming_email']),
    hasMessages: json['has_messages'] == true,
    messageCount: jsonIntOrNull(json['message_count']),
    flairUrl: jsonText(json['flair_url']),
    flairIcon: jsonText(json['flair_icon']),
    flairType: jsonText(json['flair_type']),
    flairBackgroundColor: jsonText(json['flair_bg_color']),
    flairColor: jsonText(json['flair_color']),
    bioRaw: jsonText(json['bio_raw']),
    bioCooked: jsonText(json['bio_cooked']),
    bioExcerpt: jsonText(json['bio_excerpt']),
    publicAdmission: json['public_admission'] == true,
    publicExit: json['public_exit'] == true,
    allowMembershipRequests: json['allow_membership_requests'] == true,
    defaultNotificationLevel: jsonInt(json['default_notification_level']),
    membershipRequestTemplate: jsonText(json['membership_request_template']),
    isGroupUser: json['is_group_user'] == true,
    isGroupOwner: json['is_group_owner'] == true,
    isGroupOwnerDisplay: json['is_group_owner_display'] == true,
    canSeeMembers: json['can_see_members'] == true,
    canAdminGroup: json['can_admin_group'] == true,
    canEditGroup: json['can_edit_group'] == true,
    mentionable: json['mentionable'] == true,
    messageable: json['messageable'] == true,
    publishReadState: json['publish_read_state'] == true,
    automaticMembershipEmailDomains: jsonText(
      json['automatic_membership_email_domains'],
    ),
    associatedGroupIds: _positiveIds(json['associated_group_ids']),
    watchingCategoryIds: _positiveIds(json['watching_category_ids']),
    trackingCategoryIds: _positiveIds(json['tracking_category_ids']),
    watchingFirstPostCategoryIds: _positiveIds(
      json['watching_first_post_category_ids'],
    ),
    regularCategoryIds: _positiveIds(json['regular_category_ids']),
    mutedCategoryIds: _positiveIds(json['muted_category_ids']),
    watchingTags: _groupTags(json['watching_tags']),
    trackingTags: _groupTags(json['tracking_tags']),
    watchingFirstPostTags: _groupTags(json['watching_first_post_tags']),
    regularTags: _groupTags(json['regular_tags']),
    mutedTags: _groupTags(json['muted_tags']),
    smtpServer: jsonText(json['smtp_server']),
    smtpPort: jsonIntOrNull(json['smtp_port']),
    smtpSslMode: jsonIntOrNull(json['smtp_ssl_mode']),
    smtpEnabled: json['smtp_enabled'] == true,
    smtpUpdatedAt: jsonDate(json['smtp_updated_at']),
    smtpUpdatedBy: GroupUserReference.fromWire(
      json['smtp_updated_by'],
      siteUrl,
    ),
    emailUsername: jsonText(json['email_username']),
    emailPassword: jsonText(json['email_password']),
    emailFromAlias: jsonText(json['email_from_alias']),
    allowUnknownSenderTopicReplies:
        json['allow_unknown_sender_topic_replies'] == true,
    plugins: extensions.readGroup(json, siteUrl),
  );

  final int id;
  final String name;
  final String? displayName;
  final String? fullName;
  final bool automatic;

  final int? userCount;

  final int mentionableLevel;
  final int messageableLevel;
  final int visibilityLevel;
  final int membersVisibilityLevel;
  final bool primaryGroup;
  final String? title;
  final int? grantTrustLevel;
  final String? incomingEmail;
  final bool hasMessages;
  final int? messageCount;
  final String? flairUrl;
  final String? flairIcon;
  final String? flairType;
  final String? flairBackgroundColor;
  final String? flairColor;
  final String? bioRaw;
  final String? bioCooked;
  final String? bioExcerpt;
  final bool publicAdmission;
  final bool publicExit;
  final bool allowMembershipRequests;
  final int defaultNotificationLevel;
  final String? membershipRequestTemplate;
  final bool isGroupUser;
  final bool isGroupOwner;
  final bool isGroupOwnerDisplay;
  final bool canSeeMembers;
  final bool canAdminGroup;
  final bool canEditGroup;
  final bool mentionable;
  final bool messageable;
  final bool publishReadState;
  final String? automaticMembershipEmailDomains;
  final List<int> associatedGroupIds;
  final List<int> watchingCategoryIds;
  final List<int> trackingCategoryIds;
  final List<int> watchingFirstPostCategoryIds;
  final List<int> regularCategoryIds;
  final List<int> mutedCategoryIds;
  final List<GroupTag> watchingTags;
  final List<GroupTag> trackingTags;
  final List<GroupTag> watchingFirstPostTags;
  final List<GroupTag> regularTags;
  final List<GroupTag> mutedTags;
  final String? smtpServer;
  final int? smtpPort;
  final int? smtpSslMode;
  final bool smtpEnabled;
  final DateTime? smtpUpdatedAt;
  final GroupUserReference? smtpUpdatedBy;
  final String? emailUsername;
  final String? emailPassword;
  final String? emailFromAlias;
  final bool allowUnknownSenderTopicReplies;
  final PluginData plugins;

  String get label => fullName ?? displayName ?? name;
  String? get plainBio => jsonHtmlText(bioCooked);
  bool get isPrivate => visibilityLevel > 1;
  bool get canManage => canAdminGroup || isGroupOwner;

  bool canShowMessages({
    required bool canSendPrivateMessages,
    required bool isAdmin,
  }) => canSendPrivateMessages && hasMessages && (isGroupUser || isAdmin);
}

@immutable
final class GroupTag {
  const GroupTag({required this.name, this.id, this.slug});

  static GroupTag? read(Object? value) {
    if (value is String) {
      final name = value.trim();
      return name.isEmpty ? null : GroupTag(name: name);
    }
    final json = jsonObject(value);
    final name = jsonText(json['name']);
    if (name == null) return null;
    return GroupTag(
      id: jsonIntOrNull(json['id']),
      name: name,
      slug: jsonText(json['slug']),
    );
  }

  final int? id;
  final String name;
  final String? slug;
}

@immutable
final class GroupUserReference {
  const GroupUserReference({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
  });

  static GroupUserReference? fromWire(Object? value, String siteUrl) {
    final json = jsonObject(value);
    final username = jsonText(json['username']);
    if (username == null) return null;
    return GroupUserReference(
      id: jsonInt(json['id']),
      username: username,
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;
}

@immutable
final class GroupDirectoryPage {
  const GroupDirectoryPage({
    this.groups = const [],
    this.typeFilters = const [],
    this.totalRows = 0,
    this.loadMoreUrl,
  });

  static const int maximumGroups = 100;

  factory GroupDirectoryPage.fromWire(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final extras = jsonObject(json['extras']);
    return GroupDirectoryPage(
      groups: List.unmodifiable([
        for (final group in jsonObjects(json['groups']).take(maximumGroups))
          Group.fromWire(group, siteUrl, extensions: extensions),
      ]),
      typeFilters: _strings(extras['type_filters'], maximum: 16),
      totalRows: jsonInt(json['total_rows_groups']),
      loadMoreUrl: jsonText(json['load_more_groups']),
    );
  }

  final List<Group> groups;
  final List<String> typeFilters;
  final int totalRows;
  final String? loadMoreUrl;

  String? get nextPagePath => TopicList.asJsonPath(loadMoreUrl);
}

@immutable
final class GroupDetail {
  const GroupDetail({required this.group, this.visibleGroupNames = const []});

  factory GroupDetail.fromWire(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) => GroupDetail(
    group: Group.fromWire(
      jsonObject(json['group']),
      siteUrl,
      extensions: extensions,
    ),
    visibleGroupNames: _strings(
      jsonObject(json['extras'])['visible_group_names'],
      maximum: 1000,
    ),
  );

  final Group group;
  final List<String> visibleGroupNames;
}

@immutable
final class GroupMember {
  const GroupMember({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
    this.title,
    this.primaryGroupName,
    this.lastPostedAt,
    this.lastSeenAt,
    this.addedAt,
    this.timezone,
    this.owner = false,
    this.primary = false,
  });

  factory GroupMember.fromWire(
    Map<String, dynamic> json,
    String siteUrl, {
    bool owner = false,
    String? groupName,
  }) => GroupMember(
    id: jsonInt(json['id']),
    username: jsonString(json['username']),
    name: jsonText(json['name']),
    avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
    title: jsonText(json['title']),
    primaryGroupName: jsonText(json['primary_group_name']),
    lastPostedAt: jsonDate(json['last_posted_at']),
    lastSeenAt: jsonDate(json['last_seen_at']),
    addedAt: jsonDate(json['added_at']),
    timezone: jsonText(json['timezone']),
    owner: owner,
    primary:
        groupName != null &&
        jsonText(json['primary_group_name'])?.toLowerCase() ==
            groupName.toLowerCase(),
  );

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final String? title;
  final String? primaryGroupName;
  final DateTime? lastPostedAt;
  final DateTime? lastSeenAt;
  final DateTime? addedAt;
  final String? timezone;
  final bool owner;
  final bool primary;

  GroupMember copyWith({bool? owner, bool? primary}) => GroupMember(
    id: id,
    username: username,
    name: name,
    avatarUrl: avatarUrl,
    title: title,
    primaryGroupName: primaryGroupName,
    lastPostedAt: lastPostedAt,
    lastSeenAt: lastSeenAt,
    addedAt: addedAt,
    timezone: timezone,
    owner: owner ?? this.owner,
    primary: primary ?? this.primary,
  );
}

@immutable
final class GroupMembersPage {
  const GroupMembersPage({
    this.members = const [],
    this.total = 0,
    this.limit = 0,
    this.offset = 0,
  });

  static const int maximumMembers = 1000;

  factory GroupMembersPage.fromWire(
    Map<String, dynamic> json,
    String siteUrl, {
    required String groupName,
  }) {
    final ownerIds = <int>{
      for (final owner in jsonObjects(json['owners']).take(maximumMembers))
        ?jsonIntOrNull(owner['id']),
    };
    final meta = jsonObject(json['meta']);
    return GroupMembersPage(
      members: List.unmodifiable([
        for (final member in jsonObjects(json['members']).take(maximumMembers))
          GroupMember.fromWire(
            member,
            siteUrl,
            owner: ownerIds.contains(jsonInt(member['id'])),
            groupName: groupName,
          ),
      ]),
      total: jsonInt(meta['total']),
      limit: jsonInt(meta['limit']),
      offset: jsonInt(meta['offset']),
    );
  }

  final List<GroupMember> members;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + members.length < total;
  int get nextOffset => offset + limit;
}

@immutable
final class GroupRequester {
  const GroupRequester({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
    this.reason,
    this.requestedAt,
  });

  factory GroupRequester.fromWire(Map<String, dynamic> json, String siteUrl) =>
      GroupRequester(
        id: jsonInt(json['id']),
        username: jsonString(json['username']),
        name: jsonText(json['name']),
        avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
        reason: jsonText(json['reason']),
        requestedAt: jsonDate(json['requested_at']),
      );

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;
  final String? reason;
  final DateTime? requestedAt;
}

@immutable
final class GroupRequestersPage {
  const GroupRequestersPage({
    this.requesters = const [],
    this.total = 0,
    this.limit = 0,
    this.offset = 0,
  });

  factory GroupRequestersPage.fromWire(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final meta = jsonObject(json['meta']);
    return GroupRequestersPage(
      requesters: List.unmodifiable([
        for (final requester in jsonObjects(
          json['members'],
        ).take(GroupMembersPage.maximumMembers))
          GroupRequester.fromWire(requester, siteUrl),
      ]),
      total: jsonInt(meta['total']),
      limit: jsonInt(meta['limit']),
      offset: jsonInt(meta['offset']),
    );
  }

  final List<GroupRequester> requesters;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + requesters.length < total;
  int get nextOffset => offset + limit;
}

@immutable
final class GroupActivityPost {
  const GroupActivityPost({
    required this.id,
    required this.topicId,
    required this.postNumber,
    required this.topicTitle,
    required this.topicSlug,
    required this.excerpt,
    this.createdAt,
    this.url,
    this.categoryId,
    this.postsCount = 0,
    this.postType = 1,
    this.userId,
    this.username,
    this.name,
    this.avatarUrl,
    this.userTitle,
    this.primaryGroupName,
    this.truncated = false,
  });

  factory GroupActivityPost.fromWire(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final topic = jsonObject(json['topic']);
    final user = jsonObject(json['user']);
    return GroupActivityPost(
      id: jsonInt(json['id']),
      topicId: jsonInt(json['topic_id'] ?? topic['id']),
      postNumber: jsonInt(json['post_number']),
      topicTitle: jsonTitle(
        json['topic_title'] ?? topic['title'],
        json['topic_html_title'] ?? topic['fancy_title'],
      ),
      topicSlug: jsonString(json['topic_slug'] ?? topic['slug']),
      excerpt: jsonString(json['excerpt']),
      createdAt: jsonDate(json['created_at']),
      url: jsonText(json['url']),
      categoryId: jsonIntOrNull(json['category_id'] ?? topic['category_id']),
      postsCount: jsonInt(json['posts_count'] ?? topic['posts_count']),
      postType: jsonIntOrNull(json['post_type']) ?? 1,
      userId: jsonIntOrNull(json['user_id'] ?? user['id']),
      username: jsonText(json['username'] ?? user['username']),
      name: jsonText(json['name'] ?? user['name']),
      avatarUrl: resolveAvatarUrl(
        jsonText(json['avatar_template'] ?? user['avatar_template']),
        siteUrl,
      ),
      userTitle: jsonText(json['user_title'] ?? user['title']),
      primaryGroupName: jsonText(
        json['primary_group_name'] ?? user['primary_group_name'],
      ),
      truncated: json['truncated'] == true,
    );
  }

  final int id;
  final int topicId;
  final int postNumber;
  final String topicTitle;
  final String topicSlug;
  final String excerpt;
  final DateTime? createdAt;
  final String? url;
  final int? categoryId;
  final int postsCount;
  final int postType;
  final int? userId;
  final String? username;
  final String? name;
  final String? avatarUrl;
  final String? userTitle;
  final String? primaryGroupName;
  final bool truncated;

  String get plainExcerpt => jsonHtmlText(excerpt) ?? '';
}

@immutable
final class GroupActivityPage {
  const GroupActivityPage({
    this.posts = const [],
    this.categories = const [],
    this.rawPostCount = 0,
  });

  static const int pageSize = 20;

  factory GroupActivityPage.fromWire(
    Map<String, dynamic> json,
    String siteUrl,
  ) {
    final rows = jsonObjects(json['posts']).take(pageSize).toList();
    return GroupActivityPage(
      rawPostCount: rows.length,
      posts: List.unmodifiable([
        for (final post in rows) GroupActivityPost.fromWire(post, siteUrl),
      ]),
      categories: List.unmodifiable([
        for (final category in jsonObjects(json['categories']).take(pageSize))
          TopicCategory.fromJson(category),
      ]),
    );
  }

  final List<GroupActivityPost> posts;
  final List<TopicCategory> categories;
  final int rawPostCount;

  bool get hasMore => rawPostCount == pageSize;
  DateTime? get before => posts.isEmpty ? null : posts.last.createdAt;
}

enum GroupPermissionType {
  full(1),
  createPost(2),
  readOnly(3),
  unknown(0);

  const GroupPermissionType(this.wireValue);

  final int wireValue;

  static GroupPermissionType read(Object? value) => switch (jsonInt(value)) {
    1 => full,
    2 => createPost,
    3 => readOnly,
    _ => unknown,
  };
}

@immutable
final class GroupPermission {
  const GroupPermission({required this.type, required this.category});

  factory GroupPermission.fromWire(Map<String, dynamic> json) =>
      GroupPermission(
        type: GroupPermissionType.read(json['permission_type']),
        category: TopicCategory.fromJson(jsonObject(json['category'])),
      );

  final GroupPermissionType type;
  final TopicCategory category;
}

@immutable
final class GroupLogEntry {
  const GroupLogEntry({
    required this.action,
    this.subject,
    this.previousValue,
    this.newValue,
    this.createdAt,
    this.actingUser,
    this.targetUser,
  });

  factory GroupLogEntry.fromWire(Map<String, dynamic> json, String siteUrl) =>
      GroupLogEntry(
        action: jsonString(json['action']),
        subject: jsonText(json['subject']),
        previousValue: jsonText(json['prev_value']),
        newValue: jsonText(json['new_value']),
        createdAt: jsonDate(json['created_at']),
        actingUser: GroupUserReference.fromWire(json['acting_user'], siteUrl),
        targetUser: GroupUserReference.fromWire(json['target_user'], siteUrl),
      );

  final String action;
  final String? subject;
  final String? previousValue;
  final String? newValue;
  final DateTime? createdAt;
  final GroupUserReference? actingUser;
  final GroupUserReference? targetUser;
}

@immutable
final class GroupLogsPage {
  const GroupLogsPage({this.logs = const [], this.allLoaded = true});

  static const int pageSize = 25;

  factory GroupLogsPage.fromWire(Map<String, dynamic> json, String siteUrl) =>
      GroupLogsPage(
        logs: List.unmodifiable([
          for (final log in jsonObjects(json['logs']).take(pageSize))
            GroupLogEntry.fromWire(log, siteUrl),
        ]),
        allLoaded: json['all_loaded'] != false,
      );

  final List<GroupLogEntry> logs;
  final bool allLoaded;
}

@immutable
final class GroupMembershipMutationResult {
  const GroupMembershipMutationResult({
    this.usernames = const [],
    this.emails = const [],
    this.skippedUsernames = const [],
  });

  factory GroupMembershipMutationResult.fromWire(Map<String, dynamic> json) =>
      GroupMembershipMutationResult(
        usernames: _strings(json['usernames'], maximum: 1000),
        emails: _strings(json['emails'], maximum: 1000),
        skippedUsernames: _strings(json['skipped_usernames'], maximum: 1000),
      );

  final List<String> usernames;
  final List<String> emails;
  final List<String> skippedUsernames;
}

@immutable
final class GroupInvite {
  const GroupInvite({required this.id, this.link, this.email, this.expiresAt});

  factory GroupInvite.fromWire(Map<String, dynamic> json) => GroupInvite(
    id: jsonInt(json['id']),
    link: jsonText(json['link']),
    email: jsonText(json['email']),
    expiresAt: jsonDate(json['expires_at']),
  );

  final int id;
  final String? link;
  final String? email;
  final DateTime? expiresAt;
}

List<int> _positiveIds(Object? value) => List.unmodifiable([
  for (final item in jsonArray(value).take(Group.maximumNotificationDefaults))
    if (jsonIntOrNull(item) case final id? when id > 0) id,
]);

List<GroupTag> _groupTags(Object? value) => List.unmodifiable([
  for (final item in jsonArray(value).take(Group.maximumNotificationDefaults))
    ?GroupTag.read(item),
]);

List<String> _strings(Object? value, {required int maximum}) =>
    List.unmodifiable([
      for (final item in jsonArray(value).take(maximum)) ?jsonText(item),
    ]);
