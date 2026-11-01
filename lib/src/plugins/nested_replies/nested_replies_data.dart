import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart' show listEquals;

const nestedRepliesPluginId = PluginId('nested-replies');
const nestedRepliesSettingsKey = PluginDataKey<NestedRepliesSettings>(
  owner: 'nested-replies',
  name: 'settings',
);
const nestedRepliesTopicKey = PluginDataKey<NestedTopicData>(
  owner: 'nested-replies',
  name: 'topic',
);
const nestedRepliesPostKey = PluginDataKey<NestedPostData>(
  owner: 'nested-replies',
  name: 'post',
);

Map<String, String> nestedRepliesQuery(String? query) {
  try {
    return Uri(query: query).queryParameters;
  } on FormatException {
    return const {};
  }
}

enum NestedRepliesSort {
  top('top'),
  hot('hot'),
  newest('new'),
  oldest('old');

  const NestedRepliesSort(this.wireValue);
  final String wireValue;

  static NestedRepliesSort? parse(Object? value) {
    for (final sort in values) {
      if (sort.wireValue == value) return sort;
    }
    return null;
  }
}

final class NestedRepliesSettings {
  const NestedRepliesSettings({
    this.enabled,
    this.defaultEnabled = false,
    this.hotEnabled = false,
    this.defaultSort = NestedRepliesSort.top,
    this.maxDepth = 3,
    this.capDepth = true,
  });

  factory NestedRepliesSettings.fromJson(Map<String, dynamic> json) {
    final depth = json['nested_replies_max_depth'];
    return NestedRepliesSettings(
      enabled: json['nested_replies_enabled'] is bool
          ? json['nested_replies_enabled'] as bool
          : null,
      defaultEnabled: json['nested_replies_default'] == true,
      hotEnabled: json['nested_replies_hot_sort_enabled'] == true,
      defaultSort:
          NestedRepliesSort.parse(json['nested_replies_default_sort']) ??
          NestedRepliesSort.top,
      maxDepth: depth is int && depth >= 1 && depth <= 10 ? depth : 3,
      capDepth: json['nested_replies_cap_nesting_depth'] != false,
    );
  }

  final bool? enabled;
  final bool defaultEnabled;
  final bool hotEnabled;
  final NestedRepliesSort defaultSort;
  final int maxDepth;
  final bool capDepth;

  @override
  bool operator ==(Object other) =>
      other is NestedRepliesSettings &&
      enabled == other.enabled &&
      defaultEnabled == other.defaultEnabled &&
      hotEnabled == other.hotEnabled &&
      defaultSort == other.defaultSort &&
      maxDepth == other.maxDepth &&
      capDepth == other.capDepth;

  @override
  int get hashCode => Object.hash(
    enabled,
    defaultEnabled,
    hotEnabled,
    defaultSort,
    maxDepth,
    capDepth,
  );

  bool allowsTopic(NestedTopicData? topic, {required bool privateMessage}) =>
      !privateMessage && enabled != false && topic?.enabled == true;
}

