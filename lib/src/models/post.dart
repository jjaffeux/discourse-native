import 'package:flutter/foundation.dart';

import 'composer_draft.dart';

/// One post in a topic.
@immutable
class Post {
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
    this.postType = regularPostType,
    this.actionCode,
    this.actionCodeWho,
    this.raw,
  });

  /// `post_type` values Discourse uses. Regular posts are 1; the moderator
  /// notices a topic collects — closed, pinned, invited — are 3.
  static const int regularPostType = 1;
  static const int smallActionPostType = 3;

  factory Post.fromJson(Map<String, dynamic> json, String siteUrl) {
    return Post(
      id: _int(json['id']),
      postNumber: _int(json['post_number']),
      username: (json['username'] ?? '') as String,
      name: _nonEmpty(json['name']),
      // Server-rendered HTML. Discourse does the markdown, oneboxing, emoji
      // and mention rendering, which is far too much to redo client side.
      cooked: (json['cooked'] ?? '') as String,
      avatarUrl: resolveAvatarUrl(json['avatar_template'] as String?, siteUrl),
      createdAt: DateTime.tryParse((json['created_at'] ?? '') as String),
      userTitle: _nonEmpty(json['user_title']),
      replyCount: _int(json['reply_count']),
      isStaff: json['admin'] == true || json['moderator'] == true,
      postType: json['post_type'] == null
          ? regularPostType
          : _int(json['post_type']),
      actionCode: _nonEmpty(json['action_code']),
      actionCodeWho: _nonEmpty(json['action_code_who']),
      // Only present when asked for. Reading needs the cooked HTML; writing
      // needs this, because it is the thing that was actually typed.
      raw: _nonEmpty(json['raw']),
    );
  }

  static int _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  static String? _nonEmpty(Object? value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

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
  final int postType;

  /// What the moderator action was, e.g. `closed.enabled` or `invited_user`.
  /// Only small actions carry one.
  final String? actionCode;

  /// The user or group the action was taken on, for the codes that name one.
  final String? actionCodeWho;

  /// The markdown this post was written as, when it was asked for.
  ///
  /// Absent from an ordinary read: the stream carries [cooked] and nothing
  /// needs the source until something wants to compare or edit it.
  final String? raw;

  /// Small actions are the "closed this topic" notices in the stream. They
  /// have no body of their own, so they are drawn as a one-line notice
  /// rather than as a post.
  bool get isSmallAction => postType == smallActionPostType;

  String get displayName => name ?? username;
}

/// Avatar templates are site-relative and carry a `{size}` placeholder.
String? resolveAvatarUrl(String? template, String siteUrl) {
  if (template == null || template.isEmpty) return null;
  final sized = template.replaceAll('{size}', '90');
  if (sized.startsWith('//')) return 'https:$sized';
  if (sized.startsWith('http')) return sized;
  return '$siteUrl${sized.startsWith('/') ? '' : '/'}$sized';
}

/// A topic and the posts fetched so far.
@immutable
class TopicDetail {
  const TopicDetail({
    required this.id,
    required this.title,
    required this.posts,
    required this.stream,
    this.postsCount = 0,
    this.categoryId,
    this.canCreatePost = false,
    this.draft,
    this.draftSequence = 0,
  });

  factory TopicDetail.fromJson(Map<String, dynamic> json, String siteUrl) {
    final stream = json['post_stream'] as Map<String, dynamic>? ?? const {};
    final details = json['details'] as Map<String, dynamic>? ?? const {};
    return TopicDetail(
      id: Post._int(json['id']),
      title: (json['title'] ?? json['fancy_title'] ?? '') as String,
      posts: (stream['posts'] as List<dynamic>? ?? const [])
          .map((p) => Post.fromJson(p as Map<String, dynamic>, siteUrl))
          .toList(),
      // Every post id in the topic, even the ones not fetched yet — this is
      // what makes paging through a long topic possible.
      stream: (stream['stream'] as List<dynamic>? ?? const [])
          .map(Post._int)
          .toList(),
      postsCount: Post._int(json['posts_count']),
      categoryId: json['category_id'] == null
          ? null
          : Post._int(json['category_id']),
      // The only question worth asking before showing a reply button, and the
      // whole question: the guardian behind it has already folded in closed,
      // archived and the trust levels that are allowed past them. Checking
      // `closed` again here would hide the button from the moderators who can
      // still use it. Absent when read signed out, which is also the right
      // answer — there is no key to post with.
      canCreatePost: details['can_create_post'] == true,
      // The topic payload already carries any draft for it, so opening a
      // composer needs no request of its own.
      draft: ComposerDraft.decode(json['draft']),
      draftSequence: Post._int(json['draft_sequence']),
    );
  }

