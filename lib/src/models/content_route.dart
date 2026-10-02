import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'badge_route.dart';
import 'group_route.dart';
import 'list_link.dart';
import 'sidebar.dart';
import 'site_config.dart';
import 'topic.dart';

enum TopPeriod {
  all('all'),
  yearly('yearly'),
  quarterly('quarterly'),
  monthly('monthly'),
  weekly('weekly'),
  daily('daily');

  const TopPeriod(this.queryValue);

  static TopPeriod fromQueryValue(String value) => values.firstWhere(
    (period) => period.queryValue == value,
    orElse: () => yearly,
  );

  final String queryValue;
  String get label => switch (this) {
    all => appL10n.allTime,
    yearly => appL10n.year,
    quarterly => appL10n.quarter,
    monthly => appL10n.month,
    weekly => appL10n.week,
    daily => appL10n.todayDcalendarevents,
  };
}

enum TopicListMode {
  latest,
  newActivity,
  newTopics,
  newReplies,
  unread,
  unseen,
  topAll,
  topYearly,
  topQuarterly,
  topMonthly,
  topWeekly,
  topDaily,
  popular;

  static TopicListMode? fromRoute(ContentRoute? route) {
    final known = switch ((route?.id, route?.feedPath)) {
      ('latest', null) => latest,
      ('new', '/new.json') => newActivity,
      ('new-topics', '/new.json?subset=topics') => newTopics,
      ('new-replies', '/new.json?subset=replies') => newReplies,
      ('unread', '/unread.json') => unread,
      ('unseen', '/unseen.json') => unseen,
      ('top-all', '/top.json?period=all') => topAll,
      ('top-yearly', '/top.json?period=yearly') => topYearly,
      ('top-quarterly', '/top.json?period=quarterly') => topQuarterly,
      ('top-monthly', '/top.json?period=monthly') => topMonthly,
      ('top-weekly', '/top.json?period=weekly') => topWeekly,
      ('top-daily', '/top.json?period=daily') => topDaily,
      ('hot', '/hot.json') => popular,
      _ => null,
    };
    if (known != null) return known;
    if (route == null || !route.id.startsWith('topic-list-filter-')) {
      return null;
    }
    final uri = Uri.tryParse(route.feedPath ?? '');
    return switch (uri?.path) {
      '/latest.json' || '/filter.json' => latest,
      '/new.json' => switch (uri?.queryParameters['subset']) {
        'topics' => newTopics,
        'replies' => newReplies,
        _ => newActivity,
      },
      '/unread.json' => unread,
      '/unseen.json' => unseen,
      '/hot.json' => popular,
      '/top.json' => top(
        TopPeriod.fromQueryValue(uri?.queryParameters['period'] ?? 'yearly'),
      ),
      _ => null,
    };
  }

  static TopicListMode top(TopPeriod period) => switch (period) {
    TopPeriod.all => topAll,
    TopPeriod.yearly => topYearly,
    TopPeriod.quarterly => topQuarterly,
    TopPeriod.monthly => topMonthly,
    TopPeriod.weekly => topWeekly,
    TopPeriod.daily => topDaily,
  };

  String get routeId => switch (this) {
    latest => 'latest',
    newActivity => 'new',
    newTopics => 'new-topics',
    newReplies => 'new-replies',
    unread => 'unread',
    unseen => 'unseen',
    topAll => 'top-all',
    topYearly => 'top-yearly',
    topQuarterly => 'top-quarterly',
    topMonthly => 'top-monthly',
    topWeekly => 'top-weekly',
    topDaily => 'top-daily',
    popular => 'hot',
  };

  String? get feedPath => switch (this) {
    latest => null,
    newActivity => '/new.json',
    newTopics => '/new.json?subset=topics',
    newReplies => '/new.json?subset=replies',
    unread => '/unread.json',
    unseen => '/unseen.json',
    topAll => '/top.json?period=all',
    topYearly => '/top.json?period=yearly',
    topQuarterly => '/top.json?period=quarterly',
    topMonthly => '/top.json?period=monthly',
    topWeekly => '/top.json?period=weekly',
    topDaily => '/top.json?period=daily',
    popular => '/hot.json',
  };

  bool get isNew => switch (this) {
    newActivity || newTopics || newReplies => true,
    _ => false,
  };

  bool get isTop => topPeriod != null;

