import 'package:flutter/foundation.dart';

import 'json.dart';
import 'storable.dart';

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

@immutable
class PostLikers with Storable<PostLikers> {
  const PostLikers({required this.postId, required this.likers});

  static const int maximumPageSize = 25;

  static PostLikers parse(
    Map<String, dynamic> json, {
    required int postId,
    required String siteUrl,
  }) {
    final seen = <int>{};
    return PostLikers(
      postId: postId,
      likers: List.unmodifiable([
        for (final entry in jsonObjects(
          json['post_action_users'],
        ).take(maximumPageSize))
          if (PostLiker.fromJson(entry, siteUrl) case final liker
              when liker.id > 0 &&
                  liker.username.trim().isNotEmpty &&
                  seen.add(liker.id))
            liker,
      ]),
    );
  }

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
