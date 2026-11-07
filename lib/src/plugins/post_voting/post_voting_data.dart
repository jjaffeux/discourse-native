import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart' show listEquals;

const postVotingPluginId = PluginId('discourse-post-voting');
const postVotingSettingsKey = PluginDataKey<PostVotingSettings>(
  owner: 'discourse-post-voting',
  name: 'settings',
);
const postVotingTopicKey = PluginDataKey<PostVotingTopicData>(
  owner: 'discourse-post-voting',
  name: 'topic',
);
const postVotingPostKey = PluginDataKey<PostVotingPostData>(
  owner: 'discourse-post-voting',
  name: 'post',
);
const postVotingCurrentUserKey = PluginDataKey<PostVotingActor>(
  owner: 'discourse-post-voting',
  name: 'current-user',
);
const postVotingUserCardKey = PluginDataKey<PostVotingUserScore>(
  owner: 'discourse-post-voting',
  name: 'user-card',
);
const postVotingCategoryKey = PluginDataKey<PostVotingCategoryData>(
  owner: 'discourse-post-voting',
  name: 'category',
);

enum PostVotingOrder { votes, activity }

enum PostVoteDirection {
  up,
  down;

  static PostVoteDirection? parse(Object? value) => switch (value) {
    'up' => up,
    'down' => down,
    _ => null,
  };
}

final class PostVotingSettings {
  const PostVotingSettings({
    this.enabled,
    this.commentsEnabled = true,
    this.commentLimitPerPost = 10,
    this.commentMaxRawLength = 600,
    this.commentMinRawLength = 1,
    this.answerLikesEnabled = false,
    this.dsaReportingEnabled = false,
  });

  factory PostVotingSettings.fromJson(Map<String, dynamic> json) =>
      PostVotingSettings(
        enabled: json['post_voting_enabled'] is bool
            ? json['post_voting_enabled'] as bool
            : null,
        commentsEnabled: json['post_voting_comment_enabled'] != false,
        commentLimitPerPost:
            _positive(json['post_voting_comment_limit_per_post']) ?? 10,
        commentMaxRawLength:
            _positive(json['post_voting_comment_max_raw_length']) ?? 600,
        commentMinRawLength: _positive(json['min_post_length']) ?? 1,
        answerLikesEnabled: json['post_voting_enable_likes_on_answers'] == true,
        dsaReportingEnabled: json['dsa_reporting_enabled'] == true,
      );

  final bool? enabled;
  final bool commentsEnabled;
  final int commentLimitPerPost;
  final int commentMaxRawLength;
  final int commentMinRawLength;
  final bool answerLikesEnabled;
  final bool dsaReportingEnabled;
  @override
  bool operator ==(Object other) =>
      other is PostVotingSettings &&
      enabled == other.enabled &&
      commentsEnabled == other.commentsEnabled &&
      commentLimitPerPost == other.commentLimitPerPost &&
      commentMaxRawLength == other.commentMaxRawLength &&
      commentMinRawLength == other.commentMinRawLength &&
      answerLikesEnabled == other.answerLikesEnabled &&
      dsaReportingEnabled == other.dsaReportingEnabled;

  @override
  int get hashCode => Object.hash(
    enabled,
    commentsEnabled,
    commentLimitPerPost,
    commentMaxRawLength,
    commentMinRawLength,
    answerLikesEnabled,
    dsaReportingEnabled,
  );

  bool allowsTopic(
    PostVotingTopicData? topic, {
    required bool privateMessage,
  }) => !privateMessage && enabled != false && topic?.enabled == true;

  Map<String, Object?> toJson() => {
    if (enabled != null) 'post_voting_enabled': enabled,
    'post_voting_comment_enabled': commentsEnabled,
    'post_voting_comment_limit_per_post': commentLimitPerPost,
    'post_voting_comment_max_raw_length': commentMaxRawLength,
    'min_post_length': commentMinRawLength,
    'post_voting_enable_likes_on_answers': answerLikesEnabled,
    'dsa_reporting_enabled': dsaReportingEnabled,
  };
}

final class PostVotingSettingsCodec
    extends PluginDataPersistenceCodec<PostVotingSettings> {
  const PostVotingSettingsCodec();
  @override
  PluginDataKey<PostVotingSettings> get key => postVotingSettingsKey;
  @override
  PostVotingSettings? decode(Object? value) => value is Map
      ? PostVotingSettings.fromJson(Map<String, dynamic>.from(value))
      : null;
  @override
  Object encode(PostVotingSettings value) => value.toJson();
}