  TopPeriod? get topPeriod => switch (this) {
    topAll => TopPeriod.all,
    topYearly => TopPeriod.yearly,
    topQuarterly => TopPeriod.quarterly,
    topMonthly => TopPeriod.monthly,
    topWeekly => TopPeriod.weekly,
    topDaily => TopPeriod.daily,
    _ => null,
  };

  bool get isSubset => this == newTopics || this == newReplies;
}

enum MessageListMode {
  inbox(),
  unread(),
  sent(),
  archive();

  const MessageListMode();

  String get label => switch (this) {
    inbox => appL10n.inbox,
    unread => appL10n.unread,
    sent => appL10n.sent,
    archive => appL10n.archive,
  };

  bool get supportsGroup => this != sent;

  String feedPathFor(String username, {String? groupName}) {
    final user = Uri.encodeComponent(username);
    if (groupName != null) {
      if (!supportsGroup) {
        throw ArgumentError.value(this, 'mode', 'No group sent list.');
      }
      final suffix = this == inbox ? '' : '/$name';
      return '/topics/private-messages-group/'
          '$user/${Uri.encodeComponent(groupName)}$suffix.json';
    }
    final suffix = this == inbox ? '' : '-$name';
    return '/topics/private-messages$suffix/$user.json';
  }
}

@immutable
class ContentRoute {
  const ContentRoute({
    required this.id,
    required this.title,
    required this.icon,
    this.subtitle,
    this.color,
    this.topicId,
    this.slug,
    this.postNumber,
    this.feedPath,
    this.messageGroupName,
    this.groupRoute,
    this.badgeRoute,
    this.openInSecondaryPanel = false,
    this.openInMainPanel = false,
  });

  factory ContentRoute.list(ListLink link, {String? title, Color? color}) {
    return ContentRoute(
      id: 'list-${link.feedPath}',
      title: title ?? link.placeholderTitle,
      icon: link.kind == ListKind.category ? DIcons.folder : DIcons.tag,
      color: color,
      feedPath: link.feedPath,
    );
  }

  factory ContentRoute.topic({
    required int topicId,
    required String slug,
    required String title,
    String? subtitle,
    Color? color,
    int? postNumber,
  }) {
    return ContentRoute(
      id: 'topic-$topicId',
      title: title,
      icon: DNativeIcons.topic,
      subtitle: subtitle,
      color: color,
      topicId: topicId,
      slug: slug,
      postNumber: postNumber,
    );
  }

  factory ContentRoute.badges(BadgeRoute route, {String? title}) =>
      ContentRoute(
        id: route.id,
        title: title ?? (route.isDirectory ? appL10n.badges : appL10n.badge),
        icon: DIcons.certificate,
        badgeRoute: route,
      );

  factory ContentRoute.preferences() => ContentRoute(
    id: 'preferences',
    title: appL10n.preferences,
    icon: DIcons.gear,
  );

  factory ContentRoute.newTab() =>
      ContentRoute(id: 'new-tab', title: appL10n.startPage, icon: DIcons.house);

  bool get isNewTab => id == 'new-tab';

  factory ContentRoute.appearance() => ContentRoute(
    id: 'appearance',
    title: appL10n.settings,
    icon: DIcons.gear,
  );

  factory ContentRoute.group(
    GroupRoute route, {
    String? title,
    String? feedPath,
  }) => ContentRoute(
    id: route.id,
    title: title ?? route.groupName ?? appL10n.groups,
    icon: DIcons.users,
    feedPath: feedPath,
    groupRoute: route,
  );

  factory ContentRoute.allCategories() => ContentRoute(
    id: 'all-categories',
    title: appL10n.categories,
    icon: DIcons.layerGroup,
  );

  factory ContentRoute.userActivity() =>
      ContentRoute(id: 'activity', title: appL10n.activity, icon: DIcons.list);

  factory ContentRoute.messages({
    String? groupName,
    MessageListMode mode = MessageListMode.inbox,
  }) {
    final group = groupName?.trim();
    if (group != null &&
        (group.isEmpty || group.length > maximumMessageGroupNameLength)) {
      throw ArgumentError.value(groupName, 'groupName', 'Invalid group name.');
    }
    if (group != null && !mode.supportsGroup) {
      throw ArgumentError.value(mode, 'mode', 'No group sent list.');
    }
    return ContentRoute(
      id: _messageRouteId(group, mode),
      title: appL10n.messages,
      icon: DIcons.inbox,
      messageGroupName: group,
    );
  }

