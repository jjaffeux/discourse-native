import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/json.dart';
import '../../plugin_api/reaction_presentation.dart';

@immutable
class PostReactor implements ReactionUser {
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
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      reaction: jsonString(json['reaction']),
    );
  }

  @override
  final int id;

  @override
  final String username;

  @override
  final String? name;

  @override
  final String? avatarUrl;

  @override
  final String reaction;

  @override
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

@immutable
class PostReactors with Storable<PostReactors> implements ReactionUsersPage {
  const PostReactors({
    required this.postId,
    required this.reactors,
    required this.total,
    this.filter,
  });

  /// Plugin page size and the eager client parsing ceiling.
  static const int maximumPageSize = 50;

  static PostReactors parse(
    Map<String, dynamic> json, {
    required int postId,
    required String siteUrl,
    String? filter,
  }) => PostReactors(
    postId: postId,
    filter: filter,
    reactors: List.unmodifiable(
      jsonObjects(json['users'])
          .take(maximumPageSize)
          .map((entry) => PostReactor.fromJson(entry, siteUrl)),
    ),
    total: jsonInt(json['total_rows']),
  );

  final int postId;

  final String? filter;

  @override
  final List<PostReactor> reactors;

  /// Total from the rows query; unlike `Reactions.userCount`, it excludes
  /// reactions whose emoji has been deleted.
  @override
  final int total;

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
