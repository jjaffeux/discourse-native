import 'package:flutter/foundation.dart';

import 'json.dart';
import 'notification.dart';

/// The two core records the native client can bookmark.
enum BookmarkTargetType {
  post('Post'),
  topic('Topic');

  const BookmarkTargetType(this.wireName);

  final String wireName;

  static BookmarkTargetType? read(Object? value) {
    for (final type in values) {
      if (value == type.wireName) return type;
    }
    return null;
  }
}

/// What core should do with a bookmark after the event associated with it.
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

/// One row of the bookmarks tab.
///
/// Discourse serialises a bookmark through whichever serializer the bookmarked
/// thing registered — a post, a topic, a chat message, or whatever a plugin
/// added — so the only keys that can be relied on are the ones
/// `UserBookmarkBaseSerializer` declares. Those are exactly the ones read here:
/// what it is called, who wrote it, and where it goes. A bookmark on something
/// this app has never heard of still draws, and still opens.
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

  /// The compact bookmark metadata attached to a post serializer.
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

  /// Where the bookmark points, with a topic link taken back off whatever host
  /// the site wrote it against.
  ///
  /// `bookmarkable_url` is absolute, and built from `Discourse.base_url` — the
  /// site's own idea of where it lives, which is not necessarily the origin
  /// this app connected through. A development site says `localhost:4200`
  /// while the app is talking to the Rails port; a site behind a rename, a
  /// second domain or a CDN says whatever it was configured with. Left as it
  /// came, a topic on the site being read looks like a topic on a site that is
  /// not in the rail, and opens in the browser instead of here.
  ///
  /// So a topic link is reduced to its path, which the shell then resolves
  /// against the instance in hand the same way it resolves every other link
  /// Discourse writes. Everything else keeps the URL it was given: a
  /// bookmarkable a plugin registered can point anywhere at all, and there is
  /// nowhere in this app to open it either way.
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

  /// The server-side target. Unknown plugin types are retained for activity
  /// rows even though native creation is deliberately limited to core types.
  final int? bookmarkableId;
  final String? bookmarkableType;
  final int? postNumber;

  BookmarkTargetType? get coreTargetType =>
      BookmarkTargetType.read(bookmarkableType);

  /// The title of the thing bookmarked, or empty when the site sent none.
  final String title;

  /// The note the user attached when they bookmarked it, if they wrote one.
  /// Their own words about why, which is worth more than any wording of ours.
  final String? name;

  /// Who wrote the thing bookmarked, from the `user` the serializer hangs off
  /// every bookmarkable.
  final String? author;

  /// Where it points: site-relative for a topic, and whatever the site sent
  /// for anything else. See [_path].
  ///
  /// Null only for a bookmarkable whose serializer sent none, which leaves the
  /// row with nowhere to go.
  final String? path;

  /// When the reminder is due, for the bookmarks that have one set.
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

/// What `/u/{username}/user-menu-bookmarks.json` answers with.
///
/// Two lists, because the tab is two things: the bookmark reminders that have
/// come due and not been read, which Discourse puts at the top, and then as
/// many bookmarks as its twenty-row budget has left over.
typedef BookmarkPayload = ({
  List<DiscourseNotification> reminders,
  List<Bookmark> bookmarks,
});
