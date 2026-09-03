import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../plugin_api/plugin_data.dart';
import 'bookmark.dart';
import 'composer_draft.dart';
import 'json.dart';
import 'post_flag.dart';
import 'topic.dart';
import 'user_status.dart';

@immutable
class PostNotice {
  const PostNotice({required this.type, this.raw, this.cooked});

  static PostNotice? fromJson(Object? value) {
    final json = jsonObject(value);
    final type = jsonText(json['type']);
    if (type == null) return null;
    return PostNotice(
      type: type,
      raw: jsonText(json['raw']),
      cooked: jsonText(json['cooked']),
    );
  }

  final String type;
  final String? raw;
  final String? cooked;

  @override
  bool operator ==(Object other) =>
      other is PostNotice &&
      other.type == type &&
      other.raw == raw &&
      other.cooked == cooked;

  @override
  int get hashCode => Object.hash(type, raw, cooked);
}

@immutable
class Post with Storable<Post> {
  const Post({
    required this.id,
    required this.postNumber,
    required this.username,
    required this.cooked,
    this.userId,
    this.name,
    this.avatarUrl,
    this.userStatus,
    this.mentionedUserStatuses = const {},
    this.createdAt,
    this.updatedAt,
    this.userTitle,
    this.replyCount = 0,
    this.isStaff = false,
    this.version = 1,
    this.canViewEditHistory = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canRecover = false,
    this.canPermanentlyDelete = false,
    this.wiki = false,
    this.canWiki = false,
    this.locked = false,
    this.notice,
    this.hidden = false,
    this.deletedAt,
    this.userDeleted = false,
    this.postType = regularPostType,
    this.actionCode,
    this.actionCodeWho,
    this.likeCount = 0,
    this.liked = false,
    this.canLike = false,
    this.canUnlike = false,
    this.linkCounts = const [],
    this.inboundLinks = const [],
    this.postActions = const [],
    this.raw,
    this.isLocalized = false,
    this.bookmark,
    this.plugins = PluginData.none,
  });

  static const int regularPostType = 1;
  static const int moderatorPostType = 2;
  static const int smallActionPostType = 3;
  static const int whisperPostType = 4;

  static const int likeActionId = 2;

  static const int maximumLinkCounts = 100;

  factory Post.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final like = _likeSummary(json['actions_summary']);
    final linkCountJson = jsonObjects(
      json['link_counts'],
    ).take(maximumLinkCounts).toList(growable: false);
    return Post(
      id: jsonInt(json['id']),
      postNumber: jsonInt(json['post_number']),
      username: jsonString(json['username']),
      userId: jsonIntOrNull(json['user_id']),
      name: jsonText(json['name']),
      cooked: jsonString(json['cooked']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      userStatus: UserStatus.fromJson(json['user_status']),
      mentionedUserStatuses: userStatusesByUsername(json['mentioned_users']),
      createdAt: jsonDate(json['created_at']),
      updatedAt: jsonDate(json['updated_at']),
      userTitle: jsonText(json['user_title']),
      replyCount: jsonInt(json['reply_count']),
      isStaff: json['admin'] == true || json['moderator'] == true,
      // The guardian-filtered version does not expose hidden revisions.
      version: switch (jsonIntOrNull(json['version'])) {
        final version? when version > 0 => version,
        _ => 1,
      },
      canViewEditHistory: json['can_view_edit_history'] == true,
      // This guardian result already includes ownership, timing, and topic state.
      canEdit: json['can_edit'] == true,
      canDelete: json['can_delete'] == true,
      canRecover: json['can_recover'] == true,
      canPermanentlyDelete: json['can_permanently_delete'] == true,
      wiki: json['wiki'] == true,
      canWiki: json['can_wiki'] == true,
      locked: json['locked'] == true,
      notice: PostNotice.fromJson(json['notice']),
      hidden: json['hidden'] == true,
      deletedAt: jsonDate(json['deleted_at']),
      userDeleted: json['user_deleted'] == true,
      postType: json['post_type'] == null
          ? regularPostType
          : jsonInt(json['post_type']),
      actionCode: jsonText(json['action_code']),
      actionCodeWho: jsonText(json['action_code_who']),
      likeCount: like.count,
      liked: like.acted,
      canLike: like.canAct,
      canUnlike: like.canUndo,
      linkCounts: List.unmodifiable([
        for (final link in linkCountJson) ?PostLinkCount.fromJson(link),
      ]),
      inboundLinks: List.unmodifiable([
        for (final link in linkCountJson) ?PostInboundLink.fromJson(link),
      ]),
      postActions: _postActionSummaries(json['actions_summary']),
      raw: jsonText(json['raw']),
      isLocalized: json['is_localized'] == true,
      bookmark: Bookmark.fromPostJson(json),
      plugins: extensions.readPost(json, siteUrl),
    );
  }

