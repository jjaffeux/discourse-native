part of 'content_route.dart';

final class ContentRouteCodec {
  static ContentDestination _typedDestination(
    Object type,
    Map<String, dynamic> json, {
    required String id,
    int? topicId,
    String? slug,
    int? postNumber,
    String? feedPath,
    String? messageGroupName,
    GroupRoute? groupRoute,
    BadgeRoute? badgeRoute,
  }) {
    final hasTopic = topicId != null || slug != null || postNumber != null;
    final hasOther =
        hasTopic ||
        messageGroupName != null ||
        groupRoute != null ||
        badgeRoute != null;
    switch (type) {
      case 'topic'
          when topicId != null &&
              messageGroupName == null &&
              groupRoute == null &&
              badgeRoute == null:
        return TopicDestination(
          topicId: topicId,
          slug: slug,
          postNumber: postNumber,
          retainedFeedPath: feedPath,
          legacyKey: id,
        );
      case 'feed' when !hasOther:
        final rawMode = json['topic_list_mode'];
        final mode = TopicListMode.values
            .where((mode) => mode.name == rawMode)
            .firstOrNull;
        if (rawMode != null && mode == null) {
          throw FormatException(appL10n.invalidContentRoute);
        }
        return FeedDestination(key: id, sourcePath: feedPath, mode: mode);
      case 'messages'
          when !hasTopic && groupRoute == null && badgeRoute == null:
        final mode = MessageListMode.values
            .where((mode) => mode.name == json['message_mode'])
            .firstOrNull;
        if (mode == null || (messageGroupName != null && !mode.supportsGroup)) {
          throw FormatException(appL10n.invalidContentRoute);
        }
        return MessagesDestination(
          mode: mode,
          groupName: messageGroupName,
          sourcePath: feedPath,
          legacyKey: id,
        );
      case 'group'
          when !hasTopic &&
              messageGroupName == null &&
              groupRoute != null &&
              badgeRoute == null:
        return GroupDestination(groupRoute, sourcePath: feedPath);
      case 'badge'
          when !hasTopic &&
              messageGroupName == null &&
              groupRoute == null &&
              badgeRoute != null &&
              feedPath == null:
        return BadgeDestination(badgeRoute);
      case 'page' when !hasOther && feedPath == null:
        final page = CorePage.values
            .where((page) => page.key == id)
            .firstOrNull;
        if (page != null) return PageDestination(page);
      case 'extension' when !hasOther:
        return ExtensionDestination(id, sourcePath: feedPath);
    }
    throw FormatException(appL10n.invalidContentRoute);
  }

  static ContentDestination fromSidebar(SidebarDestination source) =>
      _legacyDestination(
        id: source.id == 'filter' ? 'latest' : source.id,
        feedPath: source.feedPath,
      );

  static TopicListMode? _modeForPath(String path) {
    final uri = Uri.parse(path);
    return switch (uri.path) {
      '/latest.json' ||
      '/filter.json' ||
      '/search.json' => TopicListMode.latest,
      '/new.json' => switch (uri.queryParameters['subset']) {
        'topics' => TopicListMode.newTopics,
        'replies' => TopicListMode.newReplies,
        _ => TopicListMode.newActivity,
      },
      '/unread.json' => TopicListMode.unread,
      '/unseen.json' => TopicListMode.unseen,
      '/hot.json' => TopicListMode.popular,
      '/top.json' => TopicListMode.top(
        TopPeriod.fromQueryValue(uri.queryParameters['period'] ?? 'yearly'),
      ),
      _ => null,
    };
  }

