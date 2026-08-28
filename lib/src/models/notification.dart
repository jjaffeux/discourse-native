import 'package:flutter/foundation.dart';

import 'json.dart';

/// Discourse's numeric identity for a notification type.
///
/// This is deliberately an open value rather than an enum. Discourse plugins
/// and newer servers may add ids this build has never seen, and those ids must
/// survive parsing unchanged so an installed owner can interpret them later.
@immutable
final class NotificationTypeId {
  const NotificationTypeId(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is NotificationTypeId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

/// Discourse's wire name for a notification type.
///
/// Notification rows normally carry the numeric id, while
/// `filter_by_types` uses these names. Keeping the two values separate avoids
/// inventing a name for an unknown response id and lets arbitrary server or
/// plugin names be sent back without a closed core enum.
@immutable
final class NotificationTypeName {
  const NotificationTypeName(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is NotificationTypeName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A known pairing of the two notification type identities used by Discourse.
///
/// Core declares only core types. Optional feature modules declare their own
/// pairings beside their decoders and presentation behavior.
@immutable
final class NotificationWireType {
  const NotificationWireType(this.wireId, this.wireName);

  final int wireId;
  final String wireName;

  @override
  bool operator ==(Object other) =>
      other is NotificationWireType &&
      other.wireId == wireId &&
      other.wireName == wireName;

  @override
  int get hashCode => Object.hash(wireId, wireName);

  @override
  String toString() => '$wireName($wireId)';
}

/// Notification types owned by Discourse core.
///
/// Optional Chat, Assign, Reactions, Follow and voting types intentionally do
/// not appear here. Their modules may register them; without those modules the
/// raw row remains visible through the generic fallback.
abstract final class CoreNotificationTypes {
  static const mentioned = NotificationWireType(1, 'mentioned');
  static const replied = NotificationWireType(2, 'replied');
  static const quoted = NotificationWireType(3, 'quoted');
  static const edited = NotificationWireType(4, 'edited');
  static const liked = NotificationWireType(5, 'liked');
  static const privateMessage = NotificationWireType(6, 'private_message');
  static const invitedToPrivateMessage = NotificationWireType(
    7,
    'invited_to_private_message',
  );
  static const inviteeAccepted = NotificationWireType(8, 'invitee_accepted');
  static const posted = NotificationWireType(9, 'posted');
  static const movedPost = NotificationWireType(10, 'moved_post');
  static const linked = NotificationWireType(11, 'linked');
  static const grantedBadge = NotificationWireType(12, 'granted_badge');
  static const invitedToTopic = NotificationWireType(13, 'invited_to_topic');
  static const custom = NotificationWireType(14, 'custom');
  static const groupMentioned = NotificationWireType(15, 'group_mentioned');
  static const groupMessageSummary = NotificationWireType(
    16,
    'group_message_summary',
  );
  static const watchingFirstPost = NotificationWireType(
    17,
    'watching_first_post',
  );
  static const topicReminder = NotificationWireType(18, 'topic_reminder');
  static const likedConsolidated = NotificationWireType(
    19,
    'liked_consolidated',
  );
  static const postApproved = NotificationWireType(20, 'post_approved');
  static const membershipRequestAccepted = NotificationWireType(
    22,
    'membership_request_accepted',
  );
  static const membershipRequestConsolidated = NotificationWireType(
    23,
    'membership_request_consolidated',
  );
  static const bookmarkReminder = NotificationWireType(24, 'bookmark_reminder');
  static const watchingCategoryOrTag = NotificationWireType(
    36,
    'watching_category_or_tag',
  );
  static const newFeatures = NotificationWireType(37, 'new_features');
  static const adminProblems = NotificationWireType(38, 'admin_problems');
  static const linkedConsolidated = NotificationWireType(
    39,
    'linked_consolidated',
  );

  static const values = <NotificationWireType>[
    mentioned,
    replied,
    quoted,
    edited,
    liked,
    privateMessage,
    invitedToPrivateMessage,
    inviteeAccepted,
    posted,
    movedPost,
    linked,
    grantedBadge,
    invitedToTopic,
    custom,
    groupMentioned,
    groupMessageSummary,
    watchingFirstPost,
    topicReminder,
    likedConsolidated,
    postApproved,
    membershipRequestAccepted,
    membershipRequestConsolidated,
    bookmarkReminder,
    watchingCategoryOrTag,
    newFeatures,
    adminProblems,
    linkedConsolidated,
  ];
}

/// The core notification names Discourse groups into the Replies user-menu
/// tab, in the order used by core's `CORE_TOP_TABS` definition.
const userMenuReplyNotificationTypes = <NotificationTypeName>[
  NotificationTypeName('mentioned'),
  NotificationTypeName('group_mentioned'),
  NotificationTypeName('posted'),
  NotificationTypeName('quoted'),
  NotificationTypeName('replied'),
];

/// One notification row exactly as received from Discourse.
///
/// The envelope exposes a few stable core fields for list state and a safe
/// topic fallback. Its type id and free-form [data] remain opaque. Feature
/// modules decode that data only after their notification definition has been
/// selected by the installed registry.
@immutable
final class DiscourseNotification {
  factory DiscourseNotification({
    required int id,
    required NotificationTypeId typeId,
    NotificationTypeName? typeName,
    bool read = false,
    DateTime? createdAt,
    int? topicId,
    int? postNumber,
    String slug = '',
    String title = '',
    Map<String, Object?> data = const {},
  }) {
    final envelope = <String, Object?>{
      'id': id,
      'notification_type': typeId.value,
      if (typeName != null) 'notification_type_name': typeName.value,
      'read': read,
      if (createdAt != null) 'created_at': createdAt.toIso8601String(),
      'topic_id': ?topicId,
      'post_number': ?postNumber,
      if (slug.isNotEmpty) 'slug': slug,
      if (title.isNotEmpty) 'fancy_title': title,
      'data': data,
    };
    return DiscourseNotification.fromJson(envelope);
  }

  /// A const constructor for local fixtures which do not originate at a JSON
  /// boundary. Production wire parsing must use [fromJson], which deep-freezes
  /// the complete envelope and payload.
  @visibleForTesting
  const DiscourseNotification.test({
    required this.id,
    required this.typeId,
    this.typeName,
    this.read = false,
    this.createdAt,
    this.topicId,
    this.postNumber,
    this.slug = '',
    this.title = '',
    this.data = const {},
  }) : wire = const {};

  factory DiscourseNotification.fromJson(Map<String, dynamic> json) {
    final wire = _freezeObject(json);
    final payload = switch (wire['data']) {
      final Map<String, Object?> value => value,
      _ => const <String, Object?>{},
    };
    final rawName = jsonText(
      wire['notification_type_name'] ?? wire['notification_name'],
    );

    return DiscourseNotification._(
      wire: wire,
      id: jsonInt(wire['id']),
      typeId: NotificationTypeId(jsonInt(wire['notification_type'])),
      typeName: rawName == null ? null : NotificationTypeName(rawName),
      read: wire['read'] == true,
      createdAt: jsonDate(wire['created_at']),
      topicId: wire['topic_id'] == null
          ? null
          : jsonIntOrNull(wire['topic_id']),
      postNumber: wire['post_number'] == null
          ? null
          : jsonIntOrNull(wire['post_number']),
      slug: jsonString(wire['slug']),
      // `data` belongs to the notification type owner. Core may expose the
      // stable top-level browser title, but must not interpret a payload key
      // before an installed owner has claimed the type.
      title: jsonTitle(null, wire['fancy_title']),
      data: payload,
    );
  }

  const DiscourseNotification._({
    required this.wire,
    required this.id,
    required this.typeId,
    required this.typeName,
    required this.read,
    required this.createdAt,
    required this.topicId,
    required this.postNumber,
    required this.slug,
    required this.title,
    required this.data,
  });

  /// The complete, deeply immutable wire envelope.
  ///
  /// Unknown top-level keys are retained for the same reason unknown payload
  /// keys are retained: parsing through a smaller/core-only build must not be
  /// destructive.
  final Map<String, Object?> wire;

  final int id;
  final NotificationTypeId typeId;

  /// A name is exposed only when the wire actually supplied one. Normal
  /// `/notifications` rows carry an id alone, so unknown ids do not acquire a
  /// fabricated name.
  final NotificationTypeName? typeName;
  final bool read;
  final DateTime? createdAt;
  final int? topicId;
  final int? postNumber;
  final String slug;

  /// The decoded top-level `fancy_title`, or empty when the envelope omitted
  /// it. Type-owned alternatives such as `data.topic_title` stay in [data]
  /// until the registered owner resolves this row.
  final String title;

  /// The complete, deeply immutable type-owned payload.
  final Map<String, Object?> data;

  bool get isUnread => !read;

  /// A mutable JSON-shaped copy suitable for persistence or transport.
  Map<String, dynamic> toJson() {
    if (wire.isNotEmpty) return _thawObject(wire);
    return <String, dynamic>{
      'id': id,
      'notification_type': typeId.value,
      if (typeName != null) 'notification_type_name': typeName!.value,
      'read': read,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'topic_id': ?topicId,
      'post_number': ?postNumber,
      if (slug.isNotEmpty) 'slug': slug,
      if (title.isNotEmpty) 'fancy_title': title,
      'data': _thawObject(data),
    };
  }

  DiscourseNotification asRead() {
    if (read) return this;
    final updated = toJson()..['read'] = true;
    return DiscourseNotification.fromJson(updated);
  }
}

Map<String, Object?> _freezeObject(Map<dynamic, dynamic> source) =>
    Map<String, Object?>.unmodifiable({
      for (final entry in source.entries)
        if (entry.key is String) entry.key as String: _freezeValue(entry.value),
    });

Object? _freezeValue(Object? value) => switch (value) {
  final Map<dynamic, dynamic> map => _freezeObject(map),
  final List<dynamic> list => List<Object?>.unmodifiable(
    list.map(_freezeValue),
  ),
  _ => value,
};

Map<String, dynamic> _thawObject(Map<String, Object?> source) => {
  for (final entry in source.entries) entry.key: _thawValue(entry.value),
};

Object? _thawValue(Object? value) => switch (value) {
  final Map<String, Object?> map => _thawObject(map),
  final List<Object?> list => <Object?>[
    for (final item in list) _thawValue(item),
  ],
  _ => value,
};