  static ({int count, bool acted, bool canAct, bool canUndo}) _likeSummary(
    Object? summaries,
  ) {
    for (final entry in jsonObjects(summaries)) {
      if (jsonInt(entry['id']) != likeActionId) continue;
      return (
        count: jsonInt(entry['count']),
        acted: entry['acted'] == true,
        canAct: entry['can_act'] == true,
        canUndo: entry['can_undo'] == true,
      );
    }
    return (count: 0, acted: false, canAct: false, canUndo: false);
  }

  static List<PostActionSummary> _postActionSummaries(Object? summaries) =>
      List.unmodifiable([
        for (final entry in jsonObjects(summaries))
          if (jsonInt(entry['id']) case final id
              when id > 0 && id != likeActionId)
            PostActionSummary.fromJson(entry),
      ]);

  final int id;
  final int postNumber;
  final String username;
  final int? userId;
  final String? name;

  final String cooked;

  final String? avatarUrl;
  final UserStatus? userStatus;

  final Map<String, UserStatusReference> mentionedUserStatuses;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? userTitle;
  final int replyCount;
  final bool isStaff;

  final int version;
  final bool canViewEditHistory;

  int get editCount => version > 1 ? version - 1 : 0;

  final bool canEdit;

  final bool canDelete;
  final bool canRecover;
  final bool canPermanentlyDelete;
  final bool wiki;
  final bool canWiki;
  final bool locked;
  final PostNotice? notice;

  final bool hidden;

  final DateTime? deletedAt;

  final bool userDeleted;

  bool get isDeleted => deletedAt != null || userDeleted;

  final int postType;

  final String? actionCode;

  final String? actionCodeWho;

  final int likeCount;

  final bool liked;

  final bool canLike;
  final bool canUnlike;

  final List<PostLinkCount> linkCounts;

  final List<PostInboundLink> inboundLinks;

  final List<PostActionSummary> postActions;

  PostActionSummary? actionSummary(int typeId) {
    for (final summary in postActions) {
      if (summary.id == typeId) return summary;
    }
    return null;
  }

  bool canFlagWith(int typeId) => actionSummary(typeId)?.canAct == true;

  List<PostActionSummary> get actedFlagSummaries =>
      List.unmodifiable(postActions.where((summary) => summary.acted));

  bool get canToggleLike => liked ? canUnlike : canLike;

  final String? raw;

  final bool isLocalized;

  final Bookmark? bookmark;

  final PluginData plugins;

  bool get isSmallAction => postType == smallActionPostType;

  bool get isModeratorAction => postType == moderatorPostType;

  bool get isWhisper => postType == whisperPostType;

  String get displayName => name ?? username;

  @override
  Object get storeId => id;

  @override
  Post merge(Post incoming) {
    final merged = incoming.raw == null && raw != null
        ? incoming.withRaw(raw!)
        : incoming;
    return this == merged ? this : merged;
  }

  Post withRaw(String raw) => copyWith(raw: raw);

  Post withLike(bool liked) => copyWith(
    liked: liked,
    likeCount: liked ? likeCount + 1 : (likeCount > 0 ? likeCount - 1 : 0),
    canLike: !liked,
    canUnlike: liked,
  );

  Post withLikesOf(Post other) => copyWith(
    likeCount: other.likeCount,
    liked: other.liked,
    canLike: other.canLike,
    canUnlike: other.canUnlike,
  );

  Post withPostActionsOf(Post other) =>
      copyWith(postActions: other.postActions);

  Post withPlugins(PluginData next) => copyWith(plugins: next);

  Post withPluginsOf(Post other) => copyWith(plugins: other.plugins);

  Post withBookmark(Bookmark? next) =>
      copyWith(bookmark: next, clearBookmark: next == null);

  Post withBookmarkOf(Post other) => withBookmark(other.bookmark);