  static ContentDestination _legacyDestination({
    required String id,
    int? topicId,
    String? slug,
    int? postNumber,
    String? feedPath,
    String? messageGroupName,
    GroupRoute? groupRoute,
    BadgeRoute? badgeRoute,
  }) {
    if (topicId != null) {
      return TopicDestination(
        topicId: topicId,
        slug: slug,
        postNumber: postNumber,
        retainedFeedPath: feedPath,
        legacyKey: id,
      );
    }
    if (groupRoute != null) {
      return GroupDestination(groupRoute, sourcePath: feedPath);
    }
    if (id == 'groups') return const GroupDestination(GroupRoute.directory());
    if (badgeRoute != null || id == 'badges') {
      return BadgeDestination(badgeRoute ?? const BadgeRoute.directory());
    }
    for (final mode in MessageListMode.values) {
      if ((messageGroupName == null || mode.supportsGroup) &&
          id.split('?').first ==
              ContentRoute._messageRouteId(messageGroupName, mode)) {
        return MessagesDestination(
          mode: mode,
          groupName: messageGroupName,
          sourcePath: feedPath,
          legacyKey: id,
        );
      }
    }
    for (final page in CorePage.values) {
      if (id == page.key) return PageDestination(page);
    }
    final mode = TopicListMode.values
        .where((mode) => id == mode.routeId && feedPath == mode.feedPath)
        .firstOrNull;
    final uri = feedPath == null ? null : Uri.parse(feedPath);
    final link = uri == null ? null : ListLink.parse(_withoutJson(uri.path));
    final category = int.tryParse(uri?.queryParameters['category'] ?? '');
    final tags = uri?.queryParametersAll['tags[]'];
    if (mode != null ||
        id.startsWith('topic-list-filter-') ||
        id.startsWith('list-') ||
        id == 'bookmarks' ||
        (category != null && category > 0) ||
        (tags != null && tags.isNotEmpty) ||
        link != null ||
        uri?.pathSegments.take(2).join('/') == 'tags/c') {
      return FeedDestination(
        key: id,
        sourcePath: feedPath,
        mode:
            mode ??
            (id.startsWith('topic-list-filter-') && feedPath != null
                ? _modeForPath(feedPath)
                : null),
      );
    }
    return ExtensionDestination(id, sourcePath: feedPath);
  }

  static Map<String, Object?> encode(ContentRoute route) => {
    'destination_type': switch (route.destination) {
      TopicDestination() => 'topic',
      FeedDestination() => 'feed',
      MessagesDestination() => 'messages',
      GroupDestination() => 'group',
      BadgeDestination() => 'badge',
      PageDestination() => 'page',
      ExtensionDestination() => 'extension',
    },
    if (route.destination case FeedDestination(mode: final mode?))
      'topic_list_mode': mode.name,
    if (route.destination case MessagesDestination(:final mode))
      'message_mode': mode.name,
    'id': route.id,
    'title': route.title,
    'icon': route.icon.name,
    if (route.subtitle != null) 'subtitle': route.subtitle,
    if (route.color != null) 'color': route.color!.toARGB32(),
    if (route.topicId != null) 'topic_id': route.topicId,
    if (route.slug != null) 'slug': route.slug,
    if (route.postNumber != null) 'post_number': route.postNumber,
    if (route.feedPath != null) 'feed_path': route.feedPath,
    if (route.messageGroupName != null)
      'message_group_name': route.messageGroupName,
    if (route.groupRoute != null) 'group_route': route.groupRoute!.toJson(),
    if (route.badgeRoute != null) 'badge_route': route.badgeRoute!.toJson(),
  };

