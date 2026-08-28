import 'package:flutter/foundation.dart';

import 'json.dart';

/// The two values surrounding one revision.
///
/// A null value is meaningful for fields such as category and locale, so the
/// enclosing object is what distinguishes "unchanged" from "changed to or
/// from nothing".
@immutable
class PostRevisionChange<T> {
  const PostRevisionChange({required this.previous, required this.current});

  static PostRevisionChange<T>? fromJson<T>(
    Object? value,
    T? Function(Object? value) parse,
  ) {
    final json = jsonObject(value);
    if (!json.containsKey('previous') && !json.containsKey('current')) {
      return null;
    }
    return PostRevisionChange(
      previous: parse(json['previous']),
      current: parse(json['current']),
    );
  }

  final T? previous;
  final T? current;
}

/// Server-rendered representations of one edit.
@immutable
class PostRevisionDiff {
  const PostRevisionDiff({
    this.inline,
    this.sideBySide,
    this.sideBySideMarkdown,
  });

  static PostRevisionDiff? fromJson(Object? value) {
    final json = jsonObject(value);
    final inline = jsonText(json['inline']);
    final sideBySide = jsonText(json['side_by_side']);
    final sideBySideMarkdown = jsonText(json['side_by_side_markdown']);
    if (inline == null && sideBySide == null && sideBySideMarkdown == null) {
      return null;
    }
    return PostRevisionDiff(
      inline: inline,
      sideBySide: sideBySide,
      sideBySideMarkdown: sideBySideMarkdown,
    );
  }

  final String? inline;
  final String? sideBySide;
  final String? sideBySideMarkdown;
}

@immutable
class PostRevisionUser {
  const PostRevisionUser({
    required this.username,
    this.displayUsername,
    this.avatarUrl,
  });

  static PostRevisionUser? fromJson(Object? value, String siteUrl) {
    final json = jsonObject(value);
    final username = jsonText(json['username']);
    final displayUsername = jsonText(json['display_username']);
    final avatarUrl = resolveAvatarUrl(
      jsonText(json['avatar_template']),
      siteUrl,
    );
    if (username == null && displayUsername == null && avatarUrl == null) {
      return null;
    }
    return PostRevisionUser(
      username: username ?? displayUsername ?? '',
      displayUsername: displayUsername,
      avatarUrl: avatarUrl,
    );
  }

  final String username;
  final String? displayUsername;
  final String? avatarUrl;

  String get displayName => displayUsername ?? username;
}

@immutable
class PostRevisionReplyTarget {
  const PostRevisionReplyTarget({required this.postNumber, this.username});

  static PostRevisionReplyTarget? fromJson(Object? value) {
    final json = jsonObject(value);
    final postNumber = jsonIntOrNull(json['post_number']);
    if (postNumber == null || postNumber <= 0) return null;
    return PostRevisionReplyTarget(
      postNumber: postNumber,
      username: jsonText(json['username']),
    );
  }

  final int postNumber;
  final String? username;
}

/// One comparison returned by core's post revision endpoint.
///
/// The endpoint owns the diff. Native renders its inline HTML rather than
/// trying to reconstruct markdown or topic metadata changes from the current
/// post, which would lose edits made between the two versions being viewed.
@immutable
class PostRevision {
  const PostRevision({
    required this.postId,
    required this.currentRevision,
    required this.currentVersion,
    required this.versionCount,
    this.createdAt,
    this.previousHidden = false,
    this.currentHidden = false,
    this.firstRevision,
    this.previousRevision,
    this.nextRevision,
    this.lastRevision,
    this.username = '',
    this.displayUsername,
    this.actingUserName,
    this.avatarUrl,
    this.editReason,
    this.bodyChanges,
    this.titleChanges,
    this.userChanges,
    this.replyToPostNumberChanges,
    this.tagsChanges,
    this.categoryIdChanges,
    this.wikiChanges,
    this.postTypeChanges,
    this.localeChanges,
    this.archetypeChanges,
    this.featuredLinkChanges,
    this.canEdit = false,
    this.diffError = false,
  });