  Post copyWith({
    String? raw,
    bool? isLocalized,
    int? likeCount,
    bool? liked,
    bool? canLike,
    bool? canUnlike,
    List<PostInboundLink>? inboundLinks,
    bool? hidden,
    bool? wiki,
    bool? locked,
    PostNotice? notice,
    bool clearNotice = false,
    List<PostActionSummary>? postActions,
    Bookmark? bookmark,
    bool clearBookmark = false,
    PluginData? plugins,
  }) => Post(
    id: id,
    postNumber: postNumber,
    username: username,
    userId: userId,
    cooked: cooked,
    name: name,
    avatarUrl: avatarUrl,
    userStatus: userStatus,
    mentionedUserStatuses: mentionedUserStatuses,
    createdAt: createdAt,
    updatedAt: updatedAt,
    userTitle: userTitle,
    replyCount: replyCount,
    isStaff: isStaff,
    version: version,
    canViewEditHistory: canViewEditHistory,
    canEdit: canEdit,
    canDelete: canDelete,
    canRecover: canRecover,
    canPermanentlyDelete: canPermanentlyDelete,
    wiki: wiki ?? this.wiki,
    canWiki: canWiki,
    locked: locked ?? this.locked,
    notice: clearNotice ? null : (notice ?? this.notice),
    hidden: hidden ?? this.hidden,
    deletedAt: deletedAt,
    userDeleted: userDeleted,
    postType: postType,
    actionCode: actionCode,
    actionCodeWho: actionCodeWho,
    likeCount: likeCount ?? this.likeCount,
    liked: liked ?? this.liked,
    canLike: canLike ?? this.canLike,
    canUnlike: canUnlike ?? this.canUnlike,
    linkCounts: linkCounts,
    inboundLinks: inboundLinks == null
        ? this.inboundLinks
        : List.unmodifiable(inboundLinks),
    postActions: postActions == null
        ? this.postActions
        : List.unmodifiable(postActions),
    raw: raw ?? this.raw,
    isLocalized: isLocalized ?? this.isLocalized,
    bookmark: clearBookmark ? null : (bookmark ?? this.bookmark),
    plugins: plugins ?? this.plugins,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Post &&
          other.id == id &&
          other.postNumber == postNumber &&
          other.username == username &&
          other.userId == userId &&
          other.name == name &&
          other.cooked == cooked &&
          other.avatarUrl == avatarUrl &&
          other.userStatus == userStatus &&
          mapEquals(other.mentionedUserStatuses, mentionedUserStatuses) &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.userTitle == userTitle &&
          other.replyCount == replyCount &&
          other.isStaff == isStaff &&
          other.version == version &&
          other.canViewEditHistory == canViewEditHistory &&
          other.canEdit == canEdit &&
          other.canDelete == canDelete &&
          other.canRecover == canRecover &&
          other.canPermanentlyDelete == canPermanentlyDelete &&
          other.wiki == wiki &&
          other.canWiki == canWiki &&
          other.locked == locked &&
          other.notice == notice &&
          other.hidden == hidden &&
          other.deletedAt == deletedAt &&
          other.userDeleted == userDeleted &&
          other.postType == postType &&
          other.actionCode == actionCode &&
          other.actionCodeWho == actionCodeWho &&
          other.likeCount == likeCount &&
          other.liked == liked &&
          other.canLike == canLike &&
          other.canUnlike == canUnlike &&
          listEquals(other.linkCounts, linkCounts) &&
          listEquals(other.inboundLinks, inboundLinks) &&
          listEquals(other.postActions, postActions) &&
          other.raw == raw &&
          other.isLocalized == isLocalized &&
          other.bookmark == bookmark &&
          other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    id,
    postNumber,
    username,
    userId,
    name,
    cooked,
    avatarUrl,
    userStatus,
    Object.hashAllUnordered(mentionedUserStatuses.entries),
    createdAt,
    updatedAt,
    userTitle,
    replyCount,
    isStaff,
    version,
    canViewEditHistory,
    canEdit,
    canDelete,
    canRecover,
    canPermanentlyDelete,
    wiki,
    canWiki,
    locked,
    notice,
    hidden,
    deletedAt,
    userDeleted,
    postType,
    actionCode,
    actionCodeWho,
    likeCount,
    liked,
    canLike,
    canUnlike,
    Object.hashAll(linkCounts),
    Object.hashAll(inboundLinks),
    Object.hashAll(postActions),
    raw,
    isLocalized,
    bookmark,
    plugins,
  ]);
}

@immutable
class PostLinkCount {
  const PostLinkCount({
    required this.url,
    required this.clicks,
    this.internal = false,
  });

  static PostLinkCount? fromJson(Map<String, dynamic> json) {
    final url = jsonText(json['url']);
    final clicks = jsonInt(json['clicks']);
    if (url == null || clicks < 1) return null;
    return PostLinkCount(
      url: url,
      clicks: clicks,
      internal: json['internal'] == true,
    );
  }

  final String url;
  final int clicks;
  final bool internal;

  @override
  bool operator ==(Object other) =>
      other is PostLinkCount &&
      other.url == url &&
      other.clicks == clicks &&
      other.internal == internal;

  @override
  int get hashCode => Object.hash(url, clicks, internal);
}

@immutable
class PostInboundLink {
  const PostInboundLink({
    required this.url,
    required this.title,
    this.clicks = 0,
  });

  static PostInboundLink? fromJson(Map<String, dynamic> json) {
    if (json['internal'] != true || json['reflection'] != true) return null;
    final url = jsonText(json['url']);
    final title = jsonText(json['title']);
    if (url == null || title == null) return null;
    return PostInboundLink(
      url: url,
      title: title,
      clicks: jsonInt(json['clicks']),
    );
  }

  final String url;
  final String title;
  final int clicks;

  @override
  bool operator ==(Object other) =>
      other is PostInboundLink &&
      other.url == url &&
      other.title == title &&
      other.clicks == clicks;