  static String _messageRouteId(String? group, MessageListMode mode) {
    final inbox = group == null
        ? 'messages'
        : 'messages-group-${Uri.encodeComponent(group)}';
    if (mode == MessageListMode.inbox) return inbox;
    return group == null ? '$inbox-${mode.name}' : '$inbox/${mode.name}';
  }

  factory ContentRoute.topicList(TopicListMode mode) => ContentRoute(
    id: mode.routeId,
    title: appL10n.topics,
    icon: DIcons.layerGroup,
    feedPath: mode.feedPath,
  );

  /// [query] goes ahead of the mode's own parameters, as it does in
  /// [withTopicListQueryFrom], so both spell one list under one id.
  factory ContentRoute.filteredTopicList(
    TopicListMode mode, {
    int? categoryId,
    List<String> tags = const [],
    Map<String, List<String>> query = const {},
  }) {
    if (categoryId == null && tags.isEmpty && query.isEmpty) {
      return ContentRoute.topicList(mode);
    }
    final base = Uri.parse(mode.feedPath ?? '/latest.json');
    final uri = base.replace(
      queryParameters: <String, dynamic>{
        ...query,
        ...base.queryParameters,
        if (categoryId != null) 'category': '$categoryId',
        if (tags.isNotEmpty) 'tags[]': tags,
        if (tags.isNotEmpty) 'match_all_tags': 'true',
      },
    );
    return ContentRoute(
      id: 'topic-list-filter-$uri',
      title: appL10n.topics,
      icon: DIcons.layerGroup,
      feedPath: uri.toString(),
    );
  }

