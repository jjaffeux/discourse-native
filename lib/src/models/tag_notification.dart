import 'package:flutter/foundation.dart';

import 'storable.dart';
import 'topic.dart';

/// Core gives `TagUser` and `CategoryUser` the same `NotificationLevels`.
typedef TagNotificationLevel = CategoryNotificationLevel;

/// The signed-in account's level for one tag.
@immutable
final class TagNotificationPreference with Storable<TagNotificationPreference> {
  const TagNotificationPreference({required this.tag, required this.level});

  /// The `:tag` of `/tag/:tag/notifications`, which core resolves as an id or
  /// a name. See `ContentRoute.notificationTag`.
  final String tag;
  final TagNotificationLevel level;

  @override
  Object get storeId => tag;

  @override
  TagNotificationPreference merge(TagNotificationPreference incoming) =>
      incoming == this ? this : incoming;

  @override
  bool operator ==(Object other) =>
      other is TagNotificationPreference &&
      other.tag == tag &&
      other.level == level;

  @override
  int get hashCode => Object.hash(tag, level);
}
