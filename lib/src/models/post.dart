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

/// One post in a topic.
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
    this.bookmark,
    this.plugins = PluginData.none,
  });

  /// `post_type` values Discourse uses. Regular posts are 1; the moderator
  /// notices a topic collects — closed, pinned, invited — are 3; and private
  /// whispers are 4.
  static const int regularPostType = 1;
  static const int moderatorPostType = 2;
  static const int smallActionPostType = 3;
  static const int whisperPostType = 4;

  /// The like's row in `actions_summary`, and the `post_action_type_id` the
  /// like routes take. It is `PostActionType::LIKE_POST_ACTION_ID` server side
  /// and 2 everywhere, flags being the other numbers in that table.
  static const int likeActionId = 2;

  /// A defensive ceiling for click-count records retained with one post.
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
      // Server-rendered HTML. Discourse does the markdown, oneboxing, emoji
      // and mention rendering, which is far too much to redo client side.
      cooked: jsonString(json['cooked']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      userStatus: UserStatus.fromJson(json['user_status']),
      mentionedUserStatuses: userStatusesByUsername(json['mentioned_users']),
      createdAt: jsonDate(json['created_at']),
      updatedAt: jsonDate(json['updated_at']),
      userTitle: jsonText(json['user_title']),
      replyCount: jsonInt(json['reply_count']),
      isStaff: json['admin'] == true || json['moderator'] == true,
      // Core shows `version - 1` beside the pencil. The version is already
      // guardian-filtered: non-staff receive the public version, so hidden
      // revisions never leak through this count.
      version: switch (jsonIntOrNull(json['version'])) {
        final version? when version > 0 => version,
        _ => 1,
      },
      canViewEditHistory: json['can_view_edit_history'] == true,
      // The whole permission question, answered by the site's guardian: it has
      // already weighed ownership, staff, trust level, the edit time window and
      // whether the topic is closed or archived. Absent when read signed out,
      // which is also the right answer.
      canEdit: json['can_edit'] == true,
      canDelete: json['can_delete'] == true,
      canRecover: json['can_recover'] == true,
      canPermanentlyDelete: json['can_permanently_delete'] == true,
      wiki: json['wiki'] == true,
      canWiki: json['can_wiki'] == true,
      locked: json['locked'] == true,
      notice: PostNotice.fromJson(json['notice']),
      hidden: json['hidden'] == true,
      // Only staff are ever shown a deleted post; for everyone else Discourse
      // leaves it out of the stream entirely.
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
      // Only present when asked for. Reading needs the cooked HTML; writing
      // needs this, because it is the thing that was actually typed.
      raw: jsonText(json['raw']),
      bookmark: Bookmark.fromPostJson(json),
      // Whatever the site's optional features had to say about this post, which
      // on a site running plain core is nothing at all.
      plugins: extensions.readPost(json, siteUrl),
    );
  }

  /// The like's row of `actions_summary`, which is where Discourse reports
  /// every post action — likes alongside the flags, each under its type id.
  ///
  /// Absent keys are the ordinary case rather than a malformed payload:
  /// `count` is dropped when it is zero, and `can_act`, `acted` and `can_undo`
  /// are only written when they are true. The whole row is left out when none
  /// of them apply, which is what a post nobody has liked and this reader may
  /// not like — their own, or anyone's while signed out — looks like.
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

  /// HTML as the site rendered it.
  final String cooked;

  final String? avatarUrl;
  final UserStatus? userStatus;

  /// Statuses for the people linked from cooked `@mentions` in this post.
  final Map<String, UserStatusReference> mentionedUserStatuses;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? userTitle;
  final int replyCount;
  final bool isStaff;

  /// The initial post is version one, so every version after it is one edit.
  final int version;
  final bool canViewEditHistory;

  int get editCount => version > 1 ? version - 1 : 0;

  /// Whether this reader may rewrite this post.
  final bool canEdit;

  /// Whether this reader may delete it, and — once it is gone — put it back.
  final bool canDelete;
  final bool canRecover;
  final bool canPermanentlyDelete;
  final bool wiki;
  final bool canWiki;
  final bool locked;
  final PostNotice? notice;

  /// Whether Discourse has temporarily hidden this post after flagging.
  ///
  /// For readers who may not see the original, [cooked] is already the
  /// server-localized placeholder. This bit gates actions such as flagging.
  final bool hidden;

  /// When it was deleted, for the staff who can still see it.
  final DateTime? deletedAt;

  /// Deleted by its own author. Discourse keeps the row for a while before
  /// removing it for good, and shows a placeholder in the meantime.
  final bool userDeleted;

  bool get isDeleted => deletedAt != null || userDeleted;

  final int postType;

  /// What the moderator action was, e.g. `closed.enabled` or `invited_user`.
  /// Only small actions carry one.
  final String? actionCode;

  /// The user or group the action was taken on, for the codes that name one.
  final String? actionCodeWho;

  /// How many people have liked this post, this reader's own like included.
  ///
  /// Anyone they have ignored is already left out — the site subtracts those
  /// before serializing, so the number here is the one to draw.
  final int likeCount;

  /// Whether this reader is one of them.
  final bool liked;

  /// Whether they may add a like, and whether they may take theirs back.
  ///
  /// Two questions rather than one because they are never both true: liking
  /// spends the one and grants the other. Both are false on a post nobody may
  /// act on — your own, or anyone's while signed out — and [canUnlike] is also
  /// false once the site's undo window has run out on a like already given.
  final bool canLike;
  final bool canUnlike;

  /// Click totals for links in this post's cooked body.
  ///
  /// Core's client attaches these to matching anchors after cooking, because
  /// the server keeps volatile click totals out of the cooked HTML itself.
  /// Entries without a positive count are omitted at the model boundary.
  final List<PostLinkCount> linkCounts;

  /// Visible topics which link back to this post.
  ///
  /// Core calls these reflected internal `link_counts` and draws them beneath
  /// the post. External links and ordinary outbound links are deliberately
  /// excluded by [PostInboundLink.fromJson], matching the web post-link row.
  final List<PostInboundLink> inboundLinks;

  /// Personalized non-like post actions, which are flag rows in core.
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

  /// Whether tapping the heart would do anything.
  ///
  /// On a site with reactions this is still asked, but as a *permission* rather
  /// than as the like's own state: it is the same `post_can_act?(post, :like)`
  /// the reaction routes check, and it already carries ownership, silencing,
  /// archived topics and the undo window. See `Post.canReact`.
  bool get canToggleLike => liked ? canUnlike : canLike;

  /// The markdown this post was written as, when it was asked for.
  ///
  /// Absent from an ordinary read: the stream carries [cooked] and nothing
  /// needs the source until something wants to compare or edit it.
  final String? raw;

  /// This reader's bookmark on the post, including its reminder metadata.
  final Bookmark? bookmark;

  /// What the site's optional features said about this post, keyed by the type
  /// each of them answers with, through its stable typed key.
  ///
  /// [PluginData.none] on a site running plain core, and on every post of a
  /// site whose installed modules do not claim the payload.
  final PluginData plugins;

  /// Small actions are the "closed this topic" notices in the stream. They
  /// have no body of their own, so they are drawn as a one-line notice rather
  /// than as a post. Optional features can add their own serializer types and
  /// action codes without making those values part of this core model.
  bool get isSmallAction => postType == smallActionPostType;

  bool get isModeratorAction => postType == moderatorPostType;

  /// A private aside visible only to the site's configured whisper groups.
  bool get isWhisper => postType == whisperPostType;

  String get displayName => name ?? username;

  @override
  Object get storeId => id;

  /// A later copy wins, except that markdown already in hand is never given up.
  ///
  /// [raw] is only present when it was asked for, so an ordinary re-read — the
  /// refetch after a reply, say — carries a null that means "not requested"
  /// rather than "no longer has one". Letting that through would send the
  /// composer back to the site for a body it already had.
  @override
  Post merge(Post incoming) {
    final merged = incoming.raw == null && raw != null
        ? incoming.withRaw(raw!)
        : incoming;
    return this == merged ? this : merged;
  }

  Post withRaw(String raw) => copyWith(raw: raw);

  /// The post as it would be with this reader's like added or taken back.
  ///
  /// Drawn before the request is sent, so the heart answers the tap rather than
  /// the network. The permissions are flipped with it — a like just given can
  /// be taken back and not given again — which is the same guess Discourse's
  /// own client makes, and the site's answer overwrites all of it a moment
  /// later either way.
  ///
  /// The count is floored at zero. It is a number the site sent, and unliking a
  /// post whose count arrived stale would otherwise show -1.
  Post withLike(bool liked) => copyWith(
    liked: liked,
    likeCount: liked ? likeCount + 1 : (likeCount > 0 ? likeCount - 1 : 0),
    canLike: !liked,
    canUnlike: liked,
  );

  /// This post, but with [other]'s answer to what this reader did about it.
  ///
  /// For the two places a copy of a post arrives that cannot have known: an
  /// edit, whose payload Discourse serializes without the reader's own post
  /// actions at all, and a like this client is putting back after the site
  /// refused it. Taking either literally would say a post you liked is one you
  /// have not.
  Post withLikesOf(Post other) => copyWith(
    likeCount: other.likeCount,
    liked: other.liked,
    canLike: other.canLike,
    canUnlike: other.canUnlike,
  );

  /// This post, but with [other]'s personalized non-like action state.
  ///
  /// Post edit responses omit the reader's actions, just as they omit their
  /// like. Keeping the held rows prevents an edit from re-offering a flag the
  /// reader already submitted or erasing its confirmation.
  Post withPostActionsOf(Post other) =>
      copyWith(postActions: other.postActions);

  /// The post with one optional feature's answer replaced.
  Post withPlugins(PluginData next) => copyWith(plugins: next);

  /// This post, but with [other]'s answer from the site's optional features.
  ///
  /// The twin of [withLikesOf], for the same three places a copy of a post
  /// arrives that cannot have known what this reader did: a rollback, an edit
  /// response, and the answer to a write. Kept separate from [withLikesOf]
  /// rather than folded into it, so that what that method tests is still what
  /// it tests.
  Post withPluginsOf(Post other) => copyWith(plugins: other.plugins);

  Post withBookmark(Bookmark? next) =>
      copyWith(bookmark: next, clearBookmark: next == null);

  Post withBookmarkOf(Post other) => withBookmark(other.bookmark);

  /// Only the fields anything here has reason to change. Everything else is
  /// the site's to say, and is carried across untouched.
  Post copyWith({
    String? raw,
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
    bookmark,
    plugins,
  ]);
}

