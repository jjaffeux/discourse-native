import 'package:discourse_native/l10n/strings.dart';
import '../plugin_api/global_search.dart' show GlobalSearchLookup;
import 'global_search_models.dart';

List<GlobalSearchFilter> get globalSearchFilters => <GlobalSearchFilter>[
  GlobalSearchFilter(
    id: "category",
    label: appL10n.category,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.multi,
    icon: "folder",
    group: appL10n.where,
    operators: [
      GlobalSearchFilterOperator("any", appL10n.includeSubcategories),
      GlobalSearchFilterOperator("exactCategory", appL10n.onlyTheseCategories),
    ],
    token: "category",
    placeholder: appL10n.chooseCategories,
    help: appL10n
        .chooseOneOrMoreCategoriesMultipleCategoriesMatchAnySelectedCategory,
  ),
  GlobalSearchFilter(
    id: "tags",
    label: appL10n.tags,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.multi,
    icon: "tag",
    group: appL10n.where,
    operators: [
      GlobalSearchFilterOperator("any", appL10n.includeAny),
      GlobalSearchFilterOperator("all", appL10n.includeAll),
      GlobalSearchFilterOperator("none", appL10n.excludeAny),
      GlobalSearchFilterOperator("notAll", appL10n.excludeCombination),
    ],
    token: "tags",
    placeholder: appL10n.chooseTags,
    help: appL10n.matchAnyTagEveryTagOrExcludeSelectedTags,
  ),
  GlobalSearchFilter(
    lookup: GlobalSearchLookup.users,
    singleIdentifier: true,
    id: "author",
    label: appL10n.postedBy,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: appL10n.people,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "@",
    placeholder: appL10n.usernameOrMe,
    help: appL10n.findPostsWrittenByASpecificPersonUseMeForYour,
  ),
  GlobalSearchFilter(
    lookup: GlobalSearchLookup.users,
    singleIdentifier: true,
    id: "topicAuthor",
    label: appL10n.startedBy,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: appL10n.people,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "created:@",
    placeholder: appL10n.username,
    help: appL10n.findOpeningPostsWrittenByThisPerson,
  ),
  GlobalSearchFilter(
    lookup: GlobalSearchLookup.groups,
    singleIdentifier: true,
    rejectQuotes: true,
    id: "authorGroup",
    label: appL10n.authorSGroup,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "users",
    group: appL10n.people,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "group",
    placeholder: appL10n.groupName,
    help: appL10n.findPostsWrittenByMembersOfAGroupWhoseMembershipYou,
  ),
  GlobalSearchFilter(
    lookup: GlobalSearchLookup.groups,
    singleIdentifier: true,
    rejectQuotes: true,
    id: "groupInbox",
    label: appL10n.groupInbox,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "mail",
    group: appL10n.where,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "group_messages",
    placeholder: appL10n.groupName,
    help: appL10n.searchPersonalMessagesAddressedToThisGroup,
  ),
  GlobalSearchFilter(
    id: "searchIn",
    label: appL10n.searchIn,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "search",
    group: appL10n.where,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.byDefaultResultsAreGroupedByTopicEveryMatchingPostShows,
    choices: [
      GlobalSearchFilterChoice(
        value: "title",
        label: appL10n.topicTitles,
        token: "in:title",
      ),
      GlobalSearchFilterChoice(
        value: "first",
        label: appL10n.openingPosts,
        token: "in:first",
      ),
      GlobalSearchFilterChoice(
        value: "replies",
        label: appL10n.replies,
        token: "in:replies",
      ),
      GlobalSearchFilterChoice(
        value: "allPosts",
        label: appL10n.everyMatchingPost,
        token: "in:all-posts",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "privateMessages",
    label: appL10n.messagesTopics,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "mail",
    group: appL10n.where,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.searchTheTopicsAndPersonalMessagesAvailableToYourAccount,
    choices: [
      GlobalSearchFilterChoice(
        value: "all",
        label: appL10n.topicsAndMyMessages,
        token: "in:all",
      ),
      GlobalSearchFilterChoice(
        value: "personal",
        label: appL10n.myPersonalMessages,
        token: "in:personal",
      ),
      GlobalSearchFilterChoice(
        value: "direct",
        label: appL10n.oneToOnePersonalMessages,
        token: "in:personal-direct",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "activity",
    label: appL10n.myActivity,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "bookmark",
    group: appL10n.personal,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.narrowResultsUsingYourReadingNotificationAndPostingActivity,
    choices: [
      GlobalSearchFilterChoice(
        value: "seen",
        label: appL10n.readPosts,
        token: "in:seen",
      ),
      GlobalSearchFilterChoice(
        value: "unseen",
        label: appL10n.unreadPosts,
        token: "in:unseen",
      ),
      GlobalSearchFilterChoice(
        value: "watching",
        label: appL10n.watching,
        token: "in:watching",
      ),
      GlobalSearchFilterChoice(
        value: "tracking",
        label: appL10n.trackingOrWatching,
        token: "in:tracking",
      ),
      GlobalSearchFilterChoice(
        value: "bookmarks",
        label: appL10n.bookmarkedPosts,
        token: "in:bookmarks",
      ),
      GlobalSearchFilterChoice(
        value: "likes",
        label: appL10n.likedPosts,
        token: "in:likes",
      ),
      GlobalSearchFilterChoice(
        value: "posted",
        label: appL10n.myPosts,
        token: "in:posted",
      ),
      GlobalSearchFilterChoice(
        value: "created",
        label: appL10n.topicsIStarted,
        token: "in:created",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "status",
    label: appL10n.topicStatus,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "status",
    group: appL10n.content,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.openTopicsAreNeitherClosedNorArchived,
    choices: [
      GlobalSearchFilterChoice(
        value: "open",
        label: appL10n.open,
        token: "status:open",
      ),
      GlobalSearchFilterChoice(
        value: "closed",
        label: appL10n.closed,
        token: "status:closed",
      ),
      GlobalSearchFilterChoice(
        value: "archived",
        label: appL10n.archived,
        token: "status:archived",
      ),
      GlobalSearchFilterChoice(
        value: "noreplies",
        label: appL10n.noReplies,
        token: "status:noreplies",
      ),
      GlobalSearchFilterChoice(
        value: "singleUser",
        label: appL10n.oneParticipant,
        token: "status:single_user",
      ),
      GlobalSearchFilterChoice(
        value: "public",
        label: appL10n.publicCategories,
        token: "status:public",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "postType",
    label: appL10n.postType,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "post",
    group: appL10n.content,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.chooseTheTypeOfPostToFind,
    choices: [
      GlobalSearchFilterChoice(
        value: "regular",
        label: appL10n.regularPosts,
        token: "in:regular",
      ),
      GlobalSearchFilterChoice(
        value: "wiki",
        label: appL10n.wikiPosts,
        token: "in:wiki",
      ),
      GlobalSearchFilterChoice(
        value: "pinned",
        label: appL10n.postsInPinnedTopics,
        token: "in:pinned",
      ),
      GlobalSearchFilterChoice(
        value: "bot",
        label: appL10n.postsByBots,
        token: "in:bot",
      ),
      GlobalSearchFilterChoice(
        value: "human",
        label: appL10n.postsByPeople,
        token: "in:human",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "content",
    label: appL10n.contains,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "image",
    group: appL10n.content,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.findPostsWithImagesOrTopicsWithOrWithoutTags,
    choices: [
      GlobalSearchFilterChoice(
        value: "images",
        label: appL10n.images,
        token: "with:images",
      ),
      GlobalSearchFilterChoice(
        value: "tagged",
        label: appL10n.atLeastOneTag,
        token: "in:tagged",
      ),
      GlobalSearchFilterChoice(
        value: "untagged",
        label: appL10n.noTags,
        token: "in:untagged",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "files",
    label: appL10n.fileTypes,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "folder",
    group: appL10n.content,
    operators: [GlobalSearchFilterOperator("any", appL10n.includeAny)],
    token: "filetypes",
    placeholder: appL10n.pdfPngJpg,
    help: appL10n.enterOneOrMoreFileExtensionsSeparatedByCommas,
  ),
  GlobalSearchFilter(
    id: "postDate",
    label: appL10n.postDate,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.date,
    icon: "calendar",
    group: appL10n.datesCounts,
    operators: const [
      GlobalSearchFilterOperator("after", "after"),
      GlobalSearchFilterOperator("before", "before"),
    ],
    token: "after",
    placeholder: appL10n.inputIsoDate,
    help: appL10n.matchWhenAPostWasCreated,
    opTokens: const {"after": "after", "before": "before"},
  ),
  GlobalSearchFilter(
    id: "postCount",
    label: appL10n.postCount,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.number,
    icon: "topics",
    group: appL10n.datesCounts,
    operators: [
      GlobalSearchFilterOperator("gte", appL10n.atLeast),
      GlobalSearchFilterOperator("lte", appL10n.atMost),
      const GlobalSearchFilterOperator("eq", "exactly"),
    ],
    token: "min_posts",
    placeholder: "10",
    help: appL10n.countAllPostsInTheTopicIncludingTheOpeningPost,
    opTokens: const {
      "gte": "min_posts",
      "lte": "max_posts",
      "eq": "posts_count",
    },
  ),
  GlobalSearchFilter(
    id: "viewCount",
    label: appL10n.views,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.number,
    icon: "eye",
    group: appL10n.datesCounts,
    operators: [
      GlobalSearchFilterOperator("gte", appL10n.atLeast),
      GlobalSearchFilterOperator("lte", appL10n.atMost),
    ],
    token: "min_views",
    placeholder: "100",
    help: appL10n.matchTheTopicSViewCount,
    opTokens: const {"gte": "min_views", "lte": "max_views"},
  ),
  GlobalSearchFilter(
    id: "locale",
    label: appL10n.language,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "globe",
    group: appL10n.content,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "locale",
    placeholder: appL10n.enFrAnyOrNone,
    help: appL10n.enterALanguageCodeAnyForADetectedLanguageOrNone,
    choices: [
      GlobalSearchFilterChoice(
        value: "en",
        label: appL10n.english,
        token: "locale:en",
      ),
      GlobalSearchFilterChoice(
        value: "fr",
        label: appL10n.french,
        token: "locale:fr",
      ),
      GlobalSearchFilterChoice(
        value: "de",
        label: appL10n.german,
        token: "locale:de",
      ),
      GlobalSearchFilterChoice(
        value: "es",
        label: appL10n.spanish,
        token: "locale:es",
      ),
      GlobalSearchFilterChoice(
        value: "any",
        label: appL10n.anyDetectedLanguage,
        token: "locale:any",
      ),
      GlobalSearchFilterChoice(
        value: "none",
        label: appL10n.noDetectedLanguage,
        token: "locale:none",
      ),
    ],
  ),
  GlobalSearchFilter(
    rejectQuotes: true,
    id: "badge",
    label: appL10n.authorSBadge,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "badge",
    group: appL10n.people,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "badge",
    placeholder: appL10n.badgeNameOrID,
    help: appL10n.findPostsWrittenByUsersWhoHoldThisBadge,
  ),
  GlobalSearchFilter(
    id: "topicId",
    label: appL10n.specificTopic,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.number,
    icon: "topics",
    group: appL10n.where,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "topic",
    placeholder: appL10n.topicID,
    help: appL10n.searchPostsWithinOneTopic,
  ),
  GlobalSearchFilter(
    id: "hashtag",
    label: appL10n.categoryTagOrTagGroup,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "hash",
    group: appL10n.advanced,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "#",
    placeholder: appL10n.categoryTagOrTagGroupSlug,
    help: appL10n.lookUpACategoryFirstThenATagThenATag,
  ),
  GlobalSearchFilter(
    id: "visibility",
    label: appL10n.unlistedTopics,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "eye",
    group: appL10n.permissions,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n
        .availableWhenYourAccountCanViewUnlistedTopicsIncludingEligibleTrust,
    optional: "staff",
    choices: [
      GlobalSearchFilterChoice(
        value: "include",
        label: appL10n.includeUnlistedTopics,
        token: "include:unlisted",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "whispers",
    label: appL10n.whispers,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "lock",
    group: appL10n.permissions,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.requiresPermissionToReadWhispers,
    optional: "staff",
    choices: [
      GlobalSearchFilterChoice(
        value: "whispers",
        label: appL10n.whisperPosts,
        token: "in:whisper",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "adminMessages",
    label: appL10n.allPersonalMessages,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "lock",
    group: appL10n.permissions,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.administratorSearchAcrossPersonalMessages,
    optional: "admin",
    choices: [
      GlobalSearchFilterChoice(
        value: "all",
        label: appL10n.allUsersPersonalMessages,
        token: "in:all-pms",
      ),
    ],
  ),
  GlobalSearchFilter(
    lookup: GlobalSearchLookup.users,
    singleIdentifier: true,
    id: "adminUserMessages",
    label: appL10n.userSPersonalMessages,
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "mail",
    group: appL10n.permissions,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "personal_messages",
    placeholder: appL10n.username,
    help: appL10n.administratorSearchWithinThePersonalMessagesOfThisUser,
    optional: "admin",
  ),
  GlobalSearchFilter(
    lookup: GlobalSearchLookup.groups,
    id: "userGroup",
    label: appL10n.group,
    scope: GlobalSearchScope.users,
    kind: GlobalSearchFilterKind.text,
    icon: "users",
    group: appL10n.people,
    operators: [
      GlobalSearchFilterOperator("is", appL10n.isAMemberOf),
      GlobalSearchFilterOperator("excludes", appL10n.isNotAMemberOf),
    ],
    token: "group",
    placeholder: appL10n.groupName,
    help: appL10n
        .selectAGroupWhoseMembershipIsVisibleExclusionsCanContainMultiple,
    opTokens: const {"is": "group", "excludes": "exclude_groups"},
  ),
  GlobalSearchFilter(
    lookup: GlobalSearchLookup.users,
    id: "userName",
    label: appL10n.username,
    scope: GlobalSearchScope.users,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: appL10n.people,
    operators: [
      GlobalSearchFilterOperator("is", appL10n.isExactly),
      GlobalSearchFilterOperator("excludes", appL10n.searchOperatorExcludes),
    ],
    token: "username",
    placeholder: appL10n.username,
    help: appL10n.matchOneExactUsernameOrExcludeUsernamesSeparatedByCommas,
    opTokens: const {"is": "username", "excludes": "exclude_usernames"},
  ),
  GlobalSearchFilter(
    id: "userPeriod",
    label: appL10n.activityPeriod,
    scope: GlobalSearchScope.users,
    kind: GlobalSearchFilterKind.choice,
    icon: "calendar",
    group: appL10n.activity,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.chooseTheTimePeriodUsedForUserActivityStatistics,
    choices: [
      GlobalSearchFilterChoice(
        value: "all",
        label: appL10n.allTime,
        token: "period=all",
      ),
      GlobalSearchFilterChoice(
        value: "yearly",
        label: appL10n.year,
        token: "period=yearly",
      ),
      GlobalSearchFilterChoice(
        value: "quarterly",
        label: appL10n.quarter,
        token: "period=quarterly",
      ),
      GlobalSearchFilterChoice(
        value: "monthly",
        label: appL10n.month,
        token: "period=monthly",
      ),
      GlobalSearchFilterChoice(
        value: "weekly",
        label: appL10n.week,
        token: "period=weekly",
      ),
      GlobalSearchFilterChoice(
        value: "daily",
        label: appL10n.day,
        token: "period=daily",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "groupType",
    label: appL10n.groupType,
    scope: GlobalSearchScope.groups,
    kind: GlobalSearchFilterKind.choice,
    icon: "users",
    group: appL10n.membership,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help:
        appL10n.filterGroupMembershipOrAdmissionClosedMembershipDoesNotMeanThe,
    choices: [
      GlobalSearchFilterChoice(
        value: "my",
        label: appL10n.groupsIJoined,
        token: "type=my",
      ),
      GlobalSearchFilterChoice(
        value: "owner",
        label: appL10n.groupsIOwn,
        token: "type=owner",
      ),
      GlobalSearchFilterChoice(
        value: "public",
        label: appL10n.openMembership,
        token: "type=public",
      ),
      GlobalSearchFilterChoice(
        value: "close",
        label: appL10n.closedMembership,
        token: "type=close",
      ),
      GlobalSearchFilterChoice(
        value: "non_automatic",
        label: appL10n.customGroups,
        token: "type=non_automatic",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "groupAutomatic",
    label: appL10n.automaticGroups,
    scope: GlobalSearchScope.groups,
    kind: GlobalSearchFilterKind.choice,
    icon: "users",
    group: appL10n.permissions,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    help: appL10n.browseAutomaticGroupsAvailableToStaff,
    optional: "staff",
    choices: [
      GlobalSearchFilterChoice(
        value: "automatic",
        label: appL10n.automaticGroups,
        token: "type=automatic",
      ),
    ],
  ),
  GlobalSearchFilter(
    lookup: GlobalSearchLookup.users,
    singleIdentifier: true,
    id: "groupMember",
    label: appL10n.member,
    scope: GlobalSearchScope.groups,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: appL10n.membership,
    operators: [GlobalSearchFilterOperator("is", appL10n.searchOperatorIs)],
    token: "username",
    placeholder: appL10n.username,
    help: appL10n.findGroupsThisPersonBelongsToWhereGroupMembershipIsVisible,
  ),
];

GlobalSearchFilter? globalSearchFilter(
  String id, [
  GlobalSearchCapabilities c = const GlobalSearchCapabilities(),
]) {
  for (final filter in [...globalSearchFilters, ...c.contributedFilters]) {
    if (filter.id == id) return filter;
  }
  return null;
}

bool globalSearchFilterAvailable(
  GlobalSearchFilter filter,
  GlobalSearchCapabilities c,
) {
  final owner = c.contributions
      .where((p) => p.filters.any((f) => f.id == filter.id))
      .firstOrNull;
  if (owner != null && !c.enabledContributions.contains(owner.owner)) {
    return false;
  }
  if (!filter.scope.isCore && !c.scopes.contains(filter.scope)) return false;
  if (filter.scope == GlobalSearchScope.users && !c.userDirectory) return false;
  if (filter.scope == GlobalSearchScope.groups && !c.groupDirectory) {
    return false;
  }
  if (['tags', 'hashtag'].contains(filter.id) && !c.tagging) return false;
  if ([
        'activity',
        'privateMessages',
        'groupInbox',
        'userGroup',
        'groupMember',
      ].contains(filter.id) &&
      !c.authenticated) {
    return false;
  }
  if (filter.id == 'visibility') return c.unlisted;
  if (filter.id == 'whispers') return c.whispers;
  return switch (filter.optional) {
    'admin' => c.admin,
    'staff' => c.staff || c.admin,
    _ => true,
  };
}

List<GlobalSearchOrder> globalSearchOrders(
  GlobalSearchScope scope,
  GlobalSearchCapabilities c,
) => switch (scope) {
  GlobalSearchScope.all => [
    GlobalSearchOrder('relevance', appL10n.mostRelevant),
  ],
  GlobalSearchScope.forum => [
    GlobalSearchOrder('relevance', appL10n.mostRelevant),
    GlobalSearchOrder('latest', appL10n.latestPost),
    GlobalSearchOrder('oldest', appL10n.oldestPost),
    GlobalSearchOrder('latest_topic', appL10n.newestTopic),
    GlobalSearchOrder('oldest_topic', appL10n.oldestTopic),
    GlobalSearchOrder('views', appL10n.mostViewed),
    GlobalSearchOrder('likes', appL10n.mostLiked),
    if (c.authenticated) GlobalSearchOrder('read', appL10n.recentlyRead),
    for (final p in c.contributions)
      if (c.enabledContributions.contains(p.owner)) ...p.orders(scope),
  ],
  GlobalSearchScope.groups => [
    GlobalSearchOrder('name', appL10n.groupName),
    if (c.groupDirectory && c.groupMemberOrder)
      GlobalSearchOrder('user_count', appL10n.memberCount),
  ],
  GlobalSearchScope.users => [
    for (final key in c.userDirectory ? c.userOrders : const ['username'])
      GlobalSearchOrder(key, switch (key) {
        'username' => appL10n.username,
        'likes_received' => appL10n.likesReceived,
        'likes_given' => appL10n.likesGiven,
        'topics_entered' => appL10n.topicsViewed,
        'topic_count' => appL10n.topicsCreated,
        'post_count' => appL10n.postsCreated,
        'posts_read' => appL10n.postsRead,
        'days_visited' => appL10n.daysVisited,
        _ => key.replaceAll('_', ' '),
      }),
  ],
  _ => [
    for (final p in c.contributions)
      if (c.enabledContributions.contains(p.owner)) ...p.orders(scope),
  ],
};

String? validateGlobalSearchCondition(
  GlobalSearchCondition condition,
  GlobalSearchCapabilities c,
) {
  final d = globalSearchFilter(condition.filterId, c);
  if (d == null || !globalSearchFilterAvailable(d, c)) {
    return appL10n.thisFilterIsUnavailableOnThisSite;
  }
  if (!d.operators.any((o) => o.value == condition.operator)) {
    return appL10n.chooseASupportedCondition;
  }
  final values = condition.value;
  if (values.isEmpty || values.any((v) => v.trim().isEmpty)) {
    return appL10n.chooseOrEnterAValue;
  }
  if (values.length > 30 ||
      values.any(
        (v) => v.length > 255 || v.contains('\n') || v.contains('\u0000'),
      )) {
    return appL10n.theFilterValueIsTooLong;
  }
  final value = values.join(',');
  if (d.kind == GlobalSearchFilterKind.choice &&
      !d.choices.any((v) => v.value == value)) {
    return appL10n.chooseAnAvailableValue;
  }
  if (d.id == 'groupType' &&
      !c.authenticated &&
      ['my', 'owner'].contains(value)) {
    return appL10n.signInToSearchYourMemberships;
  }
  if (d.id == 'files' &&
      value
          .split(',')
          .any(
            (v) =>
                !RegExp(r'^\.?[a-zA-Z0-9][a-zA-Z0-9_-]*$').hasMatch(v.trim()),
          )) {
    return appL10n.enterFileExtensionsSeparatedByCommas;
  }
  if (d.kind == GlobalSearchFilterKind.number &&
      (int.tryParse(value) == null ||
          int.parse(value) < 0 ||
          d.id == 'topicId' && int.parse(value) < 2)) {
    return appL10n.enterAValidWholeNumber;
  }
  if (d.kind == GlobalSearchFilterKind.date) {
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != value) {
      return appL10n.chooseAValidDate;
    }
  }
  if (d.singleIdentifier && RegExp(r'[\s,:]').hasMatch(value)) {
    return appL10n.enterOneUsernameGroupOrChannelSlug;
  }
  if (['userGroup', 'userName'].contains(d.id) &&
      condition.operator == 'is' &&
      RegExp(r'[,|\s]').hasMatch(value)) {
    return appL10n.chooseOneValueForThisCondition;
  }
  if (d.id == 'locale' && !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
    return appL10n.enterOneLanguageCodeAnyOrNone;
  }
  if (['category', 'tags'].contains(d.id) &&
      values.any((v) => RegExp(r'[\s,"+]').hasMatch(v))) {
    return appL10n.chooseValidCategorySlugsOrTagNames;
  }
  if (d.rejectQuotes && value.contains('"')) {
    return appL10n.removeQuotesFromTheValue;
  }
  return null;
}

String globalSearchConditionToken(
  GlobalSearchCondition f, {
  String? username,
  GlobalSearchCapabilities capabilities = const GlobalSearchCapabilities(),
}) {
  final d = globalSearchFilter(f.filterId, capabilities)!;
  var value = f.value.join(',');
  for (final choice in d.choices) {
    if (choice.value == value && choice.token != null) return choice.token!;
  }
  if (d.id == 'category') {
    return 'category:${f.value.map((v) => f.operator == 'exactCategory' ? '=$v' : v).join(',')}';
  }
  if (d.id == 'tags') {
    return '${['none', 'notAll'].contains(f.operator) ? '-' : ''}tags:${f.value.join(['all', 'notAll'].contains(f.operator) ? '+' : ',')}';
  }
  final key = d.opTokens[f.operator] ?? d.token!;
  String user(String v) =>
      v.replaceFirst(RegExp(r'^@'), '').toLowerCase() == 'me' &&
          username != null
      ? username
      : v.replaceFirst(RegExp(r'^@'), '');
  if (key == '@') return '@${value.replaceFirst(RegExp(r'^@'), '')}';
  if (key == '#') return '#${value.replaceFirst(RegExp(r'^#'), '')}';
  if (key == 'created:@') return 'created:@${user(value)}';
  if (['userName', 'groupMember'].contains(d.id)) {
    value = value.split(',').map(user).join(',');
  }
  if (d.scope == GlobalSearchScope.users ||
      d.scope == GlobalSearchScope.groups) {
    if (key == 'exclude_groups') {
      value = value.split(RegExp(r'[,|]')).map((v) => v.trim()).join('|');
    }
    return '$key=$value';
  }
  if (d.id == 'files') {
    value = value
        .toLowerCase()
        .split(',')
        .map((v) => v.trim().replaceFirst(RegExp(r'^\.'), ''))
        .join(',');
  }
  return '$key:${value.contains(' ') ? '"$value"' : value}';
}

String globalSearchTerm(GlobalSearchRequest r) {
  final parts = [
    r.query.trim(),
    for (final f in r.conditions)
      globalSearchConditionToken(
        f,
        username: r.capabilities.username,
        capabilities: r.capabilities,
      ),
    if (r.scope == GlobalSearchScope.forum && r.order != 'relevance')
      'order:${r.order}',
  ];
  return parts.where((p) => p.isNotEmpty).join(' ');
}

class GlobalSearchExpression {
  const GlobalSearchExpression(this.query, this.conditions, this.order);
  final String query;
  final List<GlobalSearchCondition> conditions;
  final String? order;
}

GlobalSearchExpression parseGlobalSearchExpression(
  String text,
  GlobalSearchScope scope,
  GlobalSearchCapabilities c,
) {
  if (scope == GlobalSearchScope.users || scope == GlobalSearchScope.groups) {
    return GlobalSearchExpression(text, const [], null);
  }
  final plain = <String>[], conditions = <GlobalSearchCondition>[];
  String? order;
  final aliases = {
    'l': 'order:latest',
    'r': 'order:read',
    'f': 'in:first',
    't': 'in:title',
    'in:mine': 'in:created',
    'in:messages': 'in:personal',
    'in:whispers': 'in:whisper',
    'in:bots': 'in:bot',
    'in:humans': 'in:human',
    'include:invisible': 'include:unlisted',
  };
  final target = scope == GlobalSearchScope.all
      ? GlobalSearchScope.forum
      : scope;
  for (final match in RegExp(r'(?:[^\s"]+|"[^"]*")+').allMatches(text)) {
    final raw = match.group(0)!;
    var token = !scope.isCore ? raw : aliases[raw] ?? raw;
    token = token
        .replaceFirst(RegExp(r'^min_post_count:'), 'min_posts:')
        .replaceFirst(RegExp(r'^filetype:'), 'filetypes:');
    if (token.startsWith('"')) {
      plain.add(raw);
      continue;
    }
    if (token.startsWith('order:')) {
      final value = token.substring(6);
      if (!globalSearchOrders(target, c).any((o) => o.value == value)) {
        throw FormatException(appL10n.thisOrderingIsUnavailable);
      }
      order = value;
      continue;
    }
    GlobalSearchCondition? condition;
    for (final d in [
      ...globalSearchFilters,
      ...c.contributedFilters,
    ].where((d) => d.scope == target)) {
      for (final choice in d.choices) {
        if (choice.token == token) {
          condition = GlobalSearchCondition(
            filterId: d.id,
            operator: d.operators.first.value,
            value: [choice.value],
          );
        }
      }
    }
    if (condition == null) {
      for (final d in [...globalSearchFilters, ...c.contributedFilters]) {
        if (d.scope != target || !const ['@', '#'].contains(d.token)) continue;
        if (token.startsWith(d.token!)) {
          condition = GlobalSearchCondition(
            filterId: d.id,
            value: [token.substring(1)],
          );
          break;
        }
      }
    }
    if (condition == null &&
        token.contains(':') &&
        target == GlobalSearchScope.forum) {
      final i = token.indexOf(':'), key = token.substring(0, i);
      var value = token.substring(i + 1).replaceAll(RegExp(r'^"|"$'), '');
      if (key == 'user') {
        condition = GlobalSearchCondition(filterId: 'author', value: [value]);
      }
      if (key == 'created' && value.startsWith('@')) {
        condition = GlobalSearchCondition(
          filterId: 'topicAuthor',
          value: [value.substring(1)],
        );
      }
      if (['category', 'categories'].contains(key)) {
        condition = GlobalSearchCondition(
          filterId: 'category',
          operator: value.startsWith('=') ? 'exactCategory' : 'any',
          value: value
              .split(',')
              .map((v) => v.replaceFirst(RegExp(r'^='), ''))
              .toList(),
        );
      }
      if (['tags', 'tag', '-tags', '-tag'].contains(key)) {
        condition = GlobalSearchCondition(
          filterId: 'tags',
          operator: key.startsWith('-')
              ? (value.contains('+') ? 'notAll' : 'none')
              : (value.contains('+') ? 'all' : 'any'),
          value: value.split(RegExp(r'[,+]')),
        );
      }
      if (condition == null) {
        for (final d in [...globalSearchFilters, ...c.contributedFilters].where(
          (d) =>
              d.scope == target &&
              d.kind != GlobalSearchFilterKind.choice &&
              d.kind != GlobalSearchFilterKind.multi,
        )) {
          final ops = d.opTokens.entries.where((e) => e.value == key);
          if (d.token == key || ops.isNotEmpty) {
            if (d.kind == GlobalSearchFilterKind.date &&
                RegExp(r'^\d{1,3}$').hasMatch(value)) {
              value = DateTime.now()
                  .toUtc()
                  .subtract(Duration(days: int.parse(value)))
                  .toIso8601String()
                  .substring(0, 10);
            }
            condition = GlobalSearchCondition(
              filterId: d.id,
              operator: ops.isEmpty ? d.operators.first.value : ops.first.key,
              value: [value],
            );
            break;
          }
        }
      }
    }
    if (condition == null) {
      if (RegExp(r'^(in|status|order|include):').hasMatch(token)) {
        throw FormatException(
          appL10n.unknownOrUnavailableSearchOperator((token).toString()),
        );
      }
      plain.add(raw);
    } else {
      final error = validateGlobalSearchCondition(condition, c);
      if (error != null) throw FormatException(error);
      conditions.add(condition);
    }
  }
  return GlobalSearchExpression(
    plain.join(' '),
    List.unmodifiable(conditions),
    order,
  );
}