  final int id;
  final String title;
  final List<Post> posts;
  final List<int> stream;
  final int postsCount;
  final int? categoryId;

  /// Whether this reader may reply here.
  final bool canCreatePost;

  /// A reply left unfinished here, wherever it was started.
  final ComposerDraft? draft;

  /// What the next draft save must be sequenced against.
  final int draftSequence;

  /// Post ids not yet fetched, oldest first.
  List<int> get pendingIds {
    final have = posts.map((p) => p.id).toSet();
    return stream.where((id) => !have.contains(id)).toList();
  }

  bool get hasMore => pendingIds.isNotEmpty;

  TopicDetail withMorePosts(List<Post> more) {
    final have = posts.map((p) => p.id).toSet();
    final merged = [...posts, ...more.where((p) => !have.contains(p.id))]
      ..sort((a, b) => a.postNumber.compareTo(b.postNumber));
    return TopicDetail(
      id: id,
      title: title,
      posts: merged,
      stream: stream,
      postsCount: postsCount,
      categoryId: categoryId,
      canCreatePost: canCreatePost,
      draft: draft,
      draftSequence: draftSequence,
    );
  }

  /// Appends a post that was just created here.
  ///
  /// [withMorePosts] cannot do this. It merges posts the stream already knew
  /// about and copies `stream` and `postsCount` through untouched, which is
  /// right for paging and wrong for a post that did not exist a moment ago.
  ///
  /// Idempotent, so a reply that also arrives in a refetch is not counted
  /// twice.
  TopicDetail withNewPost(Post post) {
    final known = stream.contains(post.id);
    final merged = [...posts.where((p) => p.id != post.id), post]
      ..sort((a, b) => a.postNumber.compareTo(b.postNumber));
    return TopicDetail(
      id: id,
      title: title,
      posts: merged,
      stream: known ? stream : [...stream, post.id],
      postsCount: known ? postsCount : postsCount + 1,
      categoryId: categoryId,
      canCreatePost: canCreatePost,
      draft: draft,
      draftSequence: draftSequence,
    );
  }

  /// Records the draft this topic now has, so the cache keeps saying what the
  /// payload would say if it were fetched again.
  ///
  /// Without it, saving a draft and reopening the composer would find nothing:
  /// the local copy is deleted once the site has the text, and the topic in
  /// hand was fetched before the draft existed.
  TopicDetail withDraft(ComposerDraft? draft, int sequence) => TopicDetail(
    id: id,
    title: title,
    posts: posts,
    stream: stream,
    postsCount: postsCount,
    categoryId: categoryId,
    canCreatePost: canCreatePost,
    draft: draft,
    draftSequence: sequence,
  );

  /// Takes a freshly fetched copy's stream without dropping the posts already
  /// in hand.
  ///
  /// Replacing outright would lose the reply just made at the end of a long
  /// topic: the fetch answers with the *first* chunk of posts plus the whole
  /// stream, so a post at position 400 comes back as an id and nothing else.
  TopicDetail withRefreshed(TopicDetail fresh) {
    final byId = {
      for (final post in posts) post.id: post,
      for (final post in fresh.posts) post.id: post,
    };
    return TopicDetail(
      id: fresh.id,
      title: fresh.title,
      posts: byId.values.toList()
        ..sort((a, b) => a.postNumber.compareTo(b.postNumber)),
      stream: fresh.stream,
      postsCount: fresh.postsCount,
      categoryId: fresh.categoryId,
      canCreatePost: fresh.canCreatePost,
      draft: fresh.draft,
      draftSequence: fresh.draftSequence,
    );
  }
}
