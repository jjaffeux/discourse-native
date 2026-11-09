import 'package:discourse_native/discourse_plugin_contracts.dart';

import 'post_voting_data.dart';

final class PostVotingApi {
  const PostVotingApi(this.transport, this.models);
  final PluginApiTransport transport;
  final DiscourseModelCodec models;

  Future<PostVotingWindow> loadWindow({
    required String siteUrl,
    required int topicId,
    required PostVotingOrder order,
    required PluginRequestCredentials credentials,
    int? nearPostNumber,
    int? page,
    TopicDetail? heldTopic,
  }) async {
    _id(topicId, 'topicId');
    if (nearPostNumber != null) _id(nearPostNumber, 'nearPostNumber');
    if (page != null && (page < 0 || page > 10000)) {
      throw ArgumentError.value(page, 'page');
    }
    final json = await _get(siteUrl, '/t/$topicId.json', credentials, {
      if (order == PostVotingOrder.activity) 'filter': 'activity',
      if (nearPostNumber != null) 'post_number': '$nearPostNumber',
      if (page != null) 'page': '$page',
    });
    if (json['id'] != topicId) {
      throw const FormatException('Mismatched topic identity.');
    }
    final stream = _object(json['post_stream']);
    final ids = _ids(stream['stream']);
    final posts = _posts(
      stream['posts'],
      siteUrl,
      topicId,
      authoritativeVote: true,
    );
    if (posts.any((item) => !ids.contains(item.post.id))) {
      throw const FormatException('Post is outside the returned stream.');
    }
    if (heldTopic != null && heldTopic.id != topicId) {
      throw ArgumentError.value(heldTopic.id, 'heldTopic');
    }
    final detail = heldTopic == null
        ? models.topic(json, siteUrl).detail
        : models.topicMetadata(json, siteUrl, held: heldTopic);
    final metadata = detail.withPlugins(
      detail.plugins.withValue(
        postVotingTopicKey,
        PostVotingTopicData.fromContext(
          json,
          const TopicRecordDecodeContext.detail(),
        ),
      ),
    );
    return PostVotingWindow(
      orderedStreamIds: ids,
      posts: posts,
      metadata: metadata,
      order: order,
    );
  }

  Future<List<TopicContentPost>> loadPosts({
    required String siteUrl,
    required int topicId,
    required List<int> postIds,
    required PostVotingOrder order,
    required PluginRequestCredentials credentials,
  }) async {
    _id(topicId, 'topicId');
    if (postIds.isEmpty ||
        postIds.length > 100 ||
        postIds.toSet().length != postIds.length) {
      throw ArgumentError.value(postIds, 'postIds');
    }
    for (final id in postIds) {
      _id(id, 'postId');
    }
    final query = [
      for (final id in postIds) 'post_ids[]=$id',
      if (order == PostVotingOrder.activity) 'filter=activity',
    ].join('&');
    final json = await _get(
      siteUrl,
      '/t/$topicId/posts.json?$query',
      credentials,
      const {},
    );
    if (json.containsKey('id') && json['id'] != topicId) {
      throw const FormatException('Mismatched topic identity.');
    }
    final posts = _posts(
      _object(json['post_stream'])['posts'],
      siteUrl,
      topicId,
      authoritativeVote: true,
    );
    final found = {for (final post in posts) post.post.id: post};
    if (found.keys.any((id) => !postIds.contains(id))) {
      throw const FormatException('Unrequested post identity.');
    }
    return List.unmodifiable([
      for (final id in postIds)
        if (found.containsKey(id)) found[id]!,
    ]);
  }

  Future<void> votePost({
    required String siteUrl,
    required int postId,
    required PostVoteDirection direction,
    required PluginRequestCredentials credentials,
  }) => _ack(siteUrl, '/post_voting/vote.json', credentials, 'POST', {
    'post_id': _id(postId, 'postId'),
    'direction': direction.name,
  });
  Future<void> undoPostVote({
    required String siteUrl,
    required int postId,
    required PluginRequestCredentials credentials,
  }) => _ack(siteUrl, '/post_voting/vote.json', credentials, 'DELETE', {
    'post_id': _id(postId, 'postId'),
  });

