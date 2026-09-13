import 'global_search_models.dart';

const globalSearchFilters = <GlobalSearchFilter>[
  GlobalSearchFilter(
    id: "category",
    label: "Category",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.multi,
    icon: "folder",
    group: "Where",
    operators: [
      GlobalSearchFilterOperator("any", "include subcategories"),
      GlobalSearchFilterOperator("exactCategory", "only these categories"),
    ],
    token: "category",
    placeholder: "Choose categories",
    help:
        "Choose one or more categories. Multiple categories match any selected category.",
  ),
  GlobalSearchFilter(
    id: "tags",
    label: "Tags",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.multi,
    icon: "tag",
    group: "Where",
    operators: [
      GlobalSearchFilterOperator("any", "include any"),
      GlobalSearchFilterOperator("all", "include all"),
      GlobalSearchFilterOperator("none", "exclude any"),
      GlobalSearchFilterOperator("notAll", "exclude combination"),
    ],
    token: "tags",
    placeholder: "Choose tags",
    help: "Match any tag, every tag, or exclude selected tags.",
  ),
  GlobalSearchFilter(
    id: "author",
    label: "Posted by",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: "People",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "@",
    placeholder: "Username or me",
    help: "Find posts written by a specific person. Use me for your posts.",
  ),
  GlobalSearchFilter(
    id: "topicAuthor",
    label: "Started by",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: "People",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "created:@",
    placeholder: "Username",
    help: "Find opening posts written by this person.",
  ),
  GlobalSearchFilter(
    id: "authorGroup",
    label: "Author’s group",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "users",
    group: "People",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "group",
    placeholder: "Group name",
    help:
        "Find posts written by members of a group whose membership you can view.",
  ),
  GlobalSearchFilter(
    id: "groupInbox",
    label: "Group inbox",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "mail",
    group: "Where",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "group_messages",
    placeholder: "Group name",
    help: "Search personal messages addressed to this group.",
  ),
  GlobalSearchFilter(
    id: "searchIn",
    label: "Search in",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "search",
    group: "Where",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help:
        "By default, results are grouped by topic. Every matching post shows separate results from the same topic.",
    choices: [
      GlobalSearchFilterChoice(
        value: "title",
        label: "Topic titles",
        token: "in:title",
      ),
      GlobalSearchFilterChoice(
        value: "first",
        label: "Opening posts",
        token: "in:first",
      ),
      GlobalSearchFilterChoice(
        value: "replies",
        label: "Replies",
        token: "in:replies",
      ),
      GlobalSearchFilterChoice(
        value: "allPosts",
        label: "Every matching post",
        token: "in:all-posts",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "privateMessages",
    label: "Messages & topics",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "mail",
    group: "Where",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Search the topics and personal messages available to your account.",
    choices: [
      GlobalSearchFilterChoice(
        value: "all",
        label: "Topics and my messages",
        token: "in:all",
      ),
      GlobalSearchFilterChoice(
        value: "personal",
        label: "My personal messages",
        token: "in:personal",
      ),
      GlobalSearchFilterChoice(
        value: "direct",
        label: "One-to-one personal messages",
        token: "in:personal-direct",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "activity",
    label: "My activity",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "bookmark",
    group: "Personal",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help:
        "Narrow results using your reading, notification, and posting activity.",
    choices: [
      GlobalSearchFilterChoice(
        value: "seen",
        label: "Read posts",
        token: "in:seen",
      ),
      GlobalSearchFilterChoice(
        value: "unseen",
        label: "Unread posts",
        token: "in:unseen",
      ),
      GlobalSearchFilterChoice(
        value: "watching",
        label: "Watching",
        token: "in:watching",
      ),
      GlobalSearchFilterChoice(
        value: "tracking",
        label: "Tracking or watching",
        token: "in:tracking",
      ),
      GlobalSearchFilterChoice(
        value: "bookmarks",
        label: "Bookmarked posts",
        token: "in:bookmarks",
      ),
      GlobalSearchFilterChoice(
        value: "likes",
        label: "Liked posts",
        token: "in:likes",
      ),
      GlobalSearchFilterChoice(
        value: "posted",
        label: "My posts",
        token: "in:posted",
      ),
      GlobalSearchFilterChoice(
        value: "created",
        label: "Topics I started",
        token: "in:created",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "status",
    label: "Topic status",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "status",
    group: "Content",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Open topics are neither closed nor archived.",
    choices: [
      GlobalSearchFilterChoice(
        value: "open",
        label: "Open",
        token: "status:open",
      ),
      GlobalSearchFilterChoice(
        value: "closed",
        label: "Closed",
        token: "status:closed",
      ),
      GlobalSearchFilterChoice(
        value: "archived",
        label: "Archived",
        token: "status:archived",
      ),
      GlobalSearchFilterChoice(
        value: "noreplies",
        label: "No replies",
        token: "status:noreplies",
      ),
      GlobalSearchFilterChoice(
        value: "singleUser",
        label: "One participant",
        token: "status:single_user",
      ),
      GlobalSearchFilterChoice(
        value: "public",
        label: "Public categories",
        token: "status:public",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "postType",
    label: "Post type",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "post",
    group: "Content",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Choose the type of post to find.",
    choices: [
      GlobalSearchFilterChoice(
        value: "regular",
        label: "Regular posts",
        token: "in:regular",
      ),
      GlobalSearchFilterChoice(
        value: "wiki",
        label: "Wiki posts",
        token: "in:wiki",
      ),
      GlobalSearchFilterChoice(
        value: "pinned",
        label: "Posts in pinned topics",
        token: "in:pinned",
      ),
      GlobalSearchFilterChoice(
        value: "bot",
        label: "Posts by bots",
        token: "in:bot",
      ),
      GlobalSearchFilterChoice(
        value: "human",
        label: "Posts by people",
        token: "in:human",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "content",
    label: "Contains",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "image",
    group: "Content",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Find posts with images or topics with or without tags.",
    choices: [
      GlobalSearchFilterChoice(
        value: "images",
        label: "Images",
        token: "with:images",
      ),
      GlobalSearchFilterChoice(
        value: "tagged",
        label: "At least one tag",
        token: "in:tagged",
      ),
      GlobalSearchFilterChoice(
        value: "untagged",
        label: "No tags",
        token: "in:untagged",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "files",
    label: "File types",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "folder",
    group: "Content",
    operators: [GlobalSearchFilterOperator("any", "include any")],
    token: "filetypes",
    placeholder: "pdf, png, jpg",
    help: "Enter one or more file extensions, separated by commas.",
  ),
  GlobalSearchFilter(
    id: "postDate",
    label: "Post date",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.date,
    icon: "calendar",
    group: "Dates & counts",
    operators: [
      GlobalSearchFilterOperator("after", "after"),
      GlobalSearchFilterOperator("before", "before"),
    ],
    token: "after",
    placeholder: "YYYY-MM-DD",
    help: "Match when a post was created.",
    opTokens: {"after": "after", "before": "before"},
  ),
  GlobalSearchFilter(
    id: "postCount",
    label: "Post count",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.number,
    icon: "topics",
    group: "Dates & counts",
    operators: [
      GlobalSearchFilterOperator("gte", "at least"),
      GlobalSearchFilterOperator("lte", "at most"),
      GlobalSearchFilterOperator("eq", "exactly"),
    ],
    token: "min_posts",
    placeholder: "10",
    help: "Count all posts in the topic, including the opening post.",
    opTokens: {"gte": "min_posts", "lte": "max_posts", "eq": "posts_count"},
  ),
  GlobalSearchFilter(
    id: "viewCount",
    label: "Views",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.number,
    icon: "eye",
    group: "Dates & counts",
    operators: [
      GlobalSearchFilterOperator("gte", "at least"),
      GlobalSearchFilterOperator("lte", "at most"),
    ],
    token: "min_views",
    placeholder: "100",
    help: "Match the topic’s view count.",
    opTokens: {"gte": "min_views", "lte": "max_views"},
  ),
  GlobalSearchFilter(
    id: "locale",
    label: "Language",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "globe",
    group: "Content",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "locale",
    placeholder: "en, fr, any, or none",
    help:
        "Enter a language code, any for a detected language, or none for posts without one.",
    choices: [
      GlobalSearchFilterChoice(
        value: "en",
        label: "English",
        token: "locale:en",
      ),
      GlobalSearchFilterChoice(
        value: "fr",
        label: "French",
        token: "locale:fr",
      ),
      GlobalSearchFilterChoice(
        value: "de",
        label: "German",
        token: "locale:de",
      ),
      GlobalSearchFilterChoice(
        value: "es",
        label: "Spanish",
        token: "locale:es",
      ),
      GlobalSearchFilterChoice(
        value: "any",
        label: "Any detected language",
        token: "locale:any",
      ),
      GlobalSearchFilterChoice(
        value: "none",
        label: "No detected language",
        token: "locale:none",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "badge",
    label: "Author’s badge",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "badge",
    group: "People",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "badge",
    placeholder: "Badge name or ID",
    help: "Find posts written by users who hold this badge.",
  ),
  GlobalSearchFilter(
    id: "topicId",
    label: "Specific topic",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.number,
    icon: "topics",
    group: "Where",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "topic",
    placeholder: "Topic ID",
    help: "Search posts within one topic.",
  ),
  GlobalSearchFilter(
    id: "hashtag",
    label: "Category, tag or tag group",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "hash",
    group: "Advanced",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "#",
    placeholder: "Category, tag, or tag group slug",
    help:
        "Look up a category first, then a tag, then a tag group with this slug.",
  ),
  GlobalSearchFilter(
    id: "visibility",
    label: "Unlisted topics",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "eye",
    group: "Permissions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help:
        "Available when your account can view unlisted topics, including eligible trust level 4 users.",
    optional: "staff",
    choices: [
      GlobalSearchFilterChoice(
        value: "include",
        label: "Include unlisted topics",
        token: "include:unlisted",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "whispers",
    label: "Whispers",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "lock",
    group: "Permissions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Requires permission to read whispers.",
    optional: "staff",
    choices: [
      GlobalSearchFilterChoice(
        value: "whispers",
        label: "Whisper posts",
        token: "in:whisper",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "adminMessages",
    label: "All personal messages",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "lock",
    group: "Permissions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Administrator search across personal messages.",
    optional: "admin",
    choices: [
      GlobalSearchFilterChoice(
        value: "all",
        label: "All users’ personal messages",
        token: "in:all-pms",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "adminUserMessages",
    label: "User’s personal messages",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "mail",
    group: "Permissions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "personal_messages",
    placeholder: "Username",
    help: "Administrator search within the personal messages of this user.",
    optional: "admin",
  ),
  GlobalSearchFilter(
    id: "solved",
    label: "Solution",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "status",
    group: "Extensions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help:
        "Find solved topics or unsolved topics in categories that support solutions.",
    optional: "solved",
    choices: [
      GlobalSearchFilterChoice(
        value: "solved",
        label: "Solved",
        token: "status:solved",
      ),
      GlobalSearchFilterChoice(
        value: "unsolved",
        label: "Unsolved",
        token: "status:unsolved",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "assignment",
    label: "Assignment",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "user",
    group: "Extensions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Requires permission to view assignments.",
    optional: "assign",
    choices: [
      GlobalSearchFilterChoice(
        value: "assigned",
        label: "Assigned",
        token: "in:assigned",
      ),
      GlobalSearchFilterChoice(
        value: "unassigned",
        label: "Unassigned",
        token: "in:unassigned",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "assignee",
    label: "Assigned to",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: "Extensions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "assigned",
    placeholder: "Username or group name",
    help: "Find topics assigned to a person or group.",
    optional: "assign",
  ),
  GlobalSearchFilter(
    id: "polls",
    label: "Polls",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.choice,
    icon: "status",
    group: "Extensions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Find posts containing polls.",
    optional: "poll",
    choices: [
      GlobalSearchFilterChoice(
        value: "polls",
        label: "Contains a poll",
        token: "in:polls",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "votes",
    label: "Topic votes",
    scope: GlobalSearchScope.forum,
    kind: GlobalSearchFilterKind.number,
    icon: "heart",
    group: "Extensions",
    operators: [GlobalSearchFilterOperator("gte", "at least")],
    token: "min_vote_count",
    placeholder: "5",
    help: "Match the number of votes on a topic.",
    optional: "voting",
    opTokens: {"gte": "min_vote_count"},
  ),
  GlobalSearchFilter(
    id: "userGroup",
    label: "Group",
    scope: GlobalSearchScope.users,
    kind: GlobalSearchFilterKind.text,
    icon: "users",
    group: "People",
    operators: [
      GlobalSearchFilterOperator("is", "is a member of"),
      GlobalSearchFilterOperator("excludes", "is not a member of"),
    ],
    token: "group",
    placeholder: "Group name",
    help:
        "Select a group whose membership is visible. Exclusions can contain multiple group names.",
    opTokens: {"is": "group", "excludes": "exclude_groups"},
  ),
  GlobalSearchFilter(
    id: "userName",
    label: "Username",
    scope: GlobalSearchScope.users,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: "People",
    operators: [
      GlobalSearchFilterOperator("is", "is exactly"),
      GlobalSearchFilterOperator("excludes", "excludes"),
    ],
    token: "username",
    placeholder: "Username",
    help: "Match one exact username, or exclude usernames separated by commas.",
    opTokens: {"is": "username", "excludes": "exclude_usernames"},
  ),
  GlobalSearchFilter(
    id: "userPeriod",
    label: "Activity period",
    scope: GlobalSearchScope.users,
    kind: GlobalSearchFilterKind.choice,
    icon: "calendar",
    group: "Activity",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Choose the time period used for user activity statistics.",
    choices: [
      GlobalSearchFilterChoice(
        value: "all",
        label: "All time",
        token: "period=all",
      ),
      GlobalSearchFilterChoice(
        value: "yearly",
        label: "Year",
        token: "period=yearly",
      ),
      GlobalSearchFilterChoice(
        value: "quarterly",
        label: "Quarter",
        token: "period=quarterly",
      ),
      GlobalSearchFilterChoice(
        value: "monthly",
        label: "Month",
        token: "period=monthly",
      ),
      GlobalSearchFilterChoice(
        value: "weekly",
        label: "Week",
        token: "period=weekly",
      ),
      GlobalSearchFilterChoice(
        value: "daily",
        label: "Day",
        token: "period=daily",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "groupType",
    label: "Group type",
    scope: GlobalSearchScope.groups,
    kind: GlobalSearchFilterKind.choice,
    icon: "users",
    group: "Membership",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help:
        "Filter group membership or admission. Closed membership does not mean the group is hidden.",
    choices: [
      GlobalSearchFilterChoice(
        value: "my",
        label: "Groups I joined",
        token: "type=my",
      ),
      GlobalSearchFilterChoice(
        value: "owner",
        label: "Groups I own",
        token: "type=owner",
      ),
      GlobalSearchFilterChoice(
        value: "public",
        label: "Open membership",
        token: "type=public",
      ),
      GlobalSearchFilterChoice(
        value: "close",
        label: "Closed membership",
        token: "type=close",
      ),
      GlobalSearchFilterChoice(
        value: "non_automatic",
        label: "Custom groups",
        token: "type=non_automatic",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "groupAutomatic",
    label: "Automatic groups",
    scope: GlobalSearchScope.groups,
    kind: GlobalSearchFilterKind.choice,
    icon: "users",
    group: "Permissions",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Browse automatic groups available to staff.",
    optional: "staff",
    choices: [
      GlobalSearchFilterChoice(
        value: "automatic",
        label: "Automatic groups",
        token: "type=automatic",
      ),
    ],
  ),
  GlobalSearchFilter(
    id: "groupMember",
    label: "Member",
    scope: GlobalSearchScope.groups,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: "Membership",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "username",
    placeholder: "Username",
    help:
        "Find groups this person belongs to, where group membership is visible.",
  ),
  GlobalSearchFilter(
    id: "chatAuthor",
    label: "Sent by",
    scope: GlobalSearchScope.chat,
    kind: GlobalSearchFilterKind.text,
    icon: "user",
    group: "People",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "@",
    placeholder: "Username or me",
    help: "Find messages sent by one person.",
  ),
  GlobalSearchFilter(
    id: "chatChannel",
    label: "Channel",
    scope: GlobalSearchScope.chat,
    kind: GlobalSearchFilterKind.text,
    icon: "hash",
    group: "Where",
    operators: [GlobalSearchFilterOperator("is", "is")],
    token: "#",
    placeholder: "Channel slug or ID",
    help: "Search one channel available to your account.",
  ),
  GlobalSearchFilter(
    id: "chatThreads",
    label: "Thread replies",
    scope: GlobalSearchScope.chat,
    kind: GlobalSearchFilterKind.choice,
    icon: "post",
    group: "Content",
    operators: [GlobalSearchFilterOperator("is", "is")],
    help: "Excluding replies still includes messages that started a thread.",
    choices: [
      GlobalSearchFilterChoice(
        value: "include",
        label: "Include thread replies",
        token: "exclude_threads=false",
      ),
      GlobalSearchFilterChoice(
        value: "exclude",
        label: "Exclude thread replies",
        token: "exclude_threads=true",
      ),
    ],
  ),
];

GlobalSearchFilter? globalSearchFilter(String id) {
  for (final filter in globalSearchFilters) {
    if (filter.id == id) return filter;
  }
  return null;
}

bool globalSearchFilterAvailable(
  GlobalSearchFilter filter,
  GlobalSearchCapabilities c,
) {
  if (filter.scope == GlobalSearchScope.chat && !c.chat) return false;
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
    'solved' => c.solved,
    'assign' => c.assign,
    'poll' => c.poll,
    'voting' => c.voting,
    _ => true,
  };
}

List<GlobalSearchOrder> globalSearchOrders(
  GlobalSearchScope scope,
  GlobalSearchCapabilities c,
) => switch (scope) {
  GlobalSearchScope.all => const [
    GlobalSearchOrder('relevance', 'Most relevant'),
  ],
  GlobalSearchScope.forum => [
    const GlobalSearchOrder('relevance', 'Most relevant'),
    const GlobalSearchOrder('latest', 'Latest post'),
    const GlobalSearchOrder('oldest', 'Oldest post'),
    const GlobalSearchOrder('latest_topic', 'Newest topic'),
    const GlobalSearchOrder('oldest_topic', 'Oldest topic'),
    const GlobalSearchOrder('views', 'Most viewed'),
    const GlobalSearchOrder('likes', 'Most liked'),
    if (c.authenticated) const GlobalSearchOrder('read', 'Recently read'),
    if (c.voting) const GlobalSearchOrder('votes', 'Most votes'),
  ],
  GlobalSearchScope.chat => const [
    GlobalSearchOrder('relevance', 'Most relevant'),
    GlobalSearchOrder('latest', 'Latest message'),
  ],
  GlobalSearchScope.groups => [
    const GlobalSearchOrder('name', 'Group name'),
    if (c.groupDirectory && c.groupMemberOrder)
      const GlobalSearchOrder('user_count', 'Member count'),
  ],
  GlobalSearchScope.users => [
    for (final key in c.userDirectory ? c.userOrders : const ['username'])
      GlobalSearchOrder(key, switch (key) {
        'username' => 'Username',
        'likes_received' => 'Likes received',
        'likes_given' => 'Likes given',
        'topics_entered' => 'Topics viewed',
        'topic_count' => 'Topics created',
        'post_count' => 'Posts created',
        'posts_read' => 'Posts read',
        'days_visited' => 'Days visited',
        _ => key.replaceAll('_', ' '),
      }),
  ],
};

String? validateGlobalSearchCondition(
  GlobalSearchCondition condition,
  GlobalSearchCapabilities c,
) {
  final d = globalSearchFilter(condition.filterId);
  if (d == null || !globalSearchFilterAvailable(d, c)) {
    return 'This filter is unavailable on this site.';
  }
  if (!d.operators.any((o) => o.value == condition.operator)) {
    return 'Choose a supported condition.';
  }
  final values = condition.value;
  if (values.isEmpty || values.any((v) => v.trim().isEmpty)) {
    return 'Choose or enter a value.';
  }
  if (values.length > 30 ||
      values.any(
        (v) => v.length > 255 || v.contains('\n') || v.contains('\u0000'),
      )) {
    return 'The filter value is too long.';
  }
  final value = values.join(',');
  if (d.kind == GlobalSearchFilterKind.choice &&
      !d.choices.any((v) => v.value == value)) {
    return 'Choose an available value.';
  }
  if (d.id == 'groupType' &&
      !c.authenticated &&
      ['my', 'owner'].contains(value)) {
    return 'Sign in to search your memberships.';
  }
  if (d.id == 'files' &&
      value
          .split(',')
          .any(
            (v) =>
                !RegExp(r'^\.?[a-zA-Z0-9][a-zA-Z0-9_-]*$').hasMatch(v.trim()),
          )) {
    return 'Enter file extensions separated by commas.';
  }
  if (d.kind == GlobalSearchFilterKind.number &&
      (int.tryParse(value) == null ||
          int.parse(value) < 0 ||
          d.id == 'topicId' && int.parse(value) < 2)) {
    return 'Enter a valid whole number.';
  }
  if (d.kind == GlobalSearchFilterKind.date) {
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != value) {
      return 'Choose a valid date.';
    }
  }
  if ([
        'author',
        'topicAuthor',
        'authorGroup',
        'groupInbox',
        'chatAuthor',
        'chatChannel',
        'adminUserMessages',
        'assignee',
        'groupMember',
      ].contains(d.id) &&
      RegExp(r'[\s,:]').hasMatch(value)) {
    return 'Enter one username, group, or channel slug.';
  }
  if (['userGroup', 'userName'].contains(d.id) &&
      condition.operator == 'is' &&
      RegExp(r'[,|\s]').hasMatch(value)) {
    return 'Choose one value for this condition.';
  }
  if (d.id == 'locale' && !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
    return 'Enter one language code, any, or none.';
  }
  if (['category', 'tags'].contains(d.id) &&
      values.any((v) => RegExp(r'[\s,"+]').hasMatch(v))) {
    return 'Choose valid category slugs or tag names.';
  }
  if (['authorGroup', 'groupInbox', 'badge', 'assignee'].contains(d.id) &&
      value.contains('"')) {
    return 'Remove quotes from the value.';
  }
  return null;
}

String globalSearchConditionToken(GlobalSearchCondition f, {String? username}) {
  final d = globalSearchFilter(f.filterId)!;
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
      globalSearchConditionToken(f, username: r.capabilities.username),
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
  final target = scope == GlobalSearchScope.chat
      ? scope
      : GlobalSearchScope.forum;
  for (final match in RegExp(r'(?:[^\s"]+|"[^"]*")+').allMatches(text)) {
    final raw = match.group(0)!;
    var token = scope == GlobalSearchScope.chat ? raw : aliases[raw] ?? raw;
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
        throw const FormatException('This ordering is unavailable.');
      }
      order = value;
      continue;
    }
    GlobalSearchCondition? condition;
    for (final d in globalSearchFilters.where((d) => d.scope == target)) {
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
    if (condition == null && token.startsWith('@')) {
      condition = GlobalSearchCondition(
        filterId: target == GlobalSearchScope.chat ? 'chatAuthor' : 'author',
        value: [token.substring(1)],
      );
    }
    if (condition == null && token.startsWith('#')) {
      condition = GlobalSearchCondition(
        filterId: target == GlobalSearchScope.chat ? 'chatChannel' : 'hashtag',
        value: [token.substring(1)],
      );
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
        for (final d in globalSearchFilters.where(
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
        throw FormatException('Unknown or unavailable search operator: $token');
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
