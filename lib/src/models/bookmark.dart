import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import 'json.dart';
import 'notification.dart';

@immutable
final class BookmarkTargetType {
  const BookmarkTargetType({
    required this.owner,
    required this.name,
    required this.wireName,
    required this.refreshLabel,
    this.updatesTopicBookmarkState = false,
  });

  static const post = BookmarkTargetType(
    owner: PluginId('core'),
    name: 'post',
    wireName: 'Post',
    refreshLabel: 'topic',
    updatesTopicBookmarkState: true,
  );
  static const topic = BookmarkTargetType(
    owner: PluginId('core'),
    name: 'topic',
    wireName: 'Topic',
    refreshLabel: 'topic',
    updatesTopicBookmarkState: true,
  );

  final PluginId owner;
  final String name;
  final String wireName;
  final String refreshLabel;
  final bool updatesTopicBookmarkState;

  String get id => '${owner.value}/$name';

  static BookmarkTargetType? read(Object? value) {
    for (final type in const [post, topic]) {
      if (value == type.wireName) return type;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is BookmarkTargetType &&
      other.owner == owner &&
      other.name == name &&
      other.wireName == wireName &&
      other.refreshLabel == refreshLabel &&
      other.updatesTopicBookmarkState == updatesTopicBookmarkState;

  @override
  int get hashCode => Object.hash(
    owner,
    name,
    wireName,
    refreshLabel,
    updatesTopicBookmarkState,
  );

  @override
  String toString() => id;
}

enum BookmarkAutoDeletePreference {
  never(0),
  whenReminderSent(1),
  onOwnerReply(2),
  clearReminder(3);

  const BookmarkAutoDeletePreference(this.wireValue);

  final int wireValue;

  static BookmarkAutoDeletePreference read(Object? value) {
    final wire = jsonIntOrNull(value);
    for (final preference in values) {
      if (preference.wireValue == wire) return preference;
    }
    return clearReminder;
  }
}

@immutable
class Bookmark {
  const Bookmark({
    required this.id,
    this.bookmarkableId,
    this.bookmarkableType,
    this.postNumber,
    this.title = '',
    this.name,
    this.author,
    this.path,
    this.reminderAt,
    this.autoDeletePreference = BookmarkAutoDeletePreference.clearReminder,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    final user = jsonObject(json['user']);

    return Bookmark(
      id: jsonInt(json['id']),
      bookmarkableId: jsonIntOrNull(json['bookmarkable_id']),
      bookmarkableType: jsonText(json['bookmarkable_type']),
      postNumber: jsonIntOrNull(json['post_number']),
      title: jsonTitle(json['title'], json['fancy_title']),
      name: jsonText(json['name']),
      author: jsonText(user['username']),
      path: _path(json['bookmarkable_url']),
      reminderAt: jsonDate(json['reminder_at']),
      autoDeletePreference: BookmarkAutoDeletePreference.read(
        json['auto_delete_preference'],
      ),
    );
  }

  static Bookmark? fromPostJson(Map<String, dynamic> json) {
    if (json['bookmarked'] != true) return null;
    final bookmarkId = jsonIntOrNull(json['bookmark_id']);
    final postId = jsonIntOrNull(json['id']);
    if (bookmarkId == null || bookmarkId <= 0 || postId == null) return null;
    return Bookmark(
      id: bookmarkId,
      bookmarkableId: postId,
      bookmarkableType: BookmarkTargetType.post.wireName,
      postNumber: jsonIntOrNull(json['post_number']),
      name: jsonText(json['bookmark_name']),
      reminderAt: jsonDate(json['bookmark_reminder_at']),
      autoDeletePreference: BookmarkAutoDeletePreference.read(
        json['bookmark_auto_delete_preference'],
      ),
    );
  }

  static String? _path(Object? value) {
    final url = jsonText(value);
    if (url == null) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;
    if (uri.pathSegments.firstOrNull != 't') return url;

    final path = StringBuffer(uri.path);
    if (uri.hasQuery) path.write('?${uri.query}');
    if (uri.hasFragment) path.write('#${uri.fragment}');
    return path.toString();
  }

  final int id;

  final int? bookmarkableId;
  final String? bookmarkableType;
  final int? postNumber;

  BookmarkTargetType? get coreTargetType =>
      BookmarkTargetType.read(bookmarkableType);

  final String title;

  final String? name;

  final String? author;

  final String? path;

  final DateTime? reminderAt;

  final BookmarkAutoDeletePreference autoDeletePreference;

  Bookmark copyWith({
    String? name,
    bool clearName = false,
    DateTime? reminderAt,
    bool clearReminder = false,
    BookmarkAutoDeletePreference? autoDeletePreference,
  }) => Bookmark(
    id: id,
    bookmarkableId: bookmarkableId,
    bookmarkableType: bookmarkableType,
    postNumber: postNumber,
    title: title,
    name: clearName ? null : (name ?? this.name),
    author: author,
    path: path,
    reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
    autoDeletePreference: autoDeletePreference ?? this.autoDeletePreference,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark &&
          other.id == id &&
          other.bookmarkableId == bookmarkableId &&
          other.bookmarkableType == bookmarkableType &&
          other.postNumber == postNumber &&
          other.title == title &&
          other.name == name &&
          other.author == author &&
          other.path == path &&
          other.reminderAt == reminderAt &&
          other.autoDeletePreference == autoDeletePreference;

  @override
  int get hashCode => Object.hash(
    id,
    bookmarkableId,
    bookmarkableType,
    postNumber,
    title,
    name,
    author,
    path,
    reminderAt,
    autoDeletePreference,
  );
}

typedef BookmarkPayload = ({
  List<DiscourseNotification> reminders,
  List<Bookmark> bookmarks,
});
