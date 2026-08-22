import 'package:flutter/foundation.dart';

import '../../models/json.dart';

/// The two records the Assign plugin accepts as assignment targets.
enum AssignmentTargetType {
  topic('Topic'),
  post('Post');

  const AssignmentTargetType(this.wireName);

  final String wireName;
}

/// An Assign write target and the topic that must be refreshed afterwards.
@immutable
class AssignmentTarget {
  const AssignmentTarget.topic(int id)
    : this._(id: id, topicId: id, type: AssignmentTargetType.topic);

  const AssignmentTarget.post(int id, {required int topicId})
    : this._(id: id, topicId: topicId, type: AssignmentTargetType.post);

  const AssignmentTarget._({
    required this.id,
    required this.topicId,
    required this.type,
  });

  final int id;
  final int topicId;
  final AssignmentTargetType type;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignmentTarget &&
          other.id == id &&
          other.topicId == topicId &&
          other.type == type;

  @override
  int get hashCode => Object.hash(id, topicId, type);
}

/// A user or group that can own an assignment.
sealed class AssignmentAssignee {
  const AssignmentAssignee();

  const factory AssignmentAssignee.user({
    required String username,
    int? id,
    String? name,
    String? avatarUrl,
  }) = AssignmentUser;

  const factory AssignmentAssignee.group({
    required String name,
    int? id,
    String? fullName,
    String? flairIcon,
    String? flairColor,
    String? flairBackgroundColor,
  }) = AssignmentGroup;

  int? get id;
  String get identifier;
  String get displayName;
  String? get username;
  String? get groupName;
  String? get avatarUrl;
  bool get isGroup;
}

@immutable
final class AssignmentUser extends AssignmentAssignee {
  const AssignmentUser({
    required this.username,
    this.id,
    this.name,
    this.avatarUrl,
  });

  @override
  final int? id;

  @override
  final String username;

  final String? name;

  @override
  final String? avatarUrl;

  @override
  String get identifier => username;

  @override
  String get displayName => name ?? username;

  @override
  String? get groupName => null;

  @override
  bool get isGroup => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignmentUser &&
          other.id == id &&
          other.username == username &&
          other.name == name &&
          other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, username, name, avatarUrl);
}

@immutable
final class AssignmentGroup extends AssignmentAssignee {
  const AssignmentGroup({
    required this.name,
    this.id,
    this.fullName,
    this.flairIcon,
    this.flairColor,
    this.flairBackgroundColor,
  });

  @override
  final int? id;

  final String name;
  final String? fullName;
  final String? flairIcon;
  final String? flairColor;
  final String? flairBackgroundColor;

  @override
  String get identifier => name;

  @override
  String get displayName => fullName ?? name;

  @override
  String? get username => null;

  @override
  String get groupName => name;

  @override
  String? get avatarUrl => null;

  @override
  bool get isGroup => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignmentGroup &&
          other.id == id &&
          other.name == name &&
          other.fullName == fullName &&
          other.flairIcon == flairIcon &&
          other.flairColor == flairColor &&
          other.flairBackgroundColor == flairBackgroundColor;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    fullName,
    flairIcon,
    flairColor,
    flairBackgroundColor,
  );
}

/// One active assignment.
@immutable
class Assignment {
  const Assignment({
    required this.assignee,
    this.note,
    this.status,
    this.postId,
    this.postNumber,
  });

  final AssignmentAssignee assignee;
  final String? note;
  final String? status;

  /// Present for an assignment whose target is a post.
  final int? postId;
  final int? postNumber;

  bool get isPostAssignment => postId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Assignment &&
          other.assignee == assignee &&
          other.note == note &&
          other.status == status &&
          other.postId == postId &&
          other.postNumber == postNumber;

  @override
  int get hashCode => Object.hash(assignee, note, status, postId, postNumber);
}