final class PostVotingCategoryData {
  const PostVotingCategoryData({
    this.defaultOn = false,
    this.requiredOn = false,
  });
  factory PostVotingCategoryData.fromJson(Map<String, dynamic> json) {
    final fields = json['custom_fields'] is Map
        ? json['custom_fields'] as Map
        : const <Object?, Object?>{};
    return PostVotingCategoryData(
      defaultOn:
          (json['create_as_post_voting_default'] ??
              fields['create_as_post_voting_default']) ==
          true,
      requiredOn:
          (json['only_post_voting_in_this_category'] ??
              fields['only_post_voting_in_this_category']) ==
          true,
    );
  }
  final bool defaultOn;
  final bool requiredOn;
  @override
  bool operator ==(Object other) =>
      other is PostVotingCategoryData &&
      (defaultOn, requiredOn) == (other.defaultOn, other.requiredOn);
  @override
  int get hashCode => Object.hash(defaultOn, requiredOn);
}

final class PostVotingActor {
  const PostVotingActor({this.canFlagComments = false});
  factory PostVotingActor.fromJson(Map<String, dynamic> json) =>
      PostVotingActor(
        canFlagComments: json['can_flag_post_voting_comments'] == true,
      );
  final bool canFlagComments;
  @override
  bool operator ==(Object other) =>
      other is PostVotingActor && canFlagComments == other.canFlagComments;
  @override
  int get hashCode => canFlagComments.hashCode;
}

final class PostVotingUserScore {
  const PostVotingUserScore(this.receivedNetScore);
  final int receivedNetScore;
  @override
  bool operator ==(Object other) =>
      other is PostVotingUserScore &&
      receivedNetScore == other.receivedNetScore;
  @override
  int get hashCode => receivedNetScore.hashCode;
  static PostVotingUserScore? fromJson(Map<String, dynamic> json) =>
      json['vote_count'] is int
      ? PostVotingUserScore(json['vote_count'] as int)
      : null;
}

final class PostVotingUser {
  const PostVotingUser({
    required this.id,
    required this.username,
    this.name,
    this.avatarTemplate,
  });
  factory PostVotingUser.fromJson(Map<String, dynamic> json) {
    final id = _positive(json['id']);
    final username = _text(json['username']);
    if (id == null || username == null || username.isEmpty) {
      throw const FormatException('Invalid voter identity.');
    }
    return PostVotingUser(
      id: id,
      username: username,
      name: _text(json['name']),
      avatarTemplate: _text(json['avatar_template']),
    );
  }
  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;

  @override
  bool operator ==(Object other) =>
      other is PostVotingUser &&
      other.id == id &&
      other.username == username &&
      other.name == name &&
      other.avatarTemplate == avatarTemplate;

  @override
  int get hashCode => Object.hash(id, username, name, avatarTemplate);
}