  Future<PostVotingVoters> voters({
    required String siteUrl,
    required int postId,
    required PluginRequestCredentials credentials,
  }) async {
    final json = await _get(siteUrl, '/post_voting/voters.json', credentials, {
      'post_id': '${_id(postId, 'postId')}',
    });
    final values = json['voters'];
    final total = json['total_voters_count'];
    if (values is! List ||
        values.length > 20 ||
        total is! int ||
        total < values.length) {
      throw const FormatException('Invalid voter response.');
    }
    final seen = <int>{};
    final voters = <PostVotingVoter>[];
    for (final value in values) {
      final wire = _object(value);
      final user = PostVotingUser.fromJson(wire);
      final direction = PostVoteDirection.parse(wire['direction']);
      if (direction == null || !seen.add(user.id)) {
        throw const FormatException('Invalid voter record.');
      }
      voters.add(PostVotingVoter(user: user, direction: direction));
    }
    return PostVotingVoters(users: voters, total: total);
  }

  Future<PostVotingCommentBatch> comments({
    required String siteUrl,
    required int postId,
    required PluginRequestCredentials credentials,
    int afterCommentId = 0,
  }) async {
    _id(postId, 'postId');
    if (afterCommentId < 0) {
      throw ArgumentError.value(afterCommentId, 'afterCommentId');
    }
    final json = await _get(
      siteUrl,
      '/post_voting/comments.json',
      credentials,
      {'post_id': '$postId', 'last_comment_id': '$afterCommentId'},
    );
    final values = json['comments'];
    if (values is! List) {
      throw const FormatException('Invalid comments response.');
    }
    final comments = <PostVotingComment>[];
    var previous = afterCommentId;
    for (final value in values) {
      final comment = PostVotingComment.fromJson(
        _object(value),
        parentPostId: postId,
        authoritativeVote: true,
      );
      if (comment.id <= previous) {
        throw const FormatException('Invalid comment cursor order.');
      }
      comments.add(comment);
      previous = comment.id;
    }
    return PostVotingCommentBatch(comments);
  }

  Future<PostVotingComment> createComment({
    required String siteUrl,
    required int postId,
    required String raw,
    required PluginRequestCredentials credentials,
  }) async {
    final json = await _write(
      siteUrl,
      '/post_voting/comments.json',
      credentials,
      'POST',
      {'post_id': _id(postId, 'postId'), 'raw': raw},
    );
    return PostVotingComment.fromJson(
      json,
      parentPostId: postId,
      authoritativeVote: true,
    );
  }

  Future<PostVotingComment> editComment({
    required String siteUrl,
    required int parentPostId,
    required int commentId,
    required String raw,
    required PluginRequestCredentials credentials,
  }) async {
    _id(parentPostId, 'parentPostId');
    final json = await _write(
      siteUrl,
      '/post_voting/comments.json',
      credentials,
      'PUT',
      {'comment_id': _id(commentId, 'commentId'), 'raw': raw},
    );
    final result = PostVotingComment.fromJson(
      json,
      parentPostId: parentPostId,
      authoritativeVote: true,
    );
    if (result.id != commentId) {
      throw const FormatException('Mismatched comment identity.');
    }
    return result;
  }

  Future<PostVotingPostLocation> lookupPost({
    required String siteUrl,
    required int postId,
    required PluginRequestCredentials credentials,
  }) async {
    _id(postId, 'postId');
    final json = await _get(
      siteUrl,
      '/posts/$postId.json',
      credentials,
      const {},
    );
    final topicId = json['topic_id'];
    final number = json['post_number'];
    if (json['id'] != postId ||
        topicId is! int ||
        topicId <= 0 ||
        number is! int ||
        number <= 0) {
      throw const FormatException('Mismatched post location.');
    }
    final slug = json['topic_slug'];
    return PostVotingPostLocation(
      topicId: topicId,
      postNumber: number,
      slug: slug is String && slug.isNotEmpty ? slug : 'topic',
    );
  }

  Future<void> deleteComment({
    required String siteUrl,
    required int commentId,
    required PluginRequestCredentials credentials,
  }) => _ack(siteUrl, '/post_voting/comments.json', credentials, 'DELETE', {
    'comment_id': _id(commentId, 'commentId'),
  });
  Future<void> upvoteComment({
    required String siteUrl,
    required int commentId,
    required PluginRequestCredentials credentials,
  }) => _ack(siteUrl, '/post_voting/vote/comment.json', credentials, 'POST', {
    'comment_id': _id(commentId, 'commentId'),
  });
  Future<void> undoCommentVote({
    required String siteUrl,
    required int commentId,
    required PluginRequestCredentials credentials,
  }) => _ack(siteUrl, '/post_voting/vote/comment.json', credentials, 'DELETE', {
    'comment_id': _id(commentId, 'commentId'),
  });

