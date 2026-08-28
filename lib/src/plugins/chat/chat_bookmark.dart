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

/// The complete bookmark object attached by `Chat::MessageSerializer`.
Bookmark? chatMessageBookmarkFromJson(Map<String, dynamic> json) {
  final raw = json['bookmark'];
  if (raw is! Map<String, dynamic>) return null;
  final bookmarkId = jsonIntOrNull(raw['id']);
  final messageId = jsonIntOrNull(json['id']);
  final targetId = jsonIntOrNull(raw['bookmarkable_id']);
  if (bookmarkId == null ||
      bookmarkId <= 0 ||
      messageId == null ||
      messageId <= 0 ||
      targetId != messageId ||
      jsonText(raw['bookmarkable_type']) !=
          chatMessageBookmarkTarget.wireName) {
    return null;
  }
  return Bookmark.fromJson(raw);
}
