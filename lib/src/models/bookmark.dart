import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

import 'notification.dart';

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
    this.title = '',
    this.name,
    this.author,
    this.path,
    this.reminderAt,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};

    return Bookmark(
      id: switch (json['id']) {
        final num id => id.toInt(),
        _ => 0,
      },
      title: _title(json),
      name: _text(json['name']),
      author: _text(user['username']),
      path: _path(json['bookmarkable_url']),
      reminderAt: DateTime.tryParse((json['reminder_at'] ?? '') as String),
    );
  }

  /// What the bookmark is on, as plain text.
  ///
  /// `title` already is plain, which is why it comes first; `fancy_title` is
  /// Discourse's HTML rendering of the same string — smart quotes as entities,
  /// ampersands escaped — and only means anything once unescaped.
  static String _title(Map<String, dynamic> json) {
    if (json['title'] case final String title when title.isNotEmpty) {
      return title;
    }
    final fancy = json['fancy_title'] as String?;
    if (fancy == null || fancy.isEmpty) return '';
    return html.parseFragment(fancy).text ?? fancy;
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
    final url = _text(value);
    if (url == null) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;
    if (uri.pathSegments.firstOrNull != 't') return url;

    final path = StringBuffer(uri.path);
    if (uri.hasQuery) path.write('?${uri.query}');
    if (uri.hasFragment) path.write('#${uri.fragment}');
    return path.toString();
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  final int id;

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
