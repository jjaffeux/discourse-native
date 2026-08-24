import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../plugins/plugin_data.dart';
import 'composer_draft.dart';
import 'json.dart';
import 'post_flag.dart';
import 'topic.dart';

/// One post in a topic.
@immutable
class Post with Storable<Post> {
  const Post({
    required this.id,
    required this.postNumber,
    required this.username,
    required this.cooked,
    this.name,
    this.avatarUrl,
    this.createdAt,
    this.userTitle,
    this.replyCount = 0,
    this.isStaff = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canRecover = false,
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
    this.postActions = const [],
    this.raw,
    this.plugins = PluginData.none,
  });

  /// `post_type` values Discourse uses. Regular posts are 1; the moderator
  /// notices a topic collects — closed, pinned, invited — are 3; and private
  /// whispers are 4.
  static const int regularPostType = 1;
  static const int smallActionPostType = 3;
  static const int whisperPostType = 4;

  /// The like's row in `actions_summary`, and the `post_action_type_id` the
  /// like routes take. It is `PostActionType::LIKE_POST_ACTION_ID` server side
  /// and 2 everywhere, flags being the other numbers in that table.
  static const int likeActionId = 2;

  factory Post.fromJson(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final like = _likeSummary(json['actions_summary']);
    return Post(
      id: jsonInt(json['id']),
      postNumber: jsonInt(json['post_number']),
      username: jsonString(json['username']),
      name: jsonText(json['name']),
      // Server-rendered HTML. Discourse does the markdown, oneboxing, emoji
      // and mention rendering, which is far too much to redo client side.
      cooked: jsonString(json['cooked']),
      avatarUrl: resolveAvatarUrl(jsonText(json['avatar_template']), siteUrl),
      createdAt: jsonDate(json['created_at']),
      userTitle: jsonText(json['user_title']),
      replyCount: jsonInt(json['reply_count']),
      isStaff: json['admin'] == true || json['moderator'] == true,
      // The whole permission question, answered by the site's guardian: it has
      // already weighed ownership, staff, trust level, the edit time window and
      // whether the topic is closed or archived. Absent when read signed out,
      // which is also the right answer.
      canEdit: json['can_edit'] == true,
      canDelete: json['can_delete'] == true,
      canRecover: json['can_recover'] == true,
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
      postActions: _postActionSummaries(json['actions_summary']),
      // Only present when asked for. Reading needs the cooked HTML; writing
      // needs this, because it is the thing that was actually typed.
      raw: jsonText(json['raw']),
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
  final String? name;

  /// HTML as the site rendered it.
  final String cooked;

  final String? avatarUrl;
  final DateTime? createdAt;
  final String? userTitle;
  final int replyCount;
  final bool isStaff;

  /// Whether this reader may rewrite this post.
  final bool canEdit;

  /// Whether this reader may delete it, and — once it is gone — put it back.
  final bool canDelete;
  final bool canRecover;

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

  /// Only the fields anything here has reason to change. Everything else is
  /// the site's to say, and is carried across untouched.
  Post copyWith({
    String? raw,
    int? likeCount,
    bool? liked,
    bool? canLike,
    bool? canUnlike,
    bool? hidden,
    List<PostActionSummary>? postActions,
    PluginData? plugins,
  }) => Post(
    id: id,
    postNumber: postNumber,
    username: username,
    cooked: cooked,
    name: name,
    avatarUrl: avatarUrl,
    createdAt: createdAt,
    userTitle: userTitle,
    replyCount: replyCount,
    isStaff: isStaff,
    canEdit: canEdit,
    canDelete: canDelete,
    canRecover: canRecover,
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
    postActions: postActions == null
        ? this.postActions
        : List.unmodifiable(postActions),
    raw: raw ?? this.raw,
    plugins: plugins ?? this.plugins,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Post &&
          other.id == id &&
          other.postNumber == postNumber &&
          other.username == username &&
          other.name == name &&
          other.cooked == cooked &&
          other.avatarUrl == avatarUrl &&
          other.createdAt == createdAt &&
          other.userTitle == userTitle &&
          other.replyCount == replyCount &&
          other.isStaff == isStaff &&
          other.canEdit == canEdit &&
          other.canDelete == canDelete &&
          other.canRecover == canRecover &&
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
          listEquals(other.postActions, postActions) &&
          other.raw == raw &&
          other.plugins == plugins;

  @override
  int get hashCode => Object.hashAll([
    id,
    postNumber,
    username,
    name,
    cooked,
    avatarUrl,
    createdAt,
    userTitle,
    replyCount,
    isStaff,
    canEdit,
    canDelete,
    canRecover,
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
    Object.hashAll(postActions),
    raw,
    plugins,
  ]);
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
/// Core sends `suggested_topics` there; discourse-ai adds `related_topics` to
/// the same response. [recommendations] is null before the end rather than an
/// empty value, so a partial refetch cannot erase recommendations already held.
typedef TopicPostsPayload = ({
  List<Post> posts,
  TopicRecommendations? recommendations,
});

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
    this.postsCount = 0,
    this.categoryId,
    this.canCreatePost = false,
    this.canEdit = false,
    this.canEditTags = false,
    this.tags = const [],
    this.archived = false,
    this.draft,
    this.draftSequence = 0,
    this.recommendations,
    this.plugins = PluginData.none,
  });

  /// The fixed first-window size served by core's `TopicView`.
  ///
  /// The complete post-id stream is retained separately, so bounding eager
  /// post construction here never makes a later post unreachable.
  static const int maximumInitialPosts = 20;

  /// Reads a topic payload into the topic and its posts.
  static TopicPayload parse(
    Map<String, dynamic> json,
    String siteUrl, {
    PluginDataDecoder extensions = const EmptyPluginDataDecoder(),
  }) {
    final postStream = jsonObject(json['post_stream']);
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
        postsCount: jsonInt(json['posts_count']),
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
        canEditTags: details['can_edit_tags'] == true,
        tags: List.unmodifiable(
          jsonArray(json['tags']).map(TopicTag.parse).whereType<TopicTag>(),
        ),
        archived: json['archived'] == true,
        // The topic payload already carries any draft for it, so opening a
        // composer needs no request of its own.
        draft: ComposerDraft.decode(json['draft']),
        draftSequence: jsonInt(json['draft_sequence']),
        recommendations: TopicRecommendations.fromJson(
          json,
          siteUrl,
          extensions: extensions,
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

  final int postsCount;
  final int? categoryId;

  /// Whether this reader may reply here.
  final bool canCreatePost;
  final bool canEdit;
  final bool canEditTags;
  final List<TopicTag> tags;

  /// Archived topics reject poll writes even when their posts remain visible.
  final bool archived;

  /// A reply left unfinished here, wherever it was started.
  final ComposerDraft? draft;

  /// What the next draft save must be sequenced against.
  final int draftSequence;

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

  /// The topic with one complete optional-feature snapshot.
  TopicDetail withPlugins(PluginData next) => TopicDetail(
    id: id,
    title: title,
    stream: stream,
    postsCount: postsCount,
    categoryId: categoryId,
    canCreatePost: canCreatePost,
    canEdit: canEdit,
    canEditTags: canEditTags,
    tags: tags,
    archived: archived,
    draft: draft,
    draftSequence: draftSequence,
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
    final missing = stream.where((id) => !arrived.contains(id)).toList();
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
    int? postsCount,
    ComposerDraft? draft,
    bool clearDraft = false,
    int? draftSequence,
    bool? archived,
    int? categoryId,
    bool clearCategory = false,
    List<TopicTag>? tags,
    bool? canEdit,
    bool? canEditTags,
    TopicRecommendations? recommendations,
    PluginData? plugins,
  }) => TopicDetail(
    id: id,
    title: title ?? this.title,
    stream: stream == null ? this.stream : List.unmodifiable(stream),
    postsCount: postsCount ?? this.postsCount,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    canCreatePost: canCreatePost,
    canEdit: canEdit ?? this.canEdit,
    canEditTags: canEditTags ?? this.canEditTags,
    tags: tags == null ? this.tags : List.unmodifiable(tags),
    archived: archived ?? this.archived,
    draft: clearDraft ? null : (draft ?? this.draft),
    draftSequence: draftSequence ?? this.draftSequence,
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
          other.postsCount == postsCount &&
          other.categoryId == categoryId &&
          other.canCreatePost == canCreatePost &&
          other.canEdit == canEdit &&
          other.canEditTags == canEditTags &&
          listEquals(other.tags, tags) &&
          other.archived == archived &&
          other.draft == draft &&
          other.draftSequence == draftSequence &&
          other.recommendations == recommendations &&
          other.plugins == plugins;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    Object.hashAll(stream),
    postsCount,
    categoryId,
    canCreatePost,
    canEdit,
    canEditTags,
    Object.hashAll(tags),
    archived,
    draft,
    draftSequence,
    recommendations,
    plugins,
  );
}