/// Everything the plugin serialized for one topic or post.
///
/// The nullable parser result is the feature gate. A non-null record with a
/// null [canAssign] can still be a public, read-only assignment; an explicit
/// false means the plugin answered the permission question for this target.
@immutable
class Assignments {
  Assignments({
    required this.canAssign,
    this.direct,
    Map<int, Assignment> postAssignments = const {},
  }) : postAssignments = Map.unmodifiable(postAssignments);

  /// Defensive ceiling on parsed assignments across a topic and its posts.
  ///
  /// This is not the server's limit: `max_assignments_per_topic` is a raisable
  /// discourse-assign site setting, so every assignment under any realistic
  /// configuration must fit. The bound exists only so a pathological payload
  /// cannot allocate an unbounded assignment map.
  static const int maximumPerTopic = 50;

  static const _payloadKeys = {
    'can_assign',
    'assigned_to_user',
    'assigned_to_group',
    'indirectly_assigned_to',
    'assignment_note',
    'assignment_status',
  };

  /// Reads Assign fields attached to a topic view or topic-list item.
  ///
  /// Null means none of the plugin's fields were present. This is deliberately
  /// different from an enabled plugin returning `can_assign: false`.
  static Assignments? fromTopicJson(Map<String, dynamic> json, String siteUrl) {
    if (!_hasAssignPayload(json)) return null;

    final direct = _parseDirectAssignment(json, siteUrl);
    final indirectBudget = maximumPerTopic - (direct == null ? 0 : 1);
    final indirect = <int, Assignment>{};
    final rawIndirect = json['indirectly_assigned_to'];
    if (rawIndirect is Map<String, dynamic>) {
      for (final entry in rawIndirect.entries.take(indirectBudget)) {
        final postId = int.tryParse(entry.key);
        if (postId == null || postId <= 0) continue;
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final assignee = _parseUnknownAssignee(value['assigned_to'], siteUrl);
        if (assignee == null) continue;
        indirect[postId] = Assignment(
          assignee: assignee,
          note: jsonText(value['assignment_note']),
          status: jsonText(value['assignment_status']),
          postId: postId,
          postNumber: jsonIntOrNull(value['post_number']),
        );
      }
    }

    return Assignments(
      canAssign: _canAssign(json),
      direct: direct,
      postAssignments: indirect,
    );
  }

  /// Reads Assign fields attached to an individual post serializer.
  static Assignments? fromPostJson(Map<String, dynamic> json, String siteUrl) {
    if (!_hasAssignPayload(json)) return null;

    return Assignments(
      canAssign: _canAssign(json),
      direct: _parseDirectAssignment(
        json,
        siteUrl,
        postId: jsonIntOrNull(json['id']),
        postNumber: jsonIntOrNull(json['post_number']),
      ),
    );
  }

  final bool? canAssign;

  /// The assignment on this record itself: the topic for a topic payload, or
  /// the post for a post payload.
  final Assignment? direct;

  /// Active post assignments bundled into a topic payload, keyed by post id.
  final Map<int, Assignment> postAssignments;

  bool get hasAssignments => direct != null || postAssignments.isNotEmpty;

  Iterable<Assignment> get all => [?direct, ...postAssignments.values];

  Assignment? forPost(int postId) => postAssignments[postId];

  Assignments withDirect(Assignment? assignment) => Assignments(
    canAssign: canAssign,
    direct: assignment,
    postAssignments: postAssignments,
  );

  Assignments withPost(int postId, Assignment? assignment) {
    final updated = Map<int, Assignment>.of(postAssignments);
    if (assignment == null) {
      updated.remove(postId);
    } else {
      updated[postId] = assignment;
    }
    return Assignments(
      canAssign: canAssign,
      direct: direct,
      postAssignments: updated,
    );
  }

  static bool _hasAssignPayload(Map<String, dynamic> json) =>
      _payloadKeys.any(json.containsKey);

  static bool? _canAssign(Map<String, dynamic> json) =>
      json.containsKey('can_assign') ? json['can_assign'] == true : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Assignments &&
          other.canAssign == canAssign &&
          other.direct == direct &&
          mapEquals(other.postAssignments, postAssignments);