  /// Advanced filters are an ordinary Topics source, not a separate page.
  factory ContentRoute.topicFilter(
    String query, {
    int? categoryId,
    List<String> tags = const [],
  }) {
    final uri = Uri(
      path: '/filter.json',
      queryParameters: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (categoryId != null) 'category': '$categoryId',
        if (tags.isNotEmpty) 'tags[]': tags,
      },
    );
    return ContentRoute(
      id: 'topic-list-filter-$uri',
      title: appL10n.topics,
      icon: DIcons.layerGroup,
      feedPath: uri.toString(),
    );
  }

  String get topicFilterQuery =>
      Uri.tryParse(feedPath ?? '')?.queryParameters['q'] ?? '';
  bool get isAdvancedTopicFilter =>
      Uri.tryParse(feedPath ?? '')?.path == '/filter.json';

  /// Only q/page are understood by /filter.json. Compile taxonomy into q.
  String get topicFilterRequestPath => Uri(
    path: '/filter.json',
    queryParameters: {
      'q': [
        topicFilterQuery,
        if (categoryId != null) 'category:$categoryId',
        if (tagNames.isNotEmpty) 'tag:${tagNames.join('+')}',
      ].where((part) => part.isNotEmpty).join(' '),
    },
  ).toString();

  factory ContentRoute.homepage(
    SiteConfig config, {
    required bool connected,
    ContentRoute? registeredHomepage,
  }) {
    const anonymous = {'latest', 'top', 'categories', 'hot'};
    var homepage = config.defaultHomepage.isNotEmpty
        ? config.defaultHomepage
        : config.topMenu.firstOrNull ?? 'latest';
    if (connected && registeredHomepage?.id == homepage) {
      return registeredHomepage!;
    }
    const discovery = {
      'latest',
      'top',
      'categories',
      'hot',
      'new',
      'unread',
      'unseen',
    };
    if (!discovery.contains(homepage)) {
      homepage = config.topMenu.firstOrNull ?? 'latest';
    }
    if (!connected && !anonymous.contains(homepage)) {
      homepage =
          config.topMenu.where(anonymous.contains).firstOrNull ?? 'latest';
    }
    if (homepage == 'categories') return ContentRoute.allCategories();
    final mode = switch (homepage) {
      'hot' => TopicListMode.popular,
      'top' => TopicListMode.top(
        TopPeriod.fromQueryValue(config.topPageDefaultPeriod),
      ),
      'new' => TopicListMode.newActivity,
      'unread' => TopicListMode.unread,
      'unseen' => TopicListMode.unseen,
      _ => TopicListMode.latest,
    };
    return ContentRoute.topicList(mode);
  }

  ContentRoute.fromDestination(SidebarDestination destination)
    : id = destination.id == 'filter' ? 'latest' : destination.id,
      title = destination.id == 'filter' ? appL10n.topics : destination.label,
      icon = destination.icon,
      subtitle = null,
      color = destination.routeColor ?? destination.color,
      topicId = null,
      slug = null,
      postNumber = null,
      feedPath = destination.feedPath,
      messageGroupName = null,
      groupRoute = null,
      badgeRoute = null,
      openInSecondaryPanel = false,
      openInMainPanel = false;

  final bool openInSecondaryPanel;
  final bool openInMainPanel;

  final String id;
  final String title;

  String get tabTitle {
    if (isAdvancedTopicFilter) return title;
    return switch (TopicListMode.fromRoute(this)) {
      TopicListMode.latest => appL10n.latest,
      TopicListMode.newActivity => appL10n.messageNew,
      TopicListMode.newTopics => appL10n.newTopicsContentroute,
      TopicListMode.newReplies => appL10n.newRepliesContentroute,
      TopicListMode.unread => appL10n.unread,
      TopicListMode.unseen => appL10n.unseen,
      TopicListMode.popular => appL10n.trending,
      final mode? => appL10n.topContentroute(
        (mode.topPeriod!.label.toLowerCase()).toString(),
      ),
      null => title,
    };
  }

  final DIconData icon;
  final String? subtitle;
  final Color? color;

  final int? topicId;
  final String? slug;

  final int? postNumber;

  final String? feedPath;

  final String? messageGroupName;

  final GroupRoute? groupRoute;

  final BadgeRoute? badgeRoute;

  bool get isBadges => !isTopic && (badgeRoute != null || id == 'badges');

  /// Prevents corrupted persisted state from producing an oversized URI.
  static const int maximumFeedPathLength = 2048;

  static const int maximumMessageGroupNameLength = 255;

  bool get isTopic => topicId != null;

  bool get isPreferences => !isTopic && id == 'preferences';
  bool get isAppearance => !isTopic && id == 'appearance';

  bool get isMessages =>
      !isTopic &&
      MessageListMode.values.any(
        (mode) =>
            (messageGroupName == null || mode.supportsGroup) &&
            id == _messageRouteId(messageGroupName, mode),
      );

  MessageListMode get messageListMode => MessageListMode.values.firstWhere(
    (mode) => id == _messageRouteId(messageGroupName, mode),
    orElse: () => MessageListMode.inbox,
  );

  bool get isUsers => !isTopic && id == 'users';

  bool get isGroups => !isTopic && groupRoute?.isDirectory == true;

  bool get isGroup => !isTopic && groupRoute?.isDetail == true;

  ListLink? get _listLink {
    final uri = Uri.tryParse(feedPath ?? '');
    if (uri == null || !uri.path.endsWith('.json')) return null;
    return ListLink.parse(_withoutJson(uri.path));
  }

  ContentRoute resolveCategoryLink(Iterable<TopicCategory> categories) {
    final link = _listLink;
    if (link?.kind != ListKind.category || link!.id != null) return this;
    final slug = link.slug.toLowerCase();
    final encodedSlug = Uri.encodeComponent(slug).toLowerCase();
    final category = categories.where((category) {
      if (category.parentCategoryId != null) return false;
      final candidate = category.slug.isEmpty
          ? '${category.id}-category'
          : category.slug.toLowerCase();
      return candidate == slug || candidate == encodedSlug;
    }).firstOrNull;
    if (category == null) return this;

    final uri = Uri.parse(feedPath!);
    final path = Uri(
      pathSegments: ['', 'c', link.slug, '${category.id}.json'],
      query: uri.hasQuery ? uri.query : null,
    );
    // Keep the feed identity and scroll anchors while its category metadata
    // becomes available, including when the original request is in flight.
    return _withFeedPath(
      path.toString(),
      color: color ?? Color(category.colorValue),
    );
  }

  String get topicListSearch =>
      Uri.tryParse(feedPath ?? '')?.queryParameters['search'] ?? '';

  // These columns are supported by Discourse's TopicQuery ordering. Advanced
  // filters use their own order: syntax rather than these URL parameters.
  static const topicListSortColumns = {
    'category',
    'posts',
    'views',
    'activity',
  };

  bool get canSortTopicList => isTopicListFilter && !isAdvancedTopicFilter;

  String? get topicListOrder =>
      Uri.tryParse(feedPath ?? '')?.queryParameters['order'];

  bool get topicListAscending =>
      Uri.tryParse(feedPath ?? '')?.queryParameters['ascending'] == 'true';

  ContentRoute withTopicListSort(String? order, {bool ascending = false}) {
    if (!canSortTopicList ||
        (order != null && !topicListSortColumns.contains(order))) {
      return this;
    }
    final uri = Uri.parse(feedPath ?? '/latest.json');
    final query = {...uri.queryParametersAll}
      ..remove('page')
      ..remove('order')
      ..remove('ascending');
    if (order != null) {
      query['order'] = [order];
      if (ascending) query['ascending'] = ['true'];
    }
    final path = Uri(
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _withFeedPath(path, id: 'topic-list-filter-$path');
  }

  ContentRoute withTopicListSearch(String value) {
    final uri = Uri.parse(feedPath ?? '/latest.json');
    final query = {...uri.queryParametersAll}..remove('page');
    final term = value.trim();
    if (term.isEmpty) {
      query.remove('search');
    } else {
      query['search'] = [term];
    }
    final path = Uri(
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _withFeedPath(path, id: 'topic-list-filter-$path');
  }

  ContentRoute withTopicListQueryFrom(ContentRoute? source) {
    if (source?.isAdvancedTopicFilter == true) {
      return ContentRoute.topicFilter(
        source!.topicFilterQuery,
        categoryId: categoryId,
        tags: tagNames,
      );
    }
    final query = {...?Uri.tryParse(source?.feedPath ?? '')?.queryParametersAll}
      ..removeWhere(
        (key, _) => const {
          'category',
          'tags[]',
          'match_all_tags',
          'period',
          'subset',
          'page',
        }.contains(key),
      );
    if (query.isEmpty) return this;
    final uri = Uri.parse(feedPath ?? '/latest.json');
    final path = uri
        .replace(queryParameters: {...query, ...uri.queryParametersAll})
        .toString();
    return _withFeedPath(path, id: 'topic-list-filter-$path');
  }

  ContentRoute _withFeedPath(String path, {String? id, Color? color}) =>
      ContentRoute(
        id: id ?? this.id,
        title: title,
        icon: icon,
        subtitle: subtitle,
        color: color ?? this.color,
        topicId: topicId,
        slug: slug,
        postNumber: postNumber,
        feedPath: path,
        messageGroupName: messageGroupName,
        groupRoute: groupRoute,
        badgeRoute: badgeRoute,
        openInSecondaryPanel: openInSecondaryPanel,
        openInMainPanel: openInMainPanel,
      );

  int? get categoryId {
    final path = feedPath;
    if (path == null) return null;
    final uri = Uri.tryParse(path);
    if (uri == null || !uri.path.endsWith('.json')) return null;
    final selected = int.tryParse(uri.queryParameters['category'] ?? '');
    if (selected != null && selected > 0) return selected;
    final segments = uri.pathSegments;
    if (segments.length >= 4 && segments[0] == 'tags' && segments[1] == 'c') {
      final tagHasId = int.tryParse(_withoutJson(segments.last)) != null;
      final categoryIndex = segments.length - (tagHasId ? 3 : 2);
      if (categoryIndex < 2) return null;
      return int.tryParse(segments[categoryIndex]);
    }
    final link = _listLink;
    return link?.kind == ListKind.category ? link!.id : null;
  }

  String? get tagName {
    final path = feedPath;
    if (path == null) return null;
    final uri = Uri.tryParse(path);
    if (uri == null || !uri.path.endsWith('.json')) return null;
    final selectedTags = uri.queryParametersAll['tags[]'];
    if (selectedTags != null && selectedTags.isNotEmpty) {
      return selectedTags.first;
    }
    final segments = uri.pathSegments;
    if (segments.length >= 4 && segments[0] == 'tags' && segments[1] == 'c') {
      final last = _withoutJson(segments.last);
      return int.tryParse(last) == null ? last : segments[segments.length - 2];
    }
    final link = _listLink;
    if (link?.kind != ListKind.tag || link!.slug.isEmpty) return null;
    return link.slug;
  }

  List<String> get tagNames {
    final tags = Uri.tryParse(feedPath ?? '')?.queryParametersAll['tags[]'];
    if (tags != null) return List.unmodifiable(tags);
    final tag = tagName;
    return tag == null ? const [] : [tag];
  }

  /// A `/tag/<slug>/<id>` list names its tag by id. Its [tagName] is then the
  /// URL slug core derives from the name, not the name filters look tags up by.
  int? get tagId {
    final link = _listLink;
    return link?.kind == ListKind.tag ? link!.id : null;
  }

  bool get isTopicListFilter =>
      TopicListMode.fromRoute(this) != null ||
      categoryId != null ||
      _listLink?.kind == ListKind.category ||
      tagName != null;

  /// Topic and message feeds that can stay beside an open topic.
  bool get isTopicList =>
      !isTopic &&
      (isMessages ||
          TopicListMode.fromRoute(this) != null ||
          isTopicListFilter ||
          id.startsWith('list-') ||
          id == 'bookmarks');

  /// Contains presentation only, never fetched content or credentials.
  Map<String, Object?> toJson() => {
    'id': id,
    if (openInSecondaryPanel) 'open_in_secondary_panel': true,
    if (openInMainPanel) 'open_in_main_panel': true,
    'title': title,
    'icon': icon.name,
    if (subtitle != null) 'subtitle': subtitle,
    if (color != null) 'color': color!.toARGB32(),
    if (topicId != null) 'topic_id': topicId,
    if (slug != null) 'slug': slug,
    if (postNumber != null) 'post_number': postNumber,
    if (feedPath != null) 'feed_path': feedPath,
    if (messageGroupName != null) 'message_group_name': messageGroupName,
    if (groupRoute != null) 'group_route': groupRoute!.toJson(),
    if (badgeRoute != null) 'badge_route': badgeRoute!.toJson(),
  };

  factory ContentRoute.fromJson(Map<String, dynamic> json) {
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
            messageGroupName.length > maximumMessageGroupNameLength ||
            topicId != null ||
            !MessageListMode.values.any(
              (mode) =>
                  mode.supportsGroup &&
                  id == _messageRouteId(messageGroupName, mode),
            ))) {
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
    final route = ContentRoute(
      id: id,
      openInSecondaryPanel: json['open_in_secondary_panel'] == true,
      openInMainPanel: json['open_in_main_panel'] == true,
      title: id == 'new-tab' ? appL10n.startPage : title,
      // Upgrade the speech bubble saved by older topic tabs without changing
      // the durable icon of routes that deliberately chose another glyph.
      icon:
          (id == 'new-tab' ? DIcons.house : null) ??
          DNativeIcons.byName[iconName] ??
          (topicId != null && iconName == DIcons.comments.name
              ? DNativeIcons.topic
              : DIcons.byName[iconName] ?? DIcons.comments),
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : null,
      color: colorValue is int ? Color(colorValue) : null,
      topicId: topicId as int?,
      slug: json['slug'] is String ? json['slug'] as String : null,
      postNumber: postNumber as int?,
      feedPath: feedPath as String?,
      messageGroupName: messageGroupName as String?,
      groupRoute: groupRoute,
      badgeRoute: badgeRoute,
    );
    if (id == 'filter') return ContentRoute.topicFilter(route.topicFilterQuery);
    // Forum appearance was saved as a "themes" tab before it was renamed.
    if (id == 'themes' && !route.isTopic) return ContentRoute.appearance();
    // The removed list-search field stored its query in the feed URL. Restore
    // those lists without an invisible filter, retaining their durable IDs so
    // tab history and viewport anchors still refer to the same routes.
    if (!route.isTopicList || feedPath == null) return route;
    final uri = Uri.parse(feedPath);
    if (!uri.queryParametersAll.containsKey('search')) return route;
    final query = {...uri.queryParametersAll}..remove('search');
    final path = Uri(
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return route._withFeedPath(path);
  }

  static bool _isSafeFeedPath(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maximumFeedPathLength) {
      return false;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    try {
      // The getters decode lazily. Reject unreadable saved components before
      // restoring a route whose category, tag, or filter getters need them.
      final _ = uri.pathSegments;
      final _ = uri.queryParametersAll;
    } on FormatException {
      return false;
    }
    return value.startsWith('/') &&
        !value.startsWith('//') &&
        uri.path.isNotEmpty &&
        uri.path.endsWith('.json') &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
  }

  @override
  bool operator ==(Object other) =>
      other is ContentRoute &&
      other.id == id &&
      other.title == title &&
      other.feedPath == feedPath;

  @override
  int get hashCode => Object.hash(id, title, feedPath);
}

String _withoutJson(String segment) => segment.endsWith('.json')
    ? segment.substring(0, segment.length - '.json'.length)
    : segment;
