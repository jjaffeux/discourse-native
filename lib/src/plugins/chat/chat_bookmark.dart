import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'chat_wire.dart';

BookmarkTargetType get chatMessageBookmarkTarget => BookmarkTargetType(
  owner: const PluginId('chat'),
  name: 'message',
  wireName: chatMessageWireType,
  refreshLabel: appL10n.chatMessageChatbookmark,
);

Bookmark? chatMessageBookmarkFromJson(Map<String, dynamic> json) {
  final raw = json['bookmark'];
  if (raw is! Map<String, dynamic>) return null;
  final bookmarkId = jsonIntOrNull(raw['id']);
  final messageId = jsonIntOrNull(json['id']);
  final targetId = jsonIntOrNull(raw['bookmarkable_id']);
  final targetType = jsonText(raw['bookmarkable_type']);
  if (bookmarkId == null ||
      bookmarkId <= 0 ||
      messageId == null ||
      messageId <= 0 ||
      targetId != messageId ||
      (targetType != chatMessageBookmarkTarget.wireName &&
          targetType != chatMessagePolymorphicWireType)) {
    return null;
  }
  return Bookmark.fromJson({
    ...raw,
    // Keep the in-app target canonical so the bookmark host owns edits and
    // deletes, while accepting the polymorphic name serialized by Rails.
    'bookmarkable_type': chatMessageBookmarkTarget.wireName,
  });
}