  @override
  int get hashCode => Object.hash(url, title, clicks);
}

typedef TopicPayload = ({TopicDetail detail, List<Post> posts});

typedef TopicPostsPayload = ({
  List<Post> posts,
  TopicRecommendations? recommendations,
});

enum TopicStatusProperty {
  closed('closed'),
  archived('archived'),
  visible('visible');

  const TopicStatusProperty(this.wireName);

  final String wireName;
}

@immutable
class TopicDetail with Storable<TopicDetail> {
  const TopicDetail({
    required this.id,
    required this.title,
    required this.stream,
    this.messageBusLastId,
    this.gapsBefore = const {},
    this.gapsAfter = const {},
    this.postsCount = 0,
    this.replyCount = 0,
    this.views = 0,
    this.likeCount = 0,
    this.participantCount = 0,
    this.wordCount = 0,
    this.hasSummary = false,
    this.isNestedView = false,
    this.privateMessage = false,
    this.categoryId,
    this.canCreatePost = false,
    this.canEdit = false,
    this.canEditTags = false,
    this.tags = const [],
    this.participants = const [],
    this.links = const [],
    this.notificationLevel = TopicNotificationLevel.normal,
    this.pinned = false,
    this.unpinned = false,
    this.pinnedGlobally = false,
    this.closed = false,
    this.archived = false,
    this.visible = true,
    this.deletedAt,
    this.canCloseTopic = false,
    this.canArchiveTopic = false,
    this.canToggleTopicVisibility = false,
    this.canDeleteTopic = false,
    this.canRecoverTopic = false,
    this.canPermanentlyDelete = false,
    this.canFlagTopic = false,
    this.canReplyAsNewTopic = false,
    this.canEditStaffNotes = false,
    this.canMovePosts = false,
    this.canSplitMergeTopic = false,
    this.topicActions = const [],
    this.draft,
    this.draftSequence = 0,
    this.bookmarks = const [],
    this.recommendations,
    this.plugins = PluginData.none,
  });

  static const int maximumInitialPosts = 20;

  static const int maximumMapParticipants = 100;
  static const int maximumMapLinks = 100;

