import 'package:flutter/foundation.dart';

import '../data/store.dart';
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
    final name = (json['name'] as String?)?.trim();
    return PostLiker(
      id: switch (json['id']) {
        final num id => id.toInt(),
        _ => 0,
      },
      username: (json['username'] ?? '') as String,
      // Absent on a site with `enable_names` off, where the username is the
      // only name anyone has.
      name: name == null || name.isEmpty ? null : name,
      avatarUrl: resolveAvatarUrl(json['avatar_template'] as String?, siteUrl),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;

  String get displayName => name ?? username;
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

  static PostLikers parse(
    Map<String, dynamic> json, {
    required int postId,
    required String siteUrl,
  }) => PostLikers(
    postId: postId,
    likers: [
      for (final entry
          in json['post_action_users'] as List<dynamic>? ?? const [])
        if (entry is Map<String, dynamic>) PostLiker.fromJson(entry, siteUrl),
    ],
  );

  final int postId;
  final List<PostLiker> likers;

  @override
  Object get storeId => postId;
}