  static ContentRoute decode(Map<String, dynamic> json) {
    final type = json['destination_type'];
    final id = json['id'];
    final title = json['title'];
    final iconName = json['icon'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        iconName is! String) {
      throw FormatException(appL10n.invalidContentRoute);
    }

    final colorValue = json['color'];
    final topicId = json['topic_id'];
    final postNumber = json['post_number'];
    final feedPath = json['feed_path'];
    final messageGroupName = json['message_group_name'];
    final rawGroupRoute = json['group_route'];
    if (topicId != null && (topicId is! int || topicId <= 0)) {
      throw FormatException(appL10n.invalidContentRouteTopicId);
    }
    if (postNumber != null && (postNumber is! int || postNumber <= 0)) {
      throw FormatException(appL10n.invalidContentRoutePostNumber);
    }
    if (feedPath != null && !_isSafeFeedPath(feedPath)) {
      throw FormatException(appL10n.invalidContentRouteFeedPath);
    }
    if (messageGroupName != null &&
        (messageGroupName is! String ||
            messageGroupName.trim().isEmpty ||
            messageGroupName != messageGroupName.trim() ||
            messageGroupName.length >
                ContentRoute.maximumMessageGroupNameLength ||
            topicId != null ||
            !(type == 'messages'
                ? MessageListMode.values.any(
                    (mode) =>
                        mode.name == json['message_mode'] && mode.supportsGroup,
                  )
                : MessageListMode.values.any(
                    (mode) =>
                        mode.supportsGroup &&
                        id.split('?').first ==
                            ContentRoute._messageRouteId(
                              messageGroupName,
                              mode,
                            ),
                  )))) {
      throw FormatException(appL10n.invalidContentRouteMessageGroup);
    }
    final GroupRoute? groupRoute;
    if (rawGroupRoute == null) {
      groupRoute = null;
    } else if (rawGroupRoute is Map) {
      groupRoute = GroupRoute.fromJson(
        Map<String, dynamic>.from(rawGroupRoute),
      );
      if (topicId != null || messageGroupName != null || id != groupRoute.id) {
        throw FormatException(appL10n.invalidContentGroupRoute);
      }
    } else {
      throw FormatException(appL10n.invalidContentGroupRoute);
    }
    final rawBadgeRoute = json['badge_route'];
    final BadgeRoute? badgeRoute;
    if (rawBadgeRoute == null) {
      badgeRoute = null;
    } else if (rawBadgeRoute is Map<String, dynamic>) {
      badgeRoute = BadgeRoute.fromJson(rawBadgeRoute);
      if (topicId != null ||
          messageGroupName != null ||
          groupRoute != null ||
          feedPath != null ||
          id != badgeRoute.id) {
        throw FormatException(appL10n.invalidContentBadgeRoute);
      }
    } else {
      throw FormatException(appL10n.invalidContentBadgeRoute);
    }
    final destination = type == null
        ? _legacyDestination(
            id: id,
            topicId: topicId as int?,
            slug: json['slug'] is String ? json['slug'] as String : null,
            postNumber: postNumber as int?,
            feedPath: feedPath as String?,
            messageGroupName: messageGroupName as String?,
            groupRoute: groupRoute,
            badgeRoute: badgeRoute,
          )
        : _typedDestination(
            type as Object,
            json,
            id: id,
            topicId: topicId as int?,
            slug: json['slug'] is String ? json['slug'] as String : null,
            postNumber: postNumber as int?,
            feedPath: feedPath as String?,
            messageGroupName: messageGroupName as String?,
            groupRoute: groupRoute,
            badgeRoute: badgeRoute,
          );
    final page = switch (destination) {
      PageDestination(:final page) => page,
      _ => null,
    };
    final route = ContentRoute(
      destination: destination,
      title: page == CorePage.start ? appL10n.startPage : title,
      // Upgrade legacy default glyphs while preserving other saved artwork.
      icon:
          (page == CorePage.start ? DIcons.house : null) ??
          (page == CorePage.users && iconName == DIcons.user.name
              ? DIcons.users
              : null) ??
          (groupRoute != null && iconName == DIcons.users.name
              ? DIcons.userGroup
              : null) ??
          (page == CorePage.activity && iconName == DIcons.list.name
              ? DIcons.barsStaggered
              : null) ??
          DNativeIcons.byName[iconName] ??
          (topicId != null && iconName == DIcons.comments.name
              ? DNativeIcons.topic
              : DIcons.byName[iconName] ?? DIcons.comments),
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : null,
      color: colorValue is int ? Color(colorValue) : null,
    );
    if (type == null && id == 'filter') {
      return ContentRoute.topicFilter(route.topicFilterQuery);
    }
    // Forum appearance was saved as a "themes" tab before it was renamed.
    if (type == null && id == 'themes' && !route.isTopic) {
      return ContentRoute.appearance();
    }
    return route;
  }

  static bool _isSafeFeedPath(Object? value) => FeedPathPolicy.accepts(value);

  static ContentRoute? fromUrl(
    String url, {
    required DiscourseInstance instance,
    required SiteConfig config,
    required TopPeriod defaultTopPeriod,
    String? title,
  }) {
    final target = Uri.tryParse(url);
    if (target == null || !instance.serves(target)) return null;
    if (_ownMessagesRoute(instance, target) case final messages?) {
      return messages;
    }
    final path = instance.pathWithin(target);
    if (!target.hasQuery && !target.hasFragment) {
      if (instance.user?.staff == true &&
          (path == '/admin/dashboard' || path == '/admin')) {
        return ContentRoute.dashboard();
      }
      if (path == '/about') return ContentRoute.forumAbout();
      if (path == '/u') {
        return ContentRoute(
          destination: const PageDestination(CorePage.users),
          title: appL10n.users,
          icon: DIcons.user,
        );
      }
      if (path == '/categories') return ContentRoute.allCategories();
    }
    if (_coreListRoute(instance, target, config, defaultTopPeriod)
        case final core?) {
      return core;
    }
    if (TopicLink.parse(url, siteUrl: instance.url) case final topic?) {
      return ContentRoute.topic(
        topicId: topic.topicId,
        slug: topic.slug,
        title: title ?? topic.placeholderTitle,
        postNumber: topic.postNumber,
      );
    }
    if (ListLink.parse(url, siteUrl: instance.url) case final list?) {
      return ContentRoute.list(list, title: title);
    }
    if (config.badgesEnabled) {
      if (BadgeRoute.parse(url, siteUrl: instance.url) case final badge?) {
        return ContentRoute.badges(badge, title: title);
      }
    }
    if (GroupRoute.parse(url, siteUrl: instance.url) case final group?) {
      return ContentRoute.group(
        group,
        feedPath: group.topicFeedPath(instance.user?.username),
      );
    }
    return null;
  }