  @override
  int get hashCode => Object.hash(
    canAssign,
    direct,
    Object.hashAllUnordered(
      postAssignments.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}

/// The target-scoped candidates and group restrictions returned before search.
@immutable
class AssignmentSuggestions {
  /// Core returns the current user followed by at most five recent assignees.
  /// Bound raw slots before resolving avatars or constructing user models.
  static const int maximumSuggestedUsers = 6;

  AssignmentSuggestions({
    List<AssignmentUser> users = const [],
    List<String> assignAllowedOnGroups = const [],
    List<String> assignAllowedForGroups = const [],
  }) : users = List.unmodifiable(users),
       assignAllowedOnGroups = List.unmodifiable(assignAllowedOnGroups),
       assignAllowedForGroups = List.unmodifiable(assignAllowedForGroups);

  factory AssignmentSuggestions.fromJson(
    Map<String, dynamic> json,
    String siteUrl,
  ) => AssignmentSuggestions(
    users: [
      for (final value in jsonArray(
        json['suggestions'],
      ).take(maximumSuggestedUsers))
        if (value is Map<String, dynamic>) ?_parseUser(value, siteUrl),
    ],
    assignAllowedOnGroups: _uniqueNames(json['assign_allowed_on_groups']),
    assignAllowedForGroups: _uniqueNames(json['assign_allowed_for_groups']),
  );

  final List<AssignmentUser> users;

  /// Groups whose members may be offered as user assignees.
  final List<String> assignAllowedOnGroups;

  /// Groups which may themselves be selected as the assignee.
  final List<String> assignAllowedForGroups;

  Iterable<AssignmentAssignee> get initialAssignees => [
    ...users,
    for (final name in assignAllowedForGroups) AssignmentGroup(name: name),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignmentSuggestions &&
          listEquals(other.users, users) &&
          listEquals(other.assignAllowedOnGroups, assignAllowedOnGroups) &&
          listEquals(other.assignAllowedForGroups, assignAllowedForGroups);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(users),
    Object.hashAll(assignAllowedOnGroups),
    Object.hashAll(assignAllowedForGroups),
  );
}

Assignment? _parseDirectAssignment(
  Map<String, dynamic> json,
  String siteUrl, {
  int? postId,
  int? postNumber,
}) {
  final assignee =
      _parseUser(json['assigned_to_user'], siteUrl) ??
      _parseGroup(json['assigned_to_group']);
  if (assignee == null) return null;
  return Assignment(
    assignee: assignee,
    note: jsonText(json['assignment_note']),
    status: jsonText(json['assignment_status']),
    postId: postId,
    postNumber: postNumber,
  );
}

AssignmentAssignee? _parseUnknownAssignee(Object? value, String siteUrl) {
  if (value is! Map<String, dynamic>) return null;
  return _parseUser(value, siteUrl) ?? _parseGroup(value);
}

AssignmentUser? _parseUser(Object? value, String siteUrl) {
  if (value is! Map<String, dynamic>) return null;
  final username = jsonText(value['username']);
  if (username == null) return null;
  return AssignmentUser(
    id: jsonIntOrNull(value['id']),
    username: username,
    name: jsonText(value['name']),
    avatarUrl: resolveAvatarUrl(jsonText(value['avatar_template']), siteUrl),
  );
}

AssignmentGroup? _parseGroup(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final name = jsonText(value['name']);
  if (name == null) return null;
  return AssignmentGroup(
    id: jsonIntOrNull(value['id']),
    name: name,
    fullName: jsonText(value['full_name']) ?? jsonText(value['display_name']),
    flairIcon: jsonText(value['flair_icon']),
    flairColor: jsonText(value['flair_color']),
    flairBackgroundColor: jsonText(value['flair_bg_color']),
  );
}

List<String> _uniqueNames(Object? value) {
  final names = <String>[];
  final seen = <String>{};
  for (final raw in jsonArray(value)) {
    final name = jsonText(raw);
    if (name == null || !seen.add(name.toLowerCase())) continue;
    names.add(name);
  }
  return names;
}
