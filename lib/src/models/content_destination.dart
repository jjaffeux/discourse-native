part of 'content_route.dart';

/// Navigation payload and durable key, independent of route display metadata.
sealed class ContentDestination {
  const ContentDestination();

  String get key;

  String? get feedPath => switch (this) {
    TopicDestination(:final retainedFeedPath) => retainedFeedPath,
    FeedDestination(:final sourcePath) => sourcePath,
    MessagesDestination(:final sourcePath) => sourcePath,
    GroupDestination(:final sourcePath) => sourcePath,
    ExtensionDestination(:final sourcePath) => sourcePath,
    BadgeDestination() || PageDestination() => null,
  };

  Object get identity => switch (this) {
    TopicDestination(:final topicId, :final query) => (
      TopicDestination,
      key,
      topicId,
      query,
      feedPath,
    ),
    FeedDestination(:final mode) => (FeedDestination, key, mode, feedPath),
    MessagesDestination(:final mode, :final groupName) => (
      MessagesDestination,
      key,
      mode,
      groupName,
      feedPath,
    ),
    GroupDestination(:final route) => (GroupDestination, key, route, feedPath),
    BadgeDestination(:final route) => (
      BadgeDestination,
      key,
      route.badgeId,
      route.username,
    ),
    // Usernames are case-insensitive: one person is one page however a link
    // spelled them.
    PageDestination(:final page, :final username, :final reviewableId) => (
      PageDestination,
      key,
      page,
      username?.toLowerCase(),
      reviewableId,
    ),
    ExtensionDestination() => (ExtensionDestination, key, feedPath),
  };

  ContentDestination withFeedPath(String path, {String? key}) => switch (this) {
    FeedDestination(:final mode) => FeedDestination(
      key: key ?? this.key,
      sourcePath: path,
      mode: mode,
    ),
    MessagesDestination(:final mode, :final groupName) => MessagesDestination(
      mode: mode,
      groupName: groupName,
      sourcePath: path,
      legacyKey: key ?? this.key,
    ),
    GroupDestination(:final route) => GroupDestination(route, sourcePath: path),
    TopicDestination(
      :final topicId,
      :final slug,
      :final postNumber,
      :final query,
    ) =>
      TopicDestination(
        topicId: topicId,
        slug: slug,
        postNumber: postNumber,
        query: query,
        retainedFeedPath: path,
        legacyKey: key ?? this.key,
      ),
    ExtensionDestination() => ExtensionDestination(
      key ?? this.key,
      sourcePath: path,
    ),
    BadgeDestination() || PageDestination() => this,
  };
}

final class TopicDestination extends ContentDestination {
  const TopicDestination({
    required this.topicId,
    this.slug,
    this.postNumber,
    this.query,
    this.retainedFeedPath,
    this.legacyKey,
  }) : assert(topicId > 0),
       assert(postNumber == null || postNumber > 0);
  final int topicId;
  final String? slug;
  final int? postNumber;

  /// Opaque canonical topic query, interpreted by the selected reader.
  final String? query;

  /// Old saved topics can contain an unused feed path. Retain it losslessly.
  final String? retainedFeedPath;
  final String? legacyKey;
  @override
  String get key => legacyKey ?? 'topic-$topicId';
}

final class FeedDestination extends ContentDestination {
  const FeedDestination({required this.key, this.sourcePath, this.mode});
  factory FeedDestination.fromPath({
    required String key,
    required String path,
  }) => FeedDestination(
    key: key,
    sourcePath: path,
    mode: ContentRouteCodec._modeForPath(path),
  );
  @override
  final String key;
  final String? sourcePath;
  final TopicListMode? mode;
}

final class MessagesDestination extends ContentDestination {
  const MessagesDestination({
    this.mode = MessageListMode.inbox,
    this.groupName,
    this.sourcePath,
    this.legacyKey,
  }) : assert(groupName == null || mode != MessageListMode.sent);
  final MessageListMode mode;
  final String? groupName;
  final String? sourcePath;
  final String? legacyKey;
  @override
  String get key => legacyKey ?? ContentRoute._messageRouteId(groupName, mode);
}

final class GroupDestination extends ContentDestination {
  const GroupDestination(this.route, {this.sourcePath});
  final GroupRoute route;
  final String? sourcePath;
  @override
  String get key => route.id;
}

final class BadgeDestination extends ContentDestination {
  const BadgeDestination(this.route);
  final BadgeRoute route;
  @override
  String get key => route.id;
}

enum CorePage {
  search('global-search'),
  categories('all-categories'),
  tags('all-tags'),
  users('users'),
  drafts('drafts'),
  summary('summary'),
  bookmarks('user-bookmarks'),
  activity('activity'),
  profile('profile'),
  preferences('preferences'),
  appearance('appearance'),
  forumAbout('forum-about'),
  dashboard('dashboard'),
  review('review');

  const CorePage(this.key);
  final String key;
}

final class PageDestination extends ContentDestination {
  const PageDestination(this.page, {this.username, this.reviewableId})
    : assert(
        username == null
            ? page != CorePage.profile
            : page == CorePage.activity || page == CorePage.profile,
      ),
      assert(
        reviewableId == null || (page == CorePage.review && reviewableId > 0),
      );
  final CorePage page;

  /// The person a per-person page is about: required by a profile, optional
  /// on activity, where its absence means the signed-in reader.
  final String? username;

  /// The queue item a review link names; the queue itself when null.
  final int? reviewableId;
  @override
  String get key => switch ((username, reviewableId)) {
    (final username?, _) => '${page.key}-user-${username.toLowerCase()}',
    (_, final id?) => '${page.key}-$id',
    _ => page.key,
  };
}

/// Opaque plugin identity. The plugin capability owns parsing and authorization.
final class ExtensionDestination extends ContentDestination {
  const ExtensionDestination(this.key, {this.sourcePath});
  @override
  final String key;
  final String? sourcePath;
}