final class PostVotingTopicData
    implements
        TopicRecordValue,
        TopicReadingPolicyRecord,
        TopicReplyPolicyRecord {
  const PostVotingTopicData({
    this.enabled,
    this.answerCount,
    this.lastAnsweredAt,
    this.lastCommentedOn,
    this.lastAnswerPostNumber,
    this.lastAnswerer,
    this.serverReadState,
    this.detailMetadata = false,
  });

  factory PostVotingTopicData.fromContext(
    Map<String, dynamic> json,
    TopicRecordDecodeContext context,
  ) {
    final authoritative = context.source != TopicRecordSource.partial;
    final privateMessage = json['archetype'] == 'private_message';
    final nested = json['is_nested_view'] == true;
    final active =
        json.containsKey('is_post_voting') ||
            authoritative ||
            privateMessage ||
            nested
        ? json['is_post_voting'] == true && !privateMessage && !nested
        : null;
    // The record merge keeps for a disabled topic, so a topic decoded again
    // from the same payload stays equal to the one the store holds.
    if (active == false) return const PostVotingTopicData(enabled: false);
    final lastRead = _nonnegative(json['last_read_post_number']);
    final highest = _positive(json['highest_post_number']);
    final unread = _nonnegative(json['unread_posts']);
    return PostVotingTopicData(
      enabled: active,
      answerCount: _nonnegative(json['answer_count']),
      lastAnsweredAt: _date(json['last_answered_at']),
      lastCommentedOn: _date(json['last_commented_on']),
      lastAnswerPostNumber: _positive(json['last_answer_post_number']),
      lastAnswerer: _optionalUser(json['last_answerer']),
      serverReadState: lastRead != null && highest != null
          ? lastRead >= highest
          : unread != null && unread > 0
          ? false
          : null,
      detailMetadata: context.source == TopicRecordSource.detail,
    );
  }

  final bool? enabled;
  final int? answerCount;
  final DateTime? lastAnsweredAt;
  final DateTime? lastCommentedOn;
  final int? lastAnswerPostNumber;
  final PostVotingUser? lastAnswerer;
  final bool? serverReadState;
  final bool detailMetadata;

  PostVotingTopicData merge(PostVotingTopicData incoming) {
    if (incoming.enabled == false) {
      return const PostVotingTopicData(enabled: false);
    }
    return PostVotingTopicData(
      enabled: incoming.enabled ?? enabled,
      answerCount: incoming.answerCount ?? answerCount,
      lastAnsweredAt: incoming.detailMetadata
          ? incoming.lastAnsweredAt
          : incoming.lastAnsweredAt ?? lastAnsweredAt,
      lastCommentedOn: incoming.detailMetadata
          ? incoming.lastCommentedOn
          : incoming.lastCommentedOn ?? lastCommentedOn,
      lastAnswerPostNumber: incoming.detailMetadata
          ? incoming.lastAnswerPostNumber
          : incoming.lastAnswerPostNumber ?? lastAnswerPostNumber,
      lastAnswerer: incoming.detailMetadata
          ? incoming.lastAnswerer
          : incoming.lastAnswerer ?? lastAnswerer,
      serverReadState: incoming.serverReadState ?? serverReadState,
      detailMetadata: detailMetadata || incoming.detailMetadata,
    );
  }

  @override
  PostVotingTopicData mergeTopicRecord(Object? held) =>
      held is PostVotingTopicData ? held.merge(this) : this;
  @override
  TopicReadingPolicy? get topicReadingPolicy => enabled == true
      ? NonchronologicalTopicReadingPolicy(serverReadState: serverReadState)
      : null;
  @override
  bool get repliesToTopic => enabled == true;
  @override
  PostVotingTopicData markTopicRead() => enabled == false
      ? this
      : PostVotingTopicData(
          enabled: enabled,
          answerCount: answerCount,
          lastAnsweredAt: lastAnsweredAt,
          lastCommentedOn: lastCommentedOn,
          lastAnswerPostNumber: lastAnswerPostNumber,
          lastAnswerer: lastAnswerer,
          serverReadState: true,
          detailMetadata: detailMetadata,
        );

  // Every topic carries this record, so a topic decoded again from the same
  // payload is unchanged only if the record compares by value: the store
  // otherwise replaces the topic and every list row showing it rebuilds.
  @override
  bool operator ==(Object other) =>
      other is PostVotingTopicData &&
      other.enabled == enabled &&
      other.answerCount == answerCount &&
      other.lastAnsweredAt == lastAnsweredAt &&
      other.lastCommentedOn == lastCommentedOn &&
      other.lastAnswerPostNumber == lastAnswerPostNumber &&
      other.lastAnswerer == lastAnswerer &&
      other.serverReadState == serverReadState &&
      other.detailMetadata == detailMetadata;

  @override
  int get hashCode => Object.hash(
    enabled,
    answerCount,
    lastAnsweredAt,
    lastCommentedOn,
    lastAnswerPostNumber,
    lastAnswerer,
    serverReadState,
    detailMetadata,
  );
}

final class PostVotingPostData {
  PostVotingPostData({
    this.score,
    this.hasVotes,
    this.myVote,
    this.myVoteKnown = false,
    this.commentsCount,
    List<PostVotingComment>? initialComments,
    this.replyToPostNumber,
  }) : initialComments = initialComments == null
           ? null
           : List.unmodifiable(initialComments);

  factory PostVotingPostData.fromJson(
    Map<String, dynamic> json, {
    bool authoritativeVote = false,
  }) {
    final postId = _positive(json['id']);
    final direction = PostVoteDirection.parse(
      json['post_voting_user_voted_direction'],
    );
    final directionKnown = json.containsKey('post_voting_user_voted_direction')
        ? json['post_voting_user_voted_direction'] == null || direction != null
        : authoritativeVote && json.containsKey('post_voting_vote_count');
    return PostVotingPostData(
      score: json['post_voting_vote_count'] is int
          ? json['post_voting_vote_count'] as int
          : null,
      hasVotes: json['post_voting_has_votes'] is bool
          ? json['post_voting_has_votes'] as bool
          : null,
      myVote: direction,
      myVoteKnown: directionKnown,
      commentsCount: _nonnegative(json['comments_count']),
      initialComments: postId != null && json['comments'] is List
          ? [
              for (final value in json['comments'] as List)
                PostVotingComment.fromJson(
                  _object(value),
                  parentPostId: postId,
                  authoritativeVote: authoritativeVote,
                ),
            ]
          : null,
      replyToPostNumber: _positive(json['reply_to_post_number']),
    );
  }