  factory PostRevision.fromJson(Map<String, dynamic> json, String siteUrl) =>
      PostRevision(
        postId: jsonInt(json['post_id']),
        createdAt: jsonDate(json['created_at']),
        previousHidden: json['previous_hidden'] == true,
        currentHidden: json['current_hidden'] == true,
        firstRevision: jsonIntOrNull(json['first_revision']),
        previousRevision: jsonIntOrNull(json['previous_revision']),
        currentRevision: jsonInt(json['current_revision']),
        nextRevision: jsonIntOrNull(json['next_revision']),
        lastRevision: jsonIntOrNull(json['last_revision']),
        currentVersion: jsonInt(json['current_version']),
        versionCount: jsonInt(json['version_count']),
        username: jsonString(json['username']),
        displayUsername: jsonText(json['display_username']),
        actingUserName: jsonText(json['acting_user_name']),
        avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
        editReason: jsonText(json['edit_reason']),
        bodyChanges: PostRevisionDiff.fromJson(json['body_changes']),
        titleChanges: PostRevisionDiff.fromJson(json['title_changes']),
        userChanges: PostRevisionChange.fromJson(
          json['user_changes'],
          (value) => PostRevisionUser.fromJson(value, siteUrl),
        ),
        replyToPostNumberChanges: PostRevisionChange.fromJson(
          json['reply_to_post_number_changes'],
          PostRevisionReplyTarget.fromJson,
        ),
        tagsChanges: PostRevisionChange.fromJson(
          json['tags_changes'],
          (value) =>
              List<String>.unmodifiable(jsonArray(value).whereType<String>()),
        ),
        categoryIdChanges: PostRevisionChange.fromJson(
          json['category_id_changes'],
          jsonIntOrNull,
        ),
        wikiChanges: PostRevisionChange.fromJson(
          json['wiki_changes'],
          (value) => value is bool ? value : null,
        ),
        postTypeChanges: PostRevisionChange.fromJson(
          json['post_type_changes'],
          jsonIntOrNull,
        ),
        localeChanges: PostRevisionChange.fromJson(
          json['locale_changes'],
          jsonText,
        ),
        archetypeChanges: PostRevisionChange.fromJson(
          json['archetype_changes'],
          jsonText,
        ),
        featuredLinkChanges: PostRevisionChange.fromJson(
          json['featured_link_changes'],
          jsonText,
        ),
        canEdit: json['can_edit'] == true,
        diffError: json['diff_error'] == true,
      );

  final int postId;
  final DateTime? createdAt;
  final bool previousHidden;
  final bool currentHidden;
  final int? firstRevision;
  final int? previousRevision;
  final int currentRevision;
  final int? nextRevision;
  final int? lastRevision;
  final int currentVersion;
  final int versionCount;
  final String username;
  final String? displayUsername;
  final String? actingUserName;
  final String? avatarUrl;
  final String? editReason;
  final PostRevisionDiff? bodyChanges;
  final PostRevisionDiff? titleChanges;
  final PostRevisionChange<PostRevisionUser>? userChanges;
  final PostRevisionChange<PostRevisionReplyTarget>? replyToPostNumberChanges;
  final PostRevisionChange<List<String>>? tagsChanges;
  final PostRevisionChange<int>? categoryIdChanges;
  final PostRevisionChange<bool>? wikiChanges;
  final PostRevisionChange<int>? postTypeChanges;
  final PostRevisionChange<String>? localeChanges;
  final PostRevisionChange<String>? archetypeChanges;
  final PostRevisionChange<String>? featuredLinkChanges;
  final bool canEdit;
  final bool diffError;

  String get editorDisplayName => actingUserName ?? displayUsername ?? username;

  bool get diffHidden =>
      bodyChanges == null && !diffError && (previousHidden || currentHidden);

  String get comparisonLabel {
    final current = currentVersion > 0 ? currentVersion : 1;
    final previous = current > 1 ? current - 1 : 1;
    final total = versionCount > 0 ? versionCount : current;
    return 'Comparing version $previous to $current of $total';
  }
}
