import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import '../foundation/count_label.dart';
import '../models/discourse_instance.dart';
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

  /// Where opening the notification leads, written from the forum root the
  /// way a forum served at its host's root would write it (`/t/a-topic/7/2`,
  /// `/g/staff`, `/chat/c/-/5/44`) on every forum. The shell puts a subfolder
  /// forum's prefix in front when it opens the path, so a decoder builds its
  /// paths without knowing where the forum is served.
  ///
  /// A link the server wrote, such as a bookmark reminder's
  /// `bookmarkable_url`, already starts with that prefix. A decoder that
  /// forwards one removes the prefix first, with
  /// `DiscourseInstance.pathAndQueryWithinUrl` against the site it was given,
  /// so every path means the same thing and the prefix is added exactly once;
  /// a link that is not under the forum leaves no path.
  final String? path;
}

/// [siteUrl] is the forum [notification] came from, which a decoder needs
/// only to forward a link the server wrote; see [ResolvedNotification.path].
///
/// Returning null means the payload was not usable and asks core to render its
/// safe fallback. The registry also isolates thrown decoder errors so one
/// malformed plugin row cannot make the user menu unusable.
typedef NotificationTypeDecoder =
    ResolvedNotification? Function(
      String siteUrl,
      DiscourseNotification notification,
    );

enum CoreNotificationMenuSection { likes }

@immutable
final class PluginNotificationType {
  const PluginNotificationType({
    required this.id,
    required this.wireType,
    required this.decode,
    this.coreMenuSection,
  });

  final PluginNotificationTypeId id;
  final NotificationWireType wireType;
  final NotificationTypeDecoder decode;
  final CoreNotificationMenuSection? coreMenuSection;
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
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'upcoming-change-available',
    ),
    wireType: CoreNotificationTypes.upcomingChangeAvailable,
    decode: _decodeCoreNotification,
  ),
  PluginNotificationType(
    id: PluginNotificationTypeId(
      owner: PluginId('core'),
      name: 'upcoming-change-automatically-promoted',
    ),
    wireType: CoreNotificationTypes.upcomingChangeAutomaticallyPromoted,
    decode: _decodeCoreNotification,
  ),
];

ResolvedNotification resolveCoreNotification(
  String siteUrl,
  DiscourseNotification notification,
) {
  for (final definition in coreNotificationTypes) {
    if (definition.wireType.wireId == notification.typeId.value) {
      return definition.decode(siteUrl, notification) ??
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
            ? appL10n.newNotification
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
  return postNumber != null && postNumber > 0 ? '$path/$postNumber' : path;
}

ResolvedNotification? _decodeCoreNotification(
  String siteUrl,
  DiscourseNotification notification,
) {
  final type = notification.typeId.value;
  final data = notification.data;
  final title = _coreTopicTitle(notification);
  final group = jsonText(data['group_name']) ?? appL10n.aGroup;
  final count = jsonInt(data['count'] ?? data['inbox_count']);
  final namesActor = switch (type) {
    12 ||
    14 ||
    16 ||
    18 ||
    20 ||
    22 ||
    23 ||
    24 ||
    37 ||
    38 ||
    41 ||
    42 => false,
    _ => true,
  };
  final actor = namesActor
      ? jsonText(
              data['display_username'] ??
                  data['username'] ??
                  data['original_username'],
            ) ??
            appL10n.someone
      : null;
  final phrase = switch (type) {
    1 || 15 => appL10n.mentionedYouInNotificationtypes((title).toString()),
    2 => appL10n.repliedTo((title).toString()),
    3 => appL10n.quotedYouIn((title).toString()),
    4 => appL10n.editedYourPostIn((title).toString()),
    5 => appL10n.likedYourPostIn((title).toString()),
    19 => appL10n.liked((_posts(count)).toString()),
    39 => appL10n.linked((_posts(count)).toString()),
    11 => appL10n.linkedToYourPostFrom((title).toString()),
    6 => appL10n.sentYou((title).toString()),
    7 || 13 => appL10n.invitedYouToNotificationtypes((title).toString()),
    8 => appL10n.acceptedYourInvitation,
    9 || 36 => appL10n.postedIn((title).toString()),
    17 => appL10n.created((title).toString()),
    10 => appL10n.moved((title).toString()),
    12 => switch (jsonText(data['badge_name'])) {
      final badge? => appL10n.youEarnedTheBadge((badge).toString()),
      null => appL10n.youEarnedABadge,
    },
    16 => appL10n.inYourInbox(
      (countLabel(count, CountNoun.message)).toString(),
      (group).toString(),
    ),
    22 => appL10n.youReNowAMemberOf((group).toString()),
    23 => appL10n.messageFor(
      (countLabel(count, CountNoun.membershipRequest)).toString(),
      (group).toString(),
    ),
    18 || 24 => appL10n.reminderNotificationtypes(
      (_reminderTitle(notification)).toString(),
    ),
    20 => appL10n.yourPostInWasApproved((title).toString()),
    37 => appL10n.newFeaturesAreAvailable,
    38 => appL10n.thereIsNewAdviceOnYourSiteDashboard,
    14 =>
      notification.title.isEmpty ? appL10n.newNotification : notification.title,
    41 => _upcomingChangePhrase(data, automaticallyPromoted: false),
    42 => _upcomingChangePhrase(data, automaticallyPromoted: true),
    _ => null,
  };
  if (phrase == null) return null;

  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: _coreIcon(type),
      actor: actor,
      phrase: phrase,
    ),
    path: _corePath(siteUrl, notification),
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
    41 => CoreNotificationTypes.upcomingChangeAvailable.wireName,
    42 => CoreNotificationTypes.upcomingChangeAutomaticallyPromoted.wireName,
    _ => '',
  };
  return DIcons.byName['notification.$wireName'] ??
      switch (type) {
        9 || 17 || 36 => DIcons.discourseBellExclamation,
        37 => DIcons.asterisk,
        41 => DIcons.flask,
        42 => DIcons.discourseFlaskCheck,
        38 => DIcons.triangleExclamation,
        _ => DIcons.bell,
      };
}