/// A positive click total for one link in a post's cooked body.
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

/// One internal topic which links back to a post.
@immutable
class PostInboundLink {
  const PostInboundLink({
    required this.url,
    required this.title,
    this.clicks = 0,
  });

  /// Returns null for outbound, external, untitled, or otherwise unusable
  /// entries. Those are present in the serializer for click tracking, but the
  /// web post-link component does not display them.
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

/// What a topic fetch answers with.
///
/// Two things, kept apart: the topic, and the first chunk of its posts. They
/// are stored separately — the posts under their own ids, so the same post
/// fetched again from anywhere is the same record — and this is the shape that
/// carries them from the parser to whoever does the storing.
typedef TopicPayload = ({TopicDetail detail, List<Post> posts});

/// A page of posts and the more-topics payload attached to the final page.
///
/// Core and installed plugins may each attach a source to the same response.
/// [recommendations] is null before the end rather than an empty value, so a
/// partial refetch cannot erase recommendations already held.
typedef TopicPostsPayload = ({
  List<Post> posts,
  TopicRecommendations? recommendations,
});

/// One status toggle accepted by `PUT /t/{id}/status`.
enum TopicStatusProperty {
  closed('closed'),
  archived('archived'),
  visible('visible');

  const TopicStatusProperty(this.wireName);

