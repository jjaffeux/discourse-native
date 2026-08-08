import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import '../../models/post.dart';

/// One account that reacted to a post, and what with.
///
/// The sibling of `PostLiker`, and thin for the same reason: this is a row in a
/// list of names, and the card behind any of them is a separate fetch that only
/// happens if one is clicked.
@immutable
class PostReactor {
  const PostReactor({
    required this.id,
    required this.username,
    required this.reaction,
    this.name,
    this.avatarUrl,
  });

  factory PostReactor.fromJson(Map<String, dynamic> json, String siteUrl) {
    return PostReactor(
      id: jsonInt(json['id']),
      username: jsonString(json['username']),
      // Absent on a site with `enable_names` off, where the username is the
      // only name anyone has.
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      reaction: jsonString(json['reaction']),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;

  /// What they gave. Never empty in practice: the route's query labels a plain
  /// liker with the site's main reaction, so the merged list is uniform and
  /// there is no "liked but did not react" row to draw differently.
  final String reaction;

  String get displayName => name ?? username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostReactor &&
          other.id == id &&
          other.username == username &&
          other.name == name &&
          other.avatarUrl == avatarUrl &&
          other.reaction == reaction;

  @override
  int get hashCode => Object.hash(id, username, name, avatarUrl, reaction);
}

/// Who reacted to a post, oldest first, as the site listed them.
///
/// A record of its own rather than a field on the post, for the reason
/// `PostLikers` is: it is fetched separately and only when asked for. The
/// stream carries how many reacted, never who.
@immutable
class PostReactors with Storable<PostReactors> {
  const PostReactors({
    required this.postId,
    required this.reactors,
    required this.total,
    this.filter,
  });

  /// `{users: [...], total_rows: N}` — a different envelope from
  /// `post_action_users`, so a parser of its own rather than a flag on that one.
  static PostReactors parse(
    Map<String, dynamic> json, {
    required int postId,
    required String siteUrl,
    String? filter,
  }) => PostReactors(
    postId: postId,
    filter: filter,
    reactors: List.unmodifiable([
      for (final entry in jsonObjects(json['users']))
        PostReactor.fromJson(entry, siteUrl),
    ]),
    total: jsonInt(json['total_rows']),
  );

  final int postId;

  /// The emoji this list was narrowed to, or null for everyone who reacted.
  final String? filter;

  final List<PostReactor> reactors;

  /// How many there are in total, of which [reactors] is the first page.
  ///
  /// This is the number the panel counts with, and deliberately not
  /// `Reactions.userCount`: it comes from the same query as the rows, so "and N
  /// others" adds up. The other one counts reactions whose emoji has since been
  /// deleted, and provably exceeds what is on screen.
  final int total;

  /// Composite, so the unfiltered list and each per-emoji one are separate
  /// records rather than overwriting each other. `Store` keys on `Object`, so a
  /// String is as good an id as an int.
  @override
  Object get storeId => key(postId, filter);

  @override
  PostReactors merge(PostReactors incoming) =>
      this == incoming ? this : incoming;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostReactors &&
          other.postId == postId &&
          other.filter == filter &&
          other.total == total &&
          listEquals(other.reactors, reactors);

  @override
  int get hashCode =>
      Object.hash(postId, filter, total, Object.hashAll(reactors));

  static String key(int postId, String? filter) =>
      filter == null ? '$postId' : '$postId:$filter';
}