  static ContentRoute? _coreListRoute(
    DiscourseInstance instance,
    Uri target,
    SiteConfig config,
    TopPeriod defaultTopPeriod,
  ) {
    if (target.hasFragment) return null;
    final Map<String, List<String>> query;
    try {
      query = {...target.queryParametersAll}..remove('page');
    } on FormatException {
      return null;
    }
    final user = instance.user;
    final path = instance.pathWithin(target);
    final ContentRoute route;
    switch (path) {
      case '/tags':
        if (!config.taggingEnabled) return null;
        return ContentRoute(
          destination: const PageDestination(CorePage.tags),
          title: appL10n.tags,
          icon: DIcons.tag,
        );
      case '/filter':
        final filter = query['q']?.firstOrNull?.trim() ?? '';
        route = filter.isEmpty
            ? ContentRoute.topicList(TopicListMode.latest)
            : ContentRoute.topicFilter(filter);
      case '/latest' || '/hot':
        route = ContentRoute.filteredTopicList(
          path == '/hot' ? TopicListMode.popular : TopicListMode.latest,
          query: query,
        );
      case '/unread' || '/unseen' when user != null:
        route = ContentRoute.filteredTopicList(
          path == '/unread' ? TopicListMode.unread : TopicListMode.unseen,
          query: query,
        );
      case '/new' when user != null:
        // The server reads a subset only for a reader on the unified New
        // list; anyone else is served the whole of New.
        final subset = query.remove('subset')?.firstOrNull;
        route = ContentRoute.filteredTopicList(switch (subset) {
          'topics' when user.unifiedNewEnabled => TopicListMode.newTopics,
          'replies' when user.unifiedNewEnabled => TopicListMode.newReplies,
          _ => TopicListMode.newActivity,
        }, query: query);
      case '/top':
        final value = query.remove('period')?.firstOrNull;
        final period = value == null
            ? defaultTopPeriod
            : TopPeriod.values
                  .where((period) => period.queryValue == value)
                  .firstOrNull;
        if (period == null) return null;
        route = ContentRoute.filteredTopicList(
          TopicListMode.top(period),
          query: query,
        );
      default:
        return null;
    }
    final feedPath = route.feedPath;
    if (feedPath != null &&
        (feedPath.length > ListLink.maximumUrlLength ||
            !FeedPathPolicy.accepts(feedPath))) {
      return null;
    }
    return route;
  }

  /// The native inbox a link to the reader's own messages names, spelled as
  /// the web routes it under `/u/{me}/messages` or `/my/messages`: the
  /// personal inbox and its `unread`, `sent` and `archive` folders, and
  /// `group/{name}` with its `unread` and `archive` folders. A group-message
  /// summary notification links to a group inbox. Null — the browser — for
  /// another reader's messages, a group whose messages this account cannot
  /// read, and a folder the app has no list for.
  static ContentRoute? _ownMessagesRoute(
    DiscourseInstance instance,
    Uri target,
  ) {
    final user = instance.user;
    if (user == null || target.hasQuery || target.hasFragment) return null;
    final List<String> inbox;
    switch (DiscourseInstance.pathSegmentsWithin(instance.url, target)) {
      case ['my', 'messages', ...final rest]:
        inbox = rest;
      case ['u', final username, 'messages', ...final rest]
          when username.toLowerCase() == user.username.toLowerCase():
        inbox = rest;
      default:
        return null;
    }
    final (groupName, folder) = switch (inbox) {
      ['group', final name, ...final folder] => (name, folder),
      _ => (null, inbox),
    };
    // The route keeps the server's spelling so it is the same list, under the
    // same id, as the one the inbox selector opens.
    final group = groupName == null
        ? null
        : user.messageGroupNames
              .where((name) => name.toLowerCase() == groupName.toLowerCase())
              .firstOrNull;
    if (groupName != null && group == null) return null;
    final mode = switch (folder) {
      [] => MessageListMode.inbox,
      ['unread'] => MessageListMode.unread,
      ['sent'] => MessageListMode.sent,
      ['archive'] => MessageListMode.archive,
      _ => null,
    };
    if (mode == null || (group != null && !mode.supportsGroup)) return null;
    return ContentRoute.messages(groupName: group, mode: mode);
  }
}