String? _corePath(String siteUrl, DiscourseNotification notification) {
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
    41 || 42 => _upcomingChangePath(data),
    _ => null,
  };
  if (ownPath != null) return ownPath;
  if (notificationTopicPath(notification) case final topicPath?) {
    return topicPath;
  }

  // Discourse writes this link with the forum's subfolder in front.
  if (data['bookmarkable_url'] case final String written) {
    if (DiscourseInstance.pathAndQueryWithinUrl(siteUrl, written)
        case final path?) {
      return path;
    }
  }
  if (data['group_id'] != null && username != null && group != null) {
    return '/u/$username/messages/group/$group';
  }
  return null;
}

String _coreTopicTitle(DiscourseNotification notification) {
  final payloadTitle = notification.data['topic_title'];
  if (payloadTitle is String && payloadTitle.isNotEmpty) return payloadTitle;
  return notification.title.isEmpty ? appL10n.aTopic : notification.title;
}

/// A reminder names what was bookmarked. A post or topic bookmark carries
/// the topic title on the envelope; a chat message bookmark has no topic and
/// carries only the `title` its bookmarkable wrote into the payload ("Chat
/// message in #channel"), which is what core's bookmark-reminder.js falls
/// back to.
String _reminderTitle(DiscourseNotification notification) {
  final data = notification.data;
  final topicTitle = data['topic_title'];
  if (topicTitle is String && topicTitle.isNotEmpty) return topicTitle;
  if (notification.title.isNotEmpty) return notification.title;
  final title = data['title'];
  if (title is String && title.isNotEmpty) return title;
  return appL10n.aTopic;
}

String _upcomingChangePhrase(
  Map<String, Object?> data, {
  required bool automaticallyPromoted,
}) {
  final names = _notificationTexts(
    data['upcoming_change_humanized_names'],
    data['upcoming_change_humanized_name'],
  );
  var count = jsonInt(data['count']);
  if (count <= 0) count = names.length;

  if (names.isEmpty) {
    return automaticallyPromoted
        ? appL10n.upcomingChangesWereAutomaticallyEnabled
        : appL10n.upcomingChangesAreAvailableForPreview;
  }
  if (count <= 1) {
    return automaticallyPromoted
        ? appL10n.hasBeenAutomaticallyEnabled((names.first).toString())
        : appL10n.isAvailableForPreview((names.first).toString());
  }
  if (count == 2 && names.length > 1) {
    return automaticallyPromoted
        ? appL10n.andWereAutomaticallyEnabled(
            (names[0]).toString(),
            (names[1]).toString(),
          )
        : appL10n.andAreAvailableForPreview(
            (names[0]).toString(),
            (names[1]).toString(),
          );
  }

  final otherCount = count - 1;
  return automaticallyPromoted
      ? appL10n.andMoreChangesWereAutomaticallyEnabled(
          (names.first).toString(),
          (otherCount).toString(),
        )
      : appL10n.andMoreChangesAreAvailableForPreview(
          (names.first).toString(),
          (otherCount).toString(),
        );
}

String _upcomingChangePath(Map<String, Object?> data) {
  const base = '/admin/config/upcoming-changes';
  final names = _notificationTexts(
    data['upcoming_change_names'],
    data['upcoming_change_name'],
  );
  if (names.isEmpty) return base;
  return '$base?changeNamesFilter=${Uri.encodeQueryComponent(names.join(','))}';
}

List<String> _notificationTexts(Object? values, Object? singular) {
  if (values case final List<Object?> values) {
    final texts = values.map(jsonText).whereType<String>().toList();
    if (texts.isNotEmpty) return texts;
  }
  return switch (jsonText(singular)) {
    final text? => [text],
    null => const [],
  };
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

String _posts(int count) => count <= 1
    ? appL10n.oneOfYourPosts
    : appL10n.ofYourPosts((count).toString());