  Future<void> flagComment({
    required String siteUrl,
    required PostVotingFlagCommand command,
    required PluginRequestCredentials credentials,
  }) => _ack(siteUrl, '/post_voting/comments/flag.json', credentials, 'PUT', {
    'comment_id': _id(command.commentId, 'commentId'),
    'flag_type_id': _id(command.flagTypeId, 'flagTypeId'),
    if (command.message != null) 'message': command.message,
    'is_warning': command.isWarning,
    'take_action': command.takeAction,
    'queue_for_review': command.queueForReview,
  });

  List<TopicContentPost> _posts(
    Object? value,
    String siteUrl,
    int topicId, {
    required bool authoritativeVote,
  }) {
    if (value is! List) throw const FormatException('Invalid topic posts.');
    final ids = <int>{};
    final numbers = <int>{};
    final result = <TopicContentPost>[];
    for (final item in value) {
      final json = _object(item);
      final id = json['id'];
      final number = json['post_number'];
      if (id is! int ||
          id <= 0 ||
          number is! int ||
          number <= 0 ||
          !ids.add(id) ||
          !numbers.add(number) ||
          (json.containsKey('topic_id') && json['topic_id'] != topicId)) {
        throw const FormatException('Invalid post identity.');
      }
      final post = models.post({...json, 'topic_id': topicId}, siteUrl);
      final data = PostVotingPostData.fromJson(
        json,
        authoritativeVote: authoritativeVote,
      );
      final redacted =
          json['ignored_post_placeholder'] == true ||
          (json['deleted_post_placeholder'] == true &&
              !json.containsKey('username'));
      result.add(
        TopicContentPost(
          post.withPlugins(
            post.plugins.withValue(
              postVotingPostKey,
              data.hasData ? data : null,
            ),
          ),
          disposition: redacted
              ? TopicContentDisposition.redacted
              : TopicContentDisposition.complete,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  Future<Map<String, dynamic>> _get(
    String siteUrl,
    String path,
    PluginRequestCredentials credentials,
    Map<String, String> query,
  ) => credentials.run(
    () => transport.pluginGetJson(
      siteUrl: siteUrl,
      path: query.isEmpty
          ? path
          : Uri.parse(path).replace(queryParameters: query).toString(),
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    ),
  );

  Future<Map<String, dynamic>> _write(
    String siteUrl,
    String path,
    PluginRequestCredentials credentials,
    String method,
    Map<String, Object?> body,
  ) {
    final key = credentials.apiKey;
    if (key == null) {
      throw const WriteException(WriteFailure.forbidden, notSent: true);
    }
    return credentials.run(
      () => transport.pluginWriteJson(
        siteUrl: siteUrl,
        path: path,
        method: method,
        apiKey: key,
        clientId: credentials.clientId,
        body: body,
      ),
    );
  }

  Future<void> _ack(
    String siteUrl,
    String path,
    PluginRequestCredentials credentials,
    String method,
    Map<String, Object?> body,
  ) async {
    final json = await _write(siteUrl, path, credentials, method, body);
    if (json['success'] == 'OK' || json['success'] == true) return;
    final errors = json['errors'];
    if (errors is List && errors.whereType<String>().isNotEmpty) {
      throw WriteException(
        WriteFailure.validation,
        errors: errors.whereType<String>().toList(),
      );
    }
    throw const FormatException('Invalid mutation acknowledgement.');
  }
}

int _id(int value, String name) {
  if (value <= 0) throw ArgumentError.value(value, name);
  return value;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map) throw const FormatException('Invalid JSON object.');
  return Map<String, dynamic>.from(value);
}

List<int> _ids(Object? value) {
  if (value is! List) throw const FormatException('Invalid stream.');
  final ids = <int>[];
  final seen = <int>{};
  for (final id in value) {
    if (id is! int || id <= 0 || !seen.add(id)) {
      throw const FormatException('Invalid stream identity.');
    }
    ids.add(id);
  }
  return List.unmodifiable(ids);
}
