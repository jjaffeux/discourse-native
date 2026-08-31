import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import '../models/json.dart';
import '../models/notification.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';

@immutable
final class PluginNotificationTypeId {
  const PluginNotificationTypeId({required this.owner, required this.name});

  final PluginId owner;
  final String name;
  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationTypeId &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => id;
}

@immutable
final class NotificationPresentation {
  const NotificationPresentation({
    required this.icon,
    required this.phrase,
    this.actor,
  });

  final DIconData icon;
  final String? actor;
  final String phrase;
}

@immutable
final class ResolvedNotification {
  const ResolvedNotification({required this.presentation, this.path});

  final NotificationPresentation presentation;
  final String? path;
}

/// Returning null means the payload was not usable and asks core to render its
/// safe fallback. The registry also isolates thrown decoder errors so one
/// malformed plugin row cannot make the user menu unusable.
typedef NotificationTypeDecoder =
    ResolvedNotification? Function(DiscourseNotification notification);

@immutable
final class PluginNotificationType {
  const PluginNotificationType({
    required this.id,
    required this.wireType,
    required this.decode,
  });

  final PluginNotificationTypeId id;
  final NotificationWireType wireType;
  final NotificationTypeDecoder decode;
}

const coreNotificationTypes = <PluginNotificationType>[
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'mentioned'),
    wireType: CoreNotificationTypes.mentioned,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'replied'),
    wireType: CoreNotificationTypes.replied,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'quoted'),
    wireType: CoreNotificationTypes.quoted,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'edited'),
    wireType: CoreNotificationTypes.edited,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'liked'),
    wireType: CoreNotificationTypes.liked,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'private-message',
    ),
    wireType: CoreNotificationTypes.privateMessage,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'invited-to-private-message',
    ),
    wireType: CoreNotificationTypes.invitedToPrivateMessage,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'invitee-accepted',
    ),
    wireType: CoreNotificationTypes.inviteeAccepted,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'posted'),
    wireType: CoreNotificationTypes.posted,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'moved-post'),
    wireType: CoreNotificationTypes.movedPost,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'linked'),
    wireType: CoreNotificationTypes.linked,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'granted-badge',
    ),
    wireType: CoreNotificationTypes.grantedBadge,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'invited-to-topic',
    ),
    wireType: CoreNotificationTypes.invitedToTopic,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'custom'),
    wireType: CoreNotificationTypes.custom,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'group-mentioned',
    ),
    wireType: CoreNotificationTypes.groupMentioned,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'group-message-summary',
    ),
    wireType: CoreNotificationTypes.groupMessageSummary,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'watching-first-post',
    ),
    wireType: CoreNotificationTypes.watchingFirstPost,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'topic-reminder',
    ),
    wireType: CoreNotificationTypes.topicReminder,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'liked-consolidated',
    ),
    wireType: CoreNotificationTypes.likedConsolidated,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'post-approved',
    ),
    wireType: CoreNotificationTypes.postApproved,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'membership-request-accepted',
    ),
    wireType: CoreNotificationTypes.membershipRequestAccepted,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'membership-request-consolidated',
    ),
    wireType: CoreNotificationTypes.membershipRequestConsolidated,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'bookmark-reminder',
    ),
    wireType: CoreNotificationTypes.bookmarkReminder,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'watching-category-or-tag',
    ),
    wireType: CoreNotificationTypes.watchingCategoryOrTag,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('core'), name: 'new-features'),
    wireType: CoreNotificationTypes.newFeatures,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'admin-problems',
    ),
    wireType: CoreNotificationTypes.adminProblems,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'linked-consolidated',
    ),
    wireType: CoreNotificationTypes.linkedConsolidated,
    decode: _decodeCoreNotification,
  ),
];

ResolvedNotification resolveCoreNotification(
  DiscourseNotification notification,
) {
  for (final definition in coreNotificationTypes) {
    if (definition.wireType.wireId == notification.typeId.value) {
      return definition.decode(notification) ??
          fallbackNotification(notification);
    }
  }
  return fallbackNotification(notification);
}