  static TopicPayload parse(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
    TopicRecommendationSourceDecoder recommendationSources =
        const EmptyTopicRecommendationSourceDecoder(),
  }) {
    final postStream = jsonObject(json['post_stream']);
    final gaps = jsonObject(postStream['gaps']);
    final details = jsonObject(json['details']);
    return (
      detail: TopicDetail(
        id: jsonInt(json['id']),
        title: jsonTitle(json['title'], json['fancy_title']),
        messageBusLastId: jsonIntOrNull(json['message_bus_last_id']),
        stream: List.unmodifiable(
          jsonArray(postStream['stream']).map(jsonIntOrNull).whereType<int>(),
        ),
        gapsBefore: _parsePostGaps(gaps['before']),
        gapsAfter: _parsePostGaps(gaps['after']),
        postsCount: jsonInt(json['posts_count']),
        replyCount: jsonInt(json['reply_count']),
        views: jsonInt(json['views']),
        likeCount: jsonInt(json['like_count']),
        participantCount: jsonInt(json['participant_count']),
        wordCount: jsonInt(json['word_count']),
        hasSummary: json['has_summary'] == true,
        isNestedView: json['is_nested_view'] == true,
        privateMessage: json['archetype'] == 'private_message',
        categoryId: json['category_id'] == null
            ? null
            : jsonInt(json['category_id']),
        // Do not reapply topic state over the guardian's moderator-aware answer.
        canCreatePost: details['can_create_post'] == true,
        canEdit: details['can_edit'] == true,
        // Topic editors may edit tags even when the narrower flag is absent.
        canEditTags:
            details['can_edit'] == true || details['can_edit_tags'] == true,
        tags: List.unmodifiable(
          jsonArray(json['tags']).map(TopicTag.parse).whereType<TopicTag>(),
        ),
        participants: List.unmodifiable([
          for (final participant in jsonObjects(
            details['participants'],
          ).take(maximumMapParticipants))
            ?TopicParticipant.fromJson(participant, siteUrl),
        ]),
        links: List.unmodifiable([
          for (final link in jsonObjects(
            details['links'],
          ).take(maximumMapLinks))
            ?TopicMapLink.fromJson(link),
        ]),
        notificationLevel: TopicNotificationLevel.fromJson(
          details['notification_level'],
        ),
        pinned: json['pinned'] == true,
        unpinned: json['unpinned'] == true,
        pinnedGlobally: json['pinned_globally'] == true,
        closed: json['closed'] == true,
        archived: json['archived'] == true,
        visible: json['visible'] != false,
        deletedAt: jsonDate(json['deleted_at']),
        canCloseTopic: details['can_close_topic'] == true,
        canArchiveTopic: details['can_archive_topic'] == true,
        canToggleTopicVisibility:
            details['can_toggle_topic_visibility'] == true,
        canDeleteTopic: details['can_delete'] == true,
        canRecoverTopic: details['can_recover'] == true,
        canPermanentlyDelete: details['can_permanently_delete'] == true,
        canFlagTopic: details['can_flag_topic'] == true,
        canReplyAsNewTopic: details['can_reply_as_new_topic'] == true,
        canEditStaffNotes: details['can_edit_staff_notes'] == true,
        canMovePosts: details['can_move_posts'] == true,
        canSplitMergeTopic: details['can_split_merge_topic'] == true,
        topicActions: List.unmodifiable([
          for (final action in jsonObjects(json['actions_summary']))
            if (jsonInt(action['id']) > 0) PostActionSummary.fromJson(action),
        ]),
        draft: ComposerDraft.decode(json['draft']),
        draftSequence: jsonInt(json['draft_sequence']),
        bookmarks: List.unmodifiable([
          for (final bookmark in jsonObjects(json['bookmarks']))
            Bookmark.fromJson(bookmark),
        ]),
        recommendations: TopicRecommendations.fromJson(
          json,
          siteUrl,
          extensions: extensions,
          recommendationSources: recommendationSources,
        ),
        plugins: extensions.readTopic(json, siteUrl),
      ),
      posts: List.unmodifiable([
        for (final post in jsonObjects(
          postStream['posts'],
        ).take(maximumInitialPosts))
          Post.fromJson(post, siteUrl, extensions: extensions),
      ]),
    );
  }

  final int id;
  final String title;
  final int? messageBusLastId;

  final List<int> stream;

  final Map<int, List<int>> gapsBefore;
  final Map<int, List<int>> gapsAfter;

  final int postsCount;
  final int replyCount;
  final int views;
  final int likeCount;
  final int participantCount;
  final int wordCount;
  final bool hasSummary;
  final bool isNestedView;
  final bool privateMessage;
  final int? categoryId;

  final bool canCreatePost;
  final bool canEdit;
  final bool canEditTags;
  final List<TopicTag> tags;

  final List<TopicParticipant> participants;
  final List<TopicMapLink> links;

  final TopicNotificationLevel notificationLevel;

  final bool pinned;
  final bool unpinned;
  final bool pinnedGlobally;

  bool get hasPinPreference => pinned || unpinned;

  TopicDetail withPinPreference(bool nextPinned) =>
      copyWith(pinned: nextPinned, unpinned: !nextPinned);

  final bool closed;

  final bool archived;

  final bool visible;
  final DateTime? deletedAt;
  final bool canCloseTopic;
  final bool canArchiveTopic;
  final bool canToggleTopicVisibility;
  final bool canDeleteTopic;
  final bool canRecoverTopic;
  final bool canPermanentlyDelete;
  final bool canFlagTopic;
  final bool canReplyAsNewTopic;
  final bool canEditStaffNotes;
  final bool canMovePosts;
  final bool canSplitMergeTopic;
  final List<PostActionSummary> topicActions;

  bool get canSelectPosts => canSplitMergeTopic || canMovePosts;

  bool canFlagWith(int typeId) =>
      canFlagTopic &&
      topicActions.any((action) => action.id == typeId && action.canAct);

  TopicDetail withTopicFlag(int typeId) => copyWith(
    topicActions: [
      for (final action in topicActions)
        PostActionSummary(
          id: action.id,
          count: action.count + (action.id == typeId ? 1 : 0),
          acted: action.id == typeId || action.acted,
          canAct: false,
          canUndo: action.id == typeId || action.canUndo,
        ),
    ],
  );

  bool canChangeStatus(TopicStatusProperty property) => switch (property) {
    TopicStatusProperty.closed => canCloseTopic,
    TopicStatusProperty.archived => canArchiveTopic,
    TopicStatusProperty.visible => canToggleTopicVisibility,
  };

  bool statusValue(TopicStatusProperty property) => switch (property) {
    TopicStatusProperty.closed => closed,
    TopicStatusProperty.archived => archived,
    TopicStatusProperty.visible => visible,
  };

  bool get hasStatusActions =>
      canCloseTopic ||
      canArchiveTopic ||
      canToggleTopicVisibility ||
      canDeleteTopic ||
      canRecoverTopic ||
      canSelectPosts;

  TopicDetail withStatus(TopicStatusProperty property, bool enabled) =>
      copyWith(
        closed: property == TopicStatusProperty.closed ? enabled : null,
        archived: property == TopicStatusProperty.archived ? enabled : null,
        visible: property == TopicStatusProperty.visible ? enabled : null,
      );

  TopicDetail withDeletion(bool deleted, DateTime changedAt) => copyWith(
    deletedAt: deleted ? changedAt : null,
    clearDeletedAt: !deleted,
    canDeleteTopic: !deleted,
    canRecoverTopic: deleted,
  );

  final ComposerDraft? draft;

  final int draftSequence;

  final List<Bookmark> bookmarks;

  Bookmark? get topicBookmark => bookmarks
      .where((bookmark) => bookmark.coreTargetType == BookmarkTargetType.topic)
      .firstOrNull;

  List<Bookmark> get postBookmarks => List.unmodifiable(
    bookmarks
        .where((bookmark) => bookmark.coreTargetType == BookmarkTargetType.post)
        .toList()
      ..sort((a, b) => (a.postNumber ?? 0).compareTo(b.postNumber ?? 0)),
  );

  bool get hasBookmarks => bookmarks.isNotEmpty;

  final TopicRecommendations? recommendations;

  final PluginData plugins;

  @override
  Object get storeId => id;

  TopicDetail withPostId(int postId) => stream.contains(postId)
      ? this
      : copyWith(stream: [...stream, postId], postsCount: postsCount + 1);

  TopicDetail withExpandedGap({
    required int anchorPostId,
    required bool before,
    required List<int> consumedIds,
    required List<int> revealedIds,
  }) {
    if (consumedIds.isEmpty) return this;

    final source = before ? gapsBefore : gapsAfter;
    final gap = source[anchorPostId];
    final anchorIndex = stream.indexOf(anchorPostId);
    if (gap == null ||
        anchorIndex < 0 ||
        gap.length < consumedIds.length ||
        !listEquals(gap.sublist(0, consumedIds.length), consumedIds)) {
      return this;
    }

    final consumed = consumedIds.toSet();
    final inserted = <int>{};
    final insert = <int>[
      for (final id in revealedIds)
        if (consumed.contains(id) && !stream.contains(id) && inserted.add(id))
          id,
    ];
    final nextStream = List<int>.of(stream)
      ..insertAll(before ? anchorIndex : anchorIndex + 1, insert);
    final remaining = List<int>.unmodifiable(gap.skip(consumedIds.length));
    final nextBefore = Map<int, List<int>>.of(gapsBefore);
    final nextAfter = Map<int, List<int>>.of(gapsAfter);
    final target = before ? nextBefore : nextAfter;
    target.remove(anchorPostId);
    if (remaining.isNotEmpty) {
      // A trailing gap follows the chunk just revealed. A leading gap remains
      // immediately before its original anchor, which is already after the
      // inserted chunk.
      final nextAnchor = !before && insert.isNotEmpty
          ? insert.last
          : anchorPostId;
      target[nextAnchor] = remaining;
    }

    return copyWith(
      stream: nextStream,
      gapsBefore: nextBefore,
      gapsAfter: nextAfter,
    );
  }

  TopicDetail withoutPostId(int postId) => stream.contains(postId)
      ? copyWith(
          stream: stream.where((id) => id != postId).toList(),
          postsCount: postsCount > 0 ? postsCount - 1 : 0,
        )
      : this;

  TopicDetail withDraft(ComposerDraft? draft, int sequence) => copyWith(
    draft: draft,
    clearDraft: draft == null,
    draftSequence: sequence,
  );

  TopicDetail withRecommendations(TopicRecommendations recommendations) =>
      copyWith(recommendations: recommendations);

  TopicDetail withNotificationLevel(TopicNotificationLevel level) =>
      copyWith(notificationLevel: level);

  TopicDetail withBookmark(Bookmark bookmark) => copyWith(
    bookmarks: [
      for (final held in bookmarks)
        if (held.id != bookmark.id &&
            !(held.bookmarkableId == bookmark.bookmarkableId &&
                held.bookmarkableType == bookmark.bookmarkableType))
          held,
      bookmark,
    ],
  );

  TopicDetail withoutBookmark(int bookmarkId) => copyWith(
    bookmarks: bookmarks
        .where((bookmark) => bookmark.id != bookmarkId)
        .toList(),
  );

  TopicDetail withoutBookmarks() => copyWith(bookmarks: const []);

  TopicDetail withBookmarksOf(TopicDetail other) =>
      copyWith(bookmarks: other.bookmarks);

  TopicDetail withPlugins(PluginData next) => TopicDetail(
    id: id,
    title: title,
    messageBusLastId: messageBusLastId,
    stream: stream,
    gapsBefore: gapsBefore,
    gapsAfter: gapsAfter,
    postsCount: postsCount,
    replyCount: replyCount,
    views: views,
    likeCount: likeCount,
    participantCount: participantCount,
    wordCount: wordCount,
    hasSummary: hasSummary,
    isNestedView: isNestedView,
    privateMessage: privateMessage,
    categoryId: categoryId,
    canCreatePost: canCreatePost,
    canEdit: canEdit,
    canEditTags: canEditTags,
    tags: tags,
    participants: participants,
    links: links,
    notificationLevel: notificationLevel,
    pinned: pinned,
    unpinned: unpinned,
    pinnedGlobally: pinnedGlobally,
    closed: closed,
    archived: archived,
    visible: visible,
    deletedAt: deletedAt,
    canCloseTopic: canCloseTopic,
    canArchiveTopic: canArchiveTopic,
    canToggleTopicVisibility: canToggleTopicVisibility,
    canDeleteTopic: canDeleteTopic,
    canRecoverTopic: canRecoverTopic,
    canPermanentlyDelete: canPermanentlyDelete,
    canFlagTopic: canFlagTopic,
    canReplyAsNewTopic: canReplyAsNewTopic,
    canEditStaffNotes: canEditStaffNotes,
    canMovePosts: canMovePosts,
    canSplitMergeTopic: canSplitMergeTopic,
    topicActions: topicActions,
    draft: draft,
    draftSequence: draftSequence,
    bookmarks: bookmarks,
    recommendations: recommendations,
    plugins: next,
  );

  @override
  TopicDetail merge(TopicDetail incoming) {
    final arrived = incoming.stream.toSet();
    // A locally expanded gap id is absent from the server's filtered stream
    // by design. When a full topic refetch arrives, let it collapse back into
    // the incoming gap rather than mistaking that id for a brand-new reply and
    // appending it at the end of the topic.
    final incomingGapIds = {
      for (final gap in incoming.gapsBefore.values) ...gap,
      for (final gap in incoming.gapsAfter.values) ...gap,
    };
    final missing = stream
        .where((id) => !arrived.contains(id) && !incomingGapIds.contains(id))
        .toList();
    var merged = missing.isEmpty
        ? incoming
        : incoming.copyWith(
            stream: [...incoming.stream, ...missing],
            postsCount: incoming.postsCount + missing.length,
          );
    if (merged.recommendations == null && recommendations != null) {
      merged = merged.copyWith(recommendations: recommendations);
    }
    return this == merged ? this : merged;
  }

  TopicDetail copyWith({
    String? title,
    List<int>? stream,
    Map<int, List<int>>? gapsBefore,
    Map<int, List<int>>? gapsAfter,
    int? postsCount,
    ComposerDraft? draft,
    bool clearDraft = false,
    int? draftSequence,
    List<Bookmark>? bookmarks,
    bool? archived,
    bool? closed,
    bool? visible,
    bool? privateMessage,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    int? categoryId,
    bool clearCategory = false,
    List<TopicTag>? tags,
    bool? canEdit,
    bool? canEditTags,
    bool? canDeleteTopic,
    bool? canRecoverTopic,
    TopicNotificationLevel? notificationLevel,
    bool? pinned,
    bool? unpinned,
    List<PostActionSummary>? topicActions,
    TopicRecommendations? recommendations,
    PluginData? plugins,
  }) => TopicDetail(
    id: id,
    title: title ?? this.title,
    messageBusLastId: messageBusLastId,
    stream: stream == null ? this.stream : List.unmodifiable(stream),
    gapsBefore: gapsBefore == null
        ? this.gapsBefore
        : _freezePostGaps(gapsBefore),
    gapsAfter: gapsAfter == null ? this.gapsAfter : _freezePostGaps(gapsAfter),
    postsCount: postsCount ?? this.postsCount,
    replyCount: replyCount,
    views: views,
    likeCount: likeCount,
    participantCount: participantCount,
    wordCount: wordCount,
    hasSummary: hasSummary,
    isNestedView: isNestedView,
    privateMessage: privateMessage ?? this.privateMessage,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    canCreatePost: canCreatePost,
    canEdit: canEdit ?? this.canEdit,
    canEditTags: canEditTags ?? this.canEditTags,
    tags: tags == null ? this.tags : List.unmodifiable(tags),
    participants: participants,
    links: links,
    notificationLevel: notificationLevel ?? this.notificationLevel,
    pinned: pinned ?? this.pinned,
    unpinned: unpinned ?? this.unpinned,
    pinnedGlobally: pinnedGlobally,
    closed: closed ?? this.closed,
    archived: archived ?? this.archived,
    visible: visible ?? this.visible,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    canCloseTopic: canCloseTopic,
    canArchiveTopic: canArchiveTopic,
    canToggleTopicVisibility: canToggleTopicVisibility,
    canDeleteTopic: canDeleteTopic ?? this.canDeleteTopic,
    canRecoverTopic: canRecoverTopic ?? this.canRecoverTopic,
    canPermanentlyDelete: canPermanentlyDelete,
    canFlagTopic: canFlagTopic,
    canReplyAsNewTopic: canReplyAsNewTopic,
    canEditStaffNotes: canEditStaffNotes,
    canMovePosts: canMovePosts,
    canSplitMergeTopic: canSplitMergeTopic,
    topicActions: topicActions == null
        ? this.topicActions
        : List.unmodifiable(topicActions),
    draft: clearDraft ? null : (draft ?? this.draft),
    draftSequence: draftSequence ?? this.draftSequence,
    bookmarks: bookmarks == null
        ? this.bookmarks
        : List.unmodifiable(bookmarks),
    recommendations: recommendations ?? this.recommendations,
    plugins: plugins ?? this.plugins,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicDetail &&
          other.id == id &&
          other.title == title &&
          other.messageBusLastId == messageBusLastId &&
          listEquals(other.stream, stream) &&
          _postGapsEqual(other.gapsBefore, gapsBefore) &&
          _postGapsEqual(other.gapsAfter, gapsAfter) &&
          other.postsCount == postsCount &&
          other.replyCount == replyCount &&
          other.views == views &&
          other.likeCount == likeCount &&
          other.participantCount == participantCount &&
          other.wordCount == wordCount &&
          other.hasSummary == hasSummary &&
          other.isNestedView == isNestedView &&
          other.privateMessage == privateMessage &&
          other.categoryId == categoryId &&
          other.canCreatePost == canCreatePost &&
          other.canEdit == canEdit &&
          other.canEditTags == canEditTags &&
          listEquals(other.tags, tags) &&
          listEquals(other.participants, participants) &&
          listEquals(other.links, links) &&
          other.notificationLevel == notificationLevel &&
          other.pinned == pinned &&
          other.unpinned == unpinned &&
          other.pinnedGlobally == pinnedGlobally &&
          other.closed == closed &&
          other.archived == archived &&
          other.visible == visible &&
          other.deletedAt == deletedAt &&
          other.canCloseTopic == canCloseTopic &&
          other.canArchiveTopic == canArchiveTopic &&
          other.canToggleTopicVisibility == canToggleTopicVisibility &&
          other.canDeleteTopic == canDeleteTopic &&
          other.canRecoverTopic == canRecoverTopic &&
          other.canPermanentlyDelete == canPermanentlyDelete &&
          other.canFlagTopic == canFlagTopic &&
          other.canReplyAsNewTopic == canReplyAsNewTopic &&
          other.canEditStaffNotes == canEditStaffNotes &&
          other.canMovePosts == canMovePosts &&
          other.canSplitMergeTopic == canSplitMergeTopic &&
          listEquals(other.topicActions, topicActions) &&
          other.draft == draft &&
          other.draftSequence == draftSequence &&
          listEquals(other.bookmarks, bookmarks) &&
          other.recommendations == recommendations &&
          other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    messageBusLastId,
    Object.hashAll(stream),
    _postGapsHash(gapsBefore),
    _postGapsHash(gapsAfter),
    postsCount,
    replyCount,
    views,
    likeCount,
    participantCount,
    wordCount,
    hasSummary,
    isNestedView,
    privateMessage,
    categoryId,
    canCreatePost,
    canEdit,
    canEditTags,
    Object.hashAll(tags),
    Object.hashAll(participants),
    Object.hashAll(links),
    notificationLevel,
    pinned,
    unpinned,
    pinnedGlobally,
    closed,
    archived,
    visible,
    deletedAt,
    canCloseTopic,
    canArchiveTopic,
    canToggleTopicVisibility,
    canDeleteTopic,
    canRecoverTopic,
    canPermanentlyDelete,
    canFlagTopic,
    canReplyAsNewTopic,
    canEditStaffNotes,
    canMovePosts,
    canSplitMergeTopic,
    Object.hashAll(topicActions),
    draft,
    draftSequence,
    Object.hashAll(bookmarks),
    recommendations,
    plugins,
  ]);

  static Map<int, List<int>> _parsePostGaps(Object? value) {
    final parsed = <int, List<int>>{};
    for (final entry in jsonObject(value).entries) {
      final anchor = int.tryParse(entry.key);
      if (anchor == null || anchor <= 0) continue;
      final ids = <int>[];
      final seen = <int>{};
      for (final value in jsonArray(entry.value)) {
        final id = jsonIntOrNull(value);
        if (id != null && id > 0 && seen.add(id)) ids.add(id);
      }
      if (ids.isNotEmpty) parsed[anchor] = List.unmodifiable(ids);
    }
    return Map.unmodifiable(parsed);
  }

  static Map<int, List<int>> _freezePostGaps(Map<int, List<int>> gaps) =>
      Map.unmodifiable({
        for (final entry in gaps.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      });

  static bool _postGapsEqual(
    Map<int, List<int>> left,
    Map<int, List<int>> right,
  ) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!listEquals(entry.value, right[entry.key])) return false;
    }
    return true;
  }

  static int _postGapsHash(Map<int, List<int>> gaps) => Object.hashAllUnordered(
    gaps.entries.map(
      (entry) => Object.hash(entry.key, Object.hashAll(entry.value)),
    ),
  );
}