  final int? score;
  final bool? hasVotes;
  final PostVoteDirection? myVote;
  final bool myVoteKnown;
  final int? commentsCount;
  final List<PostVotingComment>? initialComments;
  final int? replyToPostNumber;
  @override
  bool operator ==(Object other) =>
      other is PostVotingPostData &&
      score == other.score &&
      hasVotes == other.hasVotes &&
      myVote == other.myVote &&
      myVoteKnown == other.myVoteKnown &&
      commentsCount == other.commentsCount &&
      listEquals(initialComments, other.initialComments) &&
      replyToPostNumber == other.replyToPostNumber;

  @override
  int get hashCode => Object.hash(
    score,
    hasVotes,
    myVote,
    myVoteKnown,
    commentsCount,
    initialComments == null ? null : Object.hashAll(initialComments!),
    replyToPostNumber,
  );

  bool get canHaveComments => replyToPostNumber == null;
  bool get hasData =>
      replyToPostNumber != null ||
      score != null ||
      hasVotes != null ||
      myVoteKnown ||
      commentsCount != null ||
      initialComments != null;

  PostVotingPostData merge(PostVotingPostData incoming) => PostVotingPostData(
    score: incoming.score ?? score,
    hasVotes: incoming.hasVotes ?? hasVotes,
    myVote: incoming.myVoteKnown ? incoming.myVote : myVote,
    myVoteKnown: incoming.myVoteKnown || myVoteKnown,
    commentsCount: incoming.commentsCount ?? commentsCount,
    initialComments: incoming.initialComments ?? initialComments,
    replyToPostNumber: incoming.replyToPostNumber ?? replyToPostNumber,
  );
  PostVotingPostData withVote({
    required int score,
    required bool hasVotes,
    required PostVoteDirection? myVote,
    required bool myVoteKnown,
  }) => PostVotingPostData(
    score: score,
    hasVotes: hasVotes,
    myVote: myVote,
    myVoteKnown: myVoteKnown,
    commentsCount: commentsCount,
    initialComments: initialComments,
    replyToPostNumber: replyToPostNumber,
  );
  PostVotingPostData withComments(
    List<PostVotingComment> comments, {
    required int total,
  }) => PostVotingPostData(
    score: score,
    hasVotes: hasVotes,
    myVote: myVote,
    myVoteKnown: myVoteKnown,
    commentsCount: total,
    initialComments: comments,
    replyToPostNumber: replyToPostNumber,
  );
}

final class PostVotingComment {
  PostVotingComment({
    required this.id,
    required this.parentPostId,
    this.authorId,
    this.username,
    this.name,
    required this.createdAt,
    required this.raw,
    required this.cooked,
    required this.score,
    this.myUpvote,
    Iterable<String> availableFlags = const [],
    this.reviewableId,
    required this.url,
  }) : availableFlags = List.unmodifiable(availableFlags);

  factory PostVotingComment.fromJson(
    Map<String, dynamic> json, {
    required int parentPostId,
    bool authoritativeVote = false,
  }) {
    final id = _positive(json['id']);
    final date = _date(json['created_at']);
    final raw = _text(json['raw']);
    final cooked = _text(json['cooked']);
    final score = json['post_voting_vote_count'];
    if (id == null ||
        parentPostId <= 0 ||
        date == null ||
        raw == null ||
        cooked == null ||
        score is! int ||
        (json.containsKey('post_id') && json['post_id'] != parentPostId)) {
      throw const FormatException('Invalid comment record.');
    }
    final url = Uri.tryParse(
      _text(json['url']) ?? '/p/$parentPostId#post-voting-comment-$id',
    );
    if (url == null ||
        (url.hasScheme && url.scheme != 'https' && url.scheme != 'http')) {
      throw const FormatException('Invalid comment URL.');
    }
    return PostVotingComment(
      id: id,
      parentPostId: parentPostId,
      authorId: _positive(json['user_id']),
      username: _text(json['username']),
      name: _text(json['name']),
      createdAt: date,
      raw: raw,
      cooked: cooked,
      score: score,
      myUpvote: json['user_voted'] is bool
          ? json['user_voted'] as bool
          : authoritativeVote
          ? false
          : null,
      availableFlags: json['available_flags'] is List
          ? (json['available_flags'] as List).whereType<String>()
          : const [],
      reviewableId: _positive(json['reviewable_id']),
      url: url,
    );
  }
  final int id;
  final int parentPostId;
  final int? authorId;
  final String? username;
  final String? name;
  final DateTime createdAt;
  final String raw;
  final String cooked;
  final int score;
  final bool? myUpvote;
  final List<String> availableFlags;
  final int? reviewableId;
  final Uri url;