/// Topic identity belongs to the stable envelope, so it is the sole route the
/// fallback may derive. Plugin payload URLs and ids are deliberately ignored.
ResolvedNotification fallbackNotification(DiscourseNotification notification) =>
    ResolvedNotification(
      presentation: NotificationPresentation(
        icon: DIcons.bell,
        phrase: notification.title.isEmpty
            ? 'New notification'
            : notification.title,
      ),
      path: notificationTopicPath(notification),
    );

String? notificationTopicPath(DiscourseNotification notification) {
  final topicId = notification.topicId;
  if (topicId == null || topicId <= 0) return null;
  final slug = notification.slug.isEmpty ? 'topic' : notification.slug;
  final path = '/t/$slug/$topicId';
  final postNumber = notification.postNumber;
  return postNumber != null && postNumber > 1 ? '$path/$postNumber' : path;
}

ResolvedNotification? _decodeCoreNotification(
  DiscourseNotification notification,
) {
  final type = notification.typeId.value;
  final data = notification.data;
  final title = _coreTopicTitle(notification);
  final group = jsonText(data['group_name']) ?? 'a group';
  final count = jsonInt(data['count'] ?? data['inbox_count']);
  final namesActor = switch (type) {
    12 || 16 || 18 || 20 || 22 || 23 || 24 || 37 || 38 || 14 => false,
    _ => true,
  };
  final actor = namesActor
      ? jsonText(
              data['display_username'] ??
                  data['username'] ??
                  data['original_username'],
            ) ??
            'Someone'
      : null;
  final phrase = switch (type) {
    1 || 15 => 'mentioned you in $title',
    2 => 'replied to $title',
    3 => 'quoted you in $title',
    4 => 'edited your post in $title',
    5 => 'liked your post in $title',
    19 => 'liked ${_posts(count)}',
    39 => 'linked ${_posts(count)}',
    11 => 'linked to your post from $title',
    6 => 'sent you $title',
    7 || 13 => 'invited you to $title',
    8 => 'accepted your invitation',
    9 || 36 => 'posted in $title',
    17 => 'created $title',
    10 => 'moved $title',
    12 => switch (jsonText(data['badge_name'])) {
      final badge? => 'You earned the $badge badge',
      null => 'You earned a badge',
    },
    16 => '${_plural(count, 'message')} in your $group inbox',
    22 => "You're now a member of $group",
    23 => '${_plural(count, 'membership request')} for $group',
    18 || 24 => 'Reminder: $title',
    20 => 'Your post in $title was approved',
    37 => 'New features are available',
    38 => 'There is new advice on your site dashboard',
    14 => notification.title.isEmpty ? 'New notification' : notification.title,
    _ => null,
  };
  if (phrase == null) return null;

  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: _coreIcon(type),
      actor: actor,
      phrase: phrase,
    ),
    path: _corePath(notification),
  );
}

DIconData _coreIcon(int type) {
  final wireName = switch (type) {
    1 => CoreNotificationTypes.mentioned.wireName,
    2 => CoreNotificationTypes.replied.wireName,
    3 => CoreNotificationTypes.quoted.wireName,
    4 => CoreNotificationTypes.edited.wireName,
    5 => CoreNotificationTypes.liked.wireName,
    6 => CoreNotificationTypes.privateMessage.wireName,
    7 => CoreNotificationTypes.invitedToPrivateMessage.wireName,
    8 => CoreNotificationTypes.inviteeAccepted.wireName,
    9 => CoreNotificationTypes.posted.wireName,
    10 => CoreNotificationTypes.movedPost.wireName,
    11 => CoreNotificationTypes.linked.wireName,
    12 => CoreNotificationTypes.grantedBadge.wireName,
    13 => CoreNotificationTypes.invitedToTopic.wireName,
    14 => CoreNotificationTypes.custom.wireName,
    15 => CoreNotificationTypes.groupMentioned.wireName,
    16 => CoreNotificationTypes.groupMessageSummary.wireName,
    17 => CoreNotificationTypes.watchingFirstPost.wireName,
    18 => CoreNotificationTypes.topicReminder.wireName,
    19 => CoreNotificationTypes.likedConsolidated.wireName,
    20 => CoreNotificationTypes.postApproved.wireName,
    22 => CoreNotificationTypes.membershipRequestAccepted.wireName,
    23 => CoreNotificationTypes.membershipRequestConsolidated.wireName,
    24 => CoreNotificationTypes.bookmarkReminder.wireName,
    36 => CoreNotificationTypes.watchingCategoryOrTag.wireName,
    37 => CoreNotificationTypes.newFeatures.wireName,
    38 => CoreNotificationTypes.adminProblems.wireName,
    39 => CoreNotificationTypes.linkedConsolidated.wireName,
    _ => '',
  };
  return DIcons.byName['notification.$wireName'] ??
      switch (type) {
        9 || 17 || 36 => DIcons.comment,
        37 => DIcons.asterisk,
        38 => DIcons.triangleExclamation,
        _ => DIcons.bell,
      };
}