final class NestedRepliesSettingsCodec
    extends PluginDataPersistenceCodec<NestedRepliesSettings> {
  const NestedRepliesSettingsCodec();

  @override
  PluginDataKey<NestedRepliesSettings> get key => nestedRepliesSettingsKey;

  @override
  NestedRepliesSettings? decode(Object? value) {
    if (value is! Map) return null;
    return NestedRepliesSettings.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Object encode(NestedRepliesSettings value) => {
    if (value.enabled != null) 'nested_replies_enabled': value.enabled,
    'nested_replies_default': value.defaultEnabled,
    'nested_replies_hot_sort_enabled': value.hotEnabled,
    'nested_replies_default_sort': value.defaultSort.wireValue,
    'nested_replies_max_depth': value.maxDepth,
    'nested_replies_cap_nesting_depth': value.capDepth,
  };
}

final class NestedTopicData
    implements TopicRecordValue, TopicReadingPolicyRecord {
  const NestedTopicData({
    this.enabled,
    this.hasNewReplies,
    this.hasActivityLog,
    this.pinnedPostIds,
  });

  factory NestedTopicData.fromJson(
    Map<String, dynamic> json, {
    bool authoritativeMode = false,
    bool authoritativeActivity = false,
  }) => NestedTopicData(
    enabled: json.containsKey('is_nested_view') || authoritativeMode
        ? json['is_nested_view'] == true
        : null,
    hasNewReplies: json.containsKey('has_new_replies') || authoritativeActivity
        ? json['has_new_replies'] == true
        : null,
    hasActivityLog: json['has_activity_log'] is bool
        ? json['has_activity_log'] as bool
        : null,
    pinnedPostIds: json['pinned_post_ids'] is List
        ? List.unmodifiable(
            (json['pinned_post_ids'] as List).whereType<int>().where(
              (id) => id > 0,
            ),
          )
        : null,
  );

  factory NestedTopicData.fromContext(
    Map<String, dynamic> json,
    TopicRecordDecodeContext context,
  ) => NestedTopicData.fromJson(
    json,
    authoritativeMode: context.source != TopicRecordSource.partial,
    authoritativeActivity: context.source == TopicRecordSource.list,
  );

  final bool? enabled;
  final bool? hasNewReplies;
  final bool? hasActivityLog;
  final List<int>? pinnedPostIds;

  @override
  bool operator ==(Object other) =>
      other is NestedTopicData &&
      enabled == other.enabled &&
      hasNewReplies == other.hasNewReplies &&
      hasActivityLog == other.hasActivityLog &&
      listEquals(pinnedPostIds, other.pinnedPostIds);

  @override
  int get hashCode => Object.hash(
    enabled,
    hasNewReplies,
    hasActivityLog,
    pinnedPostIds == null ? null : Object.hashAll(pinnedPostIds!),
  );

  @override
  TopicReadingPolicy? get topicReadingPolicy => enabled == true
      ? ActivityTopicReadingPolicy(
          activity: switch (hasNewReplies) {
            null => TopicActivityState.unknown,
            false => TopicActivityState.caughtUp,
            true => TopicActivityState.unread,
          },
        )
      : null;

  @override
  NestedTopicData mergeTopicRecord(Object? held) =>
      held is NestedTopicData ? held.merge(this) : this;

  @override
  NestedTopicData markTopicRead() => NestedTopicData(
    enabled: enabled,
    hasNewReplies: false,
    hasActivityLog: hasActivityLog,
    pinnedPostIds: pinnedPostIds,
  );

  NestedTopicData merge(NestedTopicData incoming) => NestedTopicData(
    enabled: incoming.enabled ?? enabled,
    hasNewReplies: incoming.hasNewReplies ?? hasNewReplies,
    hasActivityLog: incoming.hasActivityLog ?? hasActivityLog,
    pinnedPostIds: incoming.pinnedPostIds ?? pinnedPostIds,
  );
}

enum NestedPostPlaceholder { none, deleted, ignored }

final class NestedPostData {
  const NestedPostData({
    this.replyToPostNumber,
    this.directReplyCount = 0,
    this.totalDescendantCount = 0,
    this.placeholder = NestedPostPlaceholder.none,
    this.avatarColor,
    this.contentRedacted = false,
  });

  factory NestedPostData.fromJson(Map<String, dynamic> json) => NestedPostData(
    replyToPostNumber: nestedPositiveInt(json['reply_to_post_number']),
    directReplyCount: nestedCount(json['direct_reply_count']),
    totalDescendantCount: nestedCount(json['total_descendant_count']),
    placeholder: json['deleted_post_placeholder'] == true
        ? NestedPostPlaceholder.deleted
        : json['ignored_post_placeholder'] == true
        ? NestedPostPlaceholder.ignored
        : NestedPostPlaceholder.none,
    avatarColor: _avatarColor(json['avatar_color']),
    contentRedacted:
        json['ignored_post_placeholder'] == true ||
        (json['deleted_post_placeholder'] == true &&
            !json.containsKey('username')),
  );

  final int? replyToPostNumber;
  final int directReplyCount;
  final int totalDescendantCount;
  final NestedPostPlaceholder placeholder;
  final int? avatarColor;
  final bool contentRedacted;
  bool get isRoot => replyToPostNumber == null || replyToPostNumber == 1;
  bool get redacted => contentRedacted;
  bool get hiddenDeleted =>
      placeholder == NestedPostPlaceholder.deleted && redacted;

  @override
  bool operator ==(Object other) =>
      other is NestedPostData &&
      replyToPostNumber == other.replyToPostNumber &&
      directReplyCount == other.directReplyCount &&
      totalDescendantCount == other.totalDescendantCount &&
      placeholder == other.placeholder &&
      avatarColor == other.avatarColor &&
      contentRedacted == other.contentRedacted;

  @override
  int get hashCode => Object.hash(
    replyToPostNumber,
    directReplyCount,
    totalDescendantCount,
    placeholder,
    avatarColor,
    contentRedacted,
  );

  static int? _avatarColor(Object? value) {
    if (value is! String || !RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    return 0xff000000 | int.parse(value.replaceFirst('#', ''), radix: 16);
  }
}

final class NestedReplyNode {
  NestedReplyNode({
    required this.postId,
    required this.postNumber,
    required this.data,
    Iterable<NestedReplyNode> children = const [],
  }) : children = List.unmodifiable(children);

  final int postId;
  final int postNumber;
  final NestedPostData data;
  final List<NestedReplyNode> children;

  NestedReplyNode withChildren(Iterable<NestedReplyNode> value) =>
      NestedReplyNode(
        postId: postId,
        postNumber: postNumber,
        data: data,
        children: value,
      );
}

final class NestedPostPayload {
  const NestedPostPayload({required this.post, required this.data});
  final Post post;
  final NestedPostData data;
  bool get redacted => data.redacted;
}

final class NestedRootPage {
  NestedRootPage({
    required Iterable<NestedReplyNode> roots,
    required Iterable<NestedPostPayload> posts,
    required this.page,
    required this.hasMore,
    this.topicMetadata,
    this.op,
    this.requestedSort,
    this.effectiveSort,
    this.messageBusLastId,
    Iterable<int> pinnedPostIds = const [],
    this.recommendations,
  }) : roots = List.unmodifiable(roots),
       posts = List.unmodifiable(posts),
       pinnedPostIds = List.unmodifiable(pinnedPostIds);

  final List<NestedReplyNode> roots;
  final List<NestedPostPayload> posts;
  final int page;
  final bool hasMore;
  final Map<String, dynamic>? topicMetadata;
  final NestedReplyNode? op;
  final NestedRepliesSort? requestedSort;
  final NestedRepliesSort? effectiveSort;
  final int? messageBusLastId;
  final List<int> pinnedPostIds;
  final Map<String, dynamic>? recommendations;
}

final class NestedChildrenPage {
  NestedChildrenPage({
    required Iterable<NestedReplyNode> children,
    required Iterable<NestedPostPayload> posts,
    required this.page,
    required this.hasMore,
  }) : children = List.unmodifiable(children),
       posts = List.unmodifiable(posts);

  final List<NestedReplyNode> children;
  final List<NestedPostPayload> posts;
  final int page;
  final bool hasMore;
}

final class NestedContextPage {
  NestedContextPage({
    required this.topicMetadata,
    required this.op,
    required this.target,
    required Iterable<NestedReplyNode> ancestors,
    required Map<int, List<NestedReplyNode>> siblings,
    required Iterable<NestedPostPayload> posts,
    required this.ancestorsTruncated,
    required this.effectiveSort,
    this.messageBusLastId,
    this.recommendations,
  }) : ancestors = List.unmodifiable(ancestors),
       siblings = Map.unmodifiable({
         for (final entry in siblings.entries)
           entry.key: List<NestedReplyNode>.unmodifiable(entry.value),
       }),
       posts = List.unmodifiable(posts);

  final Map<String, dynamic> topicMetadata;
  final NestedReplyNode? op;
  final NestedReplyNode target;
  final List<NestedReplyNode> ancestors;
  final Map<int, List<NestedReplyNode>> siblings;
  final List<NestedPostPayload> posts;
  final bool ancestorsTruncated;
  final NestedRepliesSort effectiveSort;
  final int? messageBusLastId;
  final Map<String, dynamic>? recommendations;
}

final class NestedActivityEntry {
  const NestedActivityEntry({
    required this.synthetic,
    required this.actionCode,
    required this.createdAt,
    this.post,
    this.username,
    this.avatarTemplate,
  });
  final bool synthetic;
  final String actionCode;
  final DateTime? createdAt;
  final Post? post;
  final String? username;
  final String? avatarTemplate;
}

final class NestedActivityPage {
  NestedActivityPage({
    required Iterable<NestedActivityEntry> entries,
    required this.hasMore,
    required this.page,
  }) : entries = List.unmodifiable(entries);
  final List<NestedActivityEntry> entries;
  final bool hasMore;
  final int page;
}

final class NestedBulkResult {
  NestedBulkResult({required Iterable<int> changedTopicIds, this.errors})
    : changedTopicIds = List.unmodifiable(changedTopicIds);
  final List<int> changedTopicIds;
  final Object? errors;
}

final class NestedCategoryConversion {
  const NestedCategoryConversion({
    required this.convertedTopicCount,
    required this.completed,
  });
  final int convertedTopicCount;
  final bool completed;
}

int? nestedPositiveInt(Object? value) =>
    value is int && value > 0 ? value : null;
int nestedCount(Object? value) => value is int && value >= 0 ? value : 0;
Map<String, dynamic> nestedObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