  @override
  bool operator ==(Object other) =>
      other is PostVotingComment &&
      (
            id,
            parentPostId,
            authorId,
            username,
            name,
            createdAt,
            raw,
            cooked,
            score,
            myUpvote,
            reviewableId,
            url,
          ) ==
          (
            other.id,
            other.parentPostId,
            other.authorId,
            other.username,
            other.name,
            other.createdAt,
            other.raw,
            other.cooked,
            other.score,
            other.myUpvote,
            other.reviewableId,
            other.url,
          ) &&
      listEquals(availableFlags, other.availableFlags);

  @override
  int get hashCode => Object.hash(
    id,
    parentPostId,
    authorId,
    username,
    name,
    createdAt,
    raw,
    cooked,
    score,
    myUpvote,
    reviewableId,
    url,
    Object.hashAll(availableFlags),
  );

  PostVotingComment copyWith({
    String? raw,
    String? cooked,
    int? score,
    bool? myUpvote,
    bool clearMyUpvote = false,
    List<String>? availableFlags,
  }) => PostVotingComment(
    id: id,
    parentPostId: parentPostId,
    authorId: authorId,
    username: username,
    name: name,
    createdAt: createdAt,
    raw: raw ?? this.raw,
    cooked: cooked ?? this.cooked,
    score: score ?? this.score,
    myUpvote: clearMyUpvote ? null : myUpvote ?? this.myUpvote,
    availableFlags: availableFlags ?? this.availableFlags,
    reviewableId: reviewableId,
    url: url,
  );
}

final class PostVotingVoter {
  const PostVotingVoter({required this.user, required this.direction});
  final PostVotingUser user;
  final PostVoteDirection direction;
}

final class PostVotingVoters {
  PostVotingVoters({
    required Iterable<PostVotingVoter> users,
    required this.total,
  }) : users = List.unmodifiable(users);
  final List<PostVotingVoter> users;
  final int total;
  int get remaining => (total - users.length).clamp(0, total);
}

final class PostVotingCommentBatch {
  PostVotingCommentBatch(Iterable<PostVotingComment> comments)
    : comments = List.unmodifiable(comments);
  final List<PostVotingComment> comments;
  int? get lastCommentId => comments.isEmpty ? null : comments.last.id;
  bool get remainderLoaded => true;
}

final class PostVotingWindow {
  PostVotingWindow({
    required Iterable<int> orderedStreamIds,
    required Iterable<TopicContentPost> posts,
    required this.metadata,
    required this.order,
  }) : orderedStreamIds = List.unmodifiable(orderedStreamIds),
       posts = List.unmodifiable(posts);
  final List<int> orderedStreamIds;
  final List<TopicContentPost> posts;
  final TopicDetail metadata;
  final PostVotingOrder order;
}

final class PostVotingFlagCommand {
  const PostVotingFlagCommand({
    required this.commentId,
    required this.flagTypeId,
    this.message,
    this.isWarning = false,
    this.takeAction = false,
    this.queueForReview = false,
  });
  final int commentId;
  final int flagTypeId;
  final String? message;
  final bool isWarning;
  final bool takeAction;
  final bool queueForReview;
}

int? _positive(Object? value) => value is int && value > 0 ? value : null;
int? _nonnegative(Object? value) => value is int && value >= 0 ? value : null;
String? _text(Object? value) => value is String ? value : null;
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
Map<String, dynamic> _object(Object? value) {
  if (value is! Map) throw const FormatException('Invalid JSON object.');
  return Map<String, dynamic>.from(value);
}

PostVotingUser? _optionalUser(Object? value) {
  if (value is! Map) return null;
  try {
    return PostVotingUser.fromJson(Map<String, dynamic>.from(value));
  } on FormatException {
    return null;
  }
}

final class PostVotingPostLocation {
  const PostVotingPostLocation({
    required this.topicId,
    required this.postNumber,
    required this.slug,
  });
  final int topicId;
  final int postNumber;
  final String slug;
}
