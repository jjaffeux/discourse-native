import '../../models/bookmark.dart';
import '../../models/json.dart';
import '../../plugin_api/plugin_manifest.dart';
import 'chat_wire.dart';

const chatMessageBookmarkTarget = BookmarkTargetType(
  owner: PluginId('chat'),
  name: 'message',
  wireName: chatMessageWireType,
  refreshLabel: 'chat message',
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