  final String wireName;
}

/// A topic, and the order its posts go in.
///
/// Deliberately holds no [Post]. The posts live in the [Store] under their own
/// ids and this holds [stream] — every post id in the topic, fetched or not —
/// which is both the paging cursor and the running order. That is what makes
/// editing a post a one-record write rather than a rebuild of the topic, and
/// what lets a post fetched for one reason be found by another.
@immutable
class TopicDetail with Storable<TopicDetail> {
  const TopicDetail({
    required this.id,
    required this.title,
    required this.stream,
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

  /// The fixed first-window size served by core's `TopicView`.
  ///
  /// The complete post-id stream is retained separately, so bounding eager
  /// post construction here never makes a later post unreachable.
  static const int maximumInitialPosts = 20;

  /// The map presents compact summaries, not an unbounded member directory.
  static const int maximumMapParticipants = 100;
  static const int maximumMapLinks = 100;

  /// Reads a topic payload into the topic and its posts.
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
        // Every post id in the topic, even the ones not fetched yet — this is
        // what makes paging through a long topic possible.
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
        categoryId: json['category_id'] == null
            ? null
            : jsonInt(json['category_id']),
        // The only question worth asking before showing a reply button, and the
        // whole question: the guardian behind it has already folded in closed,
        // archived and the trust levels that are allowed past them. Checking
        // `closed` again here would hide the button from the moderators who can
        // still use it. Absent when read signed out, which is also the right
        // answer — there is no key to post with.
        canCreatePost: details['can_create_post'] == true,
        canEdit: details['can_edit'] == true,
        // Core only emits the narrower capability when the reader cannot edit
        // the whole topic. A topic editor may edit tags too, so the absent
        // specialized flag must not turn their sidebar into a read-only one.
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
        // The topic payload already carries any draft for it, so opening a
        // composer needs no request of its own.
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

  /// Every post id in the topic, in reading order.
  final List<int> stream;

  /// Post ids deliberately left out of [stream], keyed by the visible post
  /// immediately after or before them.
  ///
  /// Core uses these gaps for content this reader is allowed to reveal but
  /// has chosen not to show in the ordinary stream — most commonly posts by
  /// ignored users. Keeping the ids separate is important: ordinary paging
  /// must not fetch them until the reader expands the gap.
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
  final int? categoryId;

  /// Whether this reader may reply here.
  final bool canCreatePost;
  final bool canEdit;
  final bool canEditTags;
  final List<TopicTag> tags;

  /// Frequent posters and outbound links used by the topic map beneath the
  /// first post. Both arrive inside the payload's `details` object.
  final List<TopicParticipant> participants;
  final List<TopicMapLink> links;

  /// How closely this reader follows the topic.
  final TopicNotificationLevel notificationLevel;

  /// This account's choice for a topic the site offers as pinnable.
  ///
  /// Core sends neither flag for an ordinary topic. A topic is eligible for
  /// the footer control only when either `pinned` or `unpinned` is present and
  /// true, matching the web app's `PinnedButton.isHidden` contract.
  final bool pinned;
  final bool unpinned;
  final bool pinnedGlobally;

  bool get hasPinPreference => pinned || unpinned;

  TopicDetail withPinPreference(bool nextPinned) =>
      copyWith(pinned: nextPinned, unpinned: !nextPinned);

  final bool closed;

  /// Archived topics reject poll writes even when their posts remain visible.
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

  /// A reply left unfinished here, wherever it was started.
  final ComposerDraft? draft;

  /// What the next draft save must be sequenced against.
  final int draftSequence;

  /// Every bookmark this reader owns in the topic, including unloaded posts.
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

  /// The lists Discourse places after the final post. Null means this response
  /// was not the final post window and therefore had nothing to say about them.
  final TopicRecommendations? recommendations;

  /// What optional features attached to the full topic serializer.
  final PluginData plugins;

  @override
  Object get storeId => id;

  /// Records a post that did not exist a moment ago.
  ///
  /// The post itself goes to the store; this is only the topic's side of it —
  /// where it sits in the order, and one more on the count. Idempotent, so a
  /// reply that also arrives in a refetch is not counted twice, and an edit,
  /// whose id the stream already holds, does not move the count at all.
  TopicDetail withPostId(int postId) => stream.contains(postId)
      ? this
      : copyWith(stream: [...stream, postId], postsCount: postsCount + 1);

  /// Inserts one fetched chunk from a server-provided post gap.
  ///
  /// [consumedIds] is the prefix that was requested. [revealedIds] is the
  /// subset the site actually returned; a post removed while the request was
  /// in flight is consumed without leaving an unfetchable hole in [stream].
  /// A remainder stays attached to the next visible edge so it can be expanded
  /// again in another bounded request.
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

  /// Drops a post the site no longer serves.
  ///
  /// Only for one that is genuinely gone. A post deleted by staff, or by its
  /// own author, is still in the stream — deleted posts are shown to the people
  /// who can undo it, and hiding them here would take the undo away.
  TopicDetail withoutPostId(int postId) => stream.contains(postId)
      ? copyWith(
          stream: stream.where((id) => id != postId).toList(),
          postsCount: postsCount > 0 ? postsCount - 1 : 0,
        )
      : this;

  /// Records the draft this topic now has, so the cache keeps saying what the
  /// payload would say if it were fetched again.
  ///
  /// Without it, saving a draft and reopening the composer would find nothing:
  /// the local copy is deleted once the site has the text, and the topic in
  /// hand was fetched before the draft existed.
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

  /// The topic with one complete optional-feature snapshot.
  TopicDetail withPlugins(PluginData next) => TopicDetail(
    id: id,
    title: title,
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

  /// A refetched copy wins, except that it may not have caught up.
  ///
  /// A reply made a moment ago can be missing from the stream the site answers
  /// with — it was read before the post landed, or from a replica — and taking
  /// that literally would make the post vanish the instant it appeared. Ids
  /// only held here are kept, at the end, which is where a new post is — and
  /// counted, the way [withPostId] counts what it adds, because the copy's
  /// count was taken before they existed too.
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