String? _corePath(DiscourseNotification notification) {
  final data = notification.data;
  final type = notification.typeId.value;
  final username = jsonText(data['username']);
  final group = jsonText(data['group_name']);
  final displayUsername = jsonText(data['display_username']);
  final ownPath = switch (type) {
    12 => _badgePath(data),
    16 when username != null && group != null =>
      '/u/$username/messages/group/$group',
    22 when group != null => '/g/$group',
    23 => '/my/messages',
    19 => '/my/notifications/likes-received${_actingUsername(username)}',
    39 => '/my/notifications/links${_actingUsername(username)}',
    8 when displayUsername != null => '/u/$displayUsername',
    37 => '/admin/whats-new',
    38 => '/admin',
    _ => null,
  };
  if (ownPath != null) return ownPath;
  if (notificationTopicPath(notification) case final topicPath?) {
    return topicPath;
  }

  if (data['bookmarkable_url'] case final String path
      when _isSafeSiteRelativePath(path)) {
    return path;
  }
  if (data['group_id'] != null && username != null && group != null) {
    return '/u/$username/messages/group/$group';
  }
  return null;
}

String _coreTopicTitle(DiscourseNotification notification) {
  final payloadTitle = notification.data['topic_title'];
  if (payloadTitle is String && payloadTitle.isNotEmpty) return payloadTitle;
  return notification.title.isEmpty ? 'a topic' : notification.title;
}

String? _badgePath(Map<String, Object?> data) {
  final id = jsonIntOrNull(data['badge_id']);
  if (id == null || id <= 0) return null;
  final slug =
      jsonText(data['badge_slug']) ??
      _badgeSlug(jsonString(data['badge_name']));
  final username = jsonText(data['username']);
  final query = username == null
      ? ''
      : '?username=${Uri.encodeQueryComponent(username.toLowerCase())}';
  if (slug.isEmpty) return '/badges/$id$query';
  return '/badges/$id/$slug$query';
}

String _actingUsername(String? username) => username == null
    ? ''
    : '?acting_username=${Uri.encodeQueryComponent(username)}';

bool _isSafeSiteRelativePath(String path) {
  if (!path.startsWith('/') || path.startsWith('//')) return false;
  final uri = Uri.tryParse(path);
  return uri != null && !uri.hasScheme && !uri.hasAuthority;
}

String _badgeSlug(String name) {
  final result = StringBuffer();
  var insideSeparator = false;
  for (final codeUnit in name.codeUnits) {
    if (_isAsciiBadgeSlugCodeUnit(codeUnit)) {
      result.writeCharCode(
        codeUnit >= 0x41 && codeUnit <= 0x5A ? codeUnit + 0x20 : codeUnit,
      );
      insideSeparator = false;
    } else if (!insideSeparator) {
      result.write('-');
      insideSeparator = true;
    }
  }
  return result.toString();
}

bool _isAsciiBadgeSlugCodeUnit(int value) =>
    (value >= 0x30 && value <= 0x39) ||
    (value >= 0x41 && value <= 0x5A) ||
    value == 0x5F ||
    (value >= 0x61 && value <= 0x7A);

String _posts(int count) =>
    count <= 1 ? 'one of your posts' : '$count of your posts';

String _plural(int count, String noun) =>
    count == 1 ? '1 $noun' : '$count ${noun}s';
