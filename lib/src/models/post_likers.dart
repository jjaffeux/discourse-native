import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'json.dart';
import 'post.dart';

/// One account that liked a post.
///
/// Deliberately thinner than a user card: this is a row in a list of names,
/// and the card behind any of them is a separate fetch that only happens if
/// one is clicked.
@immutable
class PostLiker {
  const PostLiker({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
  });

  factory PostLiker.fromJson(Map<String, dynamic> json, String siteUrl) {
    return PostLiker(
      id: jsonInt(json['id']),
      username: jsonString(json['username']),
      // Absent on a site with `enable_names` off, where the username is the
      // only name anyone has.
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;

  String get displayName => name ?? username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostLiker &&
          other.id == id &&
          other.username == username &&
          other.name == name &&
          other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, username, name, avatarUrl);
}

/// Who liked a post, oldest like first, as the site listed them.
///
/// A record of its own rather than a field on [Post] because it is fetched
/// separately and only when asked for — the stream carries how many people
/// liked a post, never which ones. Stored under the post's id, so the same
/// list is shared by the popup and the sheet and survives one being dismissed.
///
/// Possibly not all of them: the route pages, and a post can collect more
/// likes than a popup should draw. [Post.likeCount] remains the total, and the
/// difference is what a "and N others" line is counting.
@immutable
class PostLikers with Storable<PostLikers> {
  const PostLikers({required this.postId, required this.likers});

  /// Largest page requested by the native likes panel.
  ///
  /// Keep this parser boundary even though the query sends the same limit: a
  /// nonconforming response must not create an arbitrary eager column of user
  /// models and avatar loads.
  static const int maximumPageSize = 25;

  static PostLikers parse(
    Map<String, dynamic> json, {
    required int postId,
    required String siteUrl,
  }) => PostLikers(
    postId: postId,
    likers: List.unmodifiable([
      for (final entry in jsonObjects(
        json['post_action_users'],
      ).take(maximumPageSize))
        PostLiker.fromJson(entry, siteUrl),
    ]),
  );

  final int postId;
  final List<PostLiker> likers;

  @override
  Object get storeId => postId;

  @override
  PostLikers merge(PostLikers incoming) => this == incoming ? this : incoming;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostLikers &&
          other.postId == postId &&
          listEquals(other.likers, likers);

  @override
  int get hashCode => Object.hash(postId, Object.hashAll(likers));
}
