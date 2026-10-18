import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'badge_route.dart';
import 'discourse_instance.dart';
import 'group_route.dart';
import 'list_link.dart';
import 'sidebar.dart';
import 'site_config.dart';
import 'topic.dart';
import 'topic_link.dart';

part 'content_destination.dart';
part 'content_route_codec.dart';

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
    return switch (route?.destination) {
      FeedDestination(:final mode) => mode,
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
    required this.destination,
    required this.title,
    required this.icon,
    this.subtitle,
    this.color,
  });

  final ContentDestination destination;

  bool sameDestinationAs(ContentRoute? other) =>
      other != null && destination.identity == other.destination.identity;

  bool isPage(CorePage page) => switch (destination) {
    PageDestination(page: final current) => current == page,
    _ => false,
  };

  ContentRoute withDisplay({
    String? title,
    DIconData? icon,
    String? subtitle,
    Color? color,
  }) => ContentRoute(
    destination: destination,
    title: title ?? this.title,
    icon: icon ?? this.icon,
    subtitle: subtitle ?? this.subtitle,
    color: color ?? this.color,
  );

  factory ContentRoute.list(ListLink link, {String? title, Color? color}) {
    return ContentRoute(
      destination: FeedDestination(
        key: 'list-${link.feedPath}',
        sourcePath: link.feedPath,
      ),
      title: title ?? link.placeholderTitle,
      icon: link.kind == ListKind.category ? DIcons.folder : DIcons.tag,
      color: color,
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
      destination: TopicDestination(
        topicId: topicId,
        slug: slug,
        postNumber: postNumber,
      ),
      title: title,
      icon: DNativeIcons.topic,
      subtitle: subtitle,
      color: color,
    );
  }

  factory ContentRoute.badges(BadgeRoute route, {String? title}) =>
      ContentRoute(
        destination: BadgeDestination(route),
        title: title ?? (route.isDirectory ? appL10n.badges : appL10n.badge),
        icon: DIcons.certificate,
      );

  factory ContentRoute.forumAbout() => ContentRoute(
    destination: const PageDestination(CorePage.forumAbout),
    title: appL10n.forumAboutTitle,
    icon: DIcons.circleInfo,
  );

  bool get isForumAbout => isPage(CorePage.forumAbout);

  factory ContentRoute.preferences() => ContentRoute(
    destination: const PageDestination(CorePage.preferences),
    title: appL10n.preferences,
    icon: DIcons.gear,
  );

  factory ContentRoute.newTab() => ContentRoute(
    destination: const PageDestination(CorePage.start),
    title: appL10n.startPage,
    icon: DIcons.house,
  );

  bool get isNewTab => isPage(CorePage.start);

  factory ContentRoute.appearance() => ContentRoute(
    destination: const PageDestination(CorePage.appearance),
    title: appL10n.settings,
    icon: DIcons.gear,
  );

  factory ContentRoute.group(
    GroupRoute route, {
    String? title,
    String? feedPath,
  }) => ContentRoute(
    destination: GroupDestination(route, sourcePath: feedPath),
    title: title ?? route.groupName ?? appL10n.groups,
    icon: DIcons.userGroup,
  );

  factory ContentRoute.allCategories() => ContentRoute(
    destination: const PageDestination(CorePage.categories),
    title: appL10n.categories,
    icon: DIcons.layerGroup,
  );

  factory ContentRoute.userActivity() => ContentRoute(
    destination: const PageDestination(CorePage.activity),
    title: appL10n.activity,
    icon: DIcons.barsStaggered,
  );

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
      destination: MessagesDestination(groupName: group, mode: mode),
      title: appL10n.messages,
      icon: DIcons.inbox,
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
    destination: FeedDestination(
      key: mode.routeId,
      sourcePath: mode.feedPath,
      mode: mode,
    ),
    title: appL10n.topics,
    icon: DIcons.layerGroup,
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
      destination: FeedDestination(
        key: 'topic-list-filter-$uri',
        sourcePath: uri.toString(),
        mode: mode,
      ),
      title: appL10n.topics,
      icon: DIcons.layerGroup,
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
      destination: FeedDestination(
        key: 'topic-list-filter-$uri',
        sourcePath: uri.toString(),
        mode: TopicListMode.latest,
      ),
      title: appL10n.topics,
      icon: DIcons.layerGroup,
    );
  }

  /// Search operators keep the search endpoint's semantics on an ordinary list.
  factory ContentRoute.searchList(
    String expression, {
    String? groupName,
    MessageListMode? messageMode,
  }) {
    final uri = Uri(
      path: '/search.json',
      queryParameters: {'q': expression, 'page': '1'},
    );
    return ContentRoute(
      destination: messageMode == null
          ? FeedDestination(
              key: 'topic-list-filter-$uri',
              sourcePath: uri.toString(),
              mode: TopicListMode.latest,
            )
          : MessagesDestination(
              groupName: groupName,
              mode: messageMode,
              sourcePath: uri.toString(),
              legacyKey:
                  '${_messageRouteId(groupName, messageMode)}?q=${Uri.encodeComponent(expression)}',
            ),
      title: messageMode == null ? appL10n.topics : appL10n.messages,
      icon: messageMode == null ? DIcons.layerGroup : DIcons.inbox,
    );
  }

  bool get isSearchList => Uri.tryParse(feedPath ?? '')?.path == '/search.json';

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
        if (topicListSearch.isNotEmpty) topicListSearch,
        if (categoryId != null) 'category:$categoryId',
        if (tagNames.isNotEmpty)
          'tag:${tagNames.map((tag) => tag.contains(RegExp(r'\s')) ? '"$tag"' : tag).join('+')}',
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

  factory ContentRoute.fromDestination(SidebarDestination source) =>
      ContentRoute(
        destination: ContentRouteCodec.fromSidebar(source),
        title: source.id == 'filter' ? appL10n.topics : source.label,
        icon: source.icon,
        color: source.routeColor ?? source.color,
      );

  String get id => destination.key;
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

  int? get topicId => switch (destination) {
    TopicDestination(:final topicId) => topicId,
    _ => null,
  };
  String? get slug => switch (destination) {
    TopicDestination(:final slug) => slug,
    _ => null,
  };
  int? get postNumber => switch (destination) {
    TopicDestination(:final postNumber) => postNumber,
    _ => null,
  };
  String? get feedPath => destination.feedPath;
  String? get messageGroupName => switch (destination) {
    MessagesDestination(:final groupName) => groupName,
    _ => null,
  };
  GroupRoute? get groupRoute => switch (destination) {
    GroupDestination(:final route) => route,
    _ => null,
  };
  BadgeRoute? get badgeRoute => switch (destination) {
    BadgeDestination(:final route) => route,
    _ => null,
  };

  static const int maximumFeedPathLength = 2048;
  static const int maximumMessageGroupNameLength = 255;

  bool get isTopic => destination is TopicDestination;
  bool get isBadges => destination is BadgeDestination;
  bool get isPreferences => isPage(CorePage.preferences);
  bool get isAppearance => isPage(CorePage.appearance);
  bool get isMessages => destination is MessagesDestination;
  MessageListMode get messageListMode => switch (destination) {
    MessagesDestination(:final mode) => mode,
    _ => MessageListMode.inbox,
  };
  bool get isUsers => isPage(CorePage.users);
  bool get isGroups => groupRoute?.isDirectory == true;
  bool get isGroup => groupRoute?.isDetail == true;

  ListLink? get _listLink {
    final uri = Uri.tryParse(feedPath ?? '');
    if (uri == null || !uri.path.endsWith('.json')) return null;
    return ListLink.parse(_withoutJson(uri.path));
  }

  bool get isTaxonomyList =>
      destination is FeedDestination && _listLink != null;

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

  bool get canSortTopicList =>
      isTopicListFilter && !isAdvancedTopicFilter && !isSearchList;

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
    return _withFeedPath(
      path,
      id: isMessages
          ? '${_messageRouteId(messageGroupName, messageListMode)}${term.isEmpty ? '' : '?search=${Uri.encodeComponent(term)}'}'
          : 'topic-list-filter-$path',
    );
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
        destination: destination.withFeedPath(path, key: id),
        title: title,
        icon: icon,
        subtitle: subtitle,
        color: color ?? this.color,
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
      destination is FeedDestination &&
      (TopicListMode.fromRoute(this) != null ||
          categoryId != null ||
          _listLink?.kind == ListKind.category ||
          tagName != null);

  /// Topic and message feeds that can stay beside an open topic.
  bool get isTopicList =>
      destination is FeedDestination || destination is MessagesDestination;

  Map<String, Object?> toJson() => ContentRouteCodec.encode(this);

  factory ContentRoute.fromJson(Map<String, dynamic> json) =>
      ContentRouteCodec.decode(json);

  @override
  bool operator ==(Object other) =>
      other is ContentRoute && sameDestinationAs(other) && other.title == title;

  @override
  int get hashCode => Object.hash(destination.identity, title);
}

String _withoutJson(String segment) => segment.endsWith('.json')
    ? segment.substring(0, segment.length - '.json'.length)
    : segment;
